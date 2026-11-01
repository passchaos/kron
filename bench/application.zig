//! Application work through public kron APIs, with a same-work no-log baseline.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
pub const workload = @import("application/workload.zig");
const stats = @import("statistics.zig");

pub const Mode = enum { none, shared, spsc };
pub const Storage = enum { memory, mmap };
pub const Options = struct {
    output: []const u8 = "",
    mode: Mode = .none,
    storage: Storage = .memory,
    work: workload.Kind = .compute,
    operations: usize = 12000,
    producers: usize = 4,
    warmup: usize = 1000,
    every: usize = 16,
    sampled: bool = false,
};

pub fn parse(args: []const []const u8) !Options {
    var result: Options = .{};
    for (args) |arg| {
        const split = std.mem.indexOfScalar(u8, arg, '=') orelse return error.InvalidArgument;
        const key = arg[0..split];
        const value = arg[split + 1 ..];
        if (std.mem.eql(u8, key, "--output")) result.output = value else if (std.mem.eql(u8, key, "--mode")) result.mode = std.meta.stringToEnum(Mode, value) orelse return error.InvalidMode else if (std.mem.eql(u8, key, "--storage")) result.storage = std.meta.stringToEnum(Storage, value) orelse return error.InvalidStorage else if (std.mem.eql(u8, key, "--work")) result.work = std.meta.stringToEnum(workload.Kind, value) orelse return error.InvalidWork else if (std.mem.eql(u8, key, "--operations")) result.operations = try std.fmt.parseInt(usize, value, 10) else if (std.mem.eql(u8, key, "--producers")) result.producers = try std.fmt.parseInt(usize, value, 10) else if (std.mem.eql(u8, key, "--warmup")) result.warmup = try std.fmt.parseInt(usize, value, 10) else if (std.mem.eql(u8, key, "--every")) result.every = try std.fmt.parseInt(usize, value, 10) else if (std.mem.eql(u8, key, "--sampled")) result.sampled = if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else return error.InvalidSampled else return error.InvalidArgument;
    }
    if (result.output.len == 0 or result.operations == 0 or result.operations > 1000000 or result.warmup > 10000 or
        (result.producers != 1 and result.producers != 4 and result.producers != 16) or result.every == 0 or result.every > 1024 or result.operations < result.producers) return error.InvalidOptions;
    return result;
}

const Gate = struct {
    ready: std.atomic.Value(u32) = .init(0),
    start: std.atomic.Value(u32) = .init(0),
    cancel: std.atomic.Value(bool) = .init(false),
};

