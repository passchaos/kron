//! Immutable type-only event metadata for explicit schema registration.
//! Values, dynamic field keys, and custom formatters belong to runtime prewarm.
const std = @import("std");
const field_module = @import("../core/field.zig");
const format_module = @import("format.zig");
const schema_module = @import("../journal/schema.zig");

pub const EventMeta = schema_module.EventMeta;
pub const FieldSchema = schema_module.FieldSchema;

/// All slices refer to permanent comptime storage. Optional types admit both
/// null and their captured payload kinds, so changing values requires no new
/// metadata entry. Untyped integer constants admit signed and unsigned capture
/// because their type alone does not reveal the value's sign.
/// Registration must account for configured context and redaction, which can
/// change the final field keys or captured kinds before submission.
pub fn metadata(
    comptime scope: []const u8,
    comptime source: ?std.builtin.SourceLocation,
    comptime template: []const u8,
    comptime Args: type,
    comptime Fields: type,
) EventMeta {
    format_module.validate(template, Args);
    const result: EventMeta = .{
        .scope = scope,
        .source = source,
        .message = template,
        .message_template = true,
        .fields = comptime fieldMetadata(Fields),
        .format_args = comptime argumentMetadata(Args),
    };
    comptime validateMetadata(result);
    return result;
}

/// A literal is part of immutable schema identity. Null leaves an ordinary
/// dynamic message to be copied into each event's payload instead.
pub fn metadataForMessage(
    comptime scope: []const u8,
    comptime source: ?std.builtin.SourceLocation,
    comptime Fields: type,
    comptime literal: ?[]const u8,
) EventMeta {
    const result: EventMeta = .{
        .scope = scope,
        .source = source,
        .message = literal,
        .fields = comptime fieldMetadata(Fields),
    };
    comptime validateMetadata(result);
    return result;
}

fn fieldMetadata(comptime Fields: type) []const FieldSchema {
    const info = switch (@typeInfo(Fields)) {
        .@"struct" => |info| info,
        else => @compileError("kron static schema fields require a named struct; dynamic Field slices require runtime value prewarmSchema"),
    };
    if (info.is_tuple and info.fields.len != 0)
        @compileError("kron static schema fields require a named struct; Field tuples require runtime value prewarmSchema");
    if (info.fields.len > schema_module.max_fields)
        @compileError("kron static schema exceeds its 64-field budget");
    const entries = comptime blk: {
        var result: [info.fields.len]FieldSchema = undefined;
        for (info.fields, 0..) |member, i| {
            result[i] = .{ .key = member.name, .kind_mask = typeMask(member.type) };
        }
        break :blk result;
    };
    return &entries;
}

fn argumentMetadata(comptime Args: type) []const FieldSchema {
    // format.validate has already checked the argument shape, count, syntax,
    // specifiers, and captured kinds. Keys match format.capture exactly.
    const members = @typeInfo(Args).@"struct".fields;
    const entries = comptime blk: {
        var result: [members.len]FieldSchema = undefined;
        for (members, 0..) |member, i| {
            result[i] = .{ .key = member.name, .kind_mask = typeMask(member.type) };
        }
        break :blk result;
    };
    return &entries;
}

fn typeMask(comptime T: type) u16 {
    if (T == field_module.Array) return schema_module.kindMask(.array);
    if (T == field_module.Group) return schema_module.kindMask(.group);
    switch (@typeInfo(T)) {
        .optional => |info| return typeMask(info.child) | schema_module.kindMask(.null_value),
        else => {},
    }
    const kind = format_module.argumentKind(T) catch
        @compileError("kron static schema cannot capture " ++ @typeName(T) ++ "; use supported scalar types (integers <=128 bits, floats <=64 bits) or an explicit borrowed byte slice");
    return switch (kind) {
        .null_value => schema_module.kindMask(.null_value),
        .boolean => schema_module.kindMask(.boolean),
        .signed => schema_module.kindMask(.signed),
        .unsigned => schema_module.kindMask(.unsigned),
        .integer => schema_module.kindMask(.signed) | schema_module.kindMask(.unsigned),
        .float => schema_module.kindMask(.float),
        .string => schema_module.kindMask(.string),
        .bytes => schema_module.kindMask(.bytes),
        .duration_ns => schema_module.kindMask(.duration_ns),
        .timestamp_ns => schema_module.kindMask(.timestamp_ns),
        .array => schema_module.kindMask(.array),
        .group => schema_module.kindMask(.group),
        .dynamic => schema_module.all_kind_mask,
    };
}

