//! Portable time output consumed by an independent Python datetime oracle.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    var bytes: [8192]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &bytes);
    const writer = &stdout.interface;
    const offsets = [_]i16{ -1439, -720, -480, -1, 0, 330, 345, 480, 840, 1439 };
    const extrema = [_]i64{ std.math.minInt(i64), -1000000001, -1, 0, 1, 1000000001, std.math.maxInt(i64) };
    for (offsets) |minutes| for (extrema) |nanoseconds| try timestamp(writer, nanoseconds, minutes);
    var rng = std.Random.DefaultPrng.init(0x74696d652d6f7261);
    for (0..4096) |_| try timestamp(writer, rng.random().int(i64), rng.random().intRangeAtMost(i16, -1439, 1439));
    const years = [_]u16{ 1, 4, 100, 400, 1600, 1677, 1700, 1800, 1900, 1969, 1970, 2000, 2100, 2262, 2400, 9999 };
    for (years) |year| {
        for (1..13) |month| {
            const count = try kron.time.daysInMonth(year, @intCast(month));
            for (1..@as(usize, count) + 1) |day| {
                const date = try kron.time.Date.init(year, @intCast(month), @intCast(day));
                const days = try date.epochDays();
                if (!std.meta.eql(date, try kron.time.Date.fromEpochDays(days))) return error.BadRoundtrip;
                try writer.print("D {d} {d} {d} {d} {d} {d}\n", .{ year, month, day, days, @intFromEnum(try date.weekday()), try date.dayOfYear() });
            }
        }
    }
    try stdout.interface.flush();
}

fn timestamp(writer: *std.Io.Writer, ns: i64, minutes: i16) !void {
    const value: kron.time.Timestamp = .{ .nanoseconds = ns };
    const offset = try kron.time.UtcOffset.init(minutes);
    var buffer: [kron.time.rfc3339.max_length]u8 = undefined;
    const output = try kron.time.rfc3339.format(value, .{ .offset = offset }, &buffer);
    const parsed = try kron.time.rfc3339.parse(output);
    if (parsed.timestamp.nanoseconds != ns or parsed.offset.minutes != minutes) return error.BadRoundtrip;
    try writer.print("T {d} {d} {s}\n", .{ ns, minutes, output });
}
