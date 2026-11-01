//! Public capture and full synchronous JSON logging benchmark. Batch timing
//! includes scalar updates, capture, and the documented output consumption;
//! full_runtime_sync also includes filtering/context/encoding/sink completion.
//! It does not measure journal submission and reports no per-call percentiles.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");

pub const Options = struct {
    iterations: usize = 10000,
    repetitions: usize = 5,
    label: []const u8 = "unspecified",
    source_hash: []const u8 = "unspecified",
};
pub fn parseOptions(args: []const []const u8) !Options {
    var result: Options = .{};
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--iterations=")) result.iterations = std.fmt.parseInt(usize, arg[13..], 10) catch return error.InvalidIterations else if (std.mem.startsWith(u8, arg, "--repetitions=")) result.repetitions = std.fmt.parseInt(usize, arg[14..], 10) catch return error.InvalidRepetitions else if (std.mem.startsWith(u8, arg, "--label=")) result.label = arg[8..] else if (std.mem.startsWith(u8, arg, "--source-hash=")) result.source_hash = arg[14..] else return error.UnknownArgument;
    }
    if (result.iterations == 0 or result.iterations > 10000) return error.InvalidIterations;
    if (result.repetitions < 5 or result.repetitions > 9) return error.InvalidRepetitions;
    return result;
}

const Scalars = struct {
    f0: u64 = 0,
    f1: u64 = 1,
    f2: u64 = 2,
    f3: u64 = 3,
    f4: u64 = 4,
    f5: u64 = 5,
    f6: u64 = 6,
    f7: u64 = 7,
    f8: u64 = 8,
    f9: u64 = 9,
    fn update(self: *Scalars, iteration: usize) void {
        const delta: u64 = @intCast(iteration % 17);
        self.f0 = delta;
        self.f1 = delta + 1;
        self.f2 = delta + 2;
        self.f3 = delta + 3;
        self.f4 = delta + 4;
        self.f5 = delta + 5;
        self.f6 = delta + 6;
        self.f7 = delta + 7;
        self.f8 = delta + 8;
        self.f9 = delta + 9;
    }
};
fn input(comptime count: usize, values: Scalars) switch (count) {
    0 => @TypeOf(.{}),
    5 => struct { f0: u64, f1: u64, f2: u64, f3: u64, f4: u64 },
    10 => Scalars,
    else => @compileError("capture benchmark fields must be 0/5/10"),
} {
    return switch (count) {
        0 => .{},
        5 => .{ .f0 = values.f0, .f1 = values.f1, .f2 = values.f2, .f3 = values.f3, .f4 = values.f4 },
        10 => values,
        else => unreachable,
    };
}

