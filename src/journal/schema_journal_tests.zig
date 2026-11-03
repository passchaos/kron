const std = @import("std");
const journal = @import("journal.zig");
const format = @import("format.zig");
const schema = @import("schema.zig");
const testing = std.testing;

fn optionsFor(tmp: *const testing.TmpDir, buffer: []u8) !journal.Options {
    return .{
        .path = try std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/schema.journal", .{tmp.sub_path}),
        .capacity = 4,
        .max_record_bytes = 64,
        .schema_capacity = 4,
        .max_schema_bytes = 1024,
    };
}
fn metadata(scope: []const u8) !schema.EventMeta {
    return .{
        .scope = scope,
        .message = "registered event",
    };
}
fn append(store: *journal.Journal, reference: ?schema.Ref, payload: []const u8) !void {
    var reservation = if (reference) |ref| try store.reserveWithSchema(ref) else try store.reserve();
    errdefer reservation.abort();
    @memcpy(reservation.buffer()[0..payload.len], payload);
    try reservation.commit(payload.len);
}
test "schema disabled preserves v1 file size framing and bytes" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var options = try optionsFor(&tmp, &path_buffer);
    options.schema_capacity = 0;
    options.max_schema_bytes = 0; // Ignored when the optional table is disabled.
    const store = try journal.Journal.create(testing.allocator, testing.io, options);
    defer store.deinit();
    try testing.expect(store.schema == null);
    try testing.expectEqual((try format.layout(options.capacity, options.max_record_bytes)).size, store.mappedBytes());
    try testing.expectEqual(@as(u32, 1), format.get(u32, store.mapping.bytes, 8));
    try testing.expectError(error.SchemasDisabled, store.registerSchema(try metadata("legacy")));
    try append(store, null, "legacy payload");
    const record = (try store.peekChecked()).?;
    try testing.expect(record.schema_ref == null);
    const slot = store.mapping.bytes[format.header_bytes..][0..store.stride];
    try testing.expectEqual(format.checksum(record.sequence, record.generation, record.payload), format.get(u32, slot, 28));
    try testing.expect(std.mem.allEqual(u8, slot[32..64], 0));
    try store.release(record);
}

test "v2 schema ref and ordinary self-contained records survive reopen across reserve gap" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    const ref = try first.registerSchema(try metadata("persistent.scope"));
    _ = try first.reserve();
    try append(first, ref, "schema payload");
    try append(first, null, "self-contained payload");
    const table_layout = try schema.readLayout(first.mapping.bytes[0..format.header_bytes]);
    try testing.expectEqual(format.schema_version, format.get(u32, first.mapping.bytes, 8));
    try testing.expectEqual(table_layout.size, first.mappedBytes());
    try testing.expectEqual(table_layout, first.getSchemaLayout().?);
    try testing.expectEqual(first.sessionIdentity(), table_layout.identity);
    try testing.expect(first.peek() == null);
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    try testing.expectEqual(ref, (try second.resolveSchema(ref)).ref);
    try testing.expectEqualStrings("persistent.scope", (try second.resolveSchema(ref)).scope);
    try testing.expectEqual(table_layout, second.getSchemaLayout().?);
    var records: [4]journal.Record = undefined;
    const batch = try second.peekBatchChecked(&records);
    try testing.expectEqual(@as(usize, 2), batch.len);
    try testing.expectEqual(ref, batch[0].schema_ref.?);
    try testing.expectEqualStrings("schema payload", batch[0].payload);
    try testing.expect(batch[1].schema_ref == null);
    try testing.expectEqualStrings("self-contained payload", batch[1].payload);
    for (batch) |record| try second.release(record);
    try testing.expectEqual(@as(u64, 3), second.writtenTarget());
    try testing.expectEqual(@as(usize, 0), second.pending());
}

