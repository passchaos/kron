//! Immutable compile-time callsite metadata. Filter/cache decisions belong to
//! each runtime, so a descriptor carries no shared mutable configuration.
const std = @import("std");
const format = @import("format.zig");
pub const Level = @import("../core/level.zig").Level;
pub const ArgKind = format.ArgKind;

pub const ArgSchema = struct {
    key: []const u8,
    kind: ArgKind,
    nullable: bool = false,
};

pub const Descriptor = struct {
    source: std.builtin.SourceLocation,
    level: Level,
    format: []const u8,
    arg_schema: []const ArgSchema,
    schema_fingerprint: u64,
};

/// The returned slices refer to immutable comptime storage. Schema identity
/// depends on stable captured kinds/keys, never on addresses or runtime ids.
pub fn descriptor(
    comptime source: std.builtin.SourceLocation,
    comptime level: Level,
    comptime template: []const u8,
    comptime Args: type,
) Descriptor {
    format.validate(template, Args);
    const schema = comptime argumentSchema(Args);
    return .{
        .source = source,
        .level = level,
        .format = template,
        .arg_schema = schema,
        .schema_fingerprint = comptime schemaFingerprint(schema),
    };
}

pub fn argumentSchema(comptime Args: type) []const ArgSchema {
    const members = switch (@typeInfo(Args)) {
        .@"struct" => |info| info.fields,
        else => @compileError("kron format arguments must be a tuple or named struct"),
    };
    const schema = comptime blk: {
        var result: [members.len]ArgSchema = undefined;
        for (members, 0..) |member, i| {
            result[i] = .{
                .key = member.name,
                .kind = format.argumentKind(member.type) catch @compileError("unsupported kron format argument type: " ++ @typeName(member.type)),
                .nullable = isNullable(member.type),
            };
        }
        break :blk result;
    };
    return &schema;
}

fn isNullable(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional, .null => true,
        else => T == @import("../core/field.zig").Value,
    };
}

/// FNV-1a over a versioned, length-delimited representation. Integer kind ids
/// are explicit to keep fingerprints stable when declarations are reordered.
pub fn schemaFingerprint(schema: []const ArgSchema) u64 {
    var hash: u64 = 14695981039346656037;
    hashBytes(&hash, "kron-format-schema-v1");
    hashNumber(&hash, schema.len);
    for (schema) |argument| {
        hashNumber(&hash, argument.key.len);
        hashBytes(&hash, argument.key);
        hashByte(&hash, kindId(argument.kind));
        hashByte(&hash, @intFromBool(argument.nullable));
    }
    return hash;
}

fn kindId(kind: ArgKind) u8 {
    return switch (kind) {
        .null_value => 0,
        .boolean => 1,
        .signed => 2,
        .unsigned => 3,
        .float => 4,
        .string => 5,
        .bytes => 6,
        .duration_ns => 7,
        .timestamp_ns => 8,
        .array => 11,
        .group => 12,
        .dynamic => 9,
        .integer => 10,
    };
}

fn hashNumber(hash: *u64, value: usize) void {
    var number: u64 = @intCast(value);
    for (0..8) |_| {
        hashByte(hash, @truncate(number));
        number >>= 8;
    }
}

fn hashBytes(hash: *u64, bytes: []const u8) void {
    for (bytes) |byte| hashByte(hash, byte);
}

fn hashByte(hash: *u64, byte: u8) void {
    hash.* = (hash.* ^ byte) *% 1099511628211;
}

test "descriptor validates format and stores immutable argument schema" {
    const Args = @TypeOf(.{ .count = @as(u32, 1), .name = @as([]const u8, "name"), .optional = @as(?i64, null) });
    const site = comptime descriptor(@src(), .info, "{[count]d} {[name]s} {[optional]d}", Args);
    try std.testing.expectEqual(Level.info, site.level);
    try std.testing.expectEqualStrings("{[count]d} {[name]s} {[optional]d}", site.format);
    try std.testing.expectEqual(@as(usize, 3), site.arg_schema.len);
    try std.testing.expectEqualStrings("count", site.arg_schema[0].key);
    try std.testing.expectEqual(ArgKind.unsigned, site.arg_schema[0].kind);
    try std.testing.expect(site.arg_schema[2].nullable);
    try std.testing.expectEqual(schemaFingerprint(site.arg_schema), site.schema_fingerprint);
}

test "schema fingerprints are independent of source location and integer width" {
    const first = comptime descriptor(@src(), .info, "{d}", @TypeOf(.{@as(u8, 1)}));
    const second = comptime descriptor(@src(), .debug, "value={x}", @TypeOf(.{@as(u64, 2)}));
    const signed = comptime descriptor(@src(), .info, "{d}", @TypeOf(.{@as(i64, 2)}));
    const optional = comptime descriptor(@src(), .info, "{d}", @TypeOf(.{@as(?u8, 2)}));
    try std.testing.expectEqual(first.schema_fingerprint, second.schema_fingerprint);
    try std.testing.expect(first.schema_fingerprint != signed.schema_fingerprint);
    try std.testing.expect(first.schema_fingerprint != optional.schema_fingerprint);
}
