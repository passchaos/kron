const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "stdout",
                .target = .stdout,
                .mode = .asynchronous,
                .format = .json,
                .timestamp = .{
                    .zone = .local,
                },
            },
        },
    });
    defer logging.destroy();
    for (0..3) |request| {
        _ = try logging.scoped("app").tryEmit(.info, "system local time", .{ .request = @as(u32, @intCast(request)) });
    }
    try logging.shutdown();
}
