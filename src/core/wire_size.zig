//! Shared node-local wire lengths. Callers pair this observer with the bounded
//! ValueValidator and check result only after complete validation. No writer,
//! validation credential or borrowed event is stored here.
const std = @import("std");
const field = @import("field.zig");

pub const SizeVisitor = struct {
    pub const Error = error{};
    // A single length above u32 cannot fit the wire format. Cap each term at
    // u32_max + 1, preserving that error without overflowing a native total.
    // There are at most 256 nodes/keys and five event/source strings; their
    // bounded sum is below 2^42. Validation still finishes before result().
    comptime {
        std.debug.assert(@bitSizeOf(usize) <= 64);
    }
    total: u64 = 0,

    pub fn add(self: *SizeVisitor, amount: usize) void {
        self.total += @min(@as(u64, amount), @as(u64, std.math.maxInt(u32)) + 1);
    }

    pub fn blob(self: *SizeVisitor, length: usize, terminated: bool) void {
        self.add(4);
        self.add(length);
        if (terminated) self.add(1);
    }

    pub fn result(self: *const SizeVisitor) error{TooLarge}!usize {
        if (self.total > std.math.maxInt(u32)) return error.TooLarge;
        return @intCast(self.total);
    }

    pub fn onField(self: *SizeVisitor, entry: field.Field) Error!void {
        self.blob(entry.key.len, false);
    }

    pub fn onValue(self: *SizeVisitor, value: field.Value) Error!void {
        switch (value) {
            .null_value => self.add(1),
            .boolean => self.add(2),
            .signed, .unsigned => self.add(17),
            .float, .duration_ns, .timestamp_ns => self.add(9),
            .string, .bytes => |bytes| {
                self.add(5);
                self.add(bytes.len);
            },
            .array, .group => self.add(5),
        }
    }
};

test "wire size caps individually unrepresentable lengths without losing exact valid sums" {
    var visitor: SizeVisitor = .{};
    visitor.add(std.math.maxInt(u32));
    try std.testing.expectEqual(@as(usize, std.math.maxInt(u32)), try visitor.result());
    visitor.add(1);
    try std.testing.expectError(error.TooLarge, visitor.result());

    visitor = .{};
    // Every arbitrary usize term used by a full valid descriptor tree can
    // exceed u32, including multiple maxInt(usize) strings and keys.
    for (0..2 * field.max_value_nodes + 5) |_| visitor.blob(std.math.maxInt(usize), true);
    try std.testing.expectError(error.TooLarge, visitor.result());
    try std.testing.expect(visitor.total < @as(u64, 1) << 42);
}

test "bounded length arithmetic agrees with exact wide sums at wire limits and native extremes" {
    var random = std.Random.DefaultPrng.init(0x6c656e6774683634);
    for (0..8192) |iteration| {
        var visitor: SizeVisitor = .{};
        var exact: u128 = 0;
        const count = iteration % (2 * field.max_value_nodes + 6);
        for (0..count) |index| {
            const amount: usize = if (iteration % 4 == 0) random.random().uintLessThan(usize, 1024) else switch (index % 7) {
                0 => random.random().int(usize),
                1 => std.math.maxInt(usize),
                2 => std.math.maxInt(u32),
                3 => std.math.maxInt(u32) - 1,
                else => random.random().uintLessThan(usize, 1024),
            };
            visitor.add(amount);
            exact += amount;
        }
        if (exact > std.math.maxInt(u32)) {
            try std.testing.expectError(error.TooLarge, visitor.result());
        } else try std.testing.expectEqual(@as(usize, @intCast(exact)), try visitor.result());
    }
}
