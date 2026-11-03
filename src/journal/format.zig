//! File protocols v1/v2: explicitly little-endian integers, never Zig structs or
//! pointers. The immutable header occupies bytes 0..64. Atomic next-sequence
//! and written progress occupy offsets 64 and 72. Two checksummed durable
//! checkpoints occupy offsets 128 and 192. Slots start at offset 4096, each
//! aligned to 64 bytes: atomic tagged state (0), sequence (8), generation (16),
//! payload length (24), CRC32 (28), then payload at offset 64.
//! V2 adds a schema extension at 256..320 and a fixed table after the data
//! region. Slot bytes 32..56 hold id/version/reserved/hash and join the CRC.
const std = @import("std");
const Crc32 = @import("../platform/crc32.zig").Crc32;

pub const magic = "KRONJNL1";
pub const version: u32 = 1;
pub const schema_version_v2: u32 = 2;
pub const schema_version: u32 = 3;
pub const header_bytes: usize = 4096;
pub const slot_header_bytes: usize = 64;
pub const max_sequence = std.math.maxInt(u64) >> 2;
pub const State = enum(u2) { empty = 0, reserved = 1, committed = 2, aborted = 3 };

pub fn put(comptime T: type, bytes: []u8, offset: usize, value: T) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], value, .little);
}
pub fn get(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
pub fn tag(sequence: u64, state: State) u64 {
    return (sequence << 2) | @intFromEnum(state);
}
pub fn checksum(sequence: u64, generation: u64, payload: []const u8) u32 {
    var header: [20]u8 = undefined;
    put(u64, &header, 0, sequence);
    put(u64, &header, 8, generation);
    put(u32, &header, 16, @intCast(payload.len));
    var crc = Crc32.init();
    crc.update(&header);
    crc.update(payload);
    return crc.final();
}

pub fn checksumV2(sequence: u64, generation: u64, reference_bytes: []const u8, payload: []const u8) u32 {
    std.debug.assert(reference_bytes.len == 24);
    var header: [20]u8 = undefined;
    put(u64, &header, 0, sequence);
    put(u64, &header, 8, generation);
    put(u32, &header, 16, @intCast(payload.len));
    var crc = Crc32.init();
    crc.update(&header);
    crc.update(reference_bytes);
    crc.update(payload);
    return crc.final();
}

/// V3 CRC covers the reference, the eight zero padding bytes and the payload.
/// The journal slot keeps the reference and padding contiguous, so the
/// producer and consumer fold them with the payload in one update.
pub fn checksumV3(sequence: u64, generation: u64, reference_and_padding: []const u8, payload: []const u8) u32 {
    std.debug.assert(reference_and_padding.len == 32);
    var header: [20]u8 = undefined;
    put(u64, &header, 0, sequence);
    put(u64, &header, 8, generation);
    put(u32, &header, 16, @intCast(payload.len));
    var crc = Crc32.init();
    crc.update(&header);
    crc.update(reference_and_padding);
    crc.update(payload);
    return crc.final();
}

/// Computes the V3 slot CRC directly from contiguous slot bytes. Bytes 8..28
/// are the sequence/generation/length header, 28..32 hold the stored CRC and
/// 32..slot_header_bytes hold the reference plus zero padding.
pub fn checksumV3Slot(bytes: []const u8, length: usize) u32 {
    std.debug.assert(bytes.len >= slot_header_bytes + length);
    var crc = Crc32.init();
    crc.update(bytes[8..28]);
    crc.update(bytes[32 .. slot_header_bytes + length]);
    return crc.final();
}

test "slot CRC v1 and v2 preserve independent golden byte order and schema binding" {
    const payload = "kron slot golden\x00\xff";
    var reference: [24]u8 = undefined;
    for (&reference, 0..) |*byte, i| byte.* = @intCast(i);
    // Constants independently calculated by Python zlib.crc32 over the
    // explicit little-endian 20-byte header, reference, and payload.
    try std.testing.expectEqual(@as(u32, 0x2f07cd99), checksum(0x0102030405060708, 0x1122334455667788, payload));
    try std.testing.expectEqual(@as(u32, 0x530df33b), checksumV2(0x0102030405060708, 0x1122334455667788, &reference, payload));
}

test "slot CRC v3 covers reference and zero padding with contiguous slot bytes" {
    const payload = "kron slot golden\x00\xff";
    var reference: [24]u8 = undefined;
    for (&reference, 0..) |*byte, i| byte.* = @intCast(i);
    var reference_and_padding: [32]u8 = undefined;
    @memcpy(reference_and_padding[0..24], &reference);
    @memset(reference_and_padding[24..], 0);
    // Independently calculated by Python zlib.crc32 over header + reference + eight zero padding bytes + payload.
    try std.testing.expectEqual(@as(u32, 0x4be88818), checksumV3(0x0102030405060708, 0x1122334455667788, &reference_and_padding, payload));
    var slot: [slot_header_bytes + payload.len]u8 = undefined;
    @memset(&slot, 0);
    put(u64, &slot, 8, 0x0102030405060708);
    put(u64, &slot, 16, 0x1122334455667788);
    put(u32, &slot, 24, payload.len);
    @memcpy(slot[32..56], &reference);
    @memcpy(slot[slot_header_bytes..], payload);
    try std.testing.expectEqual(@as(u32, 0x4be88818), checksumV3Slot(&slot, payload.len));
    // The stored CRC at 28..32 is outside the V3 input.
    put(u32, &slot, 28, 0xdeadbeef);
    try std.testing.expectEqual(@as(u32, 0x4be88818), checksumV3Slot(&slot, payload.len));
}

test "v3 slot checksum matches independent oracle across payload lengths" {
    var slot: [slot_header_bytes + 512]u8 = undefined;
    var reference: [24]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x763370616464696e);
    random.random().bytes(&reference);
    const lengths = [_]usize{ 0, 1, 3, 7, 8, 15, 16, 20, 24, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512 };
    for (lengths) |length| {
        random.random().bytes(&slot);
        @memset(slot[56..64], 0);
        @memcpy(slot[32..56], &reference);
        const sequence = random.random().int(u64);
        const generation = random.random().int(u64);
        put(u64, &slot, 8, sequence);
        put(u64, &slot, 16, generation);
        put(u32, &slot, 24, @intCast(length));
        var header: [20]u8 = undefined;
        std.mem.writeInt(u64, header[0..8], sequence, .little);
        std.mem.writeInt(u64, header[8..16], generation, .little);
        std.mem.writeInt(u32, header[16..20], @intCast(length), .little);
        var oracle = std.hash.Crc32.init();
        oracle.update(&header);
        oracle.update(slot[32..64]);
        oracle.update(slot[64 .. 64 + length]);
        try std.testing.expectEqual(oracle.final(), checksumV3Slot(&slot, length));
        try std.testing.expectEqual(oracle.final(), checksumV3(sequence, generation, slot[32..64], slot[64 .. 64 + length]));
    }
}

