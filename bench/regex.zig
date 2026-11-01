//! Business-shaped byte regexes and complete synchronous JSON delivery.
//! Isolated match timings are batch averages, never producer percentiles.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");

const Options = struct { iterations: usize = 10000, repetitions: usize = 5 };
const Case = struct {
    name: []const u8,
    pattern: []const u8,
    inputs: [4][]const u8,
    expected: [4]bool,
};
const cases = [_]Case{
    .{ .name = "http_path", .pattern = "^/api/(users|orders)/[0-9]+$", .inputs = .{ "/api/users/12345", "/health", "/api/orders/7", "/api/users/x" }, .expected = .{ true, false, true, false } },
    .{ .name = "severity_message", .pattern = "(warn|error): [a-z]+", .inputs = .{ "request_id=abc error: timeout in upstream", "completed info: success", "warn: retrying after timeout", "request_id=def" }, .expected = .{ true, false, true, false } },
    .{ .name = "long_literal_search", .pattern = "timeout", .inputs = .{ "x" ** 4096 ++ "timeout", "x" ** 8192, "timeout" ++ "x" ** 4096, "x" ** 4096 }, .expected = .{ true, false, true, false } },
    .{ .name = "nullable_loop", .pattern = "^((a?)*)*b$", .inputs = .{ "a" ** 4096 ++ "b", "a" ** 8192, "b", "a" ** 1024 }, .expected = .{ true, false, true, false } },
    .{ .name = "overlapping_alternation", .pattern = "^(a|aa|aaa|aaaa)*b$", .inputs = .{ "a" ** 4096 ++ "b", "a" ** 8192, "b", "a" ** 1024 }, .expected = .{ true, false, true, false } },
    .{ .name = "state_budget", .pattern = "a" ** 127, .inputs = .{ "a" ** 127, "x" ** 8192, "x" ** 4096 ++ "a" ** 127, "a" ** 126 }, .expected = .{ true, false, true, false } },
    .{ .name = "dense_states", .pattern = "^([a-z]|[a-z]|[a-z]|[a-z]|[a-z]|[a-z]|[a-z]|[a-z])+[0-9]$", .inputs = .{ "a" ** 1024 ++ "7", "a" ** 2048, "abc7", "123" }, .expected = .{ true, false, true, false } },
    .{ .name = "nul_high_bytes", .pattern = "^[\\x00-\\xff]+$", .inputs = .{ "\x00\xff\n", "", "\xc3\xa9", "" }, .expected = .{ true, false, true, false } },
};

fn parse(args: []const []const u8) !Options {
    var options: Options = .{};
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--iterations=")) options.iterations = std.fmt.parseInt(usize, arg[13..], 10) catch return error.InvalidBudget else if (std.mem.startsWith(u8, arg, "--repetitions=")) options.repetitions = std.fmt.parseInt(usize, arg[14..], 10) catch return error.InvalidBudget else return error.UnknownArgument;
    }
    if (options.iterations < 4 or options.iterations > 10000 or options.repetitions < 5 or options.repetitions > 9) return error.InvalidBudget;
    return options;
}

fn attemptsFor(case: Case, iterations: usize) usize {
    var max_length: usize = 0;
    for (case.inputs) |input| max_length = @max(max_length, input.len);
    // Keep long-input campaigns bounded while always testing all four inputs.
    return @max(4, iterations / @max(1, max_length / 64) / 4 * 4);
}

const Sample = struct {
    elapsed_ns: u64,
    attempts: usize,
    matches: u64,
    input_bytes: u64,
    written: u64 = 0,
    output_bytes: u64 = 0,
    checksum: u64 = 0,
    runtime_allocations: usize = 0,
};

