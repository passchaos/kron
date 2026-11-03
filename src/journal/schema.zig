//! Fixed, append-only metadata slots. Definitions contain no event values or
//! pointers. A caller syncs the mapping before marking a reference ready.
const std = @import("std");
const codec = @import("../core/codec.zig");
const journal_format = @import("format.zig");

/// Table extension and scalar-only definitions retain their original version.
pub const version: u16 = 1;
pub const nested_version: u16 = 2;

pub fn supportedVersion(value: u16) bool {
    return value == version or value == nested_version;
}
pub const extension_offset: usize = 256;
pub const extension_size: usize = 64;
pub const entry_header_size: usize = 64;
pub const reference_wire_size: usize = 24;
pub const definition_memory_size: usize = @sizeOf(Definition);
pub const max_fields: usize = 64;
pub const max_arguments: usize = 64;
pub const scalar_kind_mask: u16 = (1 << 9) - 1;
pub const all_kind_mask: u16 = (1 << 11) - 1;
const extension_magic = "KRONSCH1";
const definition_magic = "KRNS";
const definition_header_size: usize = 16;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const Error = error{
    InvalidSchemaOptions,
    TruncatedSchema,
    UnsupportedSchemaVersion,
    InvalidSchema,
    CorruptSchema,
    SchemaTooLarge,
    SchemaTableFull,
    DuplicateKey,
    TooManyFields,
    MissingSchema,
    SchemaNotReady,
    LayoutMismatch,
};

pub const Layout = struct {
    size: usize,
    offset: usize,
    stride: usize,
    capacity: usize,
    max_definition_bytes: usize,
    identity: [16]u8 = @splat(0),
};

pub fn layout(base_size: usize, capacity: usize, max_definition_bytes: usize) Error!Layout {
    if (capacity == 0 or capacity > std.math.maxInt(u32) or max_definition_bytes < definition_header_size + 4 or max_definition_bytes > std.math.maxInt(u32)) return error.InvalidSchemaOptions;
    const offset = alignSize(base_size, 4096) catch return error.InvalidSchemaOptions;
    const raw = std.math.add(usize, entry_header_size, max_definition_bytes) catch return error.InvalidSchemaOptions;
    const stride = alignSize(raw, 64) catch return error.InvalidSchemaOptions;
    if (stride > std.math.maxInt(u32)) return error.InvalidSchemaOptions;
    const region = std.math.mul(usize, capacity, stride) catch return error.InvalidSchemaOptions;
    const size = std.math.add(usize, offset, region) catch return error.InvalidSchemaOptions;
    if (std.math.cast(i64, size) == null) return error.InvalidSchemaOptions;
    return .{ .size = size, .offset = offset, .stride = stride, .capacity = capacity, .max_definition_bytes = max_definition_bytes };
}

fn alignSize(value: usize, alignment: usize) !usize {
    return (try std.math.add(usize, value, alignment - 1)) & ~(alignment - 1);
}

/// Only writes the extension. The journal owns version=2 and its first-header CRC.
pub fn writeExtension(header: []u8, spec: Layout, identity: [16]u8) void {
    const bytes = header[extension_offset..][0..extension_size];
    @memset(bytes, 0);
    @memcpy(bytes[0..8], extension_magic);
    put(u16, bytes, 8, version);
    put(u32, bytes, 12, @intCast(spec.capacity));
    put(u32, bytes, 16, @intCast(spec.stride));
    put(u32, bytes, 20, @intCast(spec.max_definition_bytes));
    put(u64, bytes, 24, @intCast(spec.offset));
    put(u64, bytes, 32, @intCast(spec.size - spec.offset));
    @memcpy(bytes[40..56], &identity);
    put(u32, bytes, 60, std.hash.Crc32.hash(bytes[0..60]));
}

pub fn readLayout(header: []const u8) Error!Layout {
    if (header.len < extension_offset + extension_size) return error.TruncatedSchema;
    const journal_version = get(u32, header, 8);
    if (journal_version != journal_format.schema_version_v2 and journal_version != journal_format.schema_version)
        return error.UnsupportedSchemaVersion;
    const bytes = header[extension_offset..][0..extension_size];
    if (!std.mem.eql(u8, bytes[0..8], extension_magic)) return error.InvalidSchema;
    if (get(u16, bytes, 8) != version) return error.UnsupportedSchemaVersion;
    if (get(u16, bytes, 10) != 0 or get(u32, bytes, 56) != 0) return error.InvalidSchema;
    if (get(u32, bytes, 60) != std.hash.Crc32.hash(bytes[0..60])) return error.CorruptSchema;
    const data_capacity = std.math.cast(usize, get(u64, header, 16)) orelse return error.LayoutMismatch;
    const data_stride = std.math.cast(usize, get(u64, header, 32)) orelse return error.LayoutMismatch;
    if (data_capacity == 0 or data_stride < 64 or data_stride % 64 != 0) return error.LayoutMismatch;
    const data = std.math.mul(usize, data_capacity, data_stride) catch return error.LayoutMismatch;
    const base = std.math.add(usize, 4096, data) catch return error.LayoutMismatch;
    var result = try layout(base, get(u32, bytes, 12), get(u32, bytes, 20));
    if (get(u64, bytes, 24) != result.offset or get(u32, bytes, 16) != result.stride or get(u64, bytes, 32) != result.size - result.offset) return error.LayoutMismatch;
    result.identity = bytes[40..56].*;
    return result;
}