test "zeroed initialization matches full clear for memory-backed journals" {
    const capacity = 2;
    const stride = 128;
    const identity = [_]u8{7} ** 16;
    var full: [header_bytes + capacity * stride]u8 = undefined;
    var zeroed: [header_bytes + capacity * stride]u8 = undefined;
    @memset(&full, 0xa5);
    @memset(&zeroed, 0);
    initialize(&full, capacity, 16, stride, identity);
    initializeZeroed(&zeroed, capacity, 16, stride, identity);
    try std.testing.expectEqualSlices(u8, &full, &zeroed);
    @memset(&full, 0xa5);
    @memset(&zeroed, 0);
    initializeV2(&full, capacity, 16, stride, identity);
    initializeV2Zeroed(&zeroed, capacity, 16, stride, identity);
    try std.testing.expectEqualSlices(u8, &full, &zeroed);
}

pub fn layout(capacity: usize, max_record_bytes: usize) !struct { stride: usize, size: usize } {
    if (capacity == 0 or max_record_bytes == 0 or max_record_bytes > std.math.maxInt(u32)) return error.InvalidOptions;
    const raw = std.math.add(usize, slot_header_bytes, max_record_bytes) catch return error.InvalidOptions;
    const padded = std.math.add(usize, raw, 63) catch return error.InvalidOptions;
    const stride = padded & ~@as(usize, 63);
    const data = std.math.mul(usize, stride, capacity) catch return error.InvalidOptions;
    const size = std.math.add(usize, header_bytes, data) catch return error.InvalidOptions;
    if (size > std.math.maxInt(i64) or capacity > max_sequence) return error.InvalidOptions;
    return .{ .stride = stride, .size = size };
}

pub fn initialize(bytes: []u8, capacity: usize, max_record_bytes: usize, stride: usize, identity: [16]u8) void {
    initializeVersion(bytes, capacity, max_record_bytes, stride, identity, version);
}

pub fn initializeV2(bytes: []u8, capacity: usize, max_record_bytes: usize, stride: usize, identity: [16]u8) void {
    initializeVersion(bytes, capacity, max_record_bytes, stride, identity, schema_version_v2);
}

