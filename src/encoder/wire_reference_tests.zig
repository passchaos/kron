//! Differential reference rendering, including malformed wire and scratch bounds.
const std = @import("std");
const field = @import("../core/field.zig");
const Event = @import("../core/event.zig").Event;
const codec = @import("../core/codec.zig");
const reference = @import("../core/schema_codec.zig");
const schema = reference.schema;
const fused = @import("wire_json.zig");
const common = @import("common.zig");
const time = @import("../time/root.zig");

fn render(payload: []const u8, definition: schema.Definition, output: []u8, scratch: []field.Field) fused.Error![]const u8 {
    const header = try reference.readReferenceHeader(payload, definition, scratch.len);
    return fused.renderReference(.json, payload, header, definition, output, scratch, null);
}

test "fused reference matches materialized all tags nested static dynamic and historical records" {
    const scalar = [_]field.Field{
        field.kv("u\"", std.math.maxInt(u128)),                    field.kv("i", std.math.minInt(i128)),
        field.kv("bool", true),                                    field.kv("float", std.math.nan(f64)),
        field.kv("zero", @as(f64, -0.0)),
        field.kv("string", "雪\n\xff\x00"),
        field.kv("bytes", field.bytes("\x00\xff")),                field.kv("duration", field.durationNs(-5)),
        field.kv("time", field.timestampNs(std.math.maxInt(i64))), field.kv("null", null),
    };
    const nested = scalar ++ [_]field.Field{field.kv("nested", field.group(&.{field.kv("arr", field.array(&.{ .null_value, .{ .boolean = false }, .{ .string = "x\ny" } }))}))};
    for ([_][]const field.Field{ &scalar, &nested }) |entries| {
        for ([_]bool{ false, true }) |static_message| {
            const event: Event = .{ .level = .warn, .scope = "schema\"雪", .message = "dynamic\nvalue", .timestamp_ns = -1, .fields = entries, .source = @src(), .session = std.math.maxInt(u64), .sequence = 99, .channel = 3, .route_mask = 1, .route_fingerprint = 31, .route_generation = 7, .config_generation = 2, .trace_id = @splat(0xab), .span_id = @splat(0xcd), .trace_flags = 0x81 };
            var region: [4160]u8 align(64) = @splat(0);
            var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 4096));
            defer registry.deinit();
            var fields: [nested.len]schema.FieldSchema = undefined;
            var metadata = try reference.eventMetadata(event, &fields, &.{});
            if (static_message) metadata.message = event.message;
            const definition = try registry.resolve((try registry.register(metadata)).ref);
            var current: [4096]u8 = undefined;
            const payload = try reference.encodeReference(event, definition, &current);
            for ([_]u16{ reference.version, codec.legacy_reference_version }) |wire_version| {
                if (wire_version == codec.legacy_reference_version and entries.len == nested.len) continue;
                var migrated: [4096]u8 = undefined;
                var migration = std.Io.Writer.fixed(&migrated);
                const header_bytes = if (wire_version == reference.version) codec.header_size else codec.previous_header_size;
                try codec.writeHeader(event, payload.len - codec.header_size + header_bytes, wire_version, &migration);
                try migration.writeAll(payload[codec.header_size..]);
                const bytes = migration.buffered();
                var decode_scratch: [codec.decode_scratch_fields]field.Field = undefined;
                const decoded = try reference.resolve(bytes, definition, &decode_scratch);
                var scratch: [codec.decode_scratch_fields]field.Field = undefined;
                const header = try reference.readReferenceHeader(bytes, definition, scratch.len);
                inline for (std.enums.values(fused.Format)) |format| {
                    for ([_]bool{ false, true }) |readable| {
                        var formatter = try time.Formatter.init(.{ .offset = .{ .minutes = 330 } });
                        var actual: [8192]u8 = undefined;
                        const rendered = try fused.renderReference(format, bytes, header, definition, &actual, &scratch, if (readable) &formatter else null);
                        var expected_bytes: [8192]u8 = undefined;
                        var expected = std.Io.Writer.fixed(&expected_bytes);
                        const output_format: common.RecordFormat = switch (format) {
                            .json => .json,
                            .text => .text,
                            .logfmt => .logfmt,
                        };
                        try common.encodeWithTime(output_format, decoded, if (readable) &formatter else null, &expected);
                        try std.testing.expectEqualSlices(u8, expected.buffered(), rendered);
                    }
                }
            }
        }
    }
}

