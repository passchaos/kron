//! Schema-referenced event payload v5 (also reads historical v2). The fixed journal slot header owns the
//! schema reference; a standalone archive writes self-contained codec v4.
const std = @import("std");
const codec = @import("codec.zig");
pub const schema = @import("../journal/schema.zig");
const Event = @import("event.zig").Event;
const field_module = @import("field.zig");
const Field = field_module.Field;
const SizeVisitor = @import("wire_size.zig").SizeVisitor;
const wire = @import("wire_write.zig");

pub const version: u16 = codec.reference_version;
pub const EventMeta = schema.EventMeta;
pub const FieldSchema = schema.FieldSchema;
pub const Definition = schema.Definition;
pub const MetadataError = schema.Error || field_module.ValidationError || error{TooManyFormatArgs};
pub const EncodeError = codec.EncodeError || schema.Error || error{SchemaMismatch};
pub const DecodeError = codec.DecodeError || schema.Error || error{SchemaMismatch};

/// Captures only key/type metadata, after context merging and redaction. The
/// keys borrow event storage for registration; values are never copied here.
pub fn eventMetadata(event: Event, fields: []FieldSchema, arguments: []FieldSchema) MetadataError!EventMeta {
    if (event.fields.len > fields.len or event.fields.len > schema.max_fields) return error.TooManyFields;
    if (event.format_args.len > arguments.len or event.format_args.len > schema.max_arguments) return error.TooManyFormatArgs;
    var validator: field_module.ValueValidator = .{};
    try validator.fields(event.fields);
    try validator.arguments(event.format_args);
    for (event.fields, fields[0..event.fields.len]) |field, *metadata| metadata.* = .{ .key = field.key, .kind_mask = schema.kindMask(codec.valueTag(field.value)) };
    for (event.format_args, arguments[0..event.format_args.len]) |argument, *metadata| metadata.* = .{ .key = argument.key, .kind_mask = schema.kindMask(codec.valueTag(argument.value)) };
    return .{
        .scope = event.scope,
        .message = if (event.message_template) event.message else null,
        .message_template = event.message_template,
        .source = event.source,
        .fields = fields[0..event.fields.len],
        .format_args = arguments[0..event.format_args.len],
    };
}

fn validateShape(event: Event, definition: Definition) EncodeError!void {
    if (!std.mem.eql(u8, event.scope, definition.scope) or event.message_template != definition.message_template or !schema.sourceEqual(event.source, definition.source) or event.fields.len != definition.field_count or event.format_args.len != definition.argument_count) return error.SchemaMismatch;
    if (definition.message) |message| if (!std.mem.eql(u8, event.message, message)) return error.SchemaMismatch;
    var fields = definition.fields();
    for (event.fields) |field| {
        const expected = (try fields.next()) orelse return error.SchemaMismatch;
        if (!std.mem.eql(u8, field.key, expected.key) or expected.kind_mask & schema.kindMask(codec.valueTag(field.value)) == 0) return error.SchemaMismatch;
    }
    var arguments = definition.arguments();
    for (event.format_args) |argument| {
        const expected = (try arguments.next()) orelse return error.SchemaMismatch;
        if (!std.mem.eql(u8, argument.key, expected.key) or expected.kind_mask & schema.kindMask(codec.valueTag(argument.value)) == 0) return error.SchemaMismatch;
    }
    if (event.level == .off) return error.InvalidLevel;
}

pub fn encodedReferenceSize(event: Event, definition: Definition) EncodeError!usize {
    var validator: field_module.ValueValidator = .{};
    var visitor: ReferenceSizeVisitor = .{ .size = .{ .total = codec.header_size }, .validator = &validator };
    if (event.trace_id != null) visitor.size.add(16);
    if (event.span_id != null) visitor.size.add(8);
    if (definition.message == null) visitor.size.blob(event.message.len, false);
    try validator.fieldsWith(event.fields, &visitor);
    try validator.argumentsWith(event.format_args, &visitor);
    // Preserve complete-tree validation before shape/level errors, and those
    // errors before wire overflow. Nothing has written destination yet.
    try validateShape(event, definition);
    return visitor.size.result();
}

