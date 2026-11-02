const std = @import("std");
const codec = @import("../core/codec.zig");
const field = @import("../core/field.zig");
const Event = @import("../core/event.zig").Event;
const common = @import("common.zig");
const wire = @import("wire_json.zig");

test "fused scratch lifecycle: failed rendering and fallback permit complete decoder reuse" {
    const event: Event = .{ .level = .info, .scope = "scratch", .message = "value", .timestamp_ns = 0, .fields = &.{ field.kv("a", true), field.kv("b", false), field.kv("c", true) } };
    var payload_bytes: [512]u8 = undefined;
    const payload = try codec.encode(event, &payload_bytes);
    const header = try codec.readHeader(payload, codec.version);
    var parser: codec.WireInput = .{ .bytes = payload, .position = header.header_bytes };
    _ = try parser.blob();
    _ = try parser.blob();
    _ = try parser.blob();
    _ = try parser.value();
    const second_key = try parser.blob();
    const second_offset = @intFromPtr(second_key.ptr) - @intFromPtr(payload.ptr);
    var changed: [512]u8 = undefined;
    var output: [2048]u8 = undefined;
    var expected_bytes: [2048]u8 = undefined;
    var scratch: [5]field.Field = undefined;
    inline for (std.enums.values(wire.Format)) |format| {
        @memset(std.mem.sliceAsBytes(&scratch), 0xa5);
        const before = field.TestingAudit.compared_keys;
        const actual = try wire.render(format, payload, header, &output, &scratch, null);
        try std.testing.expectEqual(before + 3, field.TestingAudit.compared_keys);
        // Scratch is opaque until the full decoder initializes each Field.
        const decoded = try codec.decode(payload, &scratch);
        var expected = std.Io.Writer.fixed(&expected_bytes);
        try common.encodeWithTime(@field(common.RecordFormat, @tagName(format)), decoded, null, &expected);
        try std.testing.expectEqualSlices(u8, expected.buffered(), actual);

        @memcpy(changed[0..payload.len], payload);
        changed[second_offset] = 'a';
        @memset(std.mem.sliceAsBytes(&scratch), 0xa5);
        const duplicate_before = field.TestingAudit.compared_keys;
        try std.testing.expectError(error.DuplicateKey, wire.render(format, changed[0..payload.len], header, &output, &scratch, null));
        try std.testing.expectEqual(duplicate_before + 1, field.TestingAudit.compared_keys);
        const after_duplicate = try codec.decode(payload, &scratch);
        var reencoded: [512]u8 = undefined;
        try std.testing.expectEqualSlices(u8, payload, try codec.encode(after_duplicate, &reencoded));

        @memcpy(changed[0..payload.len], payload);
        changed[payload.len - 1] = 2;
        @memset(std.mem.sliceAsBytes(&scratch), 0xa5);
        const invalid_before = field.TestingAudit.compared_keys;
        try std.testing.expectError(error.InvalidValue, wire.render(format, changed[0..payload.len], header, &output, &scratch, null));
        try std.testing.expectEqual(invalid_before + 3, field.TestingAudit.compared_keys);
        const after_invalid = try codec.decode(payload, &scratch);
        try std.testing.expectEqualSlices(u8, payload, try codec.encode(after_invalid, &reencoded));
    }
    var deferred = event;
    deferred.message_template = true;
    const fallback = try codec.encode(deferred, &changed);
    const fallback_header = try codec.readHeader(fallback, codec.version);
    @memset(std.mem.sliceAsBytes(&scratch), 0xa5);
    try std.testing.expectError(error.Fallback, wire.render(.json, fallback, fallback_header, &output, &scratch, null));
    try std.testing.expect(std.mem.allEqual(u8, std.mem.sliceAsBytes(&scratch), 0xa5));
    const decoded = try codec.decode(fallback, &scratch);
    try std.testing.expect(decoded.message_template and decoded.fields[0].value.boolean);
}

test "fused scratch lifecycle: top level reservation retains exact nested descriptor budget" {
    var names: [64][2]u8 = undefined;
    var entries: [64]field.Field = undefined;
    for (&entries, &names, 0..) |*entry, *name, index| {
        name.* = .{ @intCast(index), 'k' };
        entry.* = field.kv(name, true);
    }
    entries[63].value = field.fromAny(field.group(&.{field.kv("inner", field.array(&.{ .null_value, .{ .boolean = true } }))}));
    const event: Event = .{ .level = .info, .scope = "arena", .message = "nested", .timestamp_ns = 0, .fields = &entries };
    var payload_bytes: [2048]u8 = undefined;
    const payload = try codec.encode(event, &payload_bytes);
    const header = try codec.readHeader(payload, codec.version);
    const nested_bytes = @sizeOf(field.Field) + 2 * @sizeOf(field.Value);
    const needed = 64 + (nested_bytes + @sizeOf(field.Field) - 1) / @sizeOf(field.Field);
    var backing: [needed + 1]field.Field = undefined;
    var decoded_scratch: [needed]field.Field = undefined;
    var output: [8192]u8 = undefined;
    var expected_bytes: [8192]u8 = undefined;
    const decoded = try codec.decode(payload, &decoded_scratch);
    inline for (std.enums.values(wire.Format)) |format| {
        @memset(std.mem.sliceAsBytes(&backing), 0xa5);
        const before = field.TestingAudit.compared_keys;
        const actual = try wire.render(format, payload, header, &output, backing[0..needed], null);
        try std.testing.expectEqual(before + 64 * 63 / 2, field.TestingAudit.compared_keys);
        var expected = std.Io.Writer.fixed(&expected_bytes);
        try common.encodeWithTime(@field(common.RecordFormat, @tagName(format)), decoded, null, &expected);
        try std.testing.expectEqualSlices(u8, expected.buffered(), actual);
        try std.testing.expect(std.mem.allEqual(u8, std.mem.sliceAsBytes(backing[needed..]), 0xa5));
        for ([_]usize{ 63, 64, needed - 1 }) |capacity| {
            @memset(std.mem.sliceAsBytes(&backing), 0xa5);
            try std.testing.expectError(error.TooManyFields, wire.render(format, payload, header, &output, backing[0..capacity], null));
            try std.testing.expect(std.mem.allEqual(u8, std.mem.sliceAsBytes(backing[capacity..]), 0xa5));
        }
    }
}
