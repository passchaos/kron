//! Independent size-only and time-only rolling file outputs.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "size",
                .target = .{ .rolling_file = .{
                    .path = "kron-rolling.jsonl",
                    .max_bytes = 1024,
                    .retention = 3,
                    .backend = .portable,
                } },
                .format = .json,
                .mode = .asynchronous,
            },
            .{
                .name = "time",
                .target = .{ .rolling_file = .{
                    .path = "kron-rolling-time.jsonl",
                    .rotation_interval_ns = 100 * std.time.ns_per_ms,
                    .retention = 3,
                    .backend = .portable,
                } },
                .format = .json,
                .mode = .asynchronous,
            },
            .{
                .name = "console",
                .target = .stderr,
                .filter = "warn",
                .delivery = .best_effort,
                .mode = .asynchronous,
            },
        },
    });
    defer logging.destroy();
    for (0..20) |sequence| {
        _ = try logging.scoped("app").tryEmit(.info, "rotating output", .{ .sequence = @as(u64, @intCast(sequence)) });
        try std.Io.sleep(init.io, .fromMilliseconds(25), .awake);
    }
    _ = try logging.scoped("app").tryEmit(.warn, "also visible on stderr", .{});
    try logging.flushOutputsDurable(&.{ "size", "time" });
    try logging.shutdown();
}
