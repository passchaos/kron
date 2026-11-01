//! Complete checked delivery windows behind an admitted reservation gap.
//! The callback records actual batch flushes; corruption is injected only
//! while every output record still belongs to the consumer.
const std = @import("std");
const Runtime = @import("../runtime.zig").Runtime;
const Journal = @import("../../journal/journal.zig").Journal;
const MemorySink = @import("../../sink/memory.zig").MemorySink;
const Sink = @import("../../sink/interface.zig").Sink;
const configurations = @import("../../config/routes.zig");
const fields = @import("../field.zig");

const WindowSink = struct {
    memory: MemorySink,
    journal: ?*Journal = null,
    first_flush_records: usize = 0,
    corrupt_after: ?usize = null,
    fail_flush: bool = false,
    fail_sync: bool = false,

    fn write(raw: *anyopaque, record: []const u8) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        try self.memory.writeRecord(record);
    }
    fn flush(raw: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        try self.memory.flush();
        if (self.memory.records == 0 or self.first_flush_records != 0) return;
        self.first_flush_records = self.memory.records;
        if (self.fail_flush) return error.InjectedFlushFailure;
        if (self.corrupt_after) |prefix| {
            // A smaller old window must fail before attempting to modify a
            // record whose consumer might later release it in another batch.
            if (self.first_flush_records != 255) return error.ExpectedFullWindow;
            const journal = self.journal.?;
            journal.mapping.bytes[4096 + (prefix + 1) * journal.stride + 64] ^= 1;
        }
    }
    fn sink(self: *@This()) Sink {
        return .{ .context = self, .vtable = &.{ .writeRecord = write, .flush = flush, .sync = sync }, .supports_durable = self.fail_sync, .recovery_identity = "coalesced-window-output" };
    }
    fn sync(raw: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        if (self.fail_sync) return error.InjectedSyncFailure;
        try self.memory.flush();
    }
};

test "coalesced service window flushes all 255 queued records before reclaim without allocation" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        inline for (.{ false, true }) |persistent| {
            inline for (.{ false, true }) |prepared| {
                var tmp = std.testing.tmpDir(.{});
                defer tmp.cleanup();
                var path_bytes: [160]u8 = undefined;
                const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/window.journal", .{tmp.sub_path});
                var bytes: [256 * 1024]u8 = undefined;
                var output: WindowSink = .{ .memory = MemorySink.initBuffer(&bytes) };
                var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
                const runtime = try Runtime.create(failing.allocator(), std.testing.io, .{
                    .submission = submission,
                    .memory_queue = if (persistent) null else .{ .capacity = 256, .max_record_bytes = 512, .schema_capacity = if (prepared) 2 else 0, .max_schema_bytes = 1024 },
                    .journal = if (persistent) .{ .path = path, .capacity = 256, .max_record_bytes = 512, .schema_capacity = if (prepared) 2 else 0, .max_schema_bytes = 1024 } else null,
                    .max_thread_channels = if (submission == .low_latency) 1 else 0,
                    .thread_channel_capacity = 256,
                    .consumer_batches_per_queue = 4,
                    .idle = .sleep,
                    .routes = &.{.{ .name = "output", .sink = output.sink() }},
                });
                defer runtime.destroy();
                const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "window" }) else runtime.scoped("window");
                defer if (submission == .low_latency) log.detach() catch {};
                const journal = if (submission == .low_latency) runtime.thread_registry.?.getJournal(0) else runtime.journal.?;
                const shape: @import("../event.zig").Event = .{ .level = .info, .scope = "window", .message = "queued", .timestamp_ns = 0, .fields = &.{fields.kv("index", @as(u64, 0))} };
                const ready = if (prepared) (if (submission == .low_latency)
                    try runtime.threadLoggerWithSchema(log, try runtime.prewarmThreadSchema(1, shape))
                else
                    try runtime.loggerWithSchema(try runtime.prewarmSchema(shape))) else log;
                output.journal = journal;
                var gap = if (submission == .low_latency) try journal.reserveSingleProducer(log.owner.producer_token) else try journal.reserve();
                defer gap.abort();
                failing.fail_index = failing.alloc_index;
                failing.resize_fail_index = failing.resize_index;
                for (0..255) |index| _ = try ready.tryEmit(.info, "queued", .{ .index = @as(u64, index) });
                gap.abort();
                try runtime.flush(.written);
                try std.testing.expectEqual(@as(usize, 255), output.first_flush_records);
                try std.testing.expectEqual(@as(u64, 255), runtime.health().written);
                try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
                try std.testing.expectEqual(@as(u64, 256), journal.writtenTarget());
                try std.testing.expect(!failing.has_induced_failure);
            }
        }
    }
}

