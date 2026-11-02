//! Compile-time-selected x86_64 PCLMUL folding for IEEE CRC32/ISO-HDLC.
//! The persisted polynomial, reflection and final XOR are unchanged; this
//! module only replaces the block loop. It is imported only when the compile
//! target advertises PCLMUL and SSE2, so generic targets never analyze the
//! inline assembly. Inputs must be at least 64 bytes and a multiple of 16.
//! Based on the published Gopal/Ozturk/Intel folding construction; the
//! constants below are the reflected-domain CRC-32 values.
const std = @import("std");

const V2 = @Vector(2, u64);
const k1k2: V2 = .{ 0x0154442bd4, 0x01c6e41596 };
const k3k4: V2 = .{ 0x01751997d0, 0x00ccaa009e };
// Reflected-domain coefficients for shifting the earlier lanes by 256/384
// bits. For distance d each pair is reverse32(x^(d +/- 32) mod P) << 1,
// with the normal IEEE generator P = 0x104c11db7. Tests derive them separately.
const k256: V2 = .{ 0x00f1da05aa, 0x015a546366 };
const k384: V2 = .{ 0x003db1ecdc, 0x0174359406 };
const k5k0: V2 = .{ 0x0163cd6124, 0x0000000000 };
const poly: V2 = .{ 0x01db710641, 0x01f7011641 };
const mask: V2 = .{ 0xffffffff, 0xffffffff };

inline fn load16(p: [*]const u8) V2 {
    return @as(*align(1) const V2, @ptrCast(p)).*;
}

inline fn clmul(a: V2, b: V2, comptime imm: u8) V2 {
    var x = a;
    switch (imm) {
        0x00 => asm volatile ("pclmulqdq $0, %[b], %[a]"
            : [a] "+x" (x),
            : [b] "x" (b),
        ),
        0x10 => asm volatile ("pclmulqdq $16, %[b], %[a]"
            : [a] "+x" (x),
            : [b] "x" (b),
        ),
        0x11 => asm volatile ("pclmulqdq $17, %[b], %[a]"
            : [a] "+x" (x),
            : [b] "x" (b),
        ),
        else => @compileError("unsupported pclmul immediate"),
    }
    return x;
}

inline fn shiftRight8(v: V2) V2 {
    return std.simd.shiftElementsLeft(v, 1, 0);
}

inline fn shiftRight4(v: V2) V2 {
    const lanes: @Vector(4, u32) = @bitCast(v);
    return @bitCast(std.simd.shiftElementsLeft(lanes, 1, 0));
}

/// Returns the reflected CRC register state after `bytes`. The caller seeds
/// with its current state and finalizes with bitwise NOT, exactly as the
/// portable table path does.
pub fn update(state: u32, bytes: []const u8) u32 {
    std.debug.assert(bytes.len >= 64 and bytes.len % 16 == 0);
    var p = bytes.ptr;
    var len = bytes.len;
    var x1 = load16(p);
    x1 ^= V2{ @as(u64, state), 0 };
    var x2 = load16(p + 16);
    var x3 = load16(p + 32);
    var x4 = load16(p + 48);
    p += 64;
    len -= 64;
    while (len >= 64) {
        const x5 = clmul(x1, k1k2, 0x00);
        const x6 = clmul(x2, k1k2, 0x00);
        const x7 = clmul(x3, k1k2, 0x00);
        const x8 = clmul(x4, k1k2, 0x00);
        const y5 = load16(p);
        const y6 = load16(p + 16);
        const y7 = load16(p + 32);
        const y8 = load16(p + 48);
        x1 = clmul(x1, k1k2, 0x11) ^ x5 ^ y5;
        x2 = clmul(x2, k1k2, 0x11) ^ x6 ^ y6;
        x3 = clmul(x3, k1k2, 0x11) ^ x7 ^ y7;
        x4 = clmul(x4, k1k2, 0x11) ^ x8 ^ y8;
        p += 64;
        len -= 64;
    }
    // Fold all earlier lanes directly to x4's position. This uses the same
    // six multiplies as three serial folds, with independent dependency chains.
    // The intermediate vector is CRC-equivalent; its bytes need not be equal.
    const a = clmul(x1, k384, 0x00) ^ clmul(x1, k384, 0x11);
    const b = clmul(x2, k256, 0x00) ^ clmul(x2, k256, 0x11);
    const c = clmul(x3, k3k4, 0x00) ^ clmul(x3, k3k4, 0x11);
    x1 = a ^ b ^ c ^ x4;
    var x5: V2 = undefined;
    while (len >= 16) {
        x2 = load16(p);
        x5 = clmul(x1, k3k4, 0x00);
        x1 = clmul(x1, k3k4, 0x11) ^ x2 ^ x5;
        p += 16;
        len -= 16;
    }
    const t = clmul(x1, k3k4, 0x10);
    x1 = shiftRight8(x1) ^ t;
    const low = shiftRight4(x1);
    x1 &= mask;
    x1 = clmul(x1, k5k0, 0x00) ^ low;
    const b1 = clmul(x1 & mask, poly, 0x10);
    const b2 = clmul(b1 & mask, poly, 0x00);
    x1 ^= b2;
    return @truncate(x1[0] >> 32);
}

fn coefficient(exponent: usize) u64 {
    var remainder: u64 = 1;
    for (0..exponent) |_| {
        remainder <<= 1;
        if (remainder & (@as(u64, 1) << 32) != 0) remainder ^= 0x104c11db7;
    }
    return @as(u64, @bitReverse(@as(u32, @intCast(remainder)))) << 1;
}

test "parallel CRC collapse coefficients derive from the independent IEEE generator" {
    inline for (.{ .{ 128, k3k4 }, .{ 256, k256 }, .{ 384, k384 }, .{ 512, k1k2 } }) |entry| {
        try std.testing.expectEqual(entry[1][0], coefficient(entry[0] + 32));
        try std.testing.expectEqual(entry[1][1], coefficient(entry[0] - 32));
    }
}

test "parallel CRC collapse agrees with independent raw IEEE CRC on every input basis bit" {
    var bytes: [64]u8 = undefined;
    for (0..512) |bit| {
        @memset(&bytes, 0);
        bytes[bit / 8] = @as(u8, 1) << @intCast(bit % 8);
        var oracle: std.hash.Crc32 = .{ .crc = 0 };
        oracle.update(&bytes);
        try std.testing.expectEqual(~oracle.final(), update(0, &bytes));
    }
}