fn matchBatch(comptime predicate: bool, case: Case, io: std.Io, attempts: usize) !Sample {
    const compiled = if (predicate) try kron.Predicate.init(&.{.{ .key = "input", .operator = .pattern, .value = .{ .string = case.pattern } }}) else try kron.Pattern.init(case.pattern);
    var events: [4]kron.Event = undefined;
    var fields: [4][1]kron.Field = undefined;
    for (case.inputs, 0..) |input, index| {
        fields[index] = .{kron.kv("input", input)};
        events[index] = .{ .level = .info, .scope = "bench.regex", .message = "request", .timestamp_ns = 0, .fields = &fields[index] };
        const actual = if (predicate) try compiled.matches(events[index]) else try compiled.matches(input);
        if (actual != case.expected[index]) return error.MatchMismatch;
    }
    var matches: u64 = 0;
    var input_bytes: u64 = 0;
    const started = std.Io.Clock.awake.now(io);
    for (0..attempts) |iteration| {
        const index = iteration % case.inputs.len;
        const matched = if (predicate) try compiled.matches(events[index]) else try compiled.matches(case.inputs[index]);
        std.mem.doNotOptimizeAway(matched);
        matches += @intFromBool(matched);
        input_bytes += case.inputs[index].len;
    }
    const elapsed = started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds();
    if (matches != attempts / 2) return error.MatchMismatch;
    return .{ .elapsed_ns = @intCast(@max(0, elapsed)), .attempts = attempts, .matches = matches, .input_bytes = input_bytes };
}

const CounterSink = struct {
    records: u64 = 0,
    acknowledged: u64 = 0,
    bytes: u64 = 0,
    checksum: u64 = 0,
    last: [4096]u8 = undefined,
    last_len: usize = 0,

    fn sink(self: *CounterSink) kron.Sink {
        return .{ .context = self, .vtable = &vtable };
    }
    fn write(raw: *anyopaque, record: []const u8) anyerror!void {
        const self: *CounterSink = @ptrCast(@alignCast(raw));
        if (record.len > self.last.len or record.len < 3 or record[0] != '{' or !std.mem.endsWith(u8, record, "}\n")) return error.InvalidRecord;
        @memcpy(self.last[0..record.len], record);
        self.last_len = record.len;
        self.records += 1;
        self.bytes += record.len;
        self.checksum +%= std.hash.Wyhash.hash(0, record);
        std.mem.doNotOptimizeAway(self.checksum);
    }
    fn flush(raw: *anyopaque) anyerror!void {
        const self: *CounterSink = @ptrCast(@alignCast(raw));
        self.acknowledged = self.records;
    }
    fn sync(_: *anyopaque) anyerror!void {
        return error.UnsupportedDurability;
    }
    const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = sync };
};

