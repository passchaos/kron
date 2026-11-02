const std = @import("std");
const candidate = @import("candidate.zig");
const frontend = @import("frontend.zig");

fn oracle(seed: u32, data: []const u8) u32 {
    var state = seed;
    for (data) |byte| {
        state ^= byte;
        for (0..8) |_| state = (state >> 1) ^ (0xedb88320 & (0 -% (state & 1)));
    }
    return state;
}

test "native collapse matches independent IEEE bit oracle for every input basis" {
    var data: [64]u8 = @splat(0);
    for (0..512) |bit| {
        data[bit / 8] = @as(u8, 1) << @intCast(bit % 8);
        const expected = oracle(0, &data);
        inline for (.{ .serial, .parallel, .tree }) |mode| try std.testing.expectEqual(expected, candidate.update(mode, 0, &data));
        data[bit / 8] = 0;
    }
}

test "native full frontend preserves arbitrary seeds all small tails alignments and large fold loops" {
    var storage: [4160]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(0x6372635f6d617468);
    rng.random().bytes(&storage);
    for (0..16) |offset| {
        for (0..273) |selector| {
            const length = if (selector <= 256) selector else ([_]usize{ 271, 272, 273, 287, 288, 289, 511, 512, 513, 1023, 1024, 1025, 2048, 4095, 4096, 4111 })[selector - 257];
            const data = storage[offset..][0..length];
            for ([_]u32{ 0, 0xffffffff, 0x13579bdf }) |seed| {
                const expected = oracle(seed, data);
                inline for (.{ .serial, .parallel, .tree }) |mode| {
                    var crc: frontend.Crc32(mode) = .{ .state = seed };
                    crc.update(data);
                    try std.testing.expectEqual(expected, crc.state);
                    try std.testing.expectEqual(~expected, crc.final());
                }
            }
        }
    }
}

test "native frontend preserves incremental header schema payload boundaries and empty updates" {
    var data: [4160]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(0x6372635f70617274);
    rng.random().bytes(&data);
    for ([_]usize{ 0, 1, 15, 16, 17, 20, 24, 44, 63, 64, 65, 79, 80, 95, 96, 112, 127, 128, 129, 255, 256, 257, 512, 1024, 4096, 4111 }) |length| {
        const payload = data[0..length];
        const expected = oracle(0xffffffff, payload);
        try std.testing.expectEqual(~expected, std.hash.Crc32.hash(payload));
        for ([_]usize{ 0, 1, 15, 16, 17, 20, 24, 44, 63, 64, 65, length / 2, length }) |boundary| {
            const split = @min(boundary, length);
            inline for (.{ .serial, .parallel, .tree }) |mode| {
                var crc = frontend.Crc32(mode).init();
                crc.update(payload[0..split]);
                try std.testing.expectEqual(oracle(0xffffffff, payload[0..split]), crc.state);
                crc.update(&.{});
                crc.update(payload[split..]);
                try std.testing.expectEqual(expected, crc.state);
            }
        }
        inline for (.{ .serial, .parallel, .tree }) |mode| {
            var crc = frontend.Crc32(mode).init();
            const header_end = @min(20, length);
            const schema_end = @min(44, length);
            crc.update(payload[0..header_end]);
            try std.testing.expectEqual(oracle(0xffffffff, payload[0..header_end]), crc.state);
            crc.update(payload[header_end..schema_end]);
            try std.testing.expectEqual(oracle(0xffffffff, payload[0..schema_end]), crc.state);
            crc.update(payload[schema_end..]);
            try std.testing.expectEqual(expected, crc.state);
        }
    }
}
