const std = @import("std");
const builtin = @import("builtin");
const args = @import("args.zig");
const measurement = @import("measurement.zig");

pub const Result = struct {
    schema_version: u32 = 1,
    status: []const u8 = "ok",
    error_name: ?[]const u8 = null,
    phase: []const u8,
    mode: []const u8,
    sink: []const u8,
    backend_requested: []const u8,
    backend_selected: []const u8 = "none",
    format: []const u8,
    temperature: []const u8,
    fields: usize,
    payload: []const u8,
    long_string_bytes: usize,
    filtered_case: bool,
    events_requested: usize,
    producers: usize,
    samples_max: usize,
    warmup_attempted: u64 = 0,
    warmup_written: u64 = 0,
    overflow: []const u8,
    durable_requested: bool,
    memory_budget_bytes: usize,
    journal_slots: usize,
    channel_slots: usize,
    thread_channels: usize,
    journal_budget_bytes: usize,
    journal_allocation_bytes: usize,
    idle_requested: []const u8,
    idle_selected: []const u8 = "none",
    event_clock: []const u8,
    schema_enabled: bool,
    max_record_bytes: usize,
    file_buffer_bytes: usize,
    queue_depth: u16,
    runtime_init_ns: ?u64 = null,
    preparation_ns: ?u64 = null,
    producer_wall_ns: ?u64 = null,
    flush_written_ns: ?u64 = null,
    durable_flush_ns: ?u64 = null,
    shutdown_ns: ?u64 = null,
    total_ns: ?u64 = null,
    attempted: u64 = 0,
    accepted: u64 = 0,
    filtered: u64 = 0,
    sampled: u64 = 0,
    dropped_full: u64 = 0,
    dropped_oversize: u64 = 0,
    rejected_closing: u64 = 0,
    emit_errors: u64 = 0,
    runtime_accepted: u64 = 0,
    runtime_written: u64 = 0,
    runtime_write_errors: u64 = 0,
    sink_accepted_records: u64 = 0,
    sink_written_records: u64 = 0,
    sink_written_bytes: u64 = 0,
    final_pending: usize = 0,
    journal_high_water: usize = 0,
    artifact_bytes: ?u64 = null,
    producer_ns_per_attempt: ?f64 = null,
    written_records_per_sec: ?f64 = null,
    written_bytes_per_sec: ?f64 = null,
    latency_samples: usize = 0,
    producer_p50_ns: ?u64 = null,
    producer_p99_ns: ?u64 = null,
    producer_p999_ns: ?u64 = null,
    producer_max_ns: ?u64 = null,
    producer_sample_mean_ns: ?f64 = null,
    noop_samples: usize,
    clock_pair_p50_ns: ?u64,
    clock_pair_p99_ns: ?u64,
    clock_pair_p999_ns: ?u64,
    clock_pair_mean_ns: ?f64,
    noop_batch_ns_per_call: f64,
    awake_resolution_ns: ?u64,
    cpu_process_ns: ?u64 = null,
    cpu_producer_threads_ns: ?u64 = null,
    cpu_user_ns: ?u64 = null,
    cpu_system_ns: ?u64 = null,
    minor_faults: ?i64 = null,
    major_faults: ?i64 = null,
    voluntary_context_switches: ?i64 = null,
    involuntary_context_switches: ?i64 = null,
    process_max_rss_kib: ?u64 = null,
    zig_version: []const u8 = builtin.zig_version_string,
    optimize: []const u8 = @tagName(builtin.mode),
    target_arch: []const u8 = @tagName(builtin.cpu.arch),
    target_os: []const u8 = @tagName(builtin.os.tag),
    logical_cpu_count: ?usize,
    kernel_release: ?[]const u8,
    file_path: ?[]const u8 = null,
    journal_path: ?[]const u8 = null,
    // New fields are appended to preserve existing CSV column positions.
    queue_storage: []const u8,
    process_crash_recovery: bool,
    queue_allocation_bytes: usize,
    journal_mapped_bytes: usize,

    pub fn init(options: args.Options, phase: []const u8, baseline: measurement.Baseline, machine: *const Machine) Result {
        return .{
            .phase = phase,
            .mode = options.modeName(),
            .sink = @tagName(options.sink),
            .backend_requested = @tagName(options.backend),
            .format = @tagName(options.format),
            .temperature = @tagName(options.temperature),
            .fields = options.fields,
            .payload = @tagName(options.payload),
            .long_string_bytes = options.string_bytes,
            .filtered_case = options.filtered,
            .events_requested = options.events,
            .producers = options.producers,
            .samples_max = options.samples,
            .overflow = @tagName(options.overflow),
            .durable_requested = options.durable,
            .memory_budget_bytes = options.memory_bytes,
            .journal_slots = options.journal_slots,
            .channel_slots = options.channel_slots,
            .thread_channels = if (options.mode == .spsc) options.producers else 0,
            .journal_budget_bytes = options.journal_bytes,
            .journal_allocation_bytes = if (options.mode != .sync and options.storage == .mmap) options.journalAllocationBytes() catch 0 else 0,
            .idle_requested = @tagName(options.idle),
            .event_clock = @tagName(options.clock),
            .schema_enabled = options.schema,
            .max_record_bytes = options.max_record_bytes,
            .file_buffer_bytes = options.buffer_bytes,
            .queue_depth = options.queue_depth,
            .noop_samples = baseline.distribution.count,
            .clock_pair_p50_ns = baseline.distribution.p50_ns,
            .clock_pair_p99_ns = baseline.distribution.p99_ns,
            .clock_pair_p999_ns = baseline.distribution.p999_ns,
            .clock_pair_mean_ns = baseline.distribution.mean_ns,
            .noop_batch_ns_per_call = baseline.batch_ns_per_noop,
            .awake_resolution_ns = baseline.awake_resolution_ns,
            .logical_cpu_count = machine.cpu_count,
            .kernel_release = if (machine.has_kernel_release) std.mem.sliceTo(&machine.kernel_release, 0) else null,
            .queue_storage = options.storageName(),
            .process_crash_recovery = options.mode != .sync and options.storage == .mmap,
            .queue_allocation_bytes = options.journalAllocationBytes() catch 0,
            .journal_mapped_bytes = if (options.mode != .sync and options.storage == .mmap) options.journalAllocationBytes() catch 0 else 0,
        };
    }

    pub fn fail(self: *Result, err: anyerror) void {
        self.status = switch (err) {
            error.Unsupported, error.UnsupportedDurability => "unsupported",
            else => "failed",
        };
        self.error_name = @errorName(err);
    }

    pub fn write(self: Result, output: args.Output, writer: *std.Io.Writer) !void {
        if (output == .json) {
            try std.json.Stringify.value(self, .{}, writer);
            try writer.writeByte('\n');
        } else {
            inline for (@typeInfo(Result).@"struct".fields, 0..) |field, index| {
                if (index != 0) try writer.writeByte(',');
                try csvValue(writer, @field(self, field.name));
            }
            try writer.writeByte('\n');
        }
    }

    pub fn csvHeader(writer: *std.Io.Writer) !void {
        inline for (@typeInfo(Result).@"struct".fields, 0..) |field, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeAll(field.name);
        }
        try writer.writeByte('\n');
    }
};

