const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const args = @import("args.zig");
const statistics = @import("statistics.zig");

/// Same instrumentation on every output. Written records are counted only
/// after the underlying sink's complete-write barrier succeeds. Runtime owns
/// whole-record serialization; these fields are read after join + final flush.
pub const CountedSink = struct {
    child: kron.Sink,
    accepted_records: u64 = 0,
    written_records: u64 = 0,
    accepted_bytes: u64 = 0,
    written_bytes: u64 = 0,

    pub fn sink(self: *CountedSink) kron.Sink {
        return .{ .context = self, .vtable = &vtable, .supports_durable = self.child.supports_durable, .recovery_identity = self.child.recovery_identity };
    }

    fn write(context: *anyopaque, record: []const u8) anyerror!void {
        const self: *CountedSink = @ptrCast(@alignCast(context));
        try self.child.writeRecord(record);
        self.accepted_records += 1;
        self.accepted_bytes += record.len;
    }

    fn flush(context: *anyopaque) anyerror!void {
        const self: *CountedSink = @ptrCast(@alignCast(context));
        try self.child.flush();
        self.written_records = self.accepted_records;
        self.written_bytes = self.accepted_bytes;
    }

    fn sync(context: *anyopaque) anyerror!void {
        const self: *CountedSink = @ptrCast(@alignCast(context));
        try self.child.sync();
        self.written_records = self.accepted_records;
        self.written_bytes = self.accepted_bytes;
    }

    const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = sync };
};

pub const Counts = struct {
    attempted: u64 = 0,
    accepted: u64 = 0,
    filtered: u64 = 0,
    sampled: u64 = 0,
    dropped_full: u64 = 0,
    dropped_oversize: u64 = 0,
    rejected_closing: u64 = 0,
    emit_errors: u64 = 0,

    pub fn add(self: *Counts, other: Counts) void {
        inline for (@typeInfo(Counts).@"struct".fields) |field| @field(self, field.name) += @field(other, field.name);
    }

    fn observe(self: *Counts, result: kron.EmitResult) void {
        self.attempted += 1;
        switch (result) {
            inline else => |tag| @field(self, @tagName(tag)) += 1,
        }
    }
};

pub const Gate = struct {
    ready: std.atomic.Value(u32) = .init(0),
    start: std.atomic.Value(u32) = .init(0),
    abort: std.atomic.Value(bool) = .init(false),

    pub fn waitReady(self: *Gate, io: std.Io, count: usize) void {
        while (true) {
            const ready = self.ready.load(.acquire);
            if (ready == count) return;
            std.Io.futexWaitUncancelable(io, u32, &self.ready.raw, ready);
        }
    }

    pub fn release(self: *Gate, io: std.Io) void {
        self.start.store(1, .release);
        std.Io.futexWake(io, u32, &self.start.raw, std.math.maxInt(u32));
    }
};