fn equivalent(payload: []const u8, definition: schema.Definition, capacity: usize) !bool {
    const Guarded = struct { prefix: [64]u8 = @splat(0xac), fields: [codec.decode_scratch_fields]field.Field = undefined, suffix: [64]u8 = @splat(0xbd) };
    var scratch: Guarded = .{};
    var decoded_scratch: [codec.decode_scratch_fields]field.Field = undefined;
    var actual: [8192]u8 = undefined;
    const decoded = reference.resolve(payload, definition, decoded_scratch[0..capacity]);
    const result = render(payload, definition, &actual, scratch.fields[0..capacity]);
    try std.testing.expectEqualSlices(u8, &(@as([64]u8, @splat(0xac))), &scratch.prefix);
    try std.testing.expectEqualSlices(u8, &(@as([64]u8, @splat(0xbd))), &scratch.suffix);
    if (decoded) |event| {
        var expected_bytes: [8192]u8 = undefined;
        var expected = std.Io.Writer.fixed(&expected_bytes);
        try common.encodeWithTime(.json, event, null, &expected);
        try std.testing.expectEqualSlices(u8, expected.buffered(), try result);
        return true;
    } else |err| {
        try std.testing.expectError(err, result);
        return false;
    }
}

test "fused reference has identical checked errors on truncation mutation type mismatch and scratch exhaustion" {
    var rng = std.Random.DefaultPrng.init(0x736368656d616675);
    var region: [4160]u8 align(64) = @splat(0);
    var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 4096));
    defer registry.deinit();
    const event: Event = .{ .level = .info, .scope = "matrix", .message = "dynamic", .timestamp_ns = 0, .source = @src(), .trace_id = @splat(1), .span_id = @splat(2), .fields = &.{ field.kv("n", null), field.kv("b", true), field.kv("g", field.group(&.{ field.kv("x", @as(u64, 42)), field.kv("a", field.array(&.{ .null_value, .{ .boolean = true } })) })) } };
    var fields: [3]schema.FieldSchema = undefined;
    const definition = try registry.resolve((try registry.register(try reference.eventMetadata(event, &fields, &.{}))).ref);
    var valid_buffer: [4096]u8 = undefined;
    const valid = try reference.encodeReference(event, definition, &valid_buffer);
    try std.testing.expect(try equivalent(valid, definition, codec.decode_scratch_fields));
    for (0..16) |capacity| _ = try equivalent(valid, definition, capacity);
    for (0..valid.len) |length| try std.testing.expect(!try equivalent(valid[0..length], definition, codec.decode_scratch_fields));
    var successes: usize = 0;
    for (0..4096) |iteration| {
        var mutated: [4096]u8 = undefined;
        @memcpy(mutated[0..valid.len], valid);
        mutated[rng.random().uintLessThan(usize, valid.len)] ^= rng.random().int(u8) | 1;
        if (try equivalent(mutated[0..valid.len], definition, codec.decode_scratch_fields)) successes += 1;
        if (iteration % 64 == 0) {
            mutated[valid.len] = 0;
            _ = try equivalent(mutated[0 .. valid.len + 1], definition, codec.decode_scratch_fields);
        }
    }
    try std.testing.expect(successes != 0 and successes < 4096);
}

test "fused reference declines deferred including unused arguments for the authoritative materialized renderer" {
    for ([_]bool{ false, true }) |deferred| {
        var region: [4160]u8 align(64) = @splat(0);
        var registry = try schema.Registry.init(std.testing.allocator, std.testing.io, &region, try schema.layout(4096, 1, 4096));
        defer registry.deinit();
        const event: Event = .{ .level = .info, .scope = "template", .message = if (deferred) "value {d}" else "plain", .message_template = true, .timestamp_ns = 0, .fields = &.{}, .format_args = &.{field.kv("", @as(u64, 42))} };
        var arguments: [1]schema.FieldSchema = undefined;
        const definition = try registry.resolve((try registry.register(try reference.eventMetadata(event, &.{}, &arguments))).ref);
        var payload_bytes: [1024]u8 = undefined;
        const payload = try reference.encodeReference(event, definition, &payload_bytes);
        var scratch: [4]field.Field = undefined;
        const header = try reference.readReferenceHeader(payload, definition, scratch.len);
        var output: [2048]u8 = undefined;
        try std.testing.expectError(error.Fallback, fused.renderReference(.json, payload, header, definition, &output, &scratch, null));
        const decoded = try reference.resolve(payload, definition, &scratch);
        var writer = std.Io.Writer.fixed(&output);
        if (deferred) {
            try common.encodeWithTime(.json, decoded, null, &writer);
            try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "value 42") != null);
        } else try std.testing.expectError(error.WriteFailed, common.encodeWithTime(.json, decoded, null, &writer));
    }
}

