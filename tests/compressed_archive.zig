const std = @import("std");
const kron = @import("kron");
const compression = kron.compression;
const CompressedArchiveSink = kron.CompressedArchiveSink;
const testing = std.testing;

fn frame(buffer: []u8, sequence: u64, message: []const u8) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    try kron.encoder.encode(.binary, .{ .level = .info, .scope = "compressed", .message = message, .fields = &.{kron.kv("value", sequence)}, .timestamp_ns = 0, .sequence = sequence }, &writer);
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

test "compressed archive independent zlib blocks roundtrip complete readable frames" {
    var memory = try kron.MemorySink.init(testing.allocator, 64 * 1024);
    defer memory.deinit();
    const output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 1024, .max_records = 2 });
    defer output.deinit();
    var bytes: [1024]u8 = undefined;
    for (1..6) |sequence| try output.writeRecord(try frame(&bytes, sequence, "repeated event message"));
    try output.flush();
    try testing.expectEqual(@as(u64, 5), output.accepted_records);
    try testing.expectEqual(@as(u64, 5), output.written_records);
    try testing.expectEqual(@as(u64, 3), output.written_blocks);
    var raw: [1024]u8 = undefined;
    var window: [compression.window_bytes]u8 = undefined;
    var offset: usize = 0;
    var sequence: u64 = 1;
    while (offset < memory.written().len) {
        const decoded = try compression.decodeBlock(memory.written()[offset..], &raw, &window);
        try expectFrames(decoded.raw, sequence, decoded.header.record_count, "repeated event message");
        sequence += decoded.header.record_count;
        offset += decoded.consumed;
    }
    try testing.expectEqual(@as(u64, 6), sequence);
    try testing.expectError(error.UnsupportedDurability, output.sink().sync());
}

test "compressed archive rejects malformed frames oversize and impossible budgets" {
    var storage: [4096]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&storage);
    try testing.expectError(error.InvalidBufferBudget, CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 65537 }));
    try testing.expectError(error.InvalidBufferBudget, CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_records = 0 }));
    try testing.expectError(error.InvalidBufferBudget, CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 1024, .max_records = 2, .max_compressed_bytes = 100 }));
    const output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 160, .max_records = 2 });
    defer output.deinit();
    var bytes: [2048]u8 = undefined;
    const valid = try frame(&bytes, 1, "hello");
    try testing.expectError(error.InvalidFrame, output.writeRecord(valid[0 .. valid.len - 1]));
    bytes[valid.len - 1] ^= 1;
    try testing.expectError(error.CorruptFrame, output.writeRecord(valid));
    const large = [_]u8{'x'} ** 1024;
    try testing.expectError(error.RecordTooLarge, output.writeRecord(try frame(&bytes, 2, &large)));
    try testing.expectEqual(@as(u64, 0), output.accepted_records);
    try testing.expectEqual(@as(usize, 0), output.raw_len);
}

fn patchHeader(bytes: []u8, header: compression.Header) void {
    const encoded = compression.headerBytes(header);
    @memcpy(bytes[0..compression.header_size], &encoded);
}

