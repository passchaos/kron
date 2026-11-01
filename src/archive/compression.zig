//! Independent, bounded RFC1950 zlib/DEFLATE blocks around whole archive frames.
//! All integer fields are little endian; no Zig struct layout is persisted.
const std = @import("std");
const frame = @import("format.zig");

pub const magic = "KRONCMP1";
pub const version: u16 = 1;
pub const header_size: usize = 32;
pub const max_uncompressed_len: usize = 64 * 1024;
pub const max_compressed_len: usize = max_uncompressed_len * 2 + 1024;
pub const window_bytes = std.compress.flate.max_window_len;
pub const Algorithm = enum(u8) { deflate_zlib = 1 };
pub const Header = struct {
    version: u16 = version,
    algorithm: Algorithm = .deflate_zlib,
    flags: u8 = 0,
    uncompressed_len: u32,
    compressed_len: u32,
    crc32: u32,
    record_count: u32,
};
pub const ValidationError = error{
    Truncated,
    InvalidMagic,
    UnsupportedVersion,
    UnsupportedAlgorithm,
    InvalidFlags,
    CorruptHeader,
    InvalidLength,
    BlockTooLarge,
    InvalidFrame,
    CorruptFrame,
    InvalidCompressedData,
    DecompressedLengthMismatch,
    TrailingCompressedData,
    CorruptPayload,
    RecordCountMismatch,
    InvalidBufferBudget,
};

pub fn headerBytes(header: Header) [header_size]u8 {
    var bytes: [header_size]u8 = undefined;
    @memcpy(bytes[0..8], magic);
    std.mem.writeInt(u16, bytes[8..10], header.version, .little);
    bytes[10] = @intFromEnum(header.algorithm);
    bytes[11] = header.flags;
    std.mem.writeInt(u32, bytes[12..16], header.uncompressed_len, .little);
    std.mem.writeInt(u32, bytes[16..20], header.compressed_len, .little);
    std.mem.writeInt(u32, bytes[20..24], header.crc32, .little);
    std.mem.writeInt(u32, bytes[24..28], header.record_count, .little);
    std.mem.writeInt(u32, bytes[28..32], std.hash.Crc32.hash(bytes[0..28]), .little);
    return bytes;
}

pub fn validate(bytes: []const u8) ValidationError!Header {
    if (bytes.len < header_size) return error.Truncated;
    if (!std.mem.eql(u8, bytes[0..8], magic)) return error.InvalidMagic;
    if (std.mem.readInt(u32, bytes[28..32], .little) != std.hash.Crc32.hash(bytes[0..28])) return error.CorruptHeader;
    const algorithm = std.enums.fromInt(Algorithm, bytes[10]) orelse return error.UnsupportedAlgorithm;
    const header: Header = .{
        .version = std.mem.readInt(u16, bytes[8..10], .little),
        .algorithm = algorithm,
        .flags = bytes[11],
        .uncompressed_len = std.mem.readInt(u32, bytes[12..16], .little),
        .compressed_len = std.mem.readInt(u32, bytes[16..20], .little),
        .crc32 = std.mem.readInt(u32, bytes[20..24], .little),
        .record_count = std.mem.readInt(u32, bytes[24..28], .little),
    };
    if (header.version != version) return error.UnsupportedVersion;
    if (header.flags != 0) return error.InvalidFlags;
    if (header.uncompressed_len > max_uncompressed_len or header.compressed_len > max_compressed_len) return error.BlockTooLarge;
    if (header.uncompressed_len < frame.header_size or header.compressed_len < 6 or header.record_count == 0 or header.record_count > header.uncompressed_len / frame.header_size) return error.InvalidLength;
    return header;
}

/// Conservative workspace/output budget, not a promise of compressibility.
/// Stored/fixed DEFLATE can expand incompressible data; reserve that headroom.
pub fn compressedBound(raw_bytes: usize) ValidationError!usize {
    if (raw_bytes == 0 or raw_bytes > max_uncompressed_len) return error.InvalidBufferBudget;
    return raw_bytes * 2 + 1024;
}

