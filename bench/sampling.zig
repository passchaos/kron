//! Exact-budget global sampling, isolated from clocks, queues and encoders.
//! Batch time includes start wakeup and joins; no per-call latency is inferred.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const Sampler = kron.Sampler;

const Options = struct {
    attempts: usize = 10000,
    producers: usize = 4,
    repetitions: usize = 5,
};
const Gate = struct {
    ready: std.atomic.Value(u32) = .init(0),
    start: std.atomic.Value(u32) = .init(0),
    abort: std.atomic.Value(bool) = .init(false),
};
const Worker = struct {
    sampler: *Sampler,
    gate: *Gate,
    io: std.Io,
    attempts: usize,
    accepted: u64 = 0,

    fn run(self: *Worker) void {
        for (0..1000) |_| std.mem.doNotOptimizeAway(self.sampler.allow(0));
        _ = self.gate.ready.fetchAdd(1, .release);
        self.io.futexWake(u32, &self.gate.ready.raw, std.math.maxInt(u32));
        while (self.gate.start.load(.acquire) == 0) self.io.futexWaitUncancelable(u32, &self.gate.start.raw, 0);
        if (self.gate.abort.load(.acquire)) return;
        for (0..self.attempts) |_| {
            const allowed = self.sampler.allow(0);
            std.mem.doNotOptimizeAway(allowed);
            self.accepted += @intFromBool(allowed);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parse(arguments[1..]);
    if (builtin.single_threaded) return error.ThreadsUnavailable;
    var output_bytes: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_bytes);
    const Config = @typeInfo(@TypeOf(Sampler.init)).@"fn".params[0].type.?;
    const cases = [_]struct { name: []const u8, config: Config, expected: u64 }{
        .{ .name = "none", .config = .none, .expected = options.attempts },
        .{ .name = "every1", .config = .{ .every = 1 }, .expected = options.attempts },
        .{ .name = "every2", .config = .{ .every = 2 }, .expected = (options.attempts + 1) / 2 },
        .{ .name = "every3", .config = .{ .every = 3 }, .expected = (options.attempts + 2) / 3 },
        .{ .name = "every8", .config = .{ .every = 8 }, .expected = (options.attempts + 7) / 8 },
        .{ .name = "count", .config = .{ .count = 1024 }, .expected = @min(1024, options.attempts) },
        .{ .name = "token_bucket", .config = .{ .token_bucket = .{ .capacity = 1024, .refill_interval_ns = 10 } }, .expected = @min(1024, options.attempts) },
    };
    for (0..options.repetitions) |repetition| for (0..cases.len) |case_offset| {
        const index = if (repetition % 2 == 0) case_offset else cases.len - 1 - case_offset;
        const case = cases[index];
        var sampler = try Sampler.init(case.config);
        var gate: Gate = .{};
        var workers: [16]Worker = undefined;
        var threads: [16]?std.Thread = @splat(null);
        defer for (&threads) |*thread| if (thread.*) |handle| handle.join();
        errdefer {
            gate.abort.store(true, .release);
            gate.start.store(1, .release);
            init.io.futexWake(u32, &gate.start.raw, std.math.maxInt(u32));
        }
        for (0..options.producers) |producer| {
            workers[producer] = .{ .sampler = &sampler, .gate = &gate, .io = init.io, .attempts = options.attempts / options.producers + @intFromBool(producer < options.attempts % options.producers) };
            threads[producer] = try std.Thread.spawn(.{}, Worker.run, .{&workers[producer]});
        }
        while (true) {
            const ready = gate.ready.load(.acquire);
            if (ready == options.producers) break;
            init.io.futexWaitUncancelable(u32, &gate.ready.raw, ready);
        }
        // All users have stopped touching the shared object at the start gate.
        // Warmup does not spend the measured quota or alter the every-N phase.
        sampler = try Sampler.init(case.config);
        const started = std.Io.Clock.awake.now(init.io);
        gate.start.store(1, .release);
        init.io.futexWake(u32, &gate.start.raw, std.math.maxInt(u32));
        for (&threads) |*thread| if (thread.*) |handle| {
            handle.join();
            thread.* = null;
        };
        const total_ns = @as(u64, @intCast(@max(0, started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds())));
        var accepted: u64 = 0;
        for (workers[0..options.producers]) |worker| accepted += worker.accepted;
        if (accepted != case.expected) return error.SampleBudgetMismatch;
        const result = .{
            .status = "ok",
            .benchmark = "sampling",
            .case = case.name,
            .repetition = repetition,
            .producers = options.producers,
            .attempts = options.attempts,
            .accepted = accepted,
            .expected_accepted = case.expected,
            .total_ns = total_ns,
            .attempts_per_second = if (total_ns == 0) @as(f64, 0) else @as(f64, @floatFromInt(options.attempts)) * 1e9 / @as(f64, @floatFromInt(total_ns)),
            .fake_monotonic_ns = 0,
            .per_call_clock_reads = false,
            .sampler_bytes = @sizeOf(Sampler),
            .sampler_alignment = @alignOf(Sampler),
            .optimize = @tagName(builtin.mode),
            .zig_version = builtin.zig_version_string,
            .scope = "sampler only; start wakeup and joins included; no logging throughput or per-call tail claim",
        };
        try std.json.Stringify.value(result, .{}, &output.interface);
        try output.interface.writeByte('\n');
        try output.interface.flush();
    };
}

fn parse(arguments: []const []const u8) !Options {
    var result: Options = .{};
    for (arguments) |argument| {
        const equal = std.mem.indexOfScalar(u8, argument, '=') orelse return error.InvalidArgument;
        const key = argument[0..equal];
        const number = try std.fmt.parseInt(usize, argument[equal + 1 ..], 10);
        if (std.mem.eql(u8, key, "--attempts")) result.attempts = number else if (std.mem.eql(u8, key, "--producers")) result.producers = number else if (std.mem.eql(u8, key, "--repetitions")) result.repetitions = number else return error.UnknownOption;
    }
    if (result.attempts == 0 or result.attempts > 10000 or (result.producers != 1 and result.producers != 4 and result.producers != 16) or result.repetitions < 5 or result.repetitions > 9) return error.InvalidBudget;
    return result;
}

test "sampling benchmark requires bounded repeated exact-budget cases" {
    const options = try parse(&.{ "--producers=16", "--attempts=10000", "--repetitions=9" });
    try std.testing.expectEqual(@as(usize, 16), options.producers);
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--repetitions=1"}));
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--attempts=10001"}));
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--producers=3"}));
}
