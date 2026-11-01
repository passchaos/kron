const std = @import("std");
const field = @import("field.zig");
const Event = @import("event.zig").Event;
const Level = @import("level.zig").Level;
const SizeVisitor = @import("wire_size.zig").SizeVisitor;
const wire = @import("wire_write.zig");

/// Stable little-endian wire format, independent of Zig struct layout. The
/// journal owns commit/checksum framing; this codec owns complete event bytes.
/// New self-contained payloads use version 4 with an 84-byte header. Historical
/// version 1 has a 68-byte header without route_fingerprint. Historical
/// self-contained v3 and schema-referenced v2 use 76 bytes. Schema-referenced
/// v5 shares the v4 header and carries route_generation.
/// Header: magic[4], version:u16, flags:u16, length:u32, level:u8,
/// trace_flags:u8, reserved[2],
/// timestamp:i64, session:u64, sequence:u64, channel:u32, route_mask:u64,
/// config_generation:u64, field_count:u32, argument_count:u32,
/// route_fingerprint:u64, route_generation:u64 (v4/v5).
/// Then scope/message length-prefixed bytes, optional trace/span/source, fields,
/// and formatting arguments. Source strings include an explicit NUL terminator.
pub const magic = "KRNE";
pub const version: u16 = 4;
pub const previous_version: u16 = 3;
/// Enough descriptor storage for every event admitted by the node budget.
pub const decode_scratch_fields: usize = field.max_value_nodes;
pub const legacy_version: u16 = 1;
pub const legacy_reference_version: u16 = 2;
pub const reference_version: u16 = 5;
pub const legacy_header_size: usize = 68;
pub const previous_header_size: usize = 76;
pub const header_size: usize = 84;

pub const EncodeError = error{ BufferTooSmall, TooLarge, InvalidLevel } || field.ValidationError;
pub const DecodeError = error{ Truncated, InvalidMagic, UnsupportedVersion, InvalidLength, InvalidFlags, InvalidLevel, InvalidTag, InvalidValue, TooManyFields, DuplicateKey, ValueTooDeep, TooManyValueNodes };

pub const ValueTag = wire.ValueTag;
pub const valueTag = wire.valueTag;
const Tag = ValueTag;

pub fn encodedSize(event: Event) EncodeError!usize {
    _ = try encodeLevel(event.level);
    return measure(event);
}

/// Validate the complete borrowed tree and return the exact wire size without
/// rejecting the event level. Admission uses this before route predicates and
/// reuses the result for the accepted write; public encode keeps level-first
/// error ordering.
pub fn measure(event: Event) EncodeError!usize {
    var visitor: SizeVisitor = .{ .total = header_size };
    visitor.blob(event.scope.len, false);
    visitor.blob(event.message.len, false);
    if (event.trace_id != null) visitor.add(16);
    if (event.span_id != null) visitor.add(8);
    if (event.source) |source| {
        visitor.blob(source.module.len, true);
        visitor.blob(source.file.len, true);
        visitor.blob(source.fn_name.len, true);
        visitor.add(8);
    }
    var validator: field.ValueValidator = .{};
    try validator.fieldsWith(event.fields, &visitor);
    try validator.argumentsWith(event.format_args, &visitor);
    return visitor.result();
}

/// Wire size of the value tag and payload, excluding an attribute key.
pub fn encodedValueSize(value: field.Value) (error{TooLarge} || field.ValidationError)!usize {
    var validator: field.ValueValidator = .{};
    var visitor: SizeVisitor = .{};
    try validator.valueWith(value, &visitor);
    return visitor.result();
}

/// All validation occurs before touching destination. Typed numbers are copied
/// in binary form; formatting happens only when a collector invokes an encoder.
pub fn encode(event: Event, destination: []u8) EncodeError![]const u8 {
    return encodeSized(event, try encodedSize(event), destination);
}

/// Writes an event whose exact size was measured for the same unchanged event.
/// Level and capacity checks retain the public error order; the caller must not
/// use a size measured for different fields, arguments, scope, message, trace,
/// source or format-argument values.
pub fn encodeSized(event: Event, size: usize, destination: []u8) EncodeError![]const u8 {
    _ = try encodeLevel(event.level);
    if (destination.len < size) return error.BufferTooSmall;
    var output: Output = .{ .bytes = destination[0..size] };
    try writeEvent(&output, event, size);
    std.debug.assert(output.position == size);
    return output.bytes;
}

pub const WriteError = EncodeError || std.Io.Writer.Error;

/// Streams the identical wire bytes without a complete-record scratch buffer.
/// This is for collector/archive output; it does not format typed values.
pub fn writeTo(event: Event, writer: *std.Io.Writer) WriteError!void {
    const size = try encodedSize(event);
    var output: StreamOutput = .{ .writer = writer };
    try writeEvent(&output, event, size);
}

/// Validate/measure once, then hash and emit identical self-contained bytes.
/// The framing function receives only size/CRC and returns a fixed header.
/// No unchecked writer or reusable validation token escapes this call. All
/// Event backing storage must remain stable, including during Writer callbacks.
pub fn writeFramed(event: Event, writer: *std.Io.Writer, comptime framing: anytype) WriteError!void {
    const size = try encodedSize(event);
    var hash_buffer: [256]u8 = undefined;
    var hashing = std.Io.Writer.Hashing(std.hash.Crc32).initHasher(.init(), &hash_buffer);
    var hash_output: StreamOutput = .{ .writer = &hashing.writer };
    try writeEvent(&hash_output, event, size);
    try hashing.writer.flush();
    const header = framing(@as(u32, @intCast(size)), hashing.hasher.final());
    try writer.writeAll(&header);
    var output: StreamOutput = .{ .writer = writer };
    try writeEvent(&output, event, size);
}

/// Shares only the stable event header with other versioned payload codecs.
pub fn writeHeader(event: Event, size: usize, wire_version: u16, writer: *std.Io.Writer) WriteError!void {
    _ = try encodeLevel(event.level);
    const bytes = headerBytesForVersion(wire_version) catch return error.TooLarge;
    if (size < bytes or size > std.math.maxInt(u32) or event.fields.len > std.math.maxInt(u32) or event.format_args.len > std.math.maxInt(u32)) return error.TooLarge;
    var output: StreamOutput = .{ .writer = writer };
    try writeHeaderTo(&output, event, size, wire_version);
}

