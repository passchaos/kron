//! Optional qualification using ZKV's bounded persistence model and kron's
//! actual journal checkpoint encoder/decoder. No production implementation or
//! physical storage is exercised. Build the external module as "zkv_fault".
const std = @import("std");
const journal_format = @import("journal/format.zig");
const zkv_fault = @import("zkv_fault");

const checkpoint_offset = 128;
const checkpoint_bytes = 64;
const image_bytes = journal_format.header_bytes + 128;
const Device = zkv_fault.FaultableDevice(image_bytes, 1);
const End = enum { crash, failed_sync };
const Target = enum { empty, stale_valid };

const Boundary = struct {
    name: []const u8,
    epoch: u64,
    old_sequence: u64,
    new_sequence: u64,
};

const boundaries = [_]Boundary{
    .{ .name = "initial", .epoch = 2, .old_sequence = 0, .new_sequence = 1 },
    .{ .name = "next", .epoch = 3, .old_sequence = 1, .new_sequence = 2 },
    .{ .name = "byte_carry", .epoch = 255, .old_sequence = 255, .new_sequence = 256 },
    .{ .name = "word_carry", .epoch = 65535, .old_sequence = 65535, .new_sequence = 65536 },
    .{ .name = "double_word_carry", .epoch = 0xffffffff, .old_sequence = 0xffffffff, .new_sequence = 0x100000000 },
    .{ .name = "maximum", .epoch = std.math.maxInt(u64) - 1, .old_sequence = journal_format.max_sequence - 1, .new_sequence = journal_format.max_sequence },
};

const Counts = struct {
    cases: usize = 0,
    old_selected: usize = 0,
    new_selected: usize = 0,
    // These prefixes are shorter than the issued 64-byte positional write,
    // yet all checkpoint bytes equal the intended final image. Unchanged zero
    // padding does not have to be rewritten to form a complete checkpoint.
    complete_before_64: usize = 0,
    earliest_complete: usize = checkpoint_bytes,
    last_incomplete: usize = 0,
};

fn require(condition: bool) !void {
    if (!condition) return error.QualificationFailed;
}

fn baseline(boundary: Boundary, slot: usize, target: Target) ![image_bytes]u8 {
    var bytes: [image_bytes]u8 = undefined;
    journal_format.initialize(&bytes, 1, 64, 128, @splat(0x5a));
    @memset(bytes[checkpoint_offset..][0 .. checkpoint_bytes * 2], 0);
    journal_format.writeCheckpoint(&bytes, 1 - slot, boundary.epoch, boundary.old_sequence);
    if (target == .stale_valid) journal_format.writeCheckpoint(&bytes, slot, boundary.epoch - 1, boundary.old_sequence -| 1);
    const selected = try journal_format.checkpoint(&bytes);
    try require(selected.epoch == boundary.epoch and selected.sequence == boundary.old_sequence);
    return bytes;
}

fn terminate(device: *Device, ending: End) !void {
    if (ending == .failed_sync) {
        if (device.sync(.failure)) |_| return error.ExpectedSyncFailure else |err| {
            if (err != error.SyncFailed) return err;
        }
        try require(device.isPoisoned());
    }
    device.crash();
    try require(!device.isPoisoned());
    try require(device.durableLength() == image_bytes and device.volatileLength() == image_bytes);
}

