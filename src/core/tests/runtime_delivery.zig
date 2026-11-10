//! Real worker batches: call counts are observed on the callback thread, while
//! reservation gaps establish a complete mixed/one-version batch beforehand.
const std = @import("std");
const Runtime = @import("../runtime.zig").Runtime;
const MemorySink = @import("../../sink/memory.zig").MemorySink;
const Sink = @import("../../sink/interface.zig").Sink;
const routes = @import("../../config/routes.zig");
const batch_module = @import("../delivery_batch.zig");
const field = @import("../field.zig");
const Event = @import("../event.zig").Event;
const Clock = @import("../../platform/clock.zig").Clock;

fn renderCacheRun(allocator: std.mem.Allocator, cache: bool) ![]u8 {
    var bytes: [16 * 1024]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 },
        .routes = &.{.{ .name = "out", .sink = sink.sink(), .format = .json }},
        .clock = Clock.zeroTimestamp(),
        .render_cache = cache,
        .render_cache_record_bytes = if (cache) 512 else 0,
    });
    defer runtime.destroy();
    runtime.session = 42;
    const schema_binding = try runtime.prewarmSchema(.{ .level = .info, .scope = "cache", .message = "schema", .timestamp_ns = 0, .fields = &.{ field.kv("n", @as(u64, 7)), field.kv("nested", field.group(&.{field.kv("u", @as(u64, 8))})) } });
    for (0..4) |index| {
        _ = try runtime.scoped("cache").tryEmit(.info, "inline", .{ .n = @as(u64, index), .s = "x" });
        const event: Event = .{ .level = .info, .scope = "cache", .message = "schema", .timestamp_ns = 0, .fields = &.{ field.kv("n", @as(u64, index + 7)), field.kv("nested", field.group(&.{field.kv("u", @as(u64, index + 8))})) } };
        const admission = switch (runtime.begin(.info, "cache")) {
            .ready => |ready| ready,
            else => return error.UnexpectedAdmission,
        };
        var admitted = true;
        defer if (admitted) runtime.end();
        _ = try runtime.submitWithSchema(admission, event, schema_binding);
        runtime.end();
        admitted = false;
    }
    try runtime.flush(.written);
    try runtime.shutdown(.drain);
    return allocator.dupe(u8, sink.written());
}

test "render cache output matches deferred render for inline and schema" {
    const cached = try renderCacheRun(std.testing.allocator, true);
    defer std.testing.allocator.free(cached);
    const deferred = try renderCacheRun(std.testing.allocator, false);
    defer std.testing.allocator.free(deferred);
    try std.testing.expectEqualStrings(deferred, cached);
}

test "render cache output matches deferred render for spsc" {
    const cached = try renderCacheSpscRun(std.testing.allocator, true);
    defer std.testing.allocator.free(cached);
    const deferred = try renderCacheSpscRun(std.testing.allocator, false);
    defer std.testing.allocator.free(deferred);
    try std.testing.expectEqualStrings(deferred, cached);
}

fn renderCacheSpscRun(allocator: std.mem.Allocator, cache: bool) ![]u8 {
    var bytes: [16 * 1024]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(allocator, std.testing.io, .{
        .submission = .low_latency,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 8,
        .routes = &.{.{ .name = "out", .sink = sink.sink(), .format = .json }},
        .clock = Clock.zeroTimestamp(),
        .render_cache = cache,
        .render_cache_record_bytes = if (cache) 512 else 0,
    });
    defer runtime.destroy();
    runtime.session = 42;
    const log = try runtime.attachThread(.{ .scope = "cache" });
    for (0..4) |index| {
        _ = try log.tryEmit(.info, "inline", .{ .n = @as(u64, index), .s = "x" });
    }
    try runtime.flush(.written);
    log.detach() catch {};
    try runtime.shutdown(.drain);
    return allocator.dupe(u8, sink.written());
}

test "text queue output matches deferred render for inline and schema" {
    const text = try textFormatRun(std.testing.allocator, true);
    defer std.testing.allocator.free(text);
    const deferred = try textFormatRun(std.testing.allocator, false);
    defer std.testing.allocator.free(deferred);
    try std.testing.expectEqualStrings(deferred, text);
}

