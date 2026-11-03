const std = @import("std");
const kron = @import("kron");
const tool = @import("kroncat");
const testing = std.testing;

fn pathFor(tmp: *const testing.TmpDir, buffer: []u8, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, name });
}

fn journalFor(tmp: *const testing.TmpDir, buffer: []u8, capacity: usize) !*kron.Journal {
    if (@import("builtin").os.tag != .linux or @import("builtin").cpu.arch.endian() != .little or @sizeOf(usize) != 8) return error.SkipZigTest;
    return kron.Journal.create(testing.allocator, testing.io, .{ .path = try pathFor(tmp, buffer, "input.journal"), .capacity = capacity, .max_record_bytes = 2048 });
}

fn event(message: []const u8, sequence: u64) kron.Event {
    return .{ .level = .info, .scope = "query", .message = message, .fields = &.{}, .timestamp_ns = 10, .sequence = sequence };
}

fn append(journal: *kron.Journal, value: kron.Event) !void {
    var reservation = try journal.reserve();
    errdefer reservation.abort();
    const payload = try kron.codec.encode(value, reservation.buffer());
    try reservation.commit(payload.len);
}

fn schemaJournalFor(tmp: *const testing.TmpDir, buffer: []u8, capacity: usize, maximum: usize, schema_capacity: usize, max_schema_bytes: usize) !*kron.Journal {
    if (@import("builtin").os.tag != .linux or @import("builtin").cpu.arch.endian() != .little or @sizeOf(usize) != 8) return error.SkipZigTest;
    return kron.Journal.create(testing.allocator, testing.io, .{
        .path = try pathFor(tmp, buffer, "input.journal"),
        .capacity = capacity,
        .max_record_bytes = maximum,
        .schema_capacity = schema_capacity,
        .max_schema_bytes = max_schema_bytes,
    });
}

fn appendReferenced(journal: *kron.Journal, value: kron.Event) !kron.schema.Ref {
    var fields: [kron.schema.max_fields]kron.schema.FieldSchema = undefined;
    var arguments: [kron.schema.max_arguments]kron.schema.FieldSchema = undefined;
    const reference = try journal.registerSchema(try kron.schema_codec.eventMetadata(value, &fields, &arguments));
    const definition = try journal.resolveSchema(reference);
    var reservation = try journal.reserveWithSchema(reference);
    errdefer reservation.abort();
    const payload = try kron.schema_codec.encodeReference(value, definition, reservation.buffer());
    try reservation.commit(payload.len);
    return reference;
}

fn refreshSlotCRC(journal: *kron.Journal, slot: usize) void {
    const bytes = journal.mapping.bytes[4096 + slot * journal.stride ..][0..journal.stride];
    const sequence = std.mem.readInt(u64, bytes[8..16], .little);
    const generation = std.mem.readInt(u64, bytes[16..24], .little);
    const length = std.mem.readInt(u32, bytes[24..28], .little);
    var header: [20]u8 = undefined;
    std.mem.writeInt(u64, header[0..8], sequence, .little);
    std.mem.writeInt(u64, header[8..16], generation, .little);
    std.mem.writeInt(u32, header[16..20], length, .little);
    var crc = std.hash.Crc32.init();
    crc.update(&header);
    crc.update(bytes[32..56]);
    if (journal.file_version == 3) crc.update(bytes[56..64]);
    crc.update(bytes[64..][0..length]);
    std.mem.writeInt(u32, bytes[28..32], crc.final(), .little);
}

fn compressedBlock(workspace: *kron.compression.Workspace, raw: []const u8, count: u32, destination: []u8) ![]const u8 {
    const encoded = try workspace.compress(raw, destination[kron.compression.header_size..]);
    const header = kron.compression.headerBytes(.{ .uncompressed_len = @intCast(raw.len), .compressed_len = @intCast(encoded.len), .crc32 = std.hash.Crc32.hash(raw), .record_count = count });
    @memcpy(destination[0..header.len], &header);
    return destination[0 .. header.len + encoded.len];
}

fn payloadFrame(writer: *std.Io.Writer, payload: []const u8) !void {
    const format = kron.encoder.binary.format;
    const header = format.headerBytes(.{ .payload_len = @intCast(payload.len), .crc32 = format.frameCRC(payload) });
    try writer.writeAll(&header);
    try writer.writeAll(payload);
}

test "tool arguments parse output follow recovery and repeated predicates" {
    const options = try tool.parseArguments(&.{ "--json", "--level=warn", "--where", "code == 42", "--where=name == \"hello world\"", "--follow", "--recover", "input.journal" });
    try testing.expectEqual(kron.Format.json, options.format);
    try testing.expectEqual(kron.Level.warn, options.level);
    try testing.expect(options.follow and options.recover);
    try testing.expectEqual(@as(usize, 2), options.query_count);
    try testing.expectEqualStrings("input.journal", options.path);
    try testing.expect((try tool.parseArguments(&.{"--help"})).help);
    try testing.expectEqualStrings("--file", (try tool.parseArguments(&.{ "--", "--file" })).path);
    try testing.expectError(error.MissingPath, tool.parseArguments(&.{}));
    try testing.expectError(error.MultiplePaths, tool.parseArguments(&.{ "one", "two" }));
    try testing.expectError(error.UnknownOption, tool.parseArguments(&.{ "--bogus", "file" }));
    try testing.expectError(error.MissingOptionValue, tool.parseArguments(&.{"--level"}));
    try testing.expectError(error.InvalidLevel, tool.parseArguments(&.{ "--level=nope", "file" }));
}

