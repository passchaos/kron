//! The same logical event/attributes as reference.cpp, using public kron APIs.
const std = @import("std");
const kron = @import("kron");
const BackendKind = @TypeOf(@as(kron.FileSink.Options, .{ .path = "" }).backend);
const Frontend = enum { runtime, managed };
const Options = struct {
    frontend: Frontend = .runtime,
    output: []const u8 = "",
    events: usize = 10000,
    producers: usize = 1,
    warmup: usize = 1000,
    queue_slots: usize = 256,
    max_record_bytes: usize = 512,
    phase: []const u8 = "sampled",
    mode: []const u8 = "async",
    storage: []const u8 = "mmap",
    schema: bool = false,
    consumer_batches: usize = 4,
    backend: BackendKind = .portable,
    render_cache: bool = false,
    text_format: bool = false,
    spool_clock: []const u8 = "native",
    spool_timestamp_period: usize = 1,
};

const Gate = struct {
    ready: std.atomic.Value(u32) = .init(0),
    start: std.atomic.Value(u32) = .init(0),
};
const Worker = struct {
    runtime: *kron.Runtime,
    logging: ?*kron.Logging = null,
    options: Options,
    gate: *Gate,
    id: usize,
    samples: []u64,
    accepted: u64 = 0,
    failure: ?anyerror = null,

    fn run(self: *Worker) void {
        if (self.logging) |owner| {
            const attached = std.mem.eql(u8, self.options.mode, "spsc");
            const log = (if (attached)
                (if (self.options.schema) owner.attachPreparedThread(shape) else owner.attachThread("reference"))
            else
                (if (self.options.schema) owner.prepared(shape) else @as(anyerror!kron.Logging.Logger, owner.scoped("reference")))) catch |err| {
                self.failure = err;
                self.wait();
                return;
            };
            defer if (attached) log.detach() catch |err| {
                self.failure = err;
            };
            self.runLogger(log);
            return;
        }
        if (std.mem.eql(u8, self.options.mode, "spsc")) {
            const log = self.runtime.attachThread(.{ .scope = "reference" }) catch |err| {
                self.failure = err;
                self.wait();
                return;
            };
            defer log.detach() catch |err| {
                self.failure = err;
            };
            if (self.options.schema) {
                const binding = self.runtime.prewarmThreadSchema(@intCast(log.owner.control_index + 1), shape) catch |err| {
                    self.failure = err;
                    self.wait();
                    return;
                };
                self.runLogger(self.runtime.threadLoggerWithSchema(log, binding) catch |err| {
                    self.failure = err;
                    self.wait();
                    return;
                });
            } else self.runLogger(log);
        } else if (self.options.schema) {
            const binding = self.runtime.prewarmSchema(shape) catch |err| {
                self.failure = err;
                self.wait();
                return;
            };
            self.runLogger(self.runtime.loggerWithSchema(binding) catch |err| {
                self.failure = err;
                self.wait();
                return;
            });
        } else self.runLogger(self.runtime.scoped("reference"));
    }
    fn wait(self: *Worker) void {
        const io = self.runtime.io;
        _ = self.gate.ready.fetchAdd(1, .acq_rel);
        std.Io.futexWake(io, u32, &self.gate.ready.raw, std.math.maxInt(u32));
        while (self.gate.start.load(.acquire) == 0) std.Io.futexWaitUncancelable(io, u32, &self.gate.start.raw, 0);
    }
    fn runLogger(self: *Worker, log: anytype) void {
        for (0..share(self.options.warmup, self.options.producers, self.id)) |index| {
            _ = emit(log, self.options.events + index * self.options.producers + self.id) catch |err| {
                self.failure = err;
                break;
            };
        }
        self.wait();
        if (self.failure != null) return;
        for (0..share(self.options.events, self.options.producers, self.id)) |index| {
            const before = if (self.samples.len != 0) std.Io.Clock.awake.now(self.runtime.io) else null;
            const result = emit(log, index * self.options.producers + self.id);
            if (before) |start| self.samples[index] = elapsed(start, std.Io.Clock.awake.now(self.runtime.io));
            const outcome = result catch |err| {
                self.failure = err;
                return;
            };
            if (outcome != .accepted) {
                self.failure = error.UnexpectedOutcome;
                return;
            }
            self.accepted += 1;
        }
    }
    fn emit(log: anytype, n: usize) !kron.EmitResult {
        return log.tryEmit(.info, "event", .{ .field0 = @as(u64, @intCast(n)), .field1 = @as(u64, @intCast(n + 1)), .field2 = @as(u64, @intCast(n + 2)), .field3 = @as(u64, @intCast(n + 3)), .field4 = @as(u64, @intCast(n + 4)) });
    }
};

