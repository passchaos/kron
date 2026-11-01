//! Public Runtime/attached-owner admission and complete JSON output benchmark.
//! It never casts the opaque configuration handle or reads mutable snapshots.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");

pub const Mode = enum { shared, attached };
pub const Phase = enum { admission, full };
pub const Idle = enum { sleep, spin };
pub const QueueStorage = enum { mmap, memory };
pub const Options = struct {
    mode: Mode = .shared,
    phase: Phase = .admission,
    events: usize = 10000,
    producers: usize = 1,
    warmup: usize = 1000,
    work_dir: []const u8 = ".zig-cache/kron-snapshot",
    /// Configuration replacements by producer zero after every N measured
    /// calls. This is an explicit cold-operation variant, not steady admission.
    replace_every: usize = 0,
    idle: Idle = .sleep,
    storage: QueueStorage = .mmap,
    help: bool = false,
};
pub const usage =
    \\Usage: kron-snapshot --mode=shared|attached --phase=admission|full
    \\  --events=10000 --producers=1|4|16 --warmup=1000 --work-dir=PATH
    \\  --replace-every=N   Optional replacement after N producer-zero calls.
    \\                     Replacement variant allows cold allocations; baseline
    \\                     fails any Runtime allocator call after preparation.
    \\  --help             Show this help. Output is one JSON result row.
    \\  --idle=sleep|spin   Same worker policy in both modes; default sleep.
    \\  --storage=mmap|memory  Same capture protocol, explicit persistence contract.
    \\
;