test "v1 v2 and schema layout mismatches leave the existing journal intact" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const v2_options = try optionsFor(&tmp, &path_buffer);
    var v1_options = v2_options;
    v1_options.schema_capacity = 0;
    const first = try journal.Journal.create(testing.allocator, testing.io, v1_options);
    try append(first, null, "retained v1");
    first.deinit();
    try testing.expectError(error.LayoutMismatch, journal.Journal.create(testing.allocator, testing.io, v2_options));
    const reopened_v1 = try journal.Journal.create(testing.allocator, testing.io, v1_options);
    try testing.expectEqualStrings("retained v1", (try reopened_v1.peekChecked()).?.payload);
    reopened_v1.deinit();
    var second_path: [128]u8 = undefined;
    var second_options = v2_options;
    second_options.path = try std.fmt.bufPrint(&second_path, ".zig-cache/tmp/{s}/v2.journal", .{tmp.sub_path});
    const second = try journal.Journal.create(testing.allocator, testing.io, second_options);
    const ref = try second.registerSchema(try metadata("v2.scope"));
    try append(second, ref, "retained v2");
    second.deinit();
    var wrong_options = second_options;
    wrong_options.schema_capacity = 0;
    try testing.expectError(error.LayoutMismatch, journal.Journal.create(testing.allocator, testing.io, wrong_options));
    wrong_options = second_options;
    wrong_options.max_schema_bytes += 1;
    try testing.expectError(error.LayoutMismatch, journal.Journal.create(testing.allocator, testing.io, wrong_options));
    const reopened_v2 = try journal.Journal.create(testing.allocator, testing.io, second_options);
    defer reopened_v2.deinit();
    try testing.expectEqualStrings("retained v2", (try reopened_v2.peekChecked()).?.payload);
}

const SyncFault = struct {
    var failing = false;
    var calls: usize = 0;
    fn sync(userdata: ?*anyopaque, file: std.Io.File) std.Io.File.SyncError!void {
        calls += 1;
        if (failing) return error.InputOutput;
        return testing.io.vtable.fileSync(userdata, file);
    }
};

const PublicationFault = struct {
    threadlocal var calls: usize = 0;
    threadlocal var fail_at: usize = 0;

    fn sync(userdata: ?*anyopaque, file: std.Io.File) std.Io.File.SyncError!void {
        calls += 1;
        if (calls == fail_at) return error.InputOutput;
        return testing.io.vtable.fileSync(userdata, file);
    }
};

test "Linux file and directory publication failures reject creation and release the journal lock" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    var vtable = testing.io.vtable.*;
    vtable.fileSync = PublicationFault.sync;
    const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
    defer PublicationFault.fail_at = 0;
    for ([_]usize{ 1, 2 }) |fail_at| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buffer: [128]u8 = undefined;
        const options = try optionsFor(&tmp, &path_buffer);
        PublicationFault.calls = 0;
        PublicationFault.fail_at = fail_at;
        try testing.expectError(error.InputOutput, journal.Journal.create(testing.allocator, io, options));
        try testing.expectEqual(fail_at, PublicationFault.calls);
        // The failed owner must close/unmap everything. A fresh owner can
        // acquire the same exclusive lock and finish publication on retry.
        PublicationFault.fail_at = 0;
        const retry = try journal.Journal.create(testing.allocator, io, options);
        defer retry.deinit();
        try testing.expectEqual(@as(usize, 0), retry.pending());
        const reference = try retry.registerSchema(try metadata("retry.publish"));
        try append(retry, reference, "complete after retry");
        try testing.expectEqualStrings("complete after retry", (try retry.peekChecked()).?.payload);
    }
}

test "Linux directory sync failure after file sync keeps a schema unready until full retry" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    var vtable = testing.io.vtable.*;
    vtable.fileSync = PublicationFault.sync;
    const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
    PublicationFault.calls = 0;
    PublicationFault.fail_at = 0;
    defer PublicationFault.fail_at = 0;
    const store = try journal.Journal.create(testing.allocator, io, options);
    defer store.deinit();
    const meta = try metadata("directory.failure");
    PublicationFault.calls = 0;
    PublicationFault.fail_at = 2;
    try testing.expectError(error.InputOutput, store.registerSchema(meta));
    try testing.expectEqual(@as(usize, 2), PublicationFault.calls);
    const unready = try store.schema.?.register(meta);
    try testing.expect(unready.requires_sync);
    try testing.expectError(error.SchemaNotReady, store.reserveWithSchema(unready.ref));
    try testing.expectEqual(@as(u64, 0), store.reservationTarget());
    PublicationFault.calls = 0;
    PublicationFault.fail_at = 0;
    const ready = try store.registerSchema(meta);
    try testing.expectEqual(unready.ref, ready);
    try testing.expectEqual(@as(usize, 2), PublicationFault.calls);
    try append(store, ready, "ready after both barriers");
    try testing.expectEqualStrings("ready after both barriers", (try store.peekChecked()).?.payload);
}

