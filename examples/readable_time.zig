const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const file = try kron.FileSink.create(init.gpa, init.io, .{ .path = "kron-readable-time.jsonl" });
    defer file.deinit();
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 64, .max_record_bytes = 1024 },
        .routes = &.{.{
            .name = "file",
            .sink = file.sink(),
            .format = .json,
            .timestamp = .{ .offset = try kron.time.UtcOffset.init(480), .precision = .nanoseconds },
        }},
    });
    defer runtime.destroy();
    try std.testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("time").tryEmit(.info, "readable wall clock", .{}));
    try runtime.flush(.written);
    try runtime.shutdown(.drain);
}