test "tool equality preserves typed values and supports escaped strings and bytes" {
    const entries = [_]kron.Field{
        kron.fields.kv("minimum", std.math.minInt(i128)),
        kron.fields.kv("maximum", std.math.maxInt(u128)),
        kron.fields.kv("ratio", @as(f64, 3.25)),
        kron.fields.kv("enabled", true),
        kron.fields.kv("none", null),
        kron.fields.kv("name", "42"),
        kron.fields.kv("escaped", "hi\n\xff"),
        kron.fields.kv("blob", kron.fields.bytes("\x00\xff")),
        kron.fields.kv("duration", kron.fields.durationNs(-10)),
        kron.fields.kv("timestamp", kron.fields.timestampNs(20)),
    };
    var value = event("hello", 9);
    value.fields = &entries;
    inline for (.{ "minimum == -170141183460469231731687303715884105728", "maximum == 340282366920938463463374607431768211455", "ratio == 3.25", "enabled == true", "none == null", "name == \"42\"", "escaped == \"hi\\n\\xff\"", "blob == bytes:00FF", "duration == duration_ns:-10", "timestamp == timestamp_ns:20", "scope == query", "sequence == 9" }) |expression| {
        try testing.expect((try tool.Query.parse(expression)).matches(value));
    }
    inline for (.{ "name == 42", "ratio == 3", "enabled == 1", "blob == \"00ff\"", "missing == null", "duration == timestamp_ns:-10" }) |expression| {
        try testing.expect(!(try tool.Query.parse(expression)).matches(value));
    }
    inline for (.{ "", "key=1", "==1", "key ==", "key === 1", "bad key == 1", "key == \"unterminated", "key == \"\\q\"", "key == bytes:0", "key == bytes:zz", "key == 340282366920938463463374607431768211456" }) |expression| {
        try testing.expectError(error.InvalidWhere, tool.Query.parse(expression));
    }
    try testing.expect((try tool.Query.parse("number == 0xfee")).matchesValue(.{ .unsigned = 0xfee }));
}

test "read-only reader crosses reservation gaps under the writer lock and sees late commits" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try journalFor(&tmp, &path_buffer, 4);
    defer journal.deinit();
    var gap = try journal.reserve();
    try append(journal, event("second", 2));
    try append(journal, event("third", 3));
    try testing.expect(journal.peek() == null);
    const before = try testing.allocator.dupe(u8, journal.mapping.bytes);
    defer testing.allocator.free(before);
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, try pathFor(&tmp, &path_buffer, "input.journal"));
    defer reader.deinit();
    try testing.expectEqual(@as(u64, 2), (try reader.next()).?.sequence);
    try testing.expectEqual(@as(u64, 3), (try reader.next()).?.sequence);
    try testing.expect(try reader.next() == null);
    try testing.expectEqualSlices(u8, before, journal.mapping.bytes);
    const first = try kron.codec.encode(event("first", 1), gap.buffer());
    try gap.commit(first.len);
    const late = (try reader.next()).?;
    try testing.expectEqual(@as(u64, 1), late.sequence);
    try testing.expectEqualStrings("first", late.message);
    try testing.expect(try reader.next() == null);
    try testing.expect(try reader.next() == null);
}

test "reader returned event is independent of journal slot reuse" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try journalFor(&tmp, &path_buffer, 1);
    defer journal.deinit();
    var first = event("original", 1);
    first.fields = &.{kron.fields.kv("name", "original-field")};
    try append(journal, first);
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, try pathFor(&tmp, &path_buffer, "input.journal"));
    defer reader.deinit();
    const captured = (try reader.next()).?;
    try journal.release(journal.peek().?);
    var second = event("replacement", 2);
    second.fields = &.{kron.fields.kv("name", "replacement-field")};
    try append(journal, second);
    try testing.expectEqualStrings("original", captured.message);
    try testing.expectEqualStrings("original-field", captured.fields[0].value.string);
    const replacement = (try reader.next()).?;
    try testing.expectEqualStrings("replacement", replacement.message);
    try testing.expectEqualStrings("replacement-field", replacement.fields[0].value.string);
}

test "journal damage is reported without reclaiming or repairing evidence" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try journalFor(&tmp, &path_buffer, 2);
    defer journal.deinit();
    try append(journal, event("damage", 1));
    const path = try pathFor(&tmp, &path_buffer, "input.journal");
    journal.mapping.bytes[4096 + 64] ^= 0x40;
    const damaged = try testing.allocator.dupe(u8, journal.mapping.bytes);
    defer testing.allocator.free(damaged);
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer reader.deinit();
    try testing.expectError(error.CorruptRecord, reader.next());
    try testing.expectError(error.CorruptRecord, reader.next());
    try testing.expectEqualSlices(u8, damaged, journal.mapping.bytes);
    journal.mapping.bytes[40] ^= 1;
    try testing.expectError(error.CorruptHeader, reader.next());
    try testing.expectError(error.CorruptHeader, kron.archive.Reader.open(testing.allocator, testing.io, path));
}

test "recovery reader skips checkpointed commits and keeps all journal bytes" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try journalFor(&tmp, &path_buffer, 2);
    defer journal.deinit();
    try append(journal, event("checkpointed", 1));
    try append(journal, event("pending", 2));
    const committed = try testing.allocator.dupe(u8, journal.mapping.bytes[4096..][0..journal.stride]);
    defer testing.allocator.free(committed);
    try journal.releaseAfter(journal.peek().?, .durable);
    // Reproduce a crash between the persisted checkpoint and slot invalidation.
    @memcpy(journal.mapping.bytes[4096..][0..journal.stride], committed);
    const before = try testing.allocator.dupe(u8, journal.mapping.bytes);
    defer testing.allocator.free(before);
    const path = try pathFor(&tmp, &path_buffer, "input.journal");
    const all = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer all.deinit();
    try testing.expectEqual(@as(u64, 1), (try all.next()).?.sequence);
    const recovery = try kron.archive.Reader.openOptions(testing.allocator, testing.io, path, .{ .recover_only = true });
    defer recovery.deinit();
    try testing.expectEqual(@as(u64, 2), (try recovery.next()).?.sequence);
    try testing.expect(try recovery.next() == null);
    try testing.expectEqualSlices(u8, before, journal.mapping.bytes);
    journal.mapping.bytes[4096 + 64] ^= 0x40;
    const damaged_recovery = try kron.archive.Reader.openOptions(testing.allocator, testing.io, path, .{ .recover_only = true });
    defer damaged_recovery.deinit();
    try testing.expectError(error.CorruptRecord, damaged_recovery.next());
}

