//! Producer-local audit at the real public Runtime submission boundary.
const std = @import("std");
const kron = @import("kron");

test "prepared runtime values are validated before acceptance" {
    var bytes: [8192]u8 = undefined;
    var output = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 },
        .routes = &.{.{ .name = "audit", .sink = output.sink() }},
    });
    defer runtime.destroy();
    var event: kron.Event = .{ .level = .info, .scope = "audit", .message = "plain", .timestamp_ns = 0,
        .fields = &.{ kron.kv("nested", kron.fields.group(&.{ kron.kv("u", @as(u64, 42)), kron.kv("s", "value") })), kron.kv("flag", true) } };
    const binding = try runtime.prewarmSchema(event);
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    const admission = switch (runtime.begin(.info, "audit")) {
        .ready => |ready| ready,
        else => return error.UnexpectedAdmission,
    };
    var admitted = true;
    defer if (admitted) runtime.end();
    const before = kron.fields.TestingAudit.visited_values;
    try std.testing.expectEqual(kron.EmitResult.accepted, try runtime.submitWithSchema(admission, event, binding));
    const visits = kron.fields.TestingAudit.visited_values - before;
    runtime.end();
    admitted = false;
    try std.testing.expectEqual(@as(usize, 2), runtime.health().journal_pending);
    std.debug.print("prepared runtime submission:4 values, {d} visited nodes; record accepted and held behind reservation gap\n", .{visits});
    event.fields = &.{kron.kv("different", @as(u64, 1))};
    gap.abort();
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(u64, 1), runtime.health().written);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "nested") != null);
}
