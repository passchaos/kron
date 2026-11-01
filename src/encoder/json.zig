const std = @import("std");
const Event = @import("../core/event.zig").Event;
const common = @import("common.zig");

/// JSON Lines. Core metadata is separate from attributes. Integers outside
/// ±(2^53-1) are decimal strings, nonfinite floats are null, bytes are hex:...
/// strings, and malformed UTF-8 values become U+FFFD. Malformed property names
/// use a reversible $bytes: hex spelling to preserve key uniqueness.
pub fn encode(event: Event, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try common.encode(.json, event, writer);
}

test "JSON golden keeps metadata separate from attributes" {
    const fields = @import("../core/field.zig");
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(.{ .level = .info, .scope = "http", .message = "done\n", .fields = &.{ fields.kv("severity", "user"), fields.kv("ok", true) }, .timestamp_ns = 12 }, &writer);
    try std.testing.expectEqualStrings("{\"timestamp_ns\":12,\"severity\":\"info\",\"scope\":\"http\",\"message\":\"done\\n\",\"session\":0,\"channel\":0,\"sequence\":0,\"route_mask\":0,\"config_generation\":0,\"trace_flags\":0,\"attributes\":{\"severity\":\"user\",\"ok\":true}}\n", writer.buffered());
}

test "JSON malformed UTF-8, NaN/Inf, integer boundaries and bytes remain parseable" {
    const field = @import("../core/field.zig");
    const attributes = [_]field.Field{
        field.kv("\xffkey", "a\xff\xed\xa0\x80"),
        field.kv("nan", std.math.nan(f64)),
        field.kv("inf", std.math.inf(f64)),
        field.kv("ninf", -std.math.inf(f64)),
        field.kv("small", @as(u64, 9007199254740991)),
        field.kv("big", @as(u64, 9007199254740992)),
        field.kv("min", std.math.minInt(i128)),
        field.kv("max", std.math.maxInt(u128)),
        field.kv("blob", field.bytes("\x00\xff")),
    };
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(.{ .level = .warn, .scope = "\xff", .message = "\n", .fields = &attributes, .timestamp_ns = std.math.maxInt(i64), .source = @src(), .trace_id = @splat(0xaa), .span_id = @splat(0xbb) }, &writer);
    const output = writer.buffered();
    try std.testing.expect(std.unicode.utf8ValidateSlice(output));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, output, "\n"));
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();
    const attrs = parsed.value.object.get("attributes").?.object;
    try std.testing.expect(attrs.get("nan").? == .null);
    try std.testing.expect(attrs.get("inf").? == .null);
    try std.testing.expect(attrs.get("ninf").? == .null);
    try std.testing.expectEqual(@as(i64, 9007199254740991), attrs.get("small").?.integer);
    try std.testing.expectEqualStrings("9007199254740992", attrs.get("big").?.string);
    try std.testing.expectEqualStrings("-170141183460469231731687303715884105728", attrs.get("min").?.string);
    try std.testing.expectEqualStrings("340282366920938463463374607431768211455", attrs.get("max").?.string);
    try std.testing.expectEqualStrings("hex:00ff", attrs.get("blob").?.string);
    try std.testing.expectEqualStrings("a\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd", attrs.get("$bytes:ff6b6579").?.string);
}

test "invalid UTF-8 keys remain distinct from each other and literal hex spellings" {
    const field = @import("../core/field.zig");
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(.{ .level = .info, .scope = "", .message = "", .fields = &.{ field.kv("\xff", 1), field.kv("\xfe", 2), field.kv("$bytes:ff", 3), field.kv("\xef\xbf\xbd", 4) }, .timestamp_ns = 0 }, &writer);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    const attrs = parsed.value.object.get("attributes").?.object;
    try std.testing.expectEqual(@as(usize, 4), attrs.count());
    try std.testing.expectEqual(@as(i64, 1), attrs.get("$bytes:ff").?.integer);
    try std.testing.expectEqual(@as(i64, 2), attrs.get("$bytes:fe").?.integer);
    try std.testing.expectEqual(@as(i64, 3), attrs.get("$bytes:2462797465733a6666").?.integer);
    try std.testing.expectEqual(@as(i64, 4), attrs.get("\xef\xbf\xbd").?.integer);
}

