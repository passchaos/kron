//! Locale-independent RFC3339 with exact Unix nanoseconds and fixed offsets.
//! No OS time-zone state, calendar normalization, DST or hidden precision loss.
const std = @import("std");
const types = @import("types.zig");
const Timestamp = types.Timestamp;
const UtcOffset = types.UtcOffset;
const civil = types.civil;
pub const Error = types.Error || error{ InvalidSyntax, PrecisionLoss, LeapSecondUnsupported, UnknownOffset, BufferTooSmall };
pub const Precision = enum(u8) { seconds, milliseconds, microseconds, nanoseconds, auto };
pub const Options = struct {
    offset: UtcOffset = .utc,
    precision: Precision = .nanoseconds,

    pub fn validate(self: Options) Error!void {
        try self.offset.validate();
    }

    pub fn eql(self: Options, other: Options) bool {
        return self.offset.minutes == other.offset.minutes and self.precision == other.precision;
    }
};
pub const max_length = 35;
pub const Parsed = struct { timestamp: Timestamp, offset: UtcOffset };

fn number(input: []const u8) Error!u32 {
    var value: u32 = 0;
    for (input) |byte| {
        if (byte < '0' or byte > '9') return error.InvalidSyntax;
        value = value * 10 + (byte - '0');
    }
    return value;
}

/// Accepts T/t and Z/z as RFC3339 permits. Missing offsets, >9 fraction digits,
/// leap seconds and the RFC's unknown-local-offset -00:00 are explicit errors.
pub fn parse(input: []const u8) Error!Parsed {
    if (input.len < 20 or input.len > max_length) return if (input.len > max_length) error.PrecisionLoss else error.InvalidSyntax;
    if (input[4] != '-' or input[7] != '-' or (input[10] != 'T' and input[10] != 't') or input[13] != ':' or input[16] != ':') return error.InvalidSyntax;
    const second = try number(input[17..19]);
    if (second == 60) return error.LeapSecondUnsupported;
    var date_time: civil.DateTime = .{
        .date = .{ .year = @intCast(try number(input[0..4])), .month = @intCast(try number(input[5..7])), .day = @intCast(try number(input[8..10])) },
        .hour = @intCast(try number(input[11..13])),
        .minute = @intCast(try number(input[14..16])),
        .second = @intCast(second),
    };
    try date_time.validate();
    var index: usize = 19;
    if (input[index] == '.') {
        index += 1;
        const start = index;
        while (index < input.len and input[index] >= '0' and input[index] <= '9') : (index += 1) {}
        const digit_count = index - start;
        if (digit_count == 0) return error.InvalidSyntax;
        if (digit_count > 9) return error.PrecisionLoss;
        date_time.nanosecond = try number(input[start..index]);
        for (digit_count..9) |_| date_time.nanosecond *= 10;
    }
    if (index == input.len) return error.InvalidSyntax;
    var offset: UtcOffset = .utc;
    if (input[index] == 'Z' or input[index] == 'z') {
        if (index + 1 != input.len) return error.InvalidSyntax;
    } else {
        if (input.len - index != 6 or (input[index] != '+' and input[index] != '-') or input[index + 3] != ':') return error.InvalidSyntax;
        offset = try UtcOffset.parse(input[index..]);
    }
    return .{ .timestamp = try Timestamp.fromCivil(date_time, offset), .offset = offset };
}

fn digits(output: []u8, value: u32) void {
    var remaining = value;
    var index = output.len;
    while (index != 0) {
        index -= 1;
        output[index] = '0' + @as(u8, @intCast(remaining % 10));
        remaining /= 10;
    }
    std.debug.assert(remaining == 0);
}

