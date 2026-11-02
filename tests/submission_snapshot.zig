//! Submission ownership and lifetime contracts exercised only through exports.
const std = @import("std");
const kron = @import("kron");
const testing = std.testing;

const protection: @FieldType(kron.RuntimeOptions, "redaction") = &.{
    .{ .key = "password", .action = .mask },
    .{ .key = "omit", .action = .drop },
};

// Copying this fixture captures each descriptor layer and each mutable byte
// buffer independently; an Event copy alone still borrows the same backing.
const Caller = struct {
    scope: [15]u8 = "snapshot.caller".*,
    message: [12]u8 = "object {any}".*,
    module: [8:0]u8 = "snapshot".*,
    file: [12:0]u8 = "snapshot.zig".*,
    function: [6:0]u8 = "caller".*,
    key: [4]u8 = "name".*,
    name: [5]u8 = "alice".*,
    password: [7]u8 = "private".*,
    omitted: [6]u8 = "remove".*,
    blob: [2]u8 = .{ 0, 255 },
    nested: [3]kron.Field = undefined,
    values: [2]kron.Value = undefined,
    attributes: [2]kron.Field = undefined,
    arguments: [1]kron.Field = undefined,

    fn init(self: *Caller) void {
        self.nested = .{
            kron.kv(&self.key, @as([]const u8, &self.name)),
            kron.kv("password", @as([]const u8, &self.password)),
            kron.kv("omit", @as([]const u8, &self.omitted)),
        };
        self.values = .{ .{ .group = &self.nested }, .{ .bytes = &self.blob } };
        self.attributes = .{ kron.kv("status", @as(u64, 500)), kron.kv("object", kron.array(&self.values)) };
        self.arguments = .{kron.kv("", kron.group(&self.nested))};
    }

    fn event(self: *const Caller, channel: u32) kron.Event {
        return .{
            .level = .info,
            .scope = &self.scope,
            .message = &self.message,
            .message_template = true,
            .format_args = &self.arguments,
            .fields = &self.attributes,
            .timestamp_ns = 1234,
            .session = 101,
            .sequence = 202,
            .channel = channel,
            .route_mask = 0xface,
            .route_fingerprint = 303,
            .route_generation = 404,
            .config_generation = 505,
            .trace_id = @splat(1),
            .span_id = @splat(2),
            .trace_flags = 0x81,
            .source = .{ .module = &self.module, .file = &self.file, .fn_name = &self.function, .line = 17, .column = 4 },
            .tree_validated = true,
        };
    }

    fn overwrite(self: *Caller) void {
        @memset(&self.scope, 'x');
        @memset(&self.message, 'x');
        @memset(self.module[0..self.module.len], 'x');
        @memset(self.file[0..self.file.len], 'x');
        @memset(self.function[0..self.function.len], 'x');
        @memset(&self.key, 'x');
        @memset(&self.name, 'x');
        @memset(&self.password, 'x');
        @memset(&self.omitted, 'x');
        @memset(&self.blob, 42);
        self.nested = @splat(kron.kv("overwritten", false));
        self.values = @splat(.null_value);
        self.attributes = @splat(kron.kv("overwritten", false));
        self.arguments = @splat(kron.kv("", false));
    }
};

fn emit(owner: anytype, event: kron.Event) !kron.EmitResult {
    const admission = switch (owner.begin(.info, event.scope)) {
        .ready => |ready| ready,
        else => return error.UnexpectedAdmission,
    };
    defer owner.end();
    return owner.submit(admission, event);
}

fn unchanged(before: Caller, caller: Caller, original: kron.Event, event: kron.Event) !void {
    try testing.expectEqualDeep(before, caller);
    // Rebuild fixed metadata from the saved backing as well: two borrowed
    // Event copies must not make the expected metadata alias the live input.
    const expected = before.event(original.channel);
    inline for (std.meta.fields(kron.Event)) |member| {
        if (comptime !std.mem.eql(u8, member.name, "fields") and !std.mem.eql(u8, member.name, "format_args")) {
            try testing.expectEqualDeep(@field(expected, member.name), @field(event, member.name));
        }
    }
    try testing.expectEqualDeep(original, event);
}

fn parse(bytes: []const u8) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
}

