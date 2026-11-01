//! Clock-only dispatch microbenchmark. No logger, queue, formatter or sink is
//! present. Report direct native clock selection separately from std.Io.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const statistics = @import("statistics.zig");
const measurement = @import("measurement.zig");
const selection = @import("clock_selection.zig");
const Mode = enum { dynamic, std_io, native, none };

pub const Options = struct {
    iterations: usize = 10_000,
    warmup: usize = 1_000,
    repetitions: usize = 5,
    mode: ?Mode = null,
    help: bool = false,
};

pub const usage =
    \\Usage: kron-dispatch [--iterations=N] [--warmup=N] [--repetitions=N]
    \\                     [--mode=dynamic|std_io|native|none] [--help]
    \\Batch timing of wall-clock reads with a result checksum; JSON Lines output.
    \\Default: all four modes, 10000 iterations, 1000 excluded warmup reads,
    \\five repetitions with rotating order. Maximum: 10000000 iterations,
    \\1000000 warmup reads, 20 repetitions. Native is a separate clock provider.
    \\
;

const Result = struct {
    schema_version: u32 = 1,
    benchmark: []const u8 = "clock_dispatch",
    mode: []const u8,
    provider: []const u8,
    clock_semantics: []const u8,
    status: []const u8 = "ok",
    error_name: ?[]const u8 = null,
    repetition: usize,
    order_index: usize,
    iterations: usize,
    warmup_reads: usize,
    elapsed_ns: ?u64 = null,
    ns_per_call: ?f64 = null,
    checksum: u64 = 0,
    timestamp_reads: usize,
    clock_pair_p50_ns: ?u64,
    clock_pair_p99_ns: ?u64,
    clock_pair_mean_ns: ?f64,
    noop_batch_ns_per_call: f64,
    awake_resolution_ns: ?u64,
    measurement_clock: []const u8 = "std.Io.Clock.awake",
    dynamic_callback_from_runtime_factory: bool,
    native_provider_may_fallback_to_std_io: bool,
    zig_version: []const u8 = builtin.zig_version_string,
    optimize: []const u8 = @tagName(builtin.mode),
    target_arch: []const u8 = @tagName(builtin.cpu.arch),
    target_os: []const u8 = @tagName(builtin.os.tag),
};

pub fn main(init: std.process.Init) void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
    run(init, &stderr.interface) catch |err| {
        if (err != error.ReportedFailure) stderr.interface.print("kron-dispatch: {s}\n", .{@errorName(err)}) catch {};
        stderr.interface.flush() catch {};
        std.process.exit(1);
    };
}

fn run(init: std.process.Init, stderr: *std.Io.Writer) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const options = parse(arguments[1..]) catch |err| {
        try stderr.print("kron-dispatch: {s}\n{s}", .{ @errorName(err), usage });
        return error.ReportedFailure;
    };
    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    if (options.help) {
        try stdout.interface.writeAll(usage);
        try stdout.interface.flush();
        return;
    }
    const baseline = try measurement.Baseline.measure(init.gpa, init.io, @min(options.iterations, 10_000));
    const runtime_selector = @as(u96, @bitCast(std.Io.Clock.real.now(init.io).nanoseconds)) & 1 != 0;
    var dynamic = selection.dynamicClock(runtime_selector);
    // A memory escape also prevents whole-program analysis from specializing
    // the factory result. Verify generated code when publishing dispatch claims.
    std.mem.doNotOptimizeAway(&dynamic);
    const modes = [_]Mode{ .dynamic, .std_io, .native, .none };
    var unsupported = false;
    for (0..options.repetitions) |repetition| {
        const count: usize = if (options.mode != null) 1 else modes.len;
        for (0..count) |order_index| {
            const mode = options.mode orelse modes[(order_index + repetition) % modes.len];
            var result: Result = .{
                .mode = @tagName(mode),
                .provider = switch (mode) {
                    .dynamic, .std_io => "std.Io",
                    .native => "kron.NativeClock",
                    .none => "kron.ZeroClock",
                },
                .clock_semantics = if (mode == .none) "disabled_timestamp" else "POSIX_REALTIME_nanoseconds_clamped_i64",
                .repetition = repetition,
                .order_index = order_index,
                .iterations = options.iterations,
                .warmup_reads = options.warmup,
                .timestamp_reads = if (mode == .none) 0 else options.iterations,
                .clock_pair_p50_ns = baseline.distribution.p50_ns,
                .clock_pair_p99_ns = baseline.distribution.p99_ns,
                .clock_pair_mean_ns = baseline.distribution.mean_ns,
                .noop_batch_ns_per_call = baseline.batch_ns_per_noop,
                .awake_resolution_ns = baseline.awake_resolution_ns,
                .dynamic_callback_from_runtime_factory = mode == .dynamic,
                .native_provider_may_fallback_to_std_io = mode == .native,
            };
            if (mode == .native and !kron.NativeClock.supported) {
                result.status = "unsupported";
                result.error_name = "Unsupported";
                unsupported = true;
            } else {
                inline for (modes) |candidate| if (mode == candidate) {
                    // Warmup includes provider initialization/vDSO lookup and
                    // is deliberately excluded from the measured batch.
                    std.mem.doNotOptimizeAway(readBatch(candidate, dynamic, init.io, options.warmup));
                    const before = std.Io.Clock.awake.now(init.io);
                    result.checksum = readBatch(candidate, dynamic, init.io, options.iterations);
                    result.elapsed_ns = statistics.elapsed(before, std.Io.Clock.awake.now(init.io));
                    result.ns_per_call = @as(f64, @floatFromInt(result.elapsed_ns.?)) / @as(f64, @floatFromInt(options.iterations));
                };
            }
            try std.json.Stringify.value(result, .{}, &stdout.interface);
            try stdout.interface.writeByte('\n');
        }
        try stdout.interface.flush();
    }
    if (unsupported and options.mode == .native) std.process.exit(2);
}

