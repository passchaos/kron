const std = @import("std");
const kron = @import("kron");

test "readable time keeps original timestamp precision and independent text JSON logfmt routes" {
    var formatter = try kron.time.Formatter.init(.{ .offset = try kron.time.UtcOffset.init(480) });
    const event: kron.Event = .{ .level = .info, .scope = "time", .message = "event", .fields = &.{}, .timestamp_ns = -1 };
    inline for (.{ kron.Format.text, kron.Format.json, kron.Format.logfmt }) |format| {
        var bytes: [2048]u8 = undefined;
        var writer = std.Io.Writer.fixed(&bytes);
        try kron.encoder.encodeWithTime(format, event, &formatter, &writer);
        try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "1970-01-01T07:59:59.999999999+08:00") != null);
        if (format == .json) {
            const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer.buffered(), .{});
            defer parsed.deinit();
            try std.testing.expectEqual(@as(i64, -1), parsed.value.object.get("timestamp_ns").?.integer);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), formatter.calendar_conversions);
    var bytes: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(error.WriteFailed, kron.encoder.encodeWithTime(.binary, event, &formatter, &writer));
    try std.testing.expectEqual(@as(usize, 0), writer.end);
    formatter.options.offset.minutes = 1440;
    try std.testing.expectError(error.WriteFailed, kron.encoder.encodeWithTime(.json, event, &formatter, &writer));
    try std.testing.expectEqual(@as(usize, 0), writer.end);
}

test "readable time runs through sync shared and SPSC memory mmap with owned hot configuration" {
    inline for (.{ "sync", "memory", "mmap", "spsc-memory", "spsc-mmap" }) |mode| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_bytes: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const directory = try tmp.dir.realPath(std.testing.io, &path_bytes);
        const journal_path = try std.fs.path.join(std.testing.allocator, &.{ path_bytes[0..directory], "time.journal" });
        defer std.testing.allocator.free(journal_path);
        var old_bytes: [4096]u8 = undefined;
        var new_bytes: [4096]u8 = undefined;
        var old = kron.MemorySink.initBuffer(&old_bytes);
        var next = kron.MemorySink.initBuffer(&new_bytes);
        var failed = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const sync = comptime std.mem.eql(u8, mode, "sync");
        const mmap = comptime std.mem.endsWith(u8, mode, "mmap");
        const spsc = comptime std.mem.startsWith(u8, mode, "spsc");
        const runtime = try kron.Runtime.create(failed.allocator(), std.testing.io, .{
            .submission = if (sync) .sync else if (spsc) .low_latency else .asynchronous,
            .journal = if (mmap) .{ .path = journal_path, .capacity = 8, .max_record_bytes = 1024 } else null,
            .memory_queue = if (!sync and !mmap) .{ .capacity = 8, .max_record_bytes = 1024 } else null,
            .max_thread_channels = if (spsc) 1 else 0,
            .thread_channel_capacity = 8,
            .clock = kron.Clock.zeroTimestamp(),
            .routes = &.{.{ .name = "file", .sink = old.sink(), .recovery_identity = "time-old", .timestamp = .{ .offset = try kron.time.UtcOffset.init(480) } }},
        });
        defer runtime.destroy();
        const log = if (spsc) try runtime.attachThread(.{ .scope = "time" }) else runtime.scoped("time");
        defer if (spsc) log.detach() catch {};
        var gap: ?@typeInfo(@TypeOf(runtime.journal.?.reserve())).error_union.payload = if (sync) null else if (spsc) try log.owner.producer_token.journal.reserveSingleProducer(log.owner.producer_token) else try runtime.journal.?.reserve();
        defer if (gap) |*reservation| reservation.abort();
        const accepted = runtime.health().accepted;
        const allocations = failed.allocations;
        failed.fail_index = failed.alloc_index;
        failed.resize_fail_index = failed.resize_index;
        for (0..3) |_| try std.testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "old", .{}));
        try std.testing.expectEqual(allocations, failed.allocations);
        failed.fail_index = std.math.maxInt(usize);
        failed.resize_fail_index = std.math.maxInt(usize);
        const before = runtime.currentConfiguration();
        const installed = try runtime.replaceConfiguration(&.{.{ .name = "file", .sink = next.sink(), .recovery_identity = "time-new", .timestamp = .{ .offset = try kron.time.UtcOffset.init(-300), .precision = .seconds } }}, .{});
        try std.testing.expect(before.fingerprint != installed.fingerprint);
        try std.testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "new", .{}));
        if (gap) |*reservation| reservation.abort();
        try runtime.flush(.written);
        try std.testing.expectEqual(@as(u64, 4), runtime.health().written);
        try std.testing.expectEqual(accepted + 4, runtime.health().accepted);
        try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
        try std.testing.expect(std.mem.indexOf(u8, next.written(), "1969-12-31T19:00:00-05:00") != null);
        try std.testing.expect(std.mem.indexOf(u8, old.written(), "1970-01-01T08:00:00.000000000+08:00") != null);
        try std.testing.expectEqual(@as(usize, 3), old.records);
        try std.testing.expectEqual(@as(usize, 1), next.records);
    }
}

