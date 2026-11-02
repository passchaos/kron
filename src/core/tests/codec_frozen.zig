//! Genuine pre-experiment writer bytes guard reader and encoder interoperability.
const std = @import("std");
const codec = @import("../codec.zig");
const field = @import("../field.zig");
const encoder = @import("../../encoder/root.zig");

test "frozen v4 writer fixtures preserve complete metadata integer range nested and deferred values" {
    const fixtures = .{
        @embedFile("fixtures/v4_scalar.bin"), @embedFile("fixtures/v4_wide.bin"),
        @embedFile("fixtures/v4_nested.bin"), @embedFile("fixtures/v4_deferred.bin"),
    };
    inline for (fixtures, 0..) |bytes, index| {
        try std.testing.expectEqual(@as(u16, 4), std.mem.readInt(u16, bytes[4..6], .little));
        var scratch: [codec.decode_scratch_fields]field.Field = undefined;
        const event = try codec.decode(bytes, &scratch);
        try std.testing.expectEqualStrings("v4.fixture", event.scope);
        try std.testing.expectEqual(@as(i64, -123), event.timestamp_ns);
        try std.testing.expectEqual(@as(u64, 9), event.session);
        try std.testing.expectEqual(@as(u64, 10), event.sequence);
        try std.testing.expectEqual(@as(u32, 3), event.channel);
        try std.testing.expectEqual(@as(u64, 1), event.route_mask);
        try std.testing.expectEqual(@as(u64, 2), event.config_generation);
        try std.testing.expectEqual(@as(u64, 17), event.route_fingerprint);
        try std.testing.expectEqual(@as(u64, 4), event.route_generation);
        try std.testing.expectEqualStrings("fixture", event.source.?.module);
        try std.testing.expectEqualStrings("fixture.zig", event.source.?.file);
        try std.testing.expectEqualStrings("frozen", event.source.?.fn_name);
        try std.testing.expectEqual(@as(u32, 42), event.source.?.line);
        try std.testing.expectEqual(@as(u32, 9), event.source.?.column);
        try std.testing.expectEqual([_]u8{0xab} ** 16, event.trace_id.?);
        try std.testing.expectEqual([_]u8{0xcd} ** 8, event.span_id.?);
        try std.testing.expectEqual(@as(u8, 1), event.trace_flags);
        if (index == 0 or index == 3) {
            try std.testing.expectEqual(@as(usize, 5), event.fields.len);
            try std.testing.expectEqualStrings("zero", event.fields[0].key);
            try std.testing.expectEqual(@as(u128, 0), event.fields[0].value.unsigned);
            try std.testing.expectEqual(@as(u128, 9007199254740991), event.fields[1].value.unsigned);
            try std.testing.expectEqual(@as(u128, std.math.maxInt(u64)), event.fields[2].value.unsigned);
            try std.testing.expectEqual(@as(i128, std.math.minInt(i64)), event.fields[3].value.signed);
            try std.testing.expectEqual(@as(i128, -7), event.fields[4].value.signed);
        } else if (index == 1) {
            try std.testing.expectEqual(@as(usize, 2), event.fields.len);
            try std.testing.expectEqual(std.math.maxInt(u128), event.fields[0].value.unsigned);
            try std.testing.expectEqual(std.math.minInt(i128), event.fields[1].value.signed);
        } else {
            try std.testing.expectEqual(@as(usize, 5), event.fields[0].value.group.len);
            const values = event.fields[1].value.array;
            try std.testing.expectEqual(@as(usize, 3), values.len);
            try std.testing.expectEqual(@as(u128, 42), values[0].unsigned);
            try std.testing.expectEqual(@as(i128, -7), values[1].signed);
            try std.testing.expectEqual(field.Value.null_value, values[2]);
        }
        try std.testing.expectEqual(index == 3, event.message_template);
        if (index == 3) {
            try std.testing.expectEqual(@as(usize, 2), event.format_args.len);
            try std.testing.expectEqual(@as(u128, 42), event.format_args[0].value.unsigned);
            try std.testing.expectEqual(@as(i128, -7), event.format_args[1].value.signed);
        }
        var encoded: [4096]u8 = undefined;
        try std.testing.expectEqualSlices(u8, bytes, try codec.encode(event, &encoded));
        var stream_bytes: [4096]u8 = undefined;
        var stream = std.Io.Writer.fixed(&stream_bytes);
        try codec.writeTo(event, &stream);
        try std.testing.expectEqualSlices(u8, bytes, stream.buffered());
        var output_bytes: [8192]u8 = undefined;
        var output = std.Io.Writer.fixed(&output_bytes);
        try encoder.encode(.json, event, &output);
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.buffered(), .{});
        defer parsed.deinit();
        try std.testing.expectEqualStrings(if (index == 3) "42 -7" else "frozen event", parsed.value.object.get("message").?.string);
        try std.testing.expectEqual(@as(i64, -123), parsed.value.object.get("timestamp_ns").?.integer);
    }
}