const shape: kron.Event = .{
    .level = .info,
    .scope = "reference",
    .message = "event",
    .timestamp_ns = 0,
    .fields = &.{ kron.kv("field0", @as(u64, 0)), kron.kv("field1", @as(u64, 1)), kron.kv("field2", @as(u64, 2)), kron.kv("field3", @as(u64, 3)), kron.kv("field4", @as(u64, 4)) },
};

fn emitSpool(log: anytype, n: usize) !kron.EmitResult {
    return log.tryEmit(.info, "event", .{
        .field0 = @as(u64, @intCast(n)),
        .field1 = @as(u64, @intCast(n + 1)),
        .field2 = @as(u64, @intCast(n + 2)),
        .field3 = @as(u64, @intCast(n + 3)),
        .field4 = @as(u64, @intCast(n + 4)),
    });
}

/// Single-producer non-durable mmap spool: render directly into the output
/// mapping and let one writer thread schedule dirty-page writeback. Warmup
/// records use `events..events+warmup`, matching the shared reference contract.
fn runSpool(io: std.Io, allocator: std.mem.Allocator, options: Options, lifecycle_start: std.Io.Timestamp) !void {
    const capacity_bytes = (options.events + options.warmup) * 512 + 4 * 1024 * 1024;
    const tsc = if (std.mem.eql(u8, options.spool_clock, "tsc")) kron.TscClock.create(allocator, io, .{}) catch null else null;
    defer if (tsc) |value| value.destroy();
    const clock = if (tsc) |value| value.clock() else kron.Clock{};
    const spool = try kron.MmapSpool.create(allocator, io, .{
        .path = options.output,
        .capacity_bytes = capacity_bytes,
        .min_level = .info,
        .idle = .sleep,
        .clock = clock,
        .timestamp_period = options.spool_timestamp_period,
    });
    var spool_live = true;
    defer if (spool_live) spool.destroy();
    const initialized = std.Io.Clock.awake.now(io);
    const log = spool.logger("reference");
    for (0..options.warmup) |index| _ = try emitSpool(log, options.events + index);
    try spool.flush(.written);
    const before_health = spool.health();
    const warmup_offset = spool.writtenBytes();
    const start = std.Io.Clock.awake.now(io);
    const samples = try allocator.alloc(u64, if (std.mem.eql(u8, options.phase, "sampled")) options.events else 0);
    defer allocator.free(samples);
    @memset(samples, 0);
    for (0..options.events) |index| {
        const before = if (samples.len != 0) std.Io.Clock.awake.now(io) else null;
        _ = try emitSpool(log, index);
        if (before) |value| samples[index] = elapsed(value, std.Io.Clock.awake.now(io));
    }
    const produced = std.Io.Clock.awake.now(io);
    try spool.flush(.written);
    const flushed = std.Io.Clock.awake.now(io);
    const measured_offset = spool.writtenBytes();
    try spool.shutdown();
    const end = std.Io.Clock.awake.now(io);
    const health = spool.health();
    const accepted = health.accepted - before_health.accepted;
    const written = health.written - before_health.written;
    if (accepted != options.events or written != options.events or health.pending != 0) return error.CounterMismatch;
    if (health.dropped_full != 0 or health.dropped_oversize != 0 or health.errors != 0) return error.DeliveryError;
    spool.destroy();
    spool_live = false;
    const cleaned = std.Io.Clock.awake.now(io);
    const artifact_bytes = (try std.Io.Dir.cwd().statFile(io, options.output, .{})).size;
    const written_bytes = measured_offset - warmup_offset;
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    var noop: [10000]u64 = undefined;
    for (&noop, 0..) |*value, index| {
        const before = std.Io.Clock.awake.now(io);
        std.mem.doNotOptimizeAway(index);
        value.* = elapsed(before, std.Io.Clock.awake.now(io));
    }
    std.mem.sort(u64, &noop, {}, std.sort.asc(u64));
    const result = .{
        .schema_version = 2,
        .status = "ok",
        .library = "kron",
        .frontend = "spool",
        .consumer_idle = "sleep",
        .version = "workspace",
        .strategy = "spool_mmap_async",
        .phase = options.phase,
        .mode = options.mode,
        .storage = options.storage,
        .prepared_schema = false,
        .consumer_batches_per_queue = options.consumer_batches,
        .backend_requested = "mmap_spool",
        .backend_selected = "mmap_spool",
        .metadata = "full",
        .events = options.events,
        .producers = options.producers,
        .warmup_events = options.warmup,
        .accepted = accepted,
        .written = written,
        .drop = @as(u64, 0),
        .final_pending = health.pending,
        .producer_wall_ns = elapsed(start, produced),
        .flush_ns = elapsed(produced, flushed),
        .shutdown_ns = elapsed(flushed, end),
        .cleanup_ns = elapsed(end, cleaned),
        .init_ns = elapsed(lifecycle_start, initialized),
        .preparation_ns = elapsed(initialized, start),
        .total_ns = elapsed(start, cleaned),
        .lifecycle_ns = elapsed(lifecycle_start, cleaned),
        .lifecycle_records_per_sec = @as(f64, @floatFromInt(options.events + options.warmup)) * 1e9 / @as(f64, @floatFromInt(elapsed(lifecycle_start, cleaned))),
        .written_bytes = written_bytes,
        .artifact_bytes = artifact_bytes,
        .written_records_per_sec = @as(f64, @floatFromInt(accepted)) * 1e9 / @as(f64, @floatFromInt(elapsed(start, cleaned))),
        .sample_count = samples.len,
        .p50_ns = quantile(samples, 500),
        .p99_ns = quantile(samples, 990),
        .p999_ns = quantile(samples, 999),
        .noop_clock_pair_p50_ns = quantile(&noop, 500),
        .noop_clock_pair_p99_ns = quantile(&noop, 990),
        .queue_policy = "block",
        .queue_slots = @as(usize, 0),
        .max_record_bytes = options.max_record_bytes,
        .file_buffer_bytes = @as(usize, 0),
        .sync_threshold_bytes = @as(usize, 1024 * 1024),
        .mapping_reserved_bytes = capacity_bytes,
        .has_process_crash_recovery = false,
        .queue_reserved_bytes = capacity_bytes,
        .journal_reserved_bytes = @as(u64, 0),
        .event_clock = "std.Io_dynamic_system",
        .optimize = @tagName(@import("builtin").mode),
    };
    var buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &buffer);
    try std.json.Stringify.value(result, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}

