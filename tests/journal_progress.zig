//! Written progress and publication contracts through public Journal APIs.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const testing = std.testing;
const Options = @typeInfo(@TypeOf(kron.Journal.createMemory)).@"fn".params[2].type.?;
const Record = @typeInfo(@typeInfo(@TypeOf(kron.Journal.peekChecked(undefined))).error_union.payload).optional.child;
const payload_length = 16;

fn expectProgress(journal: *const kron.Journal, sequence: u64) !void {
    try testing.expectEqual(sequence, journal.writtenTarget());
    // This ordinary raw read is performed ONLY with no concurrent writer.
    // Memory/mmap fixtures require the supported little-endian 64-bit layout.
    // It checks immediate publication at the format's written cursor offset,
    // without sync. Concurrent observers use only the atomic public accessor.
    try testing.expectEqual(sequence, std.mem.readInt(u64, journal.mapping.bytes[72..80], .little));
}

fn append(journal: *kron.Journal, reference: ?kron.schema.Ref) !u64 {
    var reservation = if (reference) |ref| try journal.reserveWithSchema(ref) else try journal.reserve();
    defer reservation.abort();
    const buffer = reservation.buffer();
    std.mem.writeInt(u64, buffer[0..8], reservation.sequence, .little);
    std.mem.writeInt(u32, buffer[8..12], 0x81a2c3e4, .little);
    std.mem.writeInt(u32, buffer[12..16], std.hash.Crc32.hash(buffer[0..12]), .little);
    try reservation.commit(payload_length);
    return reservation.sequence;
}

fn expectRecord(record: Record, sequence: u64, capacity: usize, reference: ?kron.schema.Ref) !void {
    try testing.expectEqual(sequence, record.sequence);
    try testing.expectEqual((sequence - 1) / capacity + 1, record.generation);
    try testing.expectEqual(@as(usize, payload_length), record.payload.len);
    try testing.expectEqual(sequence, std.mem.readInt(u64, record.payload[0..8], .little));
    try testing.expectEqual(@as(u32, 0x81a2c3e4), std.mem.readInt(u32, record.payload[8..12], .little));
    try testing.expectEqual(std.hash.Crc32.hash(record.payload[0..12]), std.mem.readInt(u32, record.payload[12..16], .little));
    try testing.expectEqualDeep(reference, record.schema_ref);
}

fn ordinaryRelease(journal: *kron.Journal, reference: ?kron.schema.Ref) !void {
    const capacity = 3;
    try expectProgress(journal, 0);
    for (1..4) |sequence| {
        try testing.expectEqual(@as(u64, sequence), try append(journal, reference));
        try expectProgress(journal, 0);
    }
    try testing.expectError(error.Full, journal.reserve());
    var records: [capacity]Record = undefined;
    const batch = try journal.peekBatchChecked(&records);
    try testing.expectEqual(@as(usize, capacity), batch.len);
    for (batch, 1..) |record, sequence| try expectRecord(record, sequence, capacity, reference);
    try testing.expectError(error.InvalidRecord, journal.release(batch[1]));
    try expectProgress(journal, 0);
    if (!journal.isPersistent()) {
        try testing.expectError(error.UnsupportedDurability, journal.releaseAfter(batch[0], .durable));
        try expectProgress(journal, 0);
        try testing.expectEqual(@as(usize, capacity), journal.pending());
    }
    try journal.release(batch[0]);
    try expectProgress(journal, 1);
    try testing.expectEqual(@as(usize, 2), journal.pending());
    try testing.expectError(error.InvalidRecord, journal.release(batch[0]));
    try expectProgress(journal, 1);
    try testing.expectEqual(@as(u64, 4), try append(journal, reference));
    try testing.expectError(error.Full, journal.reserve());
    try expectProgress(journal, 1);
    for (2..5) |sequence| {
        const record = (try journal.peekChecked()) orelse return error.MissingRecord;
        try expectRecord(record, sequence, capacity, reference);
        if (sequence == 2) try journal.releaseAfter(record, .written) else try journal.release(record);
        try expectProgress(journal, sequence);
        try testing.expectEqual(4 - sequence, journal.pending());
    }
    for (5..18) |sequence| {
        try testing.expectEqual(@as(u64, sequence), try append(journal, reference));
        try expectProgress(journal, sequence - 1);
        const record = (try journal.peekChecked()) orelse return error.MissingRecord;
        try expectRecord(record, sequence, capacity, reference);
        try journal.release(record);
        try expectProgress(journal, sequence);
        try testing.expectEqual(@as(usize, 0), journal.pending());
    }
    try testing.expect((try journal.peekChecked()) == null);
    try testing.expectEqual(@as(usize, capacity), journal.highWater());
    try testing.expectEqual(@as(u64, 0), journal.durableReclaimedTarget());
}