const Worker = struct {
    runtime: ?*kron.Runtime,
    io: std.Io,
    options: Options,
    gate: *Gate,
    producer: usize,
    table: []u64,
    samples: []u64,
    completed: usize = 0,
    log_attempts: usize = 0,
    warmup_logs: usize = 0,
    checksum_sum: u64 = 0,
    checksum_xor: u64 = 0,
    failure: ?anyerror = null,

    fn run(self: *@This()) void {
        self.execute() catch |err| {
            self.failure = err;
            // Every successfully spawned worker participates in preparation,
            // including failed attachment, so main can release/join it.
            if (self.gate.start.load(.acquire) == 0) self.wait();
        };
    }

    fn execute(self: *@This()) !void {
        if (self.options.mode == .spsc) {
            const log = try self.runtime.?.attachThread(.{ .scope = "application" });
            defer log.detach() catch |err| {
                self.failure = err;
            };
            try self.runWork(log);
        } else if (self.options.mode == .shared) {
            try self.runWork(self.runtime.?.scoped("application"));
        } else try self.runWork(@as(void, {}));
    }

    fn wait(self: *@This()) void {
        _ = self.gate.ready.fetchAdd(1, .acq_rel);
        self.io.futexWake(u32, &self.gate.ready.raw, std.math.maxInt(u32));
        while (self.gate.start.load(.acquire) == 0) self.io.futexWaitUncancelable(u32, &self.gate.start.raw, 0);
    }

    fn emit(self: *@This(), log: anytype, id: u64, value: u64, warmup: bool) !void {
        if (@TypeOf(log) == void) return;
        if (try log.tryEmit(.info, "request complete", .{ .request_id = id, .result = value, .producer = @as(u64, self.producer), .rounds = @as(u64, workload.rounds(self.options.work)), .warmup = warmup }) != .accepted) return error.UnexpectedLogOutcome;
    }

    fn runWork(self: *@This(), log: anytype) !void {
        workload.initialize(self.table, self.producer);
        for (0..workload.share(self.options.warmup, self.options.producers, self.producer)) |index| {
            const id = self.options.operations + index * self.options.producers + self.producer;
            const value = workload.request(self.table, self.options.work, id);
            if (id % self.options.every == 0 and @TypeOf(log) != void) {
                try self.emit(log, id, value, true);
                self.warmup_logs += 1;
            }
        }
        // Reset application state before the timed region. All modes perform
        // exactly this same initialization/work and retain its result checksum.
        workload.initialize(self.table, self.producer);
        self.wait();
        if (self.gate.cancel.load(.acquire)) return;
        for (0..workload.share(self.options.operations, self.options.producers, self.producer)) |index| {
            const start = if (self.options.sampled) std.Io.Clock.awake.now(self.io) else null;
            const id = index * self.options.producers + self.producer;
            const value = workload.request(self.table, self.options.work, id);
            self.checksum_sum +%= value;
            self.checksum_xor ^= value;
            if (id % self.options.every == 0 and @TypeOf(log) != void) {
                try self.emit(log, id, value, false);
                self.log_attempts += 1;
            }
            if (start) |timestamp| self.samples[index] = elapsed(timestamp, std.Io.Clock.awake.now(self.io));
            self.completed += 1;
        }
    }
};

