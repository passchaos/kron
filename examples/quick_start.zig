const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{});
    defer logging.destroy();
    const log = logging.scoped("app");
    log.info("started", .{ .version = "1.0" });
    _ = try log.tryLogf(.warn, "request {d} completed", .{@as(u64, 42)}, .{ .elapsed = kron.durationNs(1200) });
    try logging.flush();
    try logging.shutdown();
}
