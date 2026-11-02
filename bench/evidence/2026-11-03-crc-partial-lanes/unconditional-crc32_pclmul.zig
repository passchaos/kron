//! Compile-time-selected x86_64 PCLMUL folding for IEEE CRC32/ISO-HDLC.
//! The persisted polynomial, reflection and final XOR are unchanged; this
//! module only replaces the block loop. It is imported only when the compile
//! target advertises PCLMUL and SSE2, so generic targets never analyze the
//! inline assembly. AVX targets use the three-operand 128-bit VEX form;
//! other PCLMUL targets retain legacy SSE. Inputs must be at least 64 bytes
//! and a multiple of 16.
//! Based on the published Gopal/Ozturk/Intel folding construction; the
//! constants below are the reflected-domain CRC-32 values.
const std = @import("std");
const builtin = @import("builtin");

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

// Both forms are pure register arithmetic. Declared inputs/outputs allow
// scheduling without forcing copies for a destructive two-operand result.
inline fn clmul(a: V2, b: V2, comptime imm: u8) V2 {
    if (comptime builtin.cpu.has(.x86, .avx)) {
        return switch (imm) {
            0x00 => asm ("vpclmulqdq $0, %[b], %[a], %[out]"
                : [out] "=x" (-> V2),
                : [a] "x" (a),
                  [b] "x" (b),
            ),
            0x10 => asm ("vpclmulqdq $16, %[b], %[a], %[out]"
                : [out] "=x" (-> V2),
                : [a] "x" (a),
                  [b] "x" (b),
            ),
            0x11 => asm ("vpclmulqdq $17, %[b], %[a], %[out]"
                : [out] "=x" (-> V2),
                : [a] "x" (a),
                  [b] "x" (b),
            ),
            else => @compileError("unsupported pclmul immediate"),
        };
    }
    var x = a;
    switch (imm) {
        0x00 => asm ("pclmulqdq $0, %[b], %[a]"
            : [a] "+x" (x),
            : [b] "x" (b),
        ),
        0x10 => asm ("pclmulqdq $16, %[b], %[a]"
            : [a] "+x" (x),
            : [b] "x" (b),
        ),
        0x11 => asm ("pclmulqdq $17, %[b], %[a]"
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

inline fn continueLane(lane: V2, block: V2) V2 {
    return clmul(lane, k1k2, 0x00) ^ clmul(lane, k1k2, 0x11) ^ block;
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
    // Continue only the lanes with another block, then order their final blocks
    // from earliest to latest. The common collapse still shifts by 384/256/128
    // bits. Each continued lane shifts by 512 bits, as in the full stripe loop;
    // the remaining folds are independent rather than following one collapse.
    switch (len) {
        0 => {},
        16 => {
            const tail = continueLane(x1, load16(p));
            x1 = x2;
            x2 = x3;
            x3 = x4;
            x4 = tail;
        },
        32 => {
            const first = continueLane(x1, load16(p));
            const second = continueLane(x2, load16(p + 16));
            x1 = x3;
            x2 = x4;
            x3 = first;
            x4 = second;
        },
        48 => {
            const first = continueLane(x1, load16(p));
            const second = continueLane(x2, load16(p + 16));
            const third = continueLane(x3, load16(p + 32));
            x1 = x4;
            x2 = first;
            x3 = second;
            x4 = third;
        },
        else => unreachable, // Inputs and the stripe loop preserve 16-byte multiples.
    }
    // Fold all earlier lanes directly to x4's position. This uses the same
    // six multiplies as three serial folds, with independent dependency chains.
    // The intermediate vector is CRC-equivalent; its bytes need not be equal.
    const a = clmul(x1, k384, 0x00) ^ clmul(x1, k384, 0x11);
    const b = clmul(x2, k256, 0x00) ^ clmul(x2, k256, 0x11);
    const c = clmul(x3, k3k4, 0x00) ^ clmul(x3, k3k4, 0x11);
    x1 = a ^ b ^ c ^ x4;
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

// Independent reflected IEEE state machine: no folding coefficients, SIMD,
// slicing table or candidate helper contributes to the expected result.
fn bitwiseState(initial: u32, bytes: []const u8) u32 {
    var state = initial;
    for (bytes) |byte| {
        state ^= byte;
        for (0..8) |_| state = (state >> 1) ^ (if (state & 1 != 0) @as(u32, 0xedb88320) else 0);
    }
    return state;
}

test "partial CRC stripes preserve every message and seed GF2 basis bit including r0 controls" {
    var bytes: [256]u8 = undefined;
    for ([_]usize{ 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240, 256 }) |length| {
        for (0..length * 8) |bit| {
            @memset(&bytes, 0);
            bytes[bit / 8] = @as(u8, 1) << @intCast(bit % 8);
            try std.testing.expectEqual(bitwiseState(0, bytes[0..length]), update(0, bytes[0..length]));
        }
        @memset(&bytes, 0);
        for (0..32) |bit| {
            const state = @as(u32, 1) << @intCast(bit);
            try std.testing.expectEqual(bitwiseState(state, bytes[0..length]), update(state, bytes[0..length]));
        }
    }
}

test "partial CRC stripes preserve arbitrary seeds and unaligned native input" {
    var bytes: [1024 + 32]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x7061727469616c34);
    random.random().bytes(&bytes);
    for (0..32) |alignment| {
        for (4..33) |blocks| {
            const input = bytes[alignment..][0 .. blocks * 16];
            const state = random.random().int(u32);
            try std.testing.expectEqual(bitwiseState(state, input), update(state, input));
        }
        const input = bytes[alignment..][0..1024];
        const state = random.random().int(u32);
        try std.testing.expectEqual(bitwiseState(state, input), update(state, input));
    }
}

test "partial CRC stripes match independently frozen zlib seeded vectors" {
    // Python zlib.crc32(data[:length], state ^ 0xffffffff) ^ 0xffffffff,
    // where data[i] = ((i * 73 + 19) ^ (i >> 3)) & 255. zlib accepts the
    // finalized previous checksum, so both conversions are explicit.
    const lengths = [_]usize{ 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240, 256, 512, 1024 };
    const states = [_]u32{ 0xffffffff, 0, 0x12345678 };
    const expected = [_][lengths.len]u32{
        .{ 0xa7d78803, 0x31185aed, 0xb88f2cc3, 0xf70b82dd, 0x28fb523a, 0x552e9711, 0xcaad7826, 0x1ca1604c, 0xba2131ed, 0xd0d1bd53, 0x8f93ef74, 0x360b93e0, 0xdf119ac8, 0x9824741c, 0xbba1ef5a },
        .{ 0x2da514ca, 0x40c4bdf4, 0xfd84b692, 0x134ad09f, 0x15ac5758, 0xdadb6d72, 0x9f55d4ba, 0xcc0ec1dc, 0xce21c6e0, 0x700ccc15, 0x4d4d4be8, 0x7595480c, 0x2d78e06f, 0xd571fe9b, 0xabebbf8b },
        .{ 0x165e253e, 0xa4a6e061, 0x4c03f08b, 0x5c2c1bcf, 0x699f3205, 0x9d88b837, 0xa37f2ce1, 0x5b4e3202, 0x0b0627d1, 0x325fa360, 0x787f693f, 0x6c65c4c3, 0x80ed3591, 0x3cf6a295, 0x21a10076 },
    };
    var bytes: [1024]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate((index * 73 + 19) ^ (index >> 3));
    for (states, expected) |state, values| for (lengths, values) |length, oracle| {
        try std.testing.expectEqual(oracle, bitwiseState(state, bytes[0..length]));
        try std.testing.expectEqual(oracle, update(state, bytes[0..length]));
    };
}