test "time configuration rejects invalid settings and initialization failures clean up" {
    var bytes: [1024]u8 = undefined;
    var sink = kron.MemorySink.initBuffer(&bytes);
    try std.testing.expectError(error.InvalidTimestampFormat, kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .routes = &.{.{ .name = "out", .sink = sink.sink(), .format = .binary, .timestamp = .{} }},
    }));
    try std.testing.expectError(error.InvalidOffset, kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .routes = &.{.{ .name = "out", .sink = sink.sink(), .timestamp = .{ .offset = .{ .minutes = 1440 } } }},
    }));
    const Fixture = struct {
        fn create(allocator: std.mem.Allocator, output: kron.Sink) !void {
            const runtime = try kron.Runtime.create(allocator, std.testing.io, .{
                .routes = &.{.{ .name = "out", .sink = output, .timestamp = .{} }},
            });
            runtime.destroy();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Fixture.create, .{sink.sink()});
}

test "time recovery rejects changed offset precision and retains the original journal timestamp" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_bytes: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(std.testing.io, &path_bytes);
    const path = try std.fs.path.join(std.testing.allocator, &.{ path_bytes[0..count], "time.journal" });
    defer std.testing.allocator.free(path);
    var failed_bytes: [2048]u8 = undefined;
    var failed = kron.MemorySink.initBuffer(&failed_bytes);
    failed.fail_after_records = 0;
    const options: kron.time.FormatOptions = .{ .offset = try kron.time.UtcOffset.init(480) };
    {
        const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = .asynchronous,
            .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 },
            .clock = kron.Clock.zeroTimestamp(),
            .routes = &.{.{ .name = "out", .sink = failed.sink(), .recovery_identity = "same", .timestamp = options }},
        });
        defer runtime.destroy();
        _ = try runtime.scoped("time").tryEmit(.info, "recover original", .{});
        try std.testing.expectError(error.InjectedWriteFailure, runtime.flush(.written));
        try std.testing.expectEqual(@as(usize, 1), runtime.health().journal_pending);
    }
    var output_bytes: [2048]u8 = undefined;
    var output = kron.MemorySink.initBuffer(&output_bytes);
    const changed = [_]kron.time.FormatOptions{
        .{ .offset = try kron.time.UtcOffset.init(-300) },
        .{ .offset = options.offset, .precision = .seconds },
    };
    for (changed) |timestamp| try std.testing.expectError(error.RecoveryRouteMismatch, kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "out", .sink = output.sink(), .recovery_identity = "same", .timestamp = timestamp }},
    }));
    const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "out", .sink = output.sink(), .recovery_identity = "same", .timestamp = options }},
    });
    defer runtime.destroy();
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(usize, 1), output.records);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "1970-01-01T08:00:00.000000000+08:00") != null);
    try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
}

test "time fanout distinguishes same format with different offsets and numeric default" {
    var buffers: [3][2048]u8 = undefined;
    var sinks = [_]kron.MemorySink{
        kron.MemorySink.initBuffer(&buffers[0]), kron.MemorySink.initBuffer(&buffers[1]), kron.MemorySink.initBuffer(&buffers[2]),
    };
    const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .clock = kron.Clock.zeroTimestamp(),
        .routes = &.{
            .{ .name = "east", .sink = sinks[0].sink(), .timestamp = .{ .offset = try kron.time.UtcOffset.init(480) } },
            .{ .name = "west", .sink = sinks[1].sink(), .timestamp = .{ .offset = try kron.time.UtcOffset.init(-300) } },
            .{ .name = "numeric", .sink = sinks[2].sink() },
        },
    });
    defer runtime.destroy();
    _ = try runtime.scoped("time").tryEmit(.info, "fanout", .{});
    try runtime.flush(.written);
    try std.testing.expect(std.mem.indexOf(u8, sinks[0].written(), "1970-01-01T08:00:00") != null);
    try std.testing.expect(std.mem.indexOf(u8, sinks[1].written(), "1969-12-31T19:00:00") != null);
    try std.testing.expect(std.mem.indexOf(u8, sinks[2].written(), "\"timestamp\":") == null);
}