test "failed cold schema sync retains definition and forbids event commit until retry" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    var vtable = testing.io.vtable.*;
    vtable.fileSync = SyncFault.sync;
    var io = testing.io;
    io.vtable = &vtable;
    SyncFault.failing = false;
    defer SyncFault.failing = false;
    const store = try journal.Journal.create(testing.allocator, io, options);
    defer store.deinit();
    const meta = try metadata("fault.scope");
    SyncFault.failing = true;
    try testing.expectError(error.InputOutput, store.registerSchema(meta));
    const incomplete = try store.schema.?.register(meta);
    try testing.expect(incomplete.requires_sync);
    try testing.expectError(error.SchemaNotReady, store.reserveWithSchema(incomplete.ref));
    try testing.expectEqual(@as(u64, 0), store.reservationTarget());
    var reservation = try store.reserve();
    reservation.schema_ref = incomplete.ref;
    try testing.expectError(error.SchemaNotReady, reservation.commit(0));
    reservation.abort();
    try testing.expect((try store.peekChecked()) == null);
    SyncFault.failing = false;
    const ready = try store.registerSchema(meta);
    try testing.expectEqual(incomplete.ref, ready);
    const sync_calls = SyncFault.calls;
    try testing.expectEqual(ready, try store.registerSchema(meta));
    try append(store, ready, "ready event");
    try testing.expectEqual(sync_calls, SyncFault.calls);
    try store.release((try store.peekChecked()).?);
}

test "failed schema sync definition can reopen and become ready after successful sync" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    var vtable = testing.io.vtable.*;
    vtable.fileSync = SyncFault.sync;
    var io = testing.io;
    io.vtable = &vtable;
    SyncFault.failing = false;
    defer SyncFault.failing = false;
    const first = try journal.Journal.create(testing.allocator, io, options);
    const meta = try metadata("retained.fault.scope");
    SyncFault.failing = true;
    try testing.expectError(error.InputOutput, first.registerSchema(meta));
    const retained = try first.schema.?.register(meta);
    first.deinit();
    SyncFault.failing = false;
    const second = try journal.Journal.create(testing.allocator, io, options);
    defer second.deinit();
    try testing.expectEqual(retained.ref, (try second.resolveSchema(retained.ref)).ref);
    try append(second, retained.ref, "recovered definition");
    try second.release((try second.peekChecked()).?);
}

test "v2 CRC covers schema ref and recovery refuses unknown references without reclaim" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    const ref = try first.registerSchema(try metadata("crc.scope"));
    try append(first, ref, "framed payload");
    const slot = first.mapping.bytes[format.header_bytes..][0..first.stride];
    slot[40] ^= 0x10;
    try testing.expectError(error.CorruptRecord, first.peekChecked());
    slot[40] ^= 0x10;
    format.put(u32, slot, 32, @intCast(options.schema_capacity + 1));
    const length = format.get(u32, slot, 24);
    format.put(u32, slot, 28, switch (first.file_version) {
        format.version => format.checksum(1, 1, slot[64..][0..length]),
        format.schema_version_v2 => format.checksumV2(1, 1, slot[32..56], slot[64..][0..length]),
        format.schema_version => format.checksumV3Slot(slot, length),
        else => unreachable,
    });
    try testing.expectError(error.MissingSchema, first.peekChecked());
    first.deinit();
    try testing.expectError(error.MissingSchema, journal.Journal.create(testing.allocator, testing.io, options));
    const Mapping = @import("../platform/mapping.zig").Mapping;
    const base = try format.layout(options.capacity, options.max_record_bytes);
    var evidence = try Mapping.open(testing.io, options.path, (try schema.layout(base.size, options.schema_capacity, options.max_schema_bytes)).size);
    defer evidence.deinit();
    try testing.expectEqual(format.tag(1, .committed), format.get(u64, evidence.bytes, format.header_bytes));
}