fn delivered(value: std.json.Value, channel: u32, mask: u64, redacted: bool) !void {
    const object = value.object;
    try testing.expectEqualStrings("snapshot.caller", object.get("scope").?.string);
    try testing.expectEqual(@as(i64, 1234), object.get("timestamp_ns").?.integer);
    try testing.expectEqual(@as(i64, channel), object.get("channel").?.integer);
    try testing.expectEqual(@as(i64, @intCast(mask)), object.get("route_mask").?.integer);
    try testing.expect(object.get("sequence").?.integer > 0);
    try testing.expectEqual(@as(i64, 0x81), object.get("trace_flags").?.integer);
    try testing.expectEqualStrings("01" ** 16, object.get("trace_id").?.string);
    try testing.expectEqualStrings("02" ** 8, object.get("span_id").?.string);
    const source = object.get("source").?.object;
    try testing.expectEqualStrings("snapshot", source.get("module").?.string);
    try testing.expectEqualStrings("snapshot.zig", source.get("file").?.string);
    try testing.expectEqualStrings("caller", source.get("function").?.string);
    try testing.expectEqual(@as(i64, 17), source.get("line").?.integer);
    try testing.expectEqual(@as(i64, 4), source.get("column").?.integer);
    const attributes = object.get("attributes").?.object;
    try testing.expectEqual(@as(i64, 500), attributes.get("status").?.integer);
    const array = attributes.get("object").?.array.items;
    const nested = array[0].object;
    try testing.expectEqualStrings("alice", nested.get("name").?.string);
    try testing.expectEqualStrings(if (redacted) "[REDACTED]" else "private", nested.get("password").?.string);
    if (redacted) {
        try testing.expect(nested.get("omit") == null);
    } else try testing.expectEqualStrings("remove", nested.get("omit").?.string);
    try testing.expectEqualStrings("hex:00ff", array[1].string);
    const message = object.get("message").?.string;
    try testing.expect(std.mem.indexOf(u8, message, "alice") != null);
    try testing.expect(std.mem.indexOf(u8, message, if (redacted) "[REDACTED]" else "private") != null);
    if (redacted) {
        try testing.expect(std.mem.indexOf(u8, message, "private") == null);
        try testing.expect(std.mem.indexOf(u8, message, "remove") == null);
    }
}

test "submission snapshot: caller metadata and every backing layer survive acceptance filtering and errors" {
    inline for (.{ .sync, .asynchronous, .low_latency }) |submission| {
        inline for (.{ false, true }) |redacted| {
            var bytes: [8192]u8 = undefined;
            var memory = kron.MemorySink.initBuffer(&bytes);
            const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
                .submission = submission,
                .memory_queue = if (submission == .sync) null else .{ .capacity = 4, .max_record_bytes = 2048 },
                .max_thread_channels = if (submission == .low_latency) 1 else 0,
                .thread_channel_capacity = 4,
                .redaction = if (redacted) protection else &.{},
                .predicate = "status >= 100",
                .routes = &.{
                    .{ .name = "selected", .sink = memory.sink(), .predicate = "status >= 500" },
                    .{ .name = "rejected", .sink = memory.sink(), .predicate = "status < 0" },
                },
            });
            defer runtime.destroy();
            const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "snapshot.caller" }) else runtime.scoped("snapshot.caller");
            defer if (submission == .low_latency) log.detach() catch {};
            const owner = if (submission == .low_latency) log.owner else runtime;
            var caller: Caller = .{};
            caller.init();
            const event = caller.event(if (submission == .low_latency) 99 else 0);
            const original = event;
            var before = caller;
            try testing.expectEqual(kron.EmitResult.accepted, try emit(owner, event));
            try unchanged(before, caller, original, event);
            // Exercise both the global predicate and the final route mask.
            for ([_]u64{ 50, 200 }) |status| {
                caller.attributes[0].value = .{ .unsigned = status };
                before = caller;
                try testing.expectEqual(kron.EmitResult.filtered, try emit(owner, event));
                try unchanged(before, caller, original, event);
            }
            caller.attributes[0].value = .{ .unsigned = 500 };
            caller.nested[2].key = "password";
            before = caller;
            const target = if (submission == .sync) 0 else (if (submission == .low_latency) log.owner.producer_token.journal else runtime.journal.?).reservationTarget();
            try testing.expectError(error.DuplicateKey, emit(owner, event));
            try unchanged(before, caller, original, event);
            caller.nested[2].key = "omit";
            before = caller;
            {
                var admission = switch (owner.begin(.info, event.scope)) {
                    .ready => |ready| ready,
                    else => return error.UnexpectedAdmission,
                };
                defer owner.end();
                admission.route_fingerprint ^= 1;
                try testing.expectError(error.InvalidAdmission, owner.submit(admission, event));
                try unchanged(before, caller, original, event);
            }
            if (submission != .sync) try testing.expectEqual(target, (if (submission == .low_latency) log.owner.producer_token.journal else runtime.journal.?).reservationTarget());
            try testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
            try runtime.flush(.written);
            try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
            try testing.expectEqual(@as(u64, 2), runtime.health().filtered);
            try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
            try testing.expectEqual(@as(usize, 1), memory.records);
            const encoded = try parse(memory.written());
            defer encoded.deinit();
            try delivered(encoded.value, if (submission == .low_latency) 1 else 0, 1, redacted);
        }
    }
}