fn runtimeBatch(case: Case, allocator: std.mem.Allocator, io: std.Io, attempts: usize) !Sample {
    const quoted = try std.json.Stringify.valueAlloc(allocator, case.pattern, .{});
    defer allocator.free(quoted);
    const spec = try std.fmt.allocPrint(allocator, "input =~ {s}", .{quoted});
    defer allocator.free(spec);
    var allocations = std.testing.FailingAllocator.init(allocator, .{});
    var sink: CounterSink = .{};
    const runtime = try kron.Runtime.create(allocations.allocator(), io, .{ .submission = .sync, .predicate = spec, .routes = &.{.{ .name = "json", .sink = sink.sink(), .format = .json }}, .clock = kron.Clock.zeroTimestamp(), .max_encoded_record_bytes = sink.last.len });
    defer runtime.destroy();
    runtime.session = 1;
    const log = runtime.loggerWithClock(kron.ZeroClock, "bench.regex");
    for (0..4) |index| {
        const result = try log.tryEmit(.info, "request", .{ .input = case.inputs[index], .attempt = index });
        if (result != if (case.expected[index]) kron.EmitResult.accepted else .filtered) return error.MatchMismatch;
    }
    try runtime.flush(.written);
    const before = runtime.health();
    const records_before = sink.records;
    const bytes_before = sink.bytes;
    const checksum_before = sink.checksum;
    const allocations_before = allocations.allocations;
    allocations.fail_index = allocations.alloc_index;
    allocations.resize_fail_index = allocations.resize_index;
    var matches: u64 = 0;
    var input_bytes: u64 = 0;
    const started = std.Io.Clock.awake.now(io);
    for (0..attempts) |iteration| {
        const index = iteration % 4;
        const result = try log.tryEmit(.info, "request", .{ .input = case.inputs[index], .attempt = iteration });
        if (result != if (case.expected[index]) kron.EmitResult.accepted else .filtered) return error.MatchMismatch;
        matches += @intFromBool(result == .accepted);
        input_bytes += case.inputs[index].len;
    }
    try runtime.flush(.written);
    const elapsed = started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds();
    const after = runtime.health();
    if (allocations.allocations != allocations_before or allocations.has_induced_failure) return error.MeasurementAllocation;
    if (matches != attempts / 2 or after.accepted - before.accepted != matches or after.written - before.written != matches or after.filtered - before.filtered != attempts - matches or sink.records - records_before != matches or sink.acknowledged != sink.records or after.accepted != after.written) return error.IncompleteWritten;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, sink.last[0..sink.last_len], .{ .duplicate_field_behavior = .@"error" });
    defer parsed.deinit();
    const attributes = parsed.value.object.get("attributes").?.object;
    if (!std.mem.eql(u8, attributes.get("input").?.string, case.inputs[2]) or attributes.get("attempt").?.integer != attempts - 2 or !std.mem.eql(u8, parsed.value.object.get("message").?.string, "request")) return error.InvalidRecord;
    return .{ .elapsed_ns = @intCast(@max(0, elapsed)), .attempts = attempts, .matches = matches, .input_bytes = input_bytes, .written = after.written - before.written, .output_bytes = sink.bytes - bytes_before, .checksum = sink.checksum -% checksum_before, .runtime_allocations = allocations.allocations - allocations_before };
}

fn row(writer: *std.Io.Writer, case: Case, operation: []const u8, repetition: usize, sample: Sample) !void {
    try std.json.Stringify.value(.{
        .benchmark = "regex",
        .case = case.name,
        .operation = operation,
        .repetition = repetition,
        .sample = sample,
        .ns_per_attempt = @as(f64, @floatFromInt(sample.elapsed_ns)) / @as(f64, @floatFromInt(sample.attempts)),
        .optimize = @tagName(builtin.mode),
        .zig = builtin.zig_version_string,
        .cpu = builtin.cpu.model.name,
        .clock_pairs = 1,
        .producer_clock = "ZeroClock for sync; none for isolated matches",
        .sink = "complete JSON hash/copy counter; written flush included; no file durability",
        .scope = "fixed-input batch average; no per-call tail or asynchronous throughput claim",
    }, .{}, writer);
    try writer.writeByte('\n');
}

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parse(arguments[1..]);
    var buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    for (0..options.repetitions) |repetition| {
        for (0..cases.len) |offset| {
            const case = cases[if (repetition % 2 == 0) offset else cases.len - 1 - offset];
            const attempts = attemptsFor(case, options.iterations);
            try row(&output.interface, case, "pattern", repetition, try matchBatch(false, case, init.io, attempts));
            try row(&output.interface, case, "predicate", repetition, try matchBatch(true, case, init.io, attempts));
        }
        for (cases[0..2]) |case| try row(&output.interface, case, "full_sync_json", repetition, try runtimeBatch(case, init.gpa, init.io, attemptsFor(case, options.iterations)));
        try output.interface.flush();
    }
}

test "regex benchmark checks business decisions complete output and bounded budgets" {
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--iterations=0"}));
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--iterations=10001"}));
    try std.testing.expectError(error.InvalidBudget, parse(&.{"--repetitions=4"}));
    try std.testing.expectError(error.UnknownArgument, parse(&.{"--unknown=1"}));
    for (cases) |case| {
        _ = try matchBatch(false, case, std.testing.io, 4);
        _ = try matchBatch(true, case, std.testing.io, 4);
        try std.testing.expectEqual(@as(usize, 0), attemptsFor(case, 10000) % 4);
    }
    for (cases[0..2]) |case| _ = try runtimeBatch(case, std.testing.allocator, std.testing.io, 4);
}