fn writeHeaderTo(output: anytype, event: Event, size: usize, wire_version: u16) @TypeOf(output.*).Error!void {
    try output.put(magic);
    try output.int(u16, wire_version);
    const flags: u16 = @as(u16, @intFromBool(event.source != null)) |
        (@as(u16, @intFromBool(event.trace_id != null)) << 1) |
        (@as(u16, @intFromBool(event.span_id != null)) << 2) |
        (@as(u16, @intFromBool(event.message_template)) << 3);
    try output.int(u16, flags);
    try output.int(u32, @intCast(size));
    try output.int(u8, encodeLevel(event.level) catch unreachable); // validated before writing
    try output.int(u8, event.trace_flags);
    try output.put(&.{ 0, 0 });
    try output.int(i64, event.timestamp_ns);
    try output.int(u64, event.session);
    try output.int(u64, event.sequence);
    try output.int(u32, event.channel);
    try output.int(u64, event.route_mask);
    try output.int(u64, event.config_generation);
    try output.int(u32, @intCast(event.fields.len));
    try output.int(u32, @intCast(event.format_args.len));
    if (wire_version != legacy_version) try output.int(u64, event.route_fingerprint);
    if (wire_version == version or wire_version == reference_version) try output.int(u64, event.route_generation);
}

fn writeEvent(output: anytype, event: Event, size: usize) @TypeOf(output.*).Error!void {
    try writeHeaderTo(output, event, size, version);
    try writeBlob(output, event.scope);
    try writeBlob(output, event.message);
    if (event.trace_id) |id| try output.put(&id);
    if (event.span_id) |id| try output.put(&id);
    if (event.source) |source| {
        try writeTerminated(output, source.module);
        try writeTerminated(output, source.file);
        try writeTerminated(output, source.fn_name);
        try output.int(u32, source.line);
        try output.int(u32, source.column);
    }
    for (event.fields) |entry| try writeField(output, entry);
    for (event.format_args) |argument| try writeField(output, argument);
}

/// Numeric header shared by the inline and referenced payload codecs. The
/// payload codec must supply scope, message and fields before exposing Event.
pub const EventHeader = struct {
    event: Event,
    flags: u16,
    field_count: usize,
    argument_count: usize,
    header_bytes: usize,
};

fn headerBytesForVersion(wire_version: u16) error{UnsupportedVersion}!usize {
    return switch (wire_version) {
        legacy_version => legacy_header_size,
        legacy_reference_version, previous_version => previous_header_size,
        reference_version, version => header_size,
        else => error.UnsupportedVersion,
    };
}

pub fn readHeader(payload: []const u8, wire_version: u16) DecodeError!EventHeader {
    var input: WireInput = .{ .bytes = payload };
    if (!std.mem.eql(u8, try input.take(4), magic)) return error.InvalidMagic;
    if (try input.int(u16) != wire_version) return error.UnsupportedVersion;
    const bytes = try headerBytesForVersion(wire_version);
    const flags = try input.int(u16);
    if (flags & ~@as(u16, 15) != 0) return error.InvalidFlags;
    const length = try input.int(u32);
    if (length < bytes) return error.InvalidLength;
    if (length > payload.len) return error.Truncated;
    if (length != payload.len) return error.InvalidLength;
    const level = try decodeLevel(try input.int(u8));
    const trace_flags = try input.int(u8);
    for (try input.take(2)) |reserved| if (reserved != 0) return error.InvalidFlags;
    var event: Event = .{
        .level = level,
        .scope = undefined,
        .message = undefined,
        .fields = undefined,
        .message_template = flags & 8 != 0,
        .trace_flags = trace_flags,
        .timestamp_ns = try input.int(i64),
        .session = try input.int(u64),
        .sequence = try input.int(u64),
        .channel = try input.int(u32),
        .route_mask = try input.int(u64),
        .config_generation = try input.int(u64),
    };
    const count: usize = try input.int(u32);
    const argument_count: usize = try input.int(u32);
    event.route_fingerprint = if (wire_version == legacy_version) 0 else try input.int(u64);
    event.route_generation = if (wire_version == version or wire_version == reference_version) try input.int(u64) else 0;
    return .{ .event = event, .flags = flags, .field_count = count, .argument_count = argument_count, .header_bytes = bytes };
}

/// Returned byte/source slices borrow payload. Attributes and arguments occupy
/// the front of scratch; nested descriptors use its remaining aligned bytes.
/// Use decode_scratch_fields entries for every admitted event. A smaller arena
/// returns TooManyFields. No decode-time allocation or persisted pointer exists.
pub fn decode(payload: []const u8, scratch: []field.Field) DecodeError!Event {
    var prefix: WireInput = .{ .bytes = payload };
    if (!std.mem.eql(u8, try prefix.take(4), magic)) return error.InvalidMagic;
    const wire_version = try prefix.int(u16);
    if (wire_version != legacy_version and wire_version != previous_version and wire_version != version) return error.UnsupportedVersion;
    const header = try readHeader(payload, wire_version);
    var event = header.event;
    const flags = header.flags;
    const count = header.field_count;
    const argument_count = header.argument_count;
    if (count > scratch.len or argument_count > scratch.len - count) return error.TooManyFields;
    var arena = DescriptorArena.init(scratch[count + argument_count ..]);
    var input: Input = .{ .bytes = payload, .position = header.header_bytes, .arena = &arena, .allow_nested = wire_version == version };
    event.scope = try input.blob();
    event.message = try input.blob();
    if (flags & 2 != 0) event.trace_id = (try input.take(16))[0..16].*;
    if (flags & 4 != 0) event.span_id = (try input.take(8))[0..8].*;
    if (flags & 1 != 0) event.source = .{
        .module = try input.terminated(),
        .file = try input.terminated(),
        .fn_name = try input.terminated(),
        .line = try input.int(u32),
        .column = try input.int(u32),
    };
    for (scratch[0..count], 0..) |*entry, index| {
        entry.* = try input.fieldValue();
        try field.checkUnique(scratch[0..index], entry.key);
    }
    for (scratch[count..][0..argument_count]) |*argument| argument.* = try input.fieldValue();
    if (input.position != payload.len) return error.InvalidLength;
    event.fields = scratch[0..count];
    event.format_args = scratch[count..][0..argument_count];
    event.tree_validated = true;
    return event;
}

fn encodeLevel(level: Level) error{InvalidLevel}!u8 {
    return switch (level) {
        .trace => 0,
        .debug => 1,
        .info => 2,
        .warn => 3,
        .err => 4,
        .fatal => 5,
        .off => error.InvalidLevel,
    };
}

fn decodeLevel(raw: u8) error{InvalidLevel}!Level {
    return switch (raw) {
        0 => .trace,
        1 => .debug,
        2 => .info,
        3 => .warn,
        4 => .err,
        5 => .fatal,
        else => error.InvalidLevel,
    };
}

