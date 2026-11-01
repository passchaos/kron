const std = @import("std");
const Event = @import("../core/event.zig").Event;
const codec = @import("../core/codec.zig");
pub const format = @import("format.zig");
pub const EncodeError = codec.WriteError;

/// Writes one self-contained binary archive frame. Codec owns validation and
/// both passes, so shape/size are checked once. No heap or complete-record
/// buffer is needed. Event backing data must remain stable for this call.
pub fn encode(event: Event, writer: *std.Io.Writer) EncodeError!void {
    try codec.writeFramed(event, writer, frameHeader);
}

fn frameHeader(length: u32, crc: u32) [format.header_size]u8 {
    return format.headerBytes(.{ .payload_len = length, .crc32 = crc });
}

test "binary archive frame preserves typed fields, templates and secret redaction" {
    const field = @import("../core/field.zig");
    const event: Event = .{
        .level = .info,
        .scope = "archive",
        .message = "request {d}: {s}",
        .message_template = true,
        .format_args = &.{ field.kv("", @as(u64, 42)), field.kv("", field.secret("secret-format-value")) },
        .fields = &.{ field.kv("limit", std.math.maxInt(u128)), field.kv("password", field.secret("secret-field-value")), field.kv("blob", field.bytes("\xff\x00")) },
        .timestamp_ns = -1,
        .session = 123,
        .sequence = 456,
        .channel = 7,
        .source = @src(),
    };
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(event, &writer);
    const frame = writer.buffered();
    const header = try format.validate(frame);
    try std.testing.expectEqual(@as(u32, @intCast(frame.len - format.header_size)), header.payload_len);
    const payload = frame[format.header_size..];
    try std.testing.expectEqual(header.crc32, format.frameCRC(payload));
    var reference: [2048]u8 = undefined;
    try std.testing.expectEqualSlices(u8, try codec.encode(event, &reference), payload);
    var scratch: [5]field.Field = undefined;
    const restored = try codec.decode(payload, &scratch);
    try std.testing.expect(restored.message_template);
    try std.testing.expectEqualStrings("request {d}: {s}", restored.message);
    try std.testing.expectEqual(@as(u128, 42), restored.format_args[0].value.unsigned);
    try std.testing.expectEqualStrings(field.redacted, restored.format_args[1].value.string);
    try std.testing.expectEqualStrings(field.redacted, restored.fields[1].value.string);
    try std.testing.expectEqual(std.math.maxInt(u128), restored.fields[0].value.unsigned);
    try std.testing.expectEqualStrings("\xff\x00", restored.fields[2].value.bytes);
    try std.testing.expect(std.mem.indexOf(u8, frame, "secret-format-value") == null);
    try std.testing.expect(std.mem.indexOf(u8, frame, "secret-field-value") == null);
    buffer[frame.len - 1] ^= 1;
    try std.testing.expect(header.crc32 != format.frameCRC(payload));
}

test "binary archive writes independent concatenated frames without a size limit" {
    const field = @import("../core/field.zig");
    const large = [_]u8{'x'} ** 8192;
    const event: Event = .{ .level = .info, .scope = "archive", .message = &large, .fields = &.{field.kv("ok", true)}, .timestamp_ns = 0 };
    var buffer: [20000]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(event, &writer);
    const first_len = writer.end;
    try encode(event, &writer);
    try std.testing.expectEqual(first_len * 2, writer.end);
    try std.testing.expectEqualSlices(u8, writer.buffered()[0..first_len], writer.buffered()[first_len..]);
    const header = try format.validate(writer.buffered());
    try std.testing.expectEqual(@as(usize, header.payload_len) + format.header_size, first_len);
    try std.testing.expectEqual(header.crc32, format.frameCRC(writer.buffered()[format.header_size..first_len]));
}

test "binary archive rejects invalid events before output and returns bounded writer failure" {
    const field = @import("../core/field.zig");
    const event: Event = .{ .level = .info, .scope = "", .message = "", .fields = &.{ field.kv("dup", 1), field.kv("dup", 2) }, .timestamp_ns = 0 };
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.DuplicateKey, encode(event, &writer));
    try std.testing.expectEqual(@as(usize, 0), writer.end);
    writer = std.Io.Writer.fixed(buffer[0..8]);
    try std.testing.expectError(error.WriteFailed, encode(.{ .level = .info, .scope = "", .message = "", .fields = &.{}, .timestamp_ns = 0 }, &writer));
}

test "binary archive validates nested values once and rejects all invalid trees before framing" {
    const field = @import("../core/field.zig");
    const event: Event = .{ .level = .info, .scope = "archive", .message = "done", .timestamp_ns = 0, .fields = &.{field.kv("array", field.array(&.{ field.fromAny(true), field.fromAny(field.group(&.{field.kv("secret", field.secret("raw"))})) }))} };
    var buffer: [4096]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);
    const before = field.TestingAudit.visited_values;
    try encode(event, &output);
    try std.testing.expectEqual(@as(usize, 4), field.TestingAudit.visited_values - before);
    const header = try format.validate(output.buffered());
    try std.testing.expectEqual(header.crc32, format.frameCRC(output.buffered()[format.header_size..]));

    var cycle: [1]field.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    var chain: [field.max_value_depth + 1]field.Value = undefined;
    for (&chain, 0..) |*node, i| node.* = if (i + 1 < chain.len) .{ .array = chain[i + 1 ..][0..1] } else .{ .group = &.{} };
    const leaves = [_]field.Value{.null_value} ** field.max_value_nodes;
    const failures = [_]struct { value: field.Value, failure: anyerror }{
        .{ .value = field.fromAny(field.array(&cycle)), .failure = error.CyclicValue },
        .{ .value = chain[0], .failure = error.ValueTooDeep },
        .{ .value = field.fromAny(field.array(&leaves)), .failure = error.TooManyValueNodes },
        .{ .value = field.fromAny(field.group(&.{ field.kv("dup", 1), field.kv("dup", 2) })), .failure = error.DuplicateKey },
    };
    for (failures) |case| {
        var invalid = event;
        invalid.fields = &.{field.kv("invalid", case.value)};
        output = std.Io.Writer.fixed(&buffer);
        try std.testing.expectError(case.failure, encode(invalid, &output));
        try std.testing.expectEqual(@as(usize, 0), output.end);
    }
    var arguments = event;
    arguments.fields = &.{};
    arguments.format_args = &.{ field.kv("", true), field.kv("", false) };
    output = std.Io.Writer.fixed(&buffer);
    try encode(arguments, &output);
    arguments.format_args = &.{field.kv("", field.group(&.{ field.kv("nested", 1), field.kv("nested", 2) }))};
    output = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.DuplicateKey, encode(arguments, &output));
    try std.testing.expectEqual(@as(usize, 0), output.end);
    arguments = event;
    arguments.fields = &.{field.kv("full", field.array(leaves[0 .. leaves.len - 1]))};
    arguments.format_args = &.{field.kv("", true)};
    output = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.TooManyValueNodes, encode(arguments, &output));
    try std.testing.expectEqual(@as(usize, 0), output.end);
}
