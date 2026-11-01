//! Native Zig host qualification. Mobile Zig hosts call run with their own
//! allocator, Io environment and a fresh writable sandbox directory.
//! No subprocess, Python, network, C ABI or language binding is required here.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const JournalOptions = @typeInfo(@FieldType(kron.RuntimeOptions, "journal")).optional.child;

pub const Mode = enum { sync, memory, mmap, spsc_memory, spsc_mmap };
pub const Durability = enum { confirmed, unsupported };
pub const ModeReport = struct {
    mode: Mode,
    accepted: u64,
    written: u64,
    pending: usize,
    storage: kron.QueueStorage,
    runtime_allocations_after_setup: usize,
    file_durable: Durability,
};
pub const JournalReport = struct { schema: bool, recovered: usize, durable: Durability, inspection_unchanged: bool };
pub const Report = struct {
    target: kron.platform.Target = kron.platform.target,
    arch: std.Target.Cpu.Arch = builtin.cpu.arch,
    zig: []const u8 = builtin.zig_version_string,
    optimize: std.builtin.OptimizeMode = builtin.mode,
    single_threaded: bool = builtin.single_threaded,
    modes: [5]?ModeReport = @splat(null),
    journals: [2]JournalReport = undefined,
    rolling_durable: Durability = undefined,
    rolling_archives: usize = 0,
    scope: []const u8 = "Native host file/runtime/queue/journal reopen checks; no process-kill or power-loss qualification.",
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, directory: []const u8) !Report {
    // Require a fresh child folder: never delete or truncate an existing test
    // result, and keep all artifacts for inspection by the host/operator.
    try std.Io.Dir.cwd().createDirPath(io, directory);
    const dir = try std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true });
    defer dir.close(io);
    try dir.createDir(io, "native-check", .default_dir);
    const child_path = try std.fs.path.join(allocator, &.{ directory, "native-check" });
    defer allocator.free(child_path);
    const child = try dir.openDir(io, "native-check", .{ .iterate = true });
    defer child.close(io);
    var report: Report = .{};
    for (std.enums.values(Mode), 0..) |mode, index| {
        if (builtin.single_threaded and mode != .sync) continue;
        report.modes[index] = try runtimeCase(allocator, io, child_path, mode);
    }
    report.journals[0] = try journalCase(allocator, io, child_path, false);
    report.journals[1] = try journalCase(allocator, io, child_path, true);
    report.rolling_durable = try rollingCase(allocator, io, child);
    report.rolling_archives = 2;
    return report;
}

