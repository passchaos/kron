//! Independent output pipeline options; the list defaults to one stderr route.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("../core/runtime_types.zig");
const outputs = @import("output.zig");

pub const Mode = enum { sync, asynchronous, spsc };
pub const Target = outputs.Target;
pub const Queue = union(enum) { none, memory: types.MemoryQueueOptions, mmap: @import("../journal/journal.zig").Options };
pub const Route = struct {
    name: []const u8 = "stderr",
    target: Target = .stderr,
    mode: Mode = .sync,
    queue: ?Queue = null,
    overflow: types.Overflow = .block,
    format: @import("../encoder/root.zig").Format = .text,
    timestamp: ?@import("../time/root.zig").FormatOptions = null,
    filter: []const u8 = "info",
    min_level: ?@import("../core/level.zig").Level = null,
    sampling: @import("../pipeline/sampler.zig").Config = .none,
    sample_bypass: @import("../core/level.zig").Level = .warn,
    /// Each pipeline redacts before copying to its own Memory/Mmap queue.
    redaction: []const @import("../pipeline/redact.zig").Rule = &.{},
    predicate: ?[]const u8 = null,
    delivery: types.Delivery = .required,
    reclaim_after: @import("../journal/journal.zig").ReclaimBoundary = .written,
    max_threads: usize = 4,
    max_encoded_record_bytes: usize = 64 * 1024,
    max_journal_bytes: usize = 256 * 1024 * 1024,
    consumer_batches_per_queue: usize = 4,
    /// Opt-in producer-rendered JSON cache for a single asynchronous JSON
    /// route. Volatile; misses and recovery use the deferred renderer.
    render_cache: bool = false,
    render_cache_record_bytes: usize = 1024,
    diagnostics: @import("../core/diagnostics.zig").Options = .{},
};
pub const Options = struct {
    outputs: []const Route = &.{.{}},
    /// Overall queue backing budget across independent output pipelines.
    max_total_queue_bytes: usize = 256 * 1024 * 1024,
};
pub fn resolve(route: Route) Route {
    var resolved = route;
    resolved.queue = route.queue orelse if (route.mode == .sync) Queue.none else Queue{ .memory = .{} };
    return resolved;
}
pub fn queueBytes(d: Route) !usize {
    const q = d.queue orelse return 0;
    if (q == .none) return 0;
    const memory = if (q == .memory) q.memory else types.MemoryQueueOptions{ .capacity = q.mmap.capacity, .max_record_bytes = q.mmap.max_record_bytes, .schema_capacity = q.mmap.schema_capacity, .max_schema_bytes = q.mmap.max_schema_bytes };
    const base = try @import("../journal/format.zig").layout(memory.capacity, memory.max_record_bytes);
    const size = if (memory.schema_capacity == 0) base.size else (try @import("../journal/schema.zig").layout(base.size, memory.schema_capacity, memory.max_schema_bytes)).size;
    return std.math.mul(usize, size, if (d.mode == .spsc) d.max_threads + 1 else 1) catch error.JournalBudgetExceeded;
}
fn journalCount(d: Route) usize {
    return if (d.queue.? != .mmap) 0 else if (d.mode == .spsc) d.max_threads + 1 else 1;
}
fn journalPath(d: Route, channel: usize, buffer: []u8) ![]const u8 {
    return if (channel == 0) d.queue.?.mmap.path else try std.fmt.bufPrint(buffer, "{s}.thread-{d}.journal", .{ d.queue.?.mmap.path, channel - 1 });
}
fn validatePaths(options: Options, route_index: usize, d: Route) !void {
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var previous_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    for (0..journalCount(d)) |channel| {
        const path = try journalPath(d, channel, &path_buffer);
        for (options.outputs) |other| {
            if (outputs.sameFileTarget(other.target, .{ .file = .{ .path = path } })) return error.JournalOutputConflict;
        }
        for (options.outputs[0..route_index]) |previous| {
            const before = resolve(previous);
            for (0..journalCount(before)) |previous_channel| {
                const previous_path = try journalPath(before, previous_channel, &previous_buffer);
                if (std.mem.eql(u8, path, previous_path)) return error.DuplicateJournalPath;
            }
        }
    }
}
pub fn validate(options: Options) !void {
    if (options.outputs.len == 0 or options.outputs.len > 64) return error.InvalidOutputs;
    var total: usize = 0;
    for (options.outputs, 0..) |route, index| {
        if (route.name.len == 0) return error.InvalidRouteName;
        const d = resolve(route);
        if (route.target == .rolling_file) try route.target.rolling_file.validate();
        for (options.outputs[0..index]) |previous| {
            if (std.mem.eql(u8, route.name, previous.name)) return error.DuplicateRoute;
            if (outputs.sameFileTarget(route.target, previous.target)) return error.DuplicateOutputTarget;
            if (route.target == .writer and previous.target == .writer and route.target.writer == previous.target.writer) return error.DuplicateOutputTarget;
        }
        if (d.mode != .sync and builtin.single_threaded) return error.ThreadsUnavailable;
        if (d.mode == .sync and d.queue.? != .none) return error.QueueRequiresAsyncMode;
        if (d.mode != .sync and d.queue.? == .none) return error.JournalRequired;
        if (d.mode == .spsc and (d.max_threads == 0 or d.max_threads > 64)) return error.InvalidThreadBudget;
        if (d.consumer_batches_per_queue == 0 or d.consumer_batches_per_queue > 4 or d.max_encoded_record_bytes == 0 or d.max_encoded_record_bytes > std.math.maxInt(u32)) return error.InvalidOptions;
        if (d.render_cache and (d.mode == .sync or d.format != .json or d.render_cache_record_bytes == 0 or d.render_cache_record_bytes > d.max_encoded_record_bytes)) return error.InvalidRenderCache;
        if (d.queue.? == .memory and d.queue.?.memory.text_format) {
            if (d.mode == .sync or d.format != .json or d.queue.?.memory.verify_crc) return error.InvalidTextFormat;
        }
        if (d.queue.? == .mmap and d.queue.?.mmap.text_format) {
            if (d.mode == .sync or d.format != .json or d.queue.?.mmap.verify_crc or d.queue.?.mmap.recover) return error.InvalidTextFormat;
        }
        if (d.queue.? == .mmap and (d.queue.?.mmap.path.len == 0 or (route.target != .file and route.target != .rolling_file))) return error.MmapRequiresFileOutput;
        if (d.mode != .sync and d.reclaim_after == .durable and d.queue.? != .mmap) return error.DurableReclaimRequiresMmap;
        try validatePaths(options, index, d);
        _ = try @import("../config/filter.zig").Filter.parse(d.filter);
        _ = try @import("../pipeline/sampler.zig").Sampler.init(d.sampling);
        _ = try @import("../pipeline/redact.zig").Redactor.init(d.redaction);
        if (d.predicate) |predicate| _ = try @import("../pipeline/predicate.zig").Predicate.parse(predicate);
        if (d.timestamp) |timestamp| {
            if (d.format == .binary) return error.InvalidTimestampFormat;
            try timestamp.validate();
        }
        const bytes = try queueBytes(d);
        if (bytes > d.max_journal_bytes) return error.JournalBudgetExceeded;
        total = std.math.add(usize, total, bytes) catch return error.JournalBudgetExceeded;
        if (total > options.max_total_queue_bytes) return error.JournalBudgetExceeded;
    }
}
