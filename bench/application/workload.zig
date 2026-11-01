//! Deterministic application work, shared by logging and no-logging trials.
//! compute uses a small working set; cache uses data-dependent 1MiB updates.
//! This is a synthetic request model, not an asserted production service.
const std = @import("std");

pub const Kind = enum { compute, cache };
pub const seed: u64 = 0x6b726f6e61707031;

pub fn tableWords(kind: Kind) usize {
    return switch (kind) {
        .compute => 256,
        .cache => 131072,
    };
}

pub fn rounds(kind: Kind) usize {
    return switch (kind) {
        .compute => 64,
        .cache => 32,
    };
}

pub fn mix(input: u64) u64 {
    var value = input;
    value = (value ^ (value >> 30)) *% 0xbf58476d1ce4e5b9;
    value = (value ^ (value >> 27)) *% 0x94d049bb133111eb;
    return value ^ (value >> 31);
}

pub fn initialize(table: []u64, producer: usize) void {
    for (table, 0..) |*item, index| item.* = mix(seed +% (@as(u64, producer) *% 0x9e3779b97f4a7c15) +% index);
}

pub fn request(table: []u64, kind: Kind, id: u64) u64 {
    std.debug.assert(table.len == tableWords(kind));
    var value = mix(seed ^ id);
    for (0..rounds(kind)) |round| {
        const index: usize = @intCast(value & (table.len - 1));
        value = mix(value ^ table[index] ^ @as(u64, round));
        table[index] = value +% id;
    }
    return value;
}

pub fn share(total: usize, producers: usize, id: usize) usize {
    return total / producers + @intFromBool(id < total % producers);
}

test "application work depends on requests and working state and preserves deterministic replay" {
    var first: [256]u64 = undefined;
    var replay: [256]u64 = undefined;
    initialize(&first, 3);
    initialize(&replay, 3);
    const original = first;
    const result = request(&first, .compute, 99);
    try std.testing.expectEqual(result, request(&replay, .compute, 99));
    try std.testing.expectEqualSlices(u64, &first, &replay);
    try std.testing.expect(!std.mem.eql(u64, &original, &first));
    try std.testing.expect(result != request(&replay, .compute, 100));
    initialize(&replay, 4);
    try std.testing.expect(result != request(&replay, .compute, 99));
    for ([_]usize{ 1, 4, 16 }) |producers| {
        var count: usize = 0;
        for (0..producers) |producer| count += share(103, producers, producer);
        try std.testing.expectEqual(@as(usize, 103), count);
    }
}