test "compressed archive headers payload CRC bounds truncation and frame counts are checked" {
    var memory = try kron.MemorySink.init(testing.allocator, 4096);
    defer memory.deinit();
    const output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 1024, .max_records = 2 });
    defer output.deinit();
    var record: [1024]u8 = undefined;
    try output.writeRecord(try frame(&record, 1, "one"));
    try output.flush();
    const block = memory.written();
    const original = try compression.validate(block);
    try testing.expectError(error.InvalidBufferBudget, compression.decodeBlock(block, &.{}, &.{}));
    var copy: [4096]u8 = undefined;
    @memcpy(copy[0..block.len], block);
    copy[10] = 0xff;
    std.mem.writeInt(u32, copy[28..32], std.hash.Crc32.hash(copy[0..28]), .little);
    try testing.expectError(error.UnsupportedAlgorithm, compression.validate(copy[0..block.len]));
    @memcpy(copy[0..block.len], block);
    var raw: [1024]u8 = undefined;
    var window: [compression.window_bytes]u8 = undefined;
    for (0..block.len) |length| try testing.expectError(error.Truncated, compression.decodeBlock(block[0..length], &raw, &window));
    copy[20] ^= 1;
    try testing.expectError(error.CorruptHeader, compression.validate(copy[0..block.len]));
    var header = original;
    header.version = 2;
    patchHeader(&copy, header);
    try testing.expectError(error.UnsupportedVersion, compression.validate(copy[0..block.len]));
    header = original;
    header.flags = 1;
    patchHeader(&copy, header);
    try testing.expectError(error.InvalidFlags, compression.validate(copy[0..block.len]));
    header = original;
    header.record_count = 0;
    patchHeader(&copy, header);
    try testing.expectError(error.InvalidLength, compression.validate(copy[0..block.len]));
    header = original;
    header.crc32 ^= 1;
    patchHeader(&copy, header);
    try testing.expectError(error.CorruptPayload, compression.decodeBlock(copy[0..block.len], &raw, &window));
    header = original;
    header.record_count = 2;
    patchHeader(&copy, header);
    try testing.expectError(error.RecordCountMismatch, compression.decodeBlock(copy[0..block.len], &raw, &window));
    header = original;
    header.uncompressed_len = 65537;
    patchHeader(&copy, header);
    try testing.expectError(error.BlockTooLarge, compression.validate(copy[0..block.len]));
    header = original;
    header.uncompressed_len -= 1;
    patchHeader(&copy, header);
    try testing.expectError(error.DecompressedLengthMismatch, compression.decodeBlock(copy[0..block.len], &raw, &window));
    header = original;
    header.compressed_len += 1;
    patchHeader(&copy, header);
    copy[block.len] = 0;
    try testing.expectError(error.TrailingCompressedData, compression.decodeBlock(copy[0 .. block.len + 1], &raw, &window));
    @memcpy(copy[0..block.len], block);
    copy[compression.header_size] ^= 0xff;
    try testing.expectError(error.InvalidCompressedData, compression.decodeBlock(copy[0..block.len], &raw, &window));
}

test "compressed archive incompressible data respects the reserved budget and failed encoders can reset" {
    var workspace = try compression.Workspace.init(testing.allocator);
    defer workspace.deinit();
    const random = try testing.allocator.alloc(u8, compression.max_uncompressed_len);
    defer testing.allocator.free(random);
    var generator = std.Random.DefaultPrng.init(0x6b726f6e);
    generator.random().bytes(random);
    var too_small: [9]u8 = undefined;
    try testing.expectError(error.WriteFailed, workspace.compress(random, &too_small));
    const compressed = try testing.allocator.alloc(u8, try compression.compressedBound(random.len));
    defer testing.allocator.free(compressed);
    const encoded = try workspace.compress(random, compressed);
    try testing.expect(encoded.len <= compressed.len);
    var reader = std.Io.Reader.fixed(encoded);
    const window = try testing.allocator.alloc(u8, compression.window_bytes);
    defer testing.allocator.free(window);
    var inflater = std.compress.flate.Decompress.init(&reader, .zlib, window);
    const restored = try testing.allocator.alloc(u8, random.len);
    defer testing.allocator.free(restored);
    try inflater.reader.readSliceAll(restored);
    var extra: [1]u8 = undefined;
    try testing.expectEqual(@as(usize, 0), try inflater.reader.readSliceShort(&extra));
    try testing.expectEqualSlices(u8, random, restored);
    std.debug.print("incompressible pilot: raw={d} compressed={d} ratio={d:.4}\n", .{ random.len, encoded.len, @as(f64, @floatFromInt(encoded.len)) / @as(f64, @floatFromInt(random.len)) });
}

