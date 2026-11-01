//! Safe complete-record and standalone value rendering. Escaping primitives
//! live separately; validated recursive output stays private to this module.
const std = @import("std");
const fields = @import("../core/field.zig");
const Value = fields.Value;
const Event = @import("../core/event.zig").Event;
const formatting = @import("../submit/format.zig");
const decimal = @import("decimal.zig");
const time = @import("../time/root.zig");

const escaping_primitives = @import("escaping.zig");
const source_path = @import("source_path.zig");
pub const Escaping = escaping_primitives.Escaping;
pub const quoted = escaping_primitives.quoted;
pub const QuotedWriter = escaping_primitives.QuotedWriter;
pub const hexByte = escaping_primitives.hexByte;
pub const hex = escaping_primitives.hex;
pub const jsonKey = escaping_primitives.jsonKey;
pub const logfmtKey = escaping_primitives.logfmtKey;

/// Validate the entire borrowed tree before an encoder writes its first byte.
/// Attributes and deferred arguments share the same bounded node budget.
pub fn validateEvent(event: Event) std.Io.Writer.Error!void {
    var validator: fields.ValueValidator = .{};
    validator.fields(event.fields) catch return error.WriteFailed;
    validator.arguments(event.format_args) catch return error.WriteFailed;
}

/// Escapes a message while deferred formatting writes it. No complete-message
/// scratch allocation or arbitrary truncation limit is needed.
pub fn message(writer: *std.Io.Writer, event: Event, escaping: Escaping) std.Io.Writer.Error!void {
    if (!event.message_template) return quoted(writer, event.message, escaping);
    var output = try QuotedWriter.init(writer, escaping);
    try formatting.render(event.message, event.format_args, &output.interface);
    try output.finish();
}

pub const RecordFormat = enum { text, json, logfmt };

/// Safe whole-record entry point. Borrowed event storage must remain unchanged
/// for this call, including during writer callbacks. Validation cannot escape
/// the call; the recursive renderer remains private.
pub fn encode(comptime format: RecordFormat, event: Event, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return encodeWithTime(format, event, null, writer);
}

pub fn encodeWithTime(comptime format: RecordFormat, event: Event, formatter: ?*time.Formatter, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try validateEvent(event);
    return renderWithTime(format, event, formatter, writer);
}

/// Internal delivery entry point. A checked decoder sets `tree_validated` only
/// after proving every attribute/argument invariant; public encoders never
/// consult the hint. An unproven event takes the normal validating path.
pub fn encodeDecoded(comptime format: RecordFormat, event: Event, formatter: ?*time.Formatter, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (!event.tree_validated) return encodeWithTime(format, event, formatter, writer);
    return renderWithTime(format, event, formatter, writer);
}

fn renderWithTime(comptime format: RecordFormat, event: Event, formatter: ?*time.Formatter, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var time_bytes: [time.rfc3339.max_length]u8 = undefined;
    const readable = if (formatter) |cache| cache.format(.{ .nanoseconds = event.timestamp_ns }, &time_bytes) catch return error.WriteFailed else null;
    switch (format) {
        .text => try encodeText(event, readable, writer),
        .json => try encodeJson(event, readable, writer),
        .logfmt => try encodeLogfmt(event, readable, writer),
    }
}

fn encodeJson(event: Event, readable: ?[]const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return encodeJsonWithAttributes(event, readable, writer, &event, struct {
        fn write(ctx: *const Event, output: *std.Io.Writer) std.Io.Writer.Error!void {
            for (ctx.fields, 0..) |field, index| {
                if (index != 0) try output.writeByte(',');
                try jsonKey(output, field.key);
                try output.writeByte(':');
                try valueInner(output, field.value, .json);
            }
        }
    }.write);
}

