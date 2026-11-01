//! Optional compatibility qualification against the actual sibling Vort source.
//! This executable is independent of kron's runtime dependency graph.
const std = @import("std");
const vort = @import("vort_checksum");
const journal = @import("journal/format.zig");
const archive = @import("archive/format.zig");
const compression = @import("archive/compression.zig");

pub fn main(_: std.process.Init) !void {
    var bytes: [65_552]u8 = undefined;
    var seed: u64 = 0x6b726f6e5f637263;
    for (&bytes) |*byte| {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        byte.* = @truncate(seed);
    }
    try same(0xcbf43926, vort.crc32Best("123456789"));
    if (vort.crc32cBest("123456789") == vort.crc32Best("123456789")) return error.PolynomialConfusion;
    const lengths = [_]usize{ 0, 1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 33, 63, 64, 65, 84, 127, 128, 129, 256, 512, 1024, 4096, 8192, 16384, 65536 };
    var cases: usize = 0;
    for (0..16) |offset| for (lengths) |length| {
        const payload = bytes[offset..][0..length];
        const expected = archive.frameCRC(payload);
        try same(expected, vort.crc32Best(payload));
        try same(expected, vort.crc32Slice32(payload));
        const split = length / 3;
        try same(expected, vort.crc32UpdateBest(vort.crc32Best(payload[0..split]), payload[split..]));
        try same(expected, vort.crc32Combine(vort.crc32Best(payload[0..split]), vort.crc32Best(payload[split..]), @intCast(length - split)));

        // Exercise the exact little-endian persisted journal binding and v2
        // schema-reference continuation, including empty and unaligned inputs.
        const sequence: u64 = 1 + @as(u64, @intCast(offset * lengths.len + cases));
        const generation: u64 = 0x1020304050607080;
        var header: [20]u8 = undefined;
        std.mem.writeInt(u64, header[0..8], sequence, .little);
        std.mem.writeInt(u64, header[8..16], generation, .little);
        std.mem.writeInt(u32, header[16..20], @intCast(length), .little);
        const prefix_crc = vort.crc32Best(&header);
        try same(journal.checksum(sequence, generation, payload), vort.crc32UpdateBest(prefix_crc, payload));
        const reference = bytes[3..27];
        try same(journal.checksumV2(sequence, generation, reference, payload), vort.crc32UpdateBest(vort.crc32UpdateBest(prefix_crc, reference), payload));

        const block_header = compression.headerBytes(.{ .uncompressed_len = @intCast(length), .compressed_len = 9, .crc32 = expected, .record_count = 1 });
        try same(std.mem.readInt(u32, block_header[28..32], .little), vort.crc32Best(block_header[0..28]));
        cases += 1;
    };
    std.debug.print("local Vort: {d} cases passed; IEEE CRC32, alignment, incremental/combine, journal v1/v2 and archive block header; backend={s}\n", .{ cases, @tagName(vort.bestCrc32Dispatch()) });
}

fn same(expected: u32, actual: u32) !void {
    if (expected != actual) return error.ChecksumInteroperabilityFailed;
}