test "schema table corruption is rejected even when no event refers to that definition" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    const referenced = try first.registerSchema(try metadata("referenced.scope"));
    const unused = try first.registerSchema(try metadata("unused.scope"));
    try append(first, referenced, "retained event");
    const table = try schema.readLayout(first.mapping.bytes[0..format.header_bytes]);
    first.mapping.bytes[table.offset + (@as(usize, unused.id) - 1) * table.stride + 64] ^= 0x20;
    first.deinit();
    try testing.expectError(error.CorruptSchema, journal.Journal.create(testing.allocator, testing.io, options));
    const Mapping = @import("../platform/mapping.zig").Mapping;
    var evidence = try Mapping.open(testing.io, options.path, table.size);
    defer evidence.deinit();
    try testing.expectEqual(format.tag(1, .committed), format.get(u64, evidence.bytes, format.header_bytes));
}

test "missing schema definition retains committed event and unknown schema versions are rejected" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    const ref = try first.registerSchema(try metadata("missing.scope"));
    var bad_version = ref;
    bad_version.version = 99;
    try testing.expectError(error.UnsupportedSchemaVersion, first.reserveWithSchema(bad_version));
    try append(first, ref, "retained event");
    const table = first.getSchemaLayout().?;
    const definition_offset = table.offset + (@as(usize, ref.id) - 1) * table.stride;
    format.put(u64, first.mapping.bytes, definition_offset, 0);
    try testing.expectError(error.MissingSchema, first.peekChecked());
    first.deinit();
    try testing.expectError(error.MissingSchema, journal.Journal.create(testing.allocator, testing.io, options));
    const Mapping = @import("../platform/mapping.zig").Mapping;
    var evidence = try Mapping.open(testing.io, options.path, table.size);
    defer evidence.deinit();
    try testing.expectEqual(format.tag(1, .committed), format.get(u64, evidence.bytes, format.header_bytes));
}

test "registered schema metadata strings keys source and format persist independently of caller buffers" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    const first = try journal.Journal.create(testing.allocator, testing.io, options);
    var scope = "owned.scope".*;
    var message = "count={d}".*;
    var key = "answer".*;
    const ref = try first.registerSchema(.{
        .scope = &scope,
        .message = &message,
        .message_template = true,
        .source = @src(),
        .fields = &.{.{ .key = &key, .kind_mask = schema.kindMask(.unsigned) }},
        .format_args = &.{.{ .key = "0", .kind_mask = schema.kindMask(.signed) }},
    });
    @memset(&scope, 'x');
    @memset(&message, 'x');
    @memset(&key, 'x');
    try append(first, ref, "schema-owned metadata");
    first.deinit();
    const second = try journal.Journal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    const definition = try second.resolveSchema(ref);
    try testing.expectEqualStrings("owned.scope", definition.scope);
    try testing.expectEqualStrings("count={d}", definition.message.?);
    try testing.expect(definition.message_template);
    try testing.expect(definition.source != null);
    var fields = definition.fields();
    const field = (try fields.next()).?;
    try testing.expectEqualStrings("answer", field.key);
    try testing.expectEqual(schema.kindMask(.unsigned), field.kind_mask);
    var arguments = definition.arguments();
    try testing.expectEqual(schema.kindMask(.signed), (try arguments.next()).?.kind_mask);
    try second.release((try second.peekChecked()).?);
}

test "schema SPSC reserve stays exclusive and warm reserve commit has no allocations" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const SpscJournal = @import("spsc.zig").SpscJournal;
    const channel = try SpscJournal.create(failing.allocator(), testing.io, options);
    defer channel.deinit();
    const ref = try channel.journal.registerSchema(try metadata("spsc.scope"));
    const token = try channel.token();
    try testing.expectError(error.ExclusiveProducer, channel.journal.reserveWithSchema(ref));
    const allocation_count = failing.alloc_index;
    failing.fail_index = allocation_count;
    for (0..64) |_| {
        var reservation = try channel.reserveWithTokenAndSchema(token, ref);
        @memcpy(reservation.buffer()[0..4], "warm");
        try reservation.commit(4);
        const record = (try channel.journal.peekChecked()).?;
        try testing.expectEqual(ref, record.schema_ref.?);
        try channel.journal.release(record);
    }
    try testing.expectEqual(allocation_count, failing.alloc_index);
}