pub fn encodeJsonWithAttributes(event: Event, readable: ?[]const u8, writer: *std.Io.Writer, context: anytype, comptime writeAttributes: fn(@TypeOf(context), *std.Io.Writer) std.Io.Writer.Error!void) std.Io.Writer.Error!void {
    try writer.writeAll("{\"timestamp_ns\":");
    try valueInner(writer, .{ .timestamp_ns = event.timestamp_ns }, .json);
    if (readable) |timestamp| {
        try writer.writeAll(",\"timestamp\":");
        try quoted(writer, timestamp, .json);
    }
    try writer.writeAll(",\"severity\":");
    try quoted(writer, @tagName(event.level), .json);
    try writer.writeAll(",\"scope\":");
    try quoted(writer, event.scope, .json);
    try writer.writeAll(",\"message\":");
    try message(writer, event, .json);
    try writer.writeAll(",\"session\":");
    try valueInner(writer, .{ .unsigned = event.session }, .json);
    try writer.writeAll(",\"channel\":");
    try decimal.write(writer, event.channel);
    try writer.writeAll(",\"sequence\":");
    try valueInner(writer, .{ .unsigned = event.sequence }, .json);
    try writer.writeAll(",\"route_mask\":");
    try valueInner(writer, .{ .unsigned = event.route_mask }, .json);
    try writer.writeAll(",\"config_generation\":");
    try valueInner(writer, .{ .unsigned = event.config_generation }, .json);
    try writer.writeAll(",\"trace_flags\":");
    try decimal.write(writer, event.trace_flags);
    if (event.trace_id) |id| {
        try writer.writeAll(",\"trace_id\":\"");
        try hex(writer, &id);
        try writer.writeByte('"');
    }
    if (event.span_id) |id| {
        try writer.writeAll(",\"span_id\":\"");
        try hex(writer, &id);
        try writer.writeByte('"');
    }
    if (event.source) |source| {
        try writer.writeAll(",\"source\":{\"module\":");
        try quoted(writer, source.module, .json);
        try writer.writeAll(",\"file\":");
        try quoted(writer, source.file, .json);
        try writer.writeAll(",\"function\":");
        try quoted(writer, source.fn_name, .json);
        try writer.writeAll(",\"line\":");
        try decimal.write(writer, source.line);
        try writer.writeAll(",\"column\":");
        try decimal.write(writer, source.column);
        try writer.writeAll("}");
    }
    try writer.writeAll(",\"attributes\":{");
    try writeAttributes(context, writer);
    try writer.writeAll("}}\n");
}

fn encodeText(event: Event, readable: ?[]const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return encodeTextWithAttributes(event, readable, writer, &event, struct {
        fn write(ctx: *const Event, output: *std.Io.Writer) std.Io.Writer.Error!void {
            for (ctx.fields) |field| {
                try output.writeByte(' ');
                try quoted(output, field.key, .text);
                try output.writeByte('=');
                try valueInner(output, field.value, .text);
            }
        }
    }.write);
}

pub fn encodeTextWithAttributes(event: Event, readable: ?[]const u8, writer: *std.Io.Writer, context: anytype, comptime writeAttributes: fn(@TypeOf(context), *std.Io.Writer) std.Io.Writer.Error!void) std.Io.Writer.Error!void {
    if (readable) |timestamp| try writer.writeAll(timestamp) else try decimal.write(writer, event.timestamp_ns);
    try writer.writeByte(' ');
    try writer.writeAll(@tagName(event.level));
    try writer.writeAll(" scope=");
    try quoted(writer, event.scope, .text);
    try writer.writeAll(" message=");
    try message(writer, event, .text);
    try writer.writeAll(" session=");
    try decimal.write(writer, event.session);
    try writer.writeAll(" channel=");
    try decimal.write(writer, event.channel);
    try writer.writeAll(" sequence=");
    try decimal.write(writer, event.sequence);
    if (event.trace_id) |id| {
        try writer.writeAll(" trace_id=");
        try hex(writer, &id);
    }
    if (event.span_id) |id| {
        try writer.writeAll(" span_id=");
        try hex(writer, &id);
    }
    if (event.source) |source| {
        try writer.writeAll(" source=");
        try source_path.write(writer, source.file);
        try writer.writeByte(':');
        try decimal.write(writer, source.line);
        try writer.writeByte(':');
        try decimal.write(writer, source.column);
    }
    try writeAttributes(context, writer);
    try writer.writeByte('\n');
}

fn encodeLogfmt(event: Event, readable: ?[]const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return encodeLogfmtWithAttributes(event, readable, writer, &event, struct {
        fn write(ctx: *const Event, output: *std.Io.Writer) std.Io.Writer.Error!void {
            for (ctx.fields) |field| {
                try output.writeAll(" attr.");
                try logfmtKey(output, field.key);
                try output.writeByte('=');
                if (field.value == .array or field.value == .group) {
                    // A nested representation is one quoted logfmt value,
                    // including embedded spaces, quotes and record separators.
                    var nested = try QuotedWriter.init(output, .text);
                    try valueInner(&nested.interface, field.value, .text);
                    try nested.finish();
                } else try valueInner(output, field.value, .text);
            }
        }
    }.write);
}