pub const Ref = struct {
    id: u32,
    version: u16 = version,
    hash: [16]u8,
};

pub const FieldSchema = struct { key: []const u8, kind_mask: u16 };
pub const EventMeta = struct {
    scope: []const u8,
    /// Null means an ordinary dynamic message, copied into each event.
    message: ?[]const u8 = null,
    message_template: bool = false,
    source: ?std.builtin.SourceLocation = null,
    fields: []const FieldSchema = &.{},
    format_args: []const FieldSchema = &.{},
};

pub fn kindMask(tag: codec.ValueTag) u16 {
    return @as(u16, 1) << @as(u4, @intCast(@intFromEnum(tag)));
}

pub const FieldIterator = struct {
    input: codec.WireInput,
    remaining: usize,
    allowed_kind_mask: u16 = scalar_kind_mask,

    pub fn next(self: *FieldIterator) Error!?FieldSchema {
        if (self.remaining == 0) return null;
        const key = self.input.blob() catch return error.TruncatedSchema;
        const mask = self.input.int(u16) catch return error.TruncatedSchema;
        if (mask == 0 or mask & ~self.allowed_kind_mask != 0) return error.InvalidSchema;
        self.remaining -= 1;
        return .{ .key = key, .kind_mask = mask };
    }
};

/// Slices borrow the validated definition bytes. Source names have explicit NULs.
pub const Definition = struct {
    ref: Ref,
    scope: []const u8,
    message: ?[]const u8,
    message_template: bool,
    source: ?std.builtin.SourceLocation,
    field_count: usize,
    argument_count: usize,
    fields_wire: []const u8,
    arguments_wire: []const u8,
    bytes: []const u8,

    pub fn fields(self: Definition) FieldIterator {
        return .{ .input = .{ .bytes = self.fields_wire }, .remaining = self.field_count, .allowed_kind_mask = versionKindMask(self.ref.version) };
    }

    pub fn arguments(self: Definition) FieldIterator {
        return .{ .input = .{ .bytes = self.arguments_wire }, .remaining = self.argument_count, .allowed_kind_mask = versionKindMask(self.ref.version) };
    }
};

fn versionKindMask(schema_version: u16) u16 {
    return if (schema_version == nested_version) all_kind_mask else scalar_kind_mask;
}

/// Metadata owns only top-level keys/kinds. Nested lengths, keys and values are
/// dynamic record data and cannot change a registered schema's identity.
pub fn metadataVersion(meta: EventMeta) u16 {
    for (meta.fields) |entry| if (entry.kind_mask & ~scalar_kind_mask != 0) return nested_version;
    for (meta.format_args) |entry| if (entry.kind_mask & ~scalar_kind_mask != 0) return nested_version;
    return version;
}

fn metadataFlags(meta: EventMeta) u16 {
    return @as(u16, @intFromBool(meta.message_template)) |
        (@as(u16, @intFromBool(meta.message != null)) << 1) |
        (@as(u16, @intFromBool(meta.source != null)) << 2);
}

pub fn encodedMetadataSize(meta: EventMeta) Error!usize {
    if (meta.fields.len > max_fields or meta.format_args.len > max_arguments) return error.TooManyFields;
    if (meta.message_template and meta.message == null) return error.InvalidSchema;
    if (!meta.message_template and meta.format_args.len != 0) return error.InvalidSchema;
    var total: usize = definition_header_size;
    try blobSize(&total, meta.scope.len, false);
    if (meta.message) |message| try blobSize(&total, message.len, false);
    if (meta.source) |source| {
        try blobSize(&total, source.module.len, true);
        try blobSize(&total, source.file.len, true);
        try blobSize(&total, source.fn_name.len, true);
        try addSize(&total, 8);
    }
    for (meta.fields, 0..) |field, i| {
        for (meta.fields[0..i]) |previous| if (std.mem.eql(u8, previous.key, field.key)) return error.DuplicateKey;
        try fieldSize(&total, field);
    }
    for (meta.format_args) |argument| try fieldSize(&total, argument);
    return total;
}

fn fieldSize(total: *usize, field: FieldSchema) Error!void {
    if (field.kind_mask == 0 or field.kind_mask & ~all_kind_mask != 0) return error.InvalidSchema;
    try blobSize(total, field.key.len, false);
    try addSize(total, 2);
}
fn addSize(total: *usize, amount: usize) Error!void {
    total.* = std.math.add(usize, total.*, amount) catch return error.SchemaTooLarge;
    if (total.* > std.math.maxInt(u32)) return error.SchemaTooLarge;
}
fn blobSize(total: *usize, length: usize, terminated: bool) Error!void {
    try addSize(total, 4);
    try addSize(total, length);
    if (terminated) try addSize(total, 1);
}