const PeekStyle = enum { unchecked, checked, batch, checked_batch };

fn peekUsing(journal: *kron.Journal, style: PeekStyle) !?Record {
    return switch (style) {
        .unchecked => journal.peek(),
        .checked => try journal.peekChecked(),
        .batch, .checked_batch => blk: {
            var records: [4]Record = undefined;
            const batch = if (style == .batch) journal.peekBatch(&records) else try journal.peekBatchChecked(&records);
            // Transfer the first borrowed descriptor to the caller; later
            // descriptors are unused and no record is released here.
            break :blk if (batch.len == 0) null else batch[0];
        },
    };
}

fn leadingTombstones(journal: *kron.Journal, reference: ?kron.schema.Ref) !void {
    const capacity = 4;
    for (std.meta.tags(PeekStyle), 0..) |style, round| {
        const first_sequence: u64 = round * 9 + 1;
        try expectProgress(journal, first_sequence - 1);
        for (0..2) |index| {
            var gap = try journal.reserve();
            try testing.expectEqual(first_sequence + index, gap.sequence);
            gap.abort();
        }
        for (2..4) |index| try testing.expectEqual(first_sequence + index, try append(journal, reference));
        try testing.expectEqual(@as(usize, 4), journal.pending());
        try testing.expectError(error.Full, journal.reserve());
        try expectProgress(journal, first_sequence - 1);
        const first = (try peekUsing(journal, style)) orelse return error.MissingRecord;
        try expectRecord(first, first_sequence + 2, capacity, reference);
        try expectProgress(journal, first_sequence + 1);
        try testing.expectEqual(@as(usize, 2), journal.pending());
        // Crossing the leading tombstones immediately enables producer reuse.
        for (4..6) |index| try testing.expectEqual(first_sequence + index, try append(journal, reference));
        try testing.expectError(error.Full, journal.reserve());
        try expectProgress(journal, first_sequence + 1);
        for (2..6) |index| {
            const record = (try journal.peekChecked()) orelse return error.MissingRecord;
            try expectRecord(record, first_sequence + index, capacity, reference);
            try journal.release(record);
            try expectProgress(journal, first_sequence + index);
            try testing.expectEqual(5 - index, journal.pending());
        }
        for (6..8) |index| {
            var gap = try journal.reserve();
            try testing.expectEqual(first_sequence + index, gap.sequence);
            gap.abort();
        }
        try expectProgress(journal, first_sequence + 5);
        try testing.expect((try peekUsing(journal, style)) == null);
        try expectProgress(journal, first_sequence + 7);
        try testing.expectEqual(@as(usize, 0), journal.pending());
        try testing.expectEqual(first_sequence + 8, try append(journal, reference));
        const record = (try journal.peekChecked()) orelse return error.MissingRecord;
        try expectRecord(record, first_sequence + 8, capacity, reference);
        try journal.release(record);
        try expectProgress(journal, first_sequence + 8);
    }
}

