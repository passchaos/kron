const std = @import("std");

pub const TokenBucketConfig = struct {
    capacity: u32,
    /// Continuous refill rate of one token per interval; unused tokens are
    /// bounded by capacity. The caller supplies monotonic nanoseconds.
    refill_interval_ns: u64,
    start_ns: u64 = 0,
};

pub const Config = union(enum) {
    none,
    /// Accept the first N calls, then reject subsequent calls.
    count: u64,
    /// Accept call 1, N+1, 2N+1, ...; N must be nonzero.
    every: u64,
    token_bucket: TokenBucketConfig,
};

pub const InitError = error{
    InvalidSampleRate,
    InvalidBucketCapacity,
    SampleWindowOverflow,
};

/// Bounded, thread-safe deterministic sampling. All mutable state fits in one
/// atomic word; calls allocate nothing and never read a hidden process clock.
pub const Sampler = struct {
    config: Config,
    state: std.atomic.Value(u64),
    burst_ns: u64 = 0,

    pub fn init(config: Config) InitError!Sampler {
        return switch (config) {
            .none => .{ .config = config, .state = .init(0) },
            .count => |count| .{ .config = config, .state = .init(count) },
            .every => |every| if (every == 0)
                error.InvalidSampleRate
            else
                .{ .config = config, .state = .init(0) },
            .token_bucket => |bucket| blk: {
                if (bucket.capacity == 0) return error.InvalidBucketCapacity;
                if (bucket.refill_interval_ns == 0) return error.InvalidSampleRate;
                const burst_ns = std.math.mul(u64, bucket.capacity - 1, bucket.refill_interval_ns) catch
                    return error.SampleWindowOverflow;
                const full_window = std.math.add(u64, burst_ns, bucket.refill_interval_ns) catch
                    return error.SampleWindowOverflow;
                _ = std.math.add(u64, bucket.start_ns, full_window) catch
                    return error.SampleWindowOverflow;
                break :blk .{
                    .config = config,
                    .state = .init(bucket.start_ns),
                    .burst_ns = burst_ns,
                };
            },
        };
    }

    pub fn allow(self: *Sampler, now_ns: u64) bool {
        return switch (self.config) {
            .none => true,
            .count => self.allowCount(),
            .every => |every| self.allowEvery(every),
            .token_bucket => |bucket| self.allowBucket(bucket, now_ns),
        };
    }

    fn allowCount(self: *Sampler) bool {
        var remaining = self.state.load(.monotonic);
        while (remaining != 0) {
            if (self.state.cmpxchgWeak(remaining, remaining - 1, .monotonic, .monotonic)) |actual| {
                remaining = actual;
            } else return true;
        }
        return false;
    }

    fn allowEvery(self: *Sampler, every: u64) bool {
        // Preserve the existing bounded phase. These common rates need no
        // general compare/exchange retry loop and retain one global order.
        if (every == 1) return true;
        if (every == 2) return self.state.fetchXor(1, .monotonic) & 1 == 0;
        var position = self.state.load(.monotonic);
        while (true) {
            const next = if (position == every - 1) 0 else position + 1;
            if (self.state.cmpxchgWeak(position, next, .monotonic, .monotonic)) |actual| {
                position = actual;
            } else return position == 0;
        }
    }

    fn allowBucket(self: *Sampler, bucket: TokenBucketConfig, now_ns: u64) bool {
        if (now_ns < bucket.start_ns) return false;
        // Virtual finish time encodes the consumed tokens. This is equivalent
        // to a continuously refilling token bucket with a fixed burst budget.
        // CAS prevents concurrent calls from spending the same token.
        var finish = self.state.load(.monotonic);
        while (true) {
            if (now_ns < finish -| self.burst_ns) return false;
            const next = std.math.add(u64, @max(now_ns, finish), bucket.refill_interval_ns) catch
                return false;
            if (self.state.cmpxchgWeak(finish, next, .monotonic, .monotonic)) |actual| {
                finish = actual;
            } else return true;
        }
    }
};

