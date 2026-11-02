//! Fused wire-to-record rendering for the current self-contained v4 payload.
//! This path is used only when the consumer selected a single JSON, text or
//! logfmt route and the payload has no deferred message/arguments. The checked
//! wire parser validates every value while the record is built in a
//! caller-owned scratch buffer; a rejected record never reaches a sink.
//! Anything else returns `error.Fallback` so decode-and-encode stays
//! authoritative.
const std = @import("std");
const codec = @import("../core/codec.zig");
const schema_codec = @import("../core/schema_codec.zig");
const field = @import("../core/field.zig");
const common = @import("common.zig");
const time = @import("../time/root.zig");

pub const Error = schema_codec.DecodeError || std.Io.Writer.Error || error{Fallback};
pub const Format = enum { json, text, logfmt };

fn Context(comptime referenced: bool) type {
    return struct {
        input: *codec.WireInput,
        count: usize,
        keys: if (referenced) schema_codec.schema.FieldIterator else []field.Field,
        failure: ?Error = null,
    };
}

fn ValueWriter(comptime format: Format, comptime referenced: bool) type {
    return struct {
        pub const Error = @import("wire_json.zig").Error;
        writer: *std.Io.Writer,
        key: []const u8,
        index: usize,
        kind_mask: u16,

        pub fn accept(self: *@This(), comptime tag: codec.ValueTag, data: anytype) @This().Error!void {
            if (referenced and self.kind_mask & schema_codec.schema.kindMask(tag) == 0) return error.SchemaMismatch;
            const writer = self.writer;
            const value_tag = @field(std.meta.Tag(field.Value), @tagName(tag));
            switch (format) {
                .json => {
                    if (self.index != 0) try writer.writeByte(',');
                    try common.jsonKey(writer, self.key);
                    try writer.writeByte(':');
                    try common.writeTaggedValue(writer, value_tag, data, .json);
                },
                .text => {
                    try writer.writeByte(' ');
                    try common.quoted(writer, self.key, .text);
                    try writer.writeAll("= ");
                    try common.writeTaggedValue(writer, value_tag, data, .text);
                },
                .logfmt => {
                    try writer.writeAll(" attr.");
                    try common.logfmtKey(writer, self.key);
                    try writer.writeByte('=');
                    if (tag == .array or tag == .group) {
                        var nested = try common.QuotedWriter.init(writer, .text);
                        try common.writeTaggedValue(&nested.interface, value_tag, data, .text);
                        try nested.finish();
                    } else try common.writeTaggedValue(writer, value_tag, data, .text);
                },
            }
        }
    };
}

fn writeAttributesFallible(comptime format: Format, comptime referenced: bool, ctx: *Context(referenced), writer: *std.Io.Writer) Error!void {
    for (0..ctx.count) |index| {
        const metadata = if (referenced) (try ctx.keys.next()) orelse return error.SchemaMismatch else {};
        const key = if (referenced) metadata.key else try ctx.input.blob();
        if (!referenced) {
            try field.checkUnique(ctx.keys[0..index], key);
            ctx.keys[index] = .{ .key = key, .value = .null_value };
        }
        var receiver: ValueWriter(format, referenced) = .{ .writer = writer, .key = key, .index = index, .kind_mask = if (referenced) metadata.kind_mask else 0 };
        try ctx.input.valueWith(&receiver);
    }
    if (ctx.input.position != ctx.input.bytes.len) return error.InvalidLength;
}

fn Attributes(comptime format: Format, comptime referenced: bool) type {
    return struct {
        fn write(ctx: *Context(referenced), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            writeAttributesFallible(format, referenced, ctx, writer) catch |err| {
                ctx.failure = err;
                return error.WriteFailed;
            };
        }
    };
}

pub fn render(format: Format, payload: []const u8, header: codec.EventHeader, output: []u8, key_scratch: []field.Field, formatter: ?*time.Formatter) Error![]const u8 {
    return switch (format) {
        .json => renderFormat(.json, false, payload, header, {}, output, key_scratch, formatter),
        .text => renderFormat(.text, false, payload, header, {}, output, key_scratch, formatter),
        .logfmt => renderFormat(.logfmt, false, payload, header, {}, output, key_scratch, formatter),
    };
}