const ReferenceSizeVisitor = struct {
    pub const Error = error{};
    size: SizeVisitor,
    validator: *const field_module.ValueValidator,

    pub fn onField(self: *@This(), entry: Field) Error!void {
        // Top-level keys live in the schema. A nested group key remains part
        // of this payload and must be counted, including groups in arguments.
        if (self.validator.depth != 0) try self.size.onField(entry);
    }

    pub fn onValue(self: *@This(), value: field_module.Value) Error!void {
        try self.size.onValue(value);
    }
};

/// Validates shape/types/capacity before touching destination. Only dynamic
/// message, nested keys and all typed values are copied into the event payload.
pub fn encodeReference(event: Event, definition: Definition, destination: []u8) EncodeError![]const u8 {
    const size = try encodedReferenceSize(event, definition);
    if (destination.len < size) return error.BufferTooSmall;
    var output = std.Io.Writer.fixed(destination[0..size]);
    codec.writeHeader(event, size, version, &output) catch |err| switch (err) {
        error.WriteFailed => return error.BufferTooSmall,
        else => |other| return other,
    };
    if (event.trace_id) |id| output.writeAll(&id) catch return error.BufferTooSmall;
    if (event.span_id) |id| output.writeAll(&id) catch return error.BufferTooSmall;
    if (definition.message == null) {
        var length: [4]u8 = undefined;
        std.mem.writeInt(u32, &length, @intCast(event.message.len), .little);
        output.writeAll(&length) catch return error.BufferTooSmall;
        output.writeAll(event.message) catch return error.BufferTooSmall;
    }
    var values_output: wire.StreamOutput = .{ .writer = &output };
    for (event.fields) |field| wire.writeValueTo(&values_output, field.value) catch return error.BufferTooSmall;
    for (event.format_args) |argument| wire.writeValueTo(&values_output, argument.value) catch return error.BufferTooSmall;
    std.debug.assert(output.end == size);
    return destination[0..size];
}

/// Shared checked prefix for materialized and fused reference consumers.
/// The definition must come from the owning registry's checked/ready lookup.
pub fn readReferenceHeader(payload: []const u8, definition: Definition, scratch_capacity: usize) DecodeError!codec.EventHeader {
    var prefix: codec.WireInput = .{ .bytes = payload };
    _ = try prefix.take(4);
    const wire_version = try prefix.int(u16);
    if (wire_version != version and wire_version != codec.legacy_reference_version) return error.UnsupportedVersion;
    const header = try codec.readHeader(payload, wire_version);
    if (header.field_count != definition.field_count or header.argument_count != definition.argument_count or header.event.message_template != definition.message_template or (header.flags & 1 != 0) != (definition.source != null)) return error.SchemaMismatch;
    if (header.field_count > scratch_capacity or header.argument_count > scratch_capacity - header.field_count) return error.TooManyFields;
    return header;
}

/// Event values borrow payload; metadata borrows the separately validated
/// definition; nested descriptors use caller scratch as in codec.decode.
/// A reader must independently own/copy both byte ranges and retain scratch.
pub fn resolve(payload: []const u8, definition: Definition, scratch: []Field) DecodeError!Event {
    const header = try readReferenceHeader(payload, definition, scratch.len);
    var event = header.event;
    event.scope = definition.scope;
    event.source = definition.source;
    var arena = codec.DescriptorArena.init(scratch[header.field_count + header.argument_count ..]);
    var input: codec.WireInput = .{ .bytes = payload, .position = header.header_bytes, .arena = &arena, .allow_nested = definition.ref.version == schema.nested_version };
    if (header.flags & 2 != 0) event.trace_id = (try input.take(16))[0..16].*;
    if (header.flags & 4 != 0) event.span_id = (try input.take(8))[0..8].*;
    event.message = if (definition.message) |message| message else try input.blob();
    var fields = definition.fields();
    for (scratch[0..header.field_count]) |*field| {
        const expected = (try fields.next()) orelse return error.SchemaMismatch;
        const value = try input.value();
        if (expected.kind_mask & schema.kindMask(codec.valueTag(value)) == 0) return error.SchemaMismatch;
        field.* = .{ .key = expected.key, .value = value };
    }
    var arguments = definition.arguments();
    for (scratch[header.field_count..][0..header.argument_count]) |*argument| {
        const expected = (try arguments.next()) orelse return error.SchemaMismatch;
        const value = try input.value();
        if (expected.kind_mask & schema.kindMask(codec.valueTag(value)) == 0) return error.SchemaMismatch;
        argument.* = .{ .key = expected.key, .value = value };
    }
    if (input.position != payload.len) return error.InvalidLength;
    event.fields = scratch[0..header.field_count];
    event.format_args = scratch[header.field_count..][0..header.argument_count];
    event.tree_validated = true;
    return event;
}