test "fused reference runtime rejects checked schema damage before output and retains exact pins" {
    const Runtime = @import("../core/runtime.zig").Runtime;
    const configurations = @import("../config/routes.zig");
    const MemorySink = @import("../sink/memory.zig").MemorySink;
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        inline for (.{ false, true }) |persistent| {
            for ([_]usize{ 1, 64 }) |pending| {
                for ([_]usize{ 16, 512 }) |output_capacity| {
                    for (0..3) |damage| {
                        var tmp = std.testing.tmpDir(.{});
                        defer tmp.cleanup();
                        var path_bytes: [160]u8 = undefined;
                        const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/schema-fused.journal", .{tmp.sub_path});
                        var output_bytes: [8192]u8 = undefined;
                        var output = MemorySink.initBuffer(&output_bytes);
                        const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
                            .submission = submission,
                            .memory_queue = if (persistent) null else .{ .capacity = 128, .max_record_bytes = 512, .schema_capacity = 2, .max_schema_bytes = 1024 },
                            .journal = if (persistent) .{ .path = path, .capacity = 128, .max_record_bytes = 512, .schema_capacity = 2, .max_schema_bytes = 1024 } else null,
                            .max_thread_channels = if (submission == .low_latency) 1 else 0,
                            .thread_channel_capacity = 128,
                            .max_encoded_record_bytes = output_capacity,
                            .routes = &.{.{ .name = "output", .sink = output.sink(), .recovery_identity = "schema-fused-output" }},
                        });
                        defer runtime.destroy();
                        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "reference" }) else runtime.scoped("reference");
                        defer if (submission == .low_latency) log.detach() catch {};
                        const channel: u32 = if (submission == .low_latency) 1 else 0;
                        const journal = if (submission == .low_latency) runtime.thread_registry.?.getJournal(0) else runtime.journal.?;
                        var gap = if (submission == .low_latency) try journal.reserveSingleProducer(log.owner.producer_token) else try journal.reserve();
                        defer gap.abort();
                        var event: Event = .{ .level = .info, .scope = "reference", .message = "checked", .timestamp_ns = 0, .fields = &.{ field.kv("first", @as(u64, 42)), field.kv("last", @as(u64, 0)) } };
                        const binding = if (submission == .low_latency) try runtime.prewarmThreadSchema(1, event) else try runtime.prewarmSchema(event);
                        const definition = try journal.resolveReadySchema(binding.reference);
                        const manager: *configurations.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
                        const view = manager.acquire();
                        defer view.release();
                        const prior_pins = view.snapshot.pendingCount();
                        var reservation = if (submission == .low_latency)
                            try journal.reserveSingleProducerWithSchema(log.owner.producer_token, binding.reference)
                        else
                            try journal.reserveWithSchema(binding.reference);
                        defer reservation.abort();
                        event.channel = channel;
                        event.sequence = reservation.sequence;
                        event.session = runtime.session;
                        event.route_generation = view.snapshot.generation;
                        event.route_fingerprint = view.snapshot.fingerprint;
                        event.route_mask = if (damage == 2) 2 else 1;
                        const payload = try reference.encodeReference(event, definition, reservation.buffer());
                        const mutable_payload = reservation.buffer()[0..payload.len];
                        if (damage == 0) std.mem.writeInt(u32, mutable_payload[60..64], 1, .little) else mutable_payload[payload.len - 17] = @intFromEnum(codec.ValueTag.boolean);
                        view.snapshot.retainChannel(channel);
                        try reservation.commit(payload.len); // Fresh CRC: fault is in schema/value validation.
                        _ = (if (channel == 0) &runtime.counters else &runtime.channel_counters[channel - 1]).accepted.fetchAdd(1, .monotonic);
                        for (1..pending) |_| {
                            var next = if (submission == .low_latency)
                                try journal.reserveSingleProducerWithSchema(log.owner.producer_token, binding.reference)
                            else
                                try journal.reserveWithSchema(binding.reference);
                            defer next.abort();
                            event.route_mask = 1;
                            event.sequence = next.sequence;
                            const good = try reference.encodeReference(event, definition, next.buffer());
                            view.snapshot.retainChannel(channel);
                            try next.commit(good.len);
                            _ = (if (channel == 0) &runtime.counters else &runtime.channel_counters[channel - 1]).accepted.fetchAdd(1, .monotonic);
                        }
                        gap.abort();
                        try std.testing.expectError(error.SchemaMismatch, runtime.flush(.written));
                        try std.testing.expectEqual(@as(usize, 0), output.records);
                        try std.testing.expectEqual(@as(u64, 0), runtime.health().written);
                        try std.testing.expectEqual(pending, runtime.health().journal_pending);
                        try std.testing.expectEqual(prior_pins + pending, view.snapshot.pendingCount());
                        try std.testing.expectEqual(@as(u64, 1), journal.writtenTarget());
                    }
                }
            }
        }
    }
}
