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
const pclmul = @import("candidate.zig");

pub fn Crc32(comptime mode: pclmul.Collapse) type {
    return struct {
        state: u32 = 0xffffffff,

        pub fn init() @This() {
            return .{};
        }

        pub fn update(self: *@This(), bytes: []const u8) void {
            if (comptime use_pclmul) {
                if (bytes.len >= 64) {
                    // Fold a multiple-of-16 prefix with PCLMUL, then finish the
                    // <16-byte tail with the identical portable state machine.
                    const bulk = bytes.len - bytes.len % 16;
                    var crc = pclmul.update(mode, self.state, bytes[0..bulk]);
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

        pub fn final(self: @This()) u32 {
            return ~self.state;
        }

        pub fn hash(bytes: []const u8) u32 {
            var crc = init();
            crc.update(bytes);
            return crc.final();
        }
    };
}

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
