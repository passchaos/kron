const std = @import("std");
const kron = @import("kron");
pub const bargs = @import("args.zig");
const measurement = @import("measurement.zig");
const statistics = @import("statistics.zig");
const report = @import("report.zig");
const clock_selection = @import("clock_selection.zig");
const Options = bargs.Options;
const Phase = enum { sampled, batch };

pub fn main(init: std.process.Init) void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
    run(init, &stderr.interface) catch |err| {
        if (err != error.ReportedFailure) stderr.interface.print("kron-bench: {s}\n", .{@errorName(err)}) catch {};
        stderr.interface.flush() catch {};
        std.process.exit(1);
    };
}

fn run(init: std.process.Init, stderr: *std.Io.Writer) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const options = bargs.parse(arguments[1..]) catch |err| {
        try stderr.print("kron-bench: {s}\n{s}", .{ @errorName(err), bargs.usage });
        return error.ReportedFailure;
    };
    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    if (options.help) {
        try stdout.interface.writeAll(bargs.usage);
        try stdout.interface.flush();
        return;
    }
    const machine = report.Machine.detect();
    const baseline = try measurement.Baseline.measure(init.gpa, init.io, @min(options.events, options.samples));
    if (options.output == .csv) try report.Result.csvHeader(&stdout.interface);
    var successful = true;
    inline for (.{ Phase.sampled, Phase.batch }) |phase| {
        successful = try runPhase(init.gpa, init.io, options, phase, baseline, &machine, &stdout.interface) and successful;
        try stdout.interface.flush();
    }
    if (!successful) std.process.exit(2);
}