test "count accepts exactly its configured budget" {
    var sampler = try Sampler.init(.{ .count = 3 });
    for (0..3) |_| try std.testing.expect(sampler.allow(0));
    for (0..10) |_| try std.testing.expect(!sampler.allow(0));
    var none = try Sampler.init(.none);
    try std.testing.expect(none.allow(0));
    var zero = try Sampler.init(.{ .count = 0 });
    try std.testing.expect(!zero.allow(0));
}

test "every N is deterministic and never wraps a call counter" {
    var sampler = try Sampler.init(.{ .every = 3 });
    for (0..20) |i| try std.testing.expectEqual(i % 3 == 0, sampler.allow(0));
    var each = try Sampler.init(.{ .every = 1 });
    for (0..5) |_| try std.testing.expect(each.allow(0));
    try std.testing.expectEqual(@as(u64, 0), each.state.load(.monotonic));
    var half = try Sampler.init(.{ .every = 2 });
    for (0..257) |index| {
        try std.testing.expectEqual(index % 2 == 0, half.allow(0));
        try std.testing.expectEqual(@as(u64, @intCast((index + 1) % 2)), half.state.load(.monotonic));
    }
    try std.testing.expectError(error.InvalidSampleRate, Sampler.init(.{ .every = 0 }));
}

test "token bucket burst and continuous refill use a fake clock" {
    var sampler = try Sampler.init(.{ .token_bucket = .{
        .capacity = 3,
        .refill_interval_ns = 10,
        .start_ns = 100,
    } });
    try std.testing.expect(!sampler.allow(99));
    for (0..3) |_| try std.testing.expect(sampler.allow(100));
    try std.testing.expect(!sampler.allow(100));
    try std.testing.expect(!sampler.allow(109));
    try std.testing.expect(sampler.allow(110));
    try std.testing.expect(!sampler.allow(110));
    // Idle time replenishes at most the configured burst capacity.
    for (0..3) |_| try std.testing.expect(sampler.allow(1000));
    try std.testing.expect(!sampler.allow(1000));
    try std.testing.expect(!sampler.allow(999));
    try std.testing.expect(sampler.allow(1010));
    try std.testing.expectError(error.InvalidBucketCapacity, Sampler.init(.{ .token_bucket = .{
        .capacity = 0,
        .refill_interval_ns = 1,
    } }));
    try std.testing.expectError(error.SampleWindowOverflow, Sampler.init(.{ .token_bucket = .{
        .capacity = 3,
        .refill_interval_ns = std.math.maxInt(u64),
    } }));
}

test "concurrent count, every, and bucket sampling preserve exact budgets" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        sampler: *Sampler,
        accepted: std.atomic.Value(u64) = .init(0),

        fn run(context: *@This()) void {
            for (0..1000) |_| {
                if (context.sampler.allow(0)) _ = context.accepted.fetchAdd(1, .monotonic);
            }
        }
    };
    const cases = [_]struct { config: Config, expected: u64 }{
        .{ .config = .{ .count = 1234 }, .expected = 1234 },
        .{ .config = .{ .every = 1 }, .expected = 4000 },
        .{ .config = .{ .every = 2 }, .expected = 2000 },
        .{ .config = .{ .every = 3 }, .expected = 1334 },
        .{ .config = .{ .every = 8 }, .expected = 500 },
        .{ .config = .{ .token_bucket = .{ .capacity = 1234, .refill_interval_ns = 10 } }, .expected = 1234 },
    };
    for (cases) |case| {
        var sampler = try Sampler.init(case.config);
        var context: Context = .{ .sampler = &sampler };
        var threads: [4]std.Thread = undefined;
        var started: usize = 0;
        defer for (threads[0..started]) |thread| thread.join();
        for (&threads) |*thread| {
            thread.* = try std.Thread.spawn(.{}, Context.run, .{&context});
            started += 1;
        }
        for (threads[0..started]) |thread| thread.join();
        started = 0;
        try std.testing.expectEqual(case.expected, context.accepted.load(.monotonic));
        if (case.config == .every) {
            try std.testing.expectEqual(@as(u64, 4000) % case.config.every, sampler.state.load(.monotonic));
            const expected = @as(u64, 4000) % case.config.every == 0;
            try std.testing.expectEqual(expected, sampler.allow(0));
            try std.testing.expectEqual(@as(u64, 4001) % case.config.every, sampler.state.load(.monotonic));
        }
    }
}