test "compressed archive full raw byte budget never splits a frame across blocks" {
    var memory = try kron.MemorySink.init(testing.allocator, 4096);
    defer memory.deinit();
    var bytes: [1024]u8 = undefined;
    const sample = try frame(&bytes, 1, "whole");
    const output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = sample.len * 2, .max_records = 3 });
    defer output.deinit();
    try output.writeRecord(sample);
    try output.writeRecord(try frame(&bytes, 2, "whole"));
    try testing.expectEqual(@as(usize, 0), memory.written().len);
    try output.writeRecord(try frame(&bytes, 3, "whole"));
    try testing.expectEqual(@as(u64, 2), output.written_records);
    try output.flush();
    var raw: [1024]u8 = undefined;
    var window: [compression.window_bytes]u8 = undefined;
    const first = try compression.decodeBlock(memory.written(), &raw, &window);
    try expectFrames(first.raw, 1, 2, "whole");
    const second = try compression.decodeBlock(memory.written()[first.consumed..], &raw, &window);
    try expectFrames(second.raw, 3, 1, "whole");
}

test "compressed archive forwards durable support and refuses unsupported sync before publishing" {
    const Durable = struct {
        bytes: [4096]u8 = undefined,
        len: usize = 0,
        sync_count: usize = 0,
        fail_sync: bool = true,
        fn write(context: *anyopaque, record: []const u8) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context));
            @memcpy(self.bytes[self.len..][0..record.len], record);
            self.len += record.len;
        }
        fn flush(_: *anyopaque) anyerror!void {}
        fn sync(context: *anyopaque) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.sync_count += 1;
            if (self.fail_sync) return error.InjectedSyncFailure;
        }
        fn sink(self: *@This()) kron.Sink {
            return .{ .context = self, .vtable = &.{ .writeRecord = write, .flush = flush, .sync = sync }, .supports_durable = true };
        }
    };
    var child: Durable = .{};
    const output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = child.sink(), .max_raw_bytes = 1024, .max_records = 2 });
    defer output.deinit();
    var bytes: [1024]u8 = undefined;
    try output.writeRecord(try frame(&bytes, 1, "sync"));
    try testing.expect(output.sink().supports_durable);
    try testing.expectError(error.InjectedSyncFailure, output.sync());
    try testing.expectEqual(@as(u64, 1), output.written_records);
    const written = child.len;
    child.fail_sync = false;
    try output.sync();
    try testing.expectEqual(@as(usize, 2), child.sync_count);
    try testing.expectEqual(written, child.len);
    var memory = try kron.MemorySink.init(testing.allocator, 4096);
    defer memory.deinit();
    const volatile_output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 1024, .max_records = 2 });
    defer volatile_output.deinit();
    try volatile_output.writeRecord(try frame(&bytes, 2, "unsupported"));
    try testing.expectError(error.UnsupportedDurability, volatile_output.sync());
    try testing.expectEqual(@as(usize, 0), memory.written().len);
}

test "compressed archive keeps failed blocks for retry and identifies duplicate full blocks" {
    var memory = try kron.MemorySink.init(testing.allocator, 8192);
    defer memory.deinit();
    const output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 1024, .max_records = 2 });
    defer output.deinit();
    var bytes: [1024]u8 = undefined;
    try output.writeRecord(try frame(&bytes, 7, "retry"));
    memory.fail_flush = true;
    try testing.expectError(error.InjectedFlushFailure, output.flush());
    const prefix = memory.written().len;
    try testing.expect(output.raw_len != 0 and output.encoded_len != 0);
    try testing.expectEqual(@as(u64, 0), output.written_records);
    memory.fail_flush = false;
    try output.flush();
    try testing.expectEqual(prefix * 2, memory.written().len);
    try testing.expectEqualSlices(u8, memory.written()[0..prefix], memory.written()[prefix..]);
    try testing.expectEqual(@as(u64, 1), output.written_records);
    try testing.expectEqual(@as(usize, 0), output.raw_len);
}

