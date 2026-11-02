//! Queue-only control for arbitrary capacities. All three CRC checks remain.
//! This does not represent full logging throughput or Foundation ranking.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const iterations = 100000;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    for ([_]usize{ 1, 2, 3, 7, 255, 256, 257, 512 }) |capacity| {
        const store = try kron.Journal.createMemory(init.gpa, init.io, .{
            .path = "unused-coordinate-control",
            .capacity = capacity,
            .max_record_bytes = 16,
        });
        defer store.deinit();
        // Independent wrap oracle outside the timed batches.
        var expected_slot: usize = 0;
        var expected_generation: u64 = 1;
        for (0..capacity * 3 + 5) |_| {
            var reservation = try store.reserve();
            errdefer if (!reservation.completed) reservation.abort();
            try std.testing.expectEqual(expected_slot, reservation.slot);
            std.mem.writeInt(u64, reservation.buffer()[0..8], reservation.sequence, .little);
            try reservation.commit(8);
            const record = (try store.peekChecked()) orelse return error.MissingRecord;
            try std.testing.expectEqual(expected_generation, record.generation);
            try std.testing.expectEqual(record.sequence, std.mem.readInt(u64, record.payload[0..8], .little));
            try store.release(record);
            expected_slot += 1;
            if (expected_slot == capacity) {
                expected_slot = 0;
                expected_generation += 1;
            }
        }
        for (0..5) |repetition| {
            const first_sequence = store.writtenTarget() + 1;
            var checksum: u64 = 0;
            const start = std.Io.Clock.awake.now(init.io);
            for (0..iterations) |_| {
                var reservation = try store.reserve();
                errdefer if (!reservation.completed) reservation.abort();
                std.mem.writeInt(u64, reservation.buffer()[0..8], reservation.sequence, .little);
                try reservation.commit(8);
                const record = (try store.peekChecked()) orelse return error.MissingRecord;
                checksum +%= std.mem.readInt(u64, record.payload[0..8], .little);
                try store.release(record);
            }
            const elapsed = @max(0, start.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
            const last_sequence = first_sequence + iterations - 1;
            try std.testing.expectEqual((first_sequence + last_sequence) * iterations / 2, checksum);
            try std.testing.expectEqual(last_sequence, store.writtenTarget());
            try std.testing.expectEqual(@as(usize, 0), store.pending());
            try std.json.Stringify.value(.{
                .benchmark = "queue-coordinate",
                .capacity = capacity,
                .iterations = iterations,
                .repetition = repetition,
                .elapsed_ns = elapsed,
                .ns_per_record = @as(f64, @floatFromInt(elapsed)) / iterations,
                .checksum = checksum,
                .first_sequence = first_sequence,
                .last_sequence = last_sequence,
                .pending = store.pending(),
                .verify_crc = store.verify_crc,
                .clock_pairs = 1,
                .zig = builtin.zig_version_string,
                .optimize = builtin.mode,
                .scope = "Memory Journal reserve/commit/checked peek/written release; CRC checks intact; queue-only control, not full logging",
            }, .{}, &output.interface);
            try output.interface.writeByte('\n');
        }
    }
    try output.interface.flush();
}