fn runPhase(allocator: std.mem.Allocator, io: std.Io, options: Options, phase: Phase, baseline: measurement.Baseline, machine: *const report.Machine, writer: *std.Io.Writer) !bool {
    var result = report.Result.init(options, @tagName(phase), baseline, machine);
    if (options.clock == .native and !kron.NativeClock.supported) return writeFailure(&result, options, writer, error.Unsupported);
    const work_dir = std.Io.Dir.cwd().createDirPathOpen(io, options.work_dir, .{ .open_options = .{ .iterate = true } }) catch |err| return writeFailure(&result, options, writer, err);
    defer work_dir.close(io);
    var identity: [8]u8 = undefined;
    try io.randomSecure(&identity);
    const stem = try std.fmt.allocPrint(allocator, "run-{x}-{s}", .{ std.mem.readInt(u64, &identity, .little), @tagName(phase) });
    defer allocator.free(stem);
    const file_name = try std.fmt.allocPrint(allocator, "{s}.log", .{stem});
    defer allocator.free(file_name);
    const journal_name = try std.fmt.allocPrint(allocator, "{s}.journal", .{stem});
    defer allocator.free(journal_name);
    const file_path = try std.fs.path.join(allocator, &.{ options.work_dir, file_name });
    defer allocator.free(file_path);
    const journal_path = try std.fs.path.join(allocator, &.{ options.work_dir, journal_name });
    defer allocator.free(journal_path);
    if (options.sink == .file) result.file_path = file_path;
    if (options.mode != .sync and options.storage == .mmap) result.journal_path = journal_path;

    const init_start = std.Io.Clock.awake.now(io);
    var memory: ?kron.MemorySink = null;
    defer if (memory) |*sink| sink.deinit();
    var file: ?*kron.FileSink = null;
    defer if (file) |sink| sink.deinit();
    const child = if (options.sink == .memory) blk: {
        memory = kron.MemorySink.init(allocator, options.memory_bytes) catch |err| return writeFailure(&result, options, writer, err);
        break :blk memory.?.sink();
    } else blk: {
        file = kron.FileSink.create(allocator, io, .{
            .path = file_name,
            .dir = work_dir,
            .buffer_bytes = options.buffer_bytes,
            .backend = std.meta.stringToEnum(@TypeOf(@as(kron.FileSink.Options, undefined).backend), @tagName(options.backend)).?,
            .queue_depth = options.queue_depth,
            .append = false,
        }) catch |err| return writeFailure(&result, options, writer, err);
        result.backend_selected = @tagName(file.?.selectedBackend());
        break :blk file.?.sink();
    };
    var counted: measurement.CountedSink = .{ .child = child };
    // Keep the injected callback runtime-selected for dynamic trials. Static
    // factories below bypass Runtime.clock for producer timestamp acquisition.
    var dynamic_clock = clock_selection.dynamicClock(identity[0] & 1 != 0);
    std.mem.doNotOptimizeAway(&dynamic_clock);
    const runtime = kron.Runtime.create(allocator, io, .{
        .submission = switch (options.mode) {
            .sync => .sync,
            .asynchronous => .asynchronous,
            .spsc => .low_latency,
        },
        .journal = if (options.mode != .sync and options.storage == .mmap) .{
            .path = journal_path,
            .capacity = options.journal_slots,
            .max_record_bytes = options.max_record_bytes,
            .recover = false,
            .schema_capacity = if (options.schema) 2 else 0,
            .max_schema_bytes = 4096,
        } else null,
        .memory_queue = if (options.mode != .sync and options.storage == .memory) .{
            .capacity = options.journal_slots,
            .max_record_bytes = options.max_record_bytes,
            .schema_capacity = if (options.schema) 2 else 0,
            .max_schema_bytes = 4096,
        } else null,
        .max_thread_channels = if (options.mode == .spsc) options.producers else 0,
        .thread_channel_capacity = options.channel_slots,
        .max_journal_bytes = options.journal_bytes,
        .idle = switch (options.idle) {
            .auto => null,
            .sleep => .sleep,
            .spin => .spin,
        },
        .clock = dynamic_clock,
        .routes = &.{.{ .name = "benchmark", .sink = counted.sink(), .format = std.meta.stringToEnum(kron.Format, @tagName(options.format)).?, .recovery_identity = if (options.sink == .memory) "benchmark-memory:v1" else null }},
        .overflow = std.meta.stringToEnum(@TypeOf(@as(kron.RuntimeOptions, undefined).overflow), @tagName(options.overflow)).?,
        .filter = if (options.filtered) "off" else "info",
        .max_encoded_record_bytes = options.max_record_bytes,
    }) catch |err| return writeFailure(&result, options, writer, err);
    defer runtime.destroy();
    result.queue_storage = @tagName(runtime.queueStorage());
    result.process_crash_recovery = runtime.queueStorage() == .mmap;
    result.idle_selected = @tagName(runtime.idle);
    result.runtime_init_ns = statistics.elapsed(init_start, std.Io.Clock.awake.now(io));

    const prepare_start = std.Io.Clock.awake.now(io);
    const long_string = try allocator.alloc(u8, options.string_bytes);
    defer allocator.free(long_string);
    const pattern = "0123456789abcdef\n\"\\";
    for (long_string, 0..) |*byte, index| byte.* = pattern[index % pattern.len];
    const sample_budget = if (phase == .sampled) @min(options.events, options.samples) else 0;
    const samples = try allocator.alloc(u64, sample_budget);
    defer allocator.free(samples);
    @memset(samples, 0);
    const thread_cpu_available = measurement.clockAvailable(io, .cpu_thread);
    const process_cpu_available = measurement.clockAvailable(io, .cpu_process);
    var gate: measurement.Gate = .{};
    var workers: [16]measurement.Worker = undefined;
    var threads: [16]?std.Thread = @splat(null);
    errdefer {
        gate.abort.store(true, .release);
        gate.release(io);
        for (&threads) |*thread| if (thread.*) |active| {
            active.join();
            thread.* = null;
        };
    }
    var sample_offset: usize = 0;
    for (0..options.producers) |index| {
        const quota = share(sample_budget, options.producers, index);
        workers[index] = .{
            .runtime = runtime,
            .io = io,
            .options = options,
            .gate = &gate,
            .id = index,
            .events = share(options.events, options.producers, index),
            .warmup = if (options.temperature == .warm) share(options.warmup_events, options.producers, index) else 0,
            .samples = samples[sample_offset..][0..quota],
            .long_string = long_string,
            .cpu_clock_available = thread_cpu_available,
        };
        sample_offset += quota;
        threads[index] = try std.Thread.spawn(.{}, measurement.Worker.run, .{&workers[index]});
    }
    gate.waitReady(io, options.producers);
    var failure: ?anyerror = null;
    for (workers[0..options.producers]) |worker| if (worker.warmup_error) |err| {
        if (failure == null) failure = err;
    };
    runtime.flush(.written) catch |err| {
        if (failure == null) failure = err;
    };
    if (failure != null) gate.abort.store(true, .release);
    const before = runtime.health();
    const before_sink = counted;
    for (workers[0..options.producers]) |worker| result.warmup_attempted += worker.warmup_attempted;
    result.warmup_written = before_sink.written_records;
    // Already drained warmup bytes do not consume the memory trial's budget.
    if (memory) |*sink| sink.clear();
    result.preparation_ns = statistics.elapsed(prepare_start, std.Io.Clock.awake.now(io));
    const cpu_before = measurement.CpuSnapshot.take(io, process_cpu_available);
    const start = std.Io.Clock.awake.now(io);
    gate.release(io);
    for (&threads) |*thread| if (thread.*) |active| {
        active.join();
        thread.* = null;
    };
    const producers_finished = std.Io.Clock.awake.now(io);
    result.producer_wall_ns = statistics.elapsed(start, producers_finished);
    runtime.flush(.written) catch |err| {
        if (failure == null) failure = err;
    };
    const written_finished = std.Io.Clock.awake.now(io);
    result.flush_written_ns = statistics.elapsed(producers_finished, written_finished);
    if (options.durable) {
        runtime.flush(.durable) catch |err| {
            if (failure == null) failure = err;
        };
        result.durable_flush_ns = statistics.elapsed(written_finished, std.Io.Clock.awake.now(io));
    }
    const shutdown_start = std.Io.Clock.awake.now(io);
    runtime.shutdown(.drain) catch |err| {
        if (failure == null) failure = err;
    };
    const end = std.Io.Clock.awake.now(io);
    result.shutdown_ns = statistics.elapsed(shutdown_start, end);
    result.total_ns = statistics.elapsed(start, end);
    const cpu = measurement.CpuSnapshot.difference(cpu_before, measurement.CpuSnapshot.take(io, process_cpu_available));
    const after = runtime.health();
    var counts: measurement.Counts = .{};
    var samples_actual: usize = 0;
    var cpu_threads: u64 = 0;
    for (workers[0..options.producers]) |worker| {
        counts.add(worker.counts);
        if (worker.failure) |err| if (failure == null) {
            failure = err;
        };
        if (worker.cpu_ns) |ns| cpu_threads += ns;
        // Compact sparse samples after failures before sorting the distribution.
        std.mem.copyForwards(u64, samples[samples_actual..][0..worker.sample_count], worker.samples[0..worker.sample_count]);
        samples_actual += worker.sample_count;
    }
    const distribution = statistics.Distribution.calculate(samples[0..samples_actual]);
    result.attempted = counts.attempted;
    result.accepted = counts.accepted;
    result.filtered = counts.filtered;
    result.sampled = counts.sampled;
    result.dropped_full = counts.dropped_full;
    result.dropped_oversize = counts.dropped_oversize;
    result.rejected_closing = counts.rejected_closing;
    result.emit_errors = counts.emit_errors;
    result.runtime_accepted = after.accepted - before.accepted;
    result.runtime_written = after.written - before.written;
    result.runtime_write_errors = after.write_errors - before.write_errors;
    result.sink_accepted_records = counted.accepted_records - before_sink.accepted_records;
    result.sink_written_records = counted.written_records - before_sink.written_records;
    result.sink_written_bytes = counted.written_bytes - before_sink.written_bytes;
    result.final_pending = after.journal_pending;
    result.journal_high_water = after.journal_high_water;
    result.producer_ns_per_attempt = if (counts.attempted == 0) null else @as(f64, @floatFromInt(result.producer_wall_ns.?)) / @as(f64, @floatFromInt(counts.attempted));
    result.written_records_per_sec = statistics.perSecond(result.sink_written_records, result.total_ns.?);
    result.written_bytes_per_sec = statistics.perSecond(result.sink_written_bytes, result.total_ns.?);
    result.latency_samples = distribution.count;
    result.producer_p50_ns = distribution.p50_ns;
    result.producer_p99_ns = distribution.p99_ns;
    result.producer_p999_ns = distribution.p999_ns;
    result.producer_max_ns = distribution.max_ns;
    result.producer_sample_mean_ns = distribution.mean_ns;
    result.cpu_process_ns = cpu.process_ns;
    result.cpu_producer_threads_ns = if (thread_cpu_available) cpu_threads else null;
    result.cpu_user_ns = cpu.user_ns;
    result.cpu_system_ns = cpu.system_ns;
    result.minor_faults = cpu.minor_faults;
    result.major_faults = cpu.major_faults;
    result.voluntary_context_switches = cpu.voluntary_context_switches;
    result.involuntary_context_switches = cpu.involuntary_context_switches;
    result.process_max_rss_kib = cpu.max_rss_kib;
    if (memory) |*sink| result.artifact_bytes = sink.written().len;
    if (file) |sink| {
        const stat = sink.file.stat(io) catch |err| return writeFailure(&result, options, writer, err);
        result.artifact_bytes = stat.size;
    }
    if (failure == null and (counts.attempted != options.events or result.accepted != result.runtime_accepted or result.runtime_written != result.sink_written_records or result.accepted != result.sink_written_records or result.final_pending != 0)) failure = error.CounterMismatch;
    if (failure == null) {
        const expected_bytes = result.sink_written_bytes + if (options.sink == .file) before_sink.written_bytes else @as(u64, 0);
        if (result.artifact_bytes != expected_bytes) failure = error.ByteCountMismatch;
    }
    if (failure) |err| result.fail(err);
    try result.write(options.output, writer);
    return failure == null;
}

fn writeFailure(result: *report.Result, options: Options, writer: *std.Io.Writer, err: anyerror) !bool {
    result.fail(err);
    try result.write(options.output, writer);
    return false;
}

fn share(total: usize, producers: usize, index: usize) usize {
    return total / producers + @intFromBool(index < total % producers);
}

test "event and sample budgets split across all producers exactly" {
    for ([_]usize{ 1, 4, 16 }) |producers| {
        var total: usize = 0;
        for (0..producers) |index| total += share(123, producers, index);
        try std.testing.expectEqual(@as(usize, 123), total);
    }
    _ = bargs;
    _ = statistics;
    _ = report;
    _ = measurement;
    _ = clock_selection;
}
