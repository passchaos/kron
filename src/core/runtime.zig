//! Stable owner of admission, filtering, journal delivery and resource lifetime.
//! Logger handles borrow this object; destroy requires all concurrent users to
//! have stopped. A failed worker retains unacknowledged journal records.
const std = @import("std");
const Level = @import("level.zig").Level;
const Field = @import("field.zig").Field;
const Event = @import("event.zig").Event;
const codec = @import("codec.zig");
const schema_codec = @import("schema_codec.zig");
const schema_module = @import("../journal/schema.zig");
const prepared_module = @import("prepared.zig");
const schema_site = @import("../submit/schema_site.zig");
pub const SchemaBinding = prepared_module.Binding;
const encoder = @import("../encoder/root.zig");
const common = @import("../encoder/common.zig");
const delivery = @import("delivery.zig");
const delivery_batch = @import("delivery_batch.zig");
const configurations = @import("../config/routes.zig");
const runtime_configuration = @import("runtime_configuration.zig");
pub const Configuration = configurations.Policy;
pub const ConfigurationVersion = configurations.Version;
const LoggerModule = @import("logger.zig");
const JournalModule = @import("../journal/journal.zig");
const Journal = JournalModule.Journal;
const Sink = @import("../sink/interface.zig").Sink;
const Filter = @import("../config/filter.zig").Filter;
const DynamicFilter = @import("../config/reload.zig").DynamicFilter;
const FilterDecision = @import("../config/reload.zig").Decision;
const BoundDecision = @import("../config/reload.zig").BoundDecision;
const thread_module = @import("thread_registry.zig");
const StaticClockOwner = @import("static_owner.zig").StaticClockOwner;
const InstanceClockOwner = @import("static_owner.zig").InstanceClockOwner;
const sampler_module = @import("../pipeline/sampler.zig");
const redact_module = @import("../pipeline/redact.zig");
const Atomic = std.atomic.Value;
const diagnostics_module = @import("diagnostics.zig");
const Clock = @import("../platform/clock.zig").Clock;
const control_module = @import("control.zig");
pub const Deadline = control_module.Deadline;
const admission_protocol = @import("admission.zig");
const closing_bit = admission_protocol.closing_bit;
const cut_bit = admission_protocol.cut_bit;
const count_mask = admission_protocol.count_mask;
const SinkFrame = struct { owner: *Runtime, previous: ?*const SinkFrame };
const ReleaseKey = struct { snapshot: *configurations.Snapshot, channel: u32, count: usize };
const RenderCache = @import("render_cache.zig").RenderCache;
threadlocal var sink_frame: ?*const SinkFrame = null;
threadlocal var cleanup_owner: ?*Runtime = null;

const types = @import("runtime_types.zig");
pub const Admission = types.Admission;
pub const BeginResult = types.BeginResult;
pub const EmitResult = types.EmitResult;
pub const Submission = types.Submission;
pub const QueueStorage = types.QueueStorage;
pub const Overflow = types.Overflow;
pub const Flush = types.Flush;
pub const Delivery = types.Delivery;
pub const Idle = types.Idle;
pub const State = types.State;
pub const RouteOptions = types.RouteOptions;
pub const Options = types.Options;
pub const Health = types.Health;
const Counters = types.Counters;
const Route = types.Route;

