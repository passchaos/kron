//! Run with the kron module. Keep std.log's static minimum at debug to let
//! Runtime.reloadFilter control every standard level during execution.
const std = @import("std");
const kron = @import("kron");
const LogBridge = kron.Logging.std_log;

pub const std_options: std.Options = .{
    .logFn = LogBridge.logFn,
    .log_level = .debug,
};

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{});
    defer logging.destroy();
    {
        try logging.bindStdLog();
        defer logging.unbindStdLog();
        std.log.info("standard logging is bound to kron", .{});
        const http = std.log.scoped(.http);
        http.debug("hidden by runtime filter", .{});
        try logging.reloadFilter("info,http=debug");
        http.debug("request {d} completed in {d} ns", .{ @as(u32, 42), @as(u64, 1200) });
        std.log.warn("standard formatters use the explicit producer buffer", .{});
    }
    try logging.shutdown();
}
