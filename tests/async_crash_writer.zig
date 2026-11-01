//! Real asynchronous producer for async_storage_crash.py. SIGKILL bypasses
//! gap.abort/deinit; a READY handshake proves acceptance before any output.
const std = @import("std");
const kron = @import("kron");

const Storage = enum { memory, mmap };
const Phase = enum { crash, drain };
const raw_password = "kron-async-real-password-5b73a998";

const Options = struct {
    storage: Storage,
    phase: Phase,
    journal: []const u8,
    output: []const u8,
};

fn parse(args: []const []const u8) !Options {
    var storage: ?Storage = null;
    var phase: ?Phase = null;
    var journal: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const argument = args[index];
        const equal = std.mem.findScalar(u8, argument, '=');
        const key = if (equal) |position| argument[0..position] else argument;
        const value = if (equal) |position| argument[position + 1 ..] else blk: {
            index += 1;
            if (index == args.len) return error.MissingOptionValue;
            break :blk args[index];
        };
        if (value.len == 0) return error.MissingOptionValue;
        if (std.mem.eql(u8, key, "--storage")) {
            if (storage != null) return error.DuplicateOption;
            storage = std.meta.stringToEnum(Storage, value) orelse return error.InvalidStorage;
        } else if (std.mem.eql(u8, key, "--phase")) {
            if (phase != null) return error.DuplicateOption;
            phase = std.meta.stringToEnum(Phase, value) orelse return error.InvalidPhase;
        } else if (std.mem.eql(u8, key, "--journal")) {
            if (journal != null) return error.DuplicateOption;
            journal = value;
        } else if (std.mem.eql(u8, key, "--output")) {
            if (output != null) return error.DuplicateOption;
            output = value;
        } else return error.UnknownOption;
    }
    return .{ .storage = storage orelse return error.StorageRequired, .phase = phase orelse return error.PhaseRequired, .journal = journal orelse return error.JournalRequired, .output = output orelse return error.OutputRequired };
}

fn announce(io: std.Io, prefix: []const u8, options: Options, health: anytype, first_sequence: u64) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.print("{s} {{\"storage\":\"{s}\",\"phase\":\"{s}\",\"accepted\":{d},\"written\":{d},\"pending\":{d},\"first_sequence\":{d},\"queue_storage\":\"{s}\",\"worker_alive\":{}}}\n", .{
        prefix,                 @tagName(options.storage), @tagName(options.phase),        health.accepted,     health.written,
        health.journal_pending, first_sequence,            @tagName(health.queue_storage), health.worker_alive,
    });
    try std.Io.File.stdout().writeStreamingAll(io, writer.buffered());
}

fn waitForWorker(runtime: *kron.Runtime, io: std.Io) !void {
    const deadline = kron.Deadline.after(io, 5 * std.time.ns_per_s);
    while (!runtime.health().worker_alive) {
        if (runtime.health().last_error) |failure| return failure;
        if (deadline.expired(io)) return error.WorkerDidNotStart;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
}

fn emitThree(runtime: *kron.Runtime, options: Options) void {
    const log = runtime.logger(.{ .scope = "async.storage" });
    for (0..3) |identifier| log.info("asynchronous storage event", .{
        .id = identifier,
        .storage = @tagName(options.storage),
        .phase = @tagName(options.phase),
        // A real ordinary string exercises the configured policy, independently
        // of secret wrappers. Neither captured bytes nor JSON may retain it.
        .password = raw_password,
    });
}

fn waitForSigkill(io: std.Io) !void {
    var byte: [1]u8 = undefined;
    while (true) {
        if (try std.Io.File.stdin().readStreaming(io, &.{&byte}) == 0) return error.ExpectedSigkill;
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parse(args);
    const file = try kron.FileSink.create(init.gpa, init.io, .{ .path = options.output, .backend = .portable, .buffer_bytes = 4096, .append = true });
    defer file.deinit();
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .asynchronous,
        .journal = if (options.storage == .mmap) .{ .path = options.journal, .capacity = 8, .max_record_bytes = 1024 } else null,
        .memory_queue = if (options.storage == .memory) .{ .capacity = 8, .max_record_bytes = 1024 } else null,
        .routes = &.{.{ .name = "output", .sink = file.sink(), .format = .json }},
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    try waitForWorker(runtime, init.io);
    if (options.phase == .crash) {
        var gap = try runtime.journal.?.reserve();
        defer gap.abort();
        emitThree(runtime, options);
        const health = runtime.health();
        if (health.accepted != 3 or health.written != 0 or health.journal_pending != 4 or health.last_error != null) return error.UnexpectedPendingHealth;
        if (runtime.journal.?.isPersistent() != (options.storage == .mmap)) return error.UnexpectedStorage;
        try announce(init.io, "READY", options, health, gap.sequence + 1);
        try waitForSigkill(init.io);
    } else {
        const first_sequence = runtime.journal.?.reservationTarget() + 1;
        emitThree(runtime, options);
        try runtime.flush(.written);
        try runtime.shutdown(.drain);
        const health = runtime.health();
        if (health.accepted != 3 or health.written != 3 or health.journal_pending != 0 or health.last_error != null or health.worker_alive) return error.UnexpectedDrainedHealth;
        try announce(init.io, "DRAINED", options, health, first_sequence);
    }
}
