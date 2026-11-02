const std = @import("std");
const builtin = @import("builtin");
const Crc32 = @import("crc32.zig").Crc32;

test "CRC segments: standard oracle matches every length through 512 and all alignments" {
    var bytes: [512 + 31]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x73686f7274777261);
    random.random().bytes(&bytes);
    for (0..32) |alignment| for (0..513) |length| {
        const input = bytes[alignment..][0..length];
        try std.testing.expectEqual(std.hash.Crc32.hash(input), Crc32.hash(input));
        const initial_state = random.random().int(u32);
        var oracle: std.hash.Crc32 = .{ .crc = initial_state };
        oracle.update(input);
        var crc: Crc32 = .{ .state = initial_state };
        crc.update(input);
        try std.testing.expectEqual(oracle.final(), crc.final());
    };
}

test "CRC segments: arbitrary seeds preserve journal partitions and block crossing controls" {
    var bytes: [4096 + 31]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x73686f7274706172);
    random.random().bytes(&bytes);
    const lengths = [_]usize{ 0, 1, 7, 8, 15, 16, 17, 19, 20, 21, 23, 24, 25, 31, 32, 33, 43, 44, 45, 47, 48, 49, 62, 63, 64, 65, 79, 80, 95, 96, 127, 128, 129, 255, 256, 257, 511, 512, 513, 1023, 1024, 1025, 4095, 4096 };
    for (0..32) |alignment| for (lengths) |length| {
        const input = bytes[alignment..][0..length];
        const state = random.random().int(u32);
        var oracle: std.hash.Crc32 = .{ .crc = state };
        oracle.update(input);
        for ([_]usize{ 15, 16, 17, 20, 23, 24, 25, 31, 32, 33, 47, 48, 49, 63, 64, 65, length / 2 }) |boundary| {
            const split = @min(boundary, length);
            var crc: Crc32 = .{ .state = state };
            crc.update(input[0..split]);
            crc.update(&.{});
            crc.update(input[split..]);
            try std.testing.expectEqual(oracle.final(), crc.final());
        }
        // The real segmented shape is header[20], reference[24], payload.
        // Keep all three updates distinct, including an empty final payload.
        if (length >= 44) {
            var crc: Crc32 = .{ .state = state };
            crc.update(input[0..20]);
            crc.update(input[20..44]);
            crc.update(input[44..]);
            try std.testing.expectEqual(oracle.final(), crc.final());
        }
    };
}

test "CRC segments: exact bounds at both inaccessible page edges" {
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
