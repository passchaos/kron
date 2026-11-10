const std = @import("std");
const journal = @import("journal.zig");
const format = @import("format.zig");
const mapping = @import("../platform/mapping.zig");
const testing = std.testing;

fn pathFor(tmp: *const testing.TmpDir, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/test.journal", .{tmp.sub_path});
}

fn append(j: *journal.Journal, text: []const u8) !void {
    var reservation = try j.reserve();
    errdefer reservation.abort();
    @memcpy(reservation.buffer()[0..text.len], text);
    try reservation.commit(text.len);
}

test "shared and single reserve coordinates preserve full width generations through nonpower wraps and aborts" {
    if (@sizeOf(usize) != 8 or @import("builtin").cpu.arch.endian() != .little) return error.SkipZigTest;
    inline for (.{ journal.ProducerMode.shared, journal.ProducerMode.single }) |mode| for ([_]usize{ 1, 2, 3, 7, 255, 256, 257, 512 }) |capacity| {
        const rounds = capacity * 3 + 5;
        for ([_]u64{ 0, (@as(u64, 1) << 32) - 3, format.max_sequence - rounds }) |start| {
            const options: journal.Options = .{
                .path = "unused-memory-coordinates",
                .capacity = capacity,
                .max_record_bytes = 16,
            };
            const store = if (mode == .single)
                try journal.Journal.createMemorySingleProducer(testing.allocator, testing.io, options)
            else
                try journal.Journal.createMemory(testing.allocator, testing.io, options);
            defer store.deinit();
            const token: ?journal.SingleProducerToken = if (mode == .single) try store.singleProducerToken() else null;
            // Seed a quiescent valid ring at an advanced cursor. Each slot's
            // next turn belongs to the first future position with that index.
            format.put(u64, store.mapping.bytes, 64, start);
            format.put(u64, store.mapping.bytes, 72, start);
            store.head = start;
            if (mode == .single) {
                store.single.consumer_free_position.store(start, .release);
                store.single.consumer_written.store(start, .release);
                store.single.cached_producer_limit = start + capacity;
            }
            const initial_slot: usize = @intCast(start % capacity);
            for (store.turns, 0..) |*turn, index| {
                turn.store(start + (index + capacity - initial_slot) % capacity, .release);
            }
            var expected_slot = initial_slot;
            var expected_generation = start / capacity + 1;
            for (0..rounds) |step| {
                const sequence = start + step + 1;
                var reservation = if (token) |owner| try store.reserveSingleProducer(owner) else try store.reserve();
                errdefer if (!reservation.completed) reservation.abort();
                try testing.expectEqual(sequence, reservation.sequence);
                try testing.expectEqual(expected_slot, reservation.slot);
                const slot = store.mapping.bytes[format.header_bytes + expected_slot * store.stride ..][0..store.stride];
                try testing.expectEqual(sequence, format.get(u64, slot, 8));
                try testing.expectEqual(expected_generation, format.get(u64, slot, 16));
                if (step % 3 == 0) {
                    reservation.abort();
                    try testing.expect(try store.peekChecked() == null);
                } else {
                    std.mem.writeInt(u64, reservation.buffer()[0..8], sequence, .little);
                    try reservation.commit(8);
                    const record = (try store.peekChecked()) orelse return error.MissingRecord;
                    try testing.expectEqual(expected_generation, record.generation);
                    try testing.expectEqual(expected_slot, record.slot);
                    try testing.expectEqual(sequence, std.mem.readInt(u64, record.payload[0..8], .little));
                    try store.release(record);
                }
                try testing.expectEqual(sequence, store.writtenTarget());
                try testing.expectEqual(@as(usize, 0), store.pending());
                expected_slot += 1;
                if (expected_slot == capacity) {
                    expected_slot = 0;
                    expected_generation += 1;
                }
            }
            if (start + rounds == format.max_sequence) {
                if (token) |owner|
                    try testing.expectError(error.SequenceExhausted, store.reserveSingleProducer(owner))
                else
                    try testing.expectError(error.SequenceExhausted, store.reserve());
                try testing.expectEqual(format.max_sequence, store.writtenTarget());
            }
        }
    };
}

