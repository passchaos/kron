//! Real worker batches: call counts are observed on the callback thread, while
//! reservation gaps establish a complete mixed/one-version batch beforehand.
const std = @import("std");
const Runtime = @import("runtime.zig").Runtime;
const MemorySink = @import("../sink/memory.zig").MemorySink;
const Sink = @import("../sink/interface.zig").Sink;
const routes = @import("../config/routes.zig");
const batch_module = @import("delivery_batch.zig");

const ObservedSink = struct {
    memory: MemorySink,
    find_calls: [64]usize = undefined,

    fn write(raw: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        const index = self.memory.records;
        if (index >= self.find_calls.len) return error.TooManyObservedRecords;
        self.find_calls[index] = routes.TestingAudit.find_calls;
        try self.memory.writeRecord(bytes);
    }
    fn flush(raw: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        try self.memory.flush();
    }
    fn sink(self: *@This()) Sink {
        return .{ .context = self, .vtable = &.{ .writeRecord = write, .flush = flush, .sync = flush } };
    }
};

test "real shared and SPSC batches perform one configuration lookup for 31 records" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var bytes: [32 * 1024]u8 = undefined;
        var output: ObservedSink = .{ .memory = MemorySink.initBuffer(&bytes) };
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const runtime = try Runtime.create(failing.allocator(), std.testing.io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 64, .max_record_bytes = 1024 },
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 64,
            .routes = &.{.{ .name = "observed", .sink = output.sink() }},
            .idle = .sleep,
        });
        defer runtime.destroy();
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "batch" }) else runtime.scoped("batch");
        defer if (submission == .low_latency) log.detach() catch {};
        const journal = if (submission == .low_latency) runtime.thread_registry.?.getJournal(0) else runtime.journal.?;
        var gap = if (submission == .low_latency) try journal.reserveSingleProducer(log.owner.producer_token) else try journal.reserve();
        defer gap.abort();
        failing.fail_index = failing.alloc_index;
        failing.resize_fail_index = failing.resize_index;
        for (0..31) |index| try std.testing.expectEqual(@import("logger.zig").EmitResult.accepted, try log.tryEmit(.info, "same batch", .{ .id = @as(u64, index) }));
        try std.testing.expectEqual(@as(usize, 32), journal.pending());
        const updates = batch_module.TestingAudit.written_updates.load(.monotonic);
        gap.abort();
        try runtime.flush(.written);
        try std.testing.expectEqual(@as(usize, 31), output.memory.records);
        // All records were ready before removing the gap, and fit one checked
        // batch. View lookup happens once before the first callback, then zero
        // additional lookups occur before the last callback.
        try std.testing.expectEqual(output.find_calls[0], output.find_calls[30]);
        try std.testing.expect(output.find_calls[0] != 0);
        try std.testing.expect(!failing.has_induced_failure);
        try std.testing.expectEqual(@as(u64, 31), runtime.health().written);
        try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
        try std.testing.expectEqual(@as(usize, 1), batch_module.TestingAudit.written_updates.load(.monotonic) - updates);
    }
}

