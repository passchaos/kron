const std = @import("std");

/// Every record is independently framed; no process-local schema is required.
pub const magic = "KRONARC1";
pub const version: u32 = 1;
pub const header_size = 24;
pub const Header = struct {
    version: u32 = 1,
    payload_len: u32,
    crc32: u32,
    reserved: u32 = 0,
};
pub const ValidationError = error{ Truncated, InvalidMagic, UnsupportedVersion, InvalidReserved };

pub fn headerBytes(header: Header) [header_size]u8 {
    var bytes: [header_size]u8 = undefined;
    @memcpy(bytes[0..8], magic);
    std.mem.writeInt(u32, bytes[8..12], header.version, .little);
    std.mem.writeInt(u32, bytes[12..16], header.payload_len, .little);
    std.mem.writeInt(u32, bytes[16..20], header.crc32, .little);
    std.mem.writeInt(u32, bytes[20..24], header.reserved, .little);
    return bytes;
}

/// Validates the header only. A reader separately checks its payload budget,
/// complete payload length, frameCRC, and the self-contained codec version.
pub fn validate(bytes: []const u8) ValidationError!Header {
    if (bytes.len < header_size) return error.Truncated;
    if (!std.mem.eql(u8, bytes[0..8], magic)) return error.InvalidMagic;
    const result: Header = .{
        .version = std.mem.readInt(u32, bytes[8..12], .little),
        .payload_len = std.mem.readInt(u32, bytes[12..16], .little),
        .crc32 = std.mem.readInt(u32, bytes[16..20], .little),
        .reserved = std.mem.readInt(u32, bytes[20..24], .little),
    };
    if (result.version != version) return error.UnsupportedVersion;
    if (result.reserved != 0) return error.InvalidReserved;
    return result;
}

/// CRC-32/ISO-HDLC over payload bytes only (same polynomial as IEEE CRC32).
pub fn frameCRC(payload: []const u8) u32 {
    return std.hash.Crc32.hash(payload);
}

test "archive frame header golden and CRC32 standard vector" {
    const bytes = headerBytes(.{ .payload_len = 0x01020304, .crc32 = 0xaabbccdd });
    try std.testing.expectEqualSlices(u8, &.{ 'K', 'R', 'O', 'N', 'A', 'R', 'C', '1', 1, 0, 0, 0, 4, 3, 2, 1, 0xdd, 0xcc, 0xbb, 0xaa, 0, 0, 0, 0 }, &bytes);
    const parsed = try validate(&bytes);
    try std.testing.expectEqual(@as(u32, 0x01020304), parsed.payload_len);
    try std.testing.expectEqual(@as(u32, 0xaabbccdd), parsed.crc32);
    try std.testing.expectEqual(@as(u32, 0xcbf43926), frameCRC("123456789"));
}

test "archive headers reject truncation, magic, version and reserved bits" {
    var bytes = headerBytes(.{ .payload_len = 12, .crc32 = 0 });
    for (0..header_size) |length| try std.testing.expectError(error.Truncated, validate(bytes[0..length]));
    bytes[0] ^= 1;
    try std.testing.expectError(error.InvalidMagic, validate(&bytes));
    bytes[0] ^= 1;
    bytes[8] = 2;
    try std.testing.expectError(error.UnsupportedVersion, validate(&bytes));
    bytes[8] = 1;
    bytes[20] = 1;
    try std.testing.expectError(error.InvalidReserved, validate(&bytes));
}
