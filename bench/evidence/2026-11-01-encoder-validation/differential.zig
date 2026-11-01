//! Independent public-API comparison against the frozen pre-change module.
const std = @import("std");
const before = @import("before");
const after = @import("after");

fn Corpus(comptime K: type) type {
    return struct {
        const values = [_]K.Value{
            .null_value,
            .{ .boolean = true },
            .{ .signed = std.math.minInt(i128) },
            .{ .unsigned = std.math.maxInt(u128) },
            .{ .float = std.math.nan(f64) },
            .{ .string = "雪\n\"\xff\xed\xa0\x80" },
            .{ .bytes = "\x00\xff" },
            .{ .duration_ns = std.math.minInt(i64) },
            .{ .timestamp_ns = std.math.maxInt(i64) },
            .{ .array = &.{} },
            .{ .group = &.{K.kv("inside", true)} },
        };
        const attributes = [_]K.Field{
            K.kv("values", K.array(&values)),
            K.kv("\xff", 1),
            K.kv("\xfe", 2),
            K.kv("$bytes:ff", 3),
            K.kv("secret", K.secret("original-secret")),
            K.kv("float-max", std.math.floatMax(f64)),
            K.kv("float-small", @as(f64, @bitCast(@as(u64, 1)))),
            K.kv("negative-zero", @as(f64, -0.0)),
            K.kv("negative-infinity", -std.math.inf(f64)),
        };
        const arguments = [_]K.Field{
            K.kv("", @as(u64, 42)),
            K.kv("", "\xe9"),
            K.kv("", "\x9b\xaa"),
            K.kv("", K.group(&attributes)),
        };

        fn event(variant: usize) K.Event {
            return .{
                .level = .warn,
                .scope = "scope\n\xff",
                .message = if (variant == 2) "id {d}: {s}{s} {any}" else "plain\n\xff\xe2\x80\xa8",
                .message_template = variant == 2,
                .format_args = if (variant == 2 or variant == 3) &arguments else &.{},
                .fields = if (variant == 0) &.{} else &attributes,
                .timestamp_ns = std.math.minInt(i64),
                .session = std.math.maxInt(u64),
                .channel = std.math.maxInt(u32),
                .sequence = std.math.maxInt(u64),
                .route_mask = std.math.maxInt(u64),
                .config_generation = std.math.maxInt(u64),
                .trace_flags = 1,
                .trace_id = @splat(0xaa),
                .span_id = @splat(0xbb),
                .source = .{ .module = "fixture", .file = "fixture\xff.zig", .fn_name = "encode", .line = 123, .column = 45 },
            };
        }
    };
}

test "encoder differential preserves every byte and every short-buffer failure" {
    var checks: usize = 0;
    inline for (.{ "text", "json", "logfmt" }) |format| {
        for (0..4) |variant| {
            var old_bytes: [16384]u8 = undefined;
            var new_bytes: [16384]u8 = undefined;
            var old_output = std.Io.Writer.fixed(&old_bytes);
            var new_output = std.Io.Writer.fixed(&new_bytes);
            try before.encoder.encode(@field(before.Format, format), Corpus(before).event(variant), &old_output);
            try after.encoder.encode(@field(after.Format, format), Corpus(after).event(variant), &new_output);
            try std.testing.expectEqualStrings(old_output.buffered(), new_output.buffered());
            const length = old_output.end;
            for (0..length) |capacity| {
                var old_short = std.Io.Writer.fixed(old_bytes[0..capacity]);
                var new_short = std.Io.Writer.fixed(new_bytes[0..capacity]);
                try std.testing.expectError(error.WriteFailed, before.encoder.encode(@field(before.Format, format), Corpus(before).event(variant), &old_short));
                try std.testing.expectError(error.WriteFailed, after.encoder.encode(@field(after.Format, format), Corpus(after).event(variant), &new_short));
                try std.testing.expectEqualStrings(old_short.buffered(), new_short.buffered());
                checks += 1;
            }
        }
    }
    std.debug.print("encoder differential: 12 complete records and {d} short-buffer prefixes identical\n", .{checks});
}