test "v1 and v2 journals remain readable and writable under the current source" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var v1_buffer: [128]u8 = undefined;
    var v2_buffer: [128]u8 = undefined;

    var v1_options = try optionsFor(&tmp, &v1_buffer);
    v1_options.path = try std.fmt.bufPrint(&v1_buffer, ".zig-cache/tmp/{s}/v1.journal", .{tmp.sub_path});
    v1_options.schema_capacity = 0;
    const v1_store = try journal.Journal.create(testing.allocator, testing.io, v1_options);
    try testing.expectEqual(@as(u32, 1), format.get(u32, v1_store.mapping.bytes, 8));
    try append(v1_store, null, "v1 payload");
    const v1_record = (try v1_store.peekChecked()).?;
    const v1_slot = v1_store.mapping.bytes[format.header_bytes..][0..v1_store.stride];
    try testing.expectEqual(format.checksum(v1_record.sequence, v1_record.generation, v1_record.payload), format.get(u32, v1_slot, 28));
    try testing.expect(std.mem.allEqual(u8, v1_slot[32..64], 0));
    try testing.expectEqualStrings("v1 payload", v1_record.payload);
    v1_store.deinit();
    const v1_reopen = try journal.Journal.create(testing.allocator, testing.io, v1_options);
    try testing.expectEqual(@as(u32, 1), format.get(u32, v1_reopen.mapping.bytes, 8));
    const v1_recovered = (try v1_reopen.peekChecked()).?;
    try testing.expectEqualStrings("v1 payload", v1_recovered.payload);
    try v1_reopen.release(v1_recovered);
    v1_reopen.deinit();

    var v2_options = try optionsFor(&tmp, &v2_buffer);
    v2_options.path = try std.fmt.bufPrint(&v2_buffer, ".zig-cache/tmp/{s}/v2.journal", .{tmp.sub_path});
    const seed = try journal.Journal.create(testing.allocator, testing.io, v2_options);
    const identity = seed.sessionIdentity();
    const table = seed.getSchemaLayout().?;
    format.initializeV2(seed.mapping.bytes, seed.capacity, seed.max_record_bytes, seed.stride, identity);
    schema.writeExtension(seed.mapping.bytes[0..format.header_bytes], table, identity);
    seed.deinit();
    const v2_store = try journal.Journal.create(testing.allocator, testing.io, v2_options);
    try testing.expectEqual(@as(u32, 2), format.get(u32, v2_store.mapping.bytes, 8));
    const ref = try v2_store.registerSchema(try metadata("v2.upgrade"));
    try append(v2_store, ref, "v2 payload");
    const v2_record = (try v2_store.peekChecked()).?;
    const v2_slot = v2_store.mapping.bytes[format.header_bytes..][0..v2_store.stride];
    try testing.expectEqual(format.checksumV2(v2_record.sequence, v2_record.generation, v2_slot[32..56], v2_record.payload), format.get(u32, v2_slot, 28));
    try testing.expectEqualStrings("v2 payload", v2_record.payload);
    v2_store.deinit();
    const v2_reopen = try journal.Journal.create(testing.allocator, testing.io, v2_options);
    try testing.expectEqual(@as(u32, 2), format.get(u32, v2_reopen.mapping.bytes, 8));
    const v2_recovered = (try v2_reopen.peekChecked()).?;
    try testing.expectEqualStrings("v2 payload", v2_recovered.payload);
    try v2_reopen.release(v2_recovered);
    v2_reopen.deinit();
}

