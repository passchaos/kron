//! Candidate single-producer mmap-spool reference: render directly into a
//! file-backed mapping, publish with msync and truncate on shutdown.
const std = @import("std");
const kron = @import("kron");

const Options = struct {
    output: []const u8 = "",
    events: usize = 100_000,
    warmup: usize = 1_000,
    capacity_bytes: usize = 0,
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
        } else if (std.mem.eql(u8, key, "--capacity-bytes")) {
            options.capacity_bytes = try std.fmt.parseInt(usize, value, 10);
        } else return error.UnknownArgument;
    }
    if (options.output.len == 0 or options.events == 0) return error.InvalidOptions;
    if (options.capacity_bytes == 0) {
        // Generous per-record budget for the five-field benchmark record; the
        // observed full JSON record is about 299 bytes.
        options.capacity_bytes = (options.events + options.warmup) * 512 + 4 * 1024 * 1024;
    }

    const allocator = init.gpa;
    const io = init.io;
    const lifecycle_start = std.Io.Clock.awake.now(io);
    const spool = try kron.MmapSpool.create(allocator, io, .{
        .path = options.output,
        .capacity_bytes = options.capacity_bytes,
        .min_level = .info,
    });
    const initialized = std.Io.Clock.awake.now(io);
    const log = spool.logger("reference");
    for (0..options.warmup) |index| _ = try emit(log, options.events + index);
    try spool.flush(.written);
    const warmup_offset = spool.writtenBytes();
    const start = std.Io.Clock.awake.now(io);
    for (0..options.events) |index| _ = try emit(log, index);
    const produced = std.Io.Clock.awake.now(io);
    try spool.flush(.written);
    const flushed = std.Io.Clock.awake.now(io);
    const measured_offset = spool.writtenBytes();
    try spool.shutdown();
    const end = std.Io.Clock.awake.now(io);
    const health = spool.health();
    const artifact_bytes = (try std.Io.Dir.cwd().statFile(io, options.output, .{})).size;
    const written_bytes = measured_offset - warmup_offset;
    spool.destroy();
    const cleaned = std.Io.Clock.awake.now(io);
    const total_ns = elapsed(start, cleaned);
    const lifecycle_ns = elapsed(lifecycle_start, cleaned);
    const result = .{
        .schema_version = 2,
        .status = "ok",
        .library = "kron",
        .frontend = "spool",
        .strategy = "spool_mmap",
        .mode = "async",
        .storage = "mmap",
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
        .queue_slots = 0,
        .file_buffer_bytes = 65536,
        .has_process_crash_recovery = false,
        .journal_reserved_bytes = 0,
        .queue_reserved_bytes = 0,
        .consumer_idle = "none",
        .backend_requested = "mmap_spool",
        .backend_selected = "mmap_spool",
    };
    var buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &buffer);
    try std.json.Stringify.value(result, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
