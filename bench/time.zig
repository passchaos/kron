//! Fixed-offset RFC3339 formatting with a full-output hash. Reports standalone
//! conversion/cache cost, not logging producer or complete-file throughput.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    var report_bytes: [4096]u8 = undefined;
    var report = std.Io.File.stdout().writerStreaming(init.io, &report_bytes);
    const cases = [_][]const u8{ "same-second", "changing-second", "offset-change", "clock-rollback" };
    for (cases, 0..) |case, kind| {
        for (0..5) |repetition| {
            var expected_checksum: ?u64 = null;
            var expected_bytes: ?u64 = null;
            for ([_]bool{ false, true }) |cached| {
                var formatter = try kron.time.Formatter.init(.{});
                var output: [kron.time.rfc3339.max_length]u8 = undefined;
                var checksum: u64 = 0;
                var written: u64 = 0;
                var conversions: usize = 0;
                const iterations = 100000;
                const started = std.Io.Clock.awake.now(init.io).nanoseconds;
                for (0..iterations) |index| {
                    const delta: i64 = @intCast(index);
                    const timestamp: kron.time.Timestamp = .{ .nanoseconds = switch (kind) {
                        1 => 1793462400000000000 + delta * 1000000000,
                        3 => 1793462400000000000 - @mod(delta, 2000) * 1000000,
                        else => 1793462400000000000 + delta,
                    } };
                    const options: kron.time.FormatOptions = .{ .offset = try kron.time.UtcOffset.init(if (kind == 2 and index % 2 == 0) 480 else 0) };
                    formatter.options = options;
                    const result = if (cached) try formatter.format(timestamp, &output) else try kron.time.rfc3339.format(timestamp, options, &output);
                    checksum +%= std.hash.Wyhash.hash(index, result);
                    written += result.len;
                    std.mem.doNotOptimizeAway(result);
                }
                const elapsed = std.Io.Clock.awake.now(init.io).nanoseconds - started;
                conversions = if (cached) formatter.calendar_conversions else iterations;
                if (expected_checksum) |expected| {
                    if (checksum != expected or written != expected_bytes.?) return error.InconsistentOutput;
                } else {
                    expected_checksum = checksum;
                    expected_bytes = written;
                }
                try report.interface.print("{{\"case\":\"{s}\",\"repetition\":{d},\"cached\":{},\"iterations\":{d},\"elapsed_ns\":{d},\"ns_per_record\":{d},\"conversions\":{d},\"checksum\":{d},\"bytes\":{d}}}\n", .{
                    case,        repetition, cached,  iterations, elapsed, @as(f64, @floatFromInt(elapsed)) / iterations,
                    conversions, checksum,   written,
                });
            }
        }
    }
    try report.interface.flush();
}
