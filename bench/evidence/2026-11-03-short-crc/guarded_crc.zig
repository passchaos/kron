const std = @import("std");
const builtin = @import("builtin");
const Crc32 = @import("crc").Crc32;

test "CRC exact segment bounds at both inaccessible page edges" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const linux = std.os.linux;
    const page_size = std.heap.pageSize();
    const address = linux.mmap(null, page_size * 3, .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    if (linux.errno(address) != .SUCCESS) return error.GuardMappingFailed;
    const mapping = @as([*]u8, @ptrFromInt(address))[0 .. page_size * 3];
    defer std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.munmap(mapping.ptr, mapping.len))) catch @panic("guard mapping cleanup failed");
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.mprotect(mapping.ptr, page_size, .{})));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.mprotect(mapping[page_size * 2 ..].ptr, page_size, .{})));
    const writable = mapping[page_size .. page_size * 2];
    for (0..129) |length| for ([_]bool{ false, true }) |at_end| {
        const input = if (at_end) writable[writable.len - length ..] else writable[0..length];
        for (input, 0..) |*byte, index| byte.* = @truncate((index * 73 + 19) ^ (index >> 3));
        const expected = std.hash.Crc32.hash(input);
        try std.testing.expectEqual(expected, Crc32.hash(input));
        for ([_]usize{ 0, 1, 15, 16, 20, 24, 31, 32, 47, 48, 63, 64, length }) |boundary| {
            const split = @min(length, boundary);
            var actual = Crc32.init();
            actual.update(input[0..split]);
            actual.update(input[split..]);
            try std.testing.expectEqual(expected, actual.final());
        }
    };
}