pub fn renderReference(format: Format, payload: []const u8, header: codec.EventHeader, definition: schema_codec.Definition, output: []u8, scratch: []field.Field, formatter: ?*time.Formatter) Error![]const u8 {
    return switch (format) {
        .json => renderFormat(.json, true, payload, header, definition, output, scratch, formatter),
        .text => renderFormat(.text, true, payload, header, definition, output, scratch, formatter),
        .logfmt => renderFormat(.logfmt, true, payload, header, definition, output, scratch, formatter),
    };
}

fn renderFormat(comptime format: Format, comptime referenced: bool, payload: []const u8, header: codec.EventHeader, definition: if (referenced) schema_codec.Definition else void, output: []u8, key_scratch: []field.Field, formatter: ?*time.Formatter) Error![]const u8 {
    if (header.event.message_template or header.argument_count != 0) return error.Fallback;
    if (header.field_count > key_scratch.len) return error.TooManyFields;
    var arena = codec.DescriptorArena.init(key_scratch[header.field_count..]);
    var input: codec.WireInput = .{ .bytes = payload, .position = header.header_bytes, .arena = &arena, .allow_nested = if (referenced) definition.ref.version == schema_codec.schema.nested_version else true };
    var event = header.event;
    event.scope = if (referenced) definition.scope else try input.blob();
    if (!referenced) event.message = try input.blob();
    if (header.flags & 2 != 0) event.trace_id = (try input.take(16))[0..16].*;
    if (header.flags & 4 != 0) event.span_id = (try input.take(8))[0..8].*;
    if (referenced) {
        event.source = definition.source;
        event.message = if (definition.message) |message| message else try input.blob();
    } else if (header.flags & 1 != 0) event.source = .{
        .module = try input.terminated(),
        .file = try input.terminated(),
        .fn_name = try input.terminated(),
        .line = try input.int(u32),
        .column = try input.int(u32),
    };
    event.fields = &.{};
    event.format_args = &.{};
    var time_bytes: [time.rfc3339.max_length]u8 = undefined;
    const readable = if (formatter) |cache| cache.format(.{ .nanoseconds = event.timestamp_ns }, &time_bytes) catch return error.WriteFailed else null;
    var writer = std.Io.Writer.fixed(output);
    var context: Context(referenced) = .{ .input = &input, .count = header.field_count, .keys = if (referenced) definition.fields() else key_scratch };
    const result = switch (format) {
        .json => common.encodeJsonWithAttributes(event, readable, &writer, &context, Attributes(format, referenced).write),
        .text => common.encodeTextWithAttributes(event, readable, &writer, &context, Attributes(format, referenced).write),
        .logfmt => common.encodeLogfmtWithAttributes(event, readable, &writer, &context, Attributes(format, referenced).write),
    };
    result catch |err| switch (err) {
        error.WriteFailed => return context.failure orelse error.WriteFailed,
        else => |other| return other,
    };
    return writer.buffered();
}

test "fused wire JSON matches decoded encoder for flat scalar events" {
    const Event = @import("../core/event.zig").Event;
    const entries = [_]field.Field{
        field.kv("u", @as(u64, 42)),
        field.kv("i", @as(i64, -7)),
        field.kv("s", "hello"),
        field.kv("b", true),
        field.kv("f", 1.5),
        field.kv("d", field.durationNs(-5)),
        field.kv("t", field.timestampNs(123)),
        field.kv("n", null),
    };
    var payload_buffer: [2048]u8 = undefined;
    const event: Event = .{
        .level = .info,
        .scope = "wire",
        .message = "flat",
        .timestamp_ns = 0,
        .fields = &entries,
        .session = 9,
        .sequence = 10,
        .channel = 3,
        .route_mask = 1,
        .config_generation = 2,
        .trace_id = @splat(1),
        .span_id = @splat(2),
        .source = @src(),
    };
    const payload = try codec.encode(event, &payload_buffer);
    const header = try codec.readHeader(payload, codec.version);
    var output: [2048]u8 = undefined;
    var keys: [16]field.Field = undefined;
    const rendered = try render(.json, payload, header, &output, &keys, null);
    var decode_scratch: [16]field.Field = undefined;
    const decoded = try codec.decode(payload, &decode_scratch);
    var expected_buffer: [2048]u8 = undefined;
    var expected = std.Io.Writer.fixed(&expected_buffer);
    try common.encodeWithTime(.json, decoded, null, &expected);
    try std.testing.expectEqualStrings(expected.buffered(), rendered);
}