const Output = struct {
    pub const Error = error{};
    bytes: []u8,
    position: usize = 0,

    pub fn put(self: *Output, bytes: []const u8) Error!void {
        @memcpy(self.bytes[self.position..][0..bytes.len], bytes);
        self.position += bytes.len;
    }

    pub fn int(self: *Output, comptime T: type, value: T) Error!void {
        std.mem.writeInt(T, self.bytes[self.position..][0..@sizeOf(T)], value, .little);
        self.position += @sizeOf(T);
    }
};

const StreamOutput = wire.StreamOutput;
const writeBlob = wire.writeBlob;
const writeTerminated = wire.writeTerminated;
const writeField = wire.writeField;
const writeValueTo = wire.writeValueTo;

/// Emits scalar tags 0..8 and explicit nested tags 9/10, without a key.
pub fn writeValue(writer: *std.Io.Writer, value: field.Value) std.Io.Writer.Error!void {
    _ = encodedValueSize(value) catch return error.WriteFailed;
    var output: StreamOutput = .{ .writer = writer };
    try writeValueTo(&output, value);
}

test "public value writer still validates invalid nested input before output" {
    var bytes: [256]u8 = @splat(0xa5);
    var output = std.Io.Writer.fixed(&bytes);
    var cycle: [1]field.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    try std.testing.expectError(error.WriteFailed, writeValue(&output, field.fromAny(field.array(&cycle))));
    const duplicate = field.fromAny(field.group(&.{ field.kv("key", 1), field.kv("key", 2) }));
    try std.testing.expectError(error.WriteFailed, writeValue(&output, duplicate));
    const huge = @as([*]const u8, @ptrCast("x"))[0..std.math.maxInt(u32)];
    try std.testing.expectError(error.WriteFailed, writeValue(&output, field.fromAny(huge)));
    try std.testing.expectEqual(@as(usize, 0), output.end);
    try std.testing.expect(std.mem.allEqual(u8, &bytes, 0xa5));
    const value = field.fromAny(field.group(&.{field.kv("key", field.array(&.{ field.fromAny(true), .null_value }))}));
    const before = field.TestingAudit.visited_values;
    try writeValue(&output, value);
    try std.testing.expectEqual(@as(usize, 4), field.TestingAudit.visited_values - before);
    try std.testing.expectEqual(try encodedValueSize(value), output.end);
}

const Input = WireInput;

/// Uses the unused part of caller Field scratch for nested descriptors. Byte
/// data continues borrowing payload. Exhaustion is reported as TooManyFields.
pub const DescriptorArena = struct {
    bytes: []u8,
    position: usize = 0,

    pub fn init(scratch: []field.Field) DescriptorArena {
        comptime std.debug.assert(@alignOf(field.Field) >= @alignOf(field.Value));
        comptime std.debug.assert(@sizeOf(field.Field) >= @sizeOf(field.Value));
        return .{ .bytes = std.mem.sliceAsBytes(scratch) };
    }

    pub fn allocate(self: *DescriptorArena, comptime T: type, count: usize) error{TooManyFields}![]T {
        const length = std.math.mul(usize, count, @sizeOf(T)) catch return error.TooManyFields;
        const aligned = std.mem.alignForward(usize, self.position, @alignOf(T));
        if (aligned > self.bytes.len or length > self.bytes.len - aligned) return error.TooManyFields;
        const result: [*]T = @ptrCast(@alignCast(self.bytes[aligned..].ptr));
        self.position = aligned + length;
        return result[0..count];
    }
};

pub const WireInput = struct {
    bytes: []const u8,
    position: usize = 0,
    arena: ?*DescriptorArena = null,
    allow_nested: bool = false,
    nodes: usize = 0,
    depth: usize = 0,

    pub fn take(self: *Input, length: usize) error{Truncated}![]const u8 {
        if (self.position > self.bytes.len or length > self.bytes.len - self.position) return error.Truncated;
        const result = self.bytes[self.position..][0..length];
        self.position += length;
        return result;
    }

    pub fn int(self: *Input, comptime T: type) error{Truncated}!T {
        return std.mem.readInt(T, (try self.take(@sizeOf(T)))[0..@sizeOf(T)], .little);
    }

    pub fn blob(self: *Input) error{Truncated}![]const u8 {
        const length = try self.int(u32);
        return self.take(length);
    }

    pub fn terminated(self: *Input) error{ Truncated, InvalidValue }![:0]const u8 {
        const length = try self.int(u32);
        const start = self.position;
        _ = try self.take(length);
        if (try self.int(u8) != 0) return error.InvalidValue;
        return self.bytes[start..][0..length :0];
    }

    fn fieldValue(self: *Input) DecodeError!field.Field {
        const key = try self.blob();
        return .{ .key = key, .value = try self.value() };
    }

    pub fn value(self: *Input) DecodeError!field.Value {
        if (self.nodes == field.max_value_nodes) return error.TooManyValueNodes;
        self.nodes += 1;
        const raw = try self.int(u8);
        const tag = std.enums.fromInt(Tag, raw) orelse return error.InvalidTag;
        if (!self.allow_nested and (tag == .array or tag == .group)) return error.InvalidTag;
        const decoded: field.Value = switch (tag) {
            .null_value => .null_value,
            .boolean => blk: {
                const raw_boolean = try self.int(u8);
                if (raw_boolean > 1) return error.InvalidValue;
                break :blk .{ .boolean = raw_boolean == 1 };
            },
            .signed => .{ .signed = try self.int(i128) },
            .unsigned => .{ .unsigned = try self.int(u128) },
            .float => .{ .float = @bitCast(try self.int(u64)) },
            .string => .{ .string = try self.blob() },
            .bytes => .{ .bytes = try self.blob() },
            .duration_ns => .{ .duration_ns = try self.int(i64) },
            .timestamp_ns => .{ .timestamp_ns = try self.int(i64) },
            .array => blk: {
                const count = try self.containerCount();
                defer self.depth -= 1;
                const arena = self.arena orelse return error.TooManyFields;
                const values = try arena.allocate(field.Value, count);
                for (values) |*child| child.* = try self.value();
                break :blk .{ .array = values };
            },
            .group => blk: {
                const count = try self.containerCount();
                defer self.depth -= 1;
                const arena = self.arena orelse return error.TooManyFields;
                const entries = try arena.allocate(field.Field, count);
                for (entries, 0..) |*entry, i| {
                    entry.* = try self.fieldValue();
                    try field.checkUnique(entries[0..i], entry.key);
                }
                break :blk .{ .group = entries };
            },
        };
        return decoded;
    }

    fn containerCount(self: *Input) DecodeError!usize {
        if (self.depth == field.max_value_depth) return error.ValueTooDeep;
        const count: usize = try self.int(u32);
        if (count > field.max_value_nodes - self.nodes) return error.TooManyValueNodes;
        self.depth += 1;
        return count;
    }
};