const HashOutput = struct {
    const WriteError = error{};
    hash: *Sha256,
    fn put(self: *HashOutput, bytes: []const u8) WriteError!void {
        self.hash.update(bytes);
    }
    fn int(self: *HashOutput, comptime T: type, value: T) WriteError!void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        self.hash.update(&bytes);
    }
};
const ByteOutput = struct {
    const WriteError = error{SchemaTooLarge};
    bytes: []u8,
    position: usize = 0,
    fn put(self: *ByteOutput, bytes: []const u8) WriteError!void {
        if (bytes.len > self.bytes.len - self.position) return error.SchemaTooLarge;
        @memcpy(self.bytes[self.position..][0..bytes.len], bytes);
        self.position += bytes.len;
    }
    fn int(self: *ByteOutput, comptime T: type, value: T) WriteError!void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        try self.put(&bytes);
    }
};
fn writeMetadata(output: anytype, meta: EventMeta) @TypeOf(output.*).WriteError!void {
    try output.put(definition_magic);
    try output.int(u16, metadataVersion(meta));
    try output.int(u16, metadataFlags(meta));
    try output.int(u16, @intCast(meta.fields.len));
    try output.int(u16, @intCast(meta.format_args.len));
    try output.int(u32, 0);
    try writeBlob(output, meta.scope, false);
    if (meta.message) |message| try writeBlob(output, message, false);
    if (meta.source) |source| {
        try writeBlob(output, source.module, true);
        try writeBlob(output, source.file, true);
        try writeBlob(output, source.fn_name, true);
        try output.int(u32, source.line);
        try output.int(u32, source.column);
    }
    for (meta.fields) |field| {
        try writeBlob(output, field.key, false);
        try output.int(u16, field.kind_mask);
    }
    for (meta.format_args) |argument| {
        try writeBlob(output, argument.key, false);
        try output.int(u16, argument.kind_mask);
    }
}
fn writeBlob(output: anytype, bytes: []const u8, terminated: bool) @TypeOf(output.*).WriteError!void {
    try output.int(u32, @intCast(bytes.len));
    try output.put(bytes);
    if (terminated) try output.int(u8, 0);
}

fn bodyHash(bytes: []const u8) [16]u8 {
    var hash = Sha256.init(.{});
    hash.update(if (get(u16, bytes, 4) == nested_version) "kron-schema-v2\x00" else "kron-schema-v1\x00");
    hash.update(bytes);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return digest[0..16].*;
}
pub fn metadataHash(meta: EventMeta) Error![16]u8 {
    _ = try encodedMetadataSize(meta);
    var hash = Sha256.init(.{});
    hash.update(if (metadataVersion(meta) == nested_version) "kron-schema-v2\x00" else "kron-schema-v1\x00");
    var output: HashOutput = .{ .hash = &hash };
    try writeMetadata(&output, meta);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return digest[0..16].*;
}

fn decodeDefinition(bytes: []const u8, reference: Ref) Error!Definition {
    var input: codec.WireInput = .{ .bytes = bytes };
    if (!std.mem.eql(u8, input.take(4) catch return error.TruncatedSchema, definition_magic)) return error.InvalidSchema;
    const schema_version = input.int(u16) catch return error.TruncatedSchema;
    if (!supportedVersion(schema_version)) return error.UnsupportedSchemaVersion;
    if (schema_version != reference.version) return error.CorruptSchema;
    const allowed_kind_mask = versionKindMask(schema_version);
    const flags = input.int(u16) catch return error.TruncatedSchema;
    if (flags & ~@as(u16, 7) != 0 or flags & 1 != 0 and flags & 2 == 0) return error.InvalidSchema;
    const field_count = input.int(u16) catch return error.TruncatedSchema;
    const argument_count = input.int(u16) catch return error.TruncatedSchema;
    if (field_count > max_fields or argument_count > max_arguments or flags & 1 == 0 and argument_count != 0) return error.InvalidSchema;
    if ((input.int(u32) catch return error.TruncatedSchema) != 0) return error.InvalidSchema;
    const scope = input.blob() catch return error.TruncatedSchema;
    const message = if (flags & 2 != 0) input.blob() catch return error.TruncatedSchema else null;
    const source: ?std.builtin.SourceLocation = if (flags & 4 != 0) .{
        .module = input.terminated() catch return error.InvalidSchema,
        .file = input.terminated() catch return error.InvalidSchema,
        .fn_name = input.terminated() catch return error.InvalidSchema,
        .line = input.int(u32) catch return error.TruncatedSchema,
        .column = input.int(u32) catch return error.TruncatedSchema,
    } else null;
    const fields_start = input.position;
    var previous: [max_fields][]const u8 = undefined;
    for (0..field_count) |i| {
        const key = input.blob() catch return error.TruncatedSchema;
        for (previous[0..i]) |old| if (std.mem.eql(u8, old, key)) return error.DuplicateKey;
        previous[i] = key;
        const mask = input.int(u16) catch return error.TruncatedSchema;
        if (mask == 0 or mask & ~allowed_kind_mask != 0) return error.InvalidSchema;
    }
    const arguments_start = input.position;
    for (0..argument_count) |_| {
        _ = input.blob() catch return error.TruncatedSchema;
        const mask = input.int(u16) catch return error.TruncatedSchema;
        if (mask == 0 or mask & ~allowed_kind_mask != 0) return error.InvalidSchema;
    }
    if (input.position != bytes.len) return error.InvalidSchema;
    return .{ .ref = reference, .scope = scope, .message = message, .message_template = flags & 1 != 0, .source = source, .field_count = field_count, .argument_count = argument_count, .fields_wire = bytes[fields_start..arguments_start], .arguments_wire = bytes[arguments_start..], .bytes = bytes };
}

