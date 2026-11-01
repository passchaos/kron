const std = @import("std");
const kron = @import("kron");

/// Both choices implement the same std.Io wall-clock semantics. The selector
/// reaches a noinline factory at runtime, keeping the callback target opaque
/// instead of measuring a compiler-folded constant callback.
pub noinline fn dynamicClock(selector: bool) kron.Clock {
    return if (selector) .{} else .{ .real_now = equivalentReal };
}

fn equivalentReal(_: ?*anyopaque, io: std.Io) i64 {
    return @intCast(std.math.clamp(std.Io.Clock.real.now(io).nanoseconds, std.math.minInt(i64), std.math.maxInt(i64)));
}

test "runtime-selected dynamic choices preserve identical clock semantics" {
    const Fake = struct {
        fn now(_: ?*anyopaque, clock: std.Io.Clock) std.Io.Timestamp {
            return .{ .nanoseconds = if (clock == .real) -123 else 456 };
        }
    };
    var vtable = std.testing.io.vtable.*;
    vtable.now = Fake.now;
    const io: std.Io = .{ .userdata = null, .vtable = &vtable };
    for ([_]bool{ false, true }) |selector| {
        const clock = dynamicClock(selector);
        try std.testing.expectEqual(@as(i64, -123), clock.realNow(io));
        try std.testing.expectEqual(@as(u64, 456), clock.monotonicNow(io));
    }
}