test "fused wire JSON matches decoded encoder for nested attributes" {
    const Event = @import("../core/event.zig").Event;
    var payload_buffer: [2048]u8 = undefined;
    const nested: Event = .{ .level = .info, .scope = "nested", .message = "x", .timestamp_ns = 0, .fields = &.{field.kv("g", field.group(&.{ field.kv("x", true), field.kv("y", field.array(&.{ .null_value, field.fromAny("z") })) }))} };
    const payload = try codec.encode(nested, &payload_buffer);
    const header = try codec.readHeader(payload, codec.version);
    var output: [2048]u8 = undefined;
    var keys: [16]field.Field = undefined;
    const rendered = try render(.json, payload, header, &output, &keys, null);
    var decode_scratch: [16]field.Field = undefined;
    const decoded = try codec.decode(payload, &decode_scratch);
    var expected_buffer: [2048]u8 = undefined;
    var expected = std.Io.Writer.fixed(&expected_buffer);
    try common.encodeWithTime(.json, decoded, null, &expected);
    try std.testing.expectEqualStrings(expected.buffered(), rendered);
}

test "fused wire JSON declines deferred messages" {
    const Event = @import("../core/event.zig").Event;
    var template_buffer: [2048]u8 = undefined;
    const template: Event = .{ .level = .info, .scope = "template", .message = "{d}", .message_template = true, .format_args = &.{field.kv("0", @as(u64, 1))}, .timestamp_ns = 0, .fields = &.{} };
    const template_payload = try codec.encode(template, &template_buffer);
    const template_header = try codec.readHeader(template_payload, codec.version);
    var output: [2048]u8 = undefined;
    var keys: [16]field.Field = undefined;
    try std.testing.expectError(error.Fallback, render(.json, template_payload, template_header, &output, &keys, null));
}

test "fused wire JSON matches readable timestamp formatting" {
    const Event = @import("../core/event.zig").Event;
    var payload_buffer: [2048]u8 = undefined;
    const event: Event = .{ .level = .warn, .scope = "time", .message = "stamp", .timestamp_ns = 1_700_000_000_123_456_789, .fields = &.{} };
    const payload = try codec.encode(event, &payload_buffer);
    const header = try codec.readHeader(payload, codec.version);
    var formatter = try time.Formatter.init(.{ .offset = try time.UtcOffset.parse("+08:00"), .precision = .milliseconds });
    var output: [2048]u8 = undefined;
    var keys: [16]field.Field = undefined;
    const rendered = try render(.json, payload, header, &output, &keys, &formatter);
    var decode_scratch: [16]field.Field = undefined;
    const decoded = try codec.decode(payload, &decode_scratch);
    var expected_buffer: [2048]u8 = undefined;
    var expected = std.Io.Writer.fixed(&expected_buffer);
    try common.encodeWithTime(.json, decoded, &formatter, &expected);
    try std.testing.expectEqualStrings(expected.buffered(), rendered);
}

test "fused wire text and logfmt match decoded encoders" {
    const Event = @import("../core/event.zig").Event;
    var payload_buffer: [2048]u8 = undefined;
    const event: Event = .{
        .level = .err,
        .scope = "fmt",
        .message = "nested",
        .timestamp_ns = -123,
        .fields = &.{
            field.kv("g", field.group(&.{ field.kv("x", true), field.kv("y", field.array(&.{ .null_value, field.fromAny("z") })) })),
            field.kv("plain", "a b"),
        },
        .session = 7,
        .sequence = 8,
        .channel = 2,
        .route_mask = 3,
        .config_generation = 4,
        .trace_id = @splat(5),
        .span_id = @splat(6),
        .source = @src(),
    };
    const payload = try codec.encode(event, &payload_buffer);
    const header = try codec.readHeader(payload, codec.version);
    inline for (.{ Format.text, Format.logfmt }) |format| {
        var output: [2048]u8 = undefined;
        var keys: [16]field.Field = undefined;
        const rendered = try render(format, payload, header, &output, &keys, null);
        var decode_scratch: [16]field.Field = undefined;
        const decoded = try codec.decode(payload, &decode_scratch);
        const record_format: common.RecordFormat = switch (format) {
            .text => .text,
            .logfmt => .logfmt,
            .json => .json,
        };
        var expected_buffer: [2048]u8 = undefined;
        var expected = std.Io.Writer.fixed(&expected_buffer);
        try common.encodeWithTime(record_format, decoded, null, &expected);
        try std.testing.expectEqualStrings(expected.buffered(), rendered);
    }
}

test {
    _ = @import("wire_reference_tests.zig");
}
