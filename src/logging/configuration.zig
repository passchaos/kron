//! Application logging configuration and cold-path validation.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("../core/runtime_types.zig");
const FileSink = @import("../sink/file.zig").FileSink;
const outputs = @import("output.zig");

pub const Mode = enum { sync, asynchronous, spsc };
pub const Target = outputs.Target;
pub const Defaults = struct {
    /// null retains the corresponding flat option for existing applications.
    format: ?@import("../encoder/root.zig").Format = null,
    timestamp: ?@import("../time/root.zig").FormatOptions = null,
    filter: ?[]const u8 = null,
    min_level: ?@import("../core/level.zig").Level = null,
    sampling: ?@import("../pipeline/sampler.zig").Config = null,
    sample_bypass: ?@import("../core/level.zig").Level = null,
    /// Output-only policy; use capture.redaction to remove values before queue.
    redaction: []const @import("../pipeline/redact.zig").Rule = &.{},
    predicate: ?[]const u8 = null,
    delivery: types.Delivery = .required,
    reclaim_after: ?@import("../journal/journal.zig").ReclaimBoundary = null,
    max_encoded_record_bytes: ?usize = null,
};

pub const Capture = struct {
    /// Irreversible protection before Memory/Mmap capture. null uses redaction.
    redaction: ?[]const @import("../pipeline/redact.zig").Rule = null,
    /// Mandatory event-wide predicate. null uses the flat predicate option.
    predicate: ?[]const u8 = null,
};

pub const Route = struct {
    name: []const u8,
    target: Target,
    /// null inherits the application-wide output format/time/boundary.
    format: ?@import("../encoder/root.zig").Format = null,
    timestamp: ?@import("../time/root.zig").FormatOptions = null,
    /// Explicitly disable an inherited readable timestamp.
    timestamp_enabled: bool = true,
    filter: ?[]const u8 = null,
    min_level: ?@import("../core/level.zig").Level = null,
    delivery: ?types.Delivery = null,
    reclaim_after: ?@import("../journal/journal.zig").ReclaimBoundary = null,
    predicate: ?[]const u8 = null,
    predicate_enabled: bool = true,
    redaction: ?[]const @import("../pipeline/redact.zig").Rule = null,
    sampling: ?@import("../pipeline/sampler.zig").Config = null,
    sample_bypass: ?@import("../core/level.zig").Level = null,
    max_encoded_record_bytes: ?usize = null,
};
pub const Output = union(enum) {
    stderr,
    stdout,
    file: FileSink.Options,
    rolling_file: @import("../sink/rolling_file.zig").RollingFileSink.Options,
    /// Borrowed writer and resources must outlive destroy().
    writer: *std.Io.Writer,
    /// One owner manages every output; names must be unique and stable.
    multiple: []const Route,
};
pub const Queue = union(enum) {
    memory: types.MemoryQueueOptions,
    mmap: @import("../journal/journal.zig").Options,
};
pub const Options = struct {
    output: Output = .stderr,
    /// Default output policies; each Route can override independently.
    defaults: Defaults = .{},
    /// Shared event protection before it is copied into the queue.
    capture: Capture = .{},
    mode: Mode = .sync,
    /// Async/SPSC default to bounded Memory. Sync requires null.
    queue: ?Queue = null,
    format: @import("../encoder/root.zig").Format = .text,
    timestamp: ?@import("../time/root.zig").FormatOptions = null,
    filter: []const u8 = "info",
    overflow: types.Overflow = .block,
    /// SPSC channels are preallocated during create.
    max_threads: usize = 4,
    max_journal_bytes: usize = 256 * 1024 * 1024,
    max_encoded_record_bytes: usize = 64 * 1024,
    consumer_batches_per_queue: usize = 4,
    reclaim_after: @import("../journal/journal.zig").ReclaimBoundary = .written,
    redaction: []const @import("../pipeline/redact.zig").Rule = &.{},
    sampling: @import("../pipeline/sampler.zig").Config = .none,
    sample_bypass: @import("../core/level.zig").Level = .warn,
    predicate: ?[]const u8 = null,
    diagnostics: @import("../core/diagnostics.zig").Options = .{},
};

