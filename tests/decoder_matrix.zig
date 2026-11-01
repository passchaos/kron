//! Bounded deterministic mutation across the supported event/schema versions.
//! Successful decodes must remain borrowed within input/schema/caller scratch,
//! reencode byte-for-byte (after legacy header migration), and render valid JSON.
const std = @import("std");
const kron = @import("kron");

const budget = 4096;
const mutations = 2048;
const Kind = enum { inline_v1, inline_v3, inline_v4, inline_nested, reference_v2, reference_v5, reference_nested, reference_template };

const Fixture = struct {
    values: [11]kron.Value = .{
        .null_value,                                 kron.fields.fromAny(true),                                             kron.fields.fromAny(std.math.minInt(i128)),
        kron.fields.fromAny(std.math.maxInt(u128)),  kron.fields.fromAny(@as(f64, @bitCast(@as(u64, 0x7ff8000000000042)))), kron.fields.fromAny("utf8 \xc3\xa9\n\"\\"),
        kron.fields.fromAny(kron.bytes("\x00\xff")), kron.fields.fromAny(kron.durationNs(-17)),                             kron.fields.fromAny(kron.timestampNs(18)),
        .{ .array = &.{} },                          .{ .group = &.{} },
    },
    nested: [2]kron.Field = undefined,
    fields: [11]kron.Field = undefined,
    arguments: [2]kron.Field = .{ kron.kv("count", @as(u64, 42)), kron.kv("label", "original") },
    event: kron.Event = undefined,

    fn init(self: *Fixture, kind: Kind) void {
        self.* = .{};
        const names = [_][]const u8{ "none", "boolean", "signed", "unsigned", "float", "string", "bytes", "duration", "time", "array", "group" };
        for (&self.fields, names, self.values) |*field, key, value| field.* = .{ .key = key, .value = value };
        self.nested = .{ kron.kv("all", kron.array(&self.values)), kron.kv("secret", kron.secret("never captured")) };
        const nested = kind == .inline_nested or kind == .reference_nested or kind == .reference_template;
        if (nested) self.fields[0] = kron.kv("root", kron.group(&self.nested));
        const template = kind == .reference_template;
        self.event = .{
            .level = .info,
            .scope = "decoder.matrix",
            .message = if (template) "value {[count]d}: {[label]s}" else "dynamic message",
            .message_template = template,
            .format_args = if (template) &self.arguments else &.{},
            // Legacy payloads have only scalar tags. Current scalar fixtures
            // also omit the two container tags, whose coverage is in nested.
            .fields = if (nested) self.fields[0..1] else self.fields[0..9],
            .timestamp_ns = -123,
            .session = std.math.maxInt(u64),
            .sequence = 19,
            .channel = 3,
            .route_mask = 1,
            .config_generation = 7,
            .route_fingerprint = 123,
            .route_generation = 11,
            .trace_id = @splat(0xab),
            .span_id = @splat(0xcd),
            .trace_flags = 1,
            .source = @src(),
        };
    }
};

fn referenced(kind: Kind) bool {
    return @intFromEnum(kind) >= @intFromEnum(Kind.reference_v2);
}

fn wireVersion(kind: Kind) u16 {
    return switch (kind) {
        .inline_v1 => 1,
        .inline_v3 => 3,
        .inline_v4, .inline_nested => 4,
        .reference_v2 => 2,
        .reference_v5, .reference_nested, .reference_template => 5,
    };
}

fn headerBytes(version: u16) usize {
    return switch (version) {
        1 => 68,
        2, 3 => 76,
        4, 5 => 84,
        else => unreachable,
    };
}

fn migrateHeader(event: kron.Event, current: []const u8, version: u16, destination: []u8) ![]const u8 {
    const length = current.len - (kron.codec.header_size - headerBytes(version));
    var output = std.Io.Writer.fixed(destination);
    try kron.codec.writeHeader(event, length, version, &output);
    try output.writeAll(current[kron.codec.header_size..]);
    return output.buffered();
}

