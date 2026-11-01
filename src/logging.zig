//! Application-owned logging setup. Handles call Runtime directly.
const std = @import("std");
const builtin = @import("builtin");
const Runtime = @import("core/runtime.zig").Runtime;
const types = @import("core/runtime_types.zig");
const logger = @import("core/logger.zig");
const threads = @import("core/thread_registry.zig");
const FileSink = @import("sink/file.zig").FileSink;
const outputs = @import("logging/output.zig");
test {
    _ = @import("logging_tests.zig");
}

pub const Logging = struct {
    /// Root std_options.logFn = kron.Logging.std_log.logFn.
    pub const std_log = @import("adapters/std_log.zig").Bridge(Runtime);
    pub const Mode = enum { sync, asynchronous, spsc };
    pub const Target = outputs.Target;
    pub const Route = struct {
        name: []const u8,
        target: Target,
        /// null inherits the application-wide output format/time/boundary.
        format: ?@import("encoder/root.zig").Format = null,
        timestamp: ?@import("time/root.zig").FormatOptions = null,
        filter: ?[]const u8 = null,
        min_level: ?@import("core/level.zig").Level = null,
        delivery: types.Delivery = .required,
        reclaim_after: ?@import("journal/journal.zig").ReclaimBoundary = null,
        predicate: ?[]const u8 = null,
    };
    pub const Output = union(enum) {
        stderr,
        stdout,
        file: FileSink.Options,
        rolling_file: @import("sink/rolling_file.zig").RollingFileSink.Options,
        /// Borrowed writer and resources must outlive destroy().
        writer: *std.Io.Writer,
        /// One owner manages every output; names must be unique and stable.
        multiple: []const Route,
    };
    pub const Queue = union(enum) {
        memory: types.MemoryQueueOptions,
        mmap: @import("journal/journal.zig").Options,
    };
    pub const Options = struct {
        output: Output = .stderr,
        mode: Mode = .sync,
        /// Async/SPSC default to bounded Memory. Sync requires null.
        queue: ?Queue = null,
        format: @import("encoder/root.zig").Format = .text,
        timestamp: ?@import("time/root.zig").FormatOptions = null,
        filter: []const u8 = "info",
        overflow: types.Overflow = .block,
        /// SPSC channels are preallocated during create.
        max_threads: usize = 4,
        max_journal_bytes: usize = 256 * 1024 * 1024,
        max_encoded_record_bytes: usize = 64 * 1024,
        consumer_batches_per_queue: usize = 4,
        reclaim_after: @import("journal/journal.zig").ReclaimBoundary = .written,
        redaction: []const @import("pipeline/redact.zig").Rule = &.{},
        sampling: @import("pipeline/sampler.zig").Config = .none,
        sample_bypass: @import("core/level.zig").Level = .warn,
        predicate: ?[]const u8 = null,
        diagnostics: @import("core/diagnostics.zig").Options = .{},
    };

    allocator: std.mem.Allocator,
    owner: *Runtime,
    destinations: []outputs.Resource,

    /// Owns file/rolling sinks and Runtime; standard streams/writers are borrowed.
    /// Stable allocation protects the writer buffer/context captured by Runtime.
    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Logging {
        try validate(options);
        const self = try allocator.create(Logging);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        var single: [1]Route = undefined;
        const definitions = routeDefinitions(options, &single);
        self.destinations = try allocator.alloc(outputs.Resource, definitions.len);
        errdefer allocator.free(self.destinations);
        var initialized: usize = 0;
        errdefer for (self.destinations[0..initialized]) |*destination| destination.deinit();
        var routes: [64]types.RouteOptions = undefined;
        for (definitions, self.destinations, routes[0..definitions.len], 0..) |definition, *destination, *route, index| {
            try destination.init(allocator, io, definition.target);
            initialized += 1;
            const sink = destination.sink();
            if (sink.recovery_identity) |identity| for (routes[0..index]) |previous| {
                if (previous.sink.recovery_identity) |other| if (std.mem.eql(u8, identity, other)) return error.DuplicateOutputTarget;
            };
            route.* = .{
                .name = definition.name,
                .sink = sink,
                .format = definition.format orelse options.format,
                .timestamp = definition.timestamp orelse options.timestamp,
                .filter = definition.filter,
                .min_level = definition.min_level,
                .delivery = definition.delivery,
                .reclaim_after = definition.reclaim_after orelse options.reclaim_after,
                .predicate = definition.predicate,
            };
        }
        const queue = options.queue orelse Queue{ .memory = .{} };
        self.owner = try Runtime.create(allocator, io, .{
            .submission = switch (options.mode) {
                .sync => .sync,
                .asynchronous => .asynchronous,
                .spsc => .low_latency,
            },
            .memory_queue = if (options.mode != .sync and queue == .memory) queue.memory else null,
            .journal = if (options.mode != .sync and queue == .mmap) queue.mmap else null,
            .max_thread_channels = if (options.mode == .spsc) options.max_threads else 0,
            .thread_channel_capacity = if (options.mode != .sync) (if (queue == .memory) queue.memory.capacity else queue.mmap.capacity) else 256,
            .max_journal_bytes = options.max_journal_bytes,
            .max_encoded_record_bytes = options.max_encoded_record_bytes,
            .consumer_batches_per_queue = options.consumer_batches_per_queue,
            .filter = options.filter,
            .overflow = options.overflow,
            .redaction = options.redaction,
            .sampling = options.sampling,
            .sample_bypass = options.sample_bypass,
            .predicate = options.predicate,
            .diagnostics = options.diagnostics,
            .routes = routes[0..definitions.len],
        });
        return self;
    }

    fn validate(options: Options) !void {
        if (options.mode == .sync and options.queue != null) return error.QueueRequiresAsyncMode;
        if (options.mode != .sync and builtin.single_threaded) return error.ThreadsUnavailable;
        if (options.consumer_batches_per_queue == 0 or options.consumer_batches_per_queue > 4 or options.max_encoded_record_bytes == 0) return error.InvalidOptions;
        if (options.mode == .spsc and (options.max_threads == 0 or options.max_threads > 64)) return error.InvalidThreadBudget;
        if (options.queue) |queue| switch (queue) {
            .memory => |memory| if (memory.capacity == 0 or memory.max_record_bytes == 0) return error.InvalidOptions,
            .mmap => |mapped| if (mapped.path.len == 0 or mapped.capacity == 0 or mapped.max_record_bytes == 0) return error.InvalidOptions,
        };
        _ = try @import("config/filter.zig").Filter.parse(options.filter);
        _ = try @import("pipeline/sampler.zig").Sampler.init(options.sampling);
        _ = try @import("pipeline/redact.zig").Redactor.init(options.redaction);
        if (options.predicate) |expression| _ = try @import("pipeline/predicate.zig").Predicate.parse(expression);
        var single: [1]Route = undefined;
        const routes = routeDefinitions(options, &single);
        if (routes.len == 0 or routes.len > 64) return error.InvalidOutputs;
        for (routes, 0..) |route, index| {
            if (route.name.len == 0) return error.InvalidRouteName;
            for (routes[0..index]) |previous| {
                if (std.mem.eql(u8, route.name, previous.name)) return error.DuplicateRoute;
                if (outputs.sameFileTarget(route.target, previous.target)) return error.DuplicateOutputTarget;
            }
            if (route.filter) |filter| _ = try @import("config/filter.zig").Filter.parse(filter);
            if (route.predicate) |expression| _ = try @import("pipeline/predicate.zig").Predicate.parse(expression);
            if (route.timestamp orelse options.timestamp) |timestamp| {
                if ((route.format orelse options.format) == .binary) return error.InvalidTimestampFormat;
                try timestamp.validate();
            }
            if ((route.reclaim_after orelse options.reclaim_after) == .durable and options.mode != .sync and (options.queue == null or options.queue.? != .mmap)) return error.DurableReclaimRequiresMmap;
            if (options.queue) |queue| if (queue == .mmap and route.delivery == .required and route.target != .file and route.target != .rolling_file) return error.MmapRequiresFileOutput;
        }
        if (options.mode != .sync) {
            const queue = options.queue orelse Queue{ .memory = .{} };
            const memory = if (queue == .memory) queue.memory else types.MemoryQueueOptions{ .capacity = queue.mmap.capacity, .max_record_bytes = queue.mmap.max_record_bytes, .schema_capacity = queue.mmap.schema_capacity, .max_schema_bytes = queue.mmap.max_schema_bytes };
            const layout = try @import("journal/format.zig").layout(memory.capacity, memory.max_record_bytes);
            const bytes = if (memory.schema_capacity == 0) layout.size else (try @import("journal/schema.zig").layout(layout.size, memory.schema_capacity, memory.max_schema_bytes)).size;
            const total = std.math.mul(usize, bytes, if (options.mode == .spsc) options.max_threads + 1 else 1) catch return error.JournalBudgetExceeded;
            if (total > options.max_journal_bytes) return error.JournalBudgetExceeded;
        }
    }

    fn routeDefinitions(options: Options, single: *[1]Route) []const Route {
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

    pub fn scoped(self: *Logging, scope: []const u8) logger.Logger(Runtime, .trace) {
        return self.owner.scoped(scope);
    }
    /// Thread-affine handle. Stop users/detach before destroying Logging.
    pub fn attachThread(self: *Logging, scope: []const u8) !logger.Logger(threads.ThreadOwner(Runtime), .trace) {
        return self.owner.attachThread(.{ .scope = scope });
    }
    /// Register a shape once and return a shared prepared logger.
    pub fn prepared(self: *Logging, shape: @import("core/event.zig").Event) !logger.Logger(@import("core/prepared.zig").Owner(Runtime), .trace) {
        return self.owner.loggerWithSchema(try self.owner.prewarmSchema(shape));
    }
    /// Attach this thread and prewarm its queue without exposing channel indices.
    pub fn attachPreparedThread(self: *Logging, shape: @import("core/event.zig").Event) !logger.Logger(@import("core/prepared.zig").ThreadOwner(threads.ThreadOwner(Runtime)), .trace) {
        const attached = try self.attachThread(shape.scope);
        errdefer attached.detach() catch {};
        const binding = try self.owner.prewarmThreadSchema(@intCast(attached.owner.control_index + 1), shape);
        return self.owner.threadLoggerWithSchema(attached, binding);
    }
    /// Advanced API is borrowed; Logging must outlive its Runtime/handle users.
    pub fn runtime(self: *Logging) *Runtime {
        return self.owner;
    }
    pub fn reloadFilter(self: *Logging, specification: []const u8) !void {
        try self.owner.reloadFilter(specification);
    }
    pub fn reloadFilterFile(self: *Logging, path: []const u8) !void {
        try self.owner.reloadFilterFile(path);
    }
    pub fn setLevel(self: *Logging, level: @import("core/level.zig").Level) !void {
        try self.owner.setLevelChecked(level);
    }
    pub fn health(self: *Logging) types.Health {
        return self.owner.health();
    }
    pub fn bindStdLog(self: *Logging) !void {
        try std_log.bind(self.owner);
    }
    pub fn unbindStdLog(self: *Logging) void {
        std_log.unbindOwner(self.owner);
    }
    pub fn flush(self: *Logging) !void {
        try self.owner.flush(.written);
    }
    pub fn flushDurable(self: *Logging) !void {
        try self.owner.flush(.durable);
    }
    pub fn flushUntil(self: *Logging, deadline: @import("core/control.zig").Deadline) !void {
        try self.owner.flushUntil(.written, deadline);
    }
    pub fn flushDurableUntil(self: *Logging, deadline: @import("core/control.zig").Deadline) !void {
        try self.owner.flushUntil(.durable, deadline);
    }
    /// Confirm selected named outputs (including their retained versions).
    pub fn flushOutputs(self: *Logging, names: []const []const u8) !void {
        try self.owner.flushRoutes(names, .written);
    }
    pub fn flushOutputsDurable(self: *Logging, names: []const []const u8) !void {
        try self.owner.flushRoutes(names, .durable);
    }
    /// Explicit completion/error; destroy remains blocking ordered cleanup.
    pub fn shutdown(self: *Logging) !void {
        try self.owner.shutdown(.drain);
    }
    pub fn shutdownUntil(self: *Logging, deadline: @import("core/control.zig").Deadline) !void {
        try self.owner.shutdownUntil(deadline);
    }
    /// Stop all logger/token users first. One owner, destroy exactly once.
    pub fn destroy(self: *Logging) void {
        self.unbindStdLog();
        self.owner.destroy();
        for (self.destinations) |*destination| destination.deinit();
        self.allocator.free(self.destinations);
        self.allocator.destroy(self);
    }
};