test "checked consumer rejects checksum valid generation corruption without releasing a captured record" {
    if (@sizeOf(usize) != 8 or @import("builtin").cpu.arch.endian() != .little) return error.SkipZigTest;
    for ([_]usize{ 1, 2, 3, 7, 255, 256, 257, 512 }) |capacity| {
        const store = try journal.Journal.createMemory(testing.allocator, testing.io, .{
            .path = "unused-memory-generation-evidence",
            .capacity = capacity,
            .max_record_bytes = 16,
        });
        defer store.deinit();
        try append(store, "evidence");
        const captured = (try store.peekChecked()) orelse return error.MissingRecord;
        const slot = store.mapping.bytes[format.header_bytes + captured.slot * store.stride ..][0..store.stride];
        const wrong_generation = captured.generation + 1;
        format.put(u64, slot, 16, wrong_generation);
        // Repair integrity independently of journal.slotChecksum: rejection
        // must come from the actual sequence/generation pair, not stale CRC.
        var header: [20]u8 = undefined;
        std.mem.writeInt(u64, header[0..8], captured.sequence, .little);
        std.mem.writeInt(u64, header[8..16], wrong_generation, .little);
        std.mem.writeInt(u32, header[16..20], @intCast(captured.payload.len), .little);
        var checksum = std.hash.Crc32.init();
        checksum.update(&header);
        checksum.update(captured.payload);
        format.put(u32, slot, 28, checksum.final());
        const damaged_hash = std.hash.Wyhash.hash(0, store.mapping.bytes);
        var records: [2]journal.Record = undefined;
        try testing.expectError(error.CorruptRecord, store.peekChecked());
        try testing.expectError(error.CorruptRecord, store.peekBatchChecked(&records));
        try testing.expectError(error.CorruptRecord, store.release(captured));
        try testing.expectEqual(@as(usize, 1), store.pending());
        try testing.expectEqual(@as(u64, 0), store.writtenTarget());
        try testing.expectEqual(damaged_hash, std.hash.Wyhash.hash(0, store.mapping.bytes));
        format.put(u64, slot, 16, captured.generation);
        format.put(u32, slot, 28, format.checksum(captured.sequence, captured.generation, captured.payload));
        try store.release(captured);
        try testing.expectEqual(@as(usize, 0), store.pending());
    }
}

test "mmap reopen replays committed payload and session without msync" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 64 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    try append(first, "self-contained event");
    const identity = first.sessionIdentity();
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    try testing.expectEqual(identity, second.sessionIdentity());
    const record = second.peek().?;
    try testing.expectEqual(@as(u64, 1), record.sequence);
    try testing.expectEqualStrings("self-contained event", record.payload);
    try second.release(record);
    try testing.expectEqual(@as(usize, 0), second.pending());
    try testing.expect(second.peek() == null);
}

test "normal consumer waits at reservation gap but recovery scans later commits" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 64 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    _ = try first.reserve();
    try append(first, "later producer");
    try append(first, "third producer");
    try testing.expect(first.peek() == null);
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    var recovered: [4]journal.Record = undefined;
    const recovered_batch = try second.peekBatchChecked(&recovered);
    try testing.expectEqual(@as(usize, 2), recovered_batch.len);
    try testing.expectEqual(@as(u64, 2), recovered_batch[0].sequence);
    try testing.expectEqual(@as(u64, 3), recovered_batch[1].sequence);
    try append(second, "fresh producer");
    // New live work remains behind the recovered batch until it is released.
    try testing.expectEqual(@as(usize, 2), second.peekBatch(&recovered).len);
    var record = second.peek().?;
    try testing.expectEqual(@as(u64, 2), record.sequence);
    try testing.expectEqualStrings("later producer", record.payload);
    try second.release(record);
    record = second.peek().?;
    try testing.expectEqual(@as(u64, 3), record.sequence);
    try second.release(record);
    record = second.peek().?;
    try testing.expectEqual(@as(u64, 4), record.sequence);
    try second.release(record);
}

