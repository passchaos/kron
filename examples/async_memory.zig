const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "stdout",
                .target = .stdout,
                .mode = .asynchronous,
                .redaction = &.{
                    .{
                        .key = "password",
                        .action = .mask,
                    },
                },
            },
        },
    });
    defer logging.destroy();
    _ = try logging.scoped("worker").tryEmit(.info, "ordinary async memory queue", .{ .answer = @as(u32, 42), .password = "private" });
    try logging.flush();
    try logging.shutdown();
}
