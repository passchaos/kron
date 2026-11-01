//! Run with the kron module. Keep std.log's static minimum at debug to let
//! Runtime.reloadFilter control every standard level during execution.
const std = @import("std");
const kron = @import("kron");
const LogBridge = kron.std_log.Bridge(kron.Runtime);

pub const std_options: std.Options = .{
    .logFn = LogBridge.logFn,
    .log_level = .debug,
};

pub fn main(init: std.process.Init) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    var sink = kron.WriterSink.init(&stderr.interface);
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .routes = &.{.{ .name = "stderr", .sink = sink.sink(), .format = .text }},
        .filter = "info",
    });
    defer runtime.destroy();
    try LogBridge.init(runtime);
    defer LogBridge.unbind();

    std.log.info("standard logging is bound to kron", .{});
    const http = std.log.scoped(.http);
    http.debug("hidden by runtime filter", .{});
    try runtime.reloadFilter("info,http=debug");
    http.debug("request {d} completed in {d} ns", .{ @as(u32, 42), @as(u64, 1200) });
    std.log.warn("standard formatters use the explicit producer buffer", .{});
    try runtime.flush(.written);
}