test "recovery completion includes abandoned trailing reservation but excludes new live work" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 16 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    try append(first, "committed one");
    _ = try first.reserve();
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    try testing.expectEqual(@as(u64, 0), second.writtenTarget());
    try append(second, "live three");
    try second.release((try second.peekChecked()).?);
    try testing.expectEqual(@as(u64, 2), second.writtenTarget());
    try testing.expectEqual(@as(u64, 3), (try second.peekChecked()).?.sequence);
    try testing.expectEqual(@as(usize, 1), second.pending());
    try second.release((try second.peekChecked()).?);
    try testing.expectEqual(@as(u64, 3), second.writtenTarget());
}

test "recovery ignores stale high written cursor while retaining pending commits" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 3, .max_record_bytes = 16 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    try append(first, "pending one");
    try append(first, "pending two");
    format.put(u64, first.mapping.bytes, 72, 999);
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    try testing.expectEqual(@as(u64, 0), second.writtenTarget());
    try testing.expectEqual(@as(usize, 2), second.pending());
    try second.release((try second.peekChecked()).?);
    try testing.expectEqual(@as(u64, 1), second.writtenTarget());
    try testing.expectEqual(@as(u64, 2), (try second.peekChecked()).?.sequence);
    try second.release((try second.peekChecked()).?);
    try testing.expectEqual(@as(u64, 2), second.writtenTarget());
}

test "recovery without commits completes abandoned tail immediately" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 3, .max_record_bytes = 16 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    _ = try first.reserve();
    _ = try first.reserve();
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    try testing.expectEqual(@as(u64, 2), second.writtenTarget());
    try testing.expectEqual(@as(usize, 0), second.pending());
    try testing.expect(second.peek() == null);
}

test "recoveryRecordAt enumerates every remaining commit across gaps without consuming" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 6, .max_record_bytes = 64 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    _ = try first.reserve();
    try append(first, "second");
    try append(first, "third");
    _ = try first.reserve();
    try append(first, "fifth");
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    const original_head = second.head;
    const original_written = second.writtenTarget();
    const sequences = [_]u64{ 2, 3, 5 };
    const payloads = [_][]const u8{ "second", "third", "fifth" };
    for (sequences, payloads, 0..) |sequence, payload, index| {
        const record = (try second.recoveryRecordAt(index)).?;
        try testing.expectEqual(sequence, record.sequence);
        try testing.expectEqualStrings(payload, record.payload);
        try testing.expectEqual(original_head, second.head);
        try testing.expectEqual(original_written, second.writtenTarget());
        try testing.expectEqual(@as(usize, 0), second.recovery_cursor);
        try testing.expectEqual(@as(usize, 3), second.pending());
    }
    try testing.expect((try second.recoveryRecordAt(3)) == null);
    try testing.expect((try second.recoveryRecordAt(std.math.maxInt(usize))) == null);
    try second.release((try second.recoveryRecordAt(0)).?);
    try testing.expectEqual(@as(u64, 3), (try second.recoveryRecordAt(0)).?.sequence);
    try testing.expectEqual(@as(u64, 5), (try second.recoveryRecordAt(1)).?.sequence);
    try testing.expect((try second.recoveryRecordAt(2)) == null);
    while (try second.recoveryRecordAt(0)) |record| try second.release(record);
    try testing.expectEqual(@as(usize, 0), second.pending());
    try testing.expect((try second.recoveryRecordAt(0)) == null);
    try testing.expectEqual(@as(u64, 5), second.writtenTarget());
    // New live records are outside this opening's recovered enumeration.
    try append(second, "live sixth");
    try testing.expect((try second.recoveryRecordAt(0)) == null);
    try second.release((try second.peekChecked()).?);
}