const Ranges = struct {
    payload: []const u8,
    schema_bytes: []const u8,
    scratch: []const kron.Field,

    fn inside(bytes: []const u8, region: []const u8) bool {
        const begin = @intFromPtr(bytes.ptr);
        const base = @intFromPtr(region.ptr);
        return begin >= base and begin - base <= region.len and bytes.len <= region.len - (begin - base);
    }

    fn borrowed(self: Ranges, bytes: []const u8) !void {
        try std.testing.expect(inside(bytes, self.payload) or inside(bytes, self.schema_bytes));
    }

    fn descriptors(self: Ranges, comptime T: type, values: []const T) !void {
        if (values.len == 0) return;
        try std.testing.expect(inside(std.mem.sliceAsBytes(values), std.mem.sliceAsBytes(self.scratch)));
    }

    fn value(self: Ranges, input: kron.Value) !void {
        switch (input) {
            .string, .bytes => |bytes| try self.borrowed(bytes),
            .array => |values| {
                try self.descriptors(kron.Value, values);
                for (values) |child| try self.value(child);
            },
            .group => |fields| {
                try self.descriptors(kron.Field, fields);
                for (fields) |field| {
                    try self.borrowed(field.key);
                    try self.value(field.value);
                }
            },
            else => {},
        }
    }

    fn event(self: Ranges, decoded: kron.Event) !void {
        try self.borrowed(decoded.scope);
        try self.borrowed(decoded.message);
        if (decoded.source) |source| {
            // Source strings have a sentinel within the retained input.
            try self.borrowed(source.module[0 .. source.module.len + 1]);
            try self.borrowed(source.file[0 .. source.file.len + 1]);
            try self.borrowed(source.fn_name[0 .. source.fn_name.len + 1]);
        }
        try self.descriptors(kron.Field, decoded.fields);
        try self.descriptors(kron.Field, decoded.format_args);
        for (decoded.fields) |field| {
            try self.borrowed(field.key);
            try self.value(field.value);
        }
        for (decoded.format_args) |field| {
            try self.borrowed(field.key);
            try self.value(field.value);
        }
    }
};

const GuardedScratch = struct {
    prefix: [64]u8 = @splat(0xa5),
    fields: [kron.codec.decode_scratch_fields]kron.Field = undefined,
    suffix: [64]u8 = @splat(0x5a),

    fn decode(self: *@This(), input: []const u8, definition: ?kron.schema.Definition, count: usize) !bool {
        // Even a failed decode must stay inside the caller's requested scratch
        // slice. Fill its unused suffix and inspect it after either result.
        const unused = std.mem.sliceAsBytes(self.fields[count..]);
        @memset(unused, 0x3c);
        const result = accepted(input, definition, self.fields[0..count]);
        try std.testing.expect(std.mem.allEqual(u8, &self.prefix, 0xa5));
        try std.testing.expect(std.mem.allEqual(u8, &self.suffix, 0x5a));
        try std.testing.expect(std.mem.allEqual(u8, unused, 0x3c));
        return result;
    }
};

fn accepted(input: []const u8, definition: ?kron.schema.Definition, scratch: []kron.Field) !bool {
    const original_hash = std.hash.Wyhash.hash(0, input);
    const schema_hash = if (definition) |schema| std.hash.Wyhash.hash(0, schema.bytes) else 0;
    const result = if (definition) |schema| kron.schema_codec.resolve(input, schema, scratch) else kron.codec.decode(input, scratch);
    try std.testing.expectEqual(original_hash, std.hash.Wyhash.hash(0, input));
    if (definition) |schema| try std.testing.expectEqual(schema_hash, std.hash.Wyhash.hash(0, schema.bytes));
    const decoded = result catch return false;
    const ranges: Ranges = .{ .payload = input, .schema_bytes = if (definition) |schema| schema.bytes else &.{}, .scratch = scratch };
    try ranges.event(decoded);
    var validator: kron.fields.ValueValidator = .{};
    try validator.fields(decoded.fields);
    try validator.arguments(decoded.format_args);
    var canonical: [budget]u8 = undefined;
    const payload = if (definition) |schema| try kron.schema_codec.encodeReference(decoded, schema, &canonical) else try kron.codec.encode(decoded, &canonical);
    const version = std.mem.readInt(u16, input[4..6], .little);
    if (version == 4 or version == 5) {
        try std.testing.expectEqualSlices(u8, input, payload);
    } else {
        // Normalize to the historical header again. Missing legacy fields
        // must have zero defaults, rather than reading beyond the old header.
        try std.testing.expectEqual(@as(u64, 0), decoded.route_generation);
        if (version == 1) try std.testing.expectEqual(@as(u64, 0), decoded.route_fingerprint);
        var historical: [budget]u8 = undefined;
        try std.testing.expectEqualSlices(u8, input, try migrateHeader(decoded, payload, version, &historical));
    }
    var json_bytes: [32 * 1024]u8 = undefined;
    var output = std.Io.Writer.fixed(&json_bytes);
    kron.encoder.encode(.json, decoded, &output) catch |err| {
        // A mutated format string can be structurally valid codec data but
        // invalid deferred formatting. The encoder must use its error boundary.
        try std.testing.expectEqual(error.WriteFailed, err);
        try std.testing.expect(decoded.message_template);
        try std.testing.expectEqual(original_hash, std.hash.Wyhash.hash(0, input));
        return true;
    };
    const json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.buffered(), .{});
    json.deinit();
    try std.testing.expectEqual(original_hash, std.hash.Wyhash.hash(0, input));
    return true;
}

