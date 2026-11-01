const std = @import("std");
const Event = @import("../core/event.zig").Event;
pub const Format = enum { text, json, logfmt, binary };
pub const text = @import("text.zig");
pub const json = @import("json.zig");
pub const logfmt = @import("logfmt.zig");
pub const binary = @import("../archive/writer.zig");
const time = @import("../time/root.zig");

test {
    _ = @import("source_path.zig");
}

test "source location text keeps repository paths linkable and identical after inline and schema decoding" {
    const field = @import("../core/field.zig");
    const codec = @import("../core/codec.zig");
    const schema = @import("../journal/schema.zig");
    const references = @import("../core/schema_codec.zig");
    const wire = @import("wire_json.zig");
    const source = @import("../submit/source.zig").fromModule("src", .{ .module = "app", .file = "http/handler.zig", .fn_name = "handle", .line = 42, .column = 7 });
    const event: Event = .{ .level = .info, .scope = "http", .message = "completed", .timestamp_ns = 0, .source = source, .fields = &.{field.kv("status", @as(u16, 200))} };
    var ordinary_bytes: [2048]u8 = undefined;
    var ordinary = std.Io.Writer.fixed(&ordinary_bytes);
    try encode(.text, event, &ordinary);
    try std.testing.expect(std.mem.indexOf(u8, ordinary.buffered(), " source= src/http/handler.zig:42:7 ") != null);
    try std.testing.expect(std.mem.indexOf(u8, ordinary.buffered(), "source= \"") == null);
    var json_bytes: [2048]u8 = undefined;
    var json_output = std.Io.Writer.fixed(&json_bytes);
    try encode(.json, event, &json_output);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_output.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(source.file, parsed.value.object.get("source").?.object.get("file").?.string);
    var payload_bytes: [2048]u8 = undefined;
    const payload = try codec.encode(event, &payload_bytes);
    var keys: [256]field.Field = undefined;
    var output_bytes: [2048]u8 = undefined;
    const inline_output = try wire.render(.text, payload, try codec.readHeader(payload, codec.version), &output_bytes, &keys, null);
    try std.testing.expectEqualStrings(ordinary.buffered(), inline_output);
    var field_metadata: [64]schema.FieldSchema = undefined;
    var arg_metadata: [64]schema.FieldSchema = undefined;
    const metadata = try references.eventMetadata(event, &field_metadata, &arg_metadata);
    const layout = try schema.layout(4096, 1, 1024);
    const region = try std.testing.allocator.alignedAlloc(u8, .fromByteUnits(4096), layout.size);
    defer std.testing.allocator.free(region);
    @memset(region, 0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, @alignCast(region[layout.offset..]), layout);
    defer registry.deinit();
    const reference = (try registry.register(metadata)).ref;
    try registry.markReady(reference);
    const definition = try registry.resolve(reference);
    const referenced = try references.encodeReference(event, definition, &payload_bytes);
    const reference_output = try wire.renderReference(.text, referenced, try references.readReferenceHeader(referenced, definition, keys.len), definition, &output_bytes, &keys, null);
    try std.testing.expectEqualStrings(ordinary.buffered(), reference_output);
}

/// Event descriptors and borrowed bytes must remain valid and unchanged until
/// this call returns. Writer callbacks must preserve that borrowed storage.
pub fn encode(format: Format, event: Event, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (format) {
        .text => try text.encode(event, writer),
        .json => try json.encode(event, writer),
        .logfmt => try logfmt.encode(event, writer),
        .binary => binary.encode(event, writer) catch return error.WriteFailed,
    }
}

/// Optional readable wall time. The caller owns and serializes this formatter.
/// Original timestamp_ns remains in JSON/logfmt; text uses the readable prefix.
pub fn encodeWithTime(format: Format, event: Event, formatter: *time.Formatter, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (format) {
        .text => try @import("common.zig").encodeWithTime(.text, event, formatter, writer),
        .json => try @import("common.zig").encodeWithTime(.json, event, formatter, writer),
        .logfmt => try @import("common.zig").encodeWithTime(.logfmt, event, formatter, writer),
        .binary => return error.WriteFailed,
    }
}

test "bounded encoders report overflow instead of treating a prefix as success" {
    for (std.enums.values(Format)) |format| {
        var buffer: [8]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try std.testing.expectError(error.WriteFailed, encode(format, .{ .level = .info, .scope = "http", .message = "too large", .fields = &.{}, .timestamp_ns = 0 }, &writer));
    }
}