test "recoveryRecordAt retains corrupt records and returns the existing checksum error" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 16 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    try append(first, "retained");
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    const original_head = second.head;
    second.mapping.bytes[format.header_bytes + format.slot_header_bytes] ^= 0x20;
    try testing.expectError(error.CorruptRecord, second.recoveryRecordAt(0));
    try testing.expectEqual(original_head, second.head);
    try testing.expectEqual(@as(usize, 0), second.recovery_cursor);
    try testing.expectEqual(@as(usize, 1), second.pending());
    try testing.expectEqual(format.tag(1, .committed), format.get(u64, second.mapping.bytes, format.header_bytes));
}

test "abort, full, oversize, wrap reuse and generation" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 8 };
    const j = try journal.Journal.create(testing.allocator, testing.io, options);
    defer j.deinit();
    var cancelled = try j.reserve();
    try testing.expectError(error.RecordTooLarge, cancelled.commit(9));
    try append(j, "one");
    try testing.expectError(error.Full, j.reserve());
    cancelled.abort();
    var record = j.peek().?;
    try testing.expectEqual(@as(u64, 2), record.sequence);
    try j.release(record);
    for (0..12) |index| {
        try append(j, "wrap");
        record = j.peek().?;
        try testing.expectEqual(@as(u64, index + 3), record.sequence);
        try testing.expectEqual(@as(u64, (index + 2) / 2 + 1), record.generation);
        try j.release(record);
        try testing.expectError(error.InvalidRecord, j.release(record));
    }
    try testing.expectEqual(@as(usize, 2), j.highWater());
    try testing.expectEqual(@as(usize, 0), j.pending());
    try testing.expectEqual(@as(u64, 14), j.reservationTarget());
}

test "lock, layout, recovery opt out, checksum corruption retain evidence" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 64 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    try testing.expectError(error.JournalLocked, journal.Journal.create(testing.allocator, testing.io, options));
    try append(first, "corrupt me");
    first.deinit();
    var no_recovery = options;
    no_recovery.recover = false;
    try testing.expectError(error.RecoveryRequired, journal.Journal.create(testing.allocator, testing.io, no_recovery));
    var wrong_layout = options;
    wrong_layout.capacity = 5;
    try testing.expectError(error.LayoutMismatch, journal.Journal.create(testing.allocator, testing.io, wrong_layout));
    // Alter a single payload byte through a separate mapping after the owner
    // releases its lock, reproducing damaged storage without Zig-layout casts.
    const Mapping = @import("../platform/mapping.zig").Mapping;
    var damaged = try Mapping.open(testing.io, options.path, (try format.layout(4, 64)).size);
    damaged.bytes[format.header_bytes + format.slot_header_bytes] ^= 0x40;
    damaged.deinit();
    try testing.expectError(error.CorruptRecord, journal.Journal.create(testing.allocator, testing.io, options));
    try testing.expectError(error.CorruptRecord, journal.Journal.create(testing.allocator, testing.io, options));
}

test "durable acknowledgement and alternating checkpoint recovery" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 64 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    try append(first, "durable output assumed by caller");
    try first.releaseAfter(first.peek().?, .durable);
    try testing.expectEqual(@as(u64, 1), first.durableReclaimedTarget());
    try append(first, "still pending");
    try first.sync();
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    const record = second.peek().?;
    try testing.expectEqual(@as(u64, 2), record.sequence);
    try testing.expectEqualStrings("still pending", record.payload);
    try second.release(record);
}

test "durable written checkpoint does not pass pending commits or regress" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 3, .max_record_bytes = 16 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    try append(first, "written");
    try append(first, "pending");
    try first.release((try first.peekChecked()).?);
    try testing.expectEqual(@as(u64, 1), first.writtenTarget());
    try first.checkpointWrittenDurable();
    try testing.expectEqual(@as(u64, 1), first.durableReclaimedTarget());
    try testing.expectEqual(@as(u64, 2), (try first.peekChecked()).?.sequence);
    try testing.expectEqual(@as(usize, 1), first.pending());
    const epoch = first.checkpoint_epoch;
    try first.checkpointWrittenDurable();
    try testing.expectEqual(epoch, first.checkpoint_epoch);
    try testing.expectEqual(@as(u64, 1), first.durableReclaimedTarget());
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    try testing.expectEqual(@as(u64, 1), second.durableReclaimedTarget());
    const record = (try second.peekChecked()).?;
    try testing.expectEqual(@as(u64, 2), record.sequence);
    try testing.expectEqualStrings("pending", record.payload);
    try second.release(record);
    try second.checkpointWrittenDurable();
    try testing.expectEqual(@as(u64, 2), second.durableReclaimedTarget());
    try testing.expectEqual(@as(usize, 0), second.pending());
}

