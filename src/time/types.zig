//! Absolute wall timestamps, fixed UTC offsets and exact elapsed durations.
//! Wall timestamps never replace the runtime's monotonic deadline clocks.
const std = @import("std");
pub const civil = @import("civil.zig");
pub const Error = civil.Error || error{ InvalidOffset, UnknownOffset, Overflow };
pub const ns_per_second: i64 = 1_000_000_000;

/// A fixed minute offset, not a geographical time zone. It has no DST rules,
/// OS lookups or environment dependencies. RFC3339 permits ±23:59.
pub const UtcOffset = struct {
    minutes: i16 = 0,
    pub const utc: UtcOffset = .{};

    pub fn init(minutes: i16) Error!UtcOffset {
        if (minutes < -1439 or minutes > 1439) return error.InvalidOffset;
        return .{ .minutes = minutes };
    }

    pub fn validate(self: UtcOffset) Error!void {
        _ = try init(self.minutes);
    }

    pub fn parse(input: []const u8) Error!UtcOffset {
        if (std.mem.eql(u8, input, "UTC") or std.mem.eql(u8, input, "Z") or std.mem.eql(u8, input, "z")) return .utc;
        if (input.len != 6 or (input[0] != '+' and input[0] != '-') or input[3] != ':') return error.InvalidOffset;
        for ([_]usize{ 1, 2, 4, 5 }) |index| if (input[index] < '0' or input[index] > '9') return error.InvalidOffset;
        const hour: i16 = @as(i16, input[1] - '0') * 10 + (input[2] - '0');
        const minute: i16 = @as(i16, input[4] - '0') * 10 + (input[5] - '0');
        if (hour > 23 or minute > 59) return error.InvalidOffset;
        const total = hour * 60 + minute;
        if (input[0] == '-' and total == 0) return error.UnknownOffset;
        return init(if (input[0] == '-') -total else total);
    }

    pub fn seconds(self: UtcOffset) Error!i64 {
        try self.validate();
        return @as(i64, self.minutes) * 60;
    }
};

/// Elapsed nanoseconds. Months and days as civil-calendar operations belong to
/// Date and require explicit end-of-month behavior instead of implicit units.
pub const Duration = struct {
    nanoseconds: i128,

    pub fn seconds(value: i64) Duration {
        return .{ .nanoseconds = @as(i128, value) * ns_per_second };
    }

    pub fn add(self: Duration, other: Duration) Error!Duration {
        return .{ .nanoseconds = std.math.add(i128, self.nanoseconds, other.nanoseconds) catch return error.Overflow };
    }

    pub fn negate(self: Duration) Error!Duration {
        return .{ .nanoseconds = std.math.sub(i128, 0, self.nanoseconds) catch return error.Overflow };
    }
};

/// Same exact i64 Unix-nanosecond range as Event.timestamp_ns. POSIX seconds
/// do not represent leap seconds. Conversions reject unrepresentable dates.
pub const Timestamp = struct {
    nanoseconds: i64,

    pub fn fromUnix(seconds: i64, nanoseconds: u32) Error!Timestamp {
        if (nanoseconds >= ns_per_second) return error.InvalidTime;
        const value = @as(i128, seconds) * ns_per_second + nanoseconds;
        return .{ .nanoseconds = std.math.cast(i64, value) orelse return error.OutOfRange };
    }

    pub fn unixSeconds(self: Timestamp) i64 {
        return @divFloor(self.nanoseconds, ns_per_second);
    }

    pub fn fraction(self: Timestamp) u32 {
        return @intCast(@mod(self.nanoseconds, ns_per_second));
    }

    pub fn toCivil(self: Timestamp, offset: UtcOffset) Error!civil.DateTime {
        const local = self.unixSeconds() + try offset.seconds();
        const time_of_day = @mod(local, 86400);
        return .{
            .date = try civil.Date.fromEpochDays(@divFloor(local, 86400)),
            .hour = @intCast(@divTrunc(time_of_day, 3600)),
            .minute = @intCast(@divTrunc(@mod(time_of_day, 3600), 60)),
            .second = @intCast(@mod(time_of_day, 60)),
            .nanosecond = self.fraction(),
        };
    }

    pub fn fromCivil(date_time: civil.DateTime, offset: UtcOffset) Error!Timestamp {
        try date_time.validate();
        const seconds = try date_time.date.epochDays() * 86400 + @as(i64, date_time.hour) * 3600 + @as(i64, date_time.minute) * 60 + date_time.second - try offset.seconds();
        return fromUnix(seconds, date_time.nanosecond);
    }

    pub fn add(self: Timestamp, elapsed: Duration) Error!Timestamp {
        const value = std.math.add(i128, self.nanoseconds, elapsed.nanoseconds) catch return error.Overflow;
        return .{ .nanoseconds = std.math.cast(i64, value) orelse return error.OutOfRange };
    }

    pub fn since(self: Timestamp, earlier: Timestamp) Duration {
        return .{ .nanoseconds = @as(i128, self.nanoseconds) - earlier.nanoseconds };
    }
};