pub const Runtime = struct {
    pub const configuration_bound_filter = true;
    /// The configuration cache allocation also carries the optional volatile
    /// producer-rendered JSON cache, keeping the Runtime object size unchanged.
    pub const Caches = struct {
        render_cache: ?*RenderCache = null,
        channels: [64]configurations.Manager.ChannelCache = @splat(.{ .channel = 0 }),
    };
    pub const TestingHooks = if (@import("builtin").is_test) struct {
        pub threadlocal var after_snapshot: ?*const fn (*anyopaque) void = null;
        pub threadlocal var context: ?*anyopaque = null;
    } else struct {};
    allocator: std.mem.Allocator,
    io: std.Io,
    configuration_handle: *anyopaque,
    configuration_cache_handle: *anyopaque,
    filter_handle: *anyopaque,
    submission: Submission,
    journal: ?*Journal,
    thread_registry: ?*thread_module.Registry(Runtime) = null,
    overflow: Overflow,
    idle: Idle,
    consumer_batches_per_queue: usize,
    output: []u8,
    session: u64,
    sync_sequence: Atomic(u64) = .init(0),
    state: Atomic(State) = .init(.running),
    /// Closing/cut flags and admission count share one modification order.
    admission_gate: Atomic(u64) = .init(0),
    admission_epoch: Atomic(u32) = .init(0),
    configuration_gate: Atomic(u64) = .init(0),
    configuration_epoch: Atomic(u32) = .init(0),
    wake_epoch: Atomic(u32) = .init(0),
    progress_epoch: Atomic(u32) = .init(0),
    worker_alive: Atomic(bool) = .init(false),
    worker_sleeping: Atomic(bool) = .init(false),
    worker_id: Atomic(std.Thread.Id) = .init(0),
    worker_error: Atomic(u16) = .init(0),
    shutdown_error: Atomic(u16) = .init(0),
    historical_durable_supported: Atomic(bool) = .init(true),
    last_error: Atomic(u16) = .init(0),
    counters: Counters = .{},
    channel_counters: [64]Counters align(64) = @splat(.{}),
    clock: Clock,
    diagnostics: diagnostics_module.Reporter,
    delivery_mutex: std.Io.Mutex = .init,
    shutdown_mutex: std.Io.Mutex = .init,
    cut_mutex: std.Io.Mutex = .init,
    configuration_mutex: std.Io.Mutex = .init,
    worker: ?std.Thread = null,
    control: ?*control_module.Control = null,

    fn dynamicFilter(self: *Runtime) *DynamicFilter {
        return @ptrCast(@alignCast(self.filter_handle));
    }

    pub fn currentFilterGeneration(self: *Runtime) u64 {
        return self.dynamicFilter().generation();
    }

    fn configurationManager(self: *Runtime) *configurations.Manager {
        return @ptrCast(@alignCast(self.configuration_handle));
    }

    fn runtimeCaches(self: *Runtime) *Caches {
        return @ptrCast(@alignCast(self.configuration_cache_handle));
    }

    fn channelCaches(self: *Runtime) *[64]configurations.Manager.ChannelCache {
        return &self.runtimeCaches().channels;
    }

    fn renderCache(self: *Runtime) ?*RenderCache {
        return self.runtimeCaches().render_cache;
    }

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Runtime {
        return @import("runtime_init.zig").create(allocator, io, options, workerMain, runControl, decodeRecord);
    }

    pub fn logger(self: *Runtime, options: struct { scope: []const u8 = "default" }) LoggerModule.Logger(Runtime, .trace) {
        return .init(self, options.scope);
    }

    pub fn scoped(self: *Runtime, scope: []const u8) LoggerModule.Logger(Runtime, .trace) {
        return .init(self, scope);
    }

    pub fn loggerWithLevel(self: *Runtime, comptime min_level: Level, scope: []const u8) LoggerModule.Logger(Runtime, min_level) {
        return .init(self, scope);
    }

    pub fn attachThread(self: *Runtime, options: struct { scope: []const u8 = "default" }) !LoggerModule.Logger(thread_module.ThreadOwner(Runtime), .trace) {
        const registry = self.thread_registry orelse return error.ThreadChannelsDisabled;
        return registry.attach(options.scope);
    }

    pub fn loggerWithClock(self: *Runtime, comptime ClockProvider: type, scope: []const u8) LoggerModule.Logger(StaticClockOwner(Runtime, ClockProvider), .trace) {
        return .init(.{ .base = self, .scope = scope }, scope);
    }

    pub fn attachThreadWithClock(self: *Runtime, comptime ClockProvider: type, options: struct { scope: []const u8 = "default" }) !LoggerModule.Logger(StaticClockOwner(thread_module.ThreadOwner(Runtime), ClockProvider), .trace) {
        const attached = try self.attachThread(.{ .scope = options.scope });
        return .init(.{ .base = attached.owner, .scope = attached.scope }, attached.scope);
    }

    pub fn loggerWithInstanceClock(self: *Runtime, clock: Clock, scope: []const u8) LoggerModule.Logger(InstanceClockOwner(Runtime), .trace) {
        return .init(.{ .base = self, .clock = clock, .scope = scope }, scope);
    }

    pub fn attachThreadWithInstanceClock(self: *Runtime, clock: Clock, options: struct { scope: []const u8 = "default" }) !LoggerModule.Logger(InstanceClockOwner(thread_module.ThreadOwner(Runtime)), .trace) {
        const attached = try self.attachThread(.{ .scope = options.scope });
        return .init(.{ .base = attached.owner, .clock = clock, .scope = attached.scope }, attached.scope);
    }

    /// Register and persist a merged/redacted event shape once. This call may
    /// allocate during registry creation and perform sync; it is not hot-path
    /// work. Values are used only to infer kinds, never stored in metadata.
    pub fn prewarmSchema(self: *Runtime, original: Event) !SchemaBinding {
        const journal = self.journal orelse return error.JournalRequired;
        return self.prewarmInJournal(journal, original);
    }

    pub fn prewarmThreadSchema(self: *Runtime, channel: u32, original: Event) !SchemaBinding {
        const registry = self.thread_registry orelse return error.ThreadChannelsDisabled;
        if (channel == 0 or channel > registry.channelCount()) return error.InvalidChannel;
        return self.prewarmInJournal(registry.getJournal(channel - 1), original);
    }

    fn prewarmInJournal(self: *Runtime, journal: *Journal, original: Event) !SchemaBinding {
        if (self.state.load(.acquire) != .running) return error.Closed;
        var validator: @import("field.zig").ValueValidator = .{};
        try validator.fields(original.fields);
        try validator.arguments(original.format_args);
        var field_metadata: [64]schema_module.FieldSchema = undefined;
        var argument_metadata: [64]schema_module.FieldSchema = undefined;
        const metadata = try schema_codec.eventMetadata(original, &field_metadata, &argument_metadata);
        return self.prewarmMetadataInJournal(journal, metadata);
    }

    /// Type-only static metadata preserves optional kind masks independently
    /// of example values. Apply runtime redaction to the static attribute shape.
    pub fn prewarmMetadata(self: *Runtime, original: schema_module.EventMeta) !SchemaBinding {
        return self.prewarmMetadataInJournal(self.journal orelse return error.JournalRequired, original);
    }

    pub fn prewarmThreadMetadata(self: *Runtime, channel: u32, metadata: schema_module.EventMeta) !SchemaBinding {
        const registry = self.thread_registry orelse return error.ThreadChannelsDisabled;
        if (channel == 0 or channel > registry.channelCount()) return error.InvalidChannel;
        return self.prewarmMetadataInJournal(registry.getJournal(channel - 1), metadata);
    }

    fn prewarmMetadataInJournal(self: *Runtime, journal: *Journal, original: schema_module.EventMeta) !SchemaBinding {
        if (self.state.load(.acquire) != .running) return error.Closed;
        const view = self.configurationManager().acquire();
        defer view.release();
        var metadata = original;
        var safe: [64]schema_module.FieldSchema = undefined;
        if (original.fields.len > safe.len) return error.TooManyFields;
        var count: usize = 0;
        for (original.fields) |field| {
            const redacted = view.snapshot.redactor.apply(.{ .key = field.key, .value = .null_value }) orelse continue;
            safe[count] = field;
            if (redacted.value == .string) safe[count].kind_mask = schema_module.kindMask(.string);
            count += 1;
        }
        metadata.fields = safe[0..count];
        const reference = try journal.registerSchema(metadata);
        return .{ .owner = self, .journal = journal, .reference = reference, .definition = try journal.resolveSchema(reference) };
    }

    pub fn prewarmFormat(self: *Runtime, comptime scope: []const u8, comptime source: ?std.builtin.SourceLocation, comptime template: []const u8, comptime Args: type, comptime Fields: type) !SchemaBinding {
        return self.prewarmMetadata(schema_site.metadata(scope, source, template, Args, Fields));
    }

    pub fn loggerWithSchema(self: *Runtime, binding: SchemaBinding) !LoggerModule.Logger(prepared_module.Owner(Runtime), .trace) {
        if (binding.owner != @as(*anyopaque, @ptrCast(self)) or binding.journal != self.journal) return error.InvalidSchemaBinding;
        var canonical = binding;
        canonical.definition = try binding.journal.resolveSchema(binding.reference);
        return .init(.{ .runtime = self, .binding = canonical }, canonical.definition.scope);
    }

    pub fn threadLoggerWithSchema(self: *Runtime, attached: LoggerModule.Logger(thread_module.ThreadOwner(Runtime), .trace), binding: SchemaBinding) !LoggerModule.Logger(prepared_module.ThreadOwner(thread_module.ThreadOwner(Runtime)), .trace) {
        if (binding.owner != @as(*anyopaque, @ptrCast(self)) or binding.journal != attached.owner.producer_token.journal or attached.owner.registry.owner != self) return error.InvalidSchemaBinding;
        return .init(.{ .base = attached.owner, .binding = binding }, "attached");
    }

    fn routeMask(self: *Runtime, level: Level, scope: []const u8) u64 {
        if (admission_protocol.getResource(self)) |raw| {
            const snapshot: *const configurations.Snapshot = @ptrCast(@alignCast(raw));
            return routeMaskIn(snapshot, level, scope, admission_protocol.getFilterDecision(self, scope) orelse self.dynamicFilter().boundDecision(scope));
        }
        const bound = self.dynamicFilter().boundDecision(scope);
        const view = self.configurationManager().acquire();
        defer view.release();
        return routeMaskIn(view.snapshot, level, scope, bound);
    }

    fn routeMaskIn(snapshot: *const configurations.Snapshot, level: Level, scope: []const u8, bound: BoundDecision) u64 {
        const configured_level = if (bound.configuration_generation == snapshot.generation) bound.decision.level else if (snapshot.default_filter) |*filter| filter.threshold(scope) else .info;
        return snapshot.selection.mask(snapshot.routes, level, scope, configured_level);
    }

    pub fn activeAdmissions(self: *Runtime) u64 {
        var count = self.admission_gate.load(.acquire) & count_mask;
        if (self.thread_registry) |registry| count += registry.activeAdmissions();
        count += self.configuration_gate.load(.acquire) & count_mask;
        return count;
    }

    /// Guard only: sampling and counters are unaffected.
    pub fn enabled(self: *Runtime, level: Level, scope: []const u8) bool {
        if (self.state.load(.acquire) != .running or self.worker_error.load(.acquire) != 0) return false;
        return self.routeMask(level, scope) != 0;
    }

    pub fn enabledCached(self: *Runtime, level: Level, scope: []const u8, decision: FilterDecision) bool {
        _ = decision;
        if (self.admission_gate.load(.acquire) & closing_bit != 0 or self.worker_error.load(.acquire) != 0) return false;
        return self.routeMask(level, scope) != 0;
    }

    /// Pure route decision for validated thread handles. It neither acquires
    /// admission nor checks worker/closing state; the frontend checks those
    /// before using this as an early filtered path.
    pub fn filterEnabled(self: *Runtime, level: Level, scope: []const u8, decision: FilterDecision) bool {
        _ = decision;
        return self.routeMask(level, scope) != 0;
    }

    pub fn filteredThread(self: *Runtime, channel: u32) void {
        _ = self.countersFor(channel).filtered.fetchAdd(1, .monotonic);
    }

    /// These methods are called only by a validated, thread-affine channel
    /// owner, or while every channel gate is cut for maintenance.
    fn threadSnapshot(self: *Runtime, channel: u32, scope: []const u8) !struct { snapshot: *configurations.Snapshot, bound: BoundDecision } {
        const registry = self.thread_registry orelse return error.ThreadChannelsDisabled;
        if (channel == 0 or channel > registry.channelCount()) return error.InvalidChannel;
        const control = &registry.controls[channel - 1];
        const cookie = JournalModule.currentThreadCookie();
        if (cookie == 0 or cookie != control.channel.control.ownerCookie() or control.thread_id.load(.acquire) != std.Thread.getCurrentId()) return error.WrongThread;
        if (control.state.load(.acquire) == .available or control.generation.load(.acquire) != control.channel.control.generation()) return error.Retired;
        // enabled() can be called from a provider/formatter inside an admitted
        // event. Preserve that event's cached version instead of refreshing and
        // dropping its only cache pin while it still borrows the snapshot.
        if (admission_protocol.getChannel(self) == channel) {
            if (admission_protocol.getResource(self)) |raw| return .{ .snapshot = @ptrCast(@alignCast(raw)), .bound = admission_protocol.getFilterDecision(self, scope) orelse self.threadFilterDecision(channel, scope) };
        }
        const cache = &self.channelCaches().*[channel - 1];
        cache.channel = channel;
        const bound = self.threadFilterDecision(channel, scope);
        return .{ .snapshot = try self.configurationManager().acquireChannel(cache), .bound = bound };
    }

    pub fn enabledThreadCached(self: *Runtime, level: Level, scope: []const u8, decision: FilterDecision, channel: u32) bool {
        _ = decision;
        if (self.admission_gate.load(.acquire) & closing_bit != 0 or self.worker_error.load(.acquire) != 0) return false;
        const selected = self.threadSnapshot(channel, scope) catch return false;
        return routeMaskIn(selected.snapshot, level, scope, selected.bound) != 0;
    }

    pub fn filterThreadEnabled(self: *Runtime, level: Level, scope: []const u8, decision: FilterDecision, channel: u32) bool {
        _ = decision;
        const selected = self.threadSnapshot(channel, scope) catch return false;
        return routeMaskIn(selected.snapshot, level, scope, selected.bound) != 0;
    }

    fn threadFilterDecision(self: *Runtime, channel: u32, scope: []const u8) BoundDecision {
        if (admission_protocol.getFilterDecision(self, scope)) |decision| return decision;
        const cache = &self.channelCaches().*[channel - 1];
        if (cache.filter_decision.decision.generation != self.dynamicFilter().generation()) cache.filter_decision = self.dynamicFilter().boundDecision(scope);
        return cache.filter_decision;
    }

    fn filterGeneration(snapshot: *const configurations.Snapshot, bound: BoundDecision) u64 {
        return if (bound.configuration_generation == snapshot.generation) bound.decision.generation else snapshot.filter_generation;
    }

    pub fn releaseThreadConfigurationCache(self: *Runtime, channel: u32) void {
        const registry = self.thread_registry orelse return;
        if (channel == 0 or channel > registry.channelCount()) return;
        const control = &registry.controls[channel - 1];
        if (admission_protocol.getChannel(self) == channel or control.activeAdmissions() != 0) {
            self.recordError(error.OutstandingAdmission, .capture);
            return;
        }
        const cookie = JournalModule.currentThreadCookie();
        if (cookie == 0 or control.channel.control.ownerCookie() != cookie or control.thread_id.load(.acquire) != std.Thread.getCurrentId() or !control.channel.control.retired()) {
            self.recordError(error.InvalidDetachCapability, .capture);
            return;
        }
        self.configurationManager().releaseChannelCache(&self.channelCaches().*[channel - 1]);
        self.channelCaches().*[channel - 1].filter_decision = .{ .decision = .{ .level = .off, .generation = 0 }, .configuration_generation = 0 };
    }

    pub fn begin(self: *Runtime, level: Level, scope: []const u8) BeginResult {
        if (!self.acquireAdmission()) {
            _ = self.counters.rejected_closing.fetchAdd(1, .monotonic);
            return .closed;
        }
        return self.beginDecision(level, scope);
    }

    pub fn beginCached(self: *Runtime, level: Level, scope: []const u8, decision: FilterDecision) BeginResult {
        _ = decision;
        if (!self.acquireAdmission()) {
            _ = self.counters.rejected_closing.fetchAdd(1, .monotonic);
            return .closed;
        }
        return self.beginDecision(level, scope);
    }

    fn beginDecision(self: *Runtime, level: Level, scope: []const u8) BeginResult {
        const bound = self.dynamicFilter().boundDecision(scope);
        const view = self.configurationManager().acquire();
        var transferred = false;
        defer if (!transferred) view.release();
        const snapshot = view.snapshot;
        if (@import("builtin").is_test) if (TestingHooks.after_snapshot) |hook| hook(TestingHooks.context.?);
        var mask = routeMaskIn(snapshot, level, scope, bound);
        if (mask == 0) {
            self.end();
            _ = self.counters.filtered.fetchAdd(1, .monotonic);
            return .filtered;
        }
        mask = self.sampleRouteMask(snapshot, mask, level);
        if (mask == 0) {
            self.end();
            _ = self.counters.sampled.fetchAdd(1, .monotonic);
            return .sampled;
        }
        // The checked View already protects this snapshot. Transfer its reader
        // to the admitted call instead of converting it to another pending pin.
        // Accepted records still retain their independent pin before commit.
        admission_protocol.attachResource(self, snapshot, releaseAdmissionView);
        transferred = true;
        admission_protocol.attachFilterDecision(self, scope, bound);
        return .{ .ready = .{ .route_mask = mask, .config_generation = filterGeneration(snapshot, bound), .route_generation = snapshot.generation, .route_fingerprint = snapshot.fingerprint } };
    }

    /// Thread channels own their admission gate. Only TLS reentrancy context
    /// is shared with ordinary Logger; no global count CAS occurs here.
    pub fn enterThreadAdmission(self: *Runtime) bool {
        if (self.diagnostics.inHook() or self.inSinkCall() or self.worker_id.load(.acquire) == std.Thread.getCurrentId()) return false;
        return admission_protocol.enter(self);
    }

    pub fn endThread(self: *Runtime) void {
        admission_protocol.leave(self);
        self.dispatchDiagnostics();
    }

    pub fn threadAdmissionEnded(self: *Runtime) void {
        if (self.admission_gate.load(.acquire) & closing_bit != 0) self.notify();
    }

    pub fn beginThread(self: *Runtime, level: Level, scope: []const u8, decision: FilterDecision, channel: u32) BeginResult {
        _ = decision;
        const counters = self.countersFor(channel);
        const selected = self.threadSnapshot(channel, scope) catch |err| {
            self.recordError(err, .capture);
            return .closed;
        };
        const snapshot = selected.snapshot;
        const bound = selected.bound;
        var mask = routeMaskIn(snapshot, level, scope, bound);
        if (mask == 0) {
            _ = counters.filtered.fetchAdd(1, .monotonic);
            return .filtered;
        }
        mask = self.sampleRouteMask(snapshot, mask, level);
        if (mask == 0) {
            _ = counters.sampled.fetchAdd(1, .monotonic);
            return .sampled;
        }
        // The channel cache already pins this version. Its owner cannot refresh
        // or detach until this call ends; no shared pending RMW is necessary.
        admission_protocol.attachBorrowedResource(self, snapshot, channel);
        admission_protocol.attachFilterDecision(self, scope, bound);
        return .{ .ready = .{ .route_mask = mask, .config_generation = filterGeneration(snapshot, bound), .route_generation = snapshot.generation, .route_fingerprint = snapshot.fingerprint } };
    }

    fn releaseAdmissionView(raw: *anyopaque) void {
        const snapshot: *configurations.Snapshot = @ptrCast(@alignCast(raw));
        (@as(configurations.View, .{ .snapshot = snapshot })).release();
    }

    fn sampleRouteMask(self: *Runtime, snapshot: *configurations.Snapshot, selected: u64, level: Level) u64 {
        if (snapshot.sampling_overrides == 0) {
            if (snapshot.sample_bypass.allows(level)) return selected;
            const now = if (snapshot.sampler.config == .token_bucket) self.monotonicNs() else 0;
            return if (snapshot.sampler.allow(now)) selected else 0;
        }
        var mask = selected & ~snapshot.sampling_overrides;
        if (mask != 0 and !snapshot.sample_bypass.allows(level)) {
            const now = if (snapshot.sampler.config == .token_bucket) self.monotonicNs() else 0;
            if (!snapshot.sampler.allow(now)) mask = 0;
        }
        var local = selected & snapshot.sampling_overrides;
        while (local != 0) {
            const index: u6 = @intCast(@ctz(local));
            const bit = @as(u64, 1) << index;
            local &= ~bit;
            const policy = snapshot.routes[index].policy.?;
            const now = if (policy.sampler.?.config == .token_bucket and !policy.sample_bypass.allows(level)) self.monotonicNs() else 0;
            if (policy.sample_bypass.allows(level) or policy.sampler.?.allow(now)) mask |= bit;
        }
        return mask;
    }

    fn retainSnapshot(raw: *anyopaque) void {
        const snapshot: *configurations.Snapshot = @ptrCast(@alignCast(raw));
        snapshot.retain();
    }

    fn releaseSnapshot(raw: *anyopaque) void {
        const snapshot: *configurations.Snapshot = @ptrCast(@alignCast(raw));
        snapshot.release();
    }

    fn admittedSnapshot(self: *Runtime, admission: Admission) !*configurations.Snapshot {
        const raw = admission_protocol.getResource(self) orelse return error.InvalidAdmission;
        const snapshot: *configurations.Snapshot = @ptrCast(@alignCast(raw));
        if (snapshot.generation != admission.route_generation or snapshot.fingerprint != admission.route_fingerprint) return error.InvalidAdmission;
        return snapshot;
    }

    fn countersFor(self: *Runtime, channel: u32) *Counters {
        return if (channel == 0 or channel > self.channel_counters.len) &self.counters else &self.channel_counters[channel - 1];
    }

    pub fn end(self: *Runtime) void {
        admission_protocol.leave(self);
        const previous = admission_protocol.release(&self.admission_gate);
        if (previous & count_mask == 1 and previous & (closing_bit | cut_bit) != 0) {
            self.wakeAdmissions();
            if (previous & closing_bit != 0) self.notify();
        }
        self.dispatchDiagnostics();
    }

    fn acquireAdmission(self: *Runtime) bool {
        if (self.diagnostics.inHook()) return false;
        if (self.ownsAdmission() or self.inSinkCall() or self.worker_id.load(.acquire) == std.Thread.getCurrentId()) {
            self.recordError(error.RecursiveSubmission, .capture);
            return false;
        }
        if (admission_protocol.full()) {
            self.reportError(error.TooManyNestedSubmissions);
            return false;
        }
        if (!admission_protocol.acquire(&self.admission_gate, &self.admission_epoch, self.io)) return false;
        const entered = admission_protocol.enter(self);
        std.debug.assert(entered);
        return true;
    }

    fn wakeAdmissions(self: *Runtime) void {
        admission_protocol.wake(&self.admission_epoch, self.io);
    }

    fn ownsAdmission(self: *Runtime) bool {
        return admission_protocol.contains(self);
    }

    fn waitAdmissions(self: *Runtime) void {
        admission_protocol.wait(&self.admission_gate, &self.admission_epoch, self.io);
    }

    fn cutTargets(self: *Runtime, targets: *[65]u64) usize {
        self.cut_mutex.lockUncancelable(self.io);
        defer self.cut_mutex.unlock(self.io);
        _ = self.admission_gate.fetchOr(cut_bit, .acq_rel);
        defer {
            _ = self.admission_gate.fetchAnd(~cut_bit, .release);
            self.wakeAdmissions();
        }
        self.waitAdmissions();
        if (self.thread_registry) |registry| registry.beginCut();
        defer if (self.thread_registry) |registry| registry.endCut();
        var count: usize = 0;
        if (self.journal) |journal| {
            targets[count] = journal.reservationTarget();
            count += 1;
        }
        if (self.thread_registry) |registry| for (registry.activeJournals()) |channel| {
            targets[count] = channel.reservationTarget();
            count += 1;
        };
        return count;
    }

    pub fn nowNs(self: *Runtime) i64 {
        return self.clock.realNow(self.io);
    }

    fn monotonicNs(self: *Runtime) u64 {
        return self.clock.monotonicNow(self.io);
    }

    pub fn captureFailed(self: *Runtime, err: anyerror) void {
        _ = self.counters.capture_errors.fetchAdd(1, .monotonic);
        self.recordError(err, .capture);
    }

    pub fn reportError(self: *Runtime, err: anyerror) void {
        self.recordError(err, .bridge);
        if (!self.ownsAdmission() and self.worker_id.load(.acquire) != std.Thread.getCurrentId()) self.dispatchDiagnostics();
    }

    fn recordError(self: *Runtime, err: anyerror, source: diagnostics_module.ReportSource) void {
        self.last_error.store(@intFromError(err), .release);
        self.diagnostics.record(err, source);
    }

    fn dispatchDiagnostics(self: *Runtime) void {
        if (self.diagnostics.pending.load(.acquire) != 0) self.diagnostics.dispatch();
    }

    pub fn submit(self: *Runtime, admission: Admission, original: Event) !EmitResult {
        return self.submitDestination(admission, original, self.journal, null, null);
    }

    pub fn submitToJournal(self: *Runtime, admission: Admission, original: Event, journal: *Journal, producer_token: ?JournalModule.SingleProducerToken) !EmitResult {
        return self.submitDestination(admission, original, journal, producer_token, null);
    }

    pub fn submitWithSchema(self: *Runtime, admission: Admission, original: Event, binding: SchemaBinding) !EmitResult {
        if (binding.owner != @as(*anyopaque, @ptrCast(self)) or binding.journal != self.journal) return error.InvalidSchemaBinding;
        return self.submitDestination(admission, original, binding.journal, null, binding.reference);
    }

    pub fn submitToJournalWithSchema(self: *Runtime, admission: Admission, original: Event, journal: *Journal, token: ?JournalModule.SingleProducerToken, binding: SchemaBinding) !EmitResult {
        if (binding.owner != @as(*anyopaque, @ptrCast(self)) or binding.journal != journal) return error.InvalidSchemaBinding;
        return self.submitDestination(admission, original, journal, token, binding.reference);
    }

    fn submitDestination(self: *Runtime, admission: Admission, original: Event, destination: ?*Journal, producer_token: ?JournalModule.SingleProducerToken, binding: ?schema_module.Ref) !EmitResult {
        if (producer_token == null and original.channel != 0) return error.InvalidChannel;
        if (producer_token != null and (original.channel == 0 or original.channel > (if (self.thread_registry) |registry| registry.channelCount() else 0))) return error.InvalidChannel;
        const snapshot = try self.admittedSnapshot(admission);
        var event = original;
        // Validate the final borrowed tree once before predicates. Inline
        // carries its complete size; schema carries dynamic value/nested-key
        // bytes, leaving canonical shape/level checks at their original later
        // boundary. Redaction rewrites values and retains independent checks.
        const measured: ?usize = if (snapshot.redactor.rule_count == 0)
            (if (binding != null) @intCast(try @import("reference_encoding.zig").measureValues(original)) else try codec.measure(original))
        else blk: {
            var validator: @import("field.zig").ValueValidator = .{};
            try validator.fields(original.fields);
            try validator.arguments(original.format_args);
            break :blk null;
        };
        const context: SubmissionContext = .{ .admission = admission, .snapshot = snapshot, .destination = destination, .producer_token = producer_token, .binding = binding, .encoded_size = measured, .tree_validated = measured != null };
        if (snapshot.redactor.rule_count != 0)
            return @import("runtime_redaction.zig").submit(self, &snapshot.redactor, &event, &context, submitSafeDestination);
        return self.submitSafeDestination(&event, &context);
    }

    const SubmissionContext = struct {
        admission: Admission,
        snapshot: *configurations.Snapshot,
        destination: ?*Journal,
        producer_token: ?JournalModule.SingleProducerToken,
        // Owner/journal were checked by the public binding wrapper. Only its
        // stable reference is needed here; the caller's definition is untrusted
        // and the canonical definition is resolved at the original boundary.
        binding: ?schema_module.Ref,
        encoded_size: ?usize = null,
        tree_validated: bool = false,
    };

    fn submitSafeDestination(self: *Runtime, event: *Event, context: *const SubmissionContext) !EmitResult {
        const admission = context.admission;
        const snapshot = context.snapshot;
        const destination = context.destination;
        const producer_token = context.producer_token;
        const binding = context.binding;
        const counters = self.countersFor(event.channel);
        // Never trust a caller-supplied provenance hint. Only the admission
        // measurement in this call can authorize the internal delivery path.
        event.tree_validated = context.tree_validated;
        event.route_mask = admission.route_mask;
        event.config_generation = admission.config_generation;
        event.session = self.session;
        event.route_fingerprint = snapshot.fingerprint;
        event.route_generation = snapshot.generation;
        if (snapshot.predicate) |*predicate| if (!try predicate.matches(event.*)) {
            _ = counters.filtered.fetchAdd(1, .monotonic);
            return .filtered;
        };
        var predicate_routes = event.route_mask & snapshot.selection.predicates;
        while (predicate_routes != 0) {
            const index: u6 = @intCast(@ctz(predicate_routes));
            const bit = @as(u64, 1) << index;
            predicate_routes &= predicate_routes - 1;
            // The immutable selection was built from this exact route table.
            // Visit original indices in order, so later predicates still see
            // earlier rejected route bits removed from the current event.
            if (!try snapshot.routes[index].predicate.?.matches(event.*)) event.route_mask &= ~bit;
        }
        if (event.route_mask == 0) {
            _ = counters.filtered.fetchAdd(1, .monotonic);
            return .filtered;
        }
        if (self.workerError()) |err| return err;
        const definition: ?schema_module.Definition = if (binding) |prepared| blk: {
            const journal = destination orelse return error.InvalidSchemaBinding;
            const canonical = if (@hasDecl(Journal, "resolveReadySchema")) try journal.resolveReadySchema(prepared) else try journal.resolveSchema(prepared);
            // Always resolve canonical metadata; public binding copies are not
            // trusted. Normal encoding validates once after reserve succeeds.
            break :blk canonical;
        } else null;
        if (destination) |journal| {
            while (true) {
                const progress = if (producer_token != null) journal.single.space_epoch.load(.seq_cst) else self.progress_epoch.load(.acquire);
                const attempt = if (binding) |prepared|
                    (if (producer_token) |token| journal.reserveSingleProducerWithSchema(token, prepared) else journal.reserveWithSchema(prepared))
                else
                    (if (producer_token) |token| journal.reserveSingleProducer(token) else journal.reserve());
                var reservation = attempt catch |err| switch (err) {
                    error.Full => {
                        switch (self.overflow) {
                            .drop_newest => {
                                _ = counters.dropped_full.fetchAdd(1, .monotonic);
                                return .dropped_full;
                            },
                            .fallback_sync => {
                                // Full fallback cannot bypass a prepared shape
                                // contract merely because no slot was obtained.
                                if (definition) |canonical| _ = if (context.encoded_size) |values_bytes|
                                    try @import("reference_encoding.zig").sizeMeasured(event.*, canonical, values_bytes)
                                else
                                    try schema_codec.encodedReferenceSize(event.*, canonical);
                                var fallback = event.*;
                                // A synchronous bypass has a distinct channel
                                // namespace, so its local sequence cannot
                                // collide with a journal's session/channel/id.
                                fallback.channel |= @as(u32, 1) << 31;
                                return self.submitSync(fallback, snapshot);
                            },
                            .block => {
                                // One owner may wait on an SPSC queue. Register
                                // before checking terminal state; a concurrent
                                // notification either wakes us or changes the
                                // observed epoch, making futex wait return.
                                if (producer_token != null) journal.single.space_waiting.store(true, .seq_cst);
                                defer if (producer_token != null) journal.single.space_waiting.store(false, .seq_cst);
                                if (self.workerError()) |failure| return failure;
                                if (self.state.load(.acquire) != .running) {
                                    _ = counters.rejected_closing.fetchAdd(1, .monotonic);
                                    return .rejected_closing;
                                }
                                const epoch = if (producer_token != null) &journal.single.space_epoch.raw else &self.progress_epoch.raw;
                                self.io.futexWaitUncancelable(u32, epoch, progress);
                                continue;
                            },
                        }
                    },
                    else => return err,
                };
                defer reservation.abort();
                event.sequence = reservation.sequence;
                const encoded = if (definition) |canonical|
                    (if (context.encoded_size) |values_bytes|
                        @import("reference_encoding.zig").writeMeasured(event.*, canonical, values_bytes, reservation.buffer())
                    else
                        schema_codec.encodeReference(event.*, canonical, reservation.buffer()))
                else if (context.encoded_size) |size|
                    codec.encodeSized(event.*, size, reservation.buffer())
                else
                    codec.encode(event.*, reservation.buffer());
                const payload = encoded catch |err| {
                    reservation.abort();
                    self.notify();
                    if (err == error.BufferTooSmall or err == error.TooLarge) {
                        _ = counters.dropped_oversize.fetchAdd(1, .monotonic);
                        return .dropped_oversize;
                    }
                    self.reportError(err);
                    return err;
                };
                // Optional producer-side render. The binary journal stays the
                // recovery source; the volatile cache only lets the consumer
                // write pre-rendered bytes. Publish before commit so a
                // committed record always has a visible render.
                var render_claim: ?RenderCache.Claim = null;
                if (definition == null and binding == null and producer_token == null and destination == self.journal and event.route_mask == 1 and snapshot.routes.len == 1 and snapshot.routes[0].format == .json) {
                    const route = &snapshot.routes[0];
                    const redacted = if (route.policy) |policy| policy.redactor != null else false;
                    if (!redacted) if (self.renderCache()) |cache| if (cache.claim(reservation.sequence)) |claim| {
                        var writer = std.Io.Writer.fixed(claim.buffer);
                        if (common.encodeDecoded(.json, event.*, route.timestamp, &writer)) |_| {
                            claim.publish(writer.buffered().len);
                            render_claim = claim;
                        } else |_| {
                            claim.abort();
                        }
                    };
                }
                // Retain before publishing: the collector can consume the
                // record immediately after the release commit marker.
                snapshot.retainChannel(event.channel);
                reservation.commit(payload.len) catch |err| {
                    if (render_claim) |claim| claim.abort();
                    snapshot.releaseChannel(event.channel);
                    return err;
                };
                _ = counters.accepted.fetchAdd(1, .monotonic);
                self.notify();
                return .accepted;
            }
        }
        return self.submitSync(event.*, snapshot);
    }

    fn submitSync(self: *Runtime, original: Event, snapshot: *configurations.Snapshot) !EmitResult {
        self.delivery_mutex.lockUncancelable(self.io);
        defer self.delivery_mutex.unlock(self.io);
        var event = original;
        event.sequence = self.sync_sequence.fetchAdd(1, .monotonic) + 1;
        try self.deliverWith(snapshot, event);
        try self.flushWith(snapshot, event.route_mask, .written, false);
        _ = self.countersFor(event.channel).accepted.fetchAdd(1, .monotonic);
        _ = self.countersFor(event.channel).written.fetchAdd(1, .monotonic);
        return .accepted;
    }

    fn deliveryDiagnostics(self: *Runtime) delivery.ErrorRecorder {
        return .{ .context = self, .record = recordDeliveryError };
    }

    fn recordDeliveryError(context: *anyopaque, err: anyerror, source: diagnostics_module.ReportSource) void {
        const self: *Runtime = @ptrCast(@alignCast(context));
        if (source == .write) _ = self.counters.write_errors.fetchAdd(1, .monotonic);
        if (source == .flush) _ = self.counters.flush_errors.fetchAdd(1, .monotonic);
        if (source == .sync) _ = self.counters.sync_errors.fetchAdd(1, .monotonic);
        self.recordError(err, source);
    }

    fn deliverWith(self: *Runtime, snapshot: *configurations.Snapshot, event: Event) !void {
        const frame: SinkFrame = .{ .owner = self, .previous = sink_frame };
        sink_frame = &frame;
        defer sink_frame = frame.previous;
        return delivery.emit(snapshot.routes, self.output, event, self.deliveryDiagnostics());
    }

    fn flushWith(self: *Runtime, snapshot: *configurations.Snapshot, mask: u64, boundary: Flush, only_required: bool) !void {
        const frame: SinkFrame = .{ .owner = self, .previous = sink_frame };
        sink_frame = &frame;
        defer sink_frame = frame.previous;
        return delivery.flush(snapshot.routes, mask, boundary, only_required, self.deliveryDiagnostics());
    }

    fn inSinkCall(self: *Runtime) bool {
        var frame = sink_frame;
        while (frame) |current| : (frame = current.previous) if (current.owner == self) return true;
        return false;
    }

    fn notify(self: *Runtime) void {
        if (self.idle == .spin and self.state.load(.acquire) == .running) return;
        _ = self.wake_epoch.fetchAdd(1, .seq_cst);
        if (self.worker_sleeping.load(.seq_cst) or self.state.load(.acquire) != .running) {
            // Shutdown and the worker can both wait on this epoch. Waking only
            // one could strand shutdown after the worker exits.
            self.io.futexWake(u32, &self.wake_epoch.raw, std.math.maxInt(u32));
        }
    }

    fn notifyProgress(self: *Runtime) void {
        _ = self.progress_epoch.fetchAdd(1, .release);
        self.io.futexWake(u32, &self.progress_epoch.raw, std.math.maxInt(u32));
    }

    fn notifyJournalProgress(self: *Runtime, journal: *Journal) void {
        self.notifyProgress();
        if (journal.producer_mode == .single) self.notifySpace(journal);
    }

    fn notifySpace(self: *Runtime, journal: *Journal) void {
        _ = journal.single.space_epoch.fetchAdd(1, .seq_cst);
        if (journal.single.space_waiting.load(.seq_cst)) self.io.futexWake(u32, &journal.single.space_epoch.raw, 1);
    }

    fn notifyAllProgress(self: *Runtime) void {
        self.notifyProgress();
        if (self.thread_registry) |registry| for (registry.activeJournals()) |journal| self.notifySpace(journal);
    }

    fn workerError(self: *Runtime) ?anyerror {
        const code = self.worker_error.load(.acquire);
        return if (code == 0) null else @errorFromInt(code);
    }

    fn workerMain(self: *Runtime) void {
        self.worker_id.store(std.Thread.getCurrentId(), .release);
        self.worker_alive.store(true, .release);
        defer {
            self.worker_id.store(0, .release);
            self.worker_alive.store(false, .release);
            self.notifyAllProgress();
        }
        while (true) {
            const observed = self.wake_epoch.load(.seq_cst);
            const work = self.drainAvailable() catch |err| {
                self.worker_error.store(@intFromError(err), .release);
                self.recordError(err, .worker);
                self.dispatchDiagnostics();
                return;
            };
            self.dispatchDiagnostics();
            if (self.admission_gate.load(.acquire) & closing_bit != 0 and self.activeAdmissions() == 0 and self.totalPending() == 0) return;
            if (work) continue;
            if (self.idle == .spin) {
                std.atomic.spinLoopHint();
                continue;
            }
            self.worker_sleeping.store(true, .seq_cst);
            if (self.wake_epoch.load(.seq_cst) == observed) {
                self.io.futexWaitUncancelable(u32, &self.wake_epoch.raw, observed);
            }
            self.worker_sleeping.store(false, .seq_cst);
        }
    }

    fn totalPending(self: *Runtime) usize {
        var pending = if (self.journal) |journal| journal.pending() else 0;
        if (self.thread_registry) |registry| for (registry.activeJournals()) |channel| {
            pending += channel.pending();
        };
        return pending;
    }

    fn drainAvailable(self: *Runtime) !bool {
        var work = false;
        if (self.journal) |journal| work = try self.drainJournal(journal);
        if (self.thread_registry) |registry| for (registry.activeJournals()) |channel| {
            work = try self.drainJournal(channel) or work;
        };
        return work;
    }

    fn drainJournal(self: *Runtime, journal: *Journal) !bool {
        var worked = false;
        const render_cache = if (self.journal) |shared| (if (shared == journal) self.renderCache() else null) else null;
        var records: [delivery_batch.max_records]JournalModule.Record = undefined;
        var channels: [delivery_batch.max_records]u32 = undefined;
        var snapshots: [delivery_batch.max_records]*configurations.Snapshot = undefined;
        var boundaries: [delivery_batch.max_records]JournalModule.ReclaimBoundary = undefined;
        // A bounded queue quantum keeps the current batch's write/reclaim
        // boundary intact. The default retains four batches; applications can
        // select fewer to reduce the number of records served before peers.
        var budget: delivery_batch.ServiceBudget = .{ .remaining = self.consumer_batches_per_queue };
        while (budget.remaining != 0) {
            const before = journal.pending();
            const batch = if (@hasDecl(Journal, "peekBatchChecked")) try journal.peekBatchChecked(records[0..budget.capacity()]) else blk: {
                const record = journal.peek() orelse break :blk records[0..0];
                records[0] = record;
                break :blk records[0..1];
            };
            if (journal.pending() != before) self.notifyJournalProgress(journal);
            if (batch.len == 0) return worked;
            budget.consume(batch.len);
            worked = true;
            self.delivery_mutex.lockUncancelable(self.io);
            defer self.delivery_mutex.unlock(self.io);
            var versions = delivery_batch.Configurations.init(self.configurationManager());
            defer versions.deinit();
            var written_counts: delivery_batch.WrittenCounts = .{};
            defer written_counts.flush();
            for (batch, 0..) |record, index| {
                var fields: [codec.decode_scratch_fields]Field = undefined;
                const preformatted = if (render_cache) |cache| cache.lookup(record.sequence) else null;
                const definition: ?schema_module.Definition = if (record.schema_ref) |reference|
                    (if (@hasDecl(Journal, "resolveReadySchema")) try journal.resolveReadySchema(reference) else try journal.resolveSchema(reference))
                else
                    null;
                const fused = blk: {
                    // Reference setup is useful on backlog, but a producer-led
                    // short window can lose locality to the larger renderer.
                    // The original materialized path remains efficient there.
                    if (definition != null and batch.len < delivery_batch.records_per_quantum) break :blk false;
                    const header = if (definition) |canonical|
                        try schema_codec.readReferenceHeader(record.payload, canonical, fields.len)
                    else
                        codec.readHeader(record.payload, codec.version) catch |err| switch (err) {
                            error.UnsupportedVersion => break :blk false,
                            else => return err,
                        };
                    if (header.event.message_template or header.argument_count != 0) break :blk false;
                    const group = versions.select(header.event.route_generation, header.event.route_fingerprint) catch |err| {
                        // Reference decode historically precedes route lookup.
                        // Preserve its error priority on rejected routing too.
                        if (definition) |canonical| _ = try schema_codec.resolve(record.payload, canonical, &fields);
                        return err;
                    };
                    const snapshot = group.snapshot();
                    if (header.event.route_mask >> @intCast(snapshot.routes.len % 64) != 0 and snapshot.routes.len != 64) {
                        if (definition) |canonical| _ = try schema_codec.resolve(record.payload, canonical, &fields);
                        return error.UnknownRoute;
                    }
                    if (!try delivery.emitWireFused(snapshot.routes, header.event.route_mask, record.payload, header, definition, preformatted, self.output, &fields, self.deliveryDiagnostics())) break :blk false;
                    if (render_cache) |cache| cache.clear(record.sequence);
                    channels[index] = header.event.channel;
                    snapshots[index] = snapshot;
                    boundaries[index] = group.include(header.event.route_mask);
                    break :blk true;
                };
                if (fused) continue;
                const event = if (definition) |canonical| try schema_codec.resolve(record.payload, canonical, &fields) else try codec.decode(record.payload, &fields);
                const group = try versions.select(event.route_generation, event.route_fingerprint);
                const snapshot = group.snapshot();
                if (event.route_mask >> @intCast(snapshot.routes.len % 64) != 0 and snapshot.routes.len != 64) return error.UnknownRoute;
                try self.deliverWith(snapshot, event);
                if (render_cache) |cache| cache.clear(record.sequence);
                channels[index] = event.channel;
                snapshots[index] = snapshot;
                boundaries[index] = group.include(event.route_mask);
            }
            for (versions.groups()) |*group| {
                try self.flushWith(group.snapshot(), group.route_mask, .written, false);
                if (group.durable_mask != 0) try self.flushWith(group.snapshot(), group.durable_mask, .durable, true);
            }
            var release_keys: [delivery_batch.max_records]ReleaseKey = undefined;
            var release_len: usize = 0;
            defer {
                if (release_len != 0) for (release_keys[0..release_len]) |key| key.snapshot.releaseChannelCount(key.channel, key.count);
            }
            var written_run_start: usize = 0;
            for (batch, 0..) |record, index| {
                if (boundaries[index] == .written) continue;
                try self.releaseWrittenRun(journal, batch[written_run_start..index], channels[written_run_start..index], snapshots[written_run_start..index], &written_counts, release_keys[0..], &release_len);
                try journal.releaseAfter(record, boundaries[index]);
                written_counts.acknowledged(&self.countersFor(channels[index]).written);
                noteRelease(release_keys[0..], &release_len, snapshots[index], channels[index]);
                written_run_start = index + 1;
            }
            try self.releaseWrittenRun(journal, batch[written_run_start..], channels[written_run_start..batch.len], snapshots[written_run_start..batch.len], &written_counts, release_keys[0..], &release_len);
            for (release_keys[0..release_len]) |key| key.snapshot.releaseChannelCount(key.channel, key.count);
            release_len = 0;
            written_counts.flush();
            self.notifyJournalProgress(journal);
        }
        return worked;
    }

    fn releaseWrittenRun(
        self: *Runtime,
        journal: *Journal,
        run: []const JournalModule.Record,
        run_channels: []const u32,
        run_snapshots: []const *configurations.Snapshot,
        written_counts: *delivery_batch.WrittenCounts,
        release_keys: []ReleaseKey,
        release_len: *usize,
    ) !void {
        if (run.len == 0) return;
        var released: usize = 0;
        const result = journal.releaseBatchWritten(run, &released);
        for (run[0..released], run_channels[0..released], run_snapshots[0..released]) |_, channel, snapshot| {
            written_counts.acknowledged(&self.countersFor(channel).written);
            noteRelease(release_keys, release_len, snapshot, channel);
        }
        try result;
    }

    fn noteRelease(keys: []ReleaseKey, len: *usize, snapshot: *configurations.Snapshot, channel: u32) void {
        for (keys[0..len.*]) |*key| {
            if (key.snapshot == snapshot and key.channel == channel) {
                key.count += 1;
                return;
            }
        }
        keys[len.*] = .{ .snapshot = snapshot, .channel = channel, .count = 1 };
        len.* += 1;
    }

    fn decodeRecord(journal: *Journal, record: JournalModule.Record, fields: []Field) !Event {
        return if (record.schema_ref) |reference|
            schema_codec.resolve(record.payload, if (@hasDecl(Journal, "resolveReadySchema")) try journal.resolveReadySchema(reference) else try journal.resolveSchema(reference), fields)
        else
            codec.decode(record.payload, fields);
    }

    pub fn reloadFilter(self: *Runtime, spec: []const u8) !void {
        try self.beginConfiguration();
        defer self.endConfiguration();
        const replacement = try Filter.parse(spec);
        self.configuration_mutex.lockUncancelable(self.io);
        defer self.configuration_mutex.unlock(self.io);
        if (self.state.load(.acquire) != .running) return error.Closed;
        if (self.dynamicFilter().generation() == std.math.maxInt(u64)) return error.FilterGenerationExhausted;
        self.dynamicFilter().publishBound(replacement, self.configurationManager().currentGeneration());
    }

    /// Explicit reload on an application/configuration thread. No filesystem
    /// access is performed by individual log calls or signal handlers.
    pub fn reloadFilterFile(self: *Runtime, path: []const u8) !void {
        if (self.state.load(.acquire) != .running) return error.Closed;
        const specification = try std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .limited(16 * 1024));
        defer self.allocator.free(specification);
        try self.reloadFilter(std.mem.trim(u8, specification, " \t\r\n"));
    }

    pub fn setLevel(self: *Runtime, level: Level) void {
        self.setLevelChecked(level) catch |err| self.recordError(err, .capture);
    }

    pub fn setLevelChecked(self: *Runtime, level: Level) !void {
        try self.beginConfiguration();
        defer self.endConfiguration();
        self.configuration_mutex.lockUncancelable(self.io);
        defer self.configuration_mutex.unlock(self.io);
        if (self.state.load(.acquire) != .running) return error.Closed;
        if (self.dynamicFilter().generation() == std.math.maxInt(u64)) return error.FilterGenerationExhausted;
        const view = self.configurationManager().acquire();
        defer view.release();
        const bound = self.dynamicFilter().boundFilter();
        var replacement = if (bound.configuration_generation == view.snapshot.generation) bound.filter else view.snapshot.default_filter.?;
        replacement.default_level = level;
        self.dynamicFilter().publishBound(replacement, view.snapshot.generation);
    }

    pub fn flush(self: *Runtime, boundary: Flush) !void {
        return self.flushAllVersions(boundary);
    }

    /// Timed operations pin the selected configuration independently of the
    /// caller. Timeout never redirects the operation to a newer target.
    pub fn flushUntil(self: *Runtime, boundary: Flush, deadline: Deadline) !void {
        try self.checkControlCaller();
        if (boundary == .durable and !self.historical_durable_supported.load(.acquire)) return error.UnsupportedDurability;
        const view = self.configurationManager().acquire();
        defer view.release();
        try self.control.?.invoke(.{ .flush = .{
            .route_mask = 0,
            .boundary = @intFromEnum(boundary),
            .all_versions = true,
            .lifetime = .{ .context = view.snapshot, .retain = retainSnapshot, .release = releaseSnapshot },
        } }, deadline);
    }

    pub fn flushRoutesUntil(self: *Runtime, names: []const []const u8, boundary: Flush, deadline: Deadline) !void {
        try self.checkControlCaller();
        const view = self.configurationManager().acquire();
        defer view.release();
        const mask = try namedMask(view.snapshot, names);
        try delivery.validateBoundary(view.snapshot.routes, mask, boundary);
        try self.control.?.invoke(.{ .flush = .{
            .route_mask = mask,
            .boundary = @intFromEnum(boundary),
            .route_generation = view.snapshot.generation,
            .route_fingerprint = view.snapshot.fingerprint,
            .lifetime = .{ .context = view.snapshot, .retain = retainSnapshot, .release = releaseSnapshot },
        } }, deadline);
    }

    /// Initiates admission closure before waiting. Timeout leaves the runtime
    /// closing and every referenced object alive. Retry shutdown to confirm.
    pub fn shutdownUntil(self: *Runtime, deadline: Deadline) !void {
        try self.checkControlCaller();
        if (deadline.expired(self.io)) return error.Timeout;
        self.closeAdmission();
        try self.control.?.invoke(.shutdown, deadline);
    }

    pub fn controlStatus(self: *Runtime) control_module.Status {
        return if (self.control) |control| control.status() else .{
            .available = false,
            .busy = false,
            .detached = false,
            .completed_operations = 0,
            .timed_out_operations = 0,
            .last_error = null,
        };
    }

    fn runControl(context: *anyopaque, task: control_module.Task) anyerror!void {
        const self: *Runtime = @ptrCast(@alignCast(context));
        switch (task) {
            .flush => |command| if (command.all_versions) {
                try self.flushAllVersions(@enumFromInt(command.boundary));
            } else {
                const view = try self.configurationManager().find(command.route_generation, command.route_fingerprint);
                defer view.release();
                try self.flushSnapshotMask(view.snapshot, command.route_mask, @enumFromInt(command.boundary));
            },
            .shutdown => try self.shutdown(.drain),
        }
    }

    fn checkControlCaller(self: *Runtime) !void {
        try self.checkControlContext();
        if (self.control == null) return error.TimedControlUnavailable;
    }

    /// Preflight a composed owner's blocking operation before touching any
    /// pipeline. This rejects callbacks which could wait for themselves.
    pub fn checkControlContext(self: *Runtime) !void {
        if (self.diagnostics.inHook()) return error.DiagnosticReentrant;
        if (cleanup_owner == self) return error.ConfigurationReentrant;
        if (self.worker_id.load(.acquire) == std.Thread.getCurrentId()) return error.WorkerReentrant;
        if (self.ownsAdmission()) return error.ProducerReentrant;
        if (self.control) |control| if (control.isWorker()) return error.ControlReentrant;
        if (self.inSinkCall()) return error.SinkReentrant;
    }

    /// Close admission without waiting, so a composed owner can stop all
    /// pipelines before draining any of them. Resources remain owned.
    pub fn stopAccepting(self: *Runtime) !void {
        try self.checkControlContext();
        self.closeAdmission();
    }

    fn namedMask(snapshot: *const configurations.Snapshot, names: []const []const u8) !u64 {
        var mask: u64 = 0;
        for (names) |name| {
            var found = false;
            for (snapshot.routes, 0..) |*route, i| if (std.mem.eql(u8, route.name, name)) {
                mask |= @as(u64, 1) << @intCast(i);
                found = true;
                break;
            };
            if (!found) return error.UnknownRoute;
        }
        return mask;
    }

    fn requiredMask(snapshot: *const configurations.Snapshot) u64 {
        var mask: u64 = 0;
        for (snapshot.routes, 0..) |*route, i| if (route.delivery == .required) {
            mask |= @as(u64, 1) << @intCast(i);
        };
        return mask;
    }

    pub fn flushRoutes(self: *Runtime, names: []const []const u8, boundary: Flush) !void {
        const view = self.configurationManager().acquire();
        defer view.release();
        return self.flushSnapshotMask(view.snapshot, try namedMask(view.snapshot, names), boundary);
    }

    fn checkFlushCaller(self: *Runtime) !void {
        if (self.diagnostics.inHook()) return error.DiagnosticReentrant;
        if (self.worker_id.load(.acquire) == std.Thread.getCurrentId()) return error.WorkerReentrant;
        if (self.ownsAdmission()) return error.ProducerReentrant;
        if (self.inSinkCall()) return if (self.control) |control| (if (control.isWorker()) error.ControlReentrant else error.SinkReentrant) else error.SinkReentrant;
    }

    fn waitForCut(self: *Runtime) !void {
        var targets: [65]u64 = undefined;
        _ = self.cutTargets(&targets);
        var journals: [65]*Journal = undefined;
        const count = self.collectJournals(&journals);
        self.notify();
        for (journals[0..count], targets[0..count]) |journal, target| {
            while (journal.writtenTarget() < target) {
                const progress = self.progress_epoch.load(.acquire);
                if (self.workerError()) |err| return err;
                if (journal.writtenTarget() >= target) break;
                self.io.futexWaitUncancelable(u32, &self.progress_epoch.raw, progress);
            }
        }
    }

    fn flushSnapshotMask(self: *Runtime, snapshot: *configurations.Snapshot, mask: u64, boundary: Flush) !void {
        try self.checkFlushCaller();
        defer self.dispatchDiagnostics();
        try delivery.validateBoundary(snapshot.routes, mask, boundary);
        try self.waitForCut();
        self.delivery_mutex.lockUncancelable(self.io);
        defer self.delivery_mutex.unlock(self.io);
        if (boundary != .drain) try self.flushWith(snapshot, mask, boundary, false);
        if (boundary == .durable) {
            var journals: [65]*Journal = undefined;
            const count = self.collectJournals(&journals);
            // A subset cannot certify the other historical targets.
            for (journals[0..count]) |journal| if (journal.isPersistent()) try journal.sync();
        }
    }

    fn flushAllVersions(self: *Runtime, boundary: Flush) !void {
        try self.checkFlushCaller();
        defer self.dispatchDiagnostics();
        if (boundary == .durable and !self.historical_durable_supported.load(.acquire)) return error.UnsupportedDurability;
        try self.waitForCut();
        self.configuration_mutex.lockUncancelable(self.io);
        defer self.configuration_mutex.unlock(self.io);
        self.delivery_mutex.lockUncancelable(self.io);
        defer self.delivery_mutex.unlock(self.io);
        var storage: [64]configurations.View = undefined;
        const views = try self.configurationManager().retainedViews(&storage);
        defer for (views) |view| view.release();
        if (boundary != .drain) for (views) |view| {
            try self.flushWith(view.snapshot, requiredMask(view.snapshot), boundary, true);
        };
        if (boundary == .durable) {
            var journals: [65]*Journal = undefined;
            const count = self.collectJournals(&journals);
            for (journals[0..count]) |journal| if (journal.isPersistent()) try journal.checkpointWrittenDurable();
        }
    }

    fn collectJournals(self: *Runtime, journals: *[65]*Journal) usize {
        var count: usize = 0;
        if (self.journal) |journal| {
            journals[count] = journal;
            count += 1;
        }
        if (self.thread_registry) |registry| for (registry.activeJournals()) |channel| {
            journals[count] = channel;
            count += 1;
        };
        return count;
    }

    pub fn shutdown(self: *Runtime, mode: enum { drain }) !void {
        _ = mode;
        if (self.diagnostics.inHook()) return error.DiagnosticReentrant;
        if (cleanup_owner == self) return error.ConfigurationReentrant;
        if (self.worker_id.load(.acquire) == std.Thread.getCurrentId()) return error.WorkerReentrant;
        if (self.ownsAdmission()) return error.ProducerReentrant;
        if (self.inSinkCall()) return if (self.control) |control| (if (control.isWorker()) error.ControlReentrant else error.SinkReentrant) else error.SinkReentrant;
        defer self.dispatchDiagnostics();
        self.shutdown_mutex.lockUncancelable(self.io);
        defer self.shutdown_mutex.unlock(self.io);
        if (self.state.load(.acquire) == .closed) {
            const failure = self.shutdown_error.load(.acquire);
            if (failure != 0) return @errorFromInt(failure);
            return;
        }
        self.closeAdmission();
        self.waitAdmissions();
        admission_protocol.wait(&self.configuration_gate, &self.configuration_epoch, self.io);
        if (self.thread_registry) |registry| registry.waitAdmissions();
        self.notify();
        if (self.worker) |worker| {
            worker.join();
            self.worker = null;
        }
        var failure: ?anyerror = self.workerError();
        if (failure == null) shutdown_flush: {
            self.delivery_mutex.lockUncancelable(self.io);
            defer self.delivery_mutex.unlock(self.io);
            var view_storage: [64]configurations.View = undefined;
            const views = self.configurationManager().retainedViews(&view_storage) catch |err| {
                failure = err;
                break :shutdown_flush;
            };
            defer for (views) |view| view.release();
            for (views) |view| self.flushWith(view.snapshot, std.math.maxInt(u64), .written, false) catch |err| {
                failure = err;
                break;
            };
        }
        self.shutdown_error.store(if (failure) |err| @intFromError(err) else 0, .release);
        // Closed means the final sink barrier has finished, including failure.
        // A timed caller observing a still-blocked barrier sees closing.
        self.state.store(.closed, .release);
        if (failure) |err| return err;
    }

    fn closeAdmission(self: *Runtime) void {
        // The global closing bit is the collector's exit publication. Publish
        // only after all thread gates are closed, before waiting for users.
        if (self.thread_registry) |registry| registry.retireAll();
        _ = self.configuration_gate.fetchOr(closing_bit, .acq_rel);
        _ = self.admission_gate.fetchOr(closing_bit, .acq_rel);
        _ = self.state.cmpxchgStrong(.running, .closing, .release, .monotonic);
        self.wakeAdmissions();
        self.notify();
        self.notifyAllProgress();
    }

    pub fn currentConfiguration(self: *Runtime) ConfigurationVersion {
        return self.configurationManager().currentVersion();
    }

    pub fn configurationReadyToCollect(self: *Runtime, version: ConfigurationVersion) bool {
        return runtime_configuration.ready(self.configurationManager(), version);
    }

    fn beginConfiguration(self: *Runtime) !void {
        if (self.diagnostics.inHook()) return error.DiagnosticReentrant;
        if (self.ownsAdmission()) return error.ProducerReentrant;
        if (self.worker_id.load(.acquire) == std.Thread.getCurrentId()) return error.WorkerReentrant;
        if (self.inSinkCall()) return error.SinkReentrant;
        if (!admission_protocol.acquire(&self.configuration_gate, &self.configuration_epoch, self.io)) return error.Closed;
    }

    fn endConfiguration(self: *Runtime) void {
        const previous = admission_protocol.release(&self.configuration_gate);
        if (previous & count_mask == 1 and previous & closing_bit != 0) {
            admission_protocol.wake(&self.configuration_epoch, self.io);
            self.notify();
        }
    }

    pub fn replaceConfiguration(self: *Runtime, routes: []const RouteOptions, policy: Configuration) !ConfigurationVersion {
        try self.beginConfiguration();
        defer self.endConfiguration();
        return runtime_configuration.replace(self, self.configurationManager(), self.dynamicFilter(), routes, policy);
    }

    /// Explicit full transaction; supplied file/environment/API values are
    /// merged once and then copied into the same route/policy snapshot.
    pub fn replaceConfigurationSources(self: *Runtime, routes: []const RouteOptions, sources: @import("../config/sources.zig").Sources) !ConfigurationVersion {
        const merged = @import("../config/sources.zig").merge(sources);
        return self.replaceConfiguration(routes, merged.policy());
    }

    /// Load a bounded application JSON policy on a configuration thread.
    /// Document storage lives through installation; successful publication
    /// owns all metadata independently of both the file and environment.
    pub fn replaceConfigurationFile(self: *Runtime, routes: []const RouteOptions, path: []const u8, sources: @import("../config/sources.zig").Sources) !ConfigurationVersion {
        const document_module = @import("../config/document.zig");
        if (self.state.load(.acquire) != .running) return error.Closed;
        const bytes = try std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .limited(document_module.max_document_bytes));
        defer self.allocator.free(bytes);
        var document = try document_module.Document.parse(self.allocator, bytes);
        defer document.deinit();
        var combined = sources;
        combined.file = document.override();
        return self.replaceConfigurationSources(routes, combined);
    }

    pub fn collectConfigurations(self: *Runtime) !usize {
        try self.beginConfiguration();
        defer self.endConfiguration();
        const ready = try runtime_configuration.prepareCollection(self, self.configurationManager(), flushWith, requiredMask);
        const previous_cleanup = cleanup_owner;
        cleanup_owner = self;
        defer cleanup_owner = previous_cleanup;
        return self.configurationManager().collectVersions(ready.versions[0..ready.count]);
    }

    pub fn queueStorage(self: *Runtime) QueueStorage {
        const queue = self.journal orelse return .none;
        return if (queue.isPersistent()) .mmap else .memory;
    }

    pub fn health(self: *Runtime) Health {
        const code = self.last_error.load(.acquire);
        var high_water: usize = 0;
        var mapped_bytes: usize = 0;
        var queue_bytes: usize = 0;
        var journals: [65]*Journal = undefined;
        const count = self.collectJournals(&journals);
        for (journals[0..count]) |journal| {
            high_water += journal.highWater();
            queue_bytes += journal.mappedBytes();
            if (journal.isPersistent()) mapped_bytes += journal.mappedBytes();
        }
        return .{
            .accepted = self.counterTotal("accepted"),
            .filtered = self.counterTotal("filtered"),
            .sampled = self.counterTotal("sampled"),
            .dropped_full = self.counterTotal("dropped_full"),
            .dropped_oversize = self.counterTotal("dropped_oversize"),
            .rejected_closing = self.counterTotal("rejected_closing"),
            .written = self.counterTotal("written"),
            .write_errors = self.counters.write_errors.load(.monotonic),
            .flush_errors = self.counters.flush_errors.load(.monotonic),
            .sync_errors = self.counters.sync_errors.load(.monotonic),
            .capture_errors = self.counters.capture_errors.load(.monotonic),
            .recovered = self.counters.recovered.load(.monotonic),
            .journal_pending = self.totalPending(),
            // Sum of per-channel peaks, not a simultaneous total peak.
            .journal_high_water = high_water,
            .journal_reserved_bytes = mapped_bytes,
            .queue_storage = self.queueStorage(),
            .queue_reserved_bytes = queue_bytes,
            .thread_channels = if (self.thread_registry) |registry| registry.channelCount() else 0,
            .worker_alive = self.worker_alive.load(.acquire),
            .last_error = if (code == 0) null else @errorFromInt(code),
            .state = self.state.load(.acquire),
        };
    }

    fn counterTotal(self: *Runtime, comptime name: []const u8) u64 {
        var sum = @field(self.counters, name).load(.monotonic);
        if (self.thread_registry) |registry| for (self.channel_counters[0..registry.channelCount()]) |*counters| {
            sum += @field(counters, name).load(.monotonic);
        };
        return sum;
    }

    pub fn destroy(self: *Runtime) void {
        if (self.diagnostics.inHook() or self.ownsAdmission() or self.inSinkCall() or cleanup_owner == self or self.worker_id.load(.acquire) == std.Thread.getCurrentId() or (if (self.control) |control| control.isWorker() else false)) @panic("destroy requires all callbacks and producers to have stopped");
        if (self.control) |control| control.destroy();
        self.control = null;
        self.shutdown(.drain) catch {};
        if (self.state.load(.acquire) != .closed or self.worker != null or self.activeAdmissions() != 0 or self.diagnostics.hook_active.load(.acquire)) {
            @panic("destroy requires a joined runtime with no active submissions or diagnostic hooks");
        }
        const allocator = self.allocator;
        for (self.channelCaches()) |*cache| if (cache.channel != 0) self.configurationManager().releaseChannelCache(cache);
        if (self.thread_registry) |registry| registry.destroy();
        if (self.journal) |journal| journal.deinit();
        self.configurationManager().discardPinsAfterStop();
        const previous_cleanup = cleanup_owner;
        cleanup_owner = self;
        defer cleanup_owner = previous_cleanup;
        self.configurationManager().destroy();
        if (self.renderCache()) |cache| cache.destroy();
        allocator.destroy(self.runtimeCaches());
        self.dynamicFilter().destroy();
        allocator.free(self.output);
        allocator.destroy(self);
    }
};

test {
    _ = @import("render_cache.zig");
    _ = @import("tests/runtime_queue_progress.zig");
    _ = @import("tests/runtime_coalesced.zig");
    _ = @import("tests/runtime.zig");
    _ = @import("tests/runtime_delivery.zig");
}
