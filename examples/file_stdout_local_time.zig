//! One Logging owner writes JSON Lines to a file and readable text to stdout.
//! Both outputs inherit system local time and are flushed by shutdown().
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "file",
                .target = .{
                    .file = .{
                        .path = "kron-file-stdout-local-time.jsonl",
                        .backend = .portable,
                    },
                },
                .format = .json,
                .mode = .asynchronous,
                .timestamp = .{
                    .zone = .local,
                },
            },
            .{
                .name = "stdout",
                .target = .stdout,
                .format = .text,
                .mode = .asynchronous,
                .timestamp = .{
                    .zone = .local,
                },
            },
        },
    });
    defer logging.destroy();

    const log = logging.scoped("app");
    for (0..3) |request| {
        const id: u32 = @intCast(request);
        _ = try log.tryLogfAt(@src(), .info, "request {d} completed", .{id}, .{
            .request = id,
            .elapsed = kron.durationNs(1200),
        });
    }
    try logging.shutdown();
}