test "event version matrix truncation and mutation retain bounded ownership canonical bytes and JSON" {
    var random = std.Random.DefaultPrng.init(0x6b726f6e6d617472);
    const rng = random.random();
    var fixture: Fixture = .{};
    var original: [budget]u8 = undefined;
    var current: [budget]u8 = undefined;
    var mutated: [budget]u8 = undefined;
    var scratch: GuardedScratch = .{};
    for (std.enums.values(Kind)) |kind| {
        fixture.init(kind);
        var region: [2112]u8 align(64) = @splat(0);
        var registry = try kron.schema.Registry.init(std.testing.allocator, std.testing.io, &region, try kron.schema.layout(4096, 1, 2048));
        defer registry.deinit();
        var definition: ?kron.schema.Definition = null;
        if (referenced(kind)) {
            var fields: [11]kron.schema.FieldSchema = undefined;
            var args: [2]kron.schema.FieldSchema = undefined;
            definition = try registry.resolve((try registry.register(try kron.schema_codec.eventMetadata(fixture.event, &fields, &args))).ref);
        }
        const payload = if (definition) |schema| try kron.schema_codec.encodeReference(fixture.event, schema, &current) else try kron.codec.encode(fixture.event, &current);
        const valid = try migrateHeader(fixture.event, payload, wireVersion(kind), &original);
        try std.testing.expect(try scratch.decode(valid, definition, scratch.fields.len));
        // Exercise descriptor exhaustion at every small caller capacity,
        // including capacities enough for top-level fields but not children.
        for (0..16) |count| {
            const enough = try scratch.decode(valid, definition, count);
            if (count < fixture.event.fields.len + fixture.event.format_args.len) try std.testing.expect(!enough);
        }
        for (0..valid.len) |length| try std.testing.expect(!try scratch.decode(valid[0..length], definition, scratch.fields.len));
        var successes: usize = 0;
        for (0..mutations) |iteration| {
            @memcpy(mutated[0..valid.len], valid);
            var length = valid.len;
            switch (iteration % 5) {
                0 => mutated[iteration / 5 % valid.len] ^= 0xff,
                1 => for (0..1 + iteration % 3) |_| {
                    mutated[rng.uintLessThan(usize, valid.len)] ^= rng.int(u8) | 1;
                },
                2 => {
                    const offset = rng.uintLessThan(usize, valid.len - 3);
                    std.mem.writeInt(u32, mutated[offset..][0..4], rng.int(u32), .little);
                },
                3 => length = rng.uintLessThan(usize, valid.len),
                4 => {
                    // A changed scalar byte gives the corpus successful cases
                    // too; never count the untouched original as mutation proof.
                    mutated[valid.len - 1] ^= 1;
                },
                else => unreachable,
            }
            successes += @intFromBool(try scratch.decode(mutated[0..length], definition, scratch.fields.len));
        }
        try std.testing.expect(successes > mutations / 10);
        std.debug.print("decoder matrix {s}: {d} truncations, {d} mutations, {d} valid reencodes\n", .{ @tagName(kind), valid.len, mutations, successes });
    }
}