test "invalid options, header version and checkpoint integrity" {
    try testing.expectError(error.InvalidOptions, format.layout(0, 8));
    try testing.expectError(error.InvalidOptions, format.layout(1, 0));
    try testing.expectError(error.InvalidOptions, format.layout(std.math.maxInt(usize), 64));
    var header: [format.header_bytes]u8 = undefined;
    format.initialize(&header, 2, 16, 128, [_]u8{3} ** 16);
    try format.validate(&header, 2, 16, 128);
    format.writeCheckpoint(&header, 1, 2, 7);
    try testing.expectEqual(@as(u64, 7), (try format.checkpoint(&header)).sequence);
    header[192 + 16] ^= 0x10;
    try testing.expectEqual(@as(u64, 0), (try format.checkpoint(&header)).sequence);
    header[128 + 16] ^= 0x10;
    try testing.expectError(error.CorruptCheckpoint, format.checkpoint(&header));
    header[40] ^= 0x01;
    try testing.expectError(error.CorruptHeader, format.validate(&header, 2, 16, 128));
    format.put(u32, &header, 8, 99);
    try testing.expectError(error.UnsupportedVersion, format.validate(&header, 2, 16, 128));
}

test "recovery validates generation, length and commit sequence" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 16 };
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    try append(first, "valid");
    first.deinit();
    const Mapping = @import("../platform/mapping.zig").Mapping;
    const size = (try format.layout(2, 16)).size;
    var damaged = try Mapping.open(testing.io, options.path, size);
    format.put(u64, damaged.bytes, format.header_bytes + 16, 99);
    damaged.deinit();
    try testing.expectError(error.CorruptRecord, journal.Journal.create(testing.allocator, testing.io, options));
    damaged = try Mapping.open(testing.io, options.path, size);
    format.put(u64, damaged.bytes, format.header_bytes + 16, 1);
    format.put(u32, damaged.bytes, format.header_bytes + 24, 17);
    damaged.deinit();
    try testing.expectError(error.CorruptRecord, journal.Journal.create(testing.allocator, testing.io, options));
    damaged = try Mapping.open(testing.io, options.path, size);
    format.put(u32, damaged.bytes, format.header_bytes + 24, 5);
    format.put(u64, damaged.bytes, format.header_bytes, format.tag(3, .committed));
    damaged.deinit();
    try testing.expectError(error.CorruptRecord, journal.Journal.create(testing.allocator, testing.io, options));
}

test "producer hot path uses no allocator after create" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 16 };
    const j = try journal.Journal.create(failing.allocator(), testing.io, options);
    defer j.deinit();
    const allocations = failing.alloc_index;
    failing.fail_index = allocations;
    for (0..100) |_| {
        try append(j, "no heap");
        try j.release(j.peek().?);
    }
    try testing.expectEqual(allocations, failing.alloc_index);
}

