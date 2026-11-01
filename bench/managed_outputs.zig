//! Complete managed single-output logging benchmark, including producer
//! capture, queue submission, consumer JSON formatting and written shutdown.
//! The source also compiles against the pre-list API for controlled comparison.
const std = @import("std");
const kron = @import("kron");
const Mode = enum { sync, memory, mmap, spsc_memory, spsc_mmap };

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.ExpectedModeDirectoryIterations;
    const mode = std.meta.stringToEnum(Mode, args[1]) orelse return error.InvalidMode;
    const iterations = try std.fmt.parseInt(usize, args[3], 10);
    if (iterations < 1000 or iterations > 1_000_000) return error.InvalidIterations;
    inline for (@typeInfo(Mode).@"enum".fields) |entry| {
        const selected: Mode = @enumFromInt(entry.value);
        if (mode == selected) return run(selected, init, args[2], iterations);
    }
    unreachable;
}

fn run(comptime mode: Mode, init: std.process.Init, directory: []const u8, iterations: usize) !void {
    const attached = mode == .spsc_memory or mode == .spsc_mmap;
    const mapped = mode == .mmap or mode == .spsc_mmap;
    const asynchronous = mode != .sync;
    const file_path = try std.fmt.allocPrint(init.arena.allocator(), "{s}/events.jsonl", .{directory});
    const journal_path = try std.fmt.allocPrint(init.arena.allocator(), "{s}/events.journal", .{directory});
    const queue: ?kron.Logging.Queue = if (!asynchronous) null else if (mapped) .{ .mmap = .{ .path = journal_path, .capacity = 256, .max_record_bytes = 8192 } } else .{ .memory = .{ .capacity = 256, .max_record_bytes = 8192 } };
    const policy_mode: kron.Logging.Mode = if (!asynchronous) .sync else if (attached) .spsc else .asynchronous;
    const options: kron.Logging.Options = if (@hasField(kron.Logging.Options, "outputs")) .{
        .outputs = &.{.{ .name = "file", .target = .{ .file = .{ .path = file_path, .append = false, .backend = .portable } }, .mode = policy_mode, .queue = queue, .format = .json, .max_threads = 1 }},
    } else .{
        .output = .{ .file = .{ .path = file_path, .append = false, .backend = .portable } },
        .mode = policy_mode,
        .queue = queue,
        .format = .json,
        .max_threads = 1,
    };
    var allocator = std.testing.FailingAllocator.init(init.gpa, .{});
    const initialized = std.Io.Clock.awake.now(init.io).nanoseconds;
    const logging = try kron.Logging.create(allocator.allocator(), init.io, options);
    defer logging.destroy();
    const initialization_ns = std.Io.Clock.awake.now(init.io).nanoseconds - initialized;
    const log = if (attached) try logging.attachThread("managed.bench") else logging.scoped("managed.bench");
    var live = attached;
    defer if (comptime attached) {
        if (live) log.detach() catch {};
    };
    const warmup = 1000;
    for (0..warmup) |id| {
        if (try log.tryEmit(.info, "managed output", .{ .id = @as(u64, @intCast(id)), .payload = "constant-value" }) != .accepted) return error.RejectedWarmup;
    }
    try logging.flush();
    allocator.fail_index = allocator.alloc_index;
    allocator.resize_fail_index = allocator.resize_index;
    const start = std.Io.Clock.awake.now(init.io).nanoseconds;
    for (0..iterations) |id| {
        if (try log.tryEmit(.info, "managed output", .{ .id = @as(u64, @intCast(id)), .payload = "constant-value" }) != .accepted) return error.RejectedEvent;
    }
    const producer_ns = std.Io.Clock.awake.now(init.io).nanoseconds - start;
    if (attached) {
        try log.detach();
        live = false;
    }
    try logging.shutdown();
    const complete_ns = std.Io.Clock.awake.now(init.io).nanoseconds - start;
    const health = logging.health();
    if (health.accepted != iterations + warmup or health.written != iterations + warmup or health.journal_pending != 0 or allocator.has_induced_failure) return error.IncompleteWorkflow;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try std.json.Stringify.value(.{
        .benchmark = "managed_single_output",
        .mode = @tagName(mode),
        .iterations = iterations,
        .warmup = warmup,
        .initialization_ns = initialization_ns,
        .producer_ns = producer_ns,
        .complete_ns = complete_ns,
        .accepted = health.accepted,
        .written = health.written,
        .pending = health.journal_pending,
        .runtime_allocations = 0,
        .backend = "portable",
        .queue_capacity = if (asynchronous) @as(usize, 256) else 0,
        .max_record_bytes = if (asynchronous) @as(usize, 8192) else 0,
    }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