test "submission snapshot: shared and SPSC acceptance copies raw Event slices before a publication gap closes" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        inline for (.{ false, true }) |redacted| {
            var bytes: [8192]u8 = undefined;
            var memory = kron.MemorySink.initBuffer(&bytes);
            const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
                .submission = submission,
                .memory_queue = .{ .capacity = 4, .max_record_bytes = 2048 },
                .max_thread_channels = if (submission == .low_latency) 1 else 0,
                .thread_channel_capacity = 4,
                .redaction = if (redacted) protection else &.{},
                .routes = &.{.{ .name = "output", .sink = memory.sink() }},
            });
            defer runtime.destroy();
            const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "snapshot.caller" }) else runtime.scoped("snapshot.caller");
            defer if (submission == .low_latency) log.detach() catch {};
            const owner = if (submission == .low_latency) log.owner else runtime;
            const queue = if (submission == .low_latency) log.owner.producer_token.journal else runtime.journal.?;
            var gap = if (submission == .low_latency) try queue.reserveSingleProducer(log.owner.producer_token) else try queue.reserve();
            defer gap.abort();
            var caller: Caller = .{};
            caller.init();
            const event = caller.event(0);
            const before = caller;
            try testing.expectEqual(kron.EmitResult.accepted, try emit(owner, event));
            try unchanged(before, caller, event, event);
            try testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
            caller.overwrite();
            gap.abort();
            try runtime.flush(.written);
            try testing.expectEqual(@as(usize, 0), queue.pending());
            try testing.expectEqual(@as(usize, 1), memory.records);
            const encoded = try parse(memory.written());
            defer encoded.deinit();
            try delivered(encoded.value, if (submission == .low_latency) 1 else 0, 1, redacted);
        }
    }
}