test "journal reader bounds memory and validates codec payloads" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try journalFor(&tmp, &path_buffer, 2);
    defer journal.deinit();
    const path = try pathFor(&tmp, &path_buffer, "input.journal");
    try testing.expectError(error.ReaderBudgetExceeded, kron.archive.Reader.openOptions(testing.allocator, testing.io, path, .{ .max_memory_bytes = @sizeOf(kron.archive.Reader) + 8 }));
    var reservation = try journal.reserve();
    @memcpy(reservation.buffer()[0..4], "NOPE");
    try reservation.commit(4);
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer reader.deinit();
    try testing.expectError(error.InvalidMagic, reader.next());
    var short_path: [160]u8 = undefined;
    const short = try tmp.dir.createFile(testing.io, "short", .{});
    defer short.close(testing.io);
    try short.writeStreamingAll(testing.io, "KRONJNL1");
    try testing.expectError(error.TruncatedJournal, kron.archive.Reader.open(testing.allocator, testing.io, try pathFor(&tmp, &short_path, "short")));
}

test "archive frames roundtrip and tool JSON filters typed deferred events" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const file = try tmp.dir.createFile(testing.io, "events.arc", .{});
    defer file.close(testing.io);
    var buffer: [4096]u8 = undefined;
    var framing = std.Io.Writer.fixed(&buffer);
    try kron.encoder.encode(.binary, event("ignore", 1), &framing);
    var selected = event("request {d}: {s}", 2);
    selected.level = .warn;
    selected.message_template = true;
    selected.format_args = &.{ kron.fields.kv("", @as(u8, 7)), kron.fields.kv("", kron.fields.secret("hidden-message")) };
    selected.fields = &.{ kron.fields.kv("code", 42), kron.fields.kv("password", kron.fields.secret("hidden-field")) };
    try kron.encoder.encode(.binary, selected, &framing);
    try file.writeStreamingAll(testing.io, framing.buffered());
    const path = try pathFor(&tmp, &path_buffer, "events.arc");
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer reader.deinit();
    try testing.expectEqual(kron.archive.Kind.archive, reader.kind());
    try testing.expectEqual(@as(u64, 1), (try reader.next()).?.sequence);
    const second = (try reader.next()).?;
    try testing.expect(second.message_template);
    try testing.expectEqualStrings(kron.fields.redacted, second.format_args[1].value.string);
    try testing.expect(try reader.next() == null);
    const filtered = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer filtered.deinit();
    const options = try tool.parseArguments(&.{ "--json", "--level=warn", "--where=code == 42", path });
    var output: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    try testing.expectEqual(@as(usize, 1), try tool.emitAvailable(filtered, &options, &writer));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, writer.buffered(), "\n"));
    try testing.expect(std.mem.find(u8, writer.buffered(), "request 7: [REDACTED]") != null);
    try testing.expect(std.mem.find(u8, writer.buffered(), "hidden-message") == null);
    try testing.expect(std.mem.find(u8, writer.buffered(), "hidden-field") == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("request 7: [REDACTED]", parsed.value.object.get("message").?.string);
}

test "archive follow waits for a partial final frame and resumes exactly once" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const file = try tmp.dir.createFile(testing.io, "events.arc", .{});
    defer file.close(testing.io);
    var buffer: [4096]u8 = undefined;
    var framing = std.Io.Writer.fixed(&buffer);
    try kron.encoder.encode(.binary, event("first", 1), &framing);
    const first_length = framing.end;
    try kron.encoder.encode(.binary, event("second", 2), &framing);
    const partial = first_length + 12;
    try file.writePositionalAll(testing.io, framing.buffered()[0..partial], 0);
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, try pathFor(&tmp, &path_buffer, "events.arc"));
    defer reader.deinit();
    try testing.expectEqual(@as(u64, 1), (try reader.next()).?.sequence);
    try testing.expectError(error.IncompleteFrame, reader.next());
    const options = try tool.parseArguments(&.{ "--follow", "events.arc" });
    var output: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    try testing.expectEqual(@as(usize, 0), try tool.emitAvailable(reader, &options, &writer));
    try file.writePositionalAll(testing.io, framing.buffered()[partial..], partial);
    try testing.expectEqual(@as(usize, 1), try tool.emitAvailable(reader, &options, &writer));
    try testing.expect(std.mem.find(u8, writer.buffered(), "second") != null);
    try testing.expectEqual(@as(usize, 0), try tool.emitAvailable(reader, &options, &writer));
}

test "archive checksum header errors and truncated tail remain visible" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const file = try tmp.dir.createFile(testing.io, "events.arc", .{});
    defer file.close(testing.io);
    var buffer: [4096]u8 = undefined;
    var framing = std.Io.Writer.fixed(&buffer);
    try kron.encoder.encode(.binary, event("first", 1), &framing);
    const path = try pathFor(&tmp, &path_buffer, "events.arc");
    inline for (.{ @as(usize, 8), @as(usize, 20), @as(usize, 24) }, .{ error.UnsupportedVersion, error.InvalidReserved, error.CorruptRecord }) |offset, expected| {
        buffer[offset] ^= 0x40;
        try file.writePositionalAll(testing.io, framing.buffered(), 0);
        const reader = try kron.archive.Reader.open(testing.allocator, testing.io, path);
        defer reader.deinit();
        try testing.expectError(expected, reader.next());
        buffer[offset] ^= 0x40;
    }
    try file.setLength(testing.io, framing.end - 1);
    try file.writePositionalAll(testing.io, framing.buffered()[0 .. framing.end - 1], 0);
    const truncated = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer truncated.deinit();
    try testing.expectError(error.IncompleteFrame, truncated.next());
}

