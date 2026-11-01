//! Unpadded decimal output for record values and metadata. Width/precision and
//! other bases stay in the general formatter used by deferred messages.
const std = @import("std");

pub fn write(writer: *std.Io.Writer, value: anytype) std.Io.Writer.Error!void {
    const info = @typeInfo(@TypeOf(value)).int;
    comptime std.debug.assert(info.bits <= 128);
    const negative = if (info.signedness == .signed) value < 0 else false;
    const magnitude = @abs(value);
    if (info.bits <= 64) return writeMagnitude(u64, writer, magnitude, negative);
    if (std.math.cast(u64, magnitude)) |small| return writeMagnitude(u64, writer, small, negative);
    return writeMagnitude(u128, writer, magnitude, negative);
}

fn digits(buffer: []u8, end: usize, value: u64, minimum: usize) usize {
    var remaining = value;
    var start = end;
    while (remaining >= 100) : (remaining /= 100) {
        start -= 2;
        buffer[start..][0..2].* = std.fmt.digits2(@intCast(remaining % 100));
    }
    if (remaining < 10) {
        start -= 1;
        buffer[start] = '0' + @as(u8, @intCast(remaining));
    } else {
        start -= 2;
        buffer[start..][0..2].* = std.fmt.digits2(@intCast(remaining));
    }
    const width = end - start;
    if (width < minimum) {
        const padded = end - minimum;
        @memset(buffer[padded..start], '0');
        start = padded;
    }
    return start;
}

fn writeMagnitude(comptime T: type, writer: *std.Io.Writer, magnitude: T, negative: bool) std.Io.Writer.Error!void {
    if (T == u64 and writer.buffer.len - writer.end >= 21) {
        writeNative(writer, magnitude, negative);
        return;
    }
    var buffer: [if (T == u64) 21 else 40]u8 = undefined;
    var start = buffer.len;
    if (T == u64) {
        start = digits(&buffer, start, magnitude, 1);
    } else {
        // Divide wide integers in 19-digit chunks. Every chunk then uses the
        // native-width digit-pair loop; at most two wide divisions are needed.
        // Keep each non-leading chunk padded even when its value is zero.
        const base = 10_000_000_000_000_000_000;
        var remaining = magnitude;
        while (remaining > std.math.maxInt(u64)) {
            const tail: u64 = @intCast(remaining % base);
            remaining /= base;
            start = digits(&buffer, start, tail, 19);
        }
        start = digits(&buffer, start, @intCast(remaining), 1);
    }
    if (negative) {
        start -= 1;
        buffer[start] = '-';
    }
    // One byte-slice write retains the original partial-write behavior, with
    // no alignment calculation or writer callback after the first failure.
    try writer.writeAll(buffer[start..]);
}

noinline fn writeNative(writer: *std.Io.Writer, magnitude: u64, negative: bool) void {
    const length = nativeDigits(magnitude) + @intFromBool(negative);
    const destination = writer.buffer[writer.end..][0..length];
    const start = digits(destination, length, magnitude, 1);
    std.debug.assert(start == @intFromBool(negative));
    if (negative) destination[0] = '-';
    writer.end += length;
}

fn nativeDigits(value: u64) usize {
    const powers = comptime blk: {
        var table: [20]u64 = undefined;
        var power: u64 = 1;
        for (&table, 0..) |*entry, index| {
            entry.* = power;
            if (index != table.len - 1) power *= 10;
        }
        break :blk table;
    };
    // floor(log2(value)) * log10(2) gives a lower decimal exponent;
    // one exact power-of-ten comparison corrects the estimate. The rational
    // approximation is within one exponent throughout the native range.
    const log2: u32 = 63 - @clz(value | 1);
    const exponent: usize = @intCast(log2 * 1233 >> 12);
    return exponent + 1 + @intFromBool(value >= powers[exponent + 1]);
}

