//! Statically selected producer clocks. StandardClock skips the optional
//! callback layer but retains the application's std.Io provider. NativeClock
//! uses Linux's vDSO-aware clock_gettime directly; it is an explicit choice.
const std = @import("std");
const builtin = @import("builtin");

pub const StandardClock = struct {
    pub inline fn realNow(io: std.Io) i64 {
        const value = std.Io.Clock.real.now(io).nanoseconds;
        return @intCast(std.math.clamp(value, std.math.minInt(i64), std.math.maxInt(i64)));
    }

    pub inline fn monotonicNow(io: std.Io) u64 {
        const value = std.Io.Clock.awake.now(io).nanoseconds;
        return @intCast(std.math.clamp(value, 0, std.math.maxInt(u64)));
    }
};

pub const NativeClock = struct {
    pub const supported = builtin.os.tag == .linux;

    pub inline fn realNow(io: std.Io) i64 {
        if (comptime !supported) return StandardClock.realNow(io);
        var timestamp: std.os.linux.timespec = undefined;
        if (std.os.linux.errno(std.os.linux.clock_gettime(.REALTIME, &timestamp)) != .SUCCESS) return StandardClock.realNow(io);
        const value = @as(i128, timestamp.sec) * std.time.ns_per_s + timestamp.nsec;
        return @intCast(std.math.clamp(value, std.math.minInt(i64), std.math.maxInt(i64)));
    }

    pub inline fn monotonicNow(io: std.Io) u64 {
        if (comptime !supported) return StandardClock.monotonicNow(io);
        var timestamp: std.os.linux.timespec = undefined;
        if (std.os.linux.errno(std.os.linux.clock_gettime(.MONOTONIC, &timestamp)) != .SUCCESS) return StandardClock.monotonicNow(io);
        const value = @as(i128, timestamp.sec) * std.time.ns_per_s + timestamp.nsec;
        return @intCast(std.math.clamp(value, 0, std.math.maxInt(u64)));
    }
};

pub const ZeroClock = struct {
    pub inline fn realNow(_: std.Io) i64 {
        return 0;
    }

    pub inline fn monotonicNow(io: std.Io) u64 {
        return StandardClock.monotonicNow(io);
    }
};

test "static clocks keep explicit injection and native capability separate" {
    const Fake = struct {
        calls: usize = 0,
        fn now(context: ?*anyopaque, clock: std.Io.Clock) std.Io.Timestamp {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            return .{ .nanoseconds = if (clock == .real) 123 else 456 };
        }
    };
    var fake: Fake = .{};
    var vtable = std.testing.io.vtable.*;
    vtable.now = Fake.now;
    const io: std.Io = .{ .userdata = &fake, .vtable = &vtable };
    try std.testing.expectEqual(@as(i64, 123), StandardClock.realNow(io));
    try std.testing.expectEqual(@as(u64, 456), StandardClock.monotonicNow(io));
    try std.testing.expectEqual(@as(i64, 0), ZeroClock.realNow(io));
    try std.testing.expectEqual(@as(usize, 2), fake.calls);
    if (NativeClock.supported) {
        const before = StandardClock.realNow(std.testing.io);
        const native = NativeClock.realNow(io);
        const after = StandardClock.realNow(std.testing.io);
        try std.testing.expect(native >= before and native <= after);
        try std.testing.expectEqual(@as(usize, 2), fake.calls);
    }
}