test "submission snapshot: public binding resolves canonical shape and rejects foreign or invalid references at the same boundary" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var bytes: [8192]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&bytes);
        const routes = [_]kron.RouteOptions{.{ .name = "output", .sink = memory.sink() }};
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 8, .max_record_bytes = 2048, .schema_capacity = 2, .max_schema_bytes = 1024 },
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 8,
            .redaction = protection,
            .predicate = "status >= 100",
            .routes = &routes,
        });
        defer runtime.destroy();
        var foreign_bytes: [1024]u8 = undefined;
        var foreign_memory = kron.MemorySink.initBuffer(&foreign_bytes);
        const foreign = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = .asynchronous,
            .memory_queue = .{ .capacity = 2, .max_record_bytes = 1024 },
            .routes = &.{.{ .name = "foreign", .sink = foreign_memory.sink() }},
        });
        defer foreign.destroy();
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "snapshot.caller" }) else runtime.scoped("snapshot.caller");
        var attached = submission == .low_latency;
        defer if (submission == .low_latency) {
            if (attached) log.detach() catch {};
        };
        const owner = if (submission == .low_latency) log.owner else runtime;
        const queue = if (submission == .low_latency) log.owner.producer_token.journal else runtime.journal.?;
        var caller: Caller = .{};
        caller.init();
        const event = caller.event(0);
        const before = caller;
        const binding = if (submission == .low_latency) try runtime.prewarmThreadSchema(1, event) else try runtime.prewarmSchema(event);
        var forged = binding;
        forged.definition.scope = "forged";
        forged.definition.message = "forged";
        forged.definition.field_count = 0;
        forged.definition.argument_count = 0;
        forged.definition.fields_wire = &.{};
        forged.definition.arguments_wire = &.{};
        var gap = if (submission == .low_latency) try queue.reserveSingleProducer(log.owner.producer_token) else try queue.reserve();
        defer gap.abort();
        const old = runtime.currentConfiguration();
        {
            const admission = switch (owner.begin(.info, event.scope)) {
                .ready => |ready| ready,
                else => return error.UnexpectedAdmission,
            };
            defer owner.end();
            try testing.expectEqual(kron.EmitResult.accepted, try owner.submitWithSchema(admission, event, forged));
            try unchanged(before, caller, event, event);
            const target = queue.reservationTarget();
            var invalid = binding;
            invalid.owner = @ptrCast(foreign);
            try testing.expectError(error.InvalidSchemaBinding, owner.submitWithSchema(admission, event, invalid));
            invalid = binding;
            invalid.journal = foreign.journal.?;
            try testing.expectError(error.InvalidSchemaBinding, owner.submitWithSchema(admission, event, invalid));
            invalid = binding;
            invalid.reference.hash[0] ^= 1;
            try testing.expectError(error.MissingSchema, owner.submitWithSchema(admission, event, invalid));
            invalid = binding;
            invalid.reference.id = 0;
            try testing.expectError(error.MissingSchema, owner.submitWithSchema(admission, event, invalid));
            invalid.reference.id = 3;
            try testing.expectError(error.MissingSchema, owner.submitWithSchema(admission, event, invalid));
            invalid = binding;
            invalid.reference.version = 0;
            try testing.expectError(error.UnsupportedSchemaVersion, owner.submitWithSchema(admission, event, invalid));
            try testing.expectEqual(target, queue.reservationTarget());
            try unchanged(before, caller, event, event);
            caller.attributes[0].value = .{ .unsigned = 50 };
            const filtered_before = caller;
            // Canonical-reference lookup remains after the global predicate.
            try testing.expectEqual(kron.EmitResult.filtered, try owner.submitWithSchema(admission, event, invalid));
            try unchanged(filtered_before, caller, event, event);
            caller.nested[2].key = "password";
            const invalid_before = caller;
            try testing.expectError(error.DuplicateKey, owner.submitWithSchema(admission, event, invalid));
            try unchanged(invalid_before, caller, event, event);
            caller.nested[2].key = "omit";
            caller.attributes[0].value = .{ .unsigned = 500 };
            var wrong = event;
            wrong.fields = &.{ kron.kv("status", @as(u64, 500)), kron.kv("wrong", true) };
            const wrong_before = wrong;
            try testing.expectError(error.SchemaMismatch, owner.submitWithSchema(admission, wrong, binding));
            try unchanged(before, caller, wrong_before, wrong);
            // Shape rejection keeps its post-reservation abort boundary.
            try testing.expectEqual(target + 1, queue.reservationTarget());
        }
        try testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
        _ = try runtime.replaceConfiguration(&routes, .{ .redaction = protection, .predicate = "status >= 100" });
        try testing.expect(!runtime.configurationReadyToCollect(old));
        caller.overwrite();
        gap.abort();
        try runtime.flush(.written);
        if (submission == .low_latency) {
            try log.detach();
            attached = false;
        }
        try testing.expect(runtime.configurationReadyToCollect(old));
        try testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
        try testing.expectEqual(@as(usize, 0), queue.pending());
        try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
        try testing.expectEqual(@as(usize, 1), memory.records);
        const encoded = try parse(memory.written());
        defer encoded.deinit();
        try delivered(encoded.value, if (submission == .low_latency) 1 else 0, 1, true);
    }
}

