//! Exact unsigned capacity arithmetic using a divisor's cold reciprocal.
const std = @import("std");

pub const Division = struct {
    quotient: u64,
    remainder: u64,
};

/// A descriptor initialized once for a nonzero divisor. Every divide/quotient
/// call must supply that same divisor; changing it requires a new descriptor.
pub const Divider = struct {
    multiplier: u64,

    pub fn init(divisor: u64) error{InvalidDivisor}!Divider {
        if (divisor == 0) return error.InvalidDivisor;
        const reciprocal = (@as(u128, 1) << 64) / divisor;
        return .{ .multiplier = @intCast(@min(reciprocal, std.math.maxInt(u64))) };
    }

    /// Precondition: divisor is nonzero and matches init's divisor.
    pub inline fn quotient(self: Divider, numerator: u64, divisor: u64) u64 {
        return self.divide(numerator, divisor).quotient;
    }

    /// Precondition: divisor is nonzero and matches init's divisor.
    /// The reciprocal's estimate is exact or one below the true quotient,
    /// including the capped reciprocal for divisor one. Its product with the
    /// divisor is therefore at most numerator, so all corrections fit u64.
    pub inline fn divide(self: Divider, numerator: u64, divisor: u64) Division {
        const estimate: u64 = @intCast((@as(u128, numerator) * self.multiplier) >> 64);
        const initial_remainder = numerator - estimate * divisor;
        const correction: u64 = @intFromBool(initial_remainder >= divisor);
        return .{
            .quotient = estimate + correction,
            .remainder = initial_remainder - (divisor & (@as(u64, 0) -% correction)),
        };
    }
};

fn expectDivision(divider: Divider, numerator: u64, divisor: u64) !void {
    const result = divider.divide(numerator, divisor);
    // The independent oracle is native unsigned division, never another
    // reciprocal calculation or a comparison between the two entry points.
    try std.testing.expectEqual(numerator / divisor, result.quotient);
    try std.testing.expectEqual(numerator % divisor, result.remainder);
    try std.testing.expectEqual(numerator / divisor, divider.quotient(numerator, divisor));
}

fn expectReciprocalBound(divider: Divider, divisor: u64) !void {
    const scale = @as(u128, 1) << 64;
    const product = @as(u128, divider.multiplier) * divisor;
    try std.testing.expect(product <= scale);
    const residual = scale - product;
    if (divisor == 1) {
        // Only divisor one caps the mathematical reciprocal at UINT64_MAX.
        try std.testing.expectEqual(std.math.maxInt(u64), divider.multiplier);
        try std.testing.expectEqual(@as(u128, 1), residual);
    } else {
        // This interval uniquely characterizes floor(2^64 / divisor), without
        // calculating that quotient in the test.
        try std.testing.expect(residual < divisor);
    }
}

fn expectDivisorBoundaries(divisor: u64) !void {
    const divider = try Divider.init(divisor);
    try expectReciprocalBound(divider, divisor);
    for ([_]u64{ 0, 1, 2, 3, 7, std.math.maxInt(u32) - 1, std.math.maxInt(u32), @as(u64, std.math.maxInt(u32)) + 1, @as(u64, std.math.maxInt(u32)) + 2, std.math.maxInt(u64) - 1, std.math.maxInt(u64) }) |numerator| {
        try expectDivision(divider, numerator, divisor);
    }

    const largest_quotient = std.math.maxInt(u64) / divisor;
    for ([_]u64{ 0, 1, 2, 3, largest_quotient / 2, largest_quotient - 1, largest_quotient }) |quotient| {
        // Wide arithmetic is confined to test boundary construction. Every
        // representable q*d boundary is checked immediately below and above.
        const product = @as(u128, quotient) * divisor;
        if (product > std.math.maxInt(u64)) continue;
        const boundary: u64 = @intCast(product);
        if (boundary != 0) try expectDivision(divider, boundary - 1, divisor);
        try expectDivision(divider, boundary, divisor);
        if (boundary != std.math.maxInt(u64)) try expectDivision(divider, boundary + 1, divisor);
    }
}

test "capacity divider rejects zero and corrects divisor one across the full numerator range" {
    try std.testing.expectError(error.InvalidDivisor, Divider.init(0));
    const divider = try Divider.init(1);
    try expectReciprocalBound(divider, 1);
    for ([_]u64{ 0, 1, 2, std.math.maxInt(u32), @as(u64, std.math.maxInt(u32)) + 1, @as(u64, 1) << 63, std.math.maxInt(u64) }) |numerator| {
        const result = divider.divide(numerator, 1);
        try std.testing.expectEqual(numerator, result.quotient);
        try std.testing.expectEqual(@as(u64, 0), result.remainder);
        try expectDivision(divider, numerator, 1);
    }
}

test "capacity divider exact boundaries include every power of two and adjacent divisors" {
    for ([_]u64{ 1, 2, 3, 7, std.math.maxInt(u32) - 1, std.math.maxInt(u32), @as(u64, std.math.maxInt(u32)) + 1, @as(u64, std.math.maxInt(u32)) + 2, std.math.maxInt(u64) - 1, std.math.maxInt(u64) }) |divisor| {
        try expectDivisorBoundaries(divisor);
    }
    for (0..64) |exponent| {
        const power = @as(u64, 1) << @as(u6, @intCast(exponent));
        if (power > 1) try expectDivisorBoundaries(power - 1);
        try expectDivisorBoundaries(power);
        try expectDivisorBoundaries(power + 1);
    }
}

test "capacity divider matches native quotient remainder and reciprocal bounds for 200000 seeded pairs" {
    var prng = std.Random.DefaultPrng.init(0x6361706163697479);
    const random = prng.random();
    for (0..200_000) |iteration| {
        const numerator = random.int(u64);
        const raw_divisor = random.int(u64);
        // Half sample the entire u64 divisor domain. Half span smaller ranges
        // so random quotients also exercise all magnitudes instead of mostly
        // zero/one. Zero samples map to the valid divisor one.
        const sampled_divisor = if (iteration % 2 == 0) raw_divisor else raw_divisor >> @as(u6, @intCast((iteration / 2) % 64));
        const divisor = if (sampled_divisor == 0) 1 else sampled_divisor;
        const divider = try Divider.init(divisor);
        try expectDivision(divider, numerator, divisor);
        try expectReciprocalBound(divider, divisor);
    }
}
