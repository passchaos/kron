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

test {
    _ = @import("tests/codec.zig");
}