test "referenced event omits static metadata and survives copied schema plus values" {
    const field = @import("field.zig");
    var region: [2 * 1088]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 2, 1024));
    defer registry.deinit();
    var value_bytes = "alice".*;
    const event: Event = .{ .level = .warn, .scope = "http.request", .message = "request {d} for {s}", .message_template = true, .source = @src(), .fields = &.{ field.kv("status", 200), field.kv("password", field.secret("original-secret")) }, .format_args = &.{ field.kv("0", @as(u64, 42)), field.kv("1", &value_bytes) }, .timestamp_ns = -12, .session = 7, .sequence = 123, .channel = 4, .route_mask = 5, .route_fingerprint = 55, .config_generation = 8, .trace_id = @splat(0xab), .span_id = @splat(0xcd), .trace_flags = 1 };
    var metadata_fields: [2]FieldSchema = undefined;
    var metadata_arguments: [2]FieldSchema = undefined;
    const meta = try eventMetadata(event, &metadata_fields, &metadata_arguments);
    const registered = try registry.register(meta);
    const definition = try registry.resolve(registered.ref);
    var payload_buffer: [2048]u8 = undefined;
    const payload = try encodeReference(event, definition, &payload_buffer);
    var inline_buffer: [2048]u8 = undefined;
    try std.testing.expect(payload.len < (try codec.encode(event, &inline_buffer)).len);
    try std.testing.expect(std.mem.find(u8, payload, "http.request") == null);
    try std.testing.expect(std.mem.find(u8, payload, "password") == null);
    try std.testing.expect(std.mem.find(u8, payload, "request {d}") == null);
    try std.testing.expect(std.mem.find(u8, &region, "original-secret") == null);
    const copied_schema = region;
    const copied = (try schema.decodeEntry(copied_schema[0..1088], registered.ref.id - 1, 1024)).?;
    @memset(&region, 0);
    @memset(&value_bytes, 'x');
    var scratch: [4]Field = undefined;
    const restored = try resolve(payload, copied, &scratch);
    try std.testing.expectEqualStrings(event.scope, restored.scope);
    try std.testing.expectEqualStrings(event.message, restored.message);
    try std.testing.expectEqualStrings("alice", restored.format_args[1].value.string);
    try std.testing.expectEqualStrings(field.redacted, restored.fields[1].value.string);
    try std.testing.expectEqual(event.route_fingerprint, restored.route_fingerprint);
    try std.testing.expectEqual(event.trace_id.?, restored.trace_id.?);
    try std.testing.expectEqualStrings(event.source.?.file, restored.source.?.file);
    // Materialized output uses the explicitly versioned self-contained codec.
    const archive_payload = try codec.encode(restored, &inline_buffer);
    try std.testing.expectEqual(@as(u16, codec.version), std.mem.readInt(u16, archive_payload[4..6], .little));
    try std.testing.expectEqualStrings("alice", (try codec.decode(archive_payload, &scratch)).format_args[1].value.string);
}