test "codec roundtrip copies all metadata and values without source pointers" {
    var dynamic_message = [_]u8{ 'h', 'i', 0xff };
    var dynamic_key = [_]u8{ 'k', 'e', 'y' };
    var dynamic_value = [_]u8{ 'v', 'a', 'l' };
    const entries = [_]field.Field{
        field.kv(&dynamic_key, &dynamic_value),
        field.kv("null", null),
        field.kv("bool", true),
        field.kv("min", std.math.minInt(i128)),
        field.kv("max", std.math.maxInt(u128)),
        field.kv("nan", std.math.nan(f64)),
        field.kv("inf", std.math.inf(f64)),
        field.kv("bytes", field.bytes("\x00\xff")),
        field.kv("duration", field.durationNs(std.math.minInt(i64))),
        field.kv("timestamp", field.timestampNs(std.math.maxInt(i64))),
        field.kv("password", field.secret("never-written-secret")),
    };
    const original: Event = .{ .level = .fatal, .scope = "codec", .message = &dynamic_message, .fields = &entries, .timestamp_ns = std.math.minInt(i64), .session = std.math.maxInt(u64), .sequence = 99, .channel = std.math.maxInt(u32), .route_mask = 123, .route_fingerprint = std.math.maxInt(u64), .config_generation = 42, .trace_id = @splat(0xab), .span_id = @splat(0xcd), .trace_flags = 0x81, .source = @src() };
    var buffer: [2048]u8 = undefined;
    const payload = try encode(original, &buffer);
    try std.testing.expectEqual(try encodedSize(original), payload.len);
    var streamed_buffer: [2048]u8 = undefined;
    var streamed = std.Io.Writer.fixed(&streamed_buffer);
    try writeTo(original, &streamed);
    try std.testing.expectEqualSlices(u8, payload, streamed.buffered());
    @memset(&dynamic_message, 'x');
    @memset(&dynamic_key, 'x');
    @memset(&dynamic_value, 'x');
    var scratch: [entries.len]field.Field = undefined;
    const restored = try decode(payload, &scratch);
    try std.testing.expectEqual(original.level, restored.level);
    try std.testing.expectEqualStrings("hi\xff", restored.message);
    try std.testing.expectEqualStrings("key", restored.fields[0].key);
    try std.testing.expectEqualStrings("val", restored.fields[0].value.string);
    try std.testing.expectEqual(original.timestamp_ns, restored.timestamp_ns);
    try std.testing.expectEqual(original.session, restored.session);
    try std.testing.expectEqual(original.sequence, restored.sequence);
    try std.testing.expectEqual(original.channel, restored.channel);
    try std.testing.expectEqual(original.route_mask, restored.route_mask);
    try std.testing.expectEqual(original.route_fingerprint, restored.route_fingerprint);
    try std.testing.expectEqual(original.config_generation, restored.config_generation);
    try std.testing.expectEqual(original.trace_id, restored.trace_id);
    try std.testing.expectEqual(original.span_id, restored.span_id);
    try std.testing.expectEqual(original.trace_flags, restored.trace_flags);
    try std.testing.expectEqualStrings(original.source.?.file, restored.source.?.file);
    try std.testing.expectEqualStrings(original.source.?.module, restored.source.?.module);
    try std.testing.expectEqualStrings(original.source.?.fn_name, restored.source.?.fn_name);
    try std.testing.expectEqual(original.source.?.line, restored.source.?.line);
    try std.testing.expectEqual(original.source.?.column, restored.source.?.column);
    try std.testing.expectEqual(std.math.minInt(i128), restored.fields[3].value.signed);
    try std.testing.expectEqual(std.math.maxInt(u128), restored.fields[4].value.unsigned);
    try std.testing.expect(std.math.isNan(restored.fields[5].value.float));
    try std.testing.expect(std.math.isPositiveInf(restored.fields[6].value.float));
    try std.testing.expectEqualStrings("\x00\xff", restored.fields[7].value.bytes);
    try std.testing.expectEqual(std.math.minInt(i64), restored.fields[8].value.duration_ns);
    try std.testing.expectEqual(std.math.maxInt(i64), restored.fields[9].value.timestamp_ns);
    try std.testing.expectEqualStrings(field.redacted, restored.fields[10].value.string);
    try std.testing.expect(std.mem.indexOf(u8, payload, "never-written-secret") == null);
    // Borrowed decode slices originate in the payload, including sentinel data.
    for (restored.fields) |entry| {
        try expectInPayload(payload, entry.key);
        switch (entry.value) {
            .string, .bytes => |value| try expectInPayload(payload, value),
            else => {},
        }
    }
    try expectInPayload(payload, restored.scope);
    try expectInPayload(payload, restored.message);
    try expectInPayload(payload, restored.source.?.file);
}

fn expectInPayload(payload: []const u8, slice: []const u8) !void {
    try std.testing.expect(@intFromPtr(slice.ptr) >= @intFromPtr(payload.ptr));
    try std.testing.expect(@intFromPtr(slice.ptr) + slice.len <= @intFromPtr(payload.ptr) + payload.len);
}

test "codec deferred arguments are copied after attributes and never contain secret values" {
    var buffer: [1024]u8 = undefined;
    const event: Event = .{ .level = .info, .scope = "fmt", .message = "request {d}: {s}", .message_template = true, .format_args = &.{ field.kv("", @as(u64, 42)), field.kv("", field.secret("hidden-format-argument")) }, .fields = &.{field.kv("status", 200)}, .timestamp_ns = 0 };
    const payload = try encode(event, &buffer);
    var scratch: [3]field.Field = undefined;
    const restored = try decode(payload, &scratch);
    try std.testing.expect(restored.message_template);
    try std.testing.expectEqual(@as(usize, 1), restored.fields.len);
    try std.testing.expectEqual(@as(usize, 2), restored.format_args.len);
    try std.testing.expectEqual(@as(u128, 42), restored.format_args[0].value.unsigned);
    try std.testing.expectEqualStrings(field.redacted, restored.format_args[1].value.string);
    try std.testing.expectEqual(@intFromPtr(&scratch[1]), @intFromPtr(restored.format_args.ptr));
    try std.testing.expect(std.mem.indexOf(u8, payload, "hidden-format-argument") == null);
    try std.testing.expectError(error.TooManyFields, decode(payload, scratch[0..2]));
}

