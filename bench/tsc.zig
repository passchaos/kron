//! One-thread clock-provider comparison. UTC reads are compared separately
//! from complete logging and never silently relabeled as qualified TSC reads.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const tsc = try kron.TscClock.create(init.gpa, io, .{ .max_error_ppm = 20_000 });
    defer tsc.destroy();
    var output_bytes: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &output_bytes);
    const initial = tsc.stats();
    try output.interface.print("{{\"benchmark\":\"tsc_qualification\",\"status\":\"{s}\",\"cpuid_hz\":{d},\"calibrated_hz\":{d},\"error_ppm\":{d},\"aux\":{d}}}\n", .{
        @tagName(initial.status), initial.capability.frequency_hz, initial.calibrated_hz, initial.calibration_error_ppm, initial.expected_aux,
    });
    const calls: usize = 100_000;
    for (0..1000) |_| {
        std.mem.doNotOptimizeAway(kron.NativeClock.realNow(io));
        std.mem.doNotOptimizeAway(tsc.realNow(io));
    }
    var checksum: u64 = 0;
    const native_started = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..calls) |_| {
        const value = kron.NativeClock.realNow(io);
        std.mem.doNotOptimizeAway(value);
        checksum +%= @bitCast(value);
    }
    const native_ns = std.Io.Clock.awake.now(io).nanoseconds - native_started;
    const before = tsc.stats();
    const tsc_started = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..calls) |_| {
        const value = tsc.realNow(io);
        std.mem.doNotOptimizeAway(value);
        checksum +%= @bitCast(value);
    }
    const tsc_ns = std.Io.Clock.awake.now(io).nanoseconds - tsc_started;
    const after = tsc.stats();
    try output.interface.print("{{\"benchmark\":\"clock_reads\",\"calls\":{d},\"native_ns_per_call\":{d},\"tsc_ns_per_call\":{d},\"tsc_status\":\"{s}\",\"qualified_reads\":{d},\"fallback_reads\":{d},\"checksum\":{d}}}\n", .{
        calls,
        @as(f64, @floatFromInt(native_ns)) / calls,
        @as(f64, @floatFromInt(tsc_ns)) / calls,
        @tagName(after.status),
        after.tsc_reads - before.tsc_reads,
        after.fallbacks - before.fallbacks,
        checksum,
    });
    try output.interface.flush();
}
