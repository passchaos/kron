//! Bounded randomized journal and archive round-trip checks. Seeds are
//! printed so a failing run can be reproduced with the same test runner seed.
const std = @import("std");
const kron = @import("kron");
const testing = std.testing;
const compression = kron.compression;

test "journal random commit peek release and mmap recovery" {
    if (@sizeOf(usize) != 8 or @import("builtin").cpu.arch.endian() != .little) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/fuzz.journal", .{tmp.sub_path});
    const capacity = 8;
    const max_record = 64;
    std.debug.print("journal fuzz seed=0x{x}\n", .{testing.random_seed});
    var prng = std.Random.DefaultPrng.init(testing.random_seed);
    const random = prng.random();
    var store = try kron.Journal.create(testing.allocator, testing.io, .{ .path = path, .capacity = capacity, .max_record_bytes = max_record, .recover = false });
    defer store.deinit();
    const Entry = struct { sequence: u64, len: usize, payload: [max_record]u8 };
    var model: [capacity]?Entry = .{null} ** capacity;
    var committed: usize = 0;
    var released: u64 = 0;
    var ops: usize = 0;
    while (ops < 20_000) : (ops += 1) {
        switch (random.intRangeAtMost(u8, 0, 3)) {
            0, 1 => {
                if (committed == capacity) continue;
                var reservation = store.reserve() catch |err| switch (err) {
                    error.Full => continue,
                    else => return err,
                };
                errdefer reservation.abort();
                const len = random.intRangeAtMost(usize, 0, max_record);
                var payload: [max_record]u8 = undefined;
                random.bytes(payload[0..len]);
                @memcpy(reservation.buffer()[0..len], payload[0..len]);
                try reservation.commit(len);
                const slot = (reservation.sequence - 1) % capacity;
                model[slot] = .{ .sequence = reservation.sequence, .len = len, .payload = payload };
                committed += 1;
            },
            2 => {
                const record = (try store.peekChecked()) orelse continue;
                const entry = model[record.slot] orelse return error.UnexpectedRecord;
                try testing.expectEqual(entry.sequence, record.sequence);
                try testing.expectEqual(entry.len, record.payload.len);
                try testing.expectEqualSlices(u8, entry.payload[0..entry.len], record.payload);
                try store.release(record);
                model[record.slot] = null;
                committed -= 1;
                released = record.sequence;
            },
            3 => {
                if (ops % 5000 != 0) continue;
                store.deinit();
                store = try kron.Journal.create(testing.allocator, testing.io, .{ .path = path, .capacity = capacity, .max_record_bytes = max_record, .recover = true });
                released = store.writtenTarget();
                while (try store.peekChecked()) |record| {
                    const entry = model[record.slot] orelse return error.UnexpectedRecord;
                    try testing.expectEqual(entry.sequence, record.sequence);
                    try testing.expectEqual(entry.len, record.payload.len);
                    try testing.expectEqualSlices(u8, entry.payload[0..entry.len], record.payload);
                    try store.release(record);
                    model[record.slot] = null;
                    committed -= 1;
                    released = record.sequence;
                }
            },
            else => unreachable,
        }
        try testing.expectEqual(committed, store.pending());
        try testing.expectEqual(released, store.writtenTarget());
    }
    while (try store.peekChecked()) |record| {
        try store.release(record);
        released = record.sequence;
    }
    try testing.expectEqual(@as(usize, 0), store.pending());
    try testing.expectEqual(released, store.writtenTarget());
}

fn frame(buffer: []u8, sequence: u64, message: []const u8) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    try kron.encoder.encode(.binary, .{ .level = .info, .scope = "fuzz", .message = message, .fields = &.{kron.kv("value", sequence)}, .timestamp_ns = 0, .sequence = sequence }, &writer);
    return writer.buffered();
}

fn expectFrames(raw: []const u8, first: u64, count: u32, message: []const u8) !void {
    var offset: usize = 0;
    for (0..count) |index| {
        const header = try kron.encoder.binary.format.validate(raw[offset..]);
        const length = kron.encoder.binary.format.header_size + @as(usize, header.payload_len);
        var fields: [256]kron.Field = undefined;
        const event = try kron.codec.decode(raw[offset + kron.encoder.binary.format.header_size ..][0..header.payload_len], &fields);
        try testing.expectEqual(first + index, event.sequence);
        try testing.expectEqualStrings(message, event.message);
        try testing.expectEqual(@as(u128, first + index), event.fields[0].value.unsigned);
        offset += length;
    }
    try testing.expectEqual(raw.len, offset);
}

test "compressed archive random record counts and messages roundtrip" {
    std.debug.print("archive fuzz seed=0x{x}\n", .{testing.random_seed});
    var prng = std.Random.DefaultPrng.init(testing.random_seed);
    const random = prng.random();
    for (0..8) |iteration| {
        const count = random.intRangeAtMost(usize, 1, 20);
        var message_storage: [48]u8 = undefined;
        const message_len = random.intRangeAtMost(usize, 1, message_storage.len);
        random.bytes(message_storage[0..message_len]);
        const message = message_storage[0..message_len];
        var memory = try kron.MemorySink.init(testing.allocator, 64 * 1024);
        defer memory.deinit();
        const output = try kron.CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 1024, .max_records = 2 });
        defer output.deinit();
        var bytes: [1024]u8 = undefined;
        for (1..count + 1) |sequence| try output.writeRecord(try frame(&bytes, sequence, message));
        try output.flush();
        try testing.expectEqual(@as(u64, count), output.accepted_records);
        try testing.expectEqual(@as(u64, count), output.written_records);
        var raw: [1024]u8 = undefined;
        var window: [compression.window_bytes]u8 = undefined;
        var offset: usize = 0;
        var sequence: u64 = 1;
        while (offset < memory.written().len) {
            const decoded = try compression.decodeBlock(memory.written()[offset..], &raw, &window);
            try expectFrames(decoded.raw, sequence, decoded.header.record_count, message);
            sequence += decoded.header.record_count;
            offset += decoded.consumed;
        }
        try testing.expectEqual(count + 1, sequence);
        _ = iteration;
    }
}