test "ordinary dynamic message and optional typed metadata roundtrip" {
    const field = @import("field.zig");
    var region: [1088]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 1024));
    defer registry.deinit();
    const metadata: EventMeta = .{ .scope = "plain", .fields = &.{.{ .key = "answer", .kind_mask = schema.kindMask(.unsigned) | schema.kindMask(.null_value) }} };
    const reference = (try registry.register(metadata)).ref;
    const definition = try registry.resolve(reference);
    var event: Event = .{ .level = .info, .scope = "plain", .message = "dynamic first", .fields = &.{field.kv("answer", null)}, .timestamp_ns = 0 };
    var buffer: [1024]u8 = undefined;
    var scratch: [1]Field = undefined;
    try std.testing.expect((try resolve(try encodeReference(event, definition, &buffer), definition, &scratch)).fields[0].value == .null_value);
    event.message = "dynamic second";
    event.fields = &.{field.kv("answer", @as(u64, 42))};
    const restored = try resolve(try encodeReference(event, definition, &buffer), definition, &scratch);
    try std.testing.expectEqualStrings("dynamic second", restored.message);
    try std.testing.expectEqual(@as(u128, 42), restored.fields[0].value.unsigned);
    event.fields = &.{field.kv("answer", true)};
    @memset(&buffer, 0xaa);
    try std.testing.expectError(error.SchemaMismatch, encodeReference(event, definition, &buffer));
    try std.testing.expectEqual(@as(u8, 0xaa), buffer[0]);
}

test "reference codec rejects malformed lengths counts tags and wrong versions" {
    var region: [1088]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 1024));
    defer registry.deinit();
    const event: Event = .{ .level = .info, .scope = "test", .message = "hello", .fields = &.{}, .timestamp_ns = 0 };
    const definition = try registry.resolve((try registry.register(.{ .scope = "test" })).ref);
    var buffer: [1024]u8 = undefined;
    const payload = try encodeReference(event, definition, &buffer);
    for (0..payload.len) |length| try std.testing.expectError(error.Truncated, resolve(payload[0..length], definition, &.{}));
    try std.testing.expectError(error.UnsupportedVersion, codec.decode(payload, &.{}));
    buffer[60] = 1;
    try std.testing.expectError(error.SchemaMismatch, resolve(payload, definition, &.{}));
}

test "reference values retain integer extremes float bits bytes and time wrappers" {
    const field = @import("field.zig");
    const nan_bits: u64 = 0x7ff8000000000042;
    const event: Event = .{ .level = .info, .scope = "typed", .message = "", .timestamp_ns = std.math.minInt(i64), .fields = &.{ field.kv("null", null), field.kv("bool", true), field.kv("min", std.math.minInt(i128)), field.kv("max", std.math.maxInt(u128)), field.kv("nan", @as(f64, @bitCast(nan_bits))), field.kv("minus_zero", @as(f64, -0.0)), field.kv("string", "\xff\x00"), field.kv("bytes", field.bytes("\x00\xff")), field.kv("duration", field.durationNs(std.math.minInt(i64))), field.kv("time", field.timestampNs(std.math.maxInt(i64))) } };
    var region: [1088]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 1024));
    defer registry.deinit();
    var metadata_fields: [10]FieldSchema = undefined;
    const meta = try eventMetadata(event, &metadata_fields, &.{});
    const definition = try registry.resolve((try registry.register(meta)).ref);
    var buffer: [2048]u8 = undefined;
    var scratch: [10]Field = undefined;
    const payload = try encodeReference(event, definition, &buffer);
    const restored = try resolve(payload, definition, &scratch);
    try std.testing.expect(restored.fields[0].value == .null_value);
    try std.testing.expect(restored.fields[1].value.boolean);
    try std.testing.expectEqual(std.math.minInt(i128), restored.fields[2].value.signed);
    try std.testing.expectEqual(std.math.maxInt(u128), restored.fields[3].value.unsigned);
    try std.testing.expectEqual(nan_bits, @as(u64, @bitCast(restored.fields[4].value.float)));
    try std.testing.expectEqual(@as(u64, 1) << 63, @as(u64, @bitCast(restored.fields[5].value.float)));
    try std.testing.expectEqualStrings("\xff\x00", restored.fields[6].value.string);
    try std.testing.expectEqualStrings("\x00\xff", restored.fields[7].value.bytes);
    try std.testing.expectEqual(std.math.minInt(i64), restored.fields[8].value.duration_ns);
    try std.testing.expectEqual(std.math.maxInt(i64), restored.fields[9].value.timestamp_ns);
    // First field starts after the shared header and empty dynamic message.
    buffer[codec.header_size + 4] = 255;
    try std.testing.expectError(error.InvalidTag, resolve(payload, definition, &scratch));
}