fn lateCrcDamage(journal: *kron.Journal, reference: ?kron.schema.Ref) !void {
    const capacity = 3;
    for (1..4) |sequence| try testing.expectEqual(@as(u64, sequence), try append(journal, reference));
    var records: [capacity]Record = undefined;
    const batch = try journal.peekBatchChecked(&records);
    try testing.expectEqual(@as(usize, capacity), batch.len);
    // Deliberate storage fault injection through public borrowed payloads;
    // fixtures own writable backing. Application consumers never mutate it.
    // Damage occurs AFTER successful checked peek, before written release.
    const first_payload = @constCast(batch[0].payload);
    first_payload[0] ^= 0x80;
    try testing.expectError(error.CorruptRecord, journal.release(batch[0]));
    try expectProgress(journal, 0);
    try testing.expectEqual(@as(usize, capacity), journal.pending());
    try testing.expectError(error.Full, journal.reserve());
    first_payload[0] ^= 0x80;
    try journal.release(batch[0]);
    try expectProgress(journal, 1);
    try testing.expectEqual(@as(u64, 4), try append(journal, reference));
    try testing.expectError(error.InvalidRecord, journal.release(batch[2]));
    try expectProgress(journal, 1);
    const second_payload = @constCast(batch[1].payload);
    second_payload[5] ^= 0x20;
    try testing.expectError(error.CorruptRecord, journal.peekBatchChecked(&records));
    try testing.expectError(error.CorruptRecord, journal.release(batch[1]));
    try testing.expectError(error.CorruptRecord, journal.release(batch[2]));
    try expectProgress(journal, 1);
    try testing.expectEqual(@as(usize, capacity), journal.pending());
    try testing.expectError(error.Full, journal.reserve());
    second_payload[5] ^= 0x20;
    const repaired = (try journal.peekChecked()) orelse return error.MissingRecord;
    try expectRecord(repaired, 2, capacity, reference);
    try journal.release(repaired);
    try expectProgress(journal, 2);
    try testing.expectEqual(@as(u64, 5), try append(journal, reference));
    try testing.expectError(error.Full, journal.reserve());
    for (3..6) |sequence| {
        const record = (try journal.peekChecked()) orelse return error.MissingRecord;
        try expectRecord(record, sequence, capacity, reference);
        try journal.release(record);
        try expectProgress(journal, sequence);
    }
    try testing.expectEqual(@as(usize, 0), journal.pending());
    try testing.expectEqual(@as(usize, capacity), journal.highWater());

    // A failing checked peek may successfully reclaim its leading tombstone.
    // Its cursor must stop before the corrupt record, rather than undoing the
    // valid prefix or incorrectly declaring the damaged sequence written.
    var leading = try journal.reserve();
    defer leading.abort();
    try testing.expectEqual(@as(u64, 6), leading.sequence);
    var damaged_reservation = if (reference) |ref| try journal.reserveWithSchema(ref) else try journal.reserve();
    defer damaged_reservation.abort();
    try testing.expectEqual(@as(u64, 7), damaged_reservation.sequence);
    const damaged_payload = damaged_reservation.buffer()[0..payload_length];
    std.mem.writeInt(u64, damaged_payload[0..8], damaged_reservation.sequence, .little);
    std.mem.writeInt(u32, damaged_payload[8..12], 0x81a2c3e4, .little);
    std.mem.writeInt(u32, damaged_payload[12..16], std.hash.Crc32.hash(damaged_payload[0..12]), .little);
    try damaged_reservation.commit(payload_length);
    try testing.expectEqual(@as(u64, 8), try append(journal, reference));
    damaged_payload[5] ^= 0x20;
    leading.abort();
    try expectProgress(journal, 5);
    try testing.expectError(error.CorruptRecord, journal.peekChecked());
    try expectProgress(journal, 6);
    try testing.expectEqual(@as(usize, 2), journal.pending());
    const damaged = journal.peek() orelse return error.MissingRecord;
    try testing.expectEqual(@as(u64, 7), damaged.sequence);
    try testing.expectError(error.CorruptRecord, journal.release(damaged));
    try expectProgress(journal, 6);
    try testing.expectEqual(@as(u64, 9), try append(journal, reference));
    try testing.expectError(error.Full, journal.reserve());
    damaged_payload[5] ^= 0x20;
    for (7..10) |sequence| {
        const record = (try journal.peekChecked()) orelse return error.MissingRecord;
        try expectRecord(record, sequence, capacity, reference);
        try journal.release(record);
        try expectProgress(journal, sequence);
    }
    try testing.expectEqual(@as(usize, 0), journal.pending());
}

const Marker = struct { sequence: u64, inverse: u64, crc: u32, signal: u32 };
const Publisher = struct {
    journal: *kron.Journal,
    record: Record,
    marker: *Marker,
    expected: Marker,

    fn run(self: *@This()) void {
        self.marker.* = self.expected;
        self.journal.release(self.record) catch @panic("publication release failed");
    }
};

