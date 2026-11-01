//! Application-owned logging setup. Handles call Runtime directly.
const std = @import("std");
const Runtime = @import("../core/runtime.zig").Runtime;
const types = @import("../core/runtime_types.zig");
const logger = @import("../core/logger.zig");
const threads = @import("../core/thread_registry.zig");
const outputs = @import("output.zig");
const configuration = @import("configuration.zig");
test {
    _ = @import("tests.zig");
}

pub const Logging = struct {
    /// Root std_options.logFn = kron.Logging.std_log.logFn.
    pub const std_log = @import("../adapters/std_log.zig").Bridge(Runtime);
    pub const Mode = configuration.Mode;
    pub const Target = configuration.Target;
    pub const Route = configuration.Route;
    pub const Output = configuration.Output;
    pub const Queue = configuration.Queue;
    pub const Options = configuration.Options;
    pub const Defaults = configuration.Defaults;
    pub const Capture = configuration.Capture;

    allocator: std.mem.Allocator,
    owner: *Runtime,
    destinations: []outputs.Resource,

    /// Owns file/rolling sinks and Runtime; standard streams/writers are borrowed.
    /// Stable allocation protects the writer buffer/context captured by Runtime.
    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Logging {
        try configuration.validate(options);
        const self = try allocator.create(Logging);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        var single: [1]Route = undefined;
        const definitions = configuration.routeDefinitions(options, &single);
        self.destinations = try allocator.alloc(outputs.Resource, definitions.len);
        errdefer allocator.free(self.destinations);
        var initialized: usize = 0;
        errdefer for (self.destinations[0..initialized]) |*destination| destination.deinit();
        var routes: [64]types.RouteOptions = undefined;
        for (definitions, self.destinations, routes[0..definitions.len], 0..) |original, *destination, *route, index| {
            const definition = configuration.resolve(options, original);
            try destination.init(allocator, io, definition.target);
            initialized += 1;
            const sink = destination.sink();
            if (sink.recovery_identity) |identity| for (routes[0..index]) |previous| {
                if (previous.sink.recovery_identity) |other| if (std.mem.eql(u8, identity, other)) return error.DuplicateOutputTarget;
            };
            route.* = .{
                .name = definition.name,
                .sink = sink,
                .format = definition.format.?,
                .timestamp = definition.timestamp,
                .filter = definition.filter,
                .min_level = definition.min_level,
                .delivery = definition.delivery.?,
                .reclaim_after = definition.reclaim_after.?,
                .predicate = definition.predicate,
                .redaction = definition.redaction.?,
                .sampling = definition.sampling,
                .sample_bypass = definition.sample_bypass.?,
                .max_encoded_record_bytes = definition.max_encoded_record_bytes,
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
            .filter = options.defaults.filter orelse options.filter,
            .overflow = options.overflow,
            .redaction = options.capture.redaction orelse options.redaction,
            .sampling = options.defaults.sampling orelse options.sampling,
            .sample_bypass = options.defaults.sample_bypass orelse options.sample_bypass,
            .predicate = options.capture.predicate orelse options.predicate,
            .diagnostics = options.diagnostics,
            .routes = routes[0..definitions.len],
        });
        return self;
    }

    pub fn scoped(self: *Logging, scope: []const u8) logger.Logger(Runtime, .trace) {
        return self.owner.scoped(scope);
    }
    /// Thread-affine handle. Stop users/detach before destroying Logging.
    pub fn attachThread(self: *Logging, scope: []const u8) !logger.Logger(threads.ThreadOwner(Runtime), .trace) {
        return self.owner.attachThread(.{ .scope = scope });
    }
    /// Register a shape once and return a shared prepared logger.
    pub fn prepared(self: *Logging, shape: @import("../core/event.zig").Event) !logger.Logger(@import("../core/prepared.zig").Owner(Runtime), .trace) {
        return self.owner.loggerWithSchema(try self.owner.prewarmSchema(shape));
    }
    /// Attach this thread and prewarm its queue without exposing channel indices.
    pub fn attachPreparedThread(self: *Logging, shape: @import("../core/event.zig").Event) !logger.Logger(@import("../core/prepared.zig").ThreadOwner(threads.ThreadOwner(Runtime)), .trace) {
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
    pub fn setLevel(self: *Logging, level: @import("../core/level.zig").Level) !void {
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
    pub fn flushUntil(self: *Logging, deadline: @import("../core/control.zig").Deadline) !void {
        try self.owner.flushUntil(.written, deadline);
    }
    pub fn flushDurableUntil(self: *Logging, deadline: @import("../core/control.zig").Deadline) !void {
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
    pub fn shutdownUntil(self: *Logging, deadline: @import("../core/control.zig").Deadline) !void {
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