/// A caller-owned cache for repeated dates in the same Unix second. It must be
/// externally serialized; there is no global/threadlocal state. Both backwards
/// timestamps and changed offsets miss the cache, including midnight crossings.
pub const Formatter = struct {
    options: Options = .{},
    second: ?i64 = null,
    offset_minutes: i16 = 0,
    prefix: [19]u8 = undefined,
    calendar_conversions: usize = 0,

    pub fn init(options: Options) Error!Formatter {
        try options.validate();
        return .{ .options = options };
    }

    pub fn format(self: *Formatter, timestamp: Timestamp, output: []u8) Error![]const u8 {
        try self.options.validate();
        var fraction_bytes: [9]u8 = undefined;
        digits(&fraction_bytes, timestamp.fraction());
        var count: usize = switch (self.options.precision) {
            .seconds => 0,
            .milliseconds => 3,
            .microseconds => 6,
            .nanoseconds, .auto => 9,
        };
        if (self.options.precision == .auto) while (count != 0 and fraction_bytes[count - 1] == '0') {
            count -= 1;
        };
        const suffix_size: usize = if (self.options.offset.minutes == 0) 1 else 6;
        const length = 19 + @as(usize, if (count == 0) 0 else 1 + count) + suffix_size;
        if (output.len < length) return error.BufferTooSmall;
        const second = timestamp.unixSeconds();
        if (self.second != second or self.offset_minutes != self.options.offset.minutes) {
            const value = try timestamp.toCivil(self.options.offset);
            digits(self.prefix[0..4], value.date.year);
            self.prefix[4] = '-';
            digits(self.prefix[5..7], value.date.month);
            self.prefix[7] = '-';
            digits(self.prefix[8..10], value.date.day);
            self.prefix[10] = 'T';
            digits(self.prefix[11..13], value.hour);
            self.prefix[13] = ':';
            digits(self.prefix[14..16], value.minute);
            self.prefix[16] = ':';
            digits(self.prefix[17..19], value.second);
            self.second = second;
            self.offset_minutes = self.options.offset.minutes;
            self.calendar_conversions +%= 1;
        }
        @memcpy(output[0..19], &self.prefix);
        var end: usize = 19;
        if (count != 0) {
            output[end] = '.';
            end += 1;
            @memcpy(output[end..][0..count], fraction_bytes[0..count]);
            end += count;
        }
        if (suffix_size == 1) {
            output[end] = 'Z';
        } else {
            const offset = self.options.offset.minutes;
            const magnitude: u32 = @abs(offset);
            output[end] = if (offset < 0) '-' else '+';
            digits(output[end + 1 ..][0..2], magnitude / 60);
            output[end + 3] = ':';
            digits(output[end + 4 ..][0..2], magnitude % 60);
        }
        return output[0..length];
    }
};

pub fn format(timestamp: Timestamp, options: Options, output: []u8) Error![]const u8 {
    var formatter = try Formatter.init(options);
    return formatter.format(timestamp, output);
}

pub fn write(timestamp: Timestamp, options: Options, writer: *std.Io.Writer) (Error || std.Io.Writer.Error)!void {
    var buffer: [max_length]u8 = undefined;
    try writer.writeAll(try format(timestamp, options, &buffer));
}

test "RFC3339 exact fractions offsets negative epochs and leap year round trips" {
    const inputs = [_][]const u8{
        "1970-01-01T00:00:00Z",                "1969-12-31T23:59:59.999999999Z",
        "2000-02-29T23:59:59.123456789+05:30", "2024-12-31t23:59:59.1-03:30",
        "1677-09-21T00:12:43.145224192Z",      "2262-04-11T23:47:16.854775807Z",
    };
    for (inputs) |input| {
        const parsed = try parse(input);
        var bytes: [max_length]u8 = undefined;
        const output = try format(parsed.timestamp, .{ .offset = parsed.offset }, &bytes);
        try std.testing.expectEqual(parsed, try parse(output));
    }
    var bytes: [max_length]u8 = undefined;
    try std.testing.expectEqualStrings("1969-12-31T23:59:59.999999999Z", try format(.{ .nanoseconds = -1 }, .{}, &bytes));
    try std.testing.expectEqualStrings("1970-01-01T08:00:00+08:00", try format(.{ .nanoseconds = 0 }, .{ .offset = try UtcOffset.init(480), .precision = .seconds }, &bytes));
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.123Z", try format(.{ .nanoseconds = 123456789 }, .{ .precision = .milliseconds }, &bytes));
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.123456Z", try format(.{ .nanoseconds = 123456789 }, .{ .precision = .microseconds }, &bytes));
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.12Z", try format(.{ .nanoseconds = 120000000 }, .{ .precision = .auto }, &bytes));
}