fn publicationObserver(journal: *kron.Journal, reference: ?kron.schema.Ref) !void {
    for (1..65) |sequence| {
        try testing.expectEqual(@as(u64, sequence), try append(journal, reference));
        const record = (try journal.peekChecked()) orelse return error.MissingRecord;
        try expectRecord(record, sequence, 1, reference);
        var marker: Marker = .{ .sequence = 0, .inverse = 0, .crc = 0, .signal = 0 };
        const expected: Marker = .{ .sequence = sequence, .inverse = ~@as(u64, sequence), .crc = std.hash.Crc32.hash(record.payload), .signal = 0xf7e6d5c4 };
        var publisher: Publisher = .{ .journal = journal, .record = record, .marker = &marker, .expected = expected };
        const thread = try std.Thread.spawn(.{}, Publisher.run, .{&publisher});
        var joined = false;
        defer if (!joined) thread.join();
        const deadline = kron.Deadline.after(testing.io, 5 * std.time.ns_per_s);
        // No completion flag, event, raw cursor read or join may publish the
        // marker to this observer. Only writtenTarget's acquire observation
        // of the consumer's progress carries the preceding plain writes.
        while (journal.writtenTarget() < sequence) {
            if (deadline.expired(testing.io)) return error.TestPublicationTimeout;
            std.Thread.yield() catch {};
        }
        // Complete the plain owned marker comparison BEFORE join, so even
        // an optimized build cannot defer an unused aggregate snapshot.
        try testing.expectEqualDeep(expected, marker);
        thread.join();
        joined = true;
        // The writer is now joined, so a raw cursor check is safe again.
        try expectProgress(journal, sequence);
        try testing.expectEqual(@as(usize, 0), journal.pending());
    }
}

fn runStorage(comptime mapped: bool, comptime with_schema: bool, capacity: usize, test_case: anytype) !void {
    if (mapped and !kron.platform.shared_journal) return error.SkipZigTest;
    if (!mapped and !kron.platform.memory_queue) return error.SkipZigTest;
    var tmp: testing.TmpDir = undefined;
    if (mapped) tmp = testing.tmpDir(.{});
    defer if (mapped) tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const options: Options = .{
        .path = if (mapped) try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/progress.journal", .{tmp.sub_path}) else "",
        .capacity = capacity,
        .max_record_bytes = payload_length,
        .schema_capacity = if (with_schema) 1 else 0,
        .max_schema_bytes = 512,
    };
    const journal = if (mapped) try kron.Journal.create(testing.allocator, testing.io, options) else try kron.Journal.createMemory(testing.allocator, testing.io, options);
    defer journal.deinit();
    const reference: ?kron.schema.Ref = if (with_schema) try journal.registerSchema(.{ .scope = "progress.schema", .message = "record" }) else null;
    try test_case(journal, reference);
}

