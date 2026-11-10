//! Pure TSC calibration math and counter-sample qualification.
//! This module has no hardware access; it is shared by the TSC clock and its
//! deterministic tests.
const std = @import("std");

pub const max_samples = 31;

pub const CounterSample = struct {
    start_ticks: u64,
    finish_ticks: u64,
    start_ns: u64,
    finish_ns: u64,
};

pub const FrequencyEstimate = struct {
    hz: u64,
    maximum_error_ppm: u32,
};

pub fn estimateFrequency(delta_ticks: u64, delta_ns: u64) ?u64 {
    if (delta_ticks == 0 or delta_ns == 0) return null;
    const value = (@as(u128, delta_ticks) * std.time.ns_per_s) / delta_ns;
    return if (value <= std.math.maxInt(u64)) @intCast(value) else null;
}

pub fn qualifyCounterSamples(
    samples: []const CounterSample,
    exact_reference_hz: ?u64,
    maximum_ppm: u32,
) error{CalibrationUnstable}!FrequencyEstimate {
    if (samples.len < 3 or samples.len > max_samples or samples.len & 1 == 0)
        return error.CalibrationUnstable;
    var estimates: [max_samples]u64 = undefined;
    for (samples, 0..) |sample, index| {
        if (sample.finish_ticks <= sample.start_ticks or sample.finish_ns <= sample.start_ns)
            return error.CalibrationUnstable;
        estimates[index] = estimateFrequency(
            sample.finish_ticks - sample.start_ticks,
            sample.finish_ns - sample.start_ns,
        ) orelse return error.CalibrationUnstable;
    }
    insertionSort(estimates[0..samples.len]);
    const frequency = estimates[samples.len / 2];
    var error_ppm: u32 = 0;
    for (estimates[0..samples.len]) |sample| {
        error_ppm = @max(error_ppm, ppmDifference(sample, frequency));
    }
    if (error_ppm > maximum_ppm) return error.CalibrationUnstable;
    if (exact_reference_hz) |reference| {
        if (ppmDifference(frequency, reference) > maximum_ppm)
            return error.CalibrationUnstable;
    }
    return .{ .hz = frequency, .maximum_error_ppm = error_ppm };
}

pub fn estimateTicks(frequency_hz: u64, duration_ns: u64) ?u64 {
    if (frequency_hz == 0) return null;
    const value = (@as(u128, frequency_hz) * duration_ns) / std.time.ns_per_s;
    return if (value <= std.math.maxInt(u64)) @intCast(value) else null;
}

pub fn multiplierQ32(frequency_hz: u64) ?u64 {
    if (frequency_hz == 0) return null;
    const value = (@as(u128, std.time.ns_per_s) << 32) / frequency_hz;
    return if (value != 0 and value <= std.math.maxInt(u64)) @intCast(value) else null;
}

pub fn ticksToNs(ticks: u64, multiplier_q32: u64) ?u64 {
    const value = (@as(u128, ticks) * multiplier_q32) >> 32;
    return if (value <= std.math.maxInt(u64)) @intCast(value) else null;
}

pub fn ppmDifference(a: u64, b: u64) u32 {
    const denominator = @max(a, b);
    if (denominator == 0) return 0;
    const difference = if (a >= b) a - b else b - a;
    const ppm = (@as(u128, difference) * 1_000_000) / denominator;
    return @intCast(@min(ppm, std.math.maxInt(u32)));
}

pub fn driftExceeded(predicted_ns: u64, actual_ns: u64, maximum_ppm: u32) bool {
    return ppmDifference(predicted_ns, actual_ns) > maximum_ppm;
}

pub fn insertionSort(values: []u64) void {
    for (values[1..], 1..) |value, i| {
        var j = i;
        while (j > 0 and values[j - 1] > value) : (j -= 1) values[j] = values[j - 1];
        values[j] = value;
    }
}

pub fn addSignedSaturating(base: i64, delta: u64) i64 {
    if (delta > std.math.maxInt(i64)) return std.math.maxInt(i64);
    return base +| @as(i64, @intCast(delta));
}

pub fn clampMonotonic(last: *std.atomic.Value(u64), candidate: u64) u64 {
    var previous = last.load(.monotonic);
    while (candidate > previous) {
        previous = last.cmpxchgWeak(previous, candidate, .monotonic, .monotonic) orelse return candidate;
    }
    return previous;
}

test "qualification math uses median and fixed point without overflow" {
    var samples = [_]u64{ 3_001_000_000, 2_999_000_000, 3_000_000_000, 9_000_000_000, 2_998_000_000 };
    insertionSort(&samples);
    try std.testing.expectEqual(@as(u64, 3_000_000_000), samples[samples.len / 2]);
    const multiplier = multiplierQ32(3_000_000_000).?;
    const ns = ticksToNs(3_000_000, multiplier).?;
    try std.testing.expect(ns >= 999_998 and ns <= 1_000_002);
    try std.testing.expectEqual(@as(u32, 1_000), ppmDifference(999_000, 1_000_000));
    try std.testing.expectEqual(@as(u64, 3_000_000_000), estimateFrequency(3_000_000, 1_000_000).?);
}

test "fake counter and monotonic samples qualify or reject without hardware" {
    const stable = [_]CounterSample{
        .{ .start_ticks = 10, .finish_ticks = 3_000_010, .start_ns = 20, .finish_ns = 1_000_020 },
        .{ .start_ticks = 100, .finish_ticks = 3_000_100, .start_ns = 200, .finish_ns = 1_000_200 },
        .{ .start_ticks = 1_000, .finish_ticks = 3_001_000, .start_ns = 2_000, .finish_ns = 1_002_000 },
    };
    const estimate = try qualifyCounterSamples(&stable, 3_000_000_000, 100);
    try std.testing.expectEqual(@as(u64, 3_000_000_000), estimate.hz);
    try std.testing.expectEqual(@as(u32, 0), estimate.maximum_error_ppm);

    var unstable = stable;
    unstable[2].finish_ticks = 4_001_000;
    try std.testing.expectError(
        error.CalibrationUnstable,
        qualifyCounterSamples(&unstable, null, 100),
    );
    var backwards = stable;
    backwards[0].finish_ns = backwards[0].start_ns;
    try std.testing.expectError(
        error.CalibrationUnstable,
        qualifyCounterSamples(&backwards, null, 100),
    );
}
