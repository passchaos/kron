//! Standalone process: the driver selects TZ before any native time call.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedMode;
    const mode = args[1];
    if (std.mem.eql(u8, mode, "historic")) {
        var cache = try kron.time.Formatter.initWithIo(init.io, .{ .zone = .local });
        var bytes: [kron.time.rfc3339.max_length]u8 = undefined;
        _ = try cache.format(.{ .nanoseconds = -5_364_662_400_000_000_000 }, &bytes); // 1800
        return error.ExpectedNonMinuteOffset;
    }
    const fail = std.mem.eql(u8, mode, "fail");
    const recover = std.mem.eql(u8, mode, "recover");
    const mapped = fail or recover or std.mem.endsWith(u8, mode, "mmap");
    const attached = std.mem.startsWith(u8, mode, "spsc");
    const sync = std.mem.eql(u8, mode, "sync");
    var bytes: [16384]u8 = undefined;
    var sink = kron.MemorySink.initBuffer(&bytes);
    if (fail) sink.fail_after_records = 0;
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = if (sync) .sync else if (attached) .low_latency else .asynchronous,
        .memory_queue = if (!sync and !mapped) .{ .capacity = 64, .max_record_bytes = 1024 } else null,
        .journal = if (mapped) .{ .path = "oracle.journal", .capacity = 64, .max_record_bytes = 1024 } else null,
        .max_thread_channels = if (attached) 1 else 0,
        .thread_channel_capacity = 64,
        .routes = &.{.{ .name = "local", .sink = sink.sink(), .recovery_identity = "oracle", .timestamp = .{ .zone = .local } }},
    });
    defer runtime.destroy();
    if (!recover) {
        const samples = [_]i64{
            -1,                        0,
            1_700_000_000_123_456_789, 1_700_000_000_123_456_790,
            1_710_053_999_999_999_999, 1_710_054_000_000_000_000,
            1_730_613_599_999_999_999, 1_730_613_600_000_000_000,
            1_728_144_000_000_000_000, 1_728_143_999_999_999_999,
            2_200_000_000_123_456_789, 1_700_000_000_000_000_001,
        };
        if (attached) {
            const log = try runtime.attachThread(.{ .scope = "oracle" });
            defer log.detach() catch {};
            for (samples, 0..) |timestamp, index| {
                const admission = log.owner.begin(.info, "oracle").ready;
                defer log.owner.end();
                _ = try log.owner.submit(admission, .{ .level = .info, .scope = "oracle", .message = "local", .timestamp_ns = timestamp, .fields = &.{kron.kv("id", @as(u32, @intCast(index)))} });
            }
        } else for (samples, 0..) |timestamp, index| {
            const admission = runtime.begin(.info, "oracle").ready;
            defer runtime.end();
            _ = try runtime.submit(admission, .{ .level = .info, .scope = "oracle", .message = "local", .timestamp_ns = timestamp, .fields = &.{kron.kv("id", @as(u32, @intCast(index)))} });
        }
    }
    if (fail) {
        runtime.shutdown(.drain) catch |err| {
            if (err != error.InjectedWriteFailure) return err;
            if (runtime.health().journal_pending != 12) return error.PendingMismatch;
            return;
        };
        return error.ExpectedWriteFailure;
    }
    try runtime.shutdown(.drain);
    var output_bytes: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_bytes);
    try output.interface.writeAll(sink.written());
    try output.interface.flush();
}