pub fn validate(options: Options) !void {
    if (options.mode == .sync and options.queue != null) return error.QueueRequiresAsyncMode;
    if (options.mode != .sync and builtin.single_threaded) return error.ThreadsUnavailable;
    if (options.consumer_batches_per_queue == 0 or options.consumer_batches_per_queue > 4 or options.max_encoded_record_bytes == 0) return error.InvalidOptions;
    if (options.mode == .spsc and (options.max_threads == 0 or options.max_threads > 64)) return error.InvalidThreadBudget;
    if (options.queue) |queue| switch (queue) {
        .memory => |memory| if (memory.capacity == 0 or memory.max_record_bytes == 0) return error.InvalidOptions,
        .mmap => |mapped| if (mapped.path.len == 0 or mapped.capacity == 0 or mapped.max_record_bytes == 0) return error.InvalidOptions,
    };
    _ = try @import("../config/filter.zig").Filter.parse(options.defaults.filter orelse options.filter);
    _ = try @import("../pipeline/sampler.zig").Sampler.init(options.defaults.sampling orelse options.sampling);
    _ = try @import("../pipeline/redact.zig").Redactor.init(options.capture.redaction orelse options.redaction);
    if (options.capture.predicate orelse options.predicate) |expression| _ = try @import("../pipeline/predicate.zig").Predicate.parse(expression);
    var single: [1]Route = undefined;
    const routes = routeDefinitions(options, &single);
    if (routes.len == 0 or routes.len > 64) return error.InvalidOutputs;
    for (routes, 0..) |original, index| {
        const route = resolve(options, original);
        if (route.name.len == 0) return error.InvalidRouteName;
        for (routes[0..index]) |previous| {
            if (std.mem.eql(u8, route.name, previous.name)) return error.DuplicateRoute;
            if (outputs.sameFileTarget(route.target, previous.target)) return error.DuplicateOutputTarget;
        }
        if (route.filter) |filter| _ = try @import("../config/filter.zig").Filter.parse(filter);
        if (route.predicate) |expression| _ = try @import("../pipeline/predicate.zig").Predicate.parse(expression);
        if (route.timestamp) |timestamp| {
            if (route.format.? == .binary) return error.InvalidTimestampFormat;
            try timestamp.validate();
        }
        try @import("../config/output_policy.zig").Policy.validate(.{ .redaction = route.redaction.?, .sampling = route.sampling, .sample_bypass = route.sample_bypass.?, .max_encoded_record_bytes = route.max_encoded_record_bytes });
        if (route.max_encoded_record_bytes) |limit| if (limit > options.max_encoded_record_bytes) return error.EncodedRecordBudgetExceeded;
        if (route.reclaim_after.? == .durable and options.mode != .sync and (options.queue == null or options.queue.? != .mmap)) return error.DurableReclaimRequiresMmap;
        if (options.queue) |queue| if (queue == .mmap and route.delivery.? == .required and route.target != .file and route.target != .rolling_file) return error.MmapRequiresFileOutput;
    }
    if (options.mode != .sync) {
        const queue = options.queue orelse Queue{ .memory = .{} };
        const memory = if (queue == .memory) queue.memory else types.MemoryQueueOptions{ .capacity = queue.mmap.capacity, .max_record_bytes = queue.mmap.max_record_bytes, .schema_capacity = queue.mmap.schema_capacity, .max_schema_bytes = queue.mmap.max_schema_bytes };
        const layout = try @import("../journal/format.zig").layout(memory.capacity, memory.max_record_bytes);
        const bytes = if (memory.schema_capacity == 0) layout.size else (try @import("../journal/schema.zig").layout(layout.size, memory.schema_capacity, memory.max_schema_bytes)).size;
        const total = std.math.mul(usize, bytes, if (options.mode == .spsc) options.max_threads + 1 else 1) catch return error.JournalBudgetExceeded;
        if (total > options.max_journal_bytes) return error.JournalBudgetExceeded;
    }
}

pub fn resolve(options: Options, route: Route) Route {
    var result = route;
    result.format = route.format orelse options.defaults.format orelse options.format;
    result.min_level = route.min_level orelse options.defaults.min_level;
    result.timestamp = if (route.timestamp_enabled) route.timestamp orelse options.defaults.timestamp orelse options.timestamp else null;
    result.delivery = route.delivery orelse options.defaults.delivery;
    result.reclaim_after = route.reclaim_after orelse options.defaults.reclaim_after orelse options.reclaim_after;
    result.predicate = if (route.predicate_enabled) route.predicate orelse options.defaults.predicate else null;
    result.redaction = route.redaction orelse options.defaults.redaction;
    result.sample_bypass = route.sample_bypass orelse options.defaults.sample_bypass orelse options.sample_bypass;
    if (route.sample_bypass != null and route.sampling == null) result.sampling = options.defaults.sampling orelse options.sampling;
    result.max_encoded_record_bytes = route.max_encoded_record_bytes orelse options.defaults.max_encoded_record_bytes;
    return result;
}

pub fn routeDefinitions(options: Options, single: *[1]Route) []const Route {
    if (options.output == .multiple) return options.output.multiple;
    single[0] = .{ .name = "output", .target = switch (options.output) {
        .stderr => .stderr,
        .stdout => .stdout,
        .file => |file| .{ .file = file },
        .rolling_file => |file| .{ .rolling_file = file },
        .writer => |writer| .{ .writer = writer },
        .multiple => unreachable,
    } };
    return single;
}