pub fn encodeLogfmtWithAttributes(event: Event, readable: ?[]const u8, writer: *std.Io.Writer, context: anytype, comptime writeAttributes: fn(@TypeOf(context), *std.Io.Writer) std.Io.Writer.Error!void) std.Io.Writer.Error!void {
    try writer.writeAll("timestamp_ns=");
    try decimal.write(writer, event.timestamp_ns);
    if (readable) |timestamp| {
        try writer.writeAll(" timestamp=");
        try quoted(writer, timestamp, .text);
    }
    try writer.writeAll(" severity=");
    try writer.writeAll(@tagName(event.level));
    try writer.writeAll(" scope=");
    try quoted(writer, event.scope, .text);
    try writer.writeAll(" message=");
    try message(writer, event, .text);
    try writer.writeAll(" session=");
    try decimal.write(writer, event.session);
    try writer.writeAll(" channel=");
    try decimal.write(writer, event.channel);
    try writer.writeAll(" sequence=");
    try decimal.write(writer, event.sequence);
    try writer.writeAll(" route_mask=");
    try decimal.write(writer, event.route_mask);
    try writer.writeAll(" config_generation=");
    try decimal.write(writer, event.config_generation);
    try writer.writeAll(" trace_flags=");
    try decimal.write(writer, event.trace_flags);
    if (event.trace_id) |id| {
        try writer.writeAll(" trace_id=");
        try hex(writer, &id);
    }
    if (event.span_id) |id| {
        try writer.writeAll(" span_id=");
        try hex(writer, &id);
    }
    if (event.source) |source| {
        try writer.writeAll(" source.file=");
        try quoted(writer, source.file, .text);
        try writer.writeAll(" source.line=");
        try decimal.write(writer, source.line);
        try writer.writeAll(" source.column=");
        try decimal.write(writer, source.column);
    }
    try writeAttributes(context, writer);
    try writer.writeByte('\n');
}

/// Standalone values retain their own complete validation. Borrowed storage
/// must remain unchanged until this call returns, including writer callbacks.
pub fn value(writer: *std.Io.Writer, typed: Value, escaping: Escaping) std.Io.Writer.Error!void {
    fields.validateValue(typed) catch return error.WriteFailed;
    try valueInner(writer, typed, escaping);
}

/// Internal wire renderer entry. The checked wire parser has already validated
/// the complete value tree; this does not accept arbitrary public values.
pub fn writeWireValue(writer: *std.Io.Writer, typed: Value, escaping: Escaping) std.Io.Writer.Error!void {
    return valueInner(writer, typed, escaping);
}

test "record encoding validates every value tag once with one shared attribute and argument budget" {
    const encoders = @import("root.zig");
    const items = [_]Value{
        .null_value,
        .{ .boolean = true },
        .{ .signed = std.math.minInt(i128) },
        .{ .unsigned = std.math.maxInt(u128) },
        .{ .float = std.math.nan(f64) },
        .{ .string = "雪\n\xff" },
        .{ .bytes = "\x00\xff" },
        .{ .duration_ns = std.math.minInt(i64) },
        .{ .timestamp_ns = std.math.maxInt(i64) },
        .{ .array = &.{} },
        .{ .group = &.{fields.kv("nested", null)} },
    };
    const event: Event = .{
        .level = .info,
        .scope = "all-tags",
        .message = "plain",
        .timestamp_ns = std.math.maxInt(i64),
        .fields = &.{fields.kv("all", fields.array(&items))},
        // Unused arguments still participate in the event-wide validation.
        .format_args = &.{fields.kv("", true)},
        .source = @src(),
    };
    inline for (.{ encoders.Format.text, encoders.Format.json, encoders.Format.logfmt }) |format| {
        var bytes: [8192]u8 = undefined;
        var output = std.Io.Writer.fixed(&bytes);
        const before = fields.TestingAudit.visited_values;
        try encoders.encode(format, event, &output);
        // Root array + eleven children + nested null + positional bool.
        try std.testing.expectEqual(@as(usize, 14), fields.TestingAudit.visited_values - before);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, output.buffered(), "\n"));
    }
}

test "record encoding standalone values still reject invalid trees before output" {
    const invalid: Value = .{ .group = &.{ fields.kv("same", 1), fields.kv("same", 2) } };
    for (std.enums.values(Escaping)) |mode| {
        var bytes: [256]u8 = undefined;
        var output = std.Io.Writer.fixed(&bytes);
        try std.testing.expectError(error.WriteFailed, value(&output, invalid, mode));
        try std.testing.expectEqual(@as(usize, 0), output.end);
        const before = fields.TestingAudit.visited_values;
        try value(&output, .{ .array = &.{ .null_value, .{ .boolean = true } } }, mode);
        try std.testing.expectEqual(@as(usize, 3), fields.TestingAudit.visited_values - before);
        try std.testing.expectEqualStrings("[null,true]", output.buffered());
    }
}