test "codec rejects every truncated prefix, unknown version and malformed lengths" {
    var buffer: [512]u8 = undefined;
    const payload = try encode(.{ .level = .info, .scope = "x", .message = "y", .fields = &.{field.kv("a", true)}, .timestamp_ns = 0 }, &buffer);
    var scratch: [2]field.Field = undefined;
    for (0..payload.len) |length| try std.testing.expectError(error.Truncated, decode(payload[0..length], &scratch));
    var mutated: [512]u8 = undefined;
    @memcpy(mutated[0..payload.len], payload);
    mutated[0] ^= 1;
    try std.testing.expectError(error.InvalidMagic, decode(mutated[0..payload.len], &scratch));
    @memcpy(mutated[0..payload.len], payload);
    mutated[4] = 99;
    try std.testing.expectError(error.UnsupportedVersion, decode(mutated[0..payload.len], &scratch));
    @memcpy(mutated[0..payload.len], payload);
    mutated[6] = 0x80;
    try std.testing.expectError(error.InvalidFlags, decode(mutated[0..payload.len], &scratch));
    @memcpy(mutated[0..payload.len], payload);
    mutated[12] = 99;
    try std.testing.expectError(error.InvalidLevel, decode(mutated[0..payload.len], &scratch));
    @memcpy(mutated[0..payload.len], payload);
    std.mem.writeInt(u32, mutated[8..12], 1, .little);
    try std.testing.expectError(error.InvalidLength, decode(mutated[0..payload.len], &scratch));
    @memcpy(mutated[0..payload.len], payload);
    std.mem.writeInt(u32, mutated[header_size..][0..4], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.Truncated, decode(mutated[0..payload.len], &scratch));
    @memcpy(mutated[0..payload.len], payload);
    mutated[payload.len] = 0;
    try std.testing.expectError(error.InvalidLength, decode(mutated[0 .. payload.len + 1], &scratch));
}

test "codec validates boolean, tag, duplicate keys and bounded output" {
    var buffer: [512]u8 = undefined;
    const event: Event = .{ .level = .info, .scope = "", .message = "", .fields = &.{field.kv("a", true)}, .timestamp_ns = 0 };
    const payload = try encode(event, &buffer);
    var scratch: [2]field.Field = undefined;
    buffer[payload.len - 1] = 2;
    try std.testing.expectError(error.InvalidValue, decode(payload, &scratch));
    buffer[payload.len - 1] = 1;
    buffer[payload.len - 2] = 99;
    try std.testing.expectError(error.InvalidTag, decode(payload, &scratch));
    var short = [_]u8{0xaa} ** 4;
    try std.testing.expectError(error.BufferTooSmall, encode(event, &short));
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa, 0xaa, 0xaa }, &short);
    var duplicate = event;
    duplicate.fields = &.{ field.kv("dup", 1), field.kv("dup", 2) };
    try std.testing.expectError(error.DuplicateKey, encode(duplicate, &buffer));
    var disabled = event;
    disabled.level = .off;
    try std.testing.expectError(error.InvalidLevel, encode(disabled, &buffer));
    const unique = try encode(.{ .level = .info, .scope = "", .message = "", .fields = &.{ field.kv("a", true), field.kv("b", false) }, .timestamp_ns = 0 }, &buffer);
    // Empty scope/message consume 8 bytes; each one-byte boolean field is 7.
    buffer[header_size + 8 + 7 + 4] = 'a';
    try std.testing.expectError(error.DuplicateKey, decode(unique, &scratch));
}

test "codec wire golden is little endian and independent of struct padding" {
    var buffer: [128]u8 = undefined;
    const payload = try encode(.{ .level = .info, .scope = "a", .message = "b", .fields = &.{}, .timestamp_ns = -2, .session = 1, .sequence = 2, .channel = 3, .route_mask = 4, .route_fingerprint = 0x0102030405060708, .config_generation = 5, .trace_flags = 6 }, &buffer);
    const expected = [_]u8{
        'K', 'R', 'N', 'E', // magic
        4, 0, 0, 0, // self-contained version, flags
        94, 0, 0, 0, // total length
        2, 6, 0, 0, // info, trace flags, reserved
        0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, // timestamp
        1, 0, 0, 0, 0, 0, 0, 0, // session
        2, 0, 0, 0, 0, 0, 0, 0, // sequence
        3, 0, 0, 0, // channel
        4, 0, 0, 0, 0, 0, 0, 0, // route mask
        5, 0, 0, 0, 0, 0, 0, 0, // generation
        0, 0, 0, 0, 0, 0, 0, 0, // field and argument counts
        8, 7, 6, 5, 4, 3, 2, 1, // route fingerprint
        0, 0, 0, 0, 0, 0, 0, 0, // route generation
        1, 0, 0, 0, 'a', // scope
        1, 0, 0, 0, 'b', // message
    };
    try std.testing.expectEqualSlices(u8, &expected, payload);
}

test "codec route fingerprint spans the appended header and both output paths" {
    const event: Event = .{ .level = .info, .scope = "", .message = "", .fields = &.{}, .timestamp_ns = 0, .route_fingerprint = 0x8877665544332211 };
    var buffer: [header_size + 8]u8 = undefined;
    const payload = try encode(event, &buffer);
    try std.testing.expectEqual(@as(usize, 84), header_size);
    try std.testing.expectEqual(@as(usize, header_size + 8), payload.len);
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 }, payload[68..76]);
    var scratch: [0]field.Field = .{};
    const restored = try decode(payload, &scratch);
    try std.testing.expectEqual(event.route_fingerprint, restored.route_fingerprint);
    for (68..header_size + 1) |length| try std.testing.expectError(error.Truncated, decode(payload[0..length], &scratch));
    var streamed_bytes: [header_size + 8]u8 = undefined;
    var streamed = std.Io.Writer.fixed(&streamed_bytes);
    try writeTo(event, &streamed);
    try std.testing.expectEqualSlices(u8, payload, streamed.buffered());
    streamed = std.Io.Writer.fixed(streamed_bytes[0 .. streamed_bytes.len - 1]);
    try std.testing.expectError(error.WriteFailed, writeTo(event, &streamed));
    var malformed = buffer;
    std.mem.writeInt(u32, malformed[8..12], 68, .little);
    try std.testing.expectError(error.InvalidLength, decode(malformed[0..68], &scratch));
    std.mem.writeInt(u32, malformed[8..12], header_size, .little);
    try std.testing.expectError(error.Truncated, decode(malformed[0..header_size], &scratch));
}

test "codec rejects corrupt source string terminators and reserved header bits" {
    var buffer: [1024]u8 = undefined;
    const source = @src();
    const payload = try encode(.{ .level = .info, .scope = "", .message = "", .fields = &.{}, .timestamp_ns = 0, .source = source }, &buffer);
    var scratch: [0]field.Field = .{};
    for (0..payload.len) |length| try std.testing.expectError(error.Truncated, decode(payload[0..length], &scratch));
    const terminator_offset = header_size + 8 + 4 + source.module.len;
    buffer[terminator_offset] = 1;
    try std.testing.expectError(error.InvalidValue, decode(payload, &scratch));
    buffer[terminator_offset] = 0;
    buffer[14] = 1;
    try std.testing.expectError(error.InvalidFlags, decode(payload, &scratch));
}

