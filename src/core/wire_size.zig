//! Shared node-local wire lengths. Callers pair this observer with the bounded
//! ValueValidator and check result only after complete validation. No writer,
//! validation credential or borrowed event is stored here.
const std = @import("std");
const field = @import("field.zig");

pub const SizeVisitor = struct {
    pub const Error = error{};
    // At most 256 values, 256 keys, and five event/source strings carry usize
    // lengths. Their sum on supported targets is below 2^74. A u128 total
    // avoids per-node overflow branches and preserves validation priority.
    comptime {
        std.debug.assert(@bitSizeOf(usize) <= 64);
    }
    total: u128 = 0,

    pub fn add(self: *SizeVisitor, amount: usize) void {
        self.total += amount;
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
