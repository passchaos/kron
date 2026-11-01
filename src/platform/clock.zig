const std = @import("std");

/// Explicit clock injection. Callbacks must support the concurrency of their
/// owner; the default delegates to the caller's std.Io without allocation.
pub const Clock = struct {
    context: ?*anyopaque = null,
    real_now: *const fn (?*anyopaque, std.Io) i64 = realDefault,
    monotonic_now: *const fn (?*anyopaque, std.Io) u64 = monotonicDefault,

    pub fn realNow(self: Clock, io: std.Io) i64 {
        return self.real_now(self.context, io);
    }

    pub fn now(self: Clock, io: std.Io) i64 {
        return self.realNow(io);
    }

    pub fn monotonicNow(self: Clock, io: std.Io) u64 {
        return self.monotonic_now(self.context, io);
    }

    /// Disables wall-clock timestamps while deadlines and sampling continue to
    /// use the real monotonic clock. This does not freeze runtime progression.
    pub fn zeroTimestamp() Clock {
        return .{ .real_now = zeroReal };
    }

    /// The equivalent operation for an injected clock preserves its monotonic
    /// callback and context, which is useful for deterministic tests.
    pub fn withoutTimestamp(self: Clock) Clock {
        var result = self;
        result.real_now = zeroReal;
        return result;
    }
};

fn zeroReal(_: ?*anyopaque, _: std.Io) i64 {
    return 0;
}

fn realDefault(_: ?*anyopaque, io: std.Io) i64 {
    // The public event timestamp has a narrower range than std.Io's i96. Clamp
    // unsupported dates rather than panicking or wrapping into another epoch.
    const value = std.Io.Clock.real.now(io).nanoseconds;
    return @intCast(std.math.clamp(value, std.math.minInt(i64), std.math.maxInt(i64)));
}

fn monotonicDefault(_: ?*anyopaque, io: std.Io) u64 {
    const value = std.Io.Clock.awake.now(io).nanoseconds;
    return @intCast(std.math.clamp(value, 0, std.math.maxInt(u64)));
}

test "injected clocks keep wall time and monotonic progression independent" {
    const Fake = struct {
        wall: i64 = -123,
        monotonic: u64 = 42,
        wall_calls: usize = 0,
        monotonic_calls: usize = 0,

        fn real(context: ?*anyopaque, _: std.Io) i64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.wall_calls += 1;
            return self.wall;
        }

        fn monotonicNow(context: ?*anyopaque, _: std.Io) u64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.monotonic_calls += 1;
            return self.monotonic;
        }
    };
    var fake: Fake = .{};
    const clock: Clock = .{ .context = &fake, .real_now = Fake.real, .monotonic_now = Fake.monotonicNow };
    try std.testing.expectEqual(@as(i64, -123), clock.realNow(std.testing.io));
    try std.testing.expectEqual(@as(u64, 42), clock.monotonicNow(std.testing.io));
    fake.wall = -456;
    fake.monotonic = 100;
    try std.testing.expectEqual(@as(i64, -456), clock.now(std.testing.io));
    try std.testing.expectEqual(@as(u64, 100), clock.monotonicNow(std.testing.io));
    const disabled = clock.withoutTimestamp();
    try std.testing.expectEqual(@as(i64, 0), disabled.realNow(std.testing.io));
    fake.monotonic = 123;
    try std.testing.expectEqual(@as(u64, 123), disabled.monotonicNow(std.testing.io));
    try std.testing.expectEqual(@as(usize, 2), fake.wall_calls);
    try std.testing.expectEqual(@as(usize, 3), fake.monotonic_calls);
}

test "default std.Io clock selection and zero timestamp retain awake clock" {
    const FakeIo = struct {
        wall: i96 = 123,
        awake: i96 = 456,
        wall_calls: usize = 0,
        awake_calls: usize = 0,

        fn now(context: ?*anyopaque, which: std.Io.Clock) std.Io.Timestamp {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            return .{ .nanoseconds = switch (which) {
                .real => blk: {
                    self.wall_calls += 1;
                    break :blk self.wall;
                },
                .awake => blk: {
                    self.awake_calls += 1;
                    break :blk self.awake;
                },
                else => unreachable,
            } };
        }
    };
    var fake: FakeIo = .{};
    var vtable = std.testing.io.vtable.*;
    vtable.now = FakeIo.now;
    const io: std.Io = .{ .userdata = &fake, .vtable = &vtable };
    const clock: Clock = .{};
    try std.testing.expectEqual(@as(i64, 123), clock.realNow(io));
    try std.testing.expectEqual(@as(u64, 456), clock.monotonicNow(io));
    const disabled = Clock.zeroTimestamp();
    try std.testing.expectEqual(@as(i64, 0), disabled.realNow(io));
    fake.awake = 1000;
    try std.testing.expectEqual(@as(u64, 1000), disabled.monotonicNow(io));
    try std.testing.expectEqual(@as(usize, 1), fake.wall_calls);
    try std.testing.expectEqual(@as(usize, 2), fake.awake_calls);
    fake.wall = std.math.maxInt(i96);
    fake.awake = -1;
    try std.testing.expectEqual(std.math.maxInt(i64), clock.realNow(io));
    try std.testing.expectEqual(@as(u64, 0), clock.monotonicNow(io));
    fake.wall = std.math.minInt(i96);
    fake.awake = std.math.maxInt(i96);
    try std.testing.expectEqual(std.math.minInt(i64), clock.realNow(io));
    try std.testing.expectEqual(std.math.maxInt(u64), clock.monotonicNow(io));
}
