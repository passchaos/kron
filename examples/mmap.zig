//! An independent Mmap file pipeline and a Memory stdout pipeline.
//! Reopening with the same paths/options automatically replays pending records.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "file",
                .queue = .{
                    .mmap = .{
                        .path = "kron-mmap.journal",
                        .capacity = 256,
                        .max_record_bytes = 8192,
                    },
                },
                .target = .{
                    .file = .{
                        .path = "kron-mmap.jsonl",
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
                .delivery = .best_effort,
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
        _ = try log.tryLogfAt(@src(), .info, "mmap request {d} completed", .{id}, .{
            .request = id,
            .elapsed = kron.durationNs(1200),
        });
    }
    // Confirm the required file and journal checkpoint before ordered cleanup.
    try logging.flushDurable();
    try logging.shutdown();
}