test "nested references keep one schema while values sizes and nested keys change" {
    const field = field_module;
    var region: [1088]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 1024));
    defer registry.deinit();
    var key = "child".*;
    var text = "original".*;
    var children = [_]Field{field.kv(&key, @as([]const u8, &text))};
    var values = [_]field.Value{ .{ .group = &children }, field.fromAny(field.bytes("\x00\xff")) };
    var event: Event = .{ .level = .info, .scope = "nested", .message = "", .timestamp_ns = 0, .route_generation = 42, .fields = &.{field.kv("values", field.array(&values))} };
    var metadata: [1]FieldSchema = undefined;
    const meta = try eventMetadata(event, &metadata, &.{});
    const reference = (try registry.register(meta)).ref;
    try std.testing.expectEqual(schema.nested_version, reference.version);
    const definition = try registry.resolve(reference);
    try std.testing.expect(std.mem.find(u8, definition.bytes, "original") == null);
    try std.testing.expect(std.mem.find(u8, definition.bytes, "child") == null);
    const initial_hash = try schema.metadataHash(meta);
    var buffer: [1024]u8 = undefined;
    const first_payload = try encodeReference(event, definition, &buffer);
    var scratch: [codec.decode_scratch_fields]Field = undefined;
    @memset(&key, 'x');
    @memset(&text, 'x');
    children[0] = field.kv("changed", false);
    values = @splat(.null_value);
    const restored = try resolve(first_payload, definition, &scratch);
    try std.testing.expectEqualStrings("child", restored.fields[0].value.array[0].group[0].key);
    try std.testing.expectEqualStrings("original", restored.fields[0].value.array[0].group[0].value.string);
    try std.testing.expectEqual(event.route_generation, restored.route_generation);
    var inline_buffer: [1024]u8 = undefined;
    const materialized = try codec.encode(restored, &inline_buffer);
    try std.testing.expectEqualStrings("original", (try codec.decode(materialized, &scratch)).fields[0].value.array[0].group[0].value.string);

    event.fields = &.{field.kv("values", field.array(&.{ field.fromAny(true), .{ .group = &.{field.kv("other", 12)} }, .{ .array = &.{} } }))};
    const changed_meta = try eventMetadata(event, &metadata, &.{});
    try std.testing.expectEqualSlices(u8, &initial_hash, &try schema.metadataHash(changed_meta));
    try std.testing.expectEqualDeep(reference, (try registry.register(changed_meta)).ref);
    const second = try resolve(try encodeReference(event, definition, &buffer), definition, &scratch);
    try std.testing.expectEqual(@as(usize, 3), second.fields[0].value.array.len);
    try std.testing.expectEqualStrings("other", second.fields[0].value.array[1].group[0].key);
    var small: [1]Field = undefined;
    try std.testing.expectError(error.TooManyFields, resolve(try encodeReference(event, definition, &buffer), definition, &small));
}

test "schema metadata and reference encoding reject invalid nested values" {
    const field = field_module;
    var cycle: [1]field.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    var event: Event = .{ .level = .info, .scope = "nested", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("values", field.array(&cycle))} };
    var metadata: [1]FieldSchema = undefined;
    try std.testing.expectError(error.CyclicValue, eventMetadata(event, &metadata, &.{}));
    var region: [576]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 512));
    defer registry.deinit();
    const reference = (try registry.register(.{ .scope = "nested", .fields = &.{.{ .key = "values", .kind_mask = schema.kindMask(.array) | schema.kindMask(.group) }} })).ref;
    const definition = try registry.resolve(reference);
    var buffer: [1024]u8 = @splat(0xaa);
    try std.testing.expectError(error.CyclicValue, encodeReference(event, definition, &buffer));
    event.fields = &.{field.kv("values", field.group(&.{ field.kv("dup", 1), field.kv("dup", 2) }))};
    try std.testing.expectError(error.DuplicateKey, encodeReference(event, definition, &buffer));
    try std.testing.expectEqual(@as(u8, 0xaa), buffer[0]);
}