fn entryChecksum(slot: []const u8, payload: []const u8) u32 {
    var crc = std.hash.Crc32.init();
    crc.update(slot[8..20]);
    crc.update(slot[24..entry_header_size]);
    crc.update(payload);
    return crc.final();
}

/// The caller snapshots/re-reads commit for live files. This function is pure
/// and accepts a copied slot; unfinished fixed slots never hide later commits.
pub fn decodeEntry(slot: []const u8, index: usize, maximum: usize) Error!?Definition {
    if (slot.len < entry_header_size) return error.TruncatedSchema;
    if (index >= std.math.maxInt(u32)) return error.InvalidSchema;
    const id: u32 = @intCast(index + 1);
    const marker = get(u64, slot, 0);
    if (marker == 0) return null;
    if (marker >> 2 != id or marker & 3 == 0) return error.CorruptSchema;
    if (marker & 3 != 2) return null;
    if (get(u32, slot, 8) != id) return error.CorruptSchema;
    const schema_version = get(u16, slot, 12);
    if (!supportedVersion(schema_version)) return error.UnsupportedSchemaVersion;
    const length: usize = get(u32, slot, 16);
    if (length < definition_header_size or length > maximum or length > slot.len - entry_header_size) return error.CorruptSchema;
    for (slot[44..64]) |byte| if (byte != 0) return error.InvalidSchema;
    const body = slot[entry_header_size..][0..length];
    if (get(u32, slot, 20) != entryChecksum(slot, body)) return error.CorruptSchema;
    const hash = slot[24..40].*;
    if (!std.mem.eql(u8, &hash, &bodyHash(body))) return error.CorruptSchema;
    const definition = try decodeDefinition(body, .{ .id = id, .version = schema_version, .hash = hash });
    if (get(u16, slot, 14) != metadataFlags(.{ .scope = definition.scope, .message = definition.message, .message_template = definition.message_template, .source = definition.source }) or get(u16, slot, 40) != definition.field_count or get(u16, slot, 42) != definition.argument_count) return error.CorruptSchema;
    return definition;
}

pub fn metadataEqual(definition: Definition, meta: EventMeta) bool {
    if (!std.mem.eql(u8, definition.scope, meta.scope) or definition.message_template != meta.message_template or definition.field_count != meta.fields.len or definition.argument_count != meta.format_args.len) return false;
    if (definition.message) |message| {
        if (meta.message == null or !std.mem.eql(u8, message, meta.message.?)) return false;
    } else if (meta.message != null) return false;
    if (!sourceEqual(definition.source, meta.source)) return false;
    var fields = definition.fields();
    for (meta.fields) |field| {
        const existing = (fields.next() catch return false) orelse return false;
        if (existing.kind_mask != field.kind_mask or !std.mem.eql(u8, existing.key, field.key)) return false;
    }
    var arguments = definition.arguments();
    for (meta.format_args) |argument| {
        const existing = (arguments.next() catch return false) orelse return false;
        if (existing.kind_mask != argument.kind_mask or !std.mem.eql(u8, existing.key, argument.key)) return false;
    }
    return true;
}
pub fn sourceEqual(a: ?std.builtin.SourceLocation, b: ?std.builtin.SourceLocation) bool {
    if (a) |left| {
        const right = b orelse return false;
        return left.line == right.line and left.column == right.column and std.mem.eql(u8, left.module, right.module) and std.mem.eql(u8, left.file, right.file) and std.mem.eql(u8, left.fn_name, right.fn_name);
    }
    return b == null;
}