test "codec single byte corruption cannot bypass bounds validation" {
    var buffer: [2048]u8 = undefined;
    const event: Event = .{ .level = .warn, .scope = "codec", .message = "{d}", .message_template = true, .format_args = &.{field.kv("", @as(i64, -42))}, .fields = &.{ field.kv("first", "value"), field.kv("second", field.bytes("\x00\xff")) }, .timestamp_ns = 0, .trace_id = @splat(1), .span_id = @splat(2), .source = @src() };
    const payload = try encode(event, &buffer);
    var mutated: [2048]u8 = undefined;
    var scratch: [3]field.Field = undefined;
    for (0..payload.len) |index| {
        @memcpy(mutated[0..payload.len], payload);
        mutated[index] ^= 0xff;
        // Data-byte mutations remain valid events; all structural mutations
        // must either remain bounded or return an explicit diagnostic.
        _ = decode(mutated[0..payload.len], &scratch) catch continue;
    }
}

test "codec preserves float bits in an unaligned payload" {
    var buffer: [513]u8 = undefined;
    const patterns = [_]u64{ 0x7ff8000000000042, 0x8000000000000000, 1 };
    const event: Event = .{ .level = .info, .scope = "", .message = "", .fields = &.{ field.kv("nan", @as(f64, @bitCast(patterns[0]))), field.kv("zero", @as(f64, @bitCast(patterns[1]))), field.kv("tiny", @as(f64, @bitCast(patterns[2]))) }, .timestamp_ns = 0 };
    const payload = try encode(event, buffer[1..]);
    var scratch: [3]field.Field = undefined;
    const restored = try decode(payload, &scratch);
    for (restored.fields, patterns) |entry, bits| try std.testing.expectEqual(bits, @as(u64, @bitCast(entry.value.float)));
}

test "historical self-contained v1 68-byte fixture decodes and reencodes as v4" {
    const legacy = [_]u8{
        'K', 'R', 'N', 'E',
        1, 0, 0, 0, // historical version and flags
        85, 0, 0, 0, // complete length
        2,    6,    0,    0, // level, trace flags and reserved
        0xfe, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff,
        1, 0, 0, 0, 0, 0, 0, 0, // session
        2, 0, 0, 0, 0, 0, 0, 0, // sequence
        3, 0, 0, 0, // channel
        4, 0, 0, 0, 0, 0, 0, 0, // route mask
        5, 0, 0, 0, 0, 0, 0, 0, // configuration generation
        1, 0,   0, 0, 0,   0, 0,   0, // field count and argument count
        // Body begins at byte 68; version 1 contains no route fingerprint.
        1, 0,   0, 0, 'a', 1, 0,   0,
        0, 'b', 1, 0, 0,   0, 'k', 1,
        1,
    };
    const header = try readHeader(&legacy, legacy_version);
    try std.testing.expectEqual(@as(usize, 68), header.header_bytes);
    var scratch: [1]field.Field = undefined;
    const restored = try decode(&legacy, &scratch);
    try std.testing.expectEqualStrings("a", restored.scope);
    try std.testing.expectEqualStrings("b", restored.message);
    try std.testing.expectEqualStrings("k", restored.fields[0].key);
    try std.testing.expect(restored.fields[0].value.boolean);
    try std.testing.expectEqual(@as(i64, -2), restored.timestamp_ns);
    try std.testing.expectEqual(@as(u64, 0), restored.route_fingerprint);
    var buffer: [128]u8 = undefined;
    const current = try encode(restored, &buffer);
    try std.testing.expectEqual(@as(u16, version), std.mem.readInt(u16, current[4..6], .little));
    try std.testing.expectEqual(legacy.len + 16, current.len);
    try std.testing.expectEqualSlices(u8, legacy[legacy_header_size..], current[header_size..]);
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** 8), current[68..76]);
    try std.testing.expectEqualStrings("b", (try decode(current, &scratch)).message);
    for (0..legacy.len) |length| try std.testing.expectError(error.Truncated, decode(legacy[0..length], &scratch));
}

test "legacy header offsets preserve source trace and deferred arguments" {
    const original: Event = .{ .level = .warn, .scope = "legacy", .message = "value={d}", .message_template = true, .format_args = &.{field.kv("0", @as(i64, -42))}, .fields = &.{field.kv("ok", true)}, .timestamp_ns = 17, .trace_id = @splat(0xab), .span_id = @splat(0xcd), .trace_flags = 1, .source = @src(), .route_fingerprint = 123 };
    var current_buffer: [2048]u8 = undefined;
    const current = try encode(original, &current_buffer);
    var legacy_buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&legacy_buffer);
    try writeHeader(original, current.len - 16, legacy_version, &writer);
    try std.testing.expectEqual(legacy_header_size, writer.end);
    try writer.writeAll(current[header_size..]);
    var scratch: [2]field.Field = undefined;
    const restored = try decode(writer.buffered(), &scratch);
    try std.testing.expectEqualStrings(original.source.?.file, restored.source.?.file);
    try std.testing.expectEqual(original.source.?.line, restored.source.?.line);
    try std.testing.expectEqual(original.trace_id.?, restored.trace_id.?);
    try std.testing.expectEqual(original.span_id.?, restored.span_id.?);
    try std.testing.expectEqual(@as(i128, -42), restored.format_args[0].value.signed);
    try std.testing.expectEqual(@as(u64, 0), restored.route_fingerprint);
    try std.testing.expectEqual(@as(usize, 84), (try readHeader(current, version)).header_bytes);
    const migrated = try encode(restored, &current_buffer);
    try std.testing.expectEqual(@as(u16, version), std.mem.readInt(u16, migrated[4..6], .little));
    try std.testing.expectEqualStrings("legacy", (try decode(migrated, &scratch)).scope);
}

test "standalone decoder rejects v2 references and unversioned extended v1 headers" {
    var buffer: [128]u8 = undefined;
    const payload = try encode(.{ .level = .info, .scope = "x", .message = "y", .fields = &.{}, .timestamp_ns = 0 }, &buffer);
    var scratch: [0]field.Field = .{};
    std.mem.writeInt(u16, buffer[4..6], reference_version, .little);
    try std.testing.expectError(error.UnsupportedVersion, decode(payload, &scratch));
    try std.testing.expectEqual(header_size, (try readHeader(payload, reference_version)).header_bytes);
    std.mem.writeInt(u16, buffer[4..6], legacy_version, .little);
    try std.testing.expectError(error.InvalidLength, decode(payload, &scratch));
}