const SpoolWorker = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    options: *const Options,
    gate: *Gate,
    id: usize,
    capacity: usize,
    accepted: u64 = 0,
    written: u64 = 0,
    written_bytes: u64 = 0,
    produced_ns: u64 = 0,
    flushed_ns: u64 = 0,
    end_ns: u64 = 0,
    samples: []u64 = &.{},
    failure: ?anyerror = null,

    fn run(self: *SpoolWorker) void {
        self.runInner() catch |err| {
            self.failure = err;
        };
    }

    fn runInner(self: *SpoolWorker) !void {
        const io = self.io;
        const allocator = self.allocator;
        const options = self.options;
        const path = try std.fmt.allocPrint(allocator, "{s}.thread-{d}", .{ options.output, self.id });
        defer allocator.free(path);
        const spool = try kron.MmapSpool.create(allocator, io, .{
            .path = path,
            .capacity_bytes = self.capacity,
            .min_level = .info,
            .idle = .sleep,
            .clock = .{},
            .channel = @intCast(self.id + 1),
            .timestamp_period = options.spool_timestamp_period,
        });
        var live = true;
        defer if (live) spool.destroy();
        const log = spool.logger("reference");
        const warmup = share(options.warmup, options.producers, self.id);
        const events = share(options.events, options.producers, self.id);
        for (0..warmup) |index| _ = try emitSpool(log, options.events + index * options.producers + self.id);
        try spool.flush(.written);
        const before = spool.health();
        const warmup_offset = spool.writtenBytes();
        _ = self.gate.ready.fetchAdd(1, .acq_rel);
        std.Io.futexWake(io, u32, &self.gate.ready.raw, std.math.maxInt(u32));
        while (self.gate.start.load(.acquire) == 0) std.Io.futexWaitUncancelable(io, u32, &self.gate.start.raw, 0);
        const start = std.Io.Clock.awake.now(io);
        for (0..events) |index| {
            const before_call = if (self.samples.len != 0) std.Io.Clock.awake.now(io) else null;
            _ = try emitSpool(log, index * options.producers + self.id);
            if (before_call) |value| self.samples[index] = elapsed(value, std.Io.Clock.awake.now(io));
        }
        const produced = std.Io.Clock.awake.now(io);
        try spool.flush(.written);
        const flushed = std.Io.Clock.awake.now(io);
        const measured_offset = spool.writtenBytes();
        try spool.shutdown();
        const end = std.Io.Clock.awake.now(io);
        const health = spool.health();
        self.accepted = health.accepted - before.accepted;
        self.written = health.written - before.written;
        self.written_bytes = measured_offset - warmup_offset;
        self.produced_ns = elapsed(start, produced);
        self.flushed_ns = elapsed(start, flushed);
        self.end_ns = elapsed(start, end);
        if (self.accepted != events or self.written != events or health.pending != 0) return error.CounterMismatch;
        if (health.dropped_full != 0 or health.dropped_oversize != 0 or health.errors != 0) return error.DeliveryError;
        spool.destroy();
        live = false;
    }
};