fn textFormatRun(allocator: std.mem.Allocator, text_format: bool) ![]u8 {
    var bytes: [16 * 1024]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{
            .capacity = 8,
            .max_record_bytes = 1024,
            .schema_capacity = 2,
            .max_schema_bytes = 1024,
            .verify_crc = !text_format,
            .text_format = text_format,
        },
        .routes = &.{.{ .name = "out", .sink = sink.sink(), .format = .json }},
        .clock = Clock.zeroTimestamp(),
    });
    defer runtime.destroy();
    runtime.session = 42;
    const schema_binding = try runtime.prewarmSchema(.{ .level = .info, .scope = "cache", .message = "schema", .timestamp_ns = 0, .fields = &.{ field.kv("n", @as(u64, 7)), field.kv("nested", field.group(&.{field.kv("u", @as(u64, 8))})) } });
    for (0..4) |index| {
        _ = try runtime.scoped("cache").tryEmit(.info, "inline", .{ .n = @as(u64, index), .s = "x" });
        const event: Event = .{ .level = .info, .scope = "cache", .message = "schema", .timestamp_ns = 0, .fields = &.{ field.kv("n", @as(u64, index + 7)), field.kv("nested", field.group(&.{field.kv("u", @as(u64, index + 8))})) } };
        const admission = switch (runtime.begin(.info, "cache")) {
            .ready => |ready| ready,
            else => return error.UnexpectedAdmission,
        };
        var admitted = true;
        defer if (admitted) runtime.end();
        _ = try runtime.submitWithSchema(admission, event, schema_binding);
        runtime.end();
        admitted = false;
    }
    try runtime.flush(.written);
    try runtime.shutdown(.drain);
    return allocator.dupe(u8, sink.written());
}

fn textFormatSpscMmapRun(allocator: std.mem.Allocator, path: []const u8, text_format: bool) ![]u8 {
    var bytes: [16 * 1024]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(allocator, std.testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024, .recover = false, .verify_crc = !text_format, .text_format = text_format },
        .max_thread_channels = 1,
        .thread_channel_capacity = 8,
        .routes = &.{.{ .name = "out", .sink = sink.sink(), .format = .json, .recovery_identity = "spsc-mmap-text" }},
        .clock = Clock.zeroTimestamp(),
    });
    defer runtime.destroy();
    runtime.session = 42;
    const log = try runtime.attachThread(.{ .scope = "cache" });
    for (0..4) |index| {
        _ = try log.tryEmit(.info, "inline", .{ .n = @as(u64, index), .s = "x" });
    }
    try runtime.flush(.written);
    log.detach() catch {};
    try runtime.shutdown(.drain);
    return allocator.dupe(u8, sink.written());
}

test "text queue spsc mmap matches durable deferred render" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var text_path: [128]u8 = undefined;
    var durable_path: [128]u8 = undefined;
    const text = try std.fmt.bufPrint(&text_path, ".zig-cache/tmp/{s}/text-spsc.journal", .{tmp.sub_path});
    const durable = try std.fmt.bufPrint(&durable_path, ".zig-cache/tmp/{s}/durable-spsc.journal", .{tmp.sub_path});
    const text_output = try textFormatSpscMmapRun(std.testing.allocator, text, true);
    defer std.testing.allocator.free(text_output);
    const durable_output = try textFormatSpscMmapRun(std.testing.allocator, durable, false);
    defer std.testing.allocator.free(durable_output);
    try std.testing.expectEqualStrings(durable_output, text_output);
}

test "text queue output matches deferred render for spsc" {
    const text = try textFormatSpscRun(std.testing.allocator, true);
    defer std.testing.allocator.free(text);
    const deferred = try textFormatSpscRun(std.testing.allocator, false);
    defer std.testing.allocator.free(deferred);
    try std.testing.expectEqualStrings(deferred, text);
}

fn textFormatSpscRun(allocator: std.mem.Allocator, text_format: bool) ![]u8 {
    var bytes: [16 * 1024]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(allocator, std.testing.io, .{
        .submission = .low_latency,
        .memory_queue = .{
            .capacity = 8,
            .max_record_bytes = 1024,
            .schema_capacity = 2,
            .max_schema_bytes = 1024,
            .verify_crc = !text_format,
            .text_format = text_format,
        },
        .max_thread_channels = 1,
        .thread_channel_capacity = 8,
        .routes = &.{.{ .name = "out", .sink = sink.sink(), .format = .json }},
        .clock = Clock.zeroTimestamp(),
    });
    defer runtime.destroy();
    runtime.session = 42;
    const log = try runtime.attachThread(.{ .scope = "cache" });
    for (0..4) |index| {
        _ = try log.tryEmit(.info, "inline", .{ .n = @as(u64, index), .s = "x" });
    }
    try runtime.flush(.written);
    log.detach() catch {};
    try runtime.shutdown(.drain);
    return allocator.dupe(u8, sink.written());
}