test "nested wire copies source bytes and descriptors into caller scratch only" {
    var key = "child".*;
    var text = "original".*;
    var data = [_]u8{ 0, 255 };
    var values = [_]field.Value{ field.fromAny(@as([]const u8, &text)), field.fromAny(field.bytes(&data)), .{ .array = &.{} }, .null_value };
    var entries = [_]field.Field{field.kv(&key, field.array(&values))};
    const event: Event = .{ .level = .info, .scope = "nested", .message = "", .timestamp_ns = 1, .route_generation = 0x8877665544332211, .fields = &.{field.kv("root", field.group(&entries))} };
    var buffer: [1024]u8 = undefined;
    const payload = try encode(event, &buffer);
    var streamed_buffer: [1024]u8 = undefined;
    var streamed = std.Io.Writer.fixed(&streamed_buffer);
    try writeTo(event, &streamed);
    try std.testing.expectEqualSlices(u8, payload, streamed.buffered());
    @memset(&key, 'x');
    @memset(&text, 'x');
    @memset(&data, 42);
    values = @splat(.null_value);
    entries[0] = field.kv("changed", false);
    var scratch: [decode_scratch_fields]field.Field = undefined;
    const restored = try decode(payload, &scratch);
    const child = restored.fields[0].value.group[0];
    try std.testing.expectEqualStrings("child", child.key);
    try std.testing.expectEqualStrings("original", child.value.array[0].string);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255 }, child.value.array[1].bytes);
    try std.testing.expectEqual(@as(usize, 0), child.value.array[2].array.len);
    try std.testing.expect(child.value.array[3] == .null_value);
    try std.testing.expectEqual(event.route_generation, restored.route_generation);
    const arena_start = @intFromPtr(&scratch[1]);
    const arena_end = @intFromPtr(scratch[0..].ptr) + @sizeOf(@TypeOf(scratch));
    try std.testing.expect(@intFromPtr(restored.fields[0].value.group.ptr) >= arena_start);
    try std.testing.expect(@intFromPtr(child.value.array.ptr) < arena_end);
    var small: [1]field.Field = undefined;
    try std.testing.expectError(error.TooManyFields, decode(payload, &small));
    for (0..payload.len) |length| try std.testing.expectError(error.Truncated, decode(payload[0..length], &scratch));
}

test "nested input rejects cycles depth nodes and duplicate group keys before writing" {
    var buffer: [4096]u8 = @splat(0xaa);
    var cyclic: [1]field.Value = undefined;
    cyclic[0] = .{ .array = &cyclic };
    var event: Event = .{ .level = .info, .scope = "", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("bad", field.array(&cyclic))} };
    try std.testing.expectError(error.CyclicValue, encode(event, &buffer));
    try std.testing.expectEqual(@as(u8, 0xaa), buffer[0]);
    var chain: [field.max_value_depth + 1]field.Value = undefined;
    chain[0] = .{ .group = &.{} };
    for (1..chain.len) |i| chain[i] = .{ .array = chain[i - 1 .. i] };
    event.fields = &.{field.kv("bad", chain[chain.len - 1])};
    try std.testing.expectError(error.ValueTooDeep, encode(event, &buffer));
    var nodes: [field.max_value_nodes]field.Value = @splat(.null_value);
    event.fields = &.{field.kv("bad", field.array(&nodes))};
    try std.testing.expectError(error.TooManyValueNodes, encode(event, &buffer));
    event.fields = &.{field.kv("bad", field.group(&.{ field.kv("dup", true), field.kv("dup", false) }))};
    try std.testing.expectError(error.DuplicateKey, encode(event, &buffer));
    try std.testing.expectEqual(@as(u8, 0xaa), buffer[0]);

    // Separate top-level attributes and arguments still share one node budget.
    event.fields = &.{field.kv("values", field.array(nodes[0 .. nodes.len - 1]))};
    event.format_args = &.{field.kv("0", true)};
    try std.testing.expectError(error.TooManyValueNodes, encode(event, &buffer));
}

test "size overflow retains complete validation priority and never touches output" {
    const huge = @as([*]const u8, @ptrCast("x"))[0..std.math.maxInt(u32)];
    var cyclic: [1]field.Value = undefined;
    cyclic[0] = .{ .array = &cyclic };
    var buffer: [128]u8 = @splat(0xa5);
    var event: Event = .{ .level = .info, .scope = "", .message = huge, .timestamp_ns = 0, .fields = &.{field.kv("cycle", field.array(&cyclic))} };
    try std.testing.expectError(error.CyclicValue, encodedSize(event));
    try std.testing.expectError(error.CyclicValue, encode(event, &buffer));
    var output = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.CyclicValue, writeTo(event, &output));
    try std.testing.expectEqual(@as(usize, 0), output.end);
    try std.testing.expect(std.mem.allEqual(u8, &buffer, 0xa5));

    event.fields = &.{ field.kv("large", huge), field.kv("same", 1), field.kv("same", 2) };
    try std.testing.expectError(error.DuplicateKey, encodedSize(event));
    try std.testing.expectError(error.DuplicateKey, encode(event, &buffer));
    const values = [_]field.Value{ field.fromAny(huge), field.fromAny(field.array(&cyclic)) };
    try std.testing.expectError(error.CyclicValue, encodedValueSize(field.fromAny(field.array(&values))));
    event.fields = &.{};
    try std.testing.expectError(error.TooLarge, encode(event, &buffer));
    try std.testing.expect(std.mem.allEqual(u8, &buffer, 0xa5));
}

test "admission measurement skips level validation and sized writes stay byte-identical" {
    const entries = [_]field.Field{
        field.kv("n", 7),
        field.kv("nested", field.group(&.{ field.kv("x", true), field.kv("y", field.array(&.{ .null_value, field.fromAny("z") })) })),
    };
    var event: Event = .{ .level = .info, .scope = "measure", .message = "hello {d}", .message_template = true, .timestamp_ns = 0, .fields = &entries, .format_args = &.{field.kv("0", @as(u64, 5))}, .trace_id = @splat(1), .source = @src() };
    var expected: [2048]u8 = undefined;
    const encoded = try encode(event, &expected);
    const measured = try measure(event);
    try std.testing.expectEqual(encoded.len, measured);
    try std.testing.expectEqual(measured, try encodedSize(event));
    var sized: [2048]u8 = undefined;
    const written = try encodeSized(event, measured, &sized);
    try std.testing.expectEqualSlices(u8, encoded, written);
    // Capacity is checked against the measured size before writing.
    try std.testing.expectError(error.BufferTooSmall, encodeSized(event, measured + 1, sized[0..measured]));
    try std.testing.expectError(error.BufferTooSmall, encodeSized(event, measured, sized[0 .. measured - 1]));
    // Admission measurement deliberately leaves level rejection to the write.
    event.level = .off;
    try std.testing.expectEqual(measured, try measure(event));
    try std.testing.expectError(error.InvalidLevel, encodedSize(event));
    try std.testing.expectError(error.InvalidLevel, encodeSized(event, measured, &sized));
    // Invalid trees still fail measurement before any destination write.
    event.level = .info;
    event.fields = &.{ field.kv("dup", 1), field.kv("dup", 2) };
    try std.testing.expectError(error.DuplicateKey, measure(event));
}

