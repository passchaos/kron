const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .mode = .asynchronous,
        .output = .{ .multiple = &.{
            .{ .name = "file", .target = .{ .rolling_file = .{ .path = "kron-rolling.jsonl", .max_bytes = 1024, .retention = 3, .backend = .portable } }, .format = .json },
            .{ .name = "console", .target = .stderr, .format = .text, .filter = "warn", .delivery = .best_effort },
        } },
    });
    defer logging.destroy();
    for (0..20) |sequence| {
        _ = try logging.scoped("app").tryEmit(.info, "rotating output", .{ .sequence = @as(u64, @intCast(sequence)) });
    }
    _ = try logging.scoped("app").tryEmit(.warn, "also visible on stderr", .{});
    try logging.flushOutputsDurable(&.{"file"});
    try logging.shutdown();
}