test "render cache does not hide journal recovery" {
    if (!@import("../../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/render-cache-recovery.journal", .{tmp.sub_path});
    var storage: [8192]u8 = undefined;
    var memory = MemorySink.initBuffer(&storage);
    {
        const first = try Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = .asynchronous,
            .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 },
            .routes = &.{.{ .name = "out", .sink = memory.sink(), .recovery_identity = "render-cache-recovery" }},
            .render_cache = true,
            .render_cache_record_bytes = 512,
            .clock = Clock.zeroTimestamp(),
        });
        defer first.destroy();
        first.session = 42;
        memory.fail_after_records = 0;
        _ = try first.scoped("cache").tryEmit(.info, "recover", .{ .n = @as(u64, 1) });
        try std.testing.expectError(error.InjectedWriteFailure, first.flush(.written));
    }
    memory.fail_after_records = null;
    const second = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "out", .sink = memory.sink(), .recovery_identity = "render-cache-recovery" }},
        .render_cache = true,
        .render_cache_record_bytes = 512,
        .clock = Clock.zeroTimestamp(),
    });
    defer second.destroy();
    second.session = 42;
    try second.flush(.written);
    try std.testing.expectEqual(@as(usize, 1), memory.records);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "recover") != null);
}

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
        for (0..31) |index| try std.testing.expectEqual(@import("../logger.zig").EmitResult.accepted, try log.tryEmit(.info, "same batch", .{ .id = @as(u64, index) }));
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

