//! Portable IEEE CRC32/ISO-HDLC with a sixteen-byte slicing table. Native
//! x86_64 builds whose compile-time target advertises PCLMUL+SSE2 also fold
//! 64-byte blocks with carry-less multiply; generic and non-x86 targets keep
//! the portable table. The persisted polynomial, reflection and final XOR are
//! identical. No runtime probing, allocation or external package is needed.
const std = @import("std");
const builtin = @import("builtin");
const polynomial: u32 = 0xedb88320;
const tables = makeTables();
const use_pclmul = switch (builtin.cpu.arch) {
    .x86_64 => std.Target.x86.featureSetHas(builtin.cpu.features, .pclmul) and
        std.Target.x86.featureSetHas(builtin.cpu.features, .sse2),
    else => false,
};
const pclmul = if (use_pclmul) @import("crc32_pclmul.zig") else struct {};

pub const Crc32 = struct {
    state: u32 = 0xffffffff,

    pub fn init() Crc32 {
        return .{};
    }

    pub fn update(self: *Crc32, bytes: []const u8) void {
        if (comptime use_pclmul) {
            if (bytes.len >= 64) {
                // Fold a multiple-of-16 prefix with PCLMUL, then finish the
                // <16-byte tail with the identical portable state machine.
                const bulk = bytes.len - bytes.len % 16;
                var crc = pclmul.update(self.state, bytes[0..bulk]);
                for (bytes[bulk..]) |byte| crc = tables[0][@as(u8, @truncate(crc)) ^ byte] ^ (crc >> 8);
                self.state = crc;
                return;
            }
        }
        var crc = self.state;
        var offset: usize = 0;
        while (bytes.len - offset >= 16) : (offset += 16) {
            const first = std.mem.readInt(u32, bytes[offset..][0..4], .little) ^ crc;
            const second = std.mem.readInt(u32, bytes[offset + 4 ..][0..4], .little);
            const third = std.mem.readInt(u32, bytes[offset + 8 ..][0..4], .little);
            const fourth = std.mem.readInt(u32, bytes[offset + 12 ..][0..4], .little);
            crc = tables[15][first & 255] ^ tables[14][(first >> 8) & 255] ^ tables[13][(first >> 16) & 255] ^ tables[12][first >> 24] ^
                tables[11][second & 255] ^ tables[10][(second >> 8) & 255] ^ tables[9][(second >> 16) & 255] ^ tables[8][second >> 24] ^
                tables[7][third & 255] ^ tables[6][(third >> 8) & 255] ^ tables[5][(third >> 16) & 255] ^ tables[4][third >> 24] ^
                tables[3][fourth & 255] ^ tables[2][(fourth >> 8) & 255] ^ tables[1][(fourth >> 16) & 255] ^ tables[0][fourth >> 24];
        }
        while (bytes.len - offset >= 8) : (offset += 8) {
            const lo = std.mem.readInt(u32, bytes[offset..][0..4], .little) ^ crc;
            const hi = std.mem.readInt(u32, bytes[offset + 4 ..][0..4], .little);
            crc = tables[7][lo & 255] ^ tables[6][(lo >> 8) & 255] ^ tables[5][(lo >> 16) & 255] ^ tables[4][lo >> 24] ^
                tables[3][hi & 255] ^ tables[2][(hi >> 8) & 255] ^ tables[1][(hi >> 16) & 255] ^ tables[0][hi >> 24];
        }
        for (bytes[offset..]) |byte| crc = tables[0][@as(u8, @truncate(crc)) ^ byte] ^ (crc >> 8);
        self.state = crc;
    }

    pub fn final(self: Crc32) u32 {
        return ~self.state;
    }

    pub fn hash(bytes: []const u8) u32 {
        var crc = init();
        crc.update(bytes);
        return crc.final();
    }
};