test "journal written by pre-V3 binary reopens with schema and pending records" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const fixture = try std.Io.Dir.cwd().readFileAlloc(testing.io, "tests/fixtures/journal/v2-old-binary-5b1fd7c.journal", testing.allocator, .limited(16384));
    defer testing.allocator.free(fixture);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "schema.journal", .data = fixture });
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    const store = try journal.Journal.create(testing.allocator, testing.io, options);
    defer store.deinit();
    try testing.expectEqual(@as(u32, 2), format.get(u32, store.mapping.bytes, 8));
    var schema_payload: ?[]const u8 = null;
    var ordinary_payload: ?[]const u8 = null;
    while (try store.peekChecked()) |record| {
        if (record.schema_ref) |reference| {
            schema_payload = record.payload;
            const definition = try store.resolveSchema(reference);
            try testing.expectEqualStrings("old.binary.v2", definition.scope);
            try testing.expectEqualStrings("old registered event", definition.message.?);
        } else {
            ordinary_payload = record.payload;
        }
        try store.release(record);
    }
    try testing.expectEqualStrings("old binary v2 schema payload", schema_payload.?);
    try testing.expectEqualStrings("old binary v2 ordinary payload", ordinary_payload.?);
}

test "v1 journal written by pre-V3 binary reopens with pending record" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const fixture = try std.Io.Dir.cwd().readFileAlloc(testing.io, "tests/fixtures/journal/v1-old-binary-5b1fd7c.journal", testing.allocator, .limited(8192));
    defer testing.allocator.free(fixture);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "schema.journal", .data = fixture });
    var path_buffer: [128]u8 = undefined;
    var options = try optionsFor(&tmp, &path_buffer);
    options.schema_capacity = 0;
    options.max_schema_bytes = 0;
    const store = try journal.Journal.create(testing.allocator, testing.io, options);
    defer store.deinit();
    try testing.expectEqual(@as(u32, 1), format.get(u32, store.mapping.bytes, 8));
    try testing.expect(store.schema == null);
    const record = (try store.peekChecked()).?;
    try testing.expect(record.schema_ref == null);
    try testing.expectEqualStrings("old binary v1 payload", record.payload);
    try store.release(record);
    try testing.expect((try store.peekChecked()) == null);
}

test "aarch64 v1 journal written by pre-V3 binary reopens with pending record" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const fixture = try std.Io.Dir.cwd().readFileAlloc(testing.io, "tests/fixtures/journal/v1-old-binary-aarch64-5b1fd7c.journal", testing.allocator, .limited(8192));
    defer testing.allocator.free(fixture);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "schema.journal", .data = fixture });
    var path_buffer: [128]u8 = undefined;
    var options = try optionsFor(&tmp, &path_buffer);
    options.schema_capacity = 0;
    options.max_schema_bytes = 0;
    const store = try journal.Journal.create(testing.allocator, testing.io, options);
    defer store.deinit();
    try testing.expectEqual(@as(u32, 1), format.get(u32, store.mapping.bytes, 8));
    try testing.expect(store.schema == null);
    const record = (try store.peekChecked()).?;
    try testing.expect(record.schema_ref == null);
    try testing.expectEqualStrings("old binary aarch64 v1 payload", record.payload);
    try store.release(record);
    try testing.expect((try store.peekChecked()) == null);
}

test "aarch64 v2 journal written by pre-V3 binary reopens with schema and pending records" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const fixture = try std.Io.Dir.cwd().readFileAlloc(testing.io, "tests/fixtures/journal/v2-old-binary-aarch64-5b1fd7c.journal", testing.allocator, .limited(16384));
    defer testing.allocator.free(fixture);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "schema.journal", .data = fixture });
    var path_buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &path_buffer);
    const store = try journal.Journal.create(testing.allocator, testing.io, options);
    defer store.deinit();
    try testing.expectEqual(@as(u32, 2), format.get(u32, store.mapping.bytes, 8));
    var schema_payload: ?[]const u8 = null;
    var ordinary_payload: ?[]const u8 = null;
    while (try store.peekChecked()) |record| {
        if (record.schema_ref) |reference| {
            schema_payload = record.payload;
            const definition = try store.resolveSchema(reference);
            try testing.expectEqualStrings("old.binary.v2", definition.scope);
            try testing.expectEqualStrings("old registered event", definition.message.?);
        } else {
            ordinary_payload = record.payload;
        }
        try store.release(record);
    }
    try testing.expectEqualStrings("old binary aarch64 v2 schema payload", schema_payload.?);
    try testing.expectEqualStrings("old binary aarch64 v2 ordinary payload", ordinary_payload.?);
}