fn refreshEntry(entry: []u8) void {
    const length = std.mem.readInt(u32, entry[16..20], .little);
    const body = entry[64..][0..length];
    var digest: [32]u8 = undefined;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(if (std.mem.readInt(u16, body[4..6], .little) == 2) "kron-schema-v2\x00" else "kron-schema-v1\x00");
    hash.update(body);
    hash.final(&digest);
    @memcpy(entry[24..40], digest[0..16]);
    var checksum = std.hash.Crc32.init();
    checksum.update(entry[8..20]);
    checksum.update(entry[24..64]);
    checksum.update(body);
    std.mem.writeInt(u32, entry[20..24], checksum.final(), .little);
}

test "schema definition mutation validates structure after refreshed checksum and hash" {
    var fixture: Fixture = .{};
    fixture.init(.reference_template);
    var original: [2112]u8 align(64) = @splat(0);
    var registry = try kron.schema.Registry.init(std.testing.allocator, std.testing.io, &original, try kron.schema.layout(4096, 1, 2048));
    defer registry.deinit();
    var fields: [11]kron.schema.FieldSchema = undefined;
    var args: [2]kron.schema.FieldSchema = undefined;
    const meta = try kron.schema_codec.eventMetadata(fixture.event, &fields, &args);
    _ = try registry.register(meta);
    const body_length = std.mem.readInt(u32, original[16..20], .little);
    const end = 64 + body_length;
    var payload_bytes: [budget]u8 = undefined;
    const definition = (try kron.schema.decodeEntry(&original, 0, 2048)).?;
    const payload = try kron.schema_codec.encodeReference(fixture.event, definition, &payload_bytes);
    var changed: [2112]u8 = undefined;
    var scratch: [kron.codec.decode_scratch_fields]kron.Field = undefined;
    for (0..end) |length| {
        const truncated = kron.schema.decodeEntry(original[0..length], 0, 2048) catch continue;
        try std.testing.expect(truncated == null);
    }
    var structural_rejections: usize = 0;
    var successes: usize = 0;
    for (64..end) |offset| {
        changed = original;
        changed[offset] ^= 0xff;
        refreshEntry(&changed);
        const decoded = kron.schema.decodeEntry(&changed, 0, 2048) catch {
            structural_rejections += 1;
            continue;
        } orelse return error.CommittedDefinitionDisappeared;
        const ranges: Ranges = .{ .payload = &.{}, .schema_bytes = decoded.bytes, .scratch = &.{} };
        try ranges.borrowed(decoded.scope);
        if (decoded.message) |message| try ranges.borrowed(message);
        var decoded_fields: [kron.schema.max_fields]kron.schema.FieldSchema = undefined;
        var field_it = decoded.fields();
        for (decoded_fields[0..decoded.field_count]) |*field| field.* = (try field_it.next()).?;
        var decoded_args: [kron.schema.max_arguments]kron.schema.FieldSchema = undefined;
        var args_it = decoded.arguments();
        for (decoded_args[0..decoded.argument_count]) |*argument| argument.* = (try args_it.next()).?;
        const rebuilt: kron.schema.EventMeta = .{ .scope = decoded.scope, .message = decoded.message, .message_template = decoded.message_template, .source = decoded.source, .fields = decoded_fields[0..decoded.field_count], .format_args = decoded_args[0..decoded.argument_count] };
        try std.testing.expectEqualSlices(u8, &decoded.ref.hash, &try kron.schema.metadataHash(rebuilt));
        try std.testing.expect(kron.schema.metadataEqual(decoded, rebuilt));
        // Decoding with changed static metadata must be safe, whether it
        // matches the event shape or rejects it as a schema mismatch.
        _ = try accepted(payload, decoded, &scratch);
        successes += 1;
    }
    try std.testing.expect(structural_rejections > 10 and successes > 10);
    std.debug.print("schema refreshed integrity matrix: {d} structural rejections, {d} valid definitions\n", .{ structural_rejections, successes });
}