fn checkPrefixes(boundary: Boundary) !Counts {
    var counts: Counts = .{};
    for (0..2) |slot| {
        inline for (.{ Target.empty, Target.stale_valid }) |target| {
            const initial = try baseline(boundary, slot, target);
            var updated = initial;
            journal_format.writeCheckpoint(&updated, slot, boundary.epoch + 1, boundary.new_sequence);
            const offset = checkpoint_offset + slot * checkpoint_bytes;
            const expected = updated[offset..][0..checkpoint_bytes];
            // Includes both endpoints: no new bytes durable and the whole
            // 64-byte write durable, plus every intermediate torn prefix.
            for (0..checkpoint_bytes + 1) |prefix| {
                inline for (.{ End.crash, End.failed_sync }) |ending| {
                    var device: Device = .{};
                    try device.write(0, &initial);
                    try device.sync(.success);
                    try device.write(offset, expected);
                    try device.persistPrefix(0, prefix);
                    try terminate(&device, ending);
                    const recovered = device.durableFile();
                    try journal_format.validate(recovered, 1, 64, 128);
                    const complete = std.mem.eql(u8, recovered[offset..][0..checkpoint_bytes], expected);
                    const selected = try journal_format.checkpoint(recovered);
                    if (complete) {
                        try require(selected.epoch == boundary.epoch + 1 and selected.sequence == boundary.new_sequence);
                        counts.new_selected += 1;
                        if (prefix < checkpoint_bytes) counts.complete_before_64 += 1;
                        counts.earliest_complete = @min(counts.earliest_complete, prefix);
                    } else {
                        // A corrupt/torn new entry must retain the complete old
                        // boundary, never acknowledge the new or a mixed one.
                        try require(selected.epoch == boundary.epoch and selected.sequence == boundary.old_sequence);
                        counts.old_selected += 1;
                        counts.last_incomplete = @max(counts.last_incomplete, prefix);
                    }
                    counts.cases += 1;
                }
            }
        }
    }
    return counts;
}

fn checkInvalidBoundaries() !usize {
    var cases: usize = 0;
    const boundary = boundaries[1];
    for (0..2) |slot| {
        inline for (.{ true, false }) |invalid_epoch| {
            const initial = try baseline(boundary, slot, .stale_valid);
            var updated = initial;
            // The real encoder supplies a valid CRC in both cases. The
            // decoder must still reject epoch zero and an out-of-range cursor.
            journal_format.writeCheckpoint(&updated, slot, if (invalid_epoch) 0 else boundary.epoch + 1, if (invalid_epoch) boundary.new_sequence else journal_format.max_sequence + 1);
            const offset = checkpoint_offset + slot * checkpoint_bytes;
            inline for (.{ End.crash, End.failed_sync }) |ending| {
                var device: Device = .{};
                try device.write(0, &initial);
                try device.sync(.success);
                try device.write(offset, updated[offset..][0..checkpoint_bytes]);
                try device.persistPrefix(0, checkpoint_bytes);
                try terminate(&device, ending);
                const selected = try journal_format.checkpoint(device.durableFile());
                try require(selected.epoch == boundary.epoch and selected.sequence == boundary.old_sequence);
                cases += 1;
            }
        }
    }
    return cases;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [2048]u8 = undefined;
    var output_file = std.Io.File.stdout().writer(init.io, &output_buffer);
    const writer = &output_file.interface;
    var total: usize = 0;
    for (boundaries) |boundary| {
        const counts = try checkPrefixes(boundary);
        total += counts.cases;
        try writer.print("{{\"boundary\":\"{s}\",\"old_sequence\":{d},\"new_sequence\":{d},\"old_epoch\":{d},\"new_epoch\":{d},\"prefix_cases\":{d},\"old_selected\":{d},\"new_selected\":{d},\"complete_before_64\":{d},\"first_complete_prefix\":{d},\"last_incomplete_prefix\":{d}}}\n", .{
            boundary.name, boundary.old_sequence, boundary.new_sequence, boundary.epoch, boundary.epoch + 1, counts.cases, counts.old_selected, counts.new_selected, counts.complete_before_64, counts.earliest_complete, counts.last_incomplete,
        });
    }
    const invalid = try checkInvalidBoundaries();
    try writer.print("{{\"result\":\"pass\",\"prefix_cases\":{d},\"invalid_boundary_cases\":{d},\"prefix_min\":0,\"prefix_max\":64,\"checkpoint_slots\":2,\"target_states\":2,\"crash_endings\":2,\"scope\":\"ZKV FaultableDevice persistence model with actual kron checkpoint protocol; no mmap, fsync, or physical power-loss evidence\",\"crc_limit\":\"Only these tested torn prefixes were qualified; CRC32 cannot guarantee detection of every possible collision\"}}\n", .{ total, invalid });
    try writer.flush();
}