test "size encode and streaming visit values once while preserving all scalar and nested wire sizes" {
    const leaves = [_]field.Value{
        .null_value,                          field.fromAny(true),              field.fromAny(@as(i128, -17)),          field.fromAny(@as(u128, 18)),
        field.fromAny(@as(f64, 1.5)),         field.fromAny("hello"),           field.fromAny(field.bytes("\x00\xff")), field.fromAny(field.durationNs(-20)),
        field.fromAny(field.timestampNs(21)), field.fromAny(field.array(&.{})), field.fromAny(field.group(&.{})),
    };
    const event: Event = .{ .level = .info, .scope = "once", .message = "{any}", .message_template = true, .timestamp_ns = 0, .fields = &.{field.kv("values", field.array(&leaves))}, .format_args = &.{ field.kv("", true), field.kv("", field.group(&.{field.kv("child", 1)})) } };
    const nodes = 15;
    var buffer: [2048]u8 = undefined;
    const initial = field.TestingAudit.visited_values;
    const size = try encodedSize(event);
    try std.testing.expectEqual(@as(usize, nodes), field.TestingAudit.visited_values - initial);
    const before_encode = field.TestingAudit.visited_values;
    const encoded = try encode(event, &buffer);
    try std.testing.expectEqual(@as(usize, nodes), field.TestingAudit.visited_values - before_encode);
    try std.testing.expectEqual(size, encoded.len);
    var stream_buffer: [2048]u8 = undefined;
    var stream = std.Io.Writer.fixed(&stream_buffer);
    const before_stream = field.TestingAudit.visited_values;
    try writeTo(event, &stream);
    try std.testing.expectEqual(@as(usize, nodes), field.TestingAudit.visited_values - before_stream);
    try std.testing.expectEqualSlices(u8, encoded, stream.buffered());
    var values_size: usize = 0;
    for (leaves) |value| values_size += try encodedValueSize(value);
    try std.testing.expectEqual(values_size + 5, try encodedValueSize(field.fromAny(field.array(&leaves))));
}

test "nested decoder rejects malformed child counts depth keys and legacy tags" {
    var buffer: [1024]u8 = undefined;
    var event: Event = .{ .level = .info, .scope = "", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("a", field.array(&.{.null_value}))} };
    var scratch: [decode_scratch_fields]field.Field = undefined;
    var payload = try encode(event, &buffer);
    const value_offset = header_size + 8 + 5;
    std.mem.writeInt(u32, buffer[value_offset + 1 ..][0..4], field.max_value_nodes, .little);
    try std.testing.expectError(error.TooManyValueNodes, decode(payload, &scratch));

    event.fields = &.{field.kv("a", field.group(&.{ field.kv("x", true), field.kv("y", false) }))};
    payload = try encode(event, &buffer);
    // group tag/count precede two one-byte keyed boolean children.
    buffer[value_offset + 5 + 7 + 4] = 'x';
    try std.testing.expectError(error.DuplicateKey, decode(payload, &scratch));

    var raw: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&raw);
    inline for (0..field.max_value_depth + 1) |_| {
        try writer.writeByte(@intFromEnum(ValueTag.array));
        try writer.writeAll(&.{ 1, 0, 0, 0 });
    }
    try writer.writeByte(@intFromEnum(ValueTag.null_value));
    var arena = DescriptorArena.init(&scratch);
    var input: WireInput = .{ .bytes = writer.buffered(), .arena = &arena, .allow_nested = true };
    try std.testing.expectError(error.ValueTooDeep, input.value());
    input = .{ .bytes = &.{ @intFromEnum(ValueTag.array), 0, 0, 0, 0 }, .arena = &arena };
    try std.testing.expectError(error.InvalidTag, input.value());
}

test "historical v3 header migrates route generation and preserves scalar body" {
    const event: Event = .{ .level = .info, .scope = "v3", .message = "legacy", .timestamp_ns = 1, .fields = &.{field.kv("answer", 42)}, .route_fingerprint = 123, .route_generation = 99 };
    var current_buffer: [256]u8 = undefined;
    const current = try encode(event, &current_buffer);
    var legacy_buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&legacy_buffer);
    try writeHeader(event, current.len - 8, previous_version, &writer);
    try std.testing.expectEqual(previous_header_size, writer.end);
    try writer.writeAll(current[header_size..]);
    var scratch: [1]field.Field = undefined;
    const restored = try decode(writer.buffered(), &scratch);
    try std.testing.expectEqual(@as(u64, 0), restored.route_generation);
    try std.testing.expectEqual(event.route_fingerprint, restored.route_fingerprint);
    try std.testing.expectEqual(@as(u128, 42), restored.fields[0].value.unsigned);
    const migrated = try encode(restored, &current_buffer);
    try std.testing.expectEqual(@as(u16, 4), std.mem.readInt(u16, migrated[4..6], .little));
    try std.testing.expectEqual(@as(u64, 0), (try decode(migrated, &scratch)).route_generation);
}

test "full node budget fits fixed scratch for the largest group descriptor layout" {
    var keys: [field.max_value_nodes - 1][1]u8 = undefined;
    var entries: [field.max_value_nodes - 1]field.Field = undefined;
    for (&entries, 0..) |*entry, i| {
        keys[i][0] = @intCast(i);
        entry.* = .{ .key = &keys[i], .value = .null_value };
    }
    const event: Event = .{ .level = .info, .scope = "", .message = "", .timestamp_ns = 0, .fields = &.{field.kv("group", field.group(&entries))} };
    var buffer: [4096]u8 = undefined;
    const payload = try encode(event, &buffer);
    var scratch: [decode_scratch_fields]field.Field = undefined;
    const restored = try decode(payload, &scratch);
    try std.testing.expectEqual(field.max_value_nodes - 1, restored.fields[0].value.group.len);
    try std.testing.expectEqualSlices(u8, &.{254}, restored.fields[0].value.group[254].key);
    var short: [decode_scratch_fields - 1]field.Field = undefined;
    try std.testing.expectError(error.TooManyFields, decode(payload, &short));
}