test "v2 schema reader independently recovers logf attributes source and secrets" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    var key = "customer".*;
    var value = "alice".*;
    const source = @src();
    const original: kron.Event = .{
        .level = .warn,
        .scope = "query.recovery",
        .message = "request {d}: {s}",
        .message_template = true,
        .format_args = &.{ kron.kv("0", @as(u64, 42)), kron.kv("1", kron.secret("hidden-format")) },
        .fields = &.{ kron.kv(&key, &value), kron.kv("status", 200), kron.kv("password", kron.secret("hidden-password")), kron.kv("blob", kron.bytes("\xff\x00")) },
        .timestamp_ns = -10,
        .session = 123,
        .sequence = 1,
        .channel = 7,
        .route_mask = 3,
        .route_fingerprint = 99,
        .config_generation = 5,
        .trace_id = @splat(0xaa),
        .span_id = @splat(0xbb),
        .trace_flags = 1,
        .source = source,
    };
    const before = blk: {
        const journal = try schemaJournalFor(&tmp, &path_buffer, 4, 2048, 4, 2048);
        defer journal.deinit();
        _ = try appendReferenced(journal, original);
        const copied = try testing.allocator.dupe(u8, journal.mapping.bytes);
        try testing.expect(std.mem.find(u8, copied, "hidden-format") == null);
        try testing.expect(std.mem.find(u8, copied, "hidden-password") == null);
        break :blk copied;
    };
    defer testing.allocator.free(before);
    @memset(&key, 'x');
    @memset(&value, 'x');
    const path = try pathFor(&tmp, &path_buffer, "input.journal");
    const reader = try kron.archive.Reader.openOptions(testing.allocator, testing.io, path, .{ .recover_only = true });
    defer reader.deinit();
    try testing.expectEqual(kron.archive.Kind.journal, reader.kind());
    const recovered = (try reader.next()).?;
    try testing.expectEqualStrings("query.recovery", recovered.scope);
    try testing.expectEqualStrings(original.message, recovered.message);
    try testing.expect(recovered.message_template);
    try testing.expectEqualStrings("customer", recovered.fields[0].key);
    try testing.expectEqualStrings("alice", recovered.fields[0].value.string);
    try testing.expectEqualStrings(kron.fields.redacted, recovered.fields[2].value.string);
    try testing.expectEqualStrings("\xff\x00", recovered.fields[3].value.bytes);
    try testing.expectEqual(@as(u128, 42), recovered.format_args[0].value.unsigned);
    try testing.expectEqualStrings(kron.fields.redacted, recovered.format_args[1].value.string);
    try testing.expectEqual(original.route_fingerprint, recovered.route_fingerprint);
    try testing.expectEqual(original.trace_id, recovered.trace_id);
    try testing.expectEqual(original.span_id, recovered.span_id);
    try testing.expectEqual(original.trace_flags, recovered.trace_flags);
    try testing.expectEqualStrings(source.file, recovered.source.?.file);
    try testing.expectEqualStrings(source.module, recovered.source.?.module);
    try testing.expectEqualStrings(source.fn_name, recovered.source.?.fn_name);
    try testing.expectEqual(source.line, recovered.source.?.line);
    try testing.expectEqual(source.column, recovered.source.?.column);
    var output: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    try kron.encoder.encode(.json, recovered, &writer);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("request 42: [REDACTED]", parsed.value.object.get("message").?.string);
    try testing.expectEqual(@as(usize, 4), parsed.value.object.get("attributes").?.object.count());
    try testing.expect(try reader.next() == null);
    const file = try tmp.dir.openFile(testing.io, "input.journal", .{});
    defer file.close(testing.io);
    const after = try testing.allocator.alloc(u8, before.len);
    defer testing.allocator.free(after);
    try testing.expectEqual(before.len, try file.readPositionalAll(testing.io, after, 0));
    try testing.expectEqualSlices(u8, before, after);
}

test "v2 reader follows newly committed schema and inline events without registry ready state" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try schemaJournalFor(&tmp, &path_buffer, 4, 2048, 4, 2048);
    defer journal.deinit();
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, try pathFor(&tmp, &path_buffer, "input.journal"));
    defer reader.deinit();
    try testing.expect(try reader.next() == null);
    var first = event("{d}", 1);
    first.message_template = true;
    first.format_args = &.{kron.kv("0", @as(u64, 10))};
    _ = try appendReferenced(journal, first);
    const first_event = (try reader.next()).?;
    try testing.expectEqual(@as(u128, 10), first_event.format_args[0].value.unsigned);
    try testing.expect(try reader.next() == null);
    // A second definition commits after reader initialization and its first
    // scan. The live reader discovers it without rebuilding any Registry.
    var second = event("dynamic", 2);
    second.scope = "new.scope";
    second.fields = &.{kron.kv("new-key", "new-value")};
    _ = try appendReferenced(journal, second);
    const recovered = (try reader.next()).?;
    try testing.expectEqualStrings("new.scope", recovered.scope);
    try testing.expectEqualStrings("dynamic", recovered.message);
    try testing.expectEqualStrings("new-key", recovered.fields[0].key);
    try testing.expectEqualStrings("new-value", recovered.fields[0].value.string);
    try append(journal, event("legacy-inline", 3));
    const inline_event = (try reader.next()).?;
    try testing.expectEqualStrings("legacy-inline", inline_event.message);
    try testing.expectEqual(@as(u64, 3), inline_event.sequence);
    try testing.expect(try reader.next() == null);
}

