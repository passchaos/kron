const std = @import("std");

/// Positional, batched file writes. The offset advances after every successful
/// partial write, so a later error preserves the actual progress for diagnosis.
pub const Portable = struct {
    io: std.Io,
    file: std.Io.File,
    offset: u64,

    pub fn init(io: std.Io, file: std.Io.File, offset: u64) Portable {
        return .{ .io = io, .file = file, .offset = offset };
    }

    pub fn writeBatch(self: *Portable, bytes: []const u8) !void {
        try writeAll(self, actualWrite, bytes, &self.offset);
    }

    pub fn flush(_: *Portable) !void {}

    pub fn sync(self: *Portable) !void {
        try @import("directory_sync.zig").syncFile(self.io, self.file);
    }

    pub fn deinit(_: *Portable) void {}

    fn actualWrite(self: *Portable, bytes: []const u8, offset: u64) !usize {
        return self.file.writePositional(self.io, &.{bytes}, offset);
    }
};

pub fn writeAll(context: anytype, comptime write: anytype, bytes: []const u8, offset: *u64) !void {
    if (bytes.len > std.math.maxInt(u64) - offset.*) return error.OffsetOverflow;
    var done: usize = 0;
    while (done < bytes.len) {
        const n = try write(context, bytes[done..], offset.*);
        if (n == 0) return error.WriteZero;
        if (n > bytes.len - done) return error.InvalidWriteResult;
        done += n;
        offset.* += n;
    }
}

test "partial writes retain explicit offsets and finish the batch" {
    const Fake = struct {
        bytes: [16]u8 = @splat(0),
        count: usize = 0,
        fn write(self: *@This(), bytes: []const u8, offset: u64) !usize {
            const n = @min(bytes.len, 2);
            @memcpy(self.bytes[@intCast(offset)..][0..n], bytes[0..n]);
            self.count += 1;
            return n;
        }
    };
    var fake: Fake = .{};
    var offset: u64 = 3;
    try writeAll(&fake, Fake.write, "hello", &offset);
    try std.testing.expectEqual(@as(u64, 8), offset);
    try std.testing.expectEqual(@as(usize, 3), fake.count);
    try std.testing.expectEqualStrings("hello", fake.bytes[3..8]);
}

test "zero writes and disk failure preserve only successful progress" {
    const Fake = struct {
        calls: usize = 0,
        zero: bool,
        fn write(self: *@This(), _: []const u8, _: u64) !usize {
            self.calls += 1;
            if (self.calls == 1) return 2;
            if (self.zero) return 0;
            return error.NoSpaceLeft;
        }
    };
    var zero: Fake = .{ .zero = true };
    var offset: u64 = 10;
    try std.testing.expectError(error.WriteZero, writeAll(&zero, Fake.write, "hello", &offset));
    try std.testing.expectEqual(@as(u64, 12), offset);
    var fault: Fake = .{ .zero = false };
    offset = 10;
    try std.testing.expectError(error.NoSpaceLeft, writeAll(&fault, Fake.write, "hello", &offset));
    try std.testing.expectEqual(@as(u64, 12), offset);
}
