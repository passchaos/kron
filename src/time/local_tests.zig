const std = @import("std");
const local = @import("local.zig");
const rfc3339 = @import("rfc3339.zig");

test "system local time cache refreshes once per event second and rejects partial output" {
    if (!local.supported) return error.SkipZigTest;
    var cache = try rfc3339.Formatter.initWithIo(std.testing.io, .{ .zone = .local });
    try std.testing.expect(cache.local_identity != null);
    var bytes: [rfc3339.max_length]u8 = undefined;
    const base: i64 = 1_700_000_000_000_000_000;
    const before = local.TestingAudit.conversions.load(.acquire);
    for (0..4096) |index| {
        const timestamp = @import("types.zig").Timestamp{ .nanoseconds = base + @as(i64, @intCast(index)) };
        const formatted = try cache.format(timestamp, &bytes);
        try std.testing.expectEqual(timestamp, (try rfc3339.parse(formatted)).timestamp);
    }
    try std.testing.expectEqual(@as(usize, 1), local.TestingAudit.conversions.load(.acquire) - before);
    try std.testing.expectEqual(@as(usize, 1), cache.calendar_conversions);
    _ = try cache.format(.{ .nanoseconds = base + std.time.ns_per_s }, &bytes);
    _ = try cache.format(.{ .nanoseconds = base }, &bytes);
    try std.testing.expectEqual(@as(usize, 3), local.TestingAudit.conversions.load(.acquire) - before);
    const conversions = cache.calendar_conversions;
    @memset(&bytes, 0xa5);
    try std.testing.expectError(error.BufferTooSmall, cache.format(.{ .nanoseconds = base }, bytes[0..18]));
    try std.testing.expect(std.mem.allEqual(u8, &bytes, 0xa5));
    try std.testing.expectEqual(conversions, cache.calendar_conversions);
    // Switching between local/fixed options in one second must invalidate the
    // local cache even when the corresponding numeric offsets happen to match.
    cache.options.zone = .fixed;
    _ = try cache.format(.{ .nanoseconds = base }, &bytes);
    cache.options.zone = .local;
    _ = try cache.format(.{ .nanoseconds = base }, &bytes);
    try std.testing.expectEqual(@as(usize, 4), local.TestingAudit.conversions.load(.acquire) - before);
}

test "system local time fingerprints distinguish rule sources and retain fixed compatibility" {
    const fixed = try rfc3339.Formatter.init(.{});
    var same = fixed;
    try std.testing.expect(fixed.eql(&same));
    if (!local.supported) {
        try std.testing.expectError(error.LocalTimeUnavailable, rfc3339.Formatter.init(.{ .zone = .local }));
        return;
    }
    var a = try rfc3339.Formatter.initWithIo(std.testing.io, .{ .zone = .local });
    var b = a;
    try std.testing.expect(a.eql(&b));
    b.local_identity.?[0] ^= 1;
    try std.testing.expect(!a.eql(&b));
    try std.testing.expect(!a.options.eql(fixed.options));
    try std.testing.expectError(error.InvalidOffset, rfc3339.Formatter.init(.{ .zone = .local, .offset = .{ .minutes = 480 } }));
}