test "v2 schema reader retains missing corrupt unknown and mismatched references for retry" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try schemaJournalFor(&tmp, &path_buffer, 2, 2048, 2, 2048);
    defer journal.deinit();
    const reference = try appendReferenced(journal, event("first", 1));
    const table = try kron.schema.readLayout(journal.mapping.bytes[0..4096]);
    const schema_slot = journal.mapping.bytes[table.offset..][0..table.stride];
    const original_schema = try testing.allocator.dupe(u8, schema_slot);
    defer testing.allocator.free(original_schema);
    const event_slot = journal.mapping.bytes[4096..][0..journal.stride];
    const original_slot = try testing.allocator.dupe(u8, event_slot);
    defer testing.allocator.free(original_slot);
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, try pathFor(&tmp, &path_buffer, "input.journal"));
    defer reader.deinit();
    std.mem.writeInt(u64, schema_slot[0..8], (@as(u64, reference.id) << 2) | 1, .little);
    try testing.expectError(error.MissingSchema, reader.next());
    try testing.expectError(error.MissingSchema, reader.next());
    try testing.expectEqual(@as(u64, 1), reader.last_sequence);
    @memcpy(schema_slot, original_schema);
    schema_slot[64 + 16 + 4] ^= 1;
    try testing.expectError(error.CorruptSchema, reader.next());
    try testing.expectError(error.CorruptSchema, reader.next());
    @memcpy(schema_slot, original_schema);
    std.mem.writeInt(u16, schema_slot[12..14], 99, .little);
    try testing.expectError(error.UnsupportedSchemaVersion, reader.next());
    @memcpy(schema_slot, original_schema);
    event_slot[40] ^= 1;
    // The schema reference participates in the v2 record checksum.
    try testing.expectError(error.CorruptRecord, reader.next());
    refreshSlotCRC(journal, 0);
    try testing.expectError(error.MissingSchema, reader.next());
    @memcpy(event_slot, original_slot);
    std.mem.writeInt(u16, event_slot[36..38], 99, .little);
    refreshSlotCRC(journal, 0);
    try testing.expectError(error.UnsupportedSchemaVersion, reader.next());
    @memcpy(event_slot, original_slot);
    std.mem.writeInt(u16, event_slot[38..40], 1, .little);
    refreshSlotCRC(journal, 0);
    try testing.expectError(error.InvalidSchemaReference, reader.next());
    @memcpy(event_slot, original_slot);
    std.mem.writeInt(u32, event_slot[32..36], @intCast(table.capacity + 1), .little);
    refreshSlotCRC(journal, 0);
    try testing.expectError(error.MissingSchema, reader.next());
    @memcpy(event_slot, original_slot);
    // Inline self-contained records require an entirely zero schema reference.
    std.mem.writeInt(u32, event_slot[32..36], 0, .little);
    refreshSlotCRC(journal, 0);
    try testing.expectError(error.InvalidSchemaReference, reader.next());
    @memcpy(event_slot, original_slot);
    const recovered = (try reader.next()).?;
    try testing.expectEqualStrings("first", recovered.message);
    try testing.expect(try reader.next() == null);
    try testing.expectEqualSlices(u8, original_schema, schema_slot);
    try testing.expectEqualSlices(u8, original_slot, event_slot);
}

test "v2 schema and field scratch budgets include complete table and compact scalar fields" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try schemaJournalFor(&tmp, &path_buffer, 2, 256, 4, 4096);
    defer journal.deinit();
    var entries: [64]kron.Field = undefined;
    var keys: [64][16]u8 = undefined;
    for (&entries, &keys, 0..) |*field, *key, index| field.* = kron.kv(try std.fmt.bufPrint(key, "key-{d}", .{index}), null);
    var many = event("compact", 1);
    many.fields = &entries;
    many.message = "{} " ** 64;
    many.message_template = true;
    many.format_args = &([_]kron.Field{kron.kv("", null)} ** 64);
    _ = try appendReferenced(journal, many);
    const path = try pathFor(&tmp, &path_buffer, "input.journal");
    // This budget easily covers the payload and legacy scratch, but cannot
    // cover four complete 4 KiB definitions plus the v2 field scratch.
    try testing.expectError(error.ReaderBudgetExceeded, kron.archive.Reader.openOptions(testing.allocator, testing.io, path, .{ .max_memory_bytes = 12 * 1024 }));
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer reader.deinit();
    const recovered = (try reader.next()).?;
    try testing.expectEqual(@as(usize, 64), recovered.fields.len);
    try testing.expectEqual(@as(usize, 64), recovered.format_args.len);
    for (recovered.fields, 0..) |field, index| {
        try testing.expectEqualStrings(entries[index].key, field.key);
        try testing.expect(field.value == .null_value);
    }
    for (recovered.format_args) |argument| try testing.expect(argument.value == .null_value);
}

test "v2 schema extension corruption and journal version changes are diagnosed" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try schemaJournalFor(&tmp, &path_buffer, 2, 2048, 2, 2048);
    defer journal.deinit();
    const path = try pathFor(&tmp, &path_buffer, "input.journal");
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer reader.deinit();
    journal.mapping.bytes[296] ^= 1;
    try testing.expectError(error.CorruptHeader, reader.next());
    try testing.expectError(error.CorruptSchema, kron.archive.Reader.open(testing.allocator, testing.io, path));
    journal.mapping.bytes[296] ^= 1;
    std.mem.writeInt(u16, journal.mapping.bytes[264..266], 99, .little);
    try testing.expectError(error.UnsupportedSchemaVersion, kron.archive.Reader.open(testing.allocator, testing.io, path));
    std.mem.writeInt(u16, journal.mapping.bytes[264..266], 1, .little);
    const original_version = std.mem.readInt(u32, journal.mapping.bytes[8..12], .little);
    std.mem.writeInt(u32, journal.mapping.bytes[8..12], 99, .little);
    try testing.expectError(error.UnsupportedVersion, kron.archive.Reader.open(testing.allocator, testing.io, path));
    std.mem.writeInt(u32, journal.mapping.bytes[8..12], original_version, .little);
    try testing.expect(try reader.next() == null);
}