test "Memory and Mmap consumer quantum bounds shared and SPSC peer service" {
    const FairSink = struct {
        memory: MemorySink,
        entered: std.Io.Event = .unset,
        proceed: std.Io.Event = .unset,
        peer_at: ?usize = null,
        peer_channel: u32,
        sequences: [3]u64 = @splat(0),

        fn number(bytes: []const u8, key: []const u8) !u64 {
            const start = (std.mem.find(u8, bytes, key) orelse return error.MissingMetadata) + key.len;
            var end = start;
            while (end < bytes.len and std.ascii.isDigit(bytes[end])) : (end += 1) {}
            return std.fmt.parseInt(u64, bytes[start..end], 10);
        }
        fn write(raw: *anyopaque, bytes: []const u8) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const index = self.memory.records;
            if (index == 0) {
                self.entered.set(std.testing.io);
                self.proceed.waitUncancelable(std.testing.io);
            }
            const channel = try number(bytes, "\"channel\":");
            if (channel > 2) return error.InvalidChannel;
            const sequence = try number(bytes, "\"sequence\":");
            if (sequence != self.sequences[channel] + 1) return error.OutOfOrder;
            self.sequences[channel] = sequence;
            if (channel == self.peer_channel and self.peer_at == null) self.peer_at = index;
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
    inline for (.{ false, true }) |persistent| {
        inline for (.{ false, true }) |shared_peer| {
            inline for (.{ 1, 2, 3, 4 }) |quantum| {
                var temporary = std.testing.tmpDir(.{});
                defer temporary.cleanup();
                var path_buffer: [192]u8 = undefined;
                const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/fairness.journal", .{temporary.sub_path});
                var bytes: [128 * 1024]u8 = undefined;
                var output: FairSink = .{ .memory = MemorySink.initBuffer(&bytes), .peer_channel = if (shared_peer) 0 else 2 };
                var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
                const runtime = try Runtime.create(failing.allocator(), std.testing.io, .{
                    .submission = .low_latency,
                    .memory_queue = if (persistent) null else .{ .capacity = 256, .max_record_bytes = 1024 },
                    .journal = if (persistent) .{ .path = path, .capacity = 256, .max_record_bytes = 1024, .recover = false } else null,
                    .max_thread_channels = if (shared_peer) 1 else 2,
                    .thread_channel_capacity = 256,
                    .routes = &.{.{ .name = "observed", .sink = output.sink(), .recovery_identity = "fairness-memory-output" }},
                    .idle = .sleep,
                    .consumer_batches_per_queue = quantum,
                });
                defer runtime.destroy();
                const busy = try runtime.attachThread(.{ .scope = "busy" });
                defer busy.detach() catch {};
                const peer = if (comptime shared_peer) runtime.scoped("shared.peer") else try runtime.attachThread(.{ .scope = "peer" });
                defer if (comptime !shared_peer) peer.detach() catch {};
                // Every failure after starting delivery must unblock the worker before
                // detach/destroy. The first callback freezes an actual one-record batch.
                defer output.proceed.set(std.testing.io);
                _ = try busy.tryEmit(.info, "first", .{});
                const deadline = std.Io.Timeout{ .duration = .{ .clock = .awake, .raw = .fromSeconds(5) } };
                try output.entered.waitTimeout(std.testing.io, deadline);
                failing.fail_index = failing.alloc_index;
                failing.resize_fail_index = failing.resize_index;
                for (0..160) |index| _ = try busy.tryEmit(.info, "backlog", .{ .index = index });
                _ = try peer.tryEmit(.info, "peer", .{});
                output.proceed.set(std.testing.io);
                try runtime.flush(.written);
                try std.testing.expectEqual(@as(usize, 162), output.memory.records);
                // The first batch has one record; subsequent full batches
                // have at most 64. Check all allowed service quanta without
                // asserting an operating-system wall-clock scheduling bound.
                const expected_peer = @min(161, 1 + (quantum - 1) * 64);
                try std.testing.expectEqual(@as(?usize, expected_peer), output.peer_at);
                try std.testing.expectEqualSlices(u64, if (shared_peer) &.{ 1, 161, 0 } else &.{ 0, 161, 1 }, &output.sequences);
                try std.testing.expectEqual(@as(u64, 162), runtime.health().written);
                try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
                try std.testing.expect(!failing.has_induced_failure);
            }
        }
    }
}

test "consumer quantum rejects unbounded or zero budgets before allocation" {
    var bytes: [1024]u8 = undefined;
    var memory = MemorySink.initBuffer(&bytes);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    for ([_]usize{ 0, 5, std.math.maxInt(usize) }) |quantum| {
        try std.testing.expectError(error.InvalidOptions, Runtime.create(failing.allocator(), std.testing.io, .{
            .routes = &.{.{ .name = "output", .sink = memory.sink() }},
            .consumer_batches_per_queue = quantum,
        }));
    }
    try std.testing.expect(!failing.has_induced_failure);
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
        journal: ?*@import("../../journal/journal.zig").Journal = null,
        corrupt: bool = true,
        releases: usize = 0,

        fn release(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.releases += 1;
        }

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
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var bytes: [16 * 1024]u8 = undefined;
        var output: CorruptOnFlush = .{ .memory = MemorySink.initBuffer(&bytes) };
        const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 8, .max_record_bytes = 1024 },
            .routes = &.{.{ .name = "file", .sink = output.sink(), .release = .{ .context = &output, .release = CorruptOnFlush.release } }},
            .configuration_slots = 2,
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 8,
            .idle = .sleep,
        });
        var live = true;
        defer if (live) runtime.destroy();
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "prefix" }) else runtime.scoped("prefix");
        defer if (live and submission == .low_latency) log.detach() catch {};
        const journal = if (submission == .low_latency) runtime.thread_registry.?.getJournal(0) else runtime.journal.?;
        output.journal = journal;
        var gap = if (submission == .low_latency) try journal.reserveSingleProducer(log.owner.producer_token) else try journal.reserve();
        defer gap.abort();
        const configuration = runtime.currentConfiguration();
        for (0..3) |index| _ = try log.tryEmit(.info, "written payload", .{ .index = index });
        // Retire the old version before delivery; a successful prefix must drop
        // only its own pins while the two damaged/unreclaimed records keep it live.
        _ = try runtime.replaceConfiguration(&.{.{ .name = "new", .sink = output.sink() }}, .{});
        gap.abort();
        try std.testing.expectError(error.CorruptRecord, runtime.flush(.written));
        try std.testing.expectEqual(@as(usize, 3), output.memory.records);
        try std.testing.expectEqual(@as(u64, 3), runtime.health().accepted);
        try std.testing.expectEqual(@as(u64, 1), runtime.health().written);
        try std.testing.expectEqual(@as(usize, 2), runtime.health().journal_pending);
        try std.testing.expectEqual(@as(u64, 2), journal.writtenTarget());
        try std.testing.expectError(error.CorruptRecord, journal.peekChecked());
        if (submission == .low_latency) try log.detach();
        const manager: *routes.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
        {
            const view = try manager.find(configuration.generation, configuration.fingerprint);
            defer view.release();
            try std.testing.expectEqual(@as(usize, 2), view.snapshot.pendingCount());
            try std.testing.expectEqual(@as(usize, 1), view.snapshot.readers.load(.seq_cst));
        }
        // Drop the inspecting View before collection: only the two record
        // pins now protect the retired target and its ownership callback.
        try std.testing.expectEqual(@as(usize, 0), try runtime.collectConfigurations());
        try std.testing.expectEqual(@as(usize, 0), output.releases);
        runtime.destroy();
        live = false;
        try std.testing.expectEqual(@as(usize, 1), output.releases);
    }
}
