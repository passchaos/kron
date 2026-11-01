//! The same logical event/attributes as reference.cpp, using public kron APIs.
const std = @import("std");
const kron = @import("kron");
const Observer = struct {
    const Metrics = struct { calls: usize = 0, unchanged: usize = 0 };
    var original: std.Io = undefined;
    var target: ?*const u32 = null;
    var metrics: [4]Metrics = @splat(.{});
    threadlocal var current: ?*Metrics = null;
    threadlocal var journal: ?*kron.Journal = null;
    fn wait(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
        if (current) |metric| {
            if (ptr == target or ptr == (if (@hasField(@TypeOf(@as(kron.Journal, undefined).single), "space_epoch")) &journal.?.single.space_epoch.raw else target)) {
                const before = journal.?.writtenTarget();
                metric.calls += 1;
                original.vtable.futexWaitUncancelable(userdata, ptr, expected);
                if (journal.?.writtenTarget() == before) metric.unchanged += 1;
                return;
            }
        }
        original.vtable.futexWaitUncancelable(userdata, ptr, expected);
    }
};
const BackendKind = @TypeOf(@as(kron.FileSink.Options, .{ .path = "" }).backend);
const Options = struct {
    output: []const u8 = "",
    events: usize = 10000,
    producers: usize = 1,
    warmup: usize = 1000,
    queue_slots: usize = 256,
    phase: []const u8 = "sampled",
    mode: []const u8 = "async",
    storage: []const u8 = "mmap",
    schema: bool = false,
    consumer_batches: usize = 4,
    backend: BackendKind = .portable,
};

