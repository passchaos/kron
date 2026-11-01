const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const tsc = try kron.TscClock.create(init.gpa, init.io, .{});
    defer tsc.destroy();
    var output_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const stats = tsc.stats();
    try stdout.interface.print("TSC status={s} frequency_hz={d} error_ppm={d} aux={d}\n", .{
        @tagName(stats.status), stats.calibrated_hz, stats.calibration_error_ppm, stats.expected_aux,
    });
    var sink = kron.WriterSink.init(&stdout.interface);
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .clock = tsc.clock(),
        .routes = &.{.{ .name = "stdout", .sink = sink.sink(), .format = .text }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("clock-example");
    log.info("qualified clock uses converted UTC nanoseconds; unqualified clock falls back", .{ .qualified = stats.status == .qualified });
    try runtime.flush(.written);
    try stdout.interface.print("TSC reads={d} fallbacks={d}\n", .{ tsc.stats().tsc_reads, tsc.stats().fallbacks });
    try stdout.interface.flush();
}
