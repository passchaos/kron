const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const output = try kron.FileSink.create(init.gpa, init.io, .{ .path = "kron-prepared.jsonl" });
    defer output.deinit();
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .low_latency,
        .journal = .{
            .path = "kron-prepared.journal",
            .capacity = 64,
            .max_record_bytes = 4096,
            .schema_capacity = 16,
            .max_schema_bytes = 4096,
        },
        .max_thread_channels = 1,
        .thread_channel_capacity = 64,
        .routes = &.{.{ .name = "file", .sink = output.sink() }},
    });
    defer runtime.destroy();
    const attached = try runtime.attachThread(.{ .scope = "worker" });
    const template: kron.Event = .{
        .level = .info,
        .scope = "worker",
        .message = "request {d} completed",
        .message_template = true,
        .format_args = &.{kron.kv("0", @as(u64, 1))},
        .fields = &.{kron.kv("status", @as(u16, 200))},
        .timestamp_ns = 0,
    };
    const binding = try runtime.prewarmThreadSchema(@intCast(attached.owner.control_index + 1), template);
    const log = try runtime.threadLoggerWithSchema(attached, binding);
    defer log.detach() catch {};
    for (0..100) |request| {
        _ = try log.tryLogf(.info, "request {d} completed", .{@as(u64, @intCast(request))}, .{ .status = @as(u16, 200) });
    }
    try runtime.flushUntil(.durable, kron.Deadline.after(init.io, 5 * std.time.ns_per_s));
    try runtime.shutdownUntil(kron.Deadline.after(init.io, 5 * std.time.ns_per_s));
}
