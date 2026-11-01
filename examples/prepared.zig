const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .output = .{ .file = .{ .path = "kron-prepared.jsonl", .backend = .portable } },
        .format = .json,
        .mode = .spsc,
        .max_threads = 1,
        .queue = .{ .mmap = .{
            .path = "kron-prepared.journal",
            .capacity = 64,
            .max_record_bytes = 4096,
            .schema_capacity = 16,
            .max_schema_bytes = 4096,
        } },
    });
    defer logging.destroy();
    const template: kron.Event = .{
        .level = .info,
        .scope = "worker",
        .message = "request {d} completed",
        .message_template = true,
        .format_args = &.{kron.kv("0", @as(u64, 1))},
        .fields = &.{kron.kv("status", @as(u16, 200))},
        .timestamp_ns = 0,
    };
    {
        const log = try logging.attachPreparedThread(template);
        defer log.detach() catch {};
        for (0..100) |request| {
            _ = try log.tryLogf(.info, "request {d} completed", .{@as(u64, @intCast(request))}, .{ .status = @as(u16, 200) });
        }
    }
    try logging.flushDurable();
    try logging.shutdown();
}
