//! A real journal owner deliberately killed by crash_recovery.py.
//! No deferred deinit/abort runs on SIGKILL; no explicit journal sync follows
//! commit. The test establishes process-crash recovery, not power-loss safety.
const std = @import("std");
const kron = @import("kron");
const Phase = enum { reserved, committed, gap, @"schema-committed", @"schema-gap", @"hot-routes" };

const raw_secret = "kron-crash-raw-secret-9e891aa7";

fn encodeEvent(journal: *kron.Journal, id: usize, commit: bool, use_schema: bool, runtime: ?*kron.Runtime) !void {
    var scope = "crash.snapshot".*;
    var text = "borrowed original".*;
    var template = "event {d}: {s}".*;
    var module: [11:0]u8 = "crash.owner".*;
    var file: [16:0]u8 = "crash_writer.zig".*;
    var function: [11:0]u8 = "encodeEvent".*;
    var id_key = "id".*;
    var snapshot_key = "snapshot".*;
    var secret_key = "secret".*;
    var bytes_key = "bytes".*;
    var attributes = [_]kron.Field{
        kron.fields.kv(id_key[0..], id),
        kron.fields.kv(snapshot_key[0..], text[0..]),
        kron.fields.kv(secret_key[0..], kron.fields.secret(raw_secret)),
        kron.fields.kv(bytes_key[0..], kron.fields.bytes("\x00\xff")),
    };
    const arguments = [_]kron.Field{
        kron.fields.kv("", id),
        kron.fields.kv("", text[0..]),
    };
    var event: kron.Event = .{
        .level = .info,
        .scope = scope[0..],
        .message = template[0..],
        .message_template = true,
        .format_args = &arguments,
        .fields = &attributes,
        .timestamp_ns = 123456789,
        .session = 4242,
        .channel = if (runtime == null) 7 else 0,
        .route_mask = 1,
        .config_generation = 3,
        .trace_id = @splat(0xaa),
        .span_id = @splat(0xbb),
        .trace_flags = 1,
        .source = .{ .module = &module, .file = &file, .fn_name = &function, .line = 41, .column = 9 },
    };
    const definition: ?kron.schema_codec.Definition = if (use_schema) blk: {
        var metadata_fields: [attributes.len]kron.schema_codec.FieldSchema = undefined;
        var metadata_arguments: [arguments.len]kron.schema_codec.FieldSchema = undefined;
        const metadata = try kron.schema_codec.eventMetadata(event, &metadata_fields, &metadata_arguments);
        const reference = try journal.registerSchema(metadata);
        // Registered definitions must already own their metadata. Overwrite
        // the caller's storage before resolving and encoding any event values.
        @memset(&scope, 'x');
        @memset(&template, 'x');
        @memset(&id_key, 'x');
        @memset(&snapshot_key, 'x');
        @memset(&secret_key, 'x');
        @memset(&bytes_key, 'x');
        @memset(module[0..module.len], 'x');
        @memset(file[0..file.len], 'x');
        @memset(function[0..function.len], 'x');
        const restored = try journal.resolveSchema(reference);
        event.scope = restored.scope;
        event.message = restored.message.?;
        event.source = restored.source;
        var registered_fields = restored.fields();
        for (&attributes) |*field| field.key = (try registered_fields.next()).?.key;
        if (!std.mem.eql(u8, event.scope, "crash.snapshot") or !std.mem.eql(u8, event.message, "event {d}: {s}") or
            !std.mem.eql(u8, attributes[1].key, "snapshot") or !std.mem.eql(u8, event.source.?.file, "crash_writer.zig")) return error.SchemaMetadataNotCopied;
        break :blk restored;
    } else null;
    // Direct journal phases publish through codec; the hot-route phase uses
    // real Runtime admission, which captures and pins its configuration.
    const ReservationType = @TypeOf(journal.reserve() catch unreachable);
    var direct_reservation: ?ReservationType = null;
    errdefer if (direct_reservation) |*reservation| reservation.abort();
    const payload_length = if (runtime) |owner| blk: {
        const admission = switch (owner.begin(.info, event.scope)) {
            .ready => |value| value,
            else => return error.UnexpectedRuntimeAdmission,
        };
        defer owner.end();
        if (try owner.submit(admission, event) != .accepted) return error.UnexpectedRuntimeSubmission;
        break :blk @as(usize, 0);
    } else blk: {
        direct_reservation = if (definition) |schema| try journal.reserveWithSchema(schema.ref) else try journal.reserve();
        const reservation = &direct_reservation.?;
        event.sequence = reservation.sequence;
        const payload = if (definition) |schema|
            try kron.schema_codec.encodeReference(event, schema, reservation.buffer())
        else
            try kron.codec.encode(event, reservation.buffer());
        break :blk payload.len;
    };
    // Every borrowed input is overwritten before the process announces ready;
    // v2 static metadata was overwritten even before reference encoding.
    @memset(&scope, 'x');
    @memset(&text, 'x');
    @memset(&template, 'x');
    @memset(&id_key, 'x');
    @memset(&snapshot_key, 'x');
    @memset(&secret_key, 'x');
    @memset(&bytes_key, 'x');
    @memset(module[0..module.len], 'x');
    @memset(file[0..file.len], 'x');
    @memset(function[0..function.len], 'x');
    std.mem.doNotOptimizeAway(&scope);
    std.mem.doNotOptimizeAway(&text);
    std.mem.doNotOptimizeAway(&template);
    std.mem.doNotOptimizeAway(&id_key);
    std.mem.doNotOptimizeAway(&snapshot_key);
    std.mem.doNotOptimizeAway(&secret_key);
    std.mem.doNotOptimizeAway(&bytes_key);
    std.mem.doNotOptimizeAway(&module);
    std.mem.doNotOptimizeAway(&file);
    std.mem.doNotOptimizeAway(&function);
    if (direct_reservation) |*reservation| if (commit) try reservation.commit(payload_length);
    // A successful uncommitted reservation intentionally stays reserved.
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var path: ?[]const u8 = null;
    var phase: ?Phase = null;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--journal") and index + 1 < args.len) {
            index += 1;
            path = args[index];
        } else if (std.mem.eql(u8, args[index], "--phase") and index + 1 < args.len) {
            index += 1;
            phase = std.meta.stringToEnum(Phase, args[index]) orelse return error.InvalidPhase;
        } else return error.InvalidArguments;
    }
    const selected_phase = phase orelse return error.PhaseRequired;
    const journal_path = path orelse return error.JournalPathRequired;
    if (selected_phase == .@"hot-routes") {
        var old_bytes: [4096]u8 = undefined;
        var new_bytes: [4096]u8 = undefined;
        var old = kron.MemorySink.initBuffer(&old_bytes);
        var current = kron.MemorySink.initBuffer(&new_bytes);
        old.fail_after_records = 0;
        const runtime = try kron.Runtime.create(init.gpa, init.io, .{
            .submission = .asynchronous,
            .journal = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 2048 },
            .routes = &.{.{ .name = "output", .sink = old.sink(), .recovery_identity = "crash-old-output" }},
        });
        defer runtime.destroy();
        var gap = try runtime.journal.?.reserve();
        defer gap.abort();
        try encodeEvent(runtime.journal.?, 0, true, false, runtime);
        const next = try runtime.replaceConfiguration(&.{.{ .name = "output", .sink = current.sink(), .recovery_identity = "crash-new-output" }}, .{});
        if (next.generation != 2) return error.UnexpectedRouteGeneration;
        try encodeEvent(runtime.journal.?, 1, true, false, runtime);
        try encodeEvent(runtime.journal.?, 2, true, false, runtime);
        gap.abort();
        if (runtime.flush(.written)) |_| return error.ExpectedRequiredSinkFailure else |err| {
            if (err != error.InjectedWriteFailure) return err;
        }
        const health = runtime.health();
        if (health.accepted != 3 or health.written != 0 or health.journal_pending != 3 or old.records != 0 or current.records != 0) return error.LostHotRouteRecords;
        try readyAndWait(init.io);
        return;
    }
    const use_schema = selected_phase == .@"schema-committed" or selected_phase == .@"schema-gap";
    const journal = try kron.Journal.create(init.gpa, init.io, .{
        .path = journal_path,
        .capacity = 8,
        .max_record_bytes = 2048,
        .schema_capacity = if (use_schema) 4 else 0,
        .max_schema_bytes = 4096,
    });
    defer journal.deinit();
    switch (selected_phase) {
        .reserved => try encodeEvent(journal, 999, false, false, null),
        .committed => for (0..3) |id| try encodeEvent(journal, id, true, false, null),
        .gap => {
            try encodeEvent(journal, 0, true, false, null);
            try encodeEvent(journal, 999, false, false, null);
            try encodeEvent(journal, 1, true, false, null);
            try encodeEvent(journal, 2, true, false, null);
        },
        .@"schema-committed" => for (0..3) |id| try encodeEvent(journal, id, true, true, null),
        .@"schema-gap" => {
            _ = try journal.reserve();
            for (0..3) |id| try encodeEvent(journal, id, true, true, null);
        },
        .@"hot-routes" => unreachable,
    }
    try readyAndWait(init.io);
}

fn readyAndWait(io: std.Io) !void {
    try std.Io.File.stdout().writeStreamingAll(io, "ready\n");
    var byte: [1]u8 = undefined;
    while (true) {
        const read = try std.Io.File.stdin().readStreaming(io, &.{&byte});
        if (read == 0) return error.ExpectedSigkill;
    }
}