pub fn initializeV3(bytes: []u8, capacity: usize, max_record_bytes: usize, stride: usize, identity: [16]u8) void {
    initializeVersion(bytes, capacity, max_record_bytes, stride, identity, schema_version);
}

/// Initializes a storage buffer whose complete contents are already zero.
/// Memory storage guarantees this after its single writable clear; file
/// mappings must keep using `initialize`/`initializeV2` so stale bytes in a
/// reused mapping cannot survive as valid-looking slot payloads.
pub fn initializeZeroed(bytes: []u8, capacity: usize, max_record_bytes: usize, stride: usize, identity: [16]u8) void {
    initializeVersionZeroed(bytes, capacity, max_record_bytes, stride, identity, version);
}

pub fn initializeV2Zeroed(bytes: []u8, capacity: usize, max_record_bytes: usize, stride: usize, identity: [16]u8) void {
    initializeVersionZeroed(bytes, capacity, max_record_bytes, stride, identity, schema_version_v2);
}

pub fn initializeV3Zeroed(bytes: []u8, capacity: usize, max_record_bytes: usize, stride: usize, identity: [16]u8) void {
    initializeVersionZeroed(bytes, capacity, max_record_bytes, stride, identity, schema_version);
}

fn initializeVersion(bytes: []u8, capacity: usize, max_record_bytes: usize, stride: usize, identity: [16]u8, file_version: u32) void {
    @memset(bytes, 0);
    initializeVersionZeroed(bytes, capacity, max_record_bytes, stride, identity, file_version);
}

fn initializeVersionZeroed(bytes: []u8, capacity: usize, max_record_bytes: usize, stride: usize, identity: [16]u8, file_version: u32) void {
    @memcpy(bytes[0..8], magic);
    put(u32, bytes, 8, file_version);
    put(u32, bytes, 12, 0x01020304);
    put(u64, bytes, 16, capacity);
    put(u64, bytes, 24, max_record_bytes);
    put(u64, bytes, 32, stride);
    @memcpy(bytes[40..56], &identity);
    put(u32, bytes, 56, header_bytes);
    put(u32, bytes, 60, std.hash.Crc32.hash(bytes[0..60]));
    writeCheckpoint(bytes, 0, 1, 0);
}

pub fn validate(bytes: []const u8, capacity: usize, max_record_bytes: usize, stride: usize) !void {
    return validateVersion(bytes, capacity, max_record_bytes, stride, version);
}

pub fn validateV2(bytes: []const u8, capacity: usize, max_record_bytes: usize, stride: usize) !void {
    return validateVersion(bytes, capacity, max_record_bytes, stride, schema_version_v2);
}

pub fn validateV3(bytes: []const u8, capacity: usize, max_record_bytes: usize, stride: usize) !void {
    return validateVersion(bytes, capacity, max_record_bytes, stride, schema_version);
}

fn validateVersion(bytes: []const u8, capacity: usize, max_record_bytes: usize, stride: usize, file_version: u32) !void {
    if (!std.mem.eql(u8, bytes[0..8], magic)) return error.InvalidJournal;
    if (get(u32, bytes, 8) != file_version) return error.UnsupportedVersion;
    if (get(u32, bytes, 12) != 0x01020304 or get(u32, bytes, 56) != header_bytes) return error.InvalidJournal;
    if (get(u32, bytes, 60) != std.hash.Crc32.hash(bytes[0..60])) return error.CorruptHeader;
    if (get(u64, bytes, 16) != capacity or get(u64, bytes, 24) != max_record_bytes or get(u64, bytes, 32) != stride) return error.LayoutMismatch;
}

pub const Checkpoint = struct { epoch: u64, sequence: u64 };
pub fn writeCheckpoint(bytes: []u8, index: usize, epoch: u64, sequence: u64) void {
    const entry = bytes[128 + index * 64 ..][0..64];
    @memset(entry, 0);
    put(u64, entry, 0, epoch);
    put(u64, entry, 8, sequence);
    put(u32, entry, 16, std.hash.Crc32.hash(entry[0..16]));
}
pub fn checkpoint(bytes: []const u8) !Checkpoint {
    var best: ?Checkpoint = null;
    for (0..2) |index| {
        const entry = bytes[128 + index * 64 ..][0..64];
        const epoch = get(u64, entry, 0);
        const sequence = get(u64, entry, 8);
        if (epoch == 0 or sequence > max_sequence or get(u32, entry, 16) != std.hash.Crc32.hash(entry[0..16])) continue;
        if (best == null or epoch > best.?.epoch) best = .{ .epoch = epoch, .sequence = sequence };
    }
    return best orelse error.CorruptCheckpoint;
}