fn runtimeCase(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, mode: Mode) !ModeReport {
    const path = try std.fs.path.join(allocator, &.{ directory, @tagName(mode) });
    defer allocator.free(path);
    const dir = try std.Io.Dir.cwd().createDirPathOpen(io, path, .{ .open_options = .{ .iterate = true } });
    defer dir.close(io);
    // Exercise Unicode file names as well as native separator handling.
    const file = try kron.FileSink.create(allocator, io, .{ .dir = dir, .path = "日志.jsonl", .backend = .portable });
    defer file.deinit();
    const journal_path = try std.fs.path.join(allocator, &.{ path, "事件.journal" });
    defer allocator.free(journal_path);
    const attached = mode == .spsc_memory or mode == .spsc_mmap;
    const memory = mode == .memory or mode == .spsc_memory;
    const mapped = mode == .mmap or mode == .spsc_mmap;
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    const runtime = try kron.Runtime.create(failing.allocator(), io, .{
        .submission = if (mode == .sync) .sync else if (attached) .low_latency else .asynchronous,
        .memory_queue = if (memory) .{ .capacity = 16, .max_record_bytes = 4096 } else null,
        .journal = if (mapped) .{ .path = journal_path, .capacity = 16, .max_record_bytes = 4096 } else null,
        .max_thread_channels = if (attached) 1 else 0,
        .thread_channel_capacity = 16,
        .idle = .sleep,
        .routes = &.{.{ .name = "file", .sink = file.sink(), .format = .json }},
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    if (attached) {
        const log = try runtime.attachThread(.{ .scope = "platform.host" });
        defer log.detach() catch {};
        failing.fail_index = failing.alloc_index;
        failing.resize_fail_index = failing.resize_index;
        try capture(runtime, log);
    } else {
        failing.fail_index = failing.alloc_index;
        failing.resize_fail_index = failing.resize_index;
        try capture(runtime, runtime.scoped("platform.host"));
    }
    try runtime.flush(.written);
    const durable = try durability(runtime);
    if (!kron.platform.directory_durable_protocol) try check(durable == .unsupported);
    // An unsupported optional boundary must leave ordinary output usable.
    try runtime.flush(.written);
    if (builtin.single_threaded) {
        try check(!runtime.controlStatus().available);
        try std.testing.expectError(error.TimedControlUnavailable, runtime.flushUntil(.written, kron.Deadline.after(io, std.time.ns_per_s)));
    } else try runtime.flushUntil(.written, kron.Deadline.after(io, 5 * std.time.ns_per_s));
    try runtime.shutdown(.drain);
    try runtime.shutdown(.drain);
    const health = runtime.health();
    try check(health.state == .closed and !health.worker_alive);
    try check(health.accepted == 2 and health.written == 2 and health.journal_pending == 0 and health.filtered == 1);
    try check(health.dropped_full == 0 and health.dropped_oversize == 0 and health.capture_errors == 0 and health.write_errors == 0);
    const expected_storage: kron.QueueStorage = if (mode == .sync) .none else if (memory) .memory else .mmap;
    try check(runtime.queueStorage() == expected_storage);
    try check(!failing.has_induced_failure);
    try validateJson(allocator, io, dir);
    var iterator = dir.iterate();
    var journals: usize = 0;
    while (try iterator.next(io)) |entry| if (std.mem.endsWith(u8, entry.name, ".journal")) {
        journals += 1;
    };
    try check(journals == if (mode == .spsc_mmap) @as(usize, 2) else if (mapped) @as(usize, 1) else 0);
    return .{ .mode = mode, .accepted = health.accepted, .written = health.written, .pending = health.journal_pending, .storage = runtime.queueStorage(), .runtime_allocations_after_setup = 0, .file_durable = durable };
}

fn durability(runtime: *kron.Runtime) !Durability {
    runtime.flush(.durable) catch |err| switch (err) {
        error.UnsupportedDurability => return .unsupported,
        else => return err,
    };
    return .confirmed;
}

fn capture(runtime: *kron.Runtime, base: anytype) !void {
    var name = "original".*;
    var values = [_]kron.Value{ kron.fields.fromAny(@as([]const u8, &name)), kron.fields.fromAny(kron.secret("private-nested")) };
    const log = base.withBorrowed(.{ .service = "platform-host" });
    try check(try log.tryEmit(.info, "first", .{ .id = @as(u64, 1), .nested = kron.array(&values), .password = "private-password" }) == .accepted);
    @memset(&name, 'x');
    values = @splat(.null_value);
    try check(try log.tryEmit(.debug, "filtered", .{}) == .filtered);
    try runtime.reloadFilter("off,platform.host=debug");
    try check(try log.tryLogf(.debug, "second {d}", .{@as(u64, 7)}, .{ .id = @as(u64, 2), .password = "private-password" }) == .accepted);
}

fn validateJson(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !void {
    const bytes = try dir.readFileAlloc(io, "日志.jsonl", allocator, .limited(16 * 1024));
    defer allocator.free(bytes);
    try check(std.mem.find(u8, bytes, "private-") == null);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    for (1..3) |id| {
        const line = lines.next() orelse return error.MissingRecord;
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
        defer parsed.deinit();
        const record = parsed.value.object;
        try check(std.mem.eql(u8, record.get("scope").?.string, "platform.host"));
        try check(std.mem.eql(u8, record.get("message").?.string, if (id == 1) "first" else "second 7"));
        const attrs = record.get("attributes").?.object;
        try check(attrs.get("id").?.integer == id);
        try check(std.mem.eql(u8, attrs.get("service").?.string, "platform-host"));
        try check(std.mem.eql(u8, attrs.get("password").?.string, "[REDACTED]"));
        if (id == 1) {
            const nested = attrs.get("nested").?.array.items;
            try check(nested.len == 2 and std.mem.eql(u8, nested[0].string, "original") and std.mem.eql(u8, nested[1].string, "[REDACTED]"));
        }
    }
    try check(lines.next().?.len == 0 and lines.next() == null);
}

fn journalCase(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, use_schema: bool) !JournalReport {
    const path = try std.fs.path.join(allocator, &.{ directory, if (use_schema) "schema.journal" else "inline.journal" });
    defer allocator.free(path);
    const options: JournalOptions = .{ .path = path, .capacity = 8, .max_record_bytes = 4096, .schema_capacity = if (use_schema) 4 else 0, .max_schema_bytes = 4096 };
    {
        const journal = try kron.Journal.create(allocator, io, options);
        defer journal.deinit();
        try std.testing.expectError(error.JournalLocked, kron.Journal.create(allocator, io, options));
        // End this owner's lifetime with a reservation gap and one complete
        // event. There is no destructor ACK, no hidden sync, and no later use
        // of the borrowed gap. This is reopen testing, not forced termination.
        const gap = try journal.reserve();
        _ = gap;
        const event = reopen_event;
        var reservation = if (use_schema) blk: {
            var fields: [2]kron.schema.FieldSchema = undefined;
            const reference = try journal.registerSchema(try kron.schema_codec.eventMetadata(event, &fields, &.{}));
            break :blk try journal.reserveWithSchema(reference);
        } else try journal.reserve();
        const payload = if (use_schema) try kron.schema_codec.encodeReference(event, try journal.resolveSchema(reservation.schema_ref.?), reservation.buffer()) else try kron.codec.encode(event, reservation.buffer());
        try reservation.commit(payload.len);
    }
    const before = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(128 * 1024));
    defer allocator.free(before);
    const before_hash = std.hash.Wyhash.hash(0, before);
    for (0..2) |_| {
        const reader = try kron.archive.Reader.openOptions(allocator, io, path, .{ .recover_only = true, .max_memory_bytes = 128 * 1024 });
        defer reader.deinit();
        try check(reader.kind() == .journal);
        try checkEvent((try reader.next()) orelse return error.MissingRecoveredEvent);
        try check(try reader.next() == null);
        const inspected = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(128 * 1024));
        defer allocator.free(inspected);
        try check(std.hash.Wyhash.hash(0, inspected) == before_hash);
    }
    var durable: Durability = undefined;
    {
        const reopened = try kron.Journal.create(allocator, io, options);
        defer reopened.deinit();
        const record = (try reopened.peekChecked()) orelse return error.MissingReopenedEvent;
        try check(record.sequence == 2);
        var scratch: [kron.codec.decode_scratch_fields]kron.Field = undefined;
        const event = if (record.schema_ref) |reference| try kron.schema_codec.resolve(record.payload, try reopened.resolveSchema(reference), &scratch) else try kron.codec.decode(record.payload, &scratch);
        try checkEvent(event);
        try reopened.releaseAfter(record, .written);
        try check(reopened.pending() == 0);
        durable = blk: {
            reopened.sync() catch |err| {
                if (err == error.UnsupportedDurability) break :blk .unsupported;
                return err;
            };
            break :blk .confirmed;
        };
    }
    const reader = try kron.archive.Reader.openOptions(allocator, io, path, .{ .recover_only = true, .max_memory_bytes = 128 * 1024 });
    defer reader.deinit();
    try check(try reader.next() == null);
    if (!kron.platform.directory_durable_protocol) try check(durable == .unsupported);
    return .{ .schema = use_schema, .recovered = 1, .durable = durable, .inspection_unchanged = true };
}

const reopen_event: kron.Event = .{ .level = .info, .scope = "platform.reopen", .message = "original", .fields = &.{ kron.kv("nested", kron.array(&.{ kron.fields.fromAny("original"), kron.fields.fromAny(kron.secret("private-value")) })), kron.kv("id", @as(u64, 7)) }, .timestamp_ns = 123, .session = 17, .sequence = 2, .channel = 0 };

fn checkEvent(event: kron.Event) !void {
    try check(event.session == 17 and event.sequence == 2 and event.fields.len == 2);
    try check(std.mem.eql(u8, event.scope, "platform.reopen") and std.mem.eql(u8, event.message, "original"));
    const values = event.fields[0].value.array;
    try check(values.len == 2 and std.mem.eql(u8, values[0].string, "original") and std.mem.eql(u8, values[1].string, "[REDACTED]"));
    try check(event.fields[1].value.unsigned == 7);
}

fn rollingCase(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !Durability {
    const output = try kron.RollingFileSink.create(allocator, io, .{ .dir = dir, .path = "轮转.log", .max_bytes = 4, .retention = 2, .buffer_bytes = 64, .backend = .portable });
    defer output.deinit();
    for ([_][]const u8{ "one\n", "two\n", "tri\n", "for\n" }) |record| try output.writeRecord(record);
    try output.flush();
    const durable: Durability = blk: {
        output.sync() catch |err| {
            if (err == error.UnsupportedDurability) break :blk .unsupported;
            return err;
        };
        break :blk .confirmed;
    };
    // Capability rejection must not latch an ordinary output error.
    try output.flush();
    try output.shutdown();
    if (!kron.platform.directory_durable_protocol) try check(durable == .unsupported);
    const paths = [_][]const u8{ "轮转.log", "轮转.log.1", "轮转.log.2" };
    const expected = [_][]const u8{ "for\n", "tri\n", "two\n" };
    for (paths, expected) |path, contents| {
        const bytes = try dir.readFileAlloc(io, path, allocator, .limited(64));
        defer allocator.free(bytes);
        try check(std.mem.eql(u8, bytes, contents));
    }
    try std.testing.expectError(error.FileNotFound, dir.statFile(io, "轮转.log.3", .{}));
    return durable;
}

fn check(condition: bool) !void {
    if (!condition) return error.PlatformQualificationFailed;
}