test "reader independently recovers nested schema values and JSON after producer exit" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    var key = "child".*;
    var name = "alice".*;
    var members = [_]kron.Field{ kron.kv(&key, &name), kron.kv("password", kron.secret("hidden-nested-value")), kron.kv("bytes", kron.bytes("\x00\xff")) };
    var items = [_]kron.Value{ kron.fields.fromAny(kron.fields.group(&members)), .null_value, .{ .unsigned = 42 }, kron.fields.fromAny(kron.fields.array(&.{})) };
    var nested = event("nested", 1);
    nested.fields = &.{ kron.kv("payload", kron.fields.array(&items)), kron.kv("metadata", kron.fields.group(&members)) };
    nested.source = @src();
    nested.route_fingerprint = 99;
    nested.route_generation = 7;
    const before = blk: {
        const journal = try schemaJournalFor(&tmp, &path_buffer, 2, 4096, 2, 2048);
        defer journal.deinit();
        const reference = try appendReferenced(journal, nested);
        try testing.expectEqual(kron.schema.nested_version, reference.version);
        break :blk try testing.allocator.dupe(u8, journal.mapping.bytes);
    };
    defer testing.allocator.free(before);
    @memset(&key, 'x');
    @memset(&name, 'x');
    items[2] = .{ .boolean = false };
    const path = try pathFor(&tmp, &path_buffer, "input.journal");
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer reader.deinit();
    try testing.expectEqual(kron.codec.decode_scratch_fields, reader.scratch.len);
    const restored = (try reader.next()).?;
    const array = restored.fields[0].value.array;
    try testing.expectEqualStrings("child", array[0].group[0].key);
    try testing.expectEqualStrings("alice", array[0].group[0].value.string);
    try testing.expectEqualStrings(kron.fields.redacted, array[0].group[1].value.string);
    try testing.expectEqualStrings("\x00\xff", array[0].group[2].value.bytes);
    try testing.expect(array[1] == .null_value);
    try testing.expectEqual(@as(u128, 42), array[2].unsigned);
    try testing.expectEqual(@as(usize, 0), array[3].array.len);
    try testing.expectEqual(nested.route_generation, restored.route_generation);
    try testing.expect(!(try tool.Query.parse("payload == null")).matches(restored));
    try testing.expect(!(try tool.Query.parse("metadata == \"anything\"")).matches(restored));
    var output: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    try kron.encoder.encode(.json, restored, &writer);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    const json_items = parsed.value.object.get("attributes").?.object.get("payload").?.array.items;
    try testing.expectEqualStrings("alice", json_items[0].object.get("child").?.string);
    try testing.expectEqualStrings(kron.fields.redacted, json_items[0].object.get("password").?.string);
    try testing.expect(std.mem.find(u8, before, "hidden-nested-value") == null);
    const file = try tmp.dir.openFile(testing.io, "input.journal", .{});
    defer file.close(testing.io);
    const after = try testing.allocator.alloc(u8, before.len);
    defer testing.allocator.free(after);
    try testing.expectEqual(before.len, try file.readPositionalAll(testing.io, after, 0));
    try testing.expectEqualSlices(u8, before, after);
}

test "fixed reader scratch covers all 256 nested nodes without record allocations" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const journal = try schemaJournalFor(&tmp, &path_buffer, 1, 4096, 1, 1024);
    defer journal.deinit();
    var members: [kron.fields.max_value_nodes - 1]kron.Field = undefined;
    var keys: [members.len][12]u8 = undefined;
    for (&members, &keys, 0..) |*member, *key, index| member.* = kron.kv(try std.fmt.bufPrint(key, "node-{d}", .{index}), null);
    var nested = event("maximum", 1);
    nested.fields = &.{kron.kv("group", kron.fields.group(&members))};
    _ = try appendReferenced(journal, nested);
    const path = try pathFor(&tmp, &path_buffer, "input.journal");
    try testing.expectError(error.ReaderBudgetExceeded, kron.archive.Reader.openOptions(testing.allocator, testing.io, path, .{ .max_memory_bytes = 16 * 1024 }));
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const reader = try kron.archive.Reader.open(failing.allocator(), testing.io, path);
    defer reader.deinit();
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    const recovered = (try reader.next()).?;
    try testing.expectEqual(members.len, recovered.fields[0].value.group.len);
    try testing.expectEqualStrings("node-254", recovered.fields[0].value.group[254].key);
    try testing.expect(recovered.fields[0].value.group[254].value == .null_value);
    try testing.expect(try reader.next() == null);
    try testing.expect(!failing.has_induced_failure);
}

test "plain archive preallocates nested scratch and payload for follow" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const file = try tmp.dir.createFile(testing.io, "nested.arc", .{});
    defer file.close(testing.io);
    var raw: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&raw);
    try kron.encoder.encode(.binary, event("first", 1), &writer);
    const first_size = writer.end;
    var nested = event("second", 2);
    nested.fields = &.{kron.kv("values", kron.fields.array(&.{ .null_value, .{ .unsigned = 42 }, kron.fields.fromAny(kron.fields.group(&.{kron.kv("ok", true)})) }))};
    try kron.encoder.encode(.binary, nested, &writer);
    try file.writePositionalAll(testing.io, writer.buffered()[0..first_size], 0);
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const reader = try kron.archive.Reader.openOptions(failing.allocator(), testing.io, try pathFor(&tmp, &path_buffer, "nested.arc"), .{ .max_archive_record_bytes = 4096 });
    defer reader.deinit();
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try testing.expectEqual(@as(u64, 1), (try reader.next()).?.sequence);
    try testing.expect(try reader.next() == null);
    try file.writePositionalAll(testing.io, writer.buffered()[first_size..], first_size);
    const recovered = (try reader.next()).?;
    try testing.expectEqual(@as(u128, 42), recovered.fields[0].value.array[1].unsigned);
    try testing.expect(recovered.fields[0].value.array[2].group[0].value.boolean);
    try testing.expect(!failing.has_induced_failure);
}