test "batch borrows records until ordered acknowledgement and stops at gaps" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 5, .max_record_bytes = 16 };
    const j = try journal.Journal.create(testing.allocator, testing.io, options);
    defer j.deinit();
    var leading_abort = try j.reserve();
    leading_abort.abort();
    try append(j, "second");
    try append(j, "third");
    var gap = try j.reserve();
    try append(j, "fifth");
    var records: [5]journal.Record = undefined;
    var batch = try j.peekBatchChecked(&records);
    try testing.expectEqual(@as(usize, 2), batch.len);
    try testing.expectEqual(@as(u64, 2), batch[0].sequence);
    try testing.expectEqual(@as(u64, 3), batch[1].sequence);
    try testing.expectEqual(@as(usize, 4), j.pending());
    try testing.expectError(error.InvalidRecord, j.release(batch[1]));
    try testing.expectEqualStrings("second", batch[0].payload);
    for (batch) |record| try j.release(record);
    try testing.expectEqual(@as(usize, 0), j.peekBatch(&records).len);
    gap.abort();
    batch = try j.peekBatchChecked(&records);
    try testing.expectEqual(@as(usize, 1), batch.len);
    try testing.expectEqual(@as(u64, 5), batch[0].sequence);
    try j.release(batch[0]);
    try testing.expectEqual(@as(usize, 0), j.pending());
}

test "batch written acknowledgement advances cursors once and rejects reordered records" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 16 };
    const j = try journal.Journal.create(testing.allocator, testing.io, options);
    defer j.deinit();
    try append(j, "one");
    try append(j, "two");
    try append(j, "three");
    var records: [4]journal.Record = undefined;
    const batch = try j.peekBatchChecked(&records);
    try testing.expectEqual(@as(usize, 3), batch.len);
    var released: usize = 0;
    try testing.expectError(error.InvalidRecord, j.releaseBatchWritten(batch[1..], &released));
    try testing.expectEqual(@as(usize, 0), released);
    try testing.expectEqual(@as(usize, 3), j.pending());
    try testing.expectEqual(@as(u64, 0), j.writtenTarget());
    try j.releaseBatchWritten(batch, &released);
    try testing.expectEqual(@as(usize, 3), released);
    try testing.expectEqual(@as(usize, 0), j.pending());
    try testing.expectEqual(@as(u64, 3), j.writtenTarget());
    try testing.expectEqual(@as(usize, 0), j.peekBatch(&records).len);
    released = 0;
    try testing.expectError(error.InvalidRecord, j.releaseBatchWritten(batch, &released));
    try testing.expectEqual(@as(usize, 0), released);
}

test "batch written acknowledgement rejects a corrupted middle slot without reclaiming" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 16 };
    const j = try journal.Journal.create(testing.allocator, testing.io, options);
    defer j.deinit();
    try append(j, "one");
    try append(j, "two");
    try append(j, "three");
    var records: [4]journal.Record = undefined;
    const batch = try j.peekBatchChecked(&records);
    const stride = (try format.layout(4, 16)).stride;
    const slot = format.header_bytes + batch[1].slot * stride;
    const original_generation = format.get(u64, j.mapping.bytes, slot + 16);
    format.put(u64, j.mapping.bytes, slot + 16, original_generation + 1);
    var released: usize = 0;
    try testing.expectError(error.CorruptRecord, j.releaseBatchWritten(batch, &released));
    try testing.expectEqual(@as(usize, 1), released);
    try testing.expectEqual(@as(usize, 2), j.pending());
    try testing.expectEqual(@as(u64, 1), j.writtenTarget());
    format.put(u64, j.mapping.bytes, slot + 16, original_generation);
    try testing.expectEqual(@as(u64, 2), (try j.peekChecked()).?.sequence);
    try j.releaseBatchWritten(batch[1..], &released);
    try testing.expectEqual(@as(usize, 2), released);
    try testing.expectEqual(@as(usize, 0), j.pending());
    try testing.expectEqual(@as(u64, 3), j.writtenTarget());
}

test "batch written acknowledgement rejects late payload corruption after checked peek" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 16 };
    const j = try journal.Journal.create(testing.allocator, testing.io, options);
    defer j.deinit();
    try append(j, "one");
    try append(j, "two");
    try append(j, "three");
    var records: [4]journal.Record = undefined;
    const batch = try j.peekBatchChecked(&records);
    const stride = (try format.layout(4, 16)).stride;
    const slot = format.header_bytes + batch[1].slot * stride;
    j.mapping.bytes[slot + format.slot_header_bytes] ^= 1;
    var released: usize = 0;
    try testing.expectError(error.CorruptRecord, j.releaseBatchWritten(batch, &released));
    try testing.expectEqual(@as(usize, 1), released);
    try testing.expectEqual(@as(usize, 2), j.pending());
    try testing.expectEqual(@as(u64, 1), j.writtenTarget());
}