const NestedSink = struct {
    memory: kron.MemorySink,
    nested: *kron.Runtime,
    outer: ?*kron.Runtime = null,
    caller: *const Caller,
    before: Caller,
    event: kron.Event,
    calls: usize = 0,

    fn write(raw: *anyopaque, record: []const u8) anyerror!void {
        const self: *NestedSink = @ptrCast(@alignCast(raw));
        self.calls += 1;
        try unchanged(self.before, self.caller.*, self.event, self.caller.event(0));
        var saved: [8192]u8 = undefined;
        try testing.expect(record.len <= saved.len);
        @memcpy(saved[0..record.len], record);
        try testing.expectEqual(kron.EmitResult.rejected_closing, try self.outer.?.scoped("recursive").tryEmit(.info, "recursive", .{}));
        try testing.expectEqual(error.RecursiveSubmission, self.outer.?.health().last_error.?);
        // A second Runtime may nest while the outer redaction callback owns
        // its stack. Its different secret/tree must not replace outer scratch.
        var nested_caller: Caller = .{};
        nested_caller.name = "bravo".*;
        nested_caller.init();
        const nested_before = nested_caller;
        const nested_event = nested_caller.event(0);
        try testing.expectEqual(kron.EmitResult.accepted, try emit(self.nested, nested_event));
        try unchanged(nested_before, nested_caller, nested_event, nested_event);
        try testing.expectEqualSlices(u8, saved[0..record.len], record);
        try unchanged(self.before, self.caller.*, self.event, self.caller.event(0));
        try self.memory.writeRecord(record);
    }

    fn flush(raw: *anyopaque) anyerror!void {
        const self: *NestedSink = @ptrCast(@alignCast(raw));
        try self.memory.flush();
    }

    fn sync(raw: *anyopaque) anyerror!void {
        const self: *NestedSink = @ptrCast(@alignCast(raw));
        try self.memory.sync();
    }

    fn sink(self: *NestedSink) kron.Sink {
        return .{ .context = self, .vtable = &.{ .writeRecord = write, .flush = flush, .sync = sync } };
    }
};

test "submission snapshot: redaction scratch survives nested public sink callbacks in sync and full fallback delivery" {
    inline for (.{ false, true }) |fallback| {
        var nested_bytes: [8192]u8 = undefined;
        var nested_memory = kron.MemorySink.initBuffer(&nested_bytes);
        const nested = try kron.Runtime.create(testing.allocator, testing.io, .{
            .redaction = protection,
            .routes = &.{.{ .name = "nested", .sink = nested_memory.sink() }},
        });
        defer nested.destroy();
        var caller: Caller = .{};
        caller.init();
        const event = caller.event(0);
        const before = caller;
        var bytes: [8192]u8 = undefined;
        var callback: NestedSink = .{ .memory = kron.MemorySink.initBuffer(&bytes), .nested = nested, .caller = &caller, .before = before, .event = event };
        var tail_bytes: [8192]u8 = undefined;
        var tail = kron.MemorySink.initBuffer(&tail_bytes);
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = if (fallback) .asynchronous else .sync,
            .memory_queue = if (fallback) .{ .capacity = 1, .max_record_bytes = 2048 } else null,
            .overflow = .fallback_sync,
            .redaction = protection,
            .routes = &.{ .{ .name = "callback", .sink = callback.sink() }, .{ .name = "tail", .sink = tail.sink() } },
        });
        defer runtime.destroy();
        callback.outer = runtime;
        var gap: ?@typeInfo(@TypeOf(kron.Journal.reserve(undefined))).error_union.payload = if (fallback) try runtime.journal.?.reserve() else null;
        defer if (gap) |*reservation| reservation.abort();
        try testing.expectEqual(kron.EmitResult.accepted, try emit(runtime, event));
        try unchanged(before, caller, event, event);
        try testing.expectEqual(@as(usize, 1), callback.calls);
        try testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
        try testing.expectEqual(@as(u64, 0), nested.activeAdmissions());
        try testing.expectEqualStrings(callback.memory.written(), tail.written());
        try testing.expectEqual(@as(usize, 1), nested_memory.records);
        const encoded = try parse(tail.written());
        defer encoded.deinit();
        try delivered(encoded.value, if (fallback) @as(u32, 1) << 31 else 0, 3, true);
        const nested_encoded = try parse(nested_memory.written());
        defer nested_encoded.deinit();
        try testing.expectEqualStrings("bravo", nested_encoded.value.object.get("attributes").?.object.get("object").?.array.items[0].object.get("name").?.string);
        if (gap) |*reservation| reservation.abort();
        try runtime.flush(.written);
        try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
        try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
    }
}
