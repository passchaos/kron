//! Actual format.checksum/checksumV2 IEEE CRC batches. Headers, chunks and complete checksums are
//! consumed; setup and oracle checks occur outside timing. No measured allocator.
const std = @import("std");
const builtin = @import("builtin");
const Crc32 = @import("platform/crc32.zig").Crc32;
const format = @import("journal/format.zig");

pub fn main(init: std.process.Init) !void {
    var data: [65536 + 16]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(0x6b726f6e63726331);
    prng.random().bytes(&data);
    var header: [20]u8 = undefined;
    var reference: [24]u8 = undefined;
    prng.random().bytes(&reference);
    var output_bytes: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_bytes);
    const iterations = 10000;
    for ([_]usize{ 0, 1, 7, 8, 9, 15, 16, 17, 19, 20, 21, 23, 24, 25, 31, 32, 33, 43, 44, 45, 47, 48, 49, 63, 64, 65, 76, 79, 80, 81, 95, 96, 97, 111, 112, 113, 127, 128, 129, 143, 144, 145, 159, 160, 161, 169, 175, 176, 177, 191, 192, 193, 207, 208, 209, 223, 224, 225, 239, 240, 241, 255, 256, 257, 511, 512, 513, 2048, 16384, 65536 }) |length| for ([_]bool{ false, true }) |schema| {
        for (0..16) |offset| {
            const payload = data[offset..][0..length];
            try std.testing.expectEqual(std.hash.Crc32.hash(payload), Crc32.hash(payload));
            std.mem.writeInt(u64, header[0..8], 1, .little);
            std.mem.writeInt(u64, header[8..16], 1, .little);
            std.mem.writeInt(u32, header[16..20], @intCast(length), .little);
            var oracle = std.hash.Crc32.init();
            oracle.update(&header);
            if (schema) oracle.update(&reference);
            oracle.update(payload);
            const checked = if (schema) format.checksumV2(1, 1, &reference, payload) else format.checksum(1, 1, payload);
            try std.testing.expectEqual(oracle.final(), checked);
        }
        for (0..5) |repetition| {
            var checksum: u64 = 0;
            const start = std.Io.Clock.awake.now(init.io);
            for (0..iterations) |iteration| {
                const payload = data[iteration % 16 ..][0..length];
                const sequence: u64 = iteration + 1;
                const generation: u64 = iteration / 256 + 1;
                const result = if (schema) format.checksumV2(sequence, generation, &reference, payload) else format.checksum(sequence, generation, payload);
                std.mem.doNotOptimizeAway(result);
                checksum +%= result;
            }
            const elapsed = @max(0, start.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
            try std.json.Stringify.value(.{
                .benchmark = "journal-crc",
                .payload_bytes = length,
                .schema = schema,
                .repetition = repetition,
                .iterations = iterations,
                .elapsed_ns = elapsed,
                .ns_per_record = @as(f64, @floatFromInt(elapsed)) / iterations,
                .checksum = checksum,
                .clock_pairs = 1,
                .heap_allocations_in_batch = 0,
                .zig = builtin.zig_version_string,
                .optimize = builtin.mode,
                .scope = "Actual journal fixed-segment entry only; all IEEE protocol checks unchanged; not logging throughput",
            }, .{}, &output.interface);
            try output.interface.writeByte('\n');
        }
    };
    try output.interface.flush();
}