/// Multi-producer non-durable spool: one spool and one output file per
/// producer thread, concatenated into the reference artifact after shutdown.
/// Each spool owns a distinct channel so per-spool sequences stay unique.
fn runSpoolMulti(io: std.Io, allocator: std.mem.Allocator, options: Options, lifecycle_start: std.Io.Timestamp) !void {
    const capacity_bytes = (options.events + options.warmup) * 512 + 4 * 1024 * 1024;
    var gate: Gate = .{};
    const workers = try allocator.alloc(SpoolWorker, options.producers);
    defer allocator.free(workers);
    const threads = try allocator.alloc(std.Thread, options.producers);
    defer allocator.free(threads);
    var sample_arrays: [64][]u64 = undefined;
    defer for (sample_arrays[0..options.producers]) |samples| allocator.free(samples);
    for (workers, 0..) |*worker, id| {
        const samples = try allocator.alloc(u64, if (std.mem.eql(u8, options.phase, "sampled")) share(options.events, options.producers, id) else 0);
        @memset(samples, 0);
        sample_arrays[id] = samples;
        worker.* = .{ .io = io, .allocator = allocator, .options = &options, .gate = &gate, .id = id, .capacity = capacity_bytes, .samples = samples };
        threads[id] = try std.Thread.spawn(.{}, SpoolWorker.run, .{worker});
    }
    while (gate.ready.load(.acquire) != options.producers) {
        const ready = gate.ready.load(.acquire);
        std.Io.futexWaitUncancelable(io, u32, &gate.ready.raw, ready);
    }
    const start = std.Io.Clock.awake.now(io);
    gate.start.store(1, .release);
    std.Io.futexWake(io, u32, &gate.start.raw, std.math.maxInt(u32));
    for (threads) |thread| thread.join();
    var max_produced: u64 = 0;
    var max_flushed: u64 = 0;
    var max_end: u64 = 0;
    var accepted: u64 = 0;
    var written: u64 = 0;
    var written_bytes: u64 = 0;
    for (workers) |worker| {
        if (worker.failure) |err| return err;
        max_produced = @max(max_produced, worker.produced_ns);
        max_flushed = @max(max_flushed, worker.flushed_ns);
        max_end = @max(max_end, worker.end_ns);
        accepted += worker.accepted;
        written += worker.written;
        written_bytes += worker.written_bytes;
    }
    // The multi-producer mode keeps one artifact per producer channel, like
    // the SPSC journal. The reference validator reads them in channel order.
    var artifact_bytes: u64 = 0;
    for (0..options.producers) |id| {
        const path = try std.fmt.allocPrint(allocator, "{s}.thread-{d}", .{ options.output, id });
        defer allocator.free(path);
        artifact_bytes += (try std.Io.Dir.cwd().statFile(io, path, .{})).size;
    }
    const cleaned = std.Io.Clock.awake.now(io);
    var combined = try allocator.alloc(u64, if (std.mem.eql(u8, options.phase, "sampled")) options.events else 0);
    defer allocator.free(combined);
    var combined_len: usize = 0;
    for (sample_arrays[0..options.producers]) |samples| {
        @memcpy(combined[combined_len..][0..samples.len], samples);
        combined_len += samples.len;
    }
    std.mem.sort(u64, combined, {}, std.sort.asc(u64));
    var noop: [10000]u64 = undefined;
    for (&noop, 0..) |*value, index| {
        const before = std.Io.Clock.awake.now(io);
        std.mem.doNotOptimizeAway(index);
        value.* = elapsed(before, std.Io.Clock.awake.now(io));
    }
    std.mem.sort(u64, &noop, {}, std.sort.asc(u64));
    const total_ns = elapsed(start, cleaned);
    const result = .{
        .schema_version = 2,
        .status = "ok",
        .library = "kron",
        .frontend = "spool",
        .consumer_idle = "sleep",
        .version = "workspace",
        .strategy = "spool_mmap_async",
        .phase = options.phase,
        .mode = options.mode,
        .storage = options.storage,
        .prepared_schema = false,
        .consumer_batches_per_queue = options.consumer_batches,
        .backend_requested = "mmap_spool",
        .backend_selected = "mmap_spool",
        .metadata = "full",
        .events = options.events,
        .producers = options.producers,
        .warmup_events = options.warmup,
        .accepted = accepted,
        .written = written,
        .drop = @as(u64, 0),
        .final_pending = @as(usize, 0),
        .producer_wall_ns = max_produced,
        .flush_ns = max_flushed - max_produced,
        .shutdown_ns = max_end - max_flushed,
        .cleanup_ns = total_ns - max_end,
        .init_ns = @as(u64, 0),
        .preparation_ns = elapsed(lifecycle_start, start),
        .total_ns = total_ns,
        .lifecycle_ns = elapsed(lifecycle_start, cleaned),
        .lifecycle_records_per_sec = @as(f64, @floatFromInt(options.events + options.warmup)) * 1e9 / @as(f64, @floatFromInt(elapsed(lifecycle_start, cleaned))),
        .written_bytes = written_bytes,
        .artifact_bytes = artifact_bytes,
        .written_records_per_sec = @as(f64, @floatFromInt(accepted)) * 1e9 / @as(f64, @floatFromInt(total_ns)),
        .sample_count = combined.len,
        .p50_ns = quantile(combined, 500),
        .p99_ns = quantile(combined, 990),
        .p999_ns = quantile(combined, 999),
        .noop_clock_pair_p50_ns = quantile(&noop, 500),
        .noop_clock_pair_p99_ns = quantile(&noop, 990),
        .queue_policy = "block",
        .queue_slots = @as(usize, 0),
        .max_record_bytes = options.max_record_bytes,
        .file_buffer_bytes = @as(usize, 0),
        .sync_threshold_bytes = @as(usize, 1024 * 1024),
        .mapping_reserved_bytes = capacity_bytes * options.producers,
        .has_process_crash_recovery = false,
        .queue_reserved_bytes = capacity_bytes * options.producers,
        .journal_reserved_bytes = @as(u64, 0),
        .event_clock = "std.Io_dynamic_system",
        .optimize = @tagName(@import("builtin").mode),
    };
    var buffer: [8192]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    try std.json.Stringify.value(result, .{}, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parse(arguments[1..]);
    const io = init.io;
    const allocator = init.gpa;
    const lifecycle_start = std.Io.Clock.awake.now(io);
    if (std.mem.eql(u8, options.mode, "spool")) {
        if (options.producers == 1) return runSpool(io, allocator, options, lifecycle_start);
        return runSpoolMulti(io, allocator, options, lifecycle_start);
    }
    const file = if (options.frontend == .runtime) try kron.FileSink.create(allocator, io, .{ .path = options.output, .buffer_bytes = 65536, .backend = options.backend, .append = false }) else null;
    var file_live = file != null;
    defer if (file_live) file.?.deinit();
    const journal_path = try std.fmt.allocPrint(allocator, "{s}.journal", .{options.output});
    defer allocator.free(journal_path);
    const is_spsc = std.mem.eql(u8, options.mode, "spsc");
    const memory = std.mem.eql(u8, options.storage, "memory");
    const managed = if (options.frontend == .managed) try kron.Logging.create(allocator, io, .{
        .max_total_queue_bytes = 32 * 1024 * 1024,
        .outputs = &.{.{
            .name = "reference",
            .target = .{ .file = .{ .path = options.output, .buffer_bytes = 65536, .backend = .portable, .append = false } },
            .mode = if (is_spsc) .spsc else .asynchronous,
            .queue = if (memory) .{ .memory = .{ .capacity = options.queue_slots, .max_record_bytes = options.max_record_bytes, .schema_capacity = if (options.schema) 2 else 0, .max_schema_bytes = 4096, .verify_crc = !options.text_format, .text_format = options.text_format } } else .{ .mmap = .{ .path = journal_path, .capacity = options.queue_slots, .max_record_bytes = options.max_record_bytes, .recover = false, .schema_capacity = if (options.schema) 2 else 0, .max_schema_bytes = 4096, .verify_crc = !options.text_format, .text_format = options.text_format } },
            .max_threads = options.producers,
            .max_journal_bytes = 32 * 1024 * 1024,
            .max_encoded_record_bytes = 512,
            .consumer_batches_per_queue = options.consumer_batches,
            .render_cache = options.render_cache,
            .render_cache_record_bytes = if (options.render_cache) options.max_record_bytes else 0,
            .format = .json,
            .overflow = .block,
        }},
    }) else null;
    const runtime = if (managed) |owner| try owner.runtime("reference") else try kron.Runtime.create(allocator, io, .{
        .submission = if (is_spsc) .low_latency else .asynchronous,
        .journal = if (!memory) .{ .path = journal_path, .capacity = options.queue_slots, .max_record_bytes = options.max_record_bytes, .recover = false, .schema_capacity = if (options.schema) 2 else 0, .max_schema_bytes = 4096, .verify_crc = !options.text_format, .text_format = options.text_format } else null,
        .memory_queue = if (memory) .{ .capacity = options.queue_slots, .max_record_bytes = options.max_record_bytes, .schema_capacity = if (options.schema) 2 else 0, .max_schema_bytes = 4096, .verify_crc = !options.text_format, .text_format = options.text_format } else null,
        .max_thread_channels = if (is_spsc) options.producers else 0,
        .thread_channel_capacity = options.queue_slots,
        .max_journal_bytes = 32 * 1024 * 1024,
        .max_encoded_record_bytes = 512,
        .overflow = .block,
        .idle = .sleep,
        .consumer_batches_per_queue = options.consumer_batches,
        .render_cache = options.render_cache,
        .render_cache_record_bytes = if (options.render_cache) options.max_record_bytes else 0,
        .routes = &.{.{ .name = "reference", .sink = file.?.sink(), .format = .json }},
    });
    var runtime_live = true;
    defer if (runtime_live) {
        if (managed) |owner| owner.destroy() else runtime.destroy();
    };
    // Same fixed-width correlation field in the C++ full JSON workload.
    // Set only before starting producers; it is not a queue/recovery change.
    runtime.session = std.math.maxInt(u64);
    const initialized = std.Io.Clock.awake.now(io);
    var gate: Gate = .{};
    var workers: [4]Worker = undefined;
    var threads: [4]?std.Thread = @splat(null);
    const samples = try allocator.alloc(u64, if (std.mem.eql(u8, options.phase, "sampled")) options.events else 0);
    defer allocator.free(samples);
    @memset(samples, 0);
    var offset: usize = 0;
    for (0..options.producers) |id| {
        const count = if (samples.len != 0) share(options.events, options.producers, id) else 0;
        workers[id] = .{ .runtime = runtime, .logging = managed, .options = options, .gate = &gate, .id = id, .samples = samples[offset..][0..count] };
        offset += count;
        threads[id] = try std.Thread.spawn(.{}, Worker.run, .{&workers[id]});
    }
    while (true) {
        const ready = gate.ready.load(.acquire);
        if (ready == options.producers) break;
        std.Io.futexWaitUncancelable(io, u32, &gate.ready.raw, ready);
    }
    if (managed) |owner| try owner.flush() else try runtime.flush(.written);
    const before_health = runtime.health();
    const before_bytes = (try std.Io.Dir.cwd().statFile(io, options.output, .{})).size;
    const start = std.Io.Clock.awake.now(io);
    gate.start.store(1, .release);
    std.Io.futexWake(io, u32, &gate.start.raw, std.math.maxInt(u32));
    for (&threads) |*thread| if (thread.*) |active| {
        active.join();
        thread.* = null;
    };
    const produced = std.Io.Clock.awake.now(io);
    if (managed) |owner| try owner.flush() else try runtime.flush(.written);
    const flushed = std.Io.Clock.awake.now(io);
    if (managed) |owner| try owner.shutdown() else try runtime.shutdown(.drain);
    const end = std.Io.Clock.awake.now(io);
    const health = runtime.health();
    const backend_selected = if (file) |sink| sink.selectedBackend() else BackendKind.portable;
    const idle_selected = runtime.idle;
    var accepted: u64 = 0;
    for (workers[0..options.producers]) |worker| {
        if (worker.failure) |err| return err;
        accepted += worker.accepted;
    }
    if (accepted != options.events or health.written - before_health.written != options.events or health.journal_pending != 0) return error.CounterMismatch;
    if (health.accepted - before_health.accepted != accepted or health.dropped_full != 0 or health.dropped_oversize != 0 or health.last_error != null) return error.DeliveryError;
    if (managed) |owner| owner.destroy() else runtime.destroy();
    runtime_live = false;
    if (file) |sink| sink.deinit();
    file_live = false;
    const cleaned = std.Io.Clock.awake.now(io);
    const artifact_bytes = (try std.Io.Dir.cwd().statFile(io, options.output, .{})).size;
    const written_bytes = artifact_bytes - before_bytes;
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    var noop: [10000]u64 = undefined;
    for (&noop, 0..) |*value, index| {
        const before = std.Io.Clock.awake.now(io);
        std.mem.doNotOptimizeAway(index);
        value.* = elapsed(before, std.Io.Clock.awake.now(io));
    }
    std.mem.sort(u64, &noop, {}, std.sort.asc(u64));
    const result = .{
        .schema_version = 2,
        .status = "ok",
        .library = "kron",
        .frontend = @tagName(options.frontend),
        .consumer_idle = @tagName(idle_selected),
        .version = "workspace",
        .strategy = "typed_capture_deferred_json",
        .phase = options.phase,
        .mode = options.mode,
        .storage = options.storage,
        .prepared_schema = options.schema,
        .consumer_batches_per_queue = options.consumer_batches,
        .backend_requested = @tagName(options.backend),
        .backend_selected = @tagName(backend_selected),
        .metadata = "full",
        .events = options.events,
        .producers = options.producers,
        .warmup_events = options.warmup,
        .accepted = accepted,
        .written = health.written - before_health.written,
        .drop = @as(u64, 0),
        .final_pending = health.journal_pending,
        .producer_wall_ns = elapsed(start, produced),
        .flush_ns = elapsed(produced, flushed),
        .shutdown_ns = elapsed(flushed, end),
        .cleanup_ns = elapsed(end, cleaned),
        .init_ns = elapsed(lifecycle_start, initialized),
        .preparation_ns = elapsed(initialized, start),
        .total_ns = elapsed(start, cleaned),
        .lifecycle_ns = elapsed(lifecycle_start, cleaned),
        .lifecycle_records_per_sec = @as(f64, @floatFromInt(options.events + options.warmup)) * 1e9 / @as(f64, @floatFromInt(elapsed(lifecycle_start, cleaned))),
        .written_bytes = written_bytes,
        .artifact_bytes = artifact_bytes,
        .written_records_per_sec = @as(f64, @floatFromInt(accepted)) * 1e9 / @as(f64, @floatFromInt(elapsed(start, cleaned))),
        .sample_count = samples.len,
        .p50_ns = quantile(samples, 500),
        .p99_ns = quantile(samples, 990),
        .p999_ns = quantile(samples, 999),
        .noop_clock_pair_p50_ns = quantile(&noop, 500),
        .noop_clock_pair_p99_ns = quantile(&noop, 990),
        .queue_policy = "block",
        .queue_slots = options.queue_slots,
        .max_record_bytes = options.max_record_bytes,
        .file_buffer_bytes = 65536,
        .has_process_crash_recovery = !memory,
        .queue_reserved_bytes = health.queue_reserved_bytes,
        .journal_reserved_bytes = health.journal_reserved_bytes,
        .event_clock = "std.Io_dynamic_system",
        .optimize = @tagName(@import("builtin").mode),
    };
    var buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &buffer);
    try std.json.Stringify.value(result, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}

test "reference backend selection is explicit and retains portable default and bounded collector budget" {
    const testing = std.testing;
    const default = try parse(&.{"--output=fixture.jsonl"});
    try testing.expectEqual(Frontend.runtime, default.frontend);
    try testing.expectEqual(Frontend.managed, (try parse(&.{ "--output=fixture.jsonl", "--frontend=managed" })).frontend);
    try testing.expectError(error.InvalidFrontend, parse(&.{ "--output=fixture.jsonl", "--frontend=unknown" }));
    try testing.expectError(error.ManagedBenchmarkRequiresPortable, parse(&.{ "--output=fixture.jsonl", "--frontend=managed", "--backend=linux_uring" }));
    try testing.expectEqual(BackendKind.portable, default.backend);
    try testing.expectEqual(@as(usize, 512), default.max_record_bytes);
    try testing.expectEqual(@as(usize, 8192), (try parse(&.{ "--output=fixture.jsonl", "--max-record-bytes=8192" })).max_record_bytes);
    try testing.expectError(error.InvalidBudget, parse(&.{ "--output=fixture.jsonl", "--max-record-bytes=0" }));
    for (std.enums.values(BackendKind)) |kind| {
        const argument = try std.fmt.allocPrint(testing.allocator, "--backend={s}", .{@tagName(kind)});
        defer testing.allocator.free(argument);
        try testing.expectEqual(kind, (try parse(&.{ "--output=fixture.jsonl", argument })).backend);
    }
    try testing.expectError(error.InvalidBackend, parse(&.{ "--output=fixture.jsonl", "--backend=imaginary" }));
    try testing.expectError(error.InvalidBudget, parse(&.{ "--output=fixture.jsonl", "--consumer-batches=0" }));
    try testing.expectError(error.InvalidBudget, parse(&.{ "--output=fixture.jsonl", "--consumer-batches=5" }));
}

fn parse(arguments: []const []const u8) !Options {
    var result: Options = .{};
    for (arguments) |argument| {
        const equal = std.mem.indexOfScalar(u8, argument, '=') orelse return error.InvalidArgument;
        const key = argument[0..equal];
        const value = argument[equal + 1 ..];
        if (std.mem.eql(u8, key, "--frontend")) {
            result.frontend = std.meta.stringToEnum(Frontend, value) orelse return error.InvalidFrontend;
        } else if (std.mem.eql(u8, key, "--output")) {
            result.output = value;
        } else if (std.mem.eql(u8, key, "--phase")) {
            result.phase = value;
        } else if (std.mem.eql(u8, key, "--mode")) {
            result.mode = value;
        } else if (std.mem.eql(u8, key, "--storage")) {
            result.storage = value;
        } else if (std.mem.eql(u8, key, "--schema")) {
            result.schema = if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else return error.InvalidSchema;
        } else if (std.mem.eql(u8, key, "--consumer-batches")) {
            result.consumer_batches = try std.fmt.parseInt(usize, value, 10);
            if (result.consumer_batches == 0 or result.consumer_batches > 4) return error.InvalidBudget;
        } else if (std.mem.eql(u8, key, "--backend")) {
            result.backend = std.meta.stringToEnum(BackendKind, value) orelse return error.InvalidBackend;
        } else if (std.mem.eql(u8, key, "--render-cache")) {
            result.render_cache = if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else return error.InvalidRenderCache;
        } else if (std.mem.eql(u8, key, "--text-format")) {
            result.text_format = if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else return error.InvalidTextFormat;
        } else if (std.mem.eql(u8, key, "--spool-clock")) {
            if (!std.mem.eql(u8, value, "native") and !std.mem.eql(u8, value, "tsc")) return error.InvalidClock;
            result.spool_clock = value;
        } else if (std.mem.eql(u8, key, "--spool-timestamp-period")) {
            result.spool_timestamp_period = try std.fmt.parseInt(usize, value, 10);
            if (result.spool_timestamp_period == 0 or result.spool_timestamp_period > 1024) return error.InvalidOptions;
        } else {
            const count = try std.fmt.parseInt(usize, value, 10);
            if (std.mem.eql(u8, key, "--events")) {
                result.events = count;
            } else if (std.mem.eql(u8, key, "--producers")) {
                result.producers = count;
            } else if (std.mem.eql(u8, key, "--warmup")) {
                result.warmup = count;
            } else if (std.mem.eql(u8, key, "--queue-slots")) {
                result.queue_slots = count;
            } else if (std.mem.eql(u8, key, "--max-record-bytes")) {
                if (count != 512 and count != 8192) return error.InvalidBudget;
                result.max_record_bytes = count;
            } else return error.UnknownArgument;
        }
    }
    if (result.output.len == 0 or result.events == 0 or result.events > 1000000 or result.warmup > 1000000 or
        (result.producers != 1 and result.producers != 4) or result.queue_slots == 0 or result.queue_slots > 65536 or
        (!std.mem.eql(u8, result.mode, "async") and !std.mem.eql(u8, result.mode, "spsc") and !std.mem.eql(u8, result.mode, "spool")) or
        (!std.mem.eql(u8, result.storage, "memory") and !std.mem.eql(u8, result.storage, "mmap")) or
        (!std.mem.eql(u8, result.phase, "sampled") and !std.mem.eql(u8, result.phase, "batch"))) return error.InvalidOptions;
    if (result.frontend == .managed and result.backend != .portable) return error.ManagedBenchmarkRequiresPortable;
    if (std.mem.eql(u8, result.mode, "spool") and
        (!std.mem.eql(u8, result.storage, "mmap") or result.schema or
            result.frontend != .runtime or result.render_cache or result.text_format)) return error.InvalidOptions;
    return result;
}
fn share(total: usize, producers: usize, id: usize) usize {
    return total / producers + @intFromBool(id < total % producers);
}
fn elapsed(start: std.Io.Timestamp, end: std.Io.Timestamp) u64 {
    return @intCast(@max(0, start.durationTo(end).toNanoseconds()));
}
fn quantile(samples: []const u64, thousandths: usize) ?u64 {
    return if (samples.len == 0) null else samples[(samples.len * thousandths + 999) / 1000 - 1];
}
