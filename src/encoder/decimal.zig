//! Unpadded decimal output for record values and metadata. Sufficient native
//! buffers receive digits directly; streaming/short buffers use bounded stack
//! output. Width/precision and other bases stay in the general formatter.
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

fn digitsChunked(buffer: []u8, end: usize, value: u64, minimum: usize) usize {
    var remaining = value;
    var start = end;
    // At most two native-width divisions produce fixed eight-digit tails.
    // Each tail and the leading chunk use cheaper 32-bit digit-pair steps.
    const base = 100_000_000;
    while (remaining >= base) : (remaining /= base) {
        var tail: u32 = @intCast(remaining % base);
        inline for (0..4) |_| {
            start -= 2;
            buffer[start..][0..2].* = std.fmt.digits2(@intCast(tail % 100));
            tail /= 100;
        }
    }
    var head: u32 = @intCast(remaining);
    while (head >= 100) : (head /= 100) {
        start -= 2;
        buffer[start..][0..2].* = std.fmt.digits2(@intCast(head % 100));
    }
    if (head < 10) {
        start -= 1;
        buffer[start] = '0' + @as(u8, @intCast(head));
    } else {
        start -= 2;
        buffer[start..][0..2].* = std.fmt.digits2(@intCast(head));
    }
    const width = end - start;
    if (width < minimum) {
        const padded = end - minimum;
        @memset(buffer[padded..start], '0');
        start = padded;
    }
    return start;
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
        // Channel, route mask, generation and trace flags are usually small.
        // One or two direct stores skip digit-count estimation and the pair
        // loop for those fields.
        if (magnitude < 100) {
            writeSmallNative(writer, @intCast(magnitude), negative);
            return;
        }
        if (magnitude >= 100_000_000) writeLargeNative(writer, magnitude, negative) else writeNative(writer, magnitude, negative);
        return;
    }
    return writeBuffered(T, writer, magnitude, negative);
}

inline fn writeSmallNative(writer: *std.Io.Writer, magnitude: u8, negative: bool) void {
    const digits_len: usize = if (magnitude < 10) 1 else 2;
    const length = digits_len + @intFromBool(negative);
    const destination = writer.buffer[writer.end..][0..length];
    const start: usize = @intFromBool(negative);
    if (negative) destination[0] = '-';
    if (magnitude < 10) {
        destination[start] = '0' + magnitude;
    } else {
        destination[start..][0..2].* = std.fmt.digits2(magnitude);
    }
    writer.end += length;
}

// Streaming, short buffers and wide integers keep their bounded temporary
// frame out of ordinary direct native output.
noinline fn writeBuffered(comptime T: type, writer: *std.Io.Writer, magnitude: T, negative: bool) std.Io.Writer.Error!void {
    var buffer: [if (T == u64) 21 else 40]u8 = undefined;
    var start = buffer.len;
    if (T == u64) {
        start = if (magnitude >= 100_000_000) digitsChunked(&buffer, start, magnitude, 1) else digits(&buffer, start, magnitude, 1);
    } else {
        // Divide wide integers in 19-digit chunks. Every chunk then uses the
        // native-width digit-pair loop; at most two wide divisions are needed.
        // Keep each non-leading chunk padded even when its value is zero.
        const base = 10_000_000_000_000_000_000;
        var remaining = magnitude;
        while (remaining > std.math.maxInt(u64)) {
            const tail: u64 = @intCast(remaining % base);
            remaining /= base;
            start = digitsChunked(&buffer, start, tail, 19);
        }
        start = digitsChunked(&buffer, start, @intCast(remaining), 1);
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
    // Keep the direct loop out of recursive value rendering's larger frame.
    // The caller already proved 21 writable bytes; only actual digits change.
    const length = nativeDigits(magnitude) + @intFromBool(negative);
    const destination = writer.buffer[writer.end..][0..length];
    const start = digits(destination, length, magnitude, 1);
    std.debug.assert(start == @intFromBool(negative));
    if (negative) destination[0] = '-';
    writer.end += length;
}

noinline fn writeLargeNative(writer: *std.Io.Writer, magnitude: u64, negative: bool) void {
    // The additional chunk registers belong only to large values. Keep the
    // original small-value renderer's frame and digit-pair loop unchanged.
    const length = nativeDigits(magnitude) + @intFromBool(negative);
    const destination = writer.buffer[writer.end..][0..length];
    const start = digitsChunked(destination, length, magnitude, 1);
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

test "decimal eight-digit tails retain interior zeros and leading widths" {
    const base: u128 = 100_000_000;
    for ([_]u128{ 1, 9, 99, 100, 1844, 99999999 }) |head| {
        for ([_]u128{ 0, 1, 9, 10, 99, 100, 9999, 10000, 99999999 }) |middle| {
            for ([_]u128{ 0, 1, 9, 10, 99999999 }) |tail| {
                const number = head * base * base + middle * base + tail;
                try expectSame(number);
                try expectSame(-@as(i128, @intCast(number)));
                if (std.math.cast(u64, number)) |native| try expectSame(native);
            }
        }
    }
}

test "direct digits preserve buffered writer partial flushes and physical failure prefixes" {
    const Short = struct {
        interface: std.Io.Writer = .{ .buffer = &.{}, .vtable = &.{ .drain = drain } },
        bytes: [64]u8 = undefined,
        end: usize = 0,
        budget: usize,
        chunk: usize,
        failed: bool = false,
        after_failure: usize = 0,

        fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            const self: *@This() = @fieldParentPtr("interface", writer);
            std.debug.assert(writer.end == 0);
            if (self.failed) self.after_failure += 1;
            if (self.end == self.budget) {
                self.failed = true;
                return error.WriteFailed;
            }
            const input = for (data[0 .. data.len - 1]) |part| {
                if (part.len != 0) break part;
            } else if (splat != 0) data[data.len - 1] else return 0;
            const count = @min(input.len, self.chunk, self.budget - self.end);
            @memcpy(self.bytes[self.end..][0..count], input[0..count]);
            self.end += count;
            return count;
        }
    };
    inline for (.{ @as(i64, std.math.minInt(i64)), @as(u64, std.math.maxInt(u64)), @as(u64, 0), @as(u64, 123456) }) |value| {
        var expected_bytes: [64]u8 = undefined;
        var expected = std.Io.Writer.fixed(&expected_bytes);
        try expected.print("prefix:{d}:end", .{value});
        for ([_]usize{ 1, 20, 21, 64 }) |buffer_length| {
            for ([_]usize{ 1, 3, 7 }) |chunk| {
                for (0..expected.end + 1) |budget| {
                    var short: Short = .{ .budget = budget, .chunk = chunk };
                    var buffer: [64]u8 = undefined;
                    var hashed = std.Io.Writer.Hashed(std.hash.Fnv1a_64).initHasher(&short.interface, .init(), buffer[0..buffer_length]);
                    const Attempt = struct {
                        fn run(writer: *std.Io.Writer, number: @TypeOf(value)) !void {
                            try writer.writeAll("prefix:");
                            try write(writer, number);
                            try writer.writeAll(":end");
                            try writer.flush();
                        }
                    };
                    if (budget == expected.end) try Attempt.run(&hashed.writer, value) else try std.testing.expectError(error.WriteFailed, Attempt.run(&hashed.writer, value));
                    try std.testing.expectEqualStrings(expected.buffered()[0..budget], short.bytes[0..short.end]);
                    try std.testing.expectEqual(@as(usize, 0), short.after_failure);
                }
            }
        }
    }
}