pub const Worker = struct {
    runtime: *kron.Runtime,
    io: std.Io,
    options: args.Options,
    gate: *Gate,
    id: usize,
    events: usize,
    warmup: usize,
    samples: []u64,
    sample_count: usize = 0,
    long_string: []const u8,
    counts: Counts = .{},
    warmup_attempted: u64 = 0,
    warmup_error: ?anyerror = null,
    failure: ?anyerror = null,
    cpu_clock_available: bool,
    cpu_ns: ?u64 = null,

    pub fn run(self: *Worker) void {
        switch (self.options.clock) {
            .dynamic => self.runDynamic(),
            .std_io => self.runStatic(kron.StandardClock),
            .native => self.runStatic(kron.NativeClock),
            .none => self.runStatic(kron.ZeroClock),
        }
    }

    fn runDynamic(self: *Worker) void {
        if (self.options.mode == .spsc) {
            const log = self.runtime.attachThread(.{ .scope = "benchmark" }) catch |err| {
                self.warmup_error = err;
                self.failure = err;
                self.readyAndWait();
                return;
            };
            defer log.detach() catch |err| {
                self.failure = err;
            };
            if (self.options.schema) {
                var fields: [10]kron.schema.FieldSchema = undefined;
                const binding = self.runtime.prewarmThreadMetadata(@intCast(log.owner.control_index + 1), self.metadata(&fields)) catch |err| {
                    self.preparationFailed(err);
                    return;
                };
                const prepared = self.runtime.threadLoggerWithSchema(log, binding) catch |err| {
                    self.preparationFailed(err);
                    return;
                };
                self.runLogger(prepared);
            } else self.runLogger(log);
        } else if (self.options.schema) {
            var fields: [10]kron.schema.FieldSchema = undefined;
            const binding = self.runtime.prewarmMetadata(self.metadata(&fields)) catch |err| {
                self.preparationFailed(err);
                return;
            };
            const prepared = self.runtime.loggerWithSchema(binding) catch |err| {
                self.preparationFailed(err);
                return;
            };
            self.runLogger(prepared);
        } else self.runLogger(self.runtime.scoped("benchmark"));
    }

    fn preparationFailed(self: *Worker, err: anyerror) void {
        self.warmup_error = err;
        self.failure = err;
        self.readyAndWait();
    }

    /// Metadata includes static field kinds/keys, never sample values. The
    /// ordinary dynamic message remains copied into every accepted event.
    fn metadata(self: *const Worker, storage: *[10]kron.schema.FieldSchema) kron.schema.EventMeta {
        const mask = if (self.options.payload == .numeric) kron.schema.kindMask(.unsigned) else kron.schema.kindMask(.string);
        inline for (0..10) |index| storage[index] = .{ .key = std.fmt.comptimePrint("field{d}", .{index}), .kind_mask = mask };
        return .{ .scope = "benchmark", .message = null, .fields = storage[0..self.options.fields] };
    }

    fn runStatic(self: *Worker, comptime ClockProvider: type) void {
        if (self.options.mode == .spsc) {
            const log = self.runtime.attachThreadWithClock(ClockProvider, .{ .scope = "benchmark" }) catch |err| {
                self.warmup_error = err;
                self.failure = err;
                self.readyAndWait();
                return;
            };
            defer log.detach() catch |err| {
                self.failure = err;
            };
            self.runLogger(log);
        } else self.runLogger(self.runtime.loggerWithClock(ClockProvider, "benchmark"));
    }

    fn readyAndWait(self: *Worker) void {
        _ = self.gate.ready.fetchAdd(1, .acq_rel);
        std.Io.futexWake(self.io, u32, &self.gate.ready.raw, std.math.maxInt(u32));
        while (self.gate.start.load(.acquire) == 0) std.Io.futexWaitUncancelable(self.io, u32, &self.gate.start.raw, 0);
    }

    fn runLogger(self: *Worker, log: anytype) void {
        for (0..self.warmup) |index| {
            self.warmup_attempted += 1;
            _ = self.emit(log, index) catch |err| {
                self.warmup_error = err;
                break;
            };
        }
        self.readyAndWait();
        if (self.gate.abort.load(.acquire)) return;
        const cpu_start = if (self.cpu_clock_available) std.Io.Clock.cpu_thread.now(self.io) else null;
        var next_sample: usize = 0;
        for (0..self.events) |index| {
            const sampled = self.sample_count < self.samples.len and index == next_sample;
            const start = if (sampled) std.Io.Clock.awake.now(self.io) else null;
            const result = self.emit(log, index);
            if (start) |before| {
                self.samples[self.sample_count] = statistics.elapsed(before, std.Io.Clock.awake.now(self.io));
                self.sample_count += 1;
                next_sample = self.sample_count * self.events / self.samples.len;
            }
            const outcome = result catch |err| {
                self.counts.attempted += 1;
                self.counts.emit_errors += 1;
                self.failure = err;
                break;
            };
            self.counts.observe(outcome);
        }
        if (cpu_start) |before| self.cpu_ns = statistics.elapsed(before, std.Io.Clock.cpu_thread.now(self.io));
    }

    fn emit(self: *const Worker, log: anytype, index: usize) anyerror!kron.EmitResult {
        const message: []const u8 = switch (self.options.payload) {
            .numeric => "benchmark event",
            .short => "request completed",
            .long => self.long_string,
        };
        return switch (self.options.fields) {
            0 => log.tryEmit(.info, message, .{}),
            5 => log.tryEmit(.info, message, .{
                .field0 = self.value(index, 0),
                .field1 = self.value(index, 1),
                .field2 = self.value(index, 2),
                .field3 = self.value(index, 3),
                .field4 = self.value(index, 4),
            }),
            10 => log.tryEmit(.info, message, .{
                .field0 = self.value(index, 0),
                .field1 = self.value(index, 1),
                .field2 = self.value(index, 2),
                .field3 = self.value(index, 3),
                .field4 = self.value(index, 4),
                .field5 = self.value(index, 5),
                .field6 = self.value(index, 6),
                .field7 = self.value(index, 7),
                .field8 = self.value(index, 8),
                .field9 = self.value(index, 9),
            }),
            else => unreachable,
        };
    }

    fn value(self: *const Worker, index: usize, slot: usize) kron.Value {
        return switch (self.options.payload) {
            .numeric => .{ .unsigned = @as(u128, index) + slot + self.id },
            .short => .{ .string = "short-string-0123456789" },
            .long => .{ .string = self.long_string },
        };
    }
};