test "persistent Reader exports the supported event version matrix without modifying files" {
    if (!kron.platform.memory_queue) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var parent: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const parent_length = try temporary.dir.realPath(std.testing.io, &parent);
    var fixture: Fixture = .{};
    var current: [budget]u8 = undefined;
    var historical: [budget]u8 = undefined;
    var frame: [budget + 24]u8 = undefined;
    var expected_bytes: [budget]u8 = undefined;
    var scratch: [kron.codec.decode_scratch_fields]kron.Field = undefined;
    for (std.enums.values(Kind)) |kind| {
        fixture.init(kind);
        fixture.event.sequence = 1;
        const store = try kron.Journal.createMemory(std.testing.allocator, std.testing.io, .{
            .path = "",
            .capacity = 2,
            .max_record_bytes = budget,
            .schema_capacity = if (referenced(kind)) 1 else 0,
            .max_schema_bytes = 2048,
        });
        defer store.deinit();
        var definition: ?kron.schema.Definition = null;
        var reference: ?kron.schema.Ref = null;
        if (referenced(kind)) {
            var fields: [11]kron.schema.FieldSchema = undefined;
            var args: [2]kron.schema.FieldSchema = undefined;
            reference = try store.registerSchema(try kron.schema_codec.eventMetadata(fixture.event, &fields, &args));
            definition = try store.resolveSchema(reference.?);
        }
        const payload = if (definition) |schema| try kron.schema_codec.encodeReference(fixture.event, schema, &current) else try kron.codec.encode(fixture.event, &current);
        const bytes = try migrateHeader(fixture.event, payload, wireVersion(kind), &historical);
        const expected_event = if (definition) |schema| try kron.schema_codec.resolve(bytes, schema, &scratch) else try kron.codec.decode(bytes, &scratch);
        const expected = try kron.codec.encode(expected_event, &expected_bytes);
        // The disk fixtures use real Reader I/O, independently of the in-memory
        // decode calls. Frame v1 and journal v1/v2 keep their own versions.
        const disk_bytes = if (reference) |ref| blk: {
            var reservation = try store.reserveWithSchema(ref);
            @memcpy(reservation.buffer()[0..bytes.len], bytes);
            try reservation.commit(bytes.len);
            break :blk store.mapping.bytes;
        } else blk: {
            const header = kron.encoder.binary.format.headerBytes(.{ .payload_len = @intCast(bytes.len), .crc32 = std.hash.Crc32.hash(bytes) });
            @memcpy(frame[0..24], &header);
            @memcpy(frame[24..][0..bytes.len], bytes);
            break :blk frame[0 .. 24 + bytes.len];
        };
        {
            const file = try temporary.dir.createFile(std.testing.io, @tagName(kind), .{});
            defer file.close(std.testing.io);
            try file.writeStreamingAll(std.testing.io, disk_bytes);
        }
        const path = try std.fs.path.join(std.testing.allocator, &.{ parent[0..parent_length], @tagName(kind) });
        defer std.testing.allocator.free(path);
        const digest = std.hash.Wyhash.hash(0, disk_bytes);
        for (0..2) |_| {
            const reader = try kron.archive.Reader.openOptions(std.testing.allocator, std.testing.io, path, .{
                .recover_only = true,
                .max_archive_record_bytes = budget,
                .max_memory_bytes = 128 * 1024,
            });
            defer reader.deinit();
            try std.testing.expectEqual(if (reference != null) kron.archive.Kind.journal else .archive, reader.kind());
            const restored = (try reader.next()) orelse return error.MissingMatrixEvent;
            var materialized: [budget]u8 = undefined;
            try std.testing.expectEqualSlices(u8, expected, try kron.codec.encode(restored, &materialized));
            try std.testing.expect(try reader.next() == null);
            const image = try temporary.dir.readFileAlloc(std.testing.io, @tagName(kind), std.testing.allocator, .limited(32 * 1024));
            defer std.testing.allocator.free(image);
            try std.testing.expectEqual(digest, std.hash.Wyhash.hash(0, image));
        }
    }
    std.debug.print("persistent Reader matrix: 8 file fixtures, two independent exports each, original bytes unchanged\n", .{});
}
