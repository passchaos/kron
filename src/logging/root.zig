//! One application owner, a list of independently configured output pipelines.
const std = @import("std");
const Runtime = @import("../core/runtime.zig").Runtime;
const types = @import("../core/runtime_types.zig");
const core = @import("../core/logger.zig");
const resources = @import("output.zig");
const config = @import("configuration.zig");
const dispatch = @import("handle.zig");
const Event = @import("../core/event.zig").Event;
const Deadline = @import("../core/control.zig").Deadline;

test {
    _ = @import("tests.zig");
}

pub const Logging = struct {
    pub const std_log = @import("../adapters/std_log.zig").Bridge(Logging);
    pub const Mode = config.Mode;
    pub const Target = config.Target;
    pub const Route = config.Route;
    pub const Queue = config.Queue;
    pub const Options = config.Options;
    pub const Outcome = dispatch.Outcome;
    pub const Logger = core.Logger(dispatch.Owner, .trace);
    const Pipeline = struct { name: []u8, runtime: *Runtime, resource: resources.Resource = undefined, mode: Mode, delivery: types.Delivery };
    const Attachment = struct {
        busy: std.atomic.Value(bool) = .init(false),
        generation: std.atomic.Value(usize) = .init(0),
        scope: [128]u8 = undefined,
        scope_len: usize = 0,
    };
    allocator: std.mem.Allocator,
    io: std.Io,
    pipelines: []Pipeline,
    attachments: []Attachment,
    thread_handles: []?dispatch.ThreadLogger,
    attachment_mutex: std.Io.Mutex = .init,
    sites_mutex: std.Io.Mutex = .init,
    sites: ?*dispatch.Site = null,
    stopping: std.atomic.Value(bool) = .init(false),

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Logging {
        try config.validate(options);
        const self = try allocator.create(Logging);
        errdefer allocator.destroy(self);
        const pipelines = try allocator.alloc(Pipeline, options.outputs.len);
        errdefer allocator.free(pipelines);
        var initialized: usize = 0;
        errdefer for (pipelines[0..initialized]) |*pipeline| {
            pipeline.runtime.destroy();
            pipeline.resource.deinit();
            allocator.free(pipeline.name);
        };
        var slots: usize = 0;
        for (options.outputs, pipelines, 0..) |route, *pipeline, route_index| {
            const d = config.resolve(route);
            const name = try allocator.dupe(u8, route.name);
            errdefer allocator.free(name);
            pipeline.name = name;
            pipeline.mode = d.mode;
            pipeline.delivery = d.delivery;
            try pipeline.resource.init(allocator, io, route.target);
            errdefer pipeline.resource.deinit();
            const sink = pipeline.resource.sink();
            if (sink.recovery_identity) |identity| for (pipelines[0..route_index]) |*previous| {
                if (previous.resource.sink().recovery_identity) |other| if (std.mem.eql(u8, identity, other)) return error.DuplicateOutputTarget;
            };
            const q = d.queue.?;
            pipeline.runtime = try Runtime.create(allocator, io, .{
                .submission = switch (d.mode) {
                    .sync => .sync,
                    .asynchronous => .asynchronous,
                    .spsc => .low_latency,
                },
                .memory_queue = if (q == .memory) q.memory else null,
                .journal = if (q == .mmap) q.mmap else null,
                .max_thread_channels = if (d.mode == .spsc) d.max_threads else 0,
                .thread_channel_capacity = if (q == .memory) q.memory.capacity else if (q == .mmap) q.mmap.capacity else 256,
                .max_journal_bytes = d.max_journal_bytes,
                .max_encoded_record_bytes = d.max_encoded_record_bytes,
                .consumer_batches_per_queue = d.consumer_batches_per_queue,
                .filter = d.filter,
                .overflow = d.overflow,
                .redaction = d.redaction,
                .sampling = d.sampling,
                .sample_bypass = d.sample_bypass,
                .predicate = d.predicate,
                .diagnostics = d.diagnostics,
                // The individual pipeline always observes its own sink errors.
                // required/best_effort applies when aggregating independent outputs.
                .routes = &.{.{ .name = name, .sink = sink, .format = d.format, .timestamp = d.timestamp, .min_level = d.min_level, .reclaim_after = d.reclaim_after }},
            });
            initialized += 1;
            if (d.mode == .spsc) slots = @max(slots, d.max_threads);
        }
        const attachments = try allocator.alloc(Attachment, slots);
        errdefer allocator.free(attachments);
        for (attachments) |*slot| slot.* = .{};
        const thread_handles = try allocator.alloc(?dispatch.ThreadLogger, slots * pipelines.len);
        @memset(thread_handles, null);
        self.* = .{ .allocator = allocator, .io = io, .pipelines = pipelines, .attachments = attachments, .thread_handles = thread_handles };
        return self;
    }
    fn allMask(self: *const Logging) u64 {
        return if (self.pipelines.len == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(self.pipelines.len)) - 1;
    }
    fn index(self: *const Logging, name: []const u8) !usize {
        for (self.pipelines, 0..) |pipeline, i| if (std.mem.eql(u8, name, pipeline.name)) return i;
        return error.UnknownOutput;
    }
    pub fn scoped(self: *Logging, scope: []const u8) Logger {
        return .init(.{ .logging = self, .scope = scope, .mask = self.allMask() }, scope);
    }
    /// Direct output handle keeps the original Runtime frontend for hot loops.
    pub fn scopedOutput(self: *Logging, name: []const u8, scope: []const u8) !core.Logger(Runtime, .trace) {
        return self.pipelines[try self.index(name)].runtime.scoped(scope);
    }
    pub fn runtime(self: *Logging, name: []const u8) !*Runtime {
        return self.pipelines[try self.index(name)].runtime;
    }
    pub fn outputHealth(self: *Logging, name: []const u8) !types.Health {
        return self.pipelines[try self.index(name)].runtime.health();
    }
    /// Per-output results from the most recent fanout call on this OS thread.
    /// Borrowed until another call on the same thread; copy to retain them.
    pub fn lastResults(self: *Logging) []const Outcome {
        return dispatch.lastResults(self);
    }
    pub fn attachThread(self: *Logging, scope: []const u8) !Logger {
        if (scope.len > 128) return error.ScopeTooLong;
        if (self.stopping.load(.acquire)) return error.Closing;
        self.attachment_mutex.lockUncancelable(self.io);
        defer self.attachment_mutex.unlock(self.io);
        const slot_index = for (self.attachments, 0..) |*slot, i| {
            if (!slot.busy.load(.acquire)) break i;
        } else return error.ChannelsExhausted;
        const slot = &self.attachments[slot_index];
        const generation = std.math.add(usize, slot.generation.load(.monotonic), 1) catch return error.GenerationExhausted;
        const handles = self.thread_handles[slot_index * self.pipelines.len ..][0..self.pipelines.len];
        var count: usize = 0;
        errdefer {
            var i = count;
            while (i != 0) {
                i -= 1;
                if (handles[i]) |handle| handle.detach() catch {};
                handles[i] = null;
            }
        }
        for (self.pipelines, handles) |pipeline, *handle| {
            handle.* = if (pipeline.mode == .spsc) try pipeline.runtime.attachThread(.{ .scope = scope }) else null;
            count += 1;
        }
        @memcpy(slot.scope[0..scope.len], scope);
        slot.scope_len = scope.len;
        slot.generation.store(generation, .release);
        slot.busy.store(true, .release);
        const owned_scope = slot.scope[0..scope.len];
        return .init(.{ .logging = self, .scope = owned_scope, .mask = self.allMask(), .token = .{ .slot = slot_index, .generation = generation, .thread = std.Thread.getCurrentId() } }, owned_scope);
    }
    fn prepare(self: *Logging, shape: Event, base: Logger) !Logger {
        const site = try self.allocator.create(dispatch.Site);
        errdefer self.allocator.destroy(site);
        site.bindings = try self.allocator.alloc(?@import("../core/prepared.zig").Binding, self.pipelines.len);
        errdefer self.allocator.free(site.bindings);
        @memset(site.bindings, null);
        for (self.pipelines, 0..) |pipeline, i| {
            if (pipeline.mode == .sync) continue;
            const attached = if (base.owner.token) |token| self.thread_handles[token.slot * self.pipelines.len + i] else null;
            site.bindings[i] = if (attached) |thread| try pipeline.runtime.prewarmThreadSchema(@intCast(thread.owner.control_index + 1), shape) else try pipeline.runtime.prewarmSchema(shape);
        }
        self.sites_mutex.lockUncancelable(self.io);
        defer self.sites_mutex.unlock(self.io);
        site.next = self.sites;
        self.sites = site;
        var result = base;
        result.owner.site = site;
        return result;
    }
    pub fn prepared(self: *Logging, shape: Event) !Logger {
        return self.prepare(shape, self.scoped(shape.scope));
    }
    pub fn attachPreparedThread(self: *Logging, shape: Event) !Logger {
        const base = try self.attachThread(shape.scope);
        errdefer base.detach() catch {};
        return self.prepare(shape, base);
    }
    pub fn reportError(self: *Logging, err: anyerror) void {
        for (self.pipelines) |pipeline| pipeline.runtime.reportError(err);
    }
    pub fn reloadFilter(self: *Logging, specification: []const u8) !void {
        for (self.pipelines) |pipeline| try pipeline.runtime.checkControlContext();
        _ = try @import("../config/filter.zig").Filter.parse(specification);
        for (self.pipelines) |pipeline| try pipeline.runtime.reloadFilter(specification);
    }
    pub fn reloadOutputFilter(self: *Logging, name: []const u8, specification: []const u8) !void {
        try self.pipelines[try self.index(name)].runtime.reloadFilter(specification);
    }
    pub fn reloadFilterFile(self: *Logging, path: []const u8) !void {
        for (self.pipelines) |pipeline| try pipeline.runtime.checkControlContext();
        for (self.pipelines) |pipeline| try pipeline.runtime.reloadFilterFile(path);
    }
    pub fn setLevel(self: *Logging, level: core.Level) !void {
        for (self.pipelines) |pipeline| try pipeline.runtime.checkControlContext();
        for (self.pipelines) |pipeline| try pipeline.runtime.setLevelChecked(level);
    }
    pub fn bindStdLog(self: *Logging) !void {
        try std_log.bind(self);
    }
    pub fn unbindStdLog(self: *Logging) void {
        std_log.unbindOwner(self);
    }
    const Action = enum { written, durable, shutdown };
    fn control(self: *Logging, action: Action, names: ?[]const []const u8, deadline: ?Deadline) !void {
        var mask = self.allMask();
        if (names) |selected| {
            mask = 0;
            for (selected) |name| mask |= @as(u64, 1) << @intCast(try self.index(name));
        }
        if (action == .durable and names == null) {
            for (self.pipelines, 0..) |pipeline, i| {
                if (pipeline.delivery != .required) mask &= ~(@as(u64, 1) << @intCast(i));
            }
        }
        // Preflight all pipelines: a callback of a later output must fail
        // before an earlier output waits for that callback to complete.
        for (self.pipelines) |pipeline| try pipeline.runtime.checkControlContext();
        if (deadline) |until| {
            for (self.pipelines, 0..) |pipeline, i| {
                if (mask & (@as(u64, 1) << @intCast(i)) != 0 and !pipeline.runtime.controlStatus().available) return error.TimedControlUnavailable;
            }
            if (until.expired(self.io)) return error.Timeout;
        }
        if (action == .shutdown) {
            self.stopping.store(true, .release);
            for (self.pipelines) |pipeline| try pipeline.runtime.stopAccepting();
        }
        var failure: ?anyerror = null;
        for (self.pipelines, 0..) |pipeline, i| {
            if (mask & (@as(u64, 1) << @intCast(i)) == 0) continue;
            const result = if (deadline) |until| switch (action) {
                .written => pipeline.runtime.flushUntil(.written, until),
                .durable => pipeline.runtime.flushUntil(.durable, until),
                .shutdown => pipeline.runtime.shutdownUntil(until),
            } else switch (action) {
                .written => pipeline.runtime.flush(.written),
                .durable => pipeline.runtime.flush(.durable),
                .shutdown => pipeline.runtime.shutdown(.drain),
            };
            result catch |err| if ((names != null or pipeline.delivery == .required) and failure == null) {
                failure = err;
            };
        }
        if (failure) |err| return err;
    }
    pub fn flush(self: *Logging) !void {
        try self.control(.written, null, null);
    }
    pub fn flushDurable(self: *Logging) !void {
        try self.control(.durable, null, null);
    }
    pub fn flushOutputs(self: *Logging, names: []const []const u8) !void {
        try self.control(.written, names, null);
    }
    pub fn flushOutputsDurable(self: *Logging, names: []const []const u8) !void {
        try self.control(.durable, names, null);
    }
    pub fn flushUntil(self: *Logging, deadline: Deadline) !void {
        try self.control(.written, null, deadline);
    }
    pub fn flushDurableUntil(self: *Logging, deadline: Deadline) !void {
        try self.control(.durable, null, deadline);
    }
    pub fn shutdown(self: *Logging) !void {
        try self.control(.shutdown, null, null);
    }
    pub fn shutdownUntil(self: *Logging, deadline: Deadline) !void {
        try self.control(.shutdown, null, deadline);
    }
    /// Counts output submissions, so one event written to two outputs counts twice.
    pub fn health(self: *Logging) types.Health {
        var result = self.pipelines[0].runtime.health();
        for (self.pipelines[1..]) |pipeline| {
            const next = pipeline.runtime.health();
            inline for (@typeInfo(types.Health).@"struct".fields) |field| {
                if (@typeInfo(field.type) == .int) @field(result, field.name) += @field(next, field.name);
            }
            result.worker_alive = result.worker_alive or next.worker_alive;
            if (result.last_error == null) result.last_error = next.last_error;
            if (result.state != next.state) result.state = .closing;
            if (result.queue_storage != next.queue_storage) result.queue_storage = .mixed;
        }
        return result;
    }
    pub fn destroy(self: *Logging) void {
        self.unbindStdLog();
        self.stopping.store(true, .release);
        for (self.pipelines) |*pipeline| {
            pipeline.runtime.destroy();
            pipeline.resource.deinit();
            self.allocator.free(pipeline.name);
        }
        var site = self.sites;
        while (site) |item| {
            site = item.next;
            self.allocator.free(item.bindings);
            self.allocator.destroy(item);
        }
        self.allocator.free(self.thread_handles);
        self.allocator.free(self.attachments);
        self.allocator.free(self.pipelines);
        self.allocator.destroy(self);
    }
};