test "compressed archive reads multiple blocks nested values and typed queries without allocation" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const file = try tmp.dir.createFile(testing.io, "events.cmp", .{ .read = true });
    defer file.close(testing.io);
    var backing: [kron.compression.max_compressed_len * 2]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&backing);
    const sink = try kron.CompressedArchiveSink.create(testing.allocator, .{ .sink = memory.sink(), .max_raw_bytes = 4096, .max_records = 128 });
    defer sink.deinit();
    var frame: [4096]u8 = undefined;
    var frame_writer = std.Io.Writer.fixed(&frame);
    try kron.encoder.encode(.binary, event("first", 1), &frame_writer);
    try sink.writeRecord(frame_writer.buffered());
    var selected = event("nested", 2);
    selected.level = .warn;
    selected.fields = &.{ kron.kv("code", 42), kron.kv("values", kron.fields.array(&.{ .null_value, .{ .unsigned = 7 } })) };
    frame_writer.end = 0;
    try kron.encoder.encode(.binary, selected, &frame_writer);
    try sink.writeRecord(frame_writer.buffered());
    try sink.flush();
    frame_writer.end = 0;
    try kron.encoder.encode(.binary, event("third", 3), &frame_writer);
    try sink.writeRecord(frame_writer.buffered());
    try sink.flush();
    try file.writePositionalAll(testing.io, memory.written(), 0);
    const path = try pathFor(&tmp, &path_buffer, "events.cmp");
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const reader = try kron.archive.Reader.open(failing.allocator(), testing.io, path);
    defer reader.deinit();
    try testing.expectEqual(kron.archive.Kind.compressed_archive, reader.kind());
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try testing.expectEqual(@as(u64, 1), (try reader.next()).?.sequence);
    const nested = (try reader.next()).?;
    try testing.expectEqual(@as(u128, 7), nested.fields[1].value.array[1].unsigned);
    try testing.expectEqual(@as(u64, 3), (try reader.next()).?.sequence);
    try testing.expect(try reader.next() == null);
    try testing.expect(!failing.has_induced_failure);
    const filtered = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer filtered.deinit();
    const options = try tool.parseArguments(&.{ "--json", "--level=warn", "--where=code == 42", path });
    var output: [4096]u8 = undefined;
    var output_writer = std.Io.Writer.fixed(&output);
    try testing.expectEqual(@as(usize, 1), try tool.emitAvailable(filtered, &options, &output_writer));
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, output_writer.buffered(), .{});
    defer parsed.deinit();
    try testing.expectEqual(@as(i64, 7), parsed.value.object.get("attributes").?.object.get("values").?.array.items[1].integer);
    const after = try testing.allocator.alloc(u8, memory.written().len);
    defer testing.allocator.free(after);
    try testing.expectEqual(after.len, try file.readPositionalAll(testing.io, after, 0));
    try testing.expectEqualSlices(u8, memory.written(), after);
}

test "compressed follow waits for complete blocks and preserves all frame boundaries" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const file = try tmp.dir.createFile(testing.io, "follow.cmp", .{});
    defer file.close(testing.io);
    var workspace = try kron.compression.Workspace.init(testing.allocator);
    defer workspace.deinit();
    var raw: [4096]u8 = undefined;
    var raw_writer = std.Io.Writer.fixed(&raw);
    try kron.encoder.encode(.binary, event("first", 1), &raw_writer);
    var block: [16384]u8 = undefined;
    const first = try compressedBlock(&workspace, raw_writer.buffered(), 1, &block);
    try file.writePositionalAll(testing.io, first, 0);
    const first_length = first.len;
    raw_writer.end = 0;
    try kron.encoder.encode(.binary, event("second", 2), &raw_writer);
    try kron.encoder.encode(.binary, event("third", 3), &raw_writer);
    const second = try compressedBlock(&workspace, raw_writer.buffered(), 2, &block);
    try file.writePositionalAll(testing.io, second[0..12], first_length);
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, try pathFor(&tmp, &path_buffer, "follow.cmp"));
    defer reader.deinit();
    try testing.expectEqual(@as(u64, 1), (try reader.next()).?.sequence);
    try testing.expectError(error.IncompleteFrame, reader.next());
    const options = try tool.parseArguments(&.{ "--follow", "follow.cmp" });
    var output: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    try testing.expectEqual(@as(usize, 0), try tool.emitAvailable(reader, &options, &writer));
    try file.writePositionalAll(testing.io, second[12 .. second.len - 1], first_length + 12);
    try testing.expectEqual(@as(usize, 0), try tool.emitAvailable(reader, &options, &writer));
    try file.writePositionalAll(testing.io, second[second.len - 1 ..], first_length + second.len - 1);
    try testing.expectEqual(@as(usize, 2), try tool.emitAvailable(reader, &options, &writer));
    try testing.expectEqual(@as(usize, 0), try tool.emitAvailable(reader, &options, &writer));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, writer.buffered(), "\n"));
}

test "compressed headers CRC raw data count truncation and memory budgets are diagnosed" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [160]u8 = undefined;
    const file = try tmp.dir.createFile(testing.io, "bad.cmp", .{});
    defer file.close(testing.io);
    var workspace = try kron.compression.Workspace.init(testing.allocator);
    defer workspace.deinit();
    var raw: [4096]u8 = undefined;
    var raw_writer = std.Io.Writer.fixed(&raw);
    try kron.encoder.encode(.binary, event("crc", 1), &raw_writer);
    var block: [16384]u8 = undefined;
    const encoded = try compressedBlock(&workspace, raw_writer.buffered(), 1, &block);
    try file.writePositionalAll(testing.io, encoded, 0);
    const path = try pathFor(&tmp, &path_buffer, "bad.cmp");
    try testing.expectError(error.ReaderBudgetExceeded, kron.archive.Reader.openOptions(testing.allocator, testing.io, path, .{ .max_memory_bytes = 128 * 1024 }));
    const limited = try kron.archive.Reader.openOptions(testing.allocator, testing.io, path, .{ .max_uncompressed_block_bytes = 24 });
    defer limited.deinit();
    try testing.expectError(error.ArchiveBlockTooLarge, limited.next());
    const reader = try kron.archive.Reader.open(testing.allocator, testing.io, path);
    defer reader.deinit();
    block[28] ^= 1;
    try file.writePositionalAll(testing.io, encoded, 0);
    try testing.expectError(error.CorruptHeader, reader.next());
    block[28] ^= 1;
    block[20] ^= 1;
    std.mem.writeInt(u32, block[28..32], std.hash.Crc32.hash(block[0..28]), .little);
    try file.writePositionalAll(testing.io, encoded, 0);
    try testing.expectError(error.CorruptPayload, reader.next());
    block[20] ^= 1;
    std.mem.writeInt(u32, block[24..28], 2, .little);
    std.mem.writeInt(u32, block[28..32], std.hash.Crc32.hash(block[0..28]), .little);
    try file.writePositionalAll(testing.io, encoded, 0);
    try testing.expectError(error.RecordCountMismatch, reader.next());
    std.mem.writeInt(u32, block[24..28], 1, .little);
    std.mem.writeInt(u32, block[28..32], std.hash.Crc32.hash(block[0..28]), .little);
    try file.setLength(testing.io, encoded.len - 1);
    try file.writePositionalAll(testing.io, encoded[0 .. encoded.len - 1], 0);
    try testing.expectError(error.IncompleteFrame, reader.next());
    try file.writePositionalAll(testing.io, encoded[encoded.len - 1 ..], encoded.len - 1);
    try testing.expectEqual(@as(u64, 1), (try reader.next()).?.sequence);
}