test "historical schema payload v2 reads scalar definitions with zero route generation" {
    var region: [576]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 512));
    defer registry.deinit();
    const meta: EventMeta = .{ .scope = "old", .fields = &.{.{ .key = "answer", .kind_mask = schema.kindMask(.unsigned) }} };
    const definition = try registry.resolve((try registry.register(meta)).ref);
    try std.testing.expectEqual(schema.version, definition.ref.version);
    const event: Event = .{ .level = .info, .scope = "old", .message = "dynamic", .timestamp_ns = 0, .fields = &.{field_module.kv("answer", 42)}, .route_fingerprint = 123, .route_generation = 99 };
    var current_buffer: [256]u8 = undefined;
    const current = try encodeReference(event, definition, &current_buffer);
    var old_buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&old_buffer);
    try codec.writeHeader(event, current.len - 8, codec.legacy_reference_version, &writer);
    try writer.writeAll(current[codec.header_size..]);
    var scratch: [1]Field = undefined;
    const restored = try resolve(writer.buffered(), definition, &scratch);
    try std.testing.expectEqual(@as(u64, 0), restored.route_generation);
    try std.testing.expectEqual(event.route_fingerprint, restored.route_fingerprint);
    try std.testing.expectEqual(@as(u128, 42), restored.fields[0].value.unsigned);
}

test "reference size and encoding validate each node once and count only payload keys" {
    const field = field_module;
    const leaves = [_]field.Value{
        .null_value,                          field.fromAny(true),              field.fromAny(@as(i128, -17)),          field.fromAny(@as(u128, 18)),
        field.fromAny(@as(f64, 1.5)),         field.fromAny("hello"),           field.fromAny(field.bytes("\x00\xff")), field.fromAny(field.durationNs(-20)),
        field.fromAny(field.timestampNs(21)), field.fromAny(field.array(&.{})), field.fromAny(field.group(&.{})),
    };
    const event: Event = .{
        .level = .info,
        .scope = "once.reference",
        .message = "{any}",
        .message_template = true,
        .source = @src(),
        .trace_id = @splat(0xab),
        .span_id = @splat(0xcd),
        .timestamp_ns = 0,
        .fields = &.{field.kv("values", field.array(&leaves))},
        .format_args = &.{ field.kv("", true), field.kv("", field.group(&.{field.kv("child", 1)})) },
    };
    var region: [2112]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 2048));
    defer registry.deinit();
    var metadata_fields: [1]FieldSchema = undefined;
    var metadata_args: [2]FieldSchema = undefined;
    const definition = try registry.resolve((try registry.register(try eventMetadata(event, &metadata_fields, &metadata_args))).ref);
    const before_size = field.TestingAudit.visited_values;
    const size = try encodedReferenceSize(event, definition);
    try std.testing.expectEqual(@as(usize, 15), field.TestingAudit.visited_values - before_size);
    // Independent sum: header 84, trace/span 24, array 5+91, arguments 2+31.
    try std.testing.expectEqual(@as(usize, 237), size);
    var buffer: [2048]u8 = undefined;
    const before_encode = field.TestingAudit.visited_values;
    const payload = try encodeReference(event, definition, &buffer);
    try std.testing.expectEqual(@as(usize, 15), field.TestingAudit.visited_values - before_encode);
    try std.testing.expectEqual(size, payload.len);
    var scratch: [codec.decode_scratch_fields]Field = undefined;
    const restored = try resolve(payload, definition, &scratch);
    try std.testing.expectEqualStrings("child", restored.format_args[1].value.group[0].key);
    var expected_buffer: [2048]u8 = undefined;
    var restored_buffer: [2048]u8 = undefined;
    try std.testing.expectEqualSlices(u8, try codec.encode(event, &expected_buffer), try codec.encode(restored, &restored_buffer));
}