fn validateMetadata(comptime meta: EventMeta) void {
    @setEvalBranchQuota(100_000);
    _ = schema_module.encodedMetadataSize(meta) catch |err|
        @compileError("kron static schema: " ++ @errorName(err));
}

test "static schema optional and dynamic masks contain every supported capture kind" {
    const Kinds = struct {
        signed: ?i128,
        unsigned: u128,
        dynamic: field_module.Value,
        maybe_dynamic: ?field_module.Value,
        boolean: bool,
        float: f64,
        text: []const u8,
        mutable_text: []u8,
        bytes: field_module.Bytes,
        secret: field_module.Secret,
        duration: field_module.Duration,
        timestamp: field_module.Timestamp,
        tag: enum { first, second },
        failure: error{Oops},
        absent: @TypeOf(null),
        string_literal: *const [3:0]u8,
    };
    const meta = comptime metadataForMessage("typed", null, Kinds, null);
    try std.testing.expectEqual(@as(usize, 16), meta.fields.len);
    try std.testing.expectEqual(schema_module.kindMask(.signed) | schema_module.kindMask(.null_value), meta.fields[0].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.unsigned), meta.fields[1].kind_mask);
    try std.testing.expectEqual(schema_module.all_kind_mask, meta.fields[2].kind_mask);
    try std.testing.expectEqual(schema_module.all_kind_mask, meta.fields[3].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.boolean), meta.fields[4].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.float), meta.fields[5].kind_mask);
    for ([_]usize{ 6, 7, 9, 12, 13, 15 }) |i| try std.testing.expectEqual(schema_module.kindMask(.string), meta.fields[i].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.bytes), meta.fields[8].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.duration_ns), meta.fields[10].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.timestamp_ns), meta.fields[11].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.null_value), meta.fields[14].kind_mask);
}

test "static schema format argument keys source and integer masks are type based" {
    const source: std.builtin.SourceLocation = .{
        .module = "app",
        .file = "worker.zig",
        .fn_name = "handle",
        .line = 42,
        .column = 7,
    };
    const Args = struct { count: u64, optional: ?i8, name: []const u8 };
    const Fields = struct { request_id: u128, ready: bool };
    const meta = comptime metadata("http.server", source, "{[count]d} {[optional]d} {[name]s}", Args, Fields);
    try std.testing.expectEqualStrings("http.server", meta.scope);
    try std.testing.expectEqualStrings("{[count]d} {[optional]d} {[name]s}", meta.message.?);
    try std.testing.expect(meta.message_template);
    try std.testing.expectEqualStrings("worker.zig", meta.source.?.file);
    try std.testing.expectEqualStrings("handle", meta.source.?.fn_name);
    try std.testing.expectEqual(@as(u32, 42), meta.source.?.line);
    try std.testing.expectEqualStrings("request_id", meta.fields[0].key);
    try std.testing.expectEqualStrings("count", meta.format_args[0].key);
    try std.testing.expectEqualStrings("optional", meta.format_args[1].key);
    try std.testing.expectEqual(schema_module.kindMask(.signed) | schema_module.kindMask(.null_value), meta.format_args[1].kind_mask);
    const integers = comptime metadata("ints", null, "{d} {d}", @TypeOf(.{ 1, -1 }), @TypeOf(.{ .constant = 1 }));
    try std.testing.expectEqualStrings("0", integers.format_args[0].key);
    try std.testing.expectEqualStrings("1", integers.format_args[1].key);
    for (integers.format_args) |argument| try std.testing.expectEqual(schema_module.kindMask(.signed) | schema_module.kindMask(.unsigned), argument.kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.signed) | schema_module.kindMask(.unsigned), integers.fields[0].kind_mask);
    const minimal = comptime metadataForMessage("small", null, struct { signed: i1, unsigned: u0 }, null);
    try std.testing.expectEqual(schema_module.kindMask(.signed), minimal.fields[0].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.unsigned), minimal.fields[1].kind_mask);
}