pub const Baseline = struct {
    distribution: statistics.Distribution,
    batch_ns_per_noop: f64,
    awake_resolution_ns: ?u64,

    pub fn measure(allocator: std.mem.Allocator, io: std.Io, count: usize) !Baseline {
        const samples = try allocator.alloc(u64, count);
        defer allocator.free(samples);
        @memset(samples, 0);
        for (samples, 0..) |*sample, index| {
            const before = std.Io.Clock.awake.now(io);
            std.mem.doNotOptimizeAway(index);
            sample.* = statistics.elapsed(before, std.Io.Clock.awake.now(io));
        }
        const before = std.Io.Clock.awake.now(io);
        for (0..count) |index| std.mem.doNotOptimizeAway(index);
        const batch_ns = statistics.elapsed(before, std.Io.Clock.awake.now(io));
        const resolution = std.Io.Clock.awake.resolution(io) catch null;
        return .{
            .distribution = statistics.Distribution.calculate(samples),
            .batch_ns_per_noop = @as(f64, @floatFromInt(batch_ns)) / @as(f64, @floatFromInt(count)),
            .awake_resolution_ns = if (resolution) |value| @intCast(@max(0, value.toNanoseconds())) else null,
        };
    }
};

pub fn clockAvailable(io: std.Io, clock: std.Io.Clock) bool {
    const resolution = clock.resolution(io) catch return false;
    return resolution.toNanoseconds() > 0;
}

pub const Cpu = struct {
    process_ns: ?u64 = null,
    producer_thread_ns: ?u64 = null,
    user_ns: ?u64 = null,
    system_ns: ?u64 = null,
    minor_faults: ?i64 = null,
    major_faults: ?i64 = null,
    voluntary_context_switches: ?i64 = null,
    involuntary_context_switches: ?i64 = null,
    max_rss_kib: ?u64 = null,
};

pub const CpuSnapshot = struct {
    time: ?std.Io.Timestamp,
    usage: if (builtin.os.tag == .linux) std.os.linux.rusage else void,

    pub fn take(io: std.Io, available: bool) CpuSnapshot {
        return .{
            .time = if (available) std.Io.Clock.cpu_process.now(io) else null,
            .usage = if (builtin.os.tag == .linux) std.posix.getrusage(std.os.linux.rusage.SELF) else {},
        };
    }

    pub fn difference(before: CpuSnapshot, after: CpuSnapshot) Cpu {
        var result: Cpu = .{ .process_ns = if (before.time) |start| statistics.elapsed(start, after.time.?) else null };
        if (builtin.os.tag == .linux) {
            result.user_ns = timevalNs(after.usage.utime) - timevalNs(before.usage.utime);
            result.system_ns = timevalNs(after.usage.stime) - timevalNs(before.usage.stime);
            result.minor_faults = after.usage.minflt - before.usage.minflt;
            result.major_faults = after.usage.majflt - before.usage.majflt;
            result.voluntary_context_switches = after.usage.nvcsw - before.usage.nvcsw;
            result.involuntary_context_switches = after.usage.nivcsw - before.usage.nivcsw;
            result.max_rss_kib = @intCast(@max(0, after.usage.maxrss));
        }
        return result;
    }
};

fn timevalNs(value: std.os.linux.timeval) u64 {
    return @intCast(@as(i128, value.sec) * 1_000_000_000 + @as(i128, value.usec) * 1000);
}

test "counted sink requires successful flush before acknowledging buffered records" {
    var memory = try kron.MemorySink.init(std.testing.allocator, 16);
    defer memory.deinit();
    var output: CountedSink = .{ .child = memory.sink() };
    try output.sink().writeRecord("one\n");
    try output.sink().writeRecord("two\n");
    try std.testing.expectEqual(@as(u64, 2), output.accepted_records);
    try std.testing.expectEqual(@as(u64, 0), output.written_records);
    memory.fail_flush = true;
    try std.testing.expectError(error.InjectedFlushFailure, output.sink().flush());
    try std.testing.expectEqual(@as(u64, 0), output.written_records);
    memory.fail_flush = false;
    try output.sink().flush();
    try std.testing.expectEqual(@as(u64, 2), output.written_records);
    try std.testing.expectEqual(@as(u64, 8), output.written_bytes);
}