pub const Machine = struct {
    cpu_count: ?usize,
    kernel_release: [65]u8 = @splat(0),
    has_kernel_release: bool = false,

    pub fn detect() Machine {
        var result: Machine = .{ .cpu_count = std.Thread.getCpuCount() catch null };
        if (builtin.os.tag == .linux) {
            var name: std.os.linux.utsname = undefined;
            if (std.os.linux.errno(std.os.linux.uname(&name)) == .SUCCESS) {
                @memcpy(result.kernel_release[0..name.release.len], &name.release);
                result.has_kernel_release = true;
            }
        }
        return result;
    }
};

fn csvValue(writer: *std.Io.Writer, value: anytype) !void {
    switch (@typeInfo(@TypeOf(value))) {
        .optional => if (value) |present| try csvValue(writer, present),
        .bool => try writer.writeAll(if (value) "true" else "false"),
        .int, .float => try writer.print("{d}", .{value}),
        .pointer => {
            try writer.writeByte('"');
            for (value) |byte| {
                if (byte == '"') try writer.writeByte('"');
                try writer.writeByte(byte);
            }
            try writer.writeByte('"');
        },
        else => @compileError("unsupported CSV field"),
    }
}

test "CSV strings escape delimiters quotes and line breaks" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();
    try csvValue(&writer.writer, @as([]const u8, "path,\"name\"\n"));
    try std.testing.expectEqualStrings("\"path,\"\"name\"\"\n\"", writer.written());
}

test "storage reports separate total queue allocation from mapped bytes and append CSV fields" {
    const baseline: measurement.Baseline = .{ .distribution = .{}, .batch_ns_per_noop = 0, .awake_resolution_ns = null };
    const machine: Machine = .{ .cpu_count = null };
    const memory = Result.init(.{ .mode = .asynchronous, .storage = .memory, .schema = true }, "batch", baseline, &machine);
    const mapped = Result.init(.{ .mode = .asynchronous, .storage = .mmap, .schema = true }, "batch", baseline, &machine);
    const sync = Result.init(.{}, "batch", baseline, &machine);
    try std.testing.expectEqualStrings("memory", memory.queue_storage);
    try std.testing.expect(!memory.process_crash_recovery);
    try std.testing.expectEqual(@as(usize, 0), memory.journal_allocation_bytes);
    try std.testing.expectEqual(@as(usize, 0), memory.journal_mapped_bytes);
    try std.testing.expectEqual(mapped.queue_allocation_bytes, memory.queue_allocation_bytes);
    try std.testing.expectEqual(mapped.queue_allocation_bytes, mapped.journal_mapped_bytes);
    try std.testing.expect(mapped.process_crash_recovery);
    try std.testing.expectEqualStrings("none", sync.queue_storage);
    try std.testing.expectEqual(@as(usize, 0), sync.queue_allocation_bytes);
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();
    try Result.csvHeader(&writer.writer);
    try std.testing.expect(std.mem.endsWith(u8, writer.written(), "file_path,journal_path,queue_storage,process_crash_recovery,queue_allocation_bytes,journal_mapped_bytes\n"));
}