pub const RegisterResult = struct { ref: Ref, requires_sync: bool };
/// A single owning registry; share its pointer between threads. Do not copy
/// the registry after use. Definition storage belongs to the borrowed mapping.
pub const Registry = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    region: []align(64) u8,
    spec: Layout,
    entries: []Entry,
    mutex: std.Io.Mutex = .init,

    const Entry = struct { marker: u64 = 0, definition: ?Definition = null, ready: std.atomic.Value(bool) = .init(false) };

    /// This is read-only validation; the region remains borrowed from its owner.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, region: []align(64) u8, spec: Layout) !Registry {
        if (@import("builtin").cpu.arch.endian() != .little) return error.UnsupportedPlatform;
        const canonical = try layout(0, spec.capacity, spec.max_definition_bytes);
        const expected = std.math.mul(usize, spec.capacity, spec.stride) catch return error.LayoutMismatch;
        if (region.len != expected or spec.stride != canonical.stride) return error.LayoutMismatch;
        const entries = try allocator.alloc(Entry, spec.capacity);
        errdefer allocator.free(entries);
        for (entries, 0..) |*entry, index| {
            const slot: []align(64) u8 = @alignCast(region[index * spec.stride ..][0..spec.stride]);
            entry.* = .{ .marker = state(slot).load(.acquire), .definition = try decodeEntry(slot, index, spec.max_definition_bytes) };
        }
        return .{ .allocator = allocator, .io = io, .region = region, .spec = spec, .entries = entries };
    }

    pub fn deinit(self: *Registry) void {
        self.allocator.free(self.entries);
    }

    pub fn register(self: *Registry, meta: EventMeta) !RegisterResult {
        const size = try encodedMetadataSize(meta);
        if (size > self.spec.max_definition_bytes) return error.SchemaTooLarge;
        const hash = try metadataHash(meta);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        var empty: ?usize = null;
        for (self.entries, 0..) |*entry, index| {
            if (entry.marker == 0 and empty == null) empty = index;
            if (entry.definition) |definition| {
                // Full canonical equality follows the hash comparison. A
                // collision gets its own immutable id, never aliases metadata.
                if (std.mem.eql(u8, &definition.ref.hash, &hash) and metadataEqual(definition, meta)) return .{ .ref = definition.ref, .requires_sync = !entry.ready.load(.acquire) };
            }
        }
        const index = empty orelse return error.SchemaTableFull;
        const id: u32 = @intCast(index + 1);
        const slot = self.slotBytes(index);
        const reserved = (@as(u64, id) << 2) | 1;
        state(slot).store(reserved, .release);
        self.entries[index].marker = reserved;
        @memset(slot[8..], 0);
        var output: ByteOutput = .{ .bytes = slot[entry_header_size..][0..size] };
        try writeMetadata(&output, meta);
        put(u32, slot, 8, id);
        put(u16, slot, 12, metadataVersion(meta));
        put(u16, slot, 14, metadataFlags(meta));
        put(u32, slot, 16, @intCast(size));
        @memcpy(slot[24..40], &hash);
        put(u16, slot, 40, @intCast(meta.fields.len));
        put(u16, slot, 42, @intCast(meta.format_args.len));
        put(u32, slot, 20, entryChecksum(slot, output.bytes));
        const reference: Ref = .{ .id = id, .version = metadataVersion(meta), .hash = hash };
        const definition = try decodeDefinition(output.bytes, reference);
        self.entries[index].definition = definition;
        const committed = (@as(u64, id) << 2) | 2;
        state(slot).store(committed, .release);
        self.entries[index].marker = committed;
        return .{ .ref = reference, .requires_sync = true };
    }

    /// Resolving committed metadata is independent of this process's ready map.
    pub fn resolve(self: *Registry, reference: Ref) Error!Definition {
        const index = try self.indexFor(reference);
        const definition = (try decodeEntry(self.slotBytes(index), index, self.spec.max_definition_bytes)) orelse return error.MissingSchema;
        if (!std.mem.eql(u8, &definition.ref.hash, &reference.hash)) return error.MissingSchema;
        return definition;
    }

    pub fn validateReady(self: *Registry, reference: Ref) Error!void {
        const index = try self.indexFor(reference);
        const slot = self.slotBytes(index);
        if (get(u32, slot, 8) != reference.id or get(u16, slot, 12) != reference.version or !std.mem.eql(u8, slot[24..40], &reference.hash)) return error.MissingSchema;
        if (!self.entries[index].ready.load(.acquire)) return error.SchemaNotReady;
    }

    /// Metadata was strictly checked at registration/recovery and its storage
    /// is immutable. Hot submissions validate the reference then use this cache.
    pub fn resolveReady(self: *Registry, reference: Ref) Error!Definition {
        try self.validateReady(reference);
        return self.entries[reference.id - 1].definition.?;
    }

    pub fn markReady(self: *Registry, reference: Ref) Error!void {
        _ = try self.resolve(reference);
        self.entries[reference.id - 1].ready.store(true, .release);
    }

    /// Called only after the owner successfully syncs the complete mapping.
    pub fn markRecoveredReady(self: *Registry) Error!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.entries) |*entry| if (entry.definition) |definition| {
            _ = try self.resolve(definition.ref);
        };
        for (self.entries) |*entry| if (entry.definition != null) entry.ready.store(true, .release);
    }

    fn indexFor(self: *Registry, reference: Ref) Error!usize {
        if (!supportedVersion(reference.version)) return error.UnsupportedSchemaVersion;
        if (reference.id == 0 or reference.id > self.entries.len) return error.MissingSchema;
        const index: usize = reference.id - 1;
        const slot = self.slotBytes(index);
        if (state(slot).load(.acquire) != ((@as(u64, reference.id) << 2) | 2)) return error.MissingSchema;
        const definition = self.entries[index].definition orelse return error.MissingSchema;
        if (definition.ref.id != reference.id or definition.ref.version != reference.version or !std.mem.eql(u8, &definition.ref.hash, &reference.hash)) return error.MissingSchema;
        return index;
    }

    fn slotBytes(self: *Registry, index: usize) []align(64) u8 {
        return @alignCast(self.region[index * self.spec.stride ..][0..self.spec.stride]);
    }
};