test "checked live peek retains corrupt records instead of exposing invalid length" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 16 };
    const j = try journal.Journal.create(testing.allocator, testing.io, options);
    defer j.deinit();
    try append(j, "first");
    try append(j, "second");
    const stride = (try format.layout(2, 16)).stride;
    format.put(u32, j.mapping.bytes, format.header_bytes + stride + 24, 99);
    var records: [2]journal.Record = undefined;
    try testing.expectError(error.CorruptRecord, j.peekBatchChecked(&records));
    try testing.expectEqual(@as(usize, 2), j.pending());
    try testing.expectEqual(@as(u64, 1), (try j.peekChecked()).?.sequence);
    format.put(u32, j.mapping.bytes, format.header_bytes + 24, 99);
    try testing.expectError(error.CorruptRecord, j.peekChecked());
    try testing.expectEqual(@as(usize, 2), j.pending());
}

test "parallel producers wrap without duplicates or payload damage" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options: journal.Options = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 32, .max_record_bytes = 16 };
    const j = try journal.Journal.create(testing.allocator, testing.io, options);
    defer j.deinit();
    const producer_count = 4;
    const per_producer = 400;
    const Worker = struct {
        fn run(store: *journal.Journal, producer: u32) void {
            for (0..per_producer) |index| {
                var reservation = while (true) {
                    break store.reserve() catch |err| switch (err) {
                        error.Full => {
                            std.Thread.yield() catch {};
                            continue;
                        },
                        else => @panic("unexpected reserve failure"),
                    };
                };
                format.put(u32, reservation.buffer(), 0, producer);
                format.put(u32, reservation.buffer(), 4, @intCast(index));
                format.put(u64, reservation.buffer(), 8, reservation.sequence);
                reservation.commit(16) catch @panic("unexpected commit failure");
            }
        }
    };
    var threads: [producer_count]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| thread.* = try std.Thread.spawn(.{}, Worker.run, .{ j, @as(u32, @intCast(index)) });
    defer for (threads) |thread| thread.join();
    var seen = [_][per_producer]bool{[_]bool{false} ** per_producer} ** producer_count;
    var received: u64 = 0;
    while (received < producer_count * per_producer) {
        const record = j.peek() orelse {
            std.Thread.yield() catch {};
            continue;
        };
        const producer = format.get(u32, record.payload, 0);
        const index = format.get(u32, record.payload, 4);
        try testing.expect(producer < producer_count and index < per_producer);
        try testing.expect(!seen[producer][index]);
        seen[producer][index] = true;
        try testing.expectEqual(received + 1, record.sequence);
        try testing.expectEqual(record.sequence, format.get(u64, record.payload, 8));
        try j.release(record);
        received += 1;
    }
    try testing.expectEqual(@as(usize, 0), j.pending());
}
test "fresh mapped zero capability implies zero body" {
    if (!mapping.supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [192]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/fresh.journal", .{tmp.sub_path});
    var map = mapping.Mapping.open(testing.io, path, 4 * 4096) catch return error.SkipZigTest;
    defer map.deinit();
    if (!map.fresh_zeroed) return error.SkipZigTest;
    try testing.expect(std.mem.allEqual(u8, map.bytes, 0));
}

test "recoverable journals reject verify_crc false" {
    if (!mapping.supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [192]u8 = undefined;
    const path = try pathFor(&tmp, &path_buffer);
    try testing.expectError(error.CrcRequiredForRecovery, journal.Journal.create(testing.allocator, testing.io, .{
        .path = path,
        .capacity = 8,
        .max_record_bytes = 512,
        .verify_crc = false,
    }));
}