test "deferred messages roundtrip typed arguments then render and escape at encoding" {
    const field = @import("../core/field.zig");
    const codec = @import("../core/codec.zig");
    var dynamic = [_]u8{ 'x', '\n', '"', 0xff };
    const event: Event = .{
        .level = .info,
        .scope = "format",
        .message = "request {d}: {s} {s}{s}",
        .message_template = true,
        .format_args = &.{ field.kv("", @as(u64, 42)), field.kv("", &dynamic), field.kv("", "\xe9"), field.kv("", "\x9b\xaa") },
        .fields = &.{field.kv("result", true)},
        .timestamp_ns = 0,
    };
    var payload_buffer: [1024]u8 = undefined;
    const payload = try codec.encode(event, &payload_buffer);
    @memset(&dynamic, 'z');
    var scratch: [5]field.Field = undefined;
    const recovered = try codec.decode(payload, &scratch);
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(recovered, &writer);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("request 42: x\n\"\xef\xbf\xbd 雪", parsed.value.object.get("message").?.string);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("attributes").?.object.count());
}

test "finite float extremes and subnormal values produce valid JSON" {
    const field = @import("../core/field.zig");
    const finite_values = [_]f64{ 0, -0.0, 1.25, -1.25, std.math.floatMax(f64), std.math.floatMin(f64), @bitCast(@as(u64, 1)) };
    for (finite_values) |number| {
        var buffer: [2048]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try encode(.{ .level = .info, .scope = "", .message = "", .fields = &.{field.kv("number", number)}, .timestamp_ns = 0 }, &writer);
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer.buffered(), .{});
        defer parsed.deinit();
        const value = parsed.value.object.get("attributes").?.object.get("number").?;
        const decoded: f64 = switch (value) {
            .float => |v| v,
            .integer => |v| @floatFromInt(v),
            // The JSON parser preserves very large integer-shaped decimal
            // spellings instead of prematurely rounding them to an i64.
            .number_string => |v| try std.fmt.parseFloat(f64, v),
            else => return error.TestUnexpectedResult,
        };
        try std.testing.expectEqual(number, decoded);
    }
}

test "nested JSON and deferred arguments survive descriptor key and scalar source overwrites" {
    const field = @import("../core/field.zig");
    const codec = @import("../core/codec.zig");
    var key = "name".*;
    var name = "alice\n".*;
    var members = [_]field.Field{
        field.kv(&key, &name),
        field.kv("empty", field.group(&.{})),
        field.kv("secret", field.secret("never-persist-nested-secret")),
        field.kv("\xff", "malformed-key"),
    };
    var items = [_]field.Value{
        .null_value,
        field.fromAny(std.math.maxInt(u128)),
        field.fromAny(std.math.nan(f64)),
        field.fromAny(field.bytes("\x00\xff")),
        field.fromAny(field.group(&members)),
        field.fromAny(field.array(&.{})),
    };
    const event: Event = .{
        .level = .info,
        .scope = "nested",
        .message = "{any}",
        .message_template = true,
        .format_args = &.{field.kv("", field.group(&members))},
        .fields = &.{field.kv("nested", field.array(&items))},
        .timestamp_ns = 0,
    };
    var payload_buffer: [4096]u8 = undefined;
    const payload = try codec.encode(event, &payload_buffer);
    @memset(&key, 'x');
    @memset(&name, 'z');
    for (&members) |*member| member.* = field.kv("overwritten", null);
    for (&items) |*item| item.* = .null_value;
    var scratch: [codec.decode_scratch_fields]field.Field = undefined;
    const recovered = try codec.decode(payload, &scratch);
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(recovered, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "never-persist-nested-secret") == null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, writer.buffered(), "\n"));
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    const nested = parsed.value.object.get("attributes").?.object.get("nested").?.array.items;
    try std.testing.expect(nested[0] == .null);
    try std.testing.expectEqualStrings("340282366920938463463374607431768211455", nested[1].string);
    try std.testing.expect(nested[2] == .null);
    try std.testing.expectEqualStrings("hex:00ff", nested[3].string);
    try std.testing.expectEqualStrings("alice\n", nested[4].object.get("name").?.string);
    try std.testing.expectEqual(@as(usize, 0), nested[4].object.get("empty").?.object.count());
    try std.testing.expectEqualStrings(field.redacted, nested[4].object.get("secret").?.string);
    try std.testing.expectEqualStrings("malformed-key", nested[4].object.get("$bytes:ff").?.string);
    try std.testing.expectEqual(@as(usize, 0), nested[5].array.items.len);
    const message = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, parsed.value.object.get("message").?.string, .{});
    defer message.deinit();
    try std.testing.expectEqualStrings("alice\n", message.value.object.get("name").?.string);
}