const CounterSink = struct {
    records: u64 = 0,
    bytes: u64 = 0,
    written: u64 = 0,
    written_bytes: u64 = 0,
    fn sink(self: *CounterSink) kron.Sink {
        return .{ .context = self, .vtable = &vtable, .recovery_identity = "snapshot-json-discard:v1" };
    }
    fn write(context: *anyopaque, record: []const u8) anyerror!void {
        const self: *CounterSink = @ptrCast(@alignCast(context));
        if (record.len < 3 or record[0] != '{' or record[record.len - 1] != '\n' or record[record.len - 2] != '}') return error.IncompleteJsonRecord;
        if (std.mem.indexOf(u8, record, "\"timestamp_ns\":0") == null or std.mem.indexOf(u8, record, "\"message\":\"snapshot event\"") == null) return error.UnexpectedJsonRecord;
        self.records += 1;
        self.bytes += record.len;
    }
    fn flush(context: *anyopaque) anyerror!void {
        const self: *CounterSink = @ptrCast(@alignCast(context));
        self.written = self.records;
        self.written_bytes = self.bytes;
    }
    fn sync(_: *anyopaque) anyerror!void {
        return error.UnsupportedDurability;
    }
    const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = sync };
};
const Gate = struct {
    ready: std.atomic.Value(u32) = .init(0),
    start: std.atomic.Value(u32) = .init(0),
    abort: std.atomic.Value(bool) = .init(false),
};
const Worker = struct {
    runtime: *kron.Runtime,
    sink: *CounterSink,
    options: Options,
    id: usize,
    gate: *Gate,
    samples: []u64,
    completed: u64 = 0,
    filtered: u64 = 0,
    dropped: u64 = 0,
    replacements: usize = 0,
    failure: ?anyerror = null,

    fn run(self: *Worker) void {
        if (self.options.mode == .attached) {
            const log = self.runtime.attachThreadWithClock(kron.ZeroClock, .{ .scope = "snapshot" }) catch |err| {
                self.failure = err;
                self.wait();
                return;
            };
            defer log.detach() catch |err| {
                self.failure = err;
            };
            self.runLogger(log);
        } else self.runLogger(self.runtime.loggerWithClock(kron.ZeroClock, "snapshot"));
    }
    fn wait(self: *Worker) void {
        _ = self.gate.ready.fetchAdd(1, .acq_rel);
        std.Io.futexWake(self.runtime.io, u32, &self.gate.ready.raw, std.math.maxInt(u32));
        while (self.gate.start.load(.acquire) == 0) std.Io.futexWaitUncancelable(self.runtime.io, u32, &self.gate.start.raw, 0);
    }
    fn call(self: *Worker, log: anytype, index: usize) !bool {
        if (self.options.phase == .admission) {
            switch (log.owner.begin(.info, "snapshot")) {
                .ready => {
                    log.owner.end();
                    return true;
                },
                .filtered, .sampled => {
                    self.filtered += 1;
                    return false;
                },
                .closed => return error.Closed,
            }
        }
        const result = try log.tryEmit(.info, "snapshot event", .{
            .field0 = @as(u64, @intCast(index + self.id)),
            .field1 = @as(u64, @intCast(index + self.id + 1)),
            .field2 = @as(u64, @intCast(index + self.id + 2)),
            .field3 = @as(u64, @intCast(index + self.id + 3)),
            .field4 = @as(u64, @intCast(index + self.id + 4)),
        });
        return switch (result) {
            .accepted => true,
            .filtered, .sampled => blk: {
                self.filtered += 1;
                break :blk false;
            },
            .dropped_full, .dropped_oversize => blk: {
                self.dropped += 1;
                break :blk false;
            },
            .rejected_closing => error.Closed,
        };
    }
    fn runLogger(self: *Worker, log: anytype) void {
        for (0..share(self.options.warmup, self.options.producers, self.id)) |index| {
            _ = self.call(log, index) catch |err| {
                self.failure = err;
                break;
            };
        }
        self.filtered = 0;
        self.dropped = 0;
        self.wait();
        if (self.failure != null or self.gate.abort.load(.acquire)) return;
        for (0..self.samples.len) |index| {
            const before = std.Io.Clock.awake.now(self.runtime.io);
            const completed = self.call(log, index) catch |err| {
                self.failure = err;
                return;
            };
            self.samples[index] = elapsed(before, std.Io.Clock.awake.now(self.runtime.io));
            self.completed += @intFromBool(completed);
            if (self.id == 0 and self.options.replace_every != 0 and (index + 1) % self.options.replace_every == 0) {
                _ = self.runtime.replaceConfiguration(&.{.{ .name = "snapshot", .sink = self.sink.sink(), .format = .json }}, .{}) catch |err| {
                    self.failure = err;
                    return;
                };
                self.replacements += 1;
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parse(argv[1..]);
    var stdout_buffer: [16384]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    if (options.help) {
        try stdout.interface.writeAll(usage);
        try stdout.interface.flush();
        return;
    }
    var runtime_allocator = std.testing.FailingAllocator.init(init.gpa, .{});
    var counter: CounterSink = .{};
    const directory = try std.Io.Dir.cwd().createDirPathOpen(init.io, options.work_dir, .{});
    defer directory.close(init.io);
    var random: [8]u8 = undefined;
    try init.io.randomSecure(&random);
    const path = try std.fmt.allocPrint(init.gpa, "{s}/snapshot-{x}.journal", .{ options.work_dir, std.mem.readInt(u64, &random, .little) });
    defer init.gpa.free(path);
    const before_init = std.Io.Clock.awake.now(init.io);
    const runtime = try kron.Runtime.create(runtime_allocator.allocator(), init.io, .{
        .submission = if (options.mode == .attached) .low_latency else .asynchronous,
        .journal = if (options.storage == .mmap) .{ .path = path, .capacity = 256, .max_record_bytes = 1024, .recover = false } else null,
        .memory_queue = if (options.storage == .memory) .{ .capacity = 256, .max_record_bytes = 1024 } else null,
        .max_thread_channels = if (options.mode == .attached) options.producers else 0,
        .thread_channel_capacity = 256,
        .max_journal_bytes = 32 * 1024 * 1024,
        .max_encoded_record_bytes = 1024,
        .idle = if (options.idle == .sleep) .sleep else .spin,
        .overflow = .block,
        .configuration_slots = 64,
        .routes = &.{.{ .name = "snapshot", .sink = counter.sink(), .format = .json }},
    });
    defer runtime.destroy();
    const init_ns = elapsed(before_init, std.Io.Clock.awake.now(init.io));
    const samples = try init.gpa.alloc(u64, options.events);
    defer init.gpa.free(samples);
    @memset(samples, 0);
    var workers: [16]Worker = undefined;
    var threads: [16]?std.Thread = @splat(null);
    var gate: Gate = .{};
    errdefer {
        gate.abort.store(true, .release);
        gate.start.store(1, .release);
        std.Io.futexWake(init.io, u32, &gate.start.raw, std.math.maxInt(u32));
        for (threads) |thread| if (thread) |t| t.join();
    }
    const preparation_start = std.Io.Clock.awake.now(init.io);
    var offset: usize = 0;
    for (0..options.producers) |id| {
        const count = share(options.events, options.producers, id);
        workers[id] = .{ .runtime = runtime, .sink = &counter, .options = options, .id = id, .gate = &gate, .samples = samples[offset..][0..count] };
        offset += count;
        threads[id] = try std.Thread.spawn(.{}, Worker.run, .{&workers[id]});
    }
    while (true) {
        const ready = gate.ready.load(.acquire);
        if (ready == options.producers) break;
        std.Io.futexWaitUncancelable(init.io, u32, &gate.ready.raw, ready);
    }
    try runtime.flush(.written);
    for (workers[0..options.producers]) |worker| if (worker.failure != null) gate.abort.store(true, .release);
    const before = runtime.health();
    const sink_before = counter;
    const allocations_before = runtime_allocator.allocations;
    if (options.replace_every == 0) {
        runtime_allocator.fail_index = runtime_allocator.alloc_index;
        runtime_allocator.resize_fail_index = runtime_allocator.resize_index;
    }
    const preparation_ns = elapsed(preparation_start, std.Io.Clock.awake.now(init.io));
    const begin = std.Io.Clock.awake.now(init.io);
    gate.start.store(1, .release);
    std.Io.futexWake(init.io, u32, &gate.start.raw, std.math.maxInt(u32));
    for (&threads) |*thread| if (thread.*) |t| {
        t.join();
        thread.* = null;
    };
    const produced = std.Io.Clock.awake.now(init.io);
    try runtime.flush(.written);
    const flushed = std.Io.Clock.awake.now(init.io);
    try runtime.shutdown(.drain);
    const end = std.Io.Clock.awake.now(init.io);
    const after = runtime.health();
    var completed: u64 = 0;
    var filtered: u64 = 0;
    var dropped: u64 = 0;
    var replacements: usize = 0;
    for (workers[0..options.producers]) |worker| {
        if (worker.failure) |err| return err;
        completed += worker.completed;
        filtered += worker.filtered;
        dropped += worker.dropped;
        replacements += worker.replacements;
    }
    const written = counter.written - sink_before.written;
    if (completed != options.events or after.journal_pending != 0 or filtered != 0 or dropped != 0 or after.write_errors != before.write_errors) return error.CounterMismatch;
    if (options.phase == .full and (written != completed or after.accepted - before.accepted != completed or after.written - before.written != completed)) return error.CounterMismatch;
    if (options.phase == .admission and (written != 0 or after.accepted != before.accepted or after.written != before.written)) return error.CounterMismatch;
    if (options.replace_every == 0 and (runtime_allocator.has_induced_failure or runtime_allocator.allocations != allocations_before)) return error.MeasurementAllocation;
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    var noop: [10000]u64 = undefined;
    for (&noop, 0..) |*sample, index| {
        const clock = std.Io.Clock.awake.now(init.io);
        std.mem.doNotOptimizeAway(index);
        sample.* = elapsed(clock, std.Io.Clock.awake.now(init.io));
    }
    std.mem.sort(u64, &noop, {}, std.sort.asc(u64));
    const result = .{
        .schema_version = 1,
        .status = "ok",
        .benchmark = "snapshot",
        .mode = @tagName(options.mode),
        .phase = @tagName(options.phase),
        .producers = options.producers,
        .events = options.events,
        .warmup = options.warmup,
        .completed = completed,
        .accepted = after.accepted - before.accepted,
        .written = written,
        .filtered = filtered,
        .drop = dropped,
        .final_pending = after.journal_pending,
        .init_ns = init_ns,
        .preparation_ns = preparation_ns,
        .producer_wall_ns = elapsed(begin, produced),
        .flush_ns = elapsed(produced, flushed),
        .shutdown_ns = elapsed(flushed, end),
        .total_ns = elapsed(begin, end),
        .calls_per_sec = @as(f64, @floatFromInt(completed)) * 1e9 / @as(f64, @floatFromInt(elapsed(begin, produced))),
        .completed_per_sec = @as(f64, @floatFromInt(completed)) * 1e9 / @as(f64, @floatFromInt(elapsed(begin, end))),
        .written_bytes = counter.written_bytes - sink_before.written_bytes,
        .sample_count = samples.len,
        .p50_ns = rank(samples, 500),
        .p99_ns = rank(samples, 990),
        .p999_ns = rank(samples, 999),
        .noop_p50_ns = rank(&noop, 500),
        .noop_p99_ns = rank(&noop, 990),
        .runtime_allocations_in_measurement = runtime_allocator.allocations - allocations_before,
        .no_allocations_in_measurement = runtime_allocator.allocations == allocations_before,
        .replace_every_thread0_calls = options.replace_every,
        .replacements = replacements,
        .steady_state = options.replace_every == 0,
        .global_snapshot_pin_metric = @as(?u64, null),
        .pin_metric_note = "opaque snapshot internals not inspected; no numeric pin count claimed",
        .event_clock = "ZeroClock",
        .field_count = if (options.phase == .full) @as(usize, 5) else 0,
        .sink = "counted_complete_json_discard",
        .queue_slots = 256,
        .channel_slots = 256,
        .max_record_bytes = 1024,
        .idle = @tagName(options.idle),
        .queue_storage = @tagName(runtime.queueStorage()),
        .process_crash_recovery = runtime.queueStorage() == .mmap,
        .zig_version = builtin.zig_version_string,
        .optimize = @tagName(builtin.mode),
        .target = @tagName(builtin.os.tag),
    };
    try std.json.Stringify.value(result, .{}, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}
fn elapsed(a: std.Io.Timestamp, b: std.Io.Timestamp) u64 {
    return @intCast(@max(0, a.durationTo(b).toNanoseconds()));
}
fn share(total: usize, producers: usize, id: usize) usize {
    return total / producers + @intFromBool(id < total % producers);
}
fn rank(samples: []const u64, fraction: usize) u64 {
    return samples[(samples.len * fraction + 999) / 1000 - 1];
}
pub fn parse(arguments: []const []const u8) !Options {
    var result: Options = .{};
    for (arguments) |argument| {
        if (std.mem.eql(u8, argument, "--help")) {
            result.help = true;
            continue;
        }
        const eq = std.mem.indexOfScalar(u8, argument, '=') orelse return error.InvalidArgument;
        const key = argument[0..eq];
        const value = argument[eq + 1 ..];
        if (std.mem.eql(u8, key, "--mode")) {
            result.mode = std.meta.stringToEnum(Mode, value) orelse return error.InvalidMode;
        } else if (std.mem.eql(u8, key, "--phase")) {
            result.phase = std.meta.stringToEnum(Phase, value) orelse return error.InvalidPhase;
        } else if (std.mem.eql(u8, key, "--work-dir")) {
            result.work_dir = value;
        } else if (std.mem.eql(u8, key, "--idle")) {
            result.idle = std.meta.stringToEnum(Idle, value) orelse return error.InvalidIdle;
        } else if (std.mem.eql(u8, key, "--storage")) {
            result.storage = std.meta.stringToEnum(QueueStorage, value) orelse return error.InvalidQueueStorage;
        } else {
            const count = try std.fmt.parseInt(usize, value, 10);
            if (std.mem.eql(u8, key, "--events")) {
                result.events = count;
            } else if (std.mem.eql(u8, key, "--producers")) {
                result.producers = count;
            } else if (std.mem.eql(u8, key, "--warmup")) {
                result.warmup = count;
            } else if (std.mem.eql(u8, key, "--replace-every")) {
                result.replace_every = count;
            } else return error.UnknownOption;
        }
    }
    if (!result.help and (result.events == 0 or result.events > 1000000 or result.warmup > 1000000 or (result.producers != 1 and result.producers != 4 and result.producers != 16) or result.work_dir.len == 0 or (result.replace_every != 0 and share(result.events, result.producers, 0) / result.replace_every > 32))) return error.InvalidBudget;
    return result;
}
test "snapshot benchmark admits bounded producer counts and explicit replacement variant" {
    const opts = try parse(&.{ "--mode=attached", "--phase=full", "--producers=16", "--replace-every=1000" });
    try std.testing.expectEqual(Mode.attached, opts.mode);
    try std.testing.expectEqual(Phase.full, opts.phase);
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--producers=3"}));
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--replace-every=1"}));
    try std.testing.expectEqual(QueueStorage.memory, (try parse(&.{"--storage=memory"})).storage);
    try std.testing.expectError(error.InvalidQueueStorage, parse(&.{"--storage=invalid"}));
}
