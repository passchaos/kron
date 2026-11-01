const std = @import("std");
const Event = @import("../core/event.zig").Event;
const common = @import("common.zig");

/// String values are always quoted with text escaping. Attribute keys have an
/// attr. prefix and percent-encoded unsafe bytes, avoiding metadata collisions.
pub fn encode(event: Event, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try common.encode(.logfmt, event, writer);
}

test "logfmt golden protects metadata and escapes keys injectively" {
    const field = @import("../core/field.zig");
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(.{ .level = .info, .scope = "worker", .message = "x\n\"", .fields = &.{ field.kv("a b=", true), field.kv("a%20b", "\xff") }, .timestamp_ns = 0 }, &writer);
    try std.testing.expectEqualStrings("timestamp_ns=0 severity=info scope=\"worker\" message=\"x\\n\\\"\" session=0 channel=0 sequence=0 route_mask=0 config_generation=0 trace_flags=0 attr.a%20b%3d=true attr.a%2520b=\"\\xff\"\n", writer.buffered());
}

test "logfmt nested representation retains text scalar and malformed byte policies" {
    const field = @import("../core/field.zig");
    const items = [_]field.Value{ .{ .unsigned = std.math.maxInt(u128) }, .{ .float = std.math.nan(f64) }, .null_value, .{ .string = "\xff\n" } };
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(.{ .level = .info, .scope = "", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("data", field.array(&items))} }, &writer);
    const marker = "attr.data=";
    const start = std.mem.indexOf(u8, writer.buffered(), marker).? + marker.len;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, std.mem.trimEnd(u8, writer.buffered()[start..], "\n"), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("[340282366920938463463374607431768211455,\"NaN\",null,\"\\xff\\n\"]", parsed.value.string);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, writer.buffered(), "\n"));
}
