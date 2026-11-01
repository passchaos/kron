const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const file = try kron.FileSink.create(init.gpa, init.io, .{ .path = "kron-predicates.jsonl" });
    defer file.deinit();
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .low_latency,
        .journal = .{ .path = "kron-predicates.journal", .capacity = 32, .max_record_bytes = 4096 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 32,
        .predicate = "tenant == \"prod\"",
        .routes = &.{.{ .name = "errors", .sink = file.sink(), .predicate = "status >= 500 && path =~ \"^/api/(users|orders)$\"" }},
    });
    defer runtime.destroy();
    const log = try runtime.attachThread(.{ .scope = "http" });
    defer log.detach() catch {};
    if (try log.tryEmit(.info, "ignored success", .{ .tenant = "prod", .status = @as(u16, 200), .path = "/api/users" }) != .filtered) return error.FilterDidNotReject;
    if (try log.tryEmit(.info, "recorded error", .{ .tenant = "prod", .status = @as(u16, 503), .path = "/api/users" }) != .accepted) return error.FilterDidNotAccept;
    try runtime.flushUntil(.durable, kron.Deadline.after(init.io, 5 * std.time.ns_per_s));
    try runtime.shutdownUntil(kron.Deadline.after(init.io, 5 * std.time.ns_per_s));
}