fn state(slot: []align(64) u8) *std.atomic.Value(u64) {
    return @ptrCast(@alignCast(slot.ptr));
}
fn put(comptime T: type, bytes: []u8, offset: usize, value: T) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], value, .little);
}
fn get(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

test "schema extension roundtrip validates version layout checksum and budgets" {
    const spec = try layout(4096 + 4 * 128, 2, 512);
    var header: [4096]u8 = @splat(0);
    put(u32, &header, 8, 2);
    put(u64, &header, 16, 4);
    put(u64, &header, 32, 128);
    writeExtension(&header, spec, @splat(7));
    const restored = try readLayout(&header);
    try std.testing.expectEqual(spec.size, restored.size);
    try std.testing.expectEqual(@as(usize, 8192), restored.offset);
    try std.testing.expectEqual(@as(usize, 576), restored.stride);
    header[296] ^= 1;
    try std.testing.expectError(error.CorruptSchema, readLayout(&header));
    put(u32, &header, 8, 1);
    try std.testing.expectError(error.UnsupportedSchemaVersion, readLayout(&header));
    try std.testing.expectError(error.InvalidSchemaOptions, layout(4096, 0, 512));
    try std.testing.expectError(error.InvalidSchemaOptions, layout(std.math.maxInt(usize), 1, 512));
}

test "registry deduplicates metadata keeps types source and requires sync after restart" {
    var region: [2 * 576]u8 align(64) = @splat(0);
    const spec = try layout(4096, 2, 512);
    var registry = try Registry.init(std.testing.allocator, std.testing.io, &region, spec);
    defer registry.deinit();
    const meta: EventMeta = .{ .scope = "http", .message = "request {d}", .message_template = true, .source = @src(), .fields = &.{.{ .key = "tenant", .kind_mask = kindMask(.string) }}, .format_args = &.{.{ .key = "0", .kind_mask = kindMask(.unsigned) | kindMask(.null_value) }} };
    const first = try registry.register(meta);
    try std.testing.expect(first.requires_sync);
    try std.testing.expectError(error.SchemaNotReady, registry.validateReady(first.ref));
    try registry.markReady(first.ref);
    try registry.validateReady(first.ref);
    try std.testing.expect(!(try registry.register(meta)).requires_sync);
    const definition = try registry.resolve(first.ref);
    try std.testing.expect(metadataEqual(definition, meta));
    var fields_iterator = definition.fields();
    try std.testing.expectEqualStrings("tenant", (try fields_iterator.next()).?.key);
    const before = region;
    var reopened = try Registry.init(std.testing.allocator, std.testing.io, &region, spec);
    defer reopened.deinit();
    try std.testing.expectEqualSlices(u8, &before, &region);
    try std.testing.expect((try reopened.register(meta)).requires_sync);
    try reopened.markRecoveredReady();
    try reopened.validateReady(first.ref);
    var other = meta;
    other.scope = "db";
    try std.testing.expectEqual(@as(u32, 2), (try reopened.register(other)).ref.id);
    other.scope = "third";
    try std.testing.expectError(error.SchemaTableFull, reopened.register(other));
}

test "unfinished schema slots do not hide later entries or get reused" {
    var region: [3 * 576]u8 align(64) = @splat(0);
    put(u64, &region, 0, (1 << 2) | 1);
    const spec = try layout(4096, 3, 512);
    var registry = try Registry.init(std.testing.allocator, std.testing.io, &region, spec);
    defer registry.deinit();
    const second = try registry.register(.{ .scope = "later" });
    try std.testing.expectEqual(@as(u32, 2), second.ref.id);
    const before = region;
    try std.testing.expectEqualStrings("later", (try decodeEntry(region[576..][0..576], 1, 512)).?.scope);
    try std.testing.expectEqualSlices(u8, &before, &region);
    region[576 + 64 + 16 + 4] ^= 1;
    try std.testing.expectError(error.CorruptSchema, registry.resolve(second.ref));
    try std.testing.expectError(error.CorruptSchema, Registry.init(std.testing.allocator, std.testing.io, &region, spec));
}

test "content hash collisions still compare complete metadata before deduplication" {
    var region: [2 * 576]u8 align(64) = @splat(0);
    var registry = try Registry.init(std.testing.allocator, std.testing.io, &region, try layout(4096, 2, 512));
    defer registry.deinit();
    const first_meta: EventMeta = .{ .scope = "first", .fields = &.{.{ .key = "key", .kind_mask = kindMask(.string) }} };
    const second_meta: EventMeta = .{ .scope = "second", .fields = first_meta.fields };
    const first = try registry.register(first_meta);
    // Force a collision in the lookup prefilter, while preserving each real
    // on-disk content hash. Full comparison must allocate a distinct id.
    registry.entries[0].definition.?.ref.hash = try metadataHash(second_meta);
    const second = try registry.register(second_meta);
    registry.entries[0].definition.?.ref.hash = first.ref.hash;
    try std.testing.expect(first.ref.id != second.ref.id);
    try std.testing.expectEqualStrings("first", (try registry.resolve(first.ref)).scope);
    try std.testing.expectEqualStrings("second", (try registry.resolve(second.ref)).scope);
    try std.testing.expectEqual(second.ref.id, (try registry.register(second_meta)).ref.id);
}

test "metadata hash covers source keys kinds and scope but never event values" {
    const base: EventMeta = .{ .scope = "scope", .message = "{d}", .message_template = true, .fields = &.{.{ .key = "value", .kind_mask = kindMask(.signed) }}, .format_args = &.{.{ .key = "0", .kind_mask = kindMask(.unsigned) }} };
    const hash = try metadataHash(base);
    var variants = [_]EventMeta{base} ** 5;
    variants[0].scope = "other";
    variants[1].message = "value={d}";
    variants[2].source = @src();
    variants[3].fields = &.{.{ .key = "different", .kind_mask = kindMask(.signed) }};
    variants[4].fields = &.{.{ .key = "value", .kind_mask = kindMask(.unsigned) }};
    for (variants) |variant| try std.testing.expect(!std.mem.eql(u8, &hash, &try metadataHash(variant)));
    try std.testing.expectError(error.DuplicateKey, metadataHash(.{ .scope = "scope", .fields = &.{
        .{ .key = "duplicate", .kind_mask = kindMask(.boolean) }, .{ .key = "duplicate", .kind_mask = kindMask(.string) },
    } }));
}

test "schema registration deeply copies keys source format and scope once" {
    var region: [1088]u8 align(64) = @splat(0);
    var registry = try Registry.init(std.testing.allocator, std.testing.io, &region, try layout(4096, 1, 1024));
    defer registry.deinit();
    var scope = "mutable-scope".*;
    var key = "mutable-key".*;
    var format = "{s}".*;
    const meta: EventMeta = .{ .scope = &scope, .message = &format, .message_template = true, .fields = &.{.{ .key = &key, .kind_mask = kindMask(.string) }}, .format_args = &.{.{ .key = "0", .kind_mask = kindMask(.string) }} };
    const reference = (try registry.register(meta)).ref;
    @memset(&scope, 'x');
    @memset(&key, 'x');
    @memset(&format, 'x');
    const definition = try registry.resolve(reference);
    try std.testing.expectEqualStrings("mutable-scope", definition.scope);
    try std.testing.expectEqualStrings("{s}", definition.message.?);
    var iterator = definition.fields();
    try std.testing.expectEqualStrings("mutable-key", (try iterator.next()).?.key);
}

test "concurrent registration publishes one definition and readiness remains local" {
    var region: [2 * 576]u8 align(64) = @splat(0);
    var registry = try Registry.init(std.testing.allocator, std.testing.io, &region, try layout(4096, 2, 512));
    defer registry.deinit();
    const Worker = struct {
        fn run(reg: *Registry, output: *RegisterResult, failure: *?anyerror) void {
            output.* = reg.register(.{ .scope = "concurrent" }) catch |err| {
                failure.* = err;
                return;
            };
        }
    };
    var results: [4]RegisterResult = undefined;
    var failures: [4]?anyerror = @splat(null);
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, i| thread.* = try std.Thread.spawn(.{}, Worker.run, .{ &registry, &results[i], &failures[i] });
    for (threads) |thread| thread.join();
    for (results, failures) |result, failure| {
        if (failure) |err| return err;
        try std.testing.expectEqual(@as(u32, 1), result.ref.id);
        try std.testing.expect(result.requires_sync);
    }
    try registry.markReady(results[0].ref);
    for (results) |result| try registry.validateReady(result.ref);
    try std.testing.expectEqual(@as(u64, 0), get(u64, region[576..], 0));
}

test "invalid refs lengths and all committed definitions are checked without mutation" {
    var region: [2 * 576]u8 align(64) = @splat(0);
    const spec = try layout(4096, 2, 512);
    var registry = try Registry.init(std.testing.allocator, std.testing.io, &region, spec);
    defer registry.deinit();
    const first = (try registry.register(.{ .scope = "first" })).ref;
    _ = try registry.register(.{ .scope = "unreferenced" });
    var wrong = first;
    wrong.id = 0;
    try std.testing.expectError(error.MissingSchema, registry.resolve(wrong));
    wrong = first;
    wrong.hash[0] ^= 1;
    try std.testing.expectError(error.MissingSchema, registry.validateReady(wrong));
    wrong = first;
    wrong.version = 99;
    try std.testing.expectError(error.UnsupportedSchemaVersion, registry.resolve(wrong));
    for (0..entry_header_size) |length| try std.testing.expectError(error.TruncatedSchema, decodeEntry(region[0..length], 0, 512));
    put(u32, &region, 576 + 16, 513);
    const before = region;
    try std.testing.expectError(error.CorruptSchema, Registry.init(std.testing.allocator, std.testing.io, &region, spec));
    try std.testing.expectEqualSlices(u8, &before, &region);
    try std.testing.expectError(error.CorruptSchema, registry.markRecoveredReady());
    try std.testing.expectError(error.SchemaNotReady, registry.validateReady(first));
}

test "ready resolution uses validated cached definitions and rejects tampered references" {
    var region: [576]u8 align(64) = @splat(0);
    var registry = try Registry.init(std.testing.allocator, std.testing.io, &region, try layout(4096, 1, 512));
    defer registry.deinit();
    const reference = (try registry.register(.{ .scope = "cached", .message = "event" })).ref;
    try std.testing.expectError(error.SchemaNotReady, registry.resolveReady(reference));
    try registry.markReady(reference);
    const cached = try registry.resolveReady(reference);
    var public_copy = cached;
    public_copy.scope = "forged";
    public_copy.message = "forged event";
    try std.testing.expectEqualStrings("cached", (try registry.resolveReady(reference)).scope);
    try std.testing.expectEqualStrings("event", (try registry.resolveReady(reference)).message.?);
    // A changed CRC proves the hot method does not redo strict CRC/SHA/parse.
    // Definition bytes and all identity fields remain unchanged and immutable.
    region[20] ^= 1;
    try std.testing.expectError(error.CorruptSchema, registry.resolve(reference));
    try std.testing.expectEqualStrings("cached", (try registry.resolveReady(reference)).scope);
    var wrong = reference;
    wrong.id = 0;
    try std.testing.expectError(error.MissingSchema, registry.resolveReady(wrong));
    wrong = reference;
    wrong.version = 99;
    try std.testing.expectError(error.UnsupportedSchemaVersion, registry.resolveReady(wrong));
    wrong = reference;
    wrong.hash[0] ^= 1;
    try std.testing.expectError(error.MissingSchema, registry.resolveReady(wrong));
    region[24] ^= 1;
    try std.testing.expectError(error.MissingSchema, registry.resolveReady(reference));
    region[24] ^= 1;
    put(u32, &region, 8, reference.id + 1);
    try std.testing.expectError(error.MissingSchema, registry.resolveReady(reference));
    put(u32, &region, 8, reference.id);
    put(u16, &region, 12, 99);
    try std.testing.expectError(error.MissingSchema, registry.resolveReady(reference));
    put(u16, &region, 12, version);
    state(&region).store(0, .release);
    try std.testing.expectError(error.MissingSchema, registry.resolveReady(reference));
}

test "nested definition masks use version two while scalar definitions stay byte compatible" {
    const scalar: EventMeta = .{ .scope = "scalar", .fields = &.{.{ .key = "value", .kind_mask = kindMask(.string) }} };
    const nested: EventMeta = .{ .scope = "nested", .fields = &.{.{ .key = "value", .kind_mask = kindMask(.array) | kindMask(.group) }} };
    try std.testing.expectEqual(version, metadataVersion(scalar));
    try std.testing.expectEqual(nested_version, metadataVersion(nested));
    try std.testing.expectEqual(@as(u16, 0x7ff), all_kind_mask);
    var region: [2 * 576]u8 align(64) = @splat(0);
    const spec = try layout(4096, 2, 512);
    var registry = try Registry.init(std.testing.allocator, std.testing.io, &region, spec);
    defer registry.deinit();
    const old_ref = (try registry.register(scalar)).ref;
    const new_ref = (try registry.register(nested)).ref;
    try std.testing.expectEqual(version, old_ref.version);
    try std.testing.expectEqual(nested_version, new_ref.version);
    try std.testing.expectEqual(version, get(u16, &region, 64 + 4));
    try std.testing.expectEqual(nested_version, get(u16, &region, 576 + 64 + 4));
    var reopened = try Registry.init(std.testing.allocator, std.testing.io, &region, spec);
    defer reopened.deinit();
    try reopened.markRecoveredReady();
    const restored = try reopened.resolveReady(new_ref);
    var iterator = restored.fields();
    try std.testing.expectEqual(kindMask(.array) | kindMask(.group), (try iterator.next()).?.kind_mask);
    try std.testing.expectEqualDeep(new_ref, (try reopened.register(nested)).ref);
    try std.testing.expectEqualDeep(old_ref, (try reopened.register(scalar)).ref);
    var forged = new_ref;
    forged.version = version;
    try std.testing.expectError(error.MissingSchema, reopened.resolve(forged));
    var old_iterator: FieldIterator = .{ .input = .{ .bytes = restored.fields_wire }, .remaining = 1 };
    try std.testing.expectError(error.InvalidSchema, old_iterator.next());
}