test "timestamp civil conversion uses floor for negative epochs and checks every bound" {
    const offsets = [_]i16{ -1439, -480, 0, 330, 480, 1439 };
    const samples = [_]i64{ std.math.minInt(i64), -1_000_000_001, -1, 0, 1, 1_000_000_001, std.math.maxInt(i64) };
    for (offsets) |minutes| {
        const offset = try UtcOffset.init(minutes);
        for (samples) |nanoseconds| {
            const value: Timestamp = .{ .nanoseconds = nanoseconds };
            try std.testing.expectEqual(value, try Timestamp.fromCivil(try value.toCivil(offset), offset));
        }
    }
    const negative = try (Timestamp{ .nanoseconds = -1 }).toCivil(.utc);
    try std.testing.expectEqualDeep(try civil.Date.init(1969, 12, 31), negative.date);
    try std.testing.expectEqual(@as(u8, 59), negative.second);
    try std.testing.expectEqual(@as(u32, 999999999), negative.nanosecond);
    try std.testing.expectError(error.InvalidOffset, UtcOffset.init(1440));
    try std.testing.expectError(error.OutOfRange, Timestamp.fromUnix(std.math.maxInt(i64), 0));
    try std.testing.expectError(error.InvalidTime, Timestamp.fromUnix(0, 1000000000));
}

test "duration and timestamp arithmetic never silently wraps" {
    const first: Timestamp = .{ .nanoseconds = std.math.minInt(i64) };
    const last: Timestamp = .{ .nanoseconds = std.math.maxInt(i64) };
    try std.testing.expectEqual(last, try first.add(last.since(first)));
    try std.testing.expectError(error.OutOfRange, last.add(.{ .nanoseconds = 1 }));
    try std.testing.expectError(error.Overflow, (Duration{ .nanoseconds = std.math.minInt(i128) }).negate());
    try std.testing.expectError(error.Overflow, (Duration{ .nanoseconds = std.math.maxInt(i128) }).add(.{ .nanoseconds = 1 }));
    try std.testing.expectEqual(@as(i128, -1000000000), Duration.seconds(-1).nanoseconds);
}

test "fixed UTC offset parsing rejects implicit geography malformed input and unknown zero" {
    try std.testing.expectEqual(UtcOffset{ .minutes = 480 }, try UtcOffset.parse("+08:00"));
    try std.testing.expectEqual(UtcOffset{ .minutes = -210 }, try UtcOffset.parse("-03:30"));
    try std.testing.expectEqual(UtcOffset.utc, try UtcOffset.parse("UTC"));
    try std.testing.expectError(error.UnknownOffset, UtcOffset.parse("-00:00"));
    const invalid = [_][]const u8{ "Asia/Shanghai", "Local", "0800", "+24:00", "+08:60", "+a8:00", "+08:00\n" };
    for (invalid) |input| try std.testing.expectError(error.InvalidOffset, UtcOffset.parse(input));
}