fn expectSame(value: anytype) !void {
    var expected_bytes: [40]u8 = undefined;
    var actual_bytes: [40]u8 = undefined;
    var expected = std.Io.Writer.fixed(&expected_bytes);
    var actual = std.Io.Writer.fixed(&actual_bytes);
    try expected.print("{d}", .{value});
    try write(&actual, value);
    try std.testing.expectEqualStrings(expected.buffered(), actual.buffered());
}

test "decimal output matches the standard formatter for native widths and all u16 values" {
    for (0..65536) |value| try expectSame(@as(u16, @intCast(value)));
    inline for (.{ i8, i16, i32, i64, u8, u16, u32, u64 }) |T| {
        try expectSame(@as(T, std.math.minInt(T)));
        try expectSame(@as(T, std.math.maxInt(T)));
        try expectSame(@as(T, 0));
        try expectSame(@as(T, 1));
    }
}

test "decimal output preserves wide decimal chunks signs and every binary boundary" {
    inline for (.{ u128, i128 }) |T| {
        try expectSame(@as(T, std.math.minInt(T)));
        try expectSame(@as(T, std.math.maxInt(T)));
    }
    var power: u128 = 1;
    for (0..39) |exponent| {
        try expectSame(power - 1);
        try expectSame(power);
        try expectSame(power + 1);
        if (power <= std.math.maxInt(i128)) try expectSame(-@as(i128, @intCast(power)));
        if (exponent != 38) power *= 10;
    }
    for (0..128) |bit| {
        const boundary = @as(u128, 1) << @intCast(bit);
        try expectSame(boundary - 1);
        try expectSame(boundary);
        try expectSame(boundary + 1);
    }
    const base: u128 = 10_000_000_000_000_000_000;
    try expectSame(base * base);
    try expectSame(base * base + 1);
    try expectSame(base * base + base - 1);
    var rng = std.Random.DefaultPrng.init(0x646563696d616c);
    for (0..2048) |_| {
        const value = rng.random().int(u128);
        try expectSame(value);
        try expectSame(@as(i128, @bitCast(value)));
    }
}

test "decimal output preserves all fixed writer prefixes on capacity failure" {
    inline for (.{ @as(u128, std.math.maxInt(u128)), @as(i128, std.math.minInt(i128)), @as(i64, -1234567890123), @as(u64, 0) }) |value| {
        var full_bytes: [40]u8 = undefined;
        var full = std.Io.Writer.fixed(&full_bytes);
        try full.print("{d}", .{value});
        for (0..full.end) |capacity| {
            var old_bytes: [40]u8 = undefined;
            var new_bytes: [40]u8 = undefined;
            var old = std.Io.Writer.fixed(old_bytes[0..capacity]);
            var new = std.Io.Writer.fixed(new_bytes[0..capacity]);
            try std.testing.expectError(error.WriteFailed, old.print("{d}", .{value}));
            try std.testing.expectError(error.WriteFailed, write(&new, value));
            try std.testing.expectEqualStrings(old.buffered(), new.buffered());
        }
    }
}

test "direct native output preserves binary decimal boundaries and existing writer bytes" {
    var power: u64 = 1;
    for (0..20) |exponent| {
        try expectSame(power - 1);
        try expectSame(power);
        try expectSame(power + 1);
        if (exponent != 19) power *= 10;
    }
    for (0..64) |bit| {
        const value: u64 = @as(u64, 1) << @intCast(bit);
        try expectSame(value - 1);
        try expectSame(value);
        try expectSame(value + 1);
    }
    var random = std.Random.DefaultPrng.init(0x6469726563743634);
    for (0..4096) |_| {
        const value = random.random().int(u64);
        try expectSame(value);
        try expectSame(@as(i64, @bitCast(value)));
    }
    var bytes: [128]u8 = @splat(0xcc);
    var writer = std.Io.Writer.fixed(&bytes);
    try writer.writeAll("prefix:");
    try write(&writer, @as(i64, std.math.minInt(i64)));
    try std.testing.expectEqualStrings("prefix:-9223372036854775808", writer.buffered());
    for (bytes[writer.end..]) |byte| try std.testing.expectEqual(@as(u8, 0xcc), byte);
}