fn readBatch(comptime mode: Mode, dynamic: kron.Clock, io: std.Io, iterations: usize) u64 {
    var checksum: u64 = 0;
    for (0..iterations) |_| {
        const value: i64 = switch (mode) {
            .dynamic => dynamic.realNow(io),
            .std_io => kron.StandardClock.realNow(io),
            .native => kron.NativeClock.realNow(io),
            .none => kron.ZeroClock.realNow(io),
        };
        // Keep a per-call observation even for ZeroClock, whose checksum alone
        // could otherwise become a constant and allow removal of the loop.
        std.mem.doNotOptimizeAway(value);
        checksum +%= @as(u64, @bitCast(value));
    }
    std.mem.doNotOptimizeAway(checksum);
    return checksum;
}

pub fn parse(arguments: []const []const u8) !Options {
    var options: Options = .{};
    for (arguments) |argument| {
        if (std.mem.eql(u8, argument, "--help")) {
            options.help = true;
            continue;
        }
        if (!std.mem.startsWith(u8, argument, "--")) return error.UnknownOption;
        const equal = std.mem.indexOfScalar(u8, argument, '=') orelse return error.MissingOptionValue;
        const key = argument[2..equal];
        const value = argument[equal + 1 ..];
        if (value.len == 0) return error.MissingOptionValue;
        if (std.mem.eql(u8, key, "mode")) {
            options.mode = std.meta.stringToEnum(Mode, value) orelse return error.InvalidMode;
            continue;
        }
        const count = std.fmt.parseInt(usize, value, 10) catch return error.InvalidInteger;
        if (std.mem.eql(u8, key, "iterations")) {
            options.iterations = count;
        } else if (std.mem.eql(u8, key, "warmup")) {
            options.warmup = count;
        } else if (std.mem.eql(u8, key, "repetitions")) {
            options.repetitions = count;
        } else return error.UnknownOption;
    }
    if (!options.help and (options.iterations == 0 or options.iterations > 10_000_000 or options.warmup > 1_000_000 or options.repetitions == 0 or options.repetitions > 20)) return error.InvalidBudget;
    return options;
}

test "clock microbenchmark parses bounded trials and preserves no-clock control" {
    const options = try parse(&.{ "--iterations=123", "--warmup=7", "--repetitions=3", "--mode=none" });
    try std.testing.expectEqual(@as(usize, 123), options.iterations);
    try std.testing.expectEqual(@as(?Mode, .none), options.mode);
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--iterations=0"}));
    try std.testing.expectError(error.InvalidMode, parse(&.{"--mode=foo"}));
    try std.testing.expectError(error.MissingOptionValue, parse(&.{"--iterations"}));
}

test "clock batches consume each std.Io timestamp and preserve no-clock checksum" {
    const Fake = struct {
        calls: usize = 0,
        fn now(context: ?*anyopaque, clock: std.Io.Clock) std.Io.Timestamp {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            std.debug.assert(clock == .real);
            self.calls += 1;
            return .{ .nanoseconds = 123 };
        }
    };
    var fake: Fake = .{};
    var vtable = std.testing.io.vtable.*;
    vtable.now = Fake.now;
    const io: std.Io = .{ .userdata = &fake, .vtable = &vtable };
    const dynamic = selection.dynamicClock(false);
    try std.testing.expectEqual(@as(u64, 123 * 37), readBatch(.dynamic, dynamic, io, 37));
    try std.testing.expectEqual(@as(usize, 37), fake.calls);
    try std.testing.expectEqual(@as(u64, 123 * 37), readBatch(.std_io, dynamic, io, 37));
    try std.testing.expectEqual(@as(usize, 74), fake.calls);
    try std.testing.expectEqual(@as(u64, 0), readBatch(.none, dynamic, io, 37));
    try std.testing.expectEqual(@as(usize, 74), fake.calls);
}