const Gate = struct {
    ready: std.atomic.Value(u32) = .init(0),
    start: std.atomic.Value(u32) = .init(0),
};
const Worker = struct {
    runtime: *kron.Runtime,
    options: Options,
    gate: *Gate,
    id: usize,
    samples: []u64,
    accepted: u64 = 0,
    failure: ?anyerror = null,

    fn run(self: *Worker) void {
        Observer.current = &Observer.metrics[self.id];
        Observer.journal = self.runtime.journal;
        defer Observer.current = null;
        if (std.mem.eql(u8, self.options.mode, "spsc")) {
            const log = self.runtime.attachThread(.{ .scope = "reference" }) catch |err| {
                self.failure = err;
                self.wait();
                return;
            };
            Observer.journal = log.owner.producer_token.journal;
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

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parse(arguments[1..]);
    Observer.original = init.io;
    var io_vtable = init.io.vtable.*;
    io_vtable.futexWaitUncancelable = Observer.wait;
    const io: std.Io = .{ .userdata = init.io.userdata, .vtable = &io_vtable };
    const allocator = init.gpa;
    const lifecycle_start = std.Io.Clock.awake.now(io);
    const file = try kron.FileSink.create(allocator, io, .{ .path = options.output, .buffer_bytes = 65536, .backend = options.backend, .append = false });
    var file_live = true;
    defer if (file_live) file.deinit();
    const journal_path = try std.fmt.allocPrint(allocator, "{s}.journal", .{options.output});
    defer allocator.free(journal_path);
    const is_spsc = std.mem.eql(u8, options.mode, "spsc");
    const memory = std.mem.eql(u8, options.storage, "memory");
    const runtime = try kron.Runtime.create(allocator, io, .{
        .submission = if (is_spsc) .low_latency else .asynchronous,
        .journal = if (!memory) .{ .path = journal_path, .capacity = options.queue_slots, .max_record_bytes = 512, .recover = false, .schema_capacity = if (options.schema) 2 else 0, .max_schema_bytes = 4096 } else null,
        .memory_queue = if (memory) .{ .capacity = options.queue_slots, .max_record_bytes = 512, .schema_capacity = if (options.schema) 2 else 0, .max_schema_bytes = 4096 } else null,
        .max_thread_channels = if (is_spsc) options.producers else 0,
        .thread_channel_capacity = options.queue_slots,
        .max_journal_bytes = 32 * 1024 * 1024,
        .max_encoded_record_bytes = 512,
        .overflow = .block,
        .idle = .sleep,
        .consumer_batches_per_queue = options.consumer_batches,
        .routes = &.{.{ .name = "reference", .sink = file.sink(), .format = .json }},
    });
    var runtime_live = true;
    defer if (runtime_live) runtime.destroy();
    // Same fixed-width correlation field in the C++ full JSON workload.
    // Set only before starting producers; it is not a queue/recovery change.
    runtime.session = std.math.maxInt(u64);
    Observer.target = &runtime.progress_epoch.raw;
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
        workers[id] = .{ .runtime = runtime, .options = options, .gate = &gate, .id = id, .samples = samples[offset..][0..count] };
        offset += count;
        threads[id] = try std.Thread.spawn(.{}, Worker.run, .{&workers[id]});
    }
    while (true) {
        const ready = gate.ready.load(.acquire);
        if (ready == options.producers) break;
        std.Io.futexWaitUncancelable(io, u32, &gate.ready.raw, ready);
    }
    try runtime.flush(.written);
    const before_health = runtime.health();
    const before_bytes = file.writtenBytes();
    const start = std.Io.Clock.awake.now(io);
    gate.start.store(1, .release);
    std.Io.futexWake(io, u32, &gate.start.raw, std.math.maxInt(u32));
    for (&threads) |*thread| if (thread.*) |active| {
        active.join();
        thread.* = null;
    };
    const produced = std.Io.Clock.awake.now(io);
    try runtime.flush(.written);
    const flushed = std.Io.Clock.awake.now(io);
    try runtime.shutdown(.drain);
    const end = std.Io.Clock.awake.now(io);
    const health = runtime.health();
    const artifact_bytes = file.writtenBytes();
    const written_bytes = artifact_bytes - before_bytes;
    const backend_selected = file.selectedBackend();
    var accepted: u64 = 0;
    for (workers[0..options.producers]) |worker| {
        if (worker.failure) |err| return err;
        accepted += worker.accepted;
    }
    if (accepted != options.events or health.written - before_health.written != options.events or health.journal_pending != 0) return error.CounterMismatch;
    if (health.accepted - before_health.accepted != accepted or health.dropped_full != 0 or health.dropped_oversize != 0 or health.last_error != null) return error.DeliveryError;
    runtime.destroy();
    runtime_live = false;
    file.deinit();
    file_live = false;
    const cleaned = std.Io.Clock.awake.now(io);
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
        .max_record_bytes = 512,
        .file_buffer_bytes = 65536,
        .has_process_crash_recovery = !memory,
        .queue_reserved_bytes = health.queue_reserved_bytes,
        .journal_reserved_bytes = health.journal_reserved_bytes,
        .event_clock = "std.Io_dynamic_system",
        .optimize = @tagName(@import("builtin").mode),
    };
    for (Observer.metrics[0..options.producers], 0..) |metric, producer| std.debug.print("QUEUE_WAIT producer={d} calls={d} unchanged_written={d}\n", .{ producer, metric.calls, metric.unchanged });
    var buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &buffer);
    try std.json.Stringify.value(result, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}

test "reference backend selection is explicit and retains portable default and bounded collector budget" {
    const testing = std.testing;
    const default = try parse(&.{"--output=fixture.jsonl"});
    try testing.expectEqual(BackendKind.portable, default.backend);
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
        if (std.mem.eql(u8, key, "--output")) {
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
            } else return error.UnknownArgument;
        }
    }
    if (result.output.len == 0 or result.events == 0 or result.events > 1000000 or result.warmup > 1000000 or
        (result.producers != 1 and result.producers != 4) or result.queue_slots == 0 or result.queue_slots > 65536 or
        (!std.mem.eql(u8, result.mode, "async") and !std.mem.eql(u8, result.mode, "spsc")) or
        (!std.mem.eql(u8, result.storage, "memory") and !std.mem.eql(u8, result.storage, "mmap")) or
        (!std.mem.eql(u8, result.phase, "sampled") and !std.mem.eql(u8, result.phase, "batch"))) return error.InvalidOptions;
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
