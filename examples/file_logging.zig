const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "file",
                .target = .{
                    .file = .{
                        .path = "kron-service.jsonl",
                        .backend = .portable,
                    },
                },
                .mode = .asynchronous,
                .format = .json,
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
    const log = logging.scoped("http").withBorrowed(.{ .service = "example" });
    _ = try log.tryEmit(.info, "request completed", .{ .status = @as(u16, 200), .password = "private" });
    try logging.reloadFilter("info,http=debug");
    log.debug("cache hit", .{ .request_id = 42 });
    try logging.flush();
    try logging.shutdown();
}