test "reference single-pass validation preserves shared node depth and duplicate budgets" {
    var region: [576]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 512));
    defer registry.deinit();
    const definition = try registry.resolve((try registry.register(.{ .scope = "budgets", .fields = &.{.{ .key = "root", .kind_mask = schema.kindMask(.array) | schema.kindMask(.group) }} })).ref);
    const leaves = [_]field_module.Value{.null_value} ** (field_module.max_value_nodes - 1);
    var event: Event = .{ .level = .info, .scope = "budgets", .message = "dynamic", .timestamp_ns = 0, .fields = &.{field_module.kv("root", field_module.array(&leaves))} };
    var buffer: [2048]u8 = undefined;
    const before = field_module.TestingAudit.visited_values;
    _ = try encodeReference(event, definition, &buffer);
    try std.testing.expectEqual(field_module.max_value_nodes, field_module.TestingAudit.visited_values - before);
    @memset(&buffer, 0xa5);
    event.format_args = &.{field_module.kv("", true)};
    try std.testing.expectError(error.TooManyValueNodes, encodeReference(event, definition, &buffer));
    event.format_args = &.{};
    var chain: [field_module.max_value_depth + 1]field_module.Value = undefined;
    chain[0] = .{ .array = &.{} };
    for (1..chain.len) |index| chain[index] = .{ .array = chain[index - 1 .. index] };
    event.fields = &.{field_module.kv("root", chain[field_module.max_value_depth - 1])};
    _ = try encodedReferenceSize(event, definition);
    event.fields = &.{field_module.kv("root", chain[field_module.max_value_depth])};
    try std.testing.expectError(error.ValueTooDeep, encodeReference(event, definition, &buffer));
    event.fields = &.{field_module.kv("root", field_module.group(&.{ field_module.kv("dup", true), field_module.kv("dup", false) }))};
    try std.testing.expectError(error.DuplicateKey, encodeReference(event, definition, &buffer));
    try std.testing.expect(std.mem.allEqual(u8, &buffer, 0xa5));
}

test "reference length overflow follows tree shape and level errors with zero output" {
    var region: [576]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 512));
    defer registry.deinit();
    const definition = try registry.resolve((try registry.register(.{ .scope = "dynamic", .fields = &.{ .{ .key = "big", .kind_mask = schema.kindMask(.string) }, .{ .key = "tree", .kind_mask = schema.kindMask(.array) } } })).ref);
    // Size checks and expected failures never dereference this synthetic span.
    const huge = @as([*]const u8, @ptrCast("x"))[0..std.math.maxInt(u32)];
    var cycle: [1]field_module.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    var event: Event = .{ .level = .info, .scope = "dynamic", .message = huge, .timestamp_ns = 0, .fields = &.{ field_module.kv("big", huge), field_module.kv("tree", field_module.array(&cycle)) } };
    var buffer: [128]u8 = @splat(0xa5);
    try std.testing.expectError(error.CyclicValue, encodeReference(event, definition, &buffer));
    event.fields = &.{ field_module.kv("big", huge), field_module.kv("tree", field_module.array(&.{})) };
    event.scope = "wrong";
    try std.testing.expectError(error.SchemaMismatch, encodeReference(event, definition, &buffer));
    event.scope = "dynamic";
    event.level = .off;
    try std.testing.expectError(error.InvalidLevel, encodeReference(event, definition, &buffer));
    event.level = .info;
    try std.testing.expectError(error.TooLarge, encodeReference(event, definition, &buffer));
    event.message = "small";
    event.fields = &.{ field_module.kv("big", "small"), field_module.kv("tree", field_module.array(&.{})) };
    const size = try encodedReferenceSize(event, definition);
    try std.testing.expectError(error.BufferTooSmall, encodeReference(event, definition, buffer[0 .. size - 1]));
    try std.testing.expect(std.mem.allEqual(u8, &buffer, 0xa5));
}