fn elapsed(start: std.Io.Timestamp, finish: std.Io.Timestamp) u64 {
    return @intCast(finish.nanoseconds - start.nanoseconds);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parse(args[1..]);
    const io = init.io;
    const begin_lifecycle = std.Io.Clock.awake.now(io);
    var file: ?*kron.FileSink = null;
    defer if (file) |sink| sink.deinit();
    var runtime: ?*kron.Runtime = null;
    defer if (runtime) |owner| owner.destroy();
    const journal_path = try std.fmt.allocPrint(init.gpa, "{s}.journal", .{options.output});
    defer init.gpa.free(journal_path);
    var runtime_allocator = std.testing.FailingAllocator.init(init.gpa, .{});
    if (options.mode != .none) {
        file = try kron.FileSink.create(runtime_allocator.allocator(), io, .{ .path = options.output, .backend = .portable, .buffer_bytes = 65536, .append = false });
        runtime = try kron.Runtime.create(runtime_allocator.allocator(), io, .{
            .submission = if (options.mode == .spsc) .low_latency else .asynchronous,
            .memory_queue = if (options.storage == .memory) .{ .capacity = 256, .max_record_bytes = 512 } else null,
            .journal = if (options.storage == .mmap) .{ .path = journal_path, .capacity = 256, .max_record_bytes = 512, .recover = false } else null,
            .max_thread_channels = if (options.mode == .spsc) options.producers else 0,
            .thread_channel_capacity = 256,
            .max_journal_bytes = 32 * 1024 * 1024,
            .max_encoded_record_bytes = 512,
            .idle = .sleep,
            .overflow = .block,
            .routes = &.{.{ .name = "application", .sink = file.?.sink(), .format = .json }},
        });
        runtime.?.session = std.math.maxInt(u64);
        // Prepared channel attachment uses existing storage. Public runtime
        // logging/flush/shutdown must never allocate after this point.
        runtime_allocator.fail_index = runtime_allocator.alloc_index;
        runtime_allocator.resize_fail_index = runtime_allocator.resize_index;
    }
    const initialized = std.Io.Clock.awake.now(io);
    var gate: Gate = .{};
    var workers: [16]Worker = undefined;
    var threads: [16]std.Thread = undefined;
    var spawned: usize = 0;
    var joined = false;
    const tables = try init.gpa.alloc(u64, options.producers * workload.tableWords(options.work));
    defer init.gpa.free(tables);
    const samples = try init.gpa.alloc(u64, if (options.sampled) options.operations else 0);
    defer init.gpa.free(samples);
    // Join before freeing borrowed application tables/sample slices on error.
    defer if (!joined) {
        gate.cancel.store(true, .release);
        gate.start.store(1, .release);
        io.futexWake(u32, &gate.start.raw, std.math.maxInt(u32));
        for (threads[0..spawned]) |thread| thread.join();
    };
    @memset(samples, 0);
    var sample_offset: usize = 0;
    for (0..options.producers) |producer| {
        const count = if (options.sampled) workload.share(options.operations, options.producers, producer) else 0;
        workers[producer] = .{ .runtime = runtime, .io = io, .options = options, .gate = &gate, .producer = producer, .table = tables[producer * workload.tableWords(options.work) ..][0..workload.tableWords(options.work)], .samples = samples[sample_offset..][0..count] };
        sample_offset += count;
        threads[producer] = try std.Thread.spawn(.{}, Worker.run, .{&workers[producer]});
        spawned += 1;
    }
    while (gate.ready.load(.acquire) != options.producers) {
        const seen = gate.ready.load(.acquire);
        if (seen != options.producers) io.futexWaitUncancelable(u32, &gate.ready.raw, seen);
    }
    for (workers[0..spawned]) |worker| if (worker.failure) |err| return err;
    if (runtime) |owner| try owner.flush(.written);
    const warmup_health = if (runtime) |owner| owner.health() else null;
    const start = std.Io.Clock.awake.now(io);
    gate.start.store(1, .release);
    io.futexWake(u32, &gate.start.raw, std.math.maxInt(u32));
    for (threads[0..spawned]) |thread| thread.join();
    joined = true;
    const produced = std.Io.Clock.awake.now(io);
    for (workers[0..spawned]) |worker| if (worker.failure) |err| return err;
    if (runtime) |owner| try owner.flush(.written);
    const flushed = std.Io.Clock.awake.now(io);
    const health = if (runtime) |owner| owner.health() else null;
    if (runtime) |owner| try owner.shutdown(.drain);
    const stopped = std.Io.Clock.awake.now(io);
    if (runtime) |owner| owner.destroy();
    runtime = null;
    const backend = if (file) |sink| @tagName(sink.selectedBackend()) else "none";
    if (file) |sink| sink.deinit();
    file = null;
    const cleaned = std.Io.Clock.awake.now(io);
    var checksum_sum: u64 = 0;
    var checksum_xor: u64 = 0;
    var completed: usize = 0;
    var attempts: usize = 0;
    var warmup_logs: usize = 0;
    var checksums: [16]struct { producer: usize, operations: usize, sum: u64, xor: u64 } = undefined;
    for (workers[0..spawned], 0..) |worker, index| {
        checksum_sum +%= worker.checksum_sum;
        checksum_xor ^= worker.checksum_xor;
        completed += worker.completed;
        attempts += worker.log_attempts;
        warmup_logs += worker.warmup_logs;
        checksums[index] = .{ .producer = index, .operations = worker.completed, .sum = worker.checksum_sum, .xor = worker.checksum_xor };
    }
    if (completed != options.operations or runtime_allocator.has_induced_failure) return error.InvalidCompletion;
    if (health) |value| if (value.accepted - warmup_health.?.accepted != attempts or value.written - warmup_health.?.written != attempts or value.journal_pending != 0 or value.dropped_full != 0 or value.last_error != null) return error.InvalidDelivery;
    const distribution = stats.Distribution.calculate(samples);
    const total_ns = elapsed(start, cleaned);
    const report = .{
        .schema_version = 1,
        .status = "ok",
        .mode = @tagName(options.mode),
        .storage = if (options.mode == .none) "none" else @tagName(options.storage),
        .work = @tagName(options.work),
        .operations = options.operations,
        .completed = completed,
        .producers = options.producers,
        .warmup_operations = options.warmup,
        .log_every = options.every,
        .sampled = options.sampled,
        .log_attempts = attempts,
        .warmup_logs = warmup_logs,
        .accepted = if (health) |h| h.accepted - warmup_health.?.accepted else 0,
        .written = if (health) |h| h.written - warmup_health.?.written else 0,
        .drop = if (health) |h| h.dropped_full else 0,
        .pending = if (health) |h| h.journal_pending else 0,
        .checksum_sum = checksum_sum,
        .checksum_xor = checksum_xor,
        .worker_checksums = checksums[0..spawned],
        .work_table_bytes = tables.len * @sizeOf(u64),
        .work_rounds = workload.rounds(options.work),
        .sample_bytes = samples.len * @sizeOf(u64),
        .queue_backing_bytes = if (health) |h| h.queue_reserved_bytes else 0,
        .journal_backing_bytes = if (health) |h| h.journal_reserved_bytes else 0,
        .runtime_init_ns = elapsed(begin_lifecycle, initialized),
        .preparation_ns = elapsed(initialized, start),
        .producer_ns = elapsed(start, produced),
        .flush_ns = elapsed(produced, flushed),
        .shutdown_ns = elapsed(flushed, stopped),
        .cleanup_ns = elapsed(stopped, cleaned),
        .total_ns = total_ns,
        .lifecycle_ns = elapsed(begin_lifecycle, cleaned),
        .application_operations_per_sec = @as(f64, @floatFromInt(completed)) * 1e9 / @as(f64, @floatFromInt(total_ns)),
        .p50_operation_ns = distribution.p50_ns,
        .p99_operation_ns = distribution.p99_ns,
        .p999_operation_ns = distribution.p999_ns,
        .backend_selected = backend,
        .system_event_clock = options.mode != .none,
        .metadata = "full",
        .fields_per_event = 5,
        .runtime_allocations_after_init = 0,
        .has_process_crash_recovery = options.mode != .none and options.storage == .mmap,
        .queue_slots = if (options.mode == .none) @as(usize, 0) else 256,
        .max_record_bytes = if (options.mode == .none) @as(usize, 0) else 512,
        .file_buffer_bytes = if (options.mode == .none) @as(usize, 0) else 65536,
        .consumer_quanta = if (options.mode == .none) @as(usize, 0) else 4,
        .optimize = @tagName(builtin.mode),
        .zig_version = builtin.zig_version_string,
    };
    var stdout_bytes: [16384]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &stdout_bytes);
    try std.json.Stringify.value(report, .{}, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}

test "application benchmark bounds inputs and distinguishes no-log and sampled modes" {
    try std.testing.expectEqual(Mode.none, (try parse(&.{"--output=fixture"})).mode);
    for ([_][]const u8{ "--producers=0", "--producers=17", "--operations=0", "--operations=1000001", "--every=0", "--every=1025", "--warmup=10001" }) |arg| {
        try std.testing.expectError(error.InvalidOptions, parse(&.{ "--output=fixture", arg }));
    }
    try std.testing.expectError(error.InvalidMode, parse(&.{ "--output=fixture", "--mode=unknown" }));
    try std.testing.expectError(error.InvalidSampled, parse(&.{ "--output=fixture", "--sampled=maybe" }));
    try std.testing.expect((try parse(&.{ "--output=fixture", "--sampled=true", "--producers=16", "--work=cache" })).sampled);
}

test {
    _ = workload;
}