test "compressed archive partial underlying failures retain raw buffers for retry" {
    const Partial = struct {
        buffer: [8192]u8 = undefined,
        len: usize = 0,
        fail: bool = true,
        fn write(context: *anyopaque, record: []const u8) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context));
            const n = if (self.fail) @min(record.len, 11) else record.len;
            @memcpy(self.buffer[self.len..][0..n], record[0..n]);
            self.len += n;
            if (self.fail) return error.InjectedShortWriteFailure;
        }
        fn flush(_: *anyopaque) anyerror!void {}
        fn sync(_: *anyopaque) anyerror!void {
            return error.UnsupportedDurability;
        }
        fn sink(self: *@This()) kron.Sink {
            return .{ .context = self, .vtable = &.{ .writeRecord = write, .flush = flush, .sync = sync } };
        }
    };
    var partial: Partial = .{};
    const output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = partial.sink(), .max_raw_bytes = 1024, .max_records = 2 });
    defer output.deinit();
    var bytes: [1024]u8 = undefined;
    try output.writeRecord(try frame(&bytes, 8, "partial"));
    try testing.expectError(error.InjectedShortWriteFailure, output.flush());
    try testing.expectEqual(@as(usize, 11), partial.len);
    try testing.expect(output.raw_len != 0 and output.encoded_len != 0);
    partial.fail = false;
    try output.flush();
    var raw: [1024]u8 = undefined;
    var window: [compression.window_bytes]u8 = undefined;
    const decoded = try compression.decodeBlock(partial.buffer[11..partial.len], &raw, &window);
    try expectFrames(decoded.raw, 8, 1, "partial");
    // A corrupt partial prefix is evidence, not a complete accepted block.
    try testing.expectError(error.CorruptHeader, compression.validate(partial.buffer[0..partial.len]));
}

test "compressed archive initialization owns stable identity and hot path allocates nothing" {
    var memory = try kron.MemorySink.init(testing.allocator, 64 * 1024);
    defer memory.deinit();
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    var child = memory.sink();
    child.recovery_identity = "file:/tmp/compressed-records";
    const output = try CompressedArchiveSink.create(failing.allocator(), .{ .sink = child, .max_raw_bytes = 1024, .max_records = 2 });
    defer output.deinit();
    try testing.expectEqualStrings("kron-compressed-archive:v1:deflate-zlib:file:/tmp/compressed-records", output.sink().recovery_identity.?);
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    var bytes: [1024]u8 = undefined;
    for (0..20) |sequence| try output.writeRecord(try frame(&bytes, sequence, "hot path"));
    try output.flush();
    try testing.expect(!failing.has_induced_failure);
    try testing.expectEqual(@as(u64, 20), output.written_records);
}

test "compressed archive reports observed compression CPU time and byte ratio" {
    var memory = try kron.MemorySink.init(testing.allocator, 256 * 1024);
    defer memory.deinit();
    const output = try CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_records = 128 });
    defer output.deinit();
    var bytes: [1024]u8 = undefined;
    const message = "repeated useful event with stable metadata and structured value";
    const before = std.Io.Clock.awake.now(testing.io);
    const cpu_before = std.Io.Clock.cpu_thread.now(testing.io);
    for (0..128) |sequence| try output.writeRecord(try frame(&bytes, sequence, message));
    try output.flush();
    const cpu_ns = cpu_before.durationTo(std.Io.Clock.cpu_thread.now(testing.io)).toNanoseconds();
    const elapsed_ns = before.durationTo(std.Io.Clock.awake.now(testing.io)).toNanoseconds();
    const ratio = @as(f64, @floatFromInt(output.written_compressed_bytes)) / @as(f64, @floatFromInt(output.written_raw_bytes));
    std.debug.print("compressed archive pilot: raw={d} compressed={d} ratio={d:.4} wall_ns={d} cpu_ns={d}\n", .{ output.written_raw_bytes, output.written_compressed_bytes, ratio, elapsed_ns, cpu_ns });
    try testing.expect(output.written_compressed_bytes < output.written_raw_bytes);
    var raw: [compression.max_uncompressed_len]u8 = undefined;
    var window: [compression.window_bytes]u8 = undefined;
    const decoded = try compression.decodeBlock(memory.written(), &raw, &window);
    try expectFrames(decoded.raw, 0, 128, message);
}
