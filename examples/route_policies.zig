//! Independent route modes, queues, overflow, sampling and redaction.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "file",
                .target = .{
                    .file = .{
                        .path = "kron-route-policies.jsonl",
                        .backend = .portable,
                    },
                },
                .sampling = .none,
                .redaction = &.{
                    .{
                        .key = "password",
                        .action = .drop,
                    },
                    .{
                        .key = "access_token",
                        .action = .mask,
                    },
                },
                .mode = .asynchronous,
                .overflow = .block,
                .format = .json,
                .timestamp = .{
                    .zone = .local,
                },
                .filter = "info",
                .max_encoded_record_bytes = 4096,
            },
            .{
                .name = "stdout",
                .target = .stdout,
                .format = .text,
                .max_encoded_record_bytes = 2048,
                .mode = .asynchronous,
                .overflow = .drop_newest,
                .queue = .{
                    .memory = .{
                        .capacity = 64,
                        .max_record_bytes = 2048,
                    },
                },
                .timestamp = .{
                    .zone = .local,
                },
                .filter = "info",
                .sampling = .{
                    .every = 2,
                },
                .redaction = &.{
                    .{
                        .key = "password",
                        .action = .mask,
                    },
                    .{
                        .key = "access_token",
                        .action = .mask,
                    },
                },
            },
        },
    });
    defer logging.destroy();
    {
        const log = logging.scoped("http");
        for (0..4) |request| {
            _ = try log.tryLogfAt(@src(), .info, "request {d} completed", .{@as(u32, @intCast(request))}, .{
                .request = @as(u32, @intCast(request)),
                .password = "example-password",
                .access_token = "example-token",
            });
        }
    }
    try logging.shutdown();
}