test "coalesced checked window rejects later corruption before any earlier record reaches a sink" {
    var bytes: [256 * 1024]u8 = undefined;
    var memory = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 256, .max_record_bytes = 512 },
        .idle = .sleep,
        .routes = &.{.{ .name = "output", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    const journal = runtime.journal.?;
    var gap = try journal.reserve();
    defer gap.abort();
    for (0..255) |index| _ = try runtime.scoped("window").tryEmit(.info, "queued", .{ .index = @as(u64, index) });
    journal.mapping.bytes[4096 + 191 * journal.stride + 64] ^= 1;
    gap.abort();
    try std.testing.expectError(error.CorruptRecord, runtime.flush(.written));
    try std.testing.expectEqual(@as(usize, 0), memory.records);
    try std.testing.expectEqual(@as(u64, 0), runtime.health().written);
    try std.testing.expectEqual(@as(usize, 255), runtime.health().journal_pending);
    try std.testing.expectEqual(@as(u64, 1), journal.writtenTarget());
}

test "coalesced old and new routes keep all record pins when final flush or durable barrier fails" {
    inline for (.{ false, true }) |durable| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_bytes: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/barrier.journal", .{tmp.sub_path});
        var old_bytes: [256 * 1024]u8 = undefined;
        var new_bytes: [256 * 1024]u8 = undefined;
        var old: WindowSink = .{ .memory = MemorySink.initBuffer(&old_bytes) };
        var next: WindowSink = .{ .memory = MemorySink.initBuffer(&new_bytes), .fail_flush = !durable, .fail_sync = durable };
        const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = .asynchronous,
            .memory_queue = if (durable) null else .{ .capacity = 256, .max_record_bytes = 512 },
            .journal = if (durable) .{ .path = path, .capacity = 256, .max_record_bytes = 512 } else null,
            .configuration_slots = 2,
            .idle = .sleep,
            .routes = &.{.{ .name = "old", .sink = old.sink() }},
        });
        defer runtime.destroy();
        const journal = runtime.journal.?;
        var gap = try journal.reserve();
        defer gap.abort();
        const old_version = runtime.currentConfiguration();
        for (0..150) |index| _ = try runtime.scoped("window").tryEmit(.info, "old", .{ .index = @as(u64, index) });
        const new_version = try runtime.replaceConfiguration(&.{.{ .name = "new", .sink = next.sink(), .reclaim_after = if (durable) .durable else .written }}, .{});
        for (0..105) |index| _ = try runtime.scoped("window").tryEmit(.info, "new", .{ .index = @as(u64, index) });
        gap.abort();
        try std.testing.expectError(if (durable) error.InjectedSyncFailure else error.InjectedFlushFailure, runtime.flush(.written));
        try std.testing.expectEqual(@as(usize, 150), old.first_flush_records);
        try std.testing.expectEqual(@as(usize, 105), next.first_flush_records);
        try std.testing.expectEqual(@as(u64, 0), runtime.health().written);
        try std.testing.expectEqual(@as(usize, 255), runtime.health().journal_pending);
        const manager: *configurations.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
        const first = try manager.find(old_version.generation, old_version.fingerprint);
        defer first.release();
        const second = try manager.find(new_version.generation, new_version.fingerprint);
        defer second.release();
        try std.testing.expectEqual(@as(usize, 150), first.snapshot.pendingCount());
        try std.testing.expectEqual(@as(usize, 105), second.snapshot.pendingCount());
        try std.testing.expectEqual(@as(usize, 1), first.snapshot.readers.load(.seq_cst));
        try std.testing.expectEqual(@as(usize, 1), second.snapshot.readers.load(.seq_cst));
    }
}