test "deferred rendering escapes all output formats without a message scratch limit" {
    const field = @import("../core/field.zig");
    var message_bytes = [_]u8{'a'} ** 8192;
    message_bytes[17] = '\n';
    const event: Event = .{ .level = .info, .scope = "fmt", .message = "{s} {d:04} {{ok}}", .message_template = true, .format_args = &.{ field.kv("", &message_bytes), field.kv("", @as(u16, 15)) }, .fields = &.{}, .timestamp_ns = 0 };
    for (std.enums.values(Format)) |format| {
        var buffer: [16384]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try encode(format, event, &writer);
        if (format == .binary) {
            const header = try binary.format.validate(writer.buffered());
            try std.testing.expectEqual(header.crc32, binary.format.frameCRC(writer.buffered()[binary.format.header_size..]));
            continue;
        }
        try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "0015 {ok}") != null);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, writer.buffered(), "\n"));
        try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\\n") != null);
    }
}

test "nested containers remain complete records with secret erasure and logfmt quoting" {
    const field = @import("../core/field.zig");
    const items = [_]field.Value{
        field.fromAny("a b\n\""),
        field.fromAny(field.secret("nested-secret-original")),
        .{ .group = &.{field.kv("ok", true)} },
        .{ .array = &.{} },
    };
    const event: Event = .{ .level = .info, .scope = "nested", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("nested", field.group(&.{field.kv("items", field.array(&items))}))} };
    inline for (.{ Format.text, Format.json, Format.logfmt }) |format| {
        var buffer: [4096]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try encode(format, event, &writer);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, writer.buffered(), "\n"));
        try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "nested-secret-original") == null);
        if (format == .logfmt) {
            const marker = "attr.nested=";
            const start = std.mem.indexOf(u8, writer.buffered(), marker).? + marker.len;
            const value = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, std.mem.trimEnd(u8, writer.buffered()[start..], "\n"), .{});
            defer value.deinit();
            const nested = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, value.value.string, .{});
            defer nested.deinit();
            const recovered = nested.value.object.get("items").?.array.items;
            try std.testing.expectEqualStrings("a b\n\"", recovered[0].string);
            try std.testing.expectEqualStrings(field.redacted, recovered[1].string);
            try std.testing.expect(recovered[2].object.get("ok").?.bool);
            try std.testing.expectEqual(@as(usize, 0), recovered[3].array.items.len);
        }
    }
}

test "all encoders reject nested cycles depth duplicate keys and shared node budget before output" {
    const field = @import("../core/field.zig");
    var cyclic: [1]field.Value = undefined;
    cyclic[0] = .{ .array = &cyclic };
    var chain: [field.max_value_depth + 1]field.Value = undefined;
    for (&chain, 0..) |*node, i| node.* = if (i + 1 < chain.len) .{ .array = chain[i + 1 ..][0..1] } else .{ .group = &.{} };
    const half = [_]field.Value{.null_value} ** (field.max_value_nodes / 2);
    const invalid = [_]Event{
        .{ .level = .info, .scope = "", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("cycle", field.array(&cyclic))} },
        .{ .level = .info, .scope = "", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("deep", chain[0])} },
        .{ .level = .info, .scope = "", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("duplicate", field.group(&.{ field.kv("key", 1), field.kv("key", 2) }))} },
        .{ .level = .info, .scope = "", .message = "{any}", .message_template = true, .timestamp_ns = 0, .fields = &.{field.kv("half", field.array(&half))}, .format_args = &.{field.kv("", field.array(&half))} },
    };
    for (std.enums.values(Format)) |format| {
        for (invalid) |event| {
            var buffer: [16384]u8 = undefined;
            var writer = std.Io.Writer.fixed(&buffer);
            try std.testing.expectError(error.WriteFailed, encode(format, event, &writer));
            try std.testing.expectEqual(@as(usize, 0), writer.end);
        }
    }
}

test {
    _ = text;
    _ = json;
    _ = logfmt;
    _ = binary;
    _ = @import("wire_json.zig");
}

test "public encoder validates even when the internal proof hint is set" {
    const field = @import("../core/field.zig");
    var cyclic: [1]field.Value = undefined;
    cyclic[0] = .{ .array = &cyclic };
    const event: Event = .{ .level = .info, .scope = "", .message = "", .fields = &.{field.kv("cycle", field.array(&cyclic))}, .timestamp_ns = 0, .tree_validated = true };
    var buffer: [256]u8 = @splat(0xa5);
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.WriteFailed, encode(.json, event, &writer));
    try std.testing.expectEqual(@as(usize, 0), writer.end);
    try std.testing.expect(std.mem.allEqual(u8, &buffer, 0xa5));
}