test "static schema ordinary literals dynamic messages and empty metadata remain distinct" {
    const NoFields = @TypeOf(.{});
    const literal = comptime metadataForMessage("plain", null, NoFields, "literal {braces}");
    const dynamic = comptime metadataForMessage("plain", null, NoFields, null);
    const empty_literal = comptime metadataForMessage("plain", null, struct {}, "");
    const formatted = comptime metadata("plain", null, "escaped {{braces}}", NoFields, NoFields);
    try std.testing.expectEqualStrings("literal {braces}", literal.message.?);
    try std.testing.expect(!literal.message_template);
    try std.testing.expect(dynamic.message == null);
    try std.testing.expect(!dynamic.message_template);
    try std.testing.expectEqualStrings("", empty_literal.message.?);
    try std.testing.expect(formatted.message_template);
    try std.testing.expectEqual(@as(usize, 0), literal.fields.len);
    try std.testing.expectEqual(@as(usize, 0), formatted.format_args.len);
    const literal_hash = try schema_module.metadataHash(literal);
    try std.testing.expect(!std.mem.eql(u8, &literal_hash, &try schema_module.metadataHash(dynamic)));
    try std.testing.expect(!std.mem.eql(u8, &literal_hash, &try schema_module.metadataHash(formatted)));
}

test "static schema optional null and full-width values reuse one registered definition" {
    const schema_codec = @import("../core/schema_codec.zig");
    const Event = @import("../core/event.zig").Event;
    const Args = struct { value: ?u128 };
    const Fields = struct { answer: ?i128 };
    const template = "{[value]d}";
    const meta = comptime metadata("optional", null, template, Args, Fields);
    var region: [576]u8 align(64) = @splat(0);
    var registry = try schema_module.Registry.init(std.testing.allocator, std.testing.io, &region, try schema_module.layout(4096, 1, 512));
    defer registry.deinit();
    const reference = (try registry.register(meta)).ref;
    const definition = try registry.resolve(reference);
    var captured_arguments: [1]field_module.Field = undefined;
    var event: Event = .{
        .level = .info,
        .scope = "optional",
        .message = template,
        .message_template = true,
        .timestamp_ns = 0,
        .fields = &.{field_module.kv("answer", @as(?i128, null))},
        .format_args = try format_module.capture(template, Args{ .value = null }, &captured_arguments),
    };
    var buffer: [512]u8 = undefined;
    var scratch: [2]field_module.Field = undefined;
    const absent = try schema_codec.resolve(try schema_codec.encodeReference(event, definition, &buffer), definition, &scratch);
    try std.testing.expect(absent.fields[0].value == .null_value);
    try std.testing.expect(absent.format_args[0].value == .null_value);
    event.fields = &.{field_module.kv("answer", @as(?i128, std.math.minInt(i128)))};
    event.format_args = try format_module.capture(template, Args{ .value = std.math.maxInt(u128) }, &captured_arguments);
    const present = try schema_codec.resolve(try schema_codec.encodeReference(event, definition, &buffer), definition, &scratch);
    try std.testing.expectEqual(std.math.minInt(i128), present.fields[0].value.signed);
    try std.testing.expectEqual(std.math.maxInt(u128), present.format_args[0].value.unsigned);
    try std.testing.expectEqualDeep(reference, (try registry.register(meta)).ref);
}

test "static nested wrapper metadata records only top level type masks" {
    const Fields = struct { values: field_module.Array, attributes: ?field_module.Group, dynamic: field_module.Value };
    const meta = comptime metadataForMessage("nested", null, Fields, null);
    try std.testing.expectEqual(schema_module.kindMask(.array), meta.fields[0].kind_mask);
    try std.testing.expectEqual(schema_module.kindMask(.group) | schema_module.kindMask(.null_value), meta.fields[1].kind_mask);
    try std.testing.expectEqual(schema_module.all_kind_mask, meta.fields[2].kind_mask);
    try std.testing.expectEqual(schema_module.nested_version, schema_module.metadataVersion(meta));
}