test "mixed version batch releases its views on sink failure but keeps record pins and leases" {
    const Lease = struct {
        memory: MemorySink,
        releases: usize = 0,
        fn release(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.releases += 1;
        }
        fn route(self: *@This()) routes.RouteOptions {
            return .{ .name = "old", .sink = self.memory.sink(), .release = .{ .context = self, .release = release } };
        }
    };
    var old_bytes: [16 * 1024]u8 = undefined;
    var new_bytes: [16 * 1024]u8 = undefined;
    var old: Lease = .{ .memory = MemorySink.initBuffer(&old_bytes) };
    var next = MemorySink.initBuffer(&new_bytes);
    next.fail_after_records = 0;
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 16, .max_record_bytes = 1024 },
        .routes = &.{old.route()},
        .configuration_slots = 2,
        .idle = .sleep,
    });
    var live = true;
    defer if (live) runtime.destroy();
    const old_version = runtime.currentConfiguration();
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    for (0..3) |_| _ = try runtime.scoped("mixed").tryEmit(.info, "old", .{});
    const new_version = try runtime.replaceConfiguration(&.{.{ .name = "next", .sink = next.sink() }}, .{});
    for (0..3) |_| _ = try runtime.scoped("mixed").tryEmit(.info, "new", .{});
    gap.abort();
    try std.testing.expectError(error.InjectedWriteFailure, runtime.flush(.written));
    try std.testing.expectEqual(@as(usize, 3), old.memory.records);
    try std.testing.expectEqual(@as(u64, 0), runtime.health().written);
    try std.testing.expectEqual(@as(usize, 6), runtime.health().journal_pending);
    const manager: *routes.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
    {
        const old_view = try manager.find(old_version.generation, old_version.fingerprint);
        defer old_view.release();
        const next_view = try manager.find(new_version.generation, new_version.fingerprint);
        defer next_view.release();
        // These newly acquired views are the sole remaining readers; the failed
        // worker batch must release all of its own readers during error unwinding.
        try std.testing.expectEqual(@as(usize, 1), old_view.snapshot.readers.load(.seq_cst));
        try std.testing.expectEqual(@as(usize, 1), next_view.snapshot.readers.load(.seq_cst));
        try std.testing.expectEqual(@as(usize, 3), old_view.snapshot.pendingCount());
        try std.testing.expectEqual(@as(usize, 3), next_view.snapshot.pendingCount());
    }
    try std.testing.expectEqual(@as(usize, 0), try runtime.collectConfigurations());
    try std.testing.expectEqual(@as(usize, 0), old.releases);
    runtime.destroy();
    live = false;
    try std.testing.expectEqual(@as(usize, 1), old.releases);
}

test "batched written counts retain the exact acknowledged prefix after late reclaim corruption" {
    const CorruptOnFlush = struct {
        memory: MemorySink,
        journal: ?*@import("../journal/journal.zig").Journal = null,
        corrupt: bool = true,

        fn write(raw: *anyopaque, bytes: []const u8) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try self.memory.writeRecord(bytes);
        }
        fn flush(raw: *anyopaque) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try self.memory.flush();
            if (self.corrupt and self.memory.records == 3) {
                self.corrupt = false;
                // All three payloads passed the initial checked peek and were
                // encoded/written before this callback. Damage sequence 3 so
                // sequence 2 reclaims successfully and the next reclaim fails.
                const journal = self.journal.?;
                journal.mapping.bytes[4096 + 2 * journal.stride + 64] ^= 1;
            }
        }
        fn sink(self: *@This()) Sink {
            return .{ .context = self, .vtable = &.{ .writeRecord = write, .flush = flush, .sync = flush } };
        }
    };
    var bytes: [16 * 1024]u8 = undefined;
    var output: CorruptOnFlush = .{ .memory = MemorySink.initBuffer(&bytes) };
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "file", .sink = output.sink() }},
        .idle = .sleep,
    });
    defer runtime.destroy();
    output.journal = runtime.journal;
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    for (0..3) |index| _ = try runtime.scoped("prefix").tryEmit(.info, "written payload", .{ .index = index });
    gap.abort();
    try std.testing.expectError(error.CorruptRecord, runtime.flush(.written));
    try std.testing.expectEqual(@as(usize, 3), output.memory.records);
    try std.testing.expectEqual(@as(u64, 3), runtime.health().accepted);
    try std.testing.expectEqual(@as(u64, 1), runtime.health().written);
    try std.testing.expectEqual(@as(usize, 2), runtime.health().journal_pending);
    try std.testing.expectEqual(@as(u64, 2), runtime.journal.?.writtenTarget());
    try std.testing.expectError(error.CorruptRecord, runtime.journal.?.peekChecked());
    const configuration = runtime.currentConfiguration();
    const manager: *routes.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
    const view = try manager.find(configuration.generation, configuration.fingerprint);
    defer view.release();
    try std.testing.expectEqual(@as(usize, 2), view.snapshot.pendingCount());
    try std.testing.expectEqual(@as(usize, 1), view.snapshot.readers.load(.seq_cst));
}
