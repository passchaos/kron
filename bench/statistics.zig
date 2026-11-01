const std = @import("std");

pub const Distribution = struct {
    count: usize = 0,
    p50_ns: ?u64 = null,
    p99_ns: ?u64 = null,
    p999_ns: ?u64 = null,
    mean_ns: ?f64 = null,
    max_ns: ?u64 = null,

    /// Nearest-rank quantiles of observed nanoseconds. No clock baseline is
    /// subtracted: subtraction of separately observed quantiles is unsound.
    pub fn calculate(samples: []u64) Distribution {
        if (samples.len == 0) return .{};
        std.mem.sort(u64, samples, {}, std.sort.asc(u64));
        var total: u128 = 0;
        for (samples) |sample| total += sample;
        return .{
            .count = samples.len,
            .p50_ns = samples[rank(samples.len, 500)],
            .p99_ns = samples[rank(samples.len, 990)],
            .p999_ns = samples[rank(samples.len, 999)],
            .mean_ns = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(samples.len)),
            .max_ns = samples[samples.len - 1],
        };
    }

    fn rank(count: usize, thousandths: usize) usize {
        return (count * thousandths + 999) / 1000 - 1;
    }
};

pub fn elapsed(start: std.Io.Timestamp, end: std.Io.Timestamp) u64 {
    return @intCast(@min(std.math.maxInt(u64), @max(0, start.durationTo(end).toNanoseconds())));
}

pub fn perSecond(count: u64, nanoseconds: u64) f64 {
    if (nanoseconds == 0) return 0;
    return @as(f64, @floatFromInt(count)) * 1_000_000_000 / @as(f64, @floatFromInt(nanoseconds));
}

test "nearest rank distributions do not invent or subtract samples" {
    var samples = [_]u64{ 50, 10, 30, 20, 40 };
    const distribution = Distribution.calculate(&samples);
    try std.testing.expectEqual(@as(?u64, 30), distribution.p50_ns);
    try std.testing.expectEqual(@as(?u64, 50), distribution.p99_ns);
    try std.testing.expectEqual(@as(?u64, 50), distribution.p999_ns);
    try std.testing.expectEqual(@as(?f64, 30), distribution.mean_ns);
    var none: [0]u64 = .{};
    try std.testing.expect(Distribution.calculate(&none).p50_ns == null);
    var single = [_]u64{17};
    try std.testing.expectEqual(@as(?u64, 17), Distribution.calculate(&single).p999_ns);
}

test "latency percentile ranks and throughput preserve measured units" {
    var samples: [1000]u64 = undefined;
    for (&samples, 1..) |*sample, value| sample.* = value;
    const distribution = Distribution.calculate(&samples);
    try std.testing.expectEqual(@as(?u64, 500), distribution.p50_ns);
    try std.testing.expectEqual(@as(?u64, 990), distribution.p99_ns);
    try std.testing.expectEqual(@as(?u64, 999), distribution.p999_ns);
    try std.testing.expectEqual(@as(f64, 50), perSecond(100, 2_000_000_000));
}
