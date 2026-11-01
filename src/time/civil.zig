//! Proleptic Gregorian calendar, years 1..9999. Invalid dates are rejected;
//! normalization and end-of-month clamping are always explicit.
const std = @import("std");
pub const Error = error{ InvalidDate, InvalidTime, OutOfRange };
pub const Weekday = enum(u3) { monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday };

pub fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

pub fn daysInMonth(year: u16, month: u8) Error!u8 {
    if (year == 0 or year > 9999 or month == 0 or month > 12) return error.InvalidDate;
    return switch (month) {
        2 => if (isLeapYear(year)) 29 else 28,
        4, 6, 9, 11 => 30,
        else => 31,
    };
}

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn init(year: u16, month: u8, day: u8) Error!Date {
        const self: Date = .{ .year = year, .month = month, .day = day };
        try self.validate();
        return self;
    }

    pub fn validate(self: Date) Error!void {
        const maximum = try daysInMonth(self.year, self.month);
        if (self.day == 0 or self.day > maximum) return error.InvalidDate;
    }

    /// Days since 1970-01-01. March-based eras keep leap-day arithmetic uniform.
    pub fn epochDays(self: Date) Error!i64 {
        try self.validate();
        const year: i64 = @as(i64, self.year) - @as(i64, @intFromBool(self.month <= 2));
        const era = @divFloor(year, 400);
        const yoe = year - era * 400;
        const month: i64 = @as(i64, self.month) + @as(i64, if (self.month > 2) -3 else 9);
        const doy = @divTrunc(153 * month + 2, 5) + self.day - 1;
        return era * 146097 + yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy - 719468;
    }

    pub fn fromEpochDays(days: i64) Error!Date {
        if (days < -719162 or days > 2932896) return error.OutOfRange;
        const shifted = days + 719468;
        const era = @divFloor(shifted, 146097);
        const doe = shifted - era * 146097;
        const yoe = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
        const doy = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
        const mp = @divTrunc(5 * doy + 2, 153);
        const month = mp + @as(i64, if (mp < 10) 3 else -9);
        return .{
            .year = @intCast(yoe + era * 400 + @as(i64, @intFromBool(month <= 2))),
            .month = @intCast(month),
            .day = @intCast(doy - @divTrunc(153 * mp + 2, 5) + 1),
        };
    }

    pub fn weekday(self: Date) Error!Weekday {
        return @enumFromInt(@as(u3, @intCast(@mod(try self.epochDays() + 3, 7) + 1)));
    }

    pub fn dayOfYear(self: Date) Error!u16 {
        return @intCast(try self.epochDays() - try (Date{ .year = self.year, .month = 1, .day = 1 }).epochDays() + 1);
    }

    pub fn addDays(self: Date, days: i64) Error!Date {
        const target = std.math.add(i64, try self.epochDays(), days) catch return error.OutOfRange;
        return fromEpochDays(target);
    }

    pub const MonthOverflow = enum { reject, clamp };
    pub fn addMonths(self: Date, months: i32, overflow: MonthOverflow) Error!Date {
        try self.validate();
        const index = @as(i64, self.year - 1) * 12 + self.month - 1 + months;
        if (index < 0 or index >= 9999 * 12) return error.OutOfRange;
        const year: u16 = @intCast(@divTrunc(index, 12) + 1);
        const month: u8 = @intCast(@mod(index, 12) + 1);
        const maximum = try daysInMonth(year, month);
        if (self.day > maximum and overflow == .reject) return error.InvalidDate;
        return .{ .year = year, .month = month, .day = @min(self.day, maximum) };
    }
};

pub const DateTime = struct {
    date: Date,
    hour: u8 = 0,
    minute: u8 = 0,
    second: u8 = 0,
    nanosecond: u32 = 0,

    pub fn validate(self: DateTime) Error!void {
        try self.date.validate();
        if (self.hour > 23 or self.minute > 59 or self.second > 59 or self.nanosecond >= 1_000_000_000) return error.InvalidTime;
    }
};

test "calendar covers the complete Gregorian 400 year cycle and civil bounds" {
    const start = try (Date{ .year = 1800, .month = 1, .day = 1 }).epochDays();
    for (0..146097) |index| {
        const day = start + @as(i64, @intCast(index));
        const date = try Date.fromEpochDays(day);
        try date.validate();
        try std.testing.expectEqual(day, try date.epochDays());
        const ordinal = try date.dayOfYear();
        try std.testing.expect(ordinal >= 1 and ordinal <= if (isLeapYear(date.year)) @as(u16, 366) else 365);
    }
    try std.testing.expectEqualDeep(try Date.init(1, 1, 1), try Date.fromEpochDays(-719162));
    try std.testing.expectEqualDeep(try Date.init(9999, 12, 31), try Date.fromEpochDays(2932896));
    try std.testing.expectEqual(Weekday.thursday, try (try Date.init(1970, 1, 1)).weekday());
    try std.testing.expectError(error.InvalidDate, Date.init(1900, 2, 29));
    _ = try Date.init(2000, 2, 29);
    try std.testing.expectError(error.InvalidDate, Date.init(0, 1, 1));
    try std.testing.expectError(error.InvalidDate, Date.init(2024, 13, 1));
}

test "calendar arithmetic rejects overflow and requires explicit month clamping" {
    const date = try Date.init(2024, 1, 31);
    try std.testing.expectError(error.InvalidDate, date.addMonths(1, .reject));
    try std.testing.expectEqualDeep(try Date.init(2024, 2, 29), try date.addMonths(1, .clamp));
    try std.testing.expectEqualDeep(try Date.init(2023, 12, 31), try date.addMonths(-1, .reject));
    try std.testing.expectError(error.OutOfRange, date.addDays(std.math.maxInt(i64)));
    try std.testing.expectError(error.OutOfRange, (try Date.init(1, 1, 1)).addDays(-1));
    try std.testing.expectError(error.InvalidTime, (DateTime{ .date = date, .second = 60 }).validate());
}
