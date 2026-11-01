//! JSON exposes @src()'s Zig module, file, function, line and column.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "file",
                .target = .{
                    .file = .{
                        .path = "kron-source-location.jsonl",
                        .backend = .portable,
                    },
                },
                .mode = .asynchronous,
                .format = .json,
                .timestamp = .{
                    .zone = .local,
                },
            },
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

    const log = logging.scoped("http.server");
    _ = try log.tryEmitAt(@src(), .info, "server started", .{ .port = @as(u16, 8080) });
    for (0..2) |request| try reportRequest(logging, @intCast(request));
    try logging.shutdown();
}

fn reportRequest(logging: *kron.Logging, request: u32) !void {
    const log = logging.scoped("http.server");
    // Place @src() at the call whose location should appear in the record.
    _ = try log.tryLogfAt(@src(), .info, "request {d} completed", .{request}, .{
        .request = request,
        .status = @as(u16, 200),
    });
}