fn recoveryGap(comptime with_schema: bool) !void {
    if (!kron.platform.shared_journal) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const capacity = 8;
    const options: Options = .{
        .path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/recovery-progress.journal", .{tmp.sub_path}),
        .capacity = capacity,
        .max_record_bytes = payload_length,
        .schema_capacity = if (with_schema) 1 else 0,
        .max_schema_bytes = 512,
    };
    const first = try kron.Journal.create(testing.allocator, testing.io, options);
    var first_live = true;
    defer if (first_live) first.deinit();
    const reference: ?kron.schema.Ref = if (with_schema) try first.registerSchema(.{ .scope = "progress.recovery", .message = "record" }) else null;
    _ = try first.reserve(); // Old gap at sequence 1.
    try testing.expectEqual(@as(u64, 2), try append(first, reference));
    _ = try first.reserve(); // Old gap at sequence 3.
    try testing.expectEqual(@as(u64, 4), try append(first, reference));
    var aborted = try first.reserve();
    aborted.abort();
    _ = try first.reserve(); // Old abandoned trailing sequence 6.
    try expectProgress(first, 0);
    first.deinit();
    first_live = false;

    const journal = try kron.Journal.create(testing.allocator, testing.io, options);
    defer journal.deinit();
    try expectProgress(journal, 1);
    try testing.expectEqual(@as(usize, 2), journal.pending());
    var new_gap = try journal.reserve();
    defer new_gap.abort();
    try testing.expectEqual(@as(u64, 7), new_gap.sequence);
    for (8..10) |sequence| try testing.expectEqual(@as(u64, sequence), try append(journal, reference));
    try testing.expectError(error.Full, journal.reserve()); // Old record 2 blocks turn 10.
    var records: [capacity]Record = undefined;
    const recovered = try journal.peekBatchChecked(&records);
    try testing.expectEqual(@as(usize, 2), recovered.len);
    try expectRecord(recovered[0], 2, capacity, reference);
    try expectRecord(recovered[1], 4, capacity, reference);
    try testing.expectError(error.InvalidRecord, journal.release(recovered[1]));
    try expectProgress(journal, 1);
    try journal.release(recovered[0]);
    try expectProgress(journal, 3); // Confirms the scanned old gap at 3 immediately.
    for (10..12) |sequence| try testing.expectEqual(@as(u64, sequence), try append(journal, reference));
    try testing.expectError(error.Full, journal.reserve()); // Old record 4 blocks turn 12.
    try journal.release(recovered[1]);
    try expectProgress(journal, 6); // Exactly the OLD recovery tail, not live tail 11.
    try testing.expectEqual(@as(u64, 11), journal.reservationTarget());
    try testing.expect((try journal.peekChecked()) == null);
    try expectProgress(journal, 6); // New live gap at 7 is still consumer-owned.
    for (12..15) |sequence| try testing.expectEqual(@as(u64, sequence), try append(journal, reference));
    try testing.expectEqual(@as(usize, capacity), journal.pending());
    try testing.expectError(error.Full, journal.reserve());
    try expectProgress(journal, 6);
    new_gap.abort();
    try expectProgress(journal, 6);
    const live = (try journal.peekChecked()) orelse return error.MissingRecord;
    try expectRecord(live, 8, capacity, reference);
    try expectProgress(journal, 7);
    for (8..15) |sequence| {
        const record = (try journal.peekChecked()) orelse return error.MissingRecord;
        try expectRecord(record, sequence, capacity, reference);
        try journal.release(record);
        try expectProgress(journal, sequence);
    }
    try testing.expectEqual(@as(usize, 0), journal.pending());
    try testing.expectEqual(@as(u64, 15), try append(journal, reference));
    const record = (try journal.peekChecked()) orelse return error.MissingRecord;
    try expectRecord(record, 15, capacity, reference);
    try journal.release(record);
    try expectProgress(journal, 15);
    try testing.expectEqual(@as(u64, 0), journal.durableReclaimedTarget());
}

test "memory journal progress: ordinary release immediately updates mapped cursor without sync" {
    inline for (.{ false, true }) |with_schema| try runStorage(false, with_schema, 3, ordinaryRelease);
}

test "mmap journal progress: ordinary release immediately updates mapped cursor without sync" {
    inline for (.{ false, true }) |with_schema| try runStorage(true, with_schema, 3, ordinaryRelease);
}

test "memory journal progress: all peek paths publish leading tombstones and free producer space" {
    try runStorage(false, false, 4, leadingTombstones);
}

test "mmap journal progress: all peek paths publish leading tombstones and free producer space" {
    try runStorage(true, false, 4, leadingTombstones);
}

test "memory journal progress: late CRC and release failures retain the failed record until repair" {
    inline for (.{ false, true }) |with_schema| try runStorage(false, with_schema, 3, lateCrcDamage);
}

test "mmap journal progress: late CRC and release failures retain the failed record until repair" {
    inline for (.{ false, true }) |with_schema| try runStorage(true, with_schema, 3, lateCrcDamage);
}

test "mmap journal progress: recovered gaps stop at old tail and never confirm a new live gap" {
    inline for (.{ false, true }) |with_schema| try recoveryGap(with_schema);
}

test "memory journal progress: writtenTarget acquire publishes plain marker before observer joins" {
    if (builtin.single_threaded) return error.SkipZigTest;
    try runStorage(false, false, 1, publicationObserver);
}

test "mmap journal progress: writtenTarget acquire publishes plain marker before observer joins" {
    if (builtin.single_threaded) return error.SkipZigTest;
    try runStorage(true, false, 1, publicationObserver);
}