test "RFC3339 rejects invalid dates leap seconds unknown offsets and lost precision" {
    try std.testing.expectError(error.InvalidDate, parse("1900-02-29T00:00:00Z"));
    try std.testing.expectError(error.InvalidTime, parse("2000-01-01T24:00:00Z"));
    try std.testing.expectError(error.LeapSecondUnsupported, parse("2016-12-31T23:59:60Z"));
    try std.testing.expectError(error.UnknownOffset, parse("2000-01-01T00:00:00-00:00"));
    try std.testing.expectError(error.PrecisionLoss, parse("2000-01-01T00:00:00.1234567890Z"));
    try std.testing.expectError(error.InvalidOffset, parse("2000-01-01T00:00:00+24:00"));
    try std.testing.expectError(error.OutOfRange, parse("0001-01-01T00:00:00Z"));
    const invalid = [_][]const u8{ "2000-01-01 00:00:00Z", "2000-01-01T00:00:00", "2000-01-01T00:00:00.Z", "2000-01-01T00:00:00Z\n", "2000-01-01T00:00:00+01:60", "abcd-01-01T00:00:00Z" };
    for (invalid) |input| if (parse(input)) |_| return error.TestUnexpectedResult else |_| {};
}

test "RFC3339 cache recomputes on clock rollback offset change and every second" {
    var formatter = try Formatter.init(.{});
    var bytes: [max_length]u8 = undefined;
    _ = try formatter.format(.{ .nanoseconds = 0 }, &bytes);
    for (0..1000) |index| _ = try formatter.format(.{ .nanoseconds = @intCast(index) }, &bytes);
    try std.testing.expectEqual(@as(usize, 1), formatter.calendar_conversions);
    try std.testing.expectEqualStrings("1969-12-31T23:59:59.999999999Z", try formatter.format(.{ .nanoseconds = -1 }, &bytes));
    formatter.options.offset = try UtcOffset.init(480);
    try std.testing.expectEqualStrings("1970-01-01T07:59:59.999999999+08:00", try formatter.format(.{ .nanoseconds = -1 }, &bytes));
    try std.testing.expectEqual(@as(usize, 3), formatter.calendar_conversions);
    for (0..max_length) |capacity| {
        @memset(&bytes, 0xaa);
        try std.testing.expectError(error.BufferTooSmall, formatter.format(.{ .nanoseconds = 0 }, bytes[0..capacity]));
        for (bytes) |byte| try std.testing.expectEqual(@as(u8, 0xaa), byte);
    }
}

test "RFC3339 seeded full timestamp range and parser mutations preserve exact instants" {
    var rng = std.Random.DefaultPrng.init(0x74696d656e736563);
    var bytes: [max_length]u8 = undefined;
    for (0..4096) |_| {
        const timestamp: Timestamp = .{ .nanoseconds = rng.random().int(i64) };
        const offset = try UtcOffset.init(rng.random().intRangeAtMost(i16, -1439, 1439));
        const output = try format(timestamp, .{ .offset = offset }, &bytes);
        try std.testing.expectEqual(Parsed{ .timestamp = timestamp, .offset = offset }, try parse(output));
        const at = rng.random().uintLessThan(usize, output.len);
        bytes[at] = rng.random().int(u8);
        if (parse(output)) |valid| {
            var canonical: [max_length]u8 = undefined;
            const spelling = try format(valid.timestamp, .{ .offset = valid.offset }, &canonical);
            try std.testing.expectEqual(valid, try parse(spelling));
        } else |_| {}
        for (0..output.len) |size| {
            // A truncation may create another valid complete timestamp (e.g.
            // a shorter fractional value followed by an existing suffix).
            if (parse(output[0..size])) |valid| {
                var canonical: [max_length]u8 = undefined;
                _ = try format(valid.timestamp, .{ .offset = valid.offset }, &canonical);
            } else |_| {}
        }
    }
}