test "plain and compressed readers accept historical v1 v3 and current nested frames" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const legacy = [_]u8{
        'K',  'R',  'N',  'E',  1,    0,    0,    0,    85,  0, 0, 0, 2, 6,   0, 0,
        0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 1,   0, 0, 0, 0, 0,   0, 0,
        2,    0,    0,    0,    0,    0,    0,    0,    3,   0, 0, 0, 4, 0,   0, 0,
        0,    0,    0,    0,    5,    0,    0,    0,    0,   0, 0, 0, 1, 0,   0, 0,
        0,    0,    0,    0,    1,    0,    0,    0,    'a', 1, 0, 0, 0, 'b', 1, 0,
        0,    0,    'k',  1,    1,
    };
    var raw: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&raw);
    try payloadFrame(&writer, &legacy);
    var previous = event("previous", 3);
    previous.route_fingerprint = 99;
    previous.route_generation = 8;
    var current_bytes: [1024]u8 = undefined;
    const current = try kron.codec.encode(previous, &current_bytes);
    var previous_bytes: [1024]u8 = undefined;
    var previous_writer = std.Io.Writer.fixed(&previous_bytes);
    const difference = kron.codec.header_size - kron.codec.previous_header_size;
    try kron.codec.writeHeader(previous, current.len - difference, kron.codec.previous_version, &previous_writer);
    try previous_writer.writeAll(current[kron.codec.header_size..]);
    try payloadFrame(&writer, previous_writer.buffered());
    var nested = event("current", 4);
    nested.route_generation = 9;
    nested.fields = &.{kron.kv("array", kron.fields.array(&.{.null_value}))};
    try kron.encoder.encode(.binary, nested, &writer);
    const plain = try tmp.dir.createFile(testing.io, "mixed.arc", .{});
    defer plain.close(testing.io);
    try plain.writePositionalAll(testing.io, writer.buffered(), 0);
    var workspace = try kron.compression.Workspace.init(testing.allocator);
    defer workspace.deinit();
    var encoded: [16384]u8 = undefined;
    const block = try compressedBlock(&workspace, writer.buffered(), 3, &encoded);
    const compressed = try tmp.dir.createFile(testing.io, "mixed.cmp", .{});
    defer compressed.close(testing.io);
    try compressed.writePositionalAll(testing.io, block, 0);
    inline for (.{ "mixed.arc", "mixed.cmp" }) |filename| {
        var path: [160]u8 = undefined;
        const reader = try kron.archive.Reader.openOptions(testing.allocator, testing.io, try pathFor(&tmp, &path, filename), .{ .max_archive_record_bytes = 4096 });
        defer reader.deinit();
        const first = (try reader.next()).?;
        try testing.expectEqualStrings("a", first.scope);
        try testing.expect(first.fields[0].value.boolean);
        try testing.expectEqual(@as(u64, 0), first.route_fingerprint);
        const second = (try reader.next()).?;
        try testing.expectEqualStrings("previous", second.message);
        try testing.expectEqual(@as(u64, 99), second.route_fingerprint);
        try testing.expectEqual(@as(u64, 0), second.route_generation);
        const third = (try reader.next()).?;
        try testing.expect(third.fields[0].value.array[0] == .null_value);
        try testing.expectEqual(@as(u64, 9), third.route_generation);
        try testing.expect(try reader.next() == null);
    }
}

test "empty and shared-prefix archives discover plain or compressed input without later allocation" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var raw: [1024]u8 = undefined;
    var raw_writer = std.Io.Writer.fixed(&raw);
    try kron.encoder.encode(.binary, event("arrived", 1), &raw_writer);
    var workspace = try kron.compression.Workspace.init(testing.allocator);
    defer workspace.deinit();
    var encoded: [4096]u8 = undefined;
    const block = try compressedBlock(&workspace, raw_writer.buffered(), 1, &encoded);
    inline for (.{ "plain-empty", "compressed-empty", "plain-prefix", "compressed-prefix" }, 0..) |filename, index| {
        const file = try tmp.dir.createFile(testing.io, filename, .{});
        defer file.close(testing.io);
        const input = if (index % 2 == 0) raw_writer.buffered() else block;
        const initial: usize = if (index < 2) 0 else 4;
        try file.writePositionalAll(testing.io, input[0..initial], 0);
        var path: [160]u8 = undefined;
        var failing = testing.FailingAllocator.init(testing.allocator, .{});
        const reader = try kron.archive.Reader.openOptions(failing.allocator(), testing.io, try pathFor(&tmp, &path, filename), .{ .max_archive_record_bytes = 4096 });
        defer reader.deinit();
        failing.fail_index = failing.alloc_index;
        failing.resize_fail_index = failing.resize_index;
        if (initial == 0) try testing.expect(try reader.next() == null) else try testing.expectError(error.IncompleteFrame, reader.next());
        try file.writePositionalAll(testing.io, input[initial..], initial);
        const received = (try reader.next()).?;
        try testing.expectEqualStrings("arrived", received.message);
        try testing.expectEqual(if (index % 2 == 0) kron.archive.Kind.archive else kron.archive.Kind.compressed_archive, reader.kind());
        try testing.expect(try reader.next() == null);
        try testing.expect(!failing.has_induced_failure);
    }
}