const CounterSink = struct {
    records: u64 = 0,
    acknowledged: u64 = 0,
    bytes: u64 = 0,
    checksum: u64 = 0,
    last: [4096]u8 = undefined,
    last_len: usize = 0,
    fn sink(self: *CounterSink) kron.Sink {
        return .{ .context = self, .vtable = &vtable, .recovery_identity = "capture-bench-json-discard-v1" };
    }
    fn write(raw: *anyopaque, record: []const u8) anyerror!void {
        const self: *CounterSink = @ptrCast(@alignCast(raw));
        if (record.len < 3 or record[0] != '{' or record[record.len - 1] != '\n' or record[record.len - 2] != '}') return error.IncompleteJsonRecord;
        if (record.len > self.last.len) return error.RecordTooLarge;
        @memcpy(self.last[0..record.len], record);
        self.last_len = record.len;
        self.records += 1;
        self.bytes += record.len;
        self.checksum +%= std.hash.Wyhash.hash(self.records, record);
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

const Sample = struct { elapsed_ns: u64, checksum: u64, accepted: u64, written: u64, output_bytes: u64, runtime_allocations: usize };

fn appendBatch(comptime count: usize, io: std.Io, iterations: usize) !Sample {
    var values: Scalars = .{};
    var scratch: [10]kron.Field = undefined;
    var checksum: u64 = 0;
    const started = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..iterations) |iteration| {
        values.update(iteration);
        var length: usize = 0;
        try kron.fields.appendFields(&scratch, &length, input(count, values));
        for (scratch[0..length]) |field| {
            checksum +%= std.hash.Wyhash.hash(@truncate(field.value.unsigned), field.key);
            checksum +%= @truncate(field.value.unsigned);
        }
        std.mem.doNotOptimizeAway(scratch[0..length]);
    }
    const elapsed = std.Io.Clock.awake.now(io).nanoseconds - started;
    std.mem.doNotOptimizeAway(checksum);
    return .{ .elapsed_ns = @intCast(@max(0, elapsed)), .checksum = checksum, .accepted = @intCast(iterations), .written = 0, .output_bytes = 0, .runtime_allocations = 0 };
}

fn runtimeBatch(comptime count: usize, comptime borrowed: bool, allocator: std.mem.Allocator, io: std.Io, iterations: usize) !Sample {
    var allocations = std.testing.FailingAllocator.init(allocator, .{});
    var sink: CounterSink = .{};
    const runtime = try kron.Runtime.create(allocations.allocator(), io, .{ .submission = .sync, .filter = "info", .routes = &.{.{ .name = "discard", .sink = sink.sink(), .format = .json }}, .max_encoded_record_bytes = sink.last.len, .clock = kron.Clock.zeroTimestamp() });
    defer runtime.destroy();
    // Before any producer runs, fix this benchmark's session so both modules
    // emit identical JSON bytes. Runtime-created production sessions stay random.
    runtime.session = 1;
    const empty = runtime.loggerWithClock(kron.ZeroClock, "capture.bench");
    // The second borrowed layer overwrites f0 from the first. For 5/10 fields,
    // the current event overwrites it again, leaving exactly one final key.
    const log = if (borrowed) empty.withBorrowed(.{ .f0 = @as(u64, 77) }).withBorrowed(.{ .f0 = @as(u64, 99) }) else empty;
    var values: Scalars = .{};
    for (0..@min(iterations, 100)) |iteration| {
        values.update(iteration);
        if (try log.tryEmitAt(@src(), .info, "capture benchmark", input(count, values)) != .accepted) return error.UnexpectedFiltered;
    }
    const before = runtime.health();
    const records_before = sink.records;
    const bytes_before = sink.bytes;
    const checksum_before = sink.checksum;
    const allocations_before = allocations.allocations;
    allocations.fail_index = allocations.alloc_index;
    allocations.resize_fail_index = allocations.resize_index;
    const started = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..iterations) |iteration| {
        values.update(iteration);
        if (try log.tryEmitAt(@src(), .info, "capture benchmark", input(count, values)) != .accepted) return error.UnexpectedFiltered;
    }
    try runtime.flush(.written);
    const elapsed = std.Io.Clock.awake.now(io).nanoseconds - started;
    const after = runtime.health();
    if (allocations.allocations != allocations_before or allocations.has_induced_failure) return error.MeasurementAllocation;
    if (after.accepted - before.accepted != iterations or after.written - before.written != iterations or sink.records - records_before != iterations or sink.acknowledged != sink.records) return error.IncompleteWritten;
    // Full JSON validation stays outside measurement and rejects duplicate
    // keys; source metadata and context/event overwrite are checked explicitly.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, sink.last[0..sink.last_len], .{ .duplicate_field_behavior = .@"error" });
    defer parsed.deinit();
    const attributes = parsed.value.object.get("attributes").?.object;
    if (attributes.count() != if (borrowed and count == 0) 1 else count) return error.WrongAttributeCount;
    if (parsed.value.object.get("source") == null) return error.MissingSource;
    if (borrowed) {
        const expected: i64 = if (count == 0) 99 else @intCast((iterations - 1) % 17);
        if (attributes.get("f0").?.integer != expected) return error.WrongContextOverwrite;
    }
    return .{ .elapsed_ns = @intCast(@max(0, elapsed)), .checksum = sink.checksum -% checksum_before, .accepted = after.accepted - before.accepted, .written = after.written - before.written, .output_bytes = sink.bytes - bytes_before, .runtime_allocations = allocations.allocations - allocations_before };
}