pub fn validateFrame(record: []const u8) ValidationError!void {
    const header = frame.validate(record) catch return error.InvalidFrame;
    const length = std.math.add(usize, header.payload_len, frame.header_size) catch return error.InvalidFrame;
    if (length != record.len) return error.InvalidFrame;
    if (frame.frameCRC(record[frame.header_size..]) != header.crc32) return error.CorruptFrame;
}

pub fn validateFrames(raw: []const u8, expected_count: u32) ValidationError!void {
    var offset: usize = 0;
    var count: u32 = 0;
    while (offset < raw.len) {
        const header = frame.validate(raw[offset..]) catch return error.InvalidFrame;
        const length = std.math.add(usize, header.payload_len, frame.header_size) catch return error.InvalidFrame;
        if (length > raw.len - offset) return error.InvalidFrame;
        try validateFrame(raw[offset..][0..length]);
        offset += length;
        count += 1;
    }
    if (count != expected_count) return error.RecordCountMismatch;
}

/// Heap-owned encoder state and history are initialized once. Encoding and
/// decoding call no allocator. Each call creates a fresh independent zlib stream.
pub const Workspace = struct {
    allocator: std.mem.Allocator,
    encoder: *std.compress.flate.Compress,
    window: []u8,

    pub fn init(allocator: std.mem.Allocator) !Workspace {
        const encoder = try allocator.create(std.compress.flate.Compress);
        errdefer allocator.destroy(encoder);
        const window = try allocator.alloc(u8, window_bytes);
        @memset(window, 0);
        return .{ .allocator = allocator, .encoder = encoder, .window = window };
    }

    pub fn deinit(self: *Workspace) void {
        self.allocator.free(self.window);
        self.allocator.destroy(self.encoder);
        self.* = undefined;
    }

    pub fn compress(self: *Workspace, raw: []const u8, output: []u8) ![]const u8 {
        if (raw.len == 0 or raw.len > max_uncompressed_len or output.len < 9) return error.InvalidBufferBudget;
        var writer = std.Io.Writer.fixed(output);
        self.encoder.* = try std.compress.flate.Compress.init(&writer, self.window, .zlib, .fastest);
        try self.encoder.writer.writeAll(raw);
        try self.encoder.finish();
        return writer.buffered();
    }
};

pub const Decoded = struct { header: Header, raw: []const u8, consumed: usize };

/// Decode exactly one complete block. Extra bytes after that block belong to
/// the next block. Caller storage stays borrowed until the next decode.
pub fn decodeBlock(bytes: []const u8, output: []u8, window: []u8) ValidationError!Decoded {
    const header = try validate(bytes);
    const total = header_size + @as(usize, header.compressed_len);
    if (bytes.len < total) return error.Truncated;
    if (output.len < header.uncompressed_len or window.len < window_bytes) return error.InvalidBufferBudget;
    var input = std.Io.Reader.fixed(bytes[header_size..total]);
    var inflater = std.compress.flate.Decompress.init(&input, .zlib, window);
    const raw = output[0..header.uncompressed_len];
    inflater.reader.readSliceAll(raw) catch return error.InvalidCompressedData;
    var extra: [1]u8 = undefined;
    const extra_count = inflater.reader.readSliceShort(&extra) catch return error.InvalidCompressedData;
    if (extra_count != 0) return error.DecompressedLengthMismatch;
    if (inflater.err != null) return error.InvalidCompressedData;
    if (input.seek != input.end) return error.TrailingCompressedData;
    if (std.hash.Crc32.hash(raw) != header.crc32) return error.CorruptPayload;
    try validateFrames(raw, header.record_count);
    return .{ .header = header, .raw = raw, .consumed = total };
}