fn makeTables() [16][256]u32 {
    @setEvalBranchQuota(80_000);
    var result: [16][256]u32 = undefined;
    for (&result[0], 0..) |*entry, index| {
        var value: u32 = @intCast(index);
        for (0..8) |_| value = if (value & 1 != 0) (value >> 1) ^ polynomial else value >> 1;
        entry.* = value;
    }
    for (1..16) |slice| for (0..256) |index| {
        const previous = result[slice - 1][index];
        result[slice][index] = (previous >> 8) ^ result[0][previous & 255];
    };
    return result;
}

test "sliced IEEE CRC32 standard vectors match the persisted polynomial" {
    try std.testing.expectEqual(@as(u32, 0), Crc32.hash(""));
    try std.testing.expectEqual(@as(u32, 0xcbf43926), Crc32.hash("123456789"));
    try std.testing.expectEqual(@as(u32, 0x414fa339), Crc32.hash("The quick brown fox jumps over the lazy dog"));
    try std.testing.expect(Crc32.hash("123456789") != std.hash.crc.Crc32Iscsi.hash("123456789"));
}

test "sliced CRC matches standard oracle across lengths alignments and incremental partitions" {
    var bytes: [4096 + 16]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x6b726f6e63726338);
    random.random().bytes(&bytes);
    const lengths = [_]usize{ 0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 19, 20, 21, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 512, 1024, 2048, 4096 };
    for (0..16) |alignment| for (lengths) |length| {
        const payload = bytes[alignment..][0..length];
        const expected = std.hash.Crc32.hash(payload);
        try std.testing.expectEqual(expected, Crc32.hash(payload));
        for ([_]usize{ 0, @min(length, 1), length / 2, length }) |split| {
            var crc = Crc32.init();
            crc.update(payload[0..split]);
            crc.update(&.{});
            crc.update(payload[split..]);
            try std.testing.expectEqual(expected, crc.final());
        }
    };
    for (0..256) |byte| {
        const one = [_]u8{@intCast(byte)};
        try std.testing.expectEqual(std.hash.Crc32.hash(&one), Crc32.hash(&one));
    }
}

test "sixteen-byte slicing preserves every block boundary and journal header partition" {
    var bytes: [65536 + 32]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x6b726f6e63726336);
    random.random().bytes(&bytes);
    const lengths = [_]usize{ 0, 7, 8, 9, 15, 16, 17, 23, 24, 25, 31, 32, 33, 47, 48, 49, 63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512, 513, 1023, 1024, 1025, 4095, 4096, 4097, 65535, 65536 };
    for (0..32) |offset| for (lengths) |length| {
        const payload = bytes[offset..][0..length];
        const oracle = std.hash.Crc32.hash(payload);
        try std.testing.expectEqual(oracle, Crc32.hash(payload));
        for ([_]usize{ 1, 7, 8, 15, 16, 17, 20, 24, 44, length / 2 }) |boundary| {
            const split = @min(boundary, length);
            var crc = Crc32.init();
            crc.update(payload[0..split]);
            crc.update(payload[split..]);
            try std.testing.expectEqual(oracle, crc.final());
        }
    };
}

test "compile-time PCLMUL path matches the portable oracle across block and partition boundaries" {
    if (!use_pclmul) return error.SkipZigTest;
    var bytes: [70064]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x70636c6d756c);
    random.random().bytes(&bytes);
    const lengths = [_]usize{ 64, 65, 79, 80, 95, 96, 127, 128, 129, 255, 256, 257, 1023, 1024, 1025, 4095, 4096, 4097, 65535, 65536, 65537, 69999 };
    for (0..32) |offset| for (lengths) |length| {
        const payload = bytes[offset..][0..length];
        const oracle = std.hash.Crc32.hash(payload);
        try std.testing.expectEqual(oracle, Crc32.hash(payload));
        for ([_]usize{ 1, 15, 16, 17, 63, 64, 65, 79, 80, 127, 128, 129, length / 2, length - 1 }) |split0| {
            const split = @min(split0, length);
            var crc = Crc32.init();
            crc.update(payload[0..split]);
            crc.update(payload[split..]);
            try std.testing.expectEqual(oracle, crc.final());
        }
    };
}