fn row(writer: *std.Io.Writer, options: Options, operation: []const u8, context: []const u8, fields_count: usize, repetition: usize, sample: Sample) !void {
    try writer.writeAll("{\"benchmark\":\"capture\",\"operation\":");
    try std.json.Stringify.value(operation, .{}, writer);
    try writer.writeAll(",\"context\":");
    try std.json.Stringify.value(context, .{}, writer);
    try writer.print(",\"numfields\":{d},\"input_shape\":\"anonymous scalar struct\",\"repetition\":{d},\"iterations\":{d},\"elapsed_ns\":{d},\"ns_per_call\":{d},\"accepted\":{d},\"written\":{d},\"output_bytes\":{d},\"checksum\":{d},\"runtime_allocations_in_batch\":{d},\"clock_pairs\":1,\"clock\":\"std.Io.Clock.awake\",\"producer_clock\":\"ZeroClock\",\"submission\":\"sync\",\"journal\":false,\"buffer_budget\":4096,\"consume\":\"append field key/value hash; runtime full JSON Wyhash and copied final record\",\"cpu\":", .{ fields_count, repetition, options.iterations, sample.elapsed_ns, @as(f64, @floatFromInt(sample.elapsed_ns)) / @as(f64, @floatFromInt(options.iterations)), sample.accepted, sample.written, sample.output_bytes, sample.checksum, sample.runtime_allocations });
    try std.json.Stringify.value(builtin.cpu.model.name, .{}, writer);
    try writer.writeAll(",\"build\":");
    try std.json.Stringify.value(@tagName(builtin.mode), .{}, writer);
    try writer.writeAll(",\"zig\":");
    try std.json.Stringify.value(builtin.zig_version_string, .{}, writer);
    try writer.writeAll(",\"label\":");
    try std.json.Stringify.value(options.label, .{}, writer);
    try writer.writeAll(",\"source_hash\":");
    try std.json.Stringify.value(options.source_hash, .{}, writer);
    try writer.writeAll(",\"fixed_session\":1");
    try writer.writeAll("}\n");
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parseOptions(args[1..]);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    inline for (.{ 0, 5, 10 }) |count| {
        _ = try appendBatch(count, init.io, @min(options.iterations, 100));
        for (0..options.repetitions) |repetition| try row(&output.interface, options, "field_append", "none", count, repetition, try appendBatch(count, init.io, options.iterations));
        inline for (.{ false, true }) |borrowed| {
            for (0..options.repetitions) |repetition| try row(&output.interface, options, "full_runtime_sync_json", if (borrowed) "borrowed_overwrite" else "empty", count, repetition, try runtimeBatch(count, borrowed, init.gpa, init.io, options.iterations));
        }
    }
    try output.interface.flush();
}

test "capture benchmark bounded options and complete public paths" {
    try std.testing.expectError(error.InvalidIterations, parseOptions(&.{"--iterations=0"}));
    try std.testing.expectError(error.InvalidIterations, parseOptions(&.{"--iterations=10001"}));
    try std.testing.expectError(error.InvalidRepetitions, parseOptions(&.{"--repetitions=4"}));
    try std.testing.expectError(error.InvalidRepetitions, parseOptions(&.{"--repetitions=10"}));
    try std.testing.expectEqual(@as(usize, 10000), (try parseOptions(&.{})).iterations);
    inline for (.{ 0, 5, 10 }) |count| {
        _ = try appendBatch(count, std.testing.io, 2);
        _ = try runtimeBatch(count, false, std.testing.allocator, std.testing.io, 2);
        _ = try runtimeBatch(count, true, std.testing.allocator, std.testing.io, 2);
    }
}