test "coalesced flush failure retains every slot and pin of a retired configuration" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var bytes: [256 * 1024]u8 = undefined;
        var output: WindowSink = .{ .memory = MemorySink.initBuffer(&bytes), .fail_flush = true };
        const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 256, .max_record_bytes = 512 },
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 256,
            .configuration_slots = 2,
            .idle = .sleep,
            .routes = &.{.{ .name = "old", .sink = output.sink() }},
        });
        defer runtime.destroy();
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "window" }) else runtime.scoped("window");
        defer if (submission == .low_latency) log.detach() catch {};
        const journal = if (submission == .low_latency) runtime.thread_registry.?.getJournal(0) else runtime.journal.?;
        var gap = if (submission == .low_latency) try journal.reserveSingleProducer(log.owner.producer_token) else try journal.reserve();
        defer gap.abort();
        const old = runtime.currentConfiguration();
        for (0..255) |index| _ = try log.tryEmit(.info, "queued", .{ .index = @as(u64, index) });
        _ = try runtime.replaceConfiguration(&.{.{ .name = "new", .sink = output.sink() }}, .{});
        gap.abort();
        try std.testing.expectError(error.InjectedFlushFailure, runtime.flush(.written));
        try std.testing.expectEqual(@as(usize, 255), output.first_flush_records);
        try std.testing.expectEqual(@as(u64, 0), runtime.health().written);
        try std.testing.expectEqual(@as(usize, 255), runtime.health().journal_pending);
        try std.testing.expectEqual(@as(u64, 1), journal.writtenTarget());
        if (submission == .low_latency) try log.detach();
        const manager: *configurations.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
        {
            const view = try manager.find(old.generation, old.fingerprint);
            defer view.release();
            try std.testing.expectEqual(@as(usize, 255), view.snapshot.pendingCount());
        }
        try std.testing.expectEqual(@as(usize, 0), try runtime.collectConfigurations());
    }
}

test "coalesced late corruption acknowledges only its successful prefix and retains old configuration" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var bytes: [256 * 1024]u8 = undefined;
        var output: WindowSink = .{ .memory = MemorySink.initBuffer(&bytes), .corrupt_after = 190 };
        const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 256, .max_record_bytes = 512 },
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 256,
            .consumer_batches_per_queue = 4,
            .configuration_slots = 2,
            .idle = .sleep,
            .routes = &.{.{ .name = "old", .sink = output.sink() }},
        });
        defer runtime.destroy();
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "window" }) else runtime.scoped("window");
        defer if (submission == .low_latency) log.detach() catch {};
        const journal = if (submission == .low_latency) runtime.thread_registry.?.getJournal(0) else runtime.journal.?;
        output.journal = journal;
        var gap = if (submission == .low_latency) try journal.reserveSingleProducer(log.owner.producer_token) else try journal.reserve();
        defer gap.abort();
        const old = runtime.currentConfiguration();
        for (0..255) |index| _ = try log.tryEmit(.info, "queued", .{ .index = @as(u64, index) });
        _ = try runtime.replaceConfiguration(&.{.{ .name = "new", .sink = output.sink() }}, .{});
        gap.abort();
        try std.testing.expectError(error.CorruptRecord, runtime.flush(.written));
        try std.testing.expectEqual(@as(usize, 255), output.first_flush_records);
        try std.testing.expectEqual(@as(u64, 190), runtime.health().written);
        try std.testing.expectEqual(@as(usize, 65), runtime.health().journal_pending);
        try std.testing.expectEqual(@as(u64, 191), journal.writtenTarget());
        if (submission == .low_latency) try log.detach();
        const manager: *configurations.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
        {
            const view = try manager.find(old.generation, old.fingerprint);
            defer view.release();
            try std.testing.expectEqual(@as(usize, 65), view.snapshot.pendingCount());
        }
        try std.testing.expectEqual(@as(usize, 0), try runtime.collectConfigurations());
    }
}