fn valueInner(writer: *std.Io.Writer, typed: Value, escaping: Escaping) std.Io.Writer.Error!void {
    switch (typed) {
        .null_value => try writer.writeAll("null"),
        .boolean => |v| try writer.writeAll(if (v) "true" else "false"),
        .signed => |v| {
            const quote = escaping == .json and (v < -9007199254740991 or v > 9007199254740991);
            if (quote) try writer.writeByte('"');
            try decimal.write(writer, v);
            if (quote) try writer.writeByte('"');
        },
        .unsigned => |v| {
            const quote = escaping == .json and v > 9007199254740991;
            if (quote) try writer.writeByte('"');
            try decimal.write(writer, v);
            if (quote) try writer.writeByte('"');
        },
        .float => |v| {
            if (std.math.isFinite(v)) {
                try writer.print("{d}", .{v});
            } else if (escaping == .json) {
                try writer.writeAll("null");
            } else try quoted(writer, if (std.math.isNan(v)) "NaN" else if (v < 0) "-Inf" else "Inf", escaping);
        },
        .string => |v| try quoted(writer, v, escaping),
        .bytes => |v| {
            try writer.writeAll("\"hex:");
            try hex(writer, v);
            try writer.writeByte('"');
        },
        .duration_ns, .timestamp_ns => |v| {
            const quote = escaping == .json and (v < -9007199254740991 or v > 9007199254740991);
            if (quote) try writer.writeByte('"');
            try decimal.write(writer, v);
            if (quote) try writer.writeByte('"');
        },
        .array => |items| {
            try writer.writeByte('[');
            for (items, 0..) |item, index| {
                if (index != 0) try writer.writeByte(',');
                try valueInner(writer, item, escaping);
            }
            try writer.writeByte(']');
        },
        .group => |members| {
            try writer.writeByte('{');
            for (members, 0..) |member, index| {
                if (index != 0) try writer.writeByte(',');
                if (escaping == .json) {
                    try jsonKey(writer, member.key);
                } else try quoted(writer, member.key, escaping);
                try writer.writeByte(':');
                try valueInner(writer, member.value, escaping);
            }
            try writer.writeByte('}');
        },
    }
}

test "decoded delivery proof reuses decoder validation with identical bytes" {
    const codec = @import("../core/codec.zig");
    var payload_buffer: [4096]u8 = undefined;
    const event: Event = .{
        .level = .warn,
        .scope = "proof",
        .message = "value {d}",
        .message_template = true,
        .format_args = &.{fields.kv("0", @as(u64, 42))},
        .fields = &.{
            fields.kv("nested", fields.group(&.{fields.kv("x", true), fields.kv("y", fields.array(&.{ .null_value, fields.fromAny("z") }))})),
            fields.kv("secret", fields.secret("original")),
        },
        .timestamp_ns = -1,
        .session = 7,
        .sequence = 9,
        .channel = 2,
        .route_mask = 1,
        .config_generation = 3,
        .trace_id = @splat(1),
        .source = @src(),
    };
    const payload = try codec.encode(event, &payload_buffer);
    var scratch: [64]fields.Field = undefined;
    const decoded = try codec.decode(payload, &scratch);
    try std.testing.expect(decoded.tree_validated);
    inline for (.{ RecordFormat.text, RecordFormat.json, RecordFormat.logfmt }) |format| {
        var expected_bytes: [4096]u8 = undefined;
        var actual_bytes: [4096]u8 = undefined;
        var expected = std.Io.Writer.fixed(&expected_bytes);
        var actual = std.Io.Writer.fixed(&actual_bytes);
        try encodeWithTime(format, decoded, null, &expected);
        try encodeDecoded(format, decoded, null, &actual);
        try std.testing.expectEqualStrings(expected.buffered(), actual.buffered());
    }
    // An unproven event still takes the complete validation path.
    var cyclic: [1]fields.Value = undefined;
    cyclic[0] = .{ .array = &cyclic };
    const invalid: Event = .{ .level = .info, .scope = "", .message = "", .fields = &.{fields.kv("cycle", fields.array(&cyclic))}, .timestamp_ns = 0 };
    var untouched: [256]u8 = @splat(0xa5);
    var output = std.Io.Writer.fixed(&untouched);
    try std.testing.expectError(error.WriteFailed, encodeDecoded(.json, invalid, null, &output));
    try std.testing.expectEqual(@as(usize, 0), output.end);
    try std.testing.expect(std.mem.allEqual(u8, &untouched, 0xa5));
}
