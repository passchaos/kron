//! Single-producer volatile FastRuntime reference for the text fast path.
const std = @import("std");
const kron = @import("kron");

const Options = struct {
    output: []const u8 = "",
    events: usize = 100_000,
    warmup: usize = 1_000,
    queue_slots: usize = 256,
    max_record_bytes: usize = 512,
};

fn elapsed(start: std.Io.Timestamp, end: std.Io.Timestamp) u64 {
    return @intCast(@max(0, start.durationTo(end).toNanoseconds()));
}

fn emit(log: anytype, n: usize) !kron.EmitResult {
    return log.tryEmit(.info, "event", .{
        .field0 = @as(u64, @intCast(n)),
        .field1 = @as(u64, @intCast(n + 1)),
        .field2 = @as(u64, @intCast(n + 2)),
        .field3 = @as(u64, @intCast(n + 3)),
        .field4 = @as(u64, @intCast(n + 4)),
    });
}

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    var options: Options = .{};
    for (arguments[1..]) |argument| {
        const equal = std.mem.indexOfScalar(u8, argument, '=') orelse return error.InvalidArgument;
        const key = argument[0..equal];
        const value = argument[equal + 1 ..];
        if (std.mem.eql(u8, key, "--output")) {
            options.output = value;
        } else if (std.mem.eql(u8, key, "--events")) {
            options.events = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "--warmup")) {
            options.warmup = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "--queue-slots")) {
            options.queue_slots = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "--max-record-bytes")) {
            options.max_record_bytes = try std.fmt.parseInt(usize, value, 10);
        } else return error.UnknownArgument;
    }
    if (options.output.len == 0 or options.events == 0 or options.queue_slots == 0 or options.max_record_bytes == 0) return error.InvalidOptions;

    const allocator = init.gpa;
    const io = init.io;
    const lifecycle_start = std.Io.Clock.awake.now(io);
    const file = try kron.FileSink.create(allocator, io, .{ .path = options.output, .buffer_bytes = 65536, .backend = .portable, .append = false });
    var file_live = true;
    defer if (file_live) file.deinit();
    const fast = try kron.FastRuntime.create(allocator, io, .{
        .sink = file.sink(),
        .capacity = options.queue_slots,
        .max_record_bytes = options.max_record_bytes,
        .overflow = .block,
        .min_level = .info,
        .idle = .spin,
    });
    var fast_live = true;
    defer if (fast_live) fast.destroy();
    const initialized = std.Io.Clock.awake.now(io);
    const log = fast.logger("reference");
    for (0..options.warmup) |index| _ = try emit(log, index);
    try fast.flush(.written);
    const before_bytes = (try std.Io.Dir.cwd().statFile(io, options.output, .{})).size;
    const start = std.Io.Clock.awake.now(io);
    for (0..options.events) |index| _ = try emit(log, options.warmup + index);
    const produced = std.Io.Clock.awake.now(io);
    try fast.flush(.written);
    const flushed = std.Io.Clock.awake.now(io);
    try fast.shutdown();
    const end = std.Io.Clock.awake.now(io);
    const health = fast.health();
    const artifact_bytes = (try std.Io.Dir.cwd().statFile(io, options.output, .{})).size;
    const written_bytes = artifact_bytes - before_bytes;
    fast.destroy();
    fast_live = false;
    file.deinit();
    file_live = false;
    const cleaned = std.Io.Clock.awake.now(io);
    const total_ns = elapsed(start, cleaned);
    const lifecycle_ns = elapsed(lifecycle_start, cleaned);
    const result = .{
        .schema_version = 2,
        .status = "ok",
        .library = "kron",
        .frontend = "fast",
        .strategy = "fast_text",
        .mode = "async",
        .storage = "memory",
        .prepared_schema = false,
        .phase = "batch",
        .metadata = "full",
        .events = options.events,
        .producers = 1,
        .warmup_events = options.warmup,
        .accepted = health.accepted,
        .written = health.written,
        .drop = health.dropped_full,
        .final_pending = health.pending,
        .producer_wall_ns = elapsed(start, produced),
        .flush_ns = elapsed(produced, flushed),
        .shutdown_ns = elapsed(flushed, end),
        .cleanup_ns = elapsed(end, cleaned),
        .total_ns = total_ns,
        .init_ns = elapsed(lifecycle_start, initialized),
        .preparation_ns = elapsed(initialized, start),
        .lifecycle_ns = lifecycle_ns,
        .lifecycle_records_per_sec = @as(f64, @floatFromInt(options.events + options.warmup)) * 1e9 / @as(f64, @floatFromInt(lifecycle_ns)),
        .written_bytes = written_bytes,
        .artifact_bytes = artifact_bytes,
        .written_records_per_sec = @as(f64, @floatFromInt(options.events)) * 1e9 / @as(f64, @floatFromInt(total_ns)),
        .sample_count = 0,
        .p50_ns = @as(?u64, null),
        .p99_ns = @as(?u64, null),
        .p999_ns = @as(?u64, null),
        .queue_policy = "block",
        .queue_slots = options.queue_slots,
        .file_buffer_bytes = 65536,
        .has_process_crash_recovery = false,
        .journal_reserved_bytes = 0,
        .queue_reserved_bytes = 0,
        .consumer_idle = "sleep",
        .backend_requested = "portable",
        .backend_selected = "portable",
    };
    var buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &buffer);
    try std.json.Stringify.value(result, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
