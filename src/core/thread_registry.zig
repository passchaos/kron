//! Fixed-budget thread channels. All journals and controls are allocated before
//! attachment and stay at stable addresses until destroy. Retirement closes
//! frontend admission while keeping committed data available to the collector.
const std = @import("std");
const logger = @import("logger.zig");
const spsc = @import("../journal/spsc.zig");
const journal_module = @import("../journal/journal.zig");
const cache_module = @import("../config/cache.zig");
pub const Journal = journal_module.Journal;
pub const ProducerToken = spsc.ProducerToken;
pub const max_scope_bytes = 128;
pub const closing_bit: usize = @as(usize, 1) << (@bitSizeOf(usize) - 1);
pub const cut_bit: usize = closing_bit >> 1;
pub const count_mask: usize = cut_bit - 1;
const Atomic = std.atomic.Value;

pub const Options = struct {
    max_channels: usize,
    journal_path_prefix: []const u8,
    capacity: usize,
    max_record_bytes: usize,
    schema_capacity: usize = 0,
    max_schema_bytes: usize = 8192,
    memory: bool = false,
};

pub const ChannelState = enum(u8) { available, attached, retiring };

pub fn Registry(comptime R: type) type {
    return struct {
        const Self = @This();
        pub const Control = struct {
            channel: *spsc.SpscJournal,
            state: Atomic(ChannelState) = .init(.available),
            generation: Atomic(u64),
            thread_id: Atomic(std.Thread.Id) = .init(0),
            admission_gate: Atomic(usize) align(64) = .init(0),
            admission_epoch: Atomic(u32) align(64) = .init(0),
            scope_buffer: [max_scope_bytes]u8 = undefined,
            scope_len: usize = 0,
            cache: cache_module.CachedFilter = undefined,

            fn scope(self: *const Control) []const u8 {
                return self.scope_buffer[0..self.scope_len];
            }

            pub fn activeAdmissions(self: *const Control) usize {
                return self.admission_gate.load(.acquire) & count_mask;
            }

            fn wake(self: *Control, io: std.Io) void {
                _ = self.admission_epoch.fetchAdd(1, .release);
                io.futexWake(u32, &self.admission_epoch.raw, std.math.maxInt(u32));
            }

            fn acquire(self: *Control, io: std.Io) bool {
                while (true) {
                    // Read the epoch before checking gate state. endCut or
                    // retireAll either changes it before futex registration,
                    // making the wait return immediately, or wakes that wait.
                    const epoch = self.admission_epoch.load(.acquire);
                    const gate = self.admission_gate.load(.acquire);
                    if (gate & closing_bit != 0) return false;
                    // An admitted owner may log recursively while finishing
                    // its event. Blocking that same thread on a cut would
                    // prevent its outer count from ever reaching zero.
                    if (gate & cut_bit != 0 and gate & count_mask == 0) {
                        io.futexWaitUncancelable(u32, &self.admission_epoch.raw, epoch);
                        continue;
                    }
                    if (gate & count_mask == count_mask) return false;
                    if (self.admission_gate.cmpxchgWeak(gate, gate + 1, .acq_rel, .acquire) == null) return true;
                }
            }

            fn release(self: *Control, io: std.Io) void {
                const previous = self.admission_gate.fetchSub(1, .acq_rel);
                std.debug.assert(previous & count_mask != 0);
                if (previous & count_mask == 1 and previous & (closing_bit | cut_bit) != 0) self.wake(io);
            }
        };

        allocator: std.mem.Allocator,
        io: std.Io,
        owner: *R,
        controls: []Control,
        journals: []*Journal,
        closing: Atomic(bool) = .init(false),
        lifecycle_mutex: std.Io.Mutex = .init,

        pub fn create(allocator: std.mem.Allocator, io: std.Io, owner: *R, options: Options) !*Self {
            if (options.max_channels == 0 or options.max_channels > std.math.maxInt(u32) or
                (!options.memory and options.journal_path_prefix.len == 0) or options.capacity == 0 or options.max_record_bytes == 0)
                return error.InvalidOptions;
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);
            const controls = try allocator.alloc(Control, options.max_channels);
            errdefer allocator.free(controls);
            const journals = try allocator.alloc(*Journal, options.max_channels);
            errdefer allocator.free(journals);
            var initialized: usize = 0;
            errdefer for (controls[0..initialized]) |*control| control.channel.deinit();
            for (controls, journals, 0..) |*control, *journal, index| {
                const path = if (options.memory) null else try std.fmt.allocPrint(allocator, "{s}.thread-{d}.journal", .{ options.journal_path_prefix, index });
                defer if (path) |owned| allocator.free(owned);
                const channel_options: spsc.Options = .{
                    .path = path orelse "",
                    .capacity = options.capacity,
                    .max_record_bytes = options.max_record_bytes,
                    .schema_capacity = options.schema_capacity,
                    .max_schema_bytes = options.max_schema_bytes,
                };
                const channel = if (options.memory) try spsc.SpscJournal.createMemory(allocator, io, channel_options) else try spsc.SpscJournal.create(allocator, io, channel_options);
                errdefer channel.deinit();
                try channel.retire();
                control.* = .{ .channel = channel, .generation = .init(channel.control.generation()) };
                journal.* = channel.journal;
                initialized += 1;
            }
            self.* = .{ .allocator = allocator, .io = io, .owner = owner, .controls = controls, .journals = journals };
            return self;
        }

        /// Scope storage, cache and token generation belong to this attachment.
        /// Copies of the returned frontend share its token, never a mutable
        /// owner object that could silently acquire a future attachment.
        /// The frontend's scope field is a static label; use copyScope to
        /// inspect the actual attachment scope without exposing reusable data.
        pub fn attach(self: *Self, scope: []const u8) !logger.Logger(ThreadOwner(R), .trace) {
            if (scope.len > max_scope_bytes) return error.ScopeTooLong;
            if (@hasField(R, "diagnostics")) {
                if (self.owner.diagnostics.inHook()) return error.ProducerReentrant;
            }
            self.lifecycle_mutex.lockUncancelable(self.io);
            defer self.lifecycle_mutex.unlock(self.io);
            if (self.closing.load(.acquire) or self.owner.state.load(.acquire) != .running) return error.Closing;
            for (self.controls, 0..) |*control, index| {
                if (control.state.load(.acquire) != .available) continue;
                std.debug.assert(control.activeAdmissions() == 0);
                const token = try control.channel.reactivate();
                @memcpy(control.scope_buffer[0..scope.len], scope);
                control.scope_len = scope.len;
                control.cache = if (@hasDecl(R, "configuration_bound_filter")) undefined else cache_module.CachedFilter.init(self.owner.filter, control.scope());
                const thread_id = std.Thread.getCurrentId();
                control.thread_id.store(thread_id, .monotonic);
                control.generation.store(token.generation, .release);
                control.state.store(.attached, .release);
                // retireAll can close gates without taking the lifecycle
                // mutex. Never clear its flags while publishing attachment.
                if (self.closing.load(.acquire) or self.owner.state.load(.acquire) != .running) {
                    try control.channel.journal.retireSingleProducer(token);
                    control.state.store(.available, .release);
                    return error.Closing;
                }
                return .init(.{
                    .registry = self,
                    .control_index = index,
                    .producer_token = token,
                    .generation = token.generation,
                    .thread_id = thread_id,
                    .thread_cookie = control.channel.control.ownerCookie(),
                }, "attached");
            }
            return error.ChannelsExhausted;
        }

        pub fn getJournal(self: *const Self, index: usize) *Journal {
            return self.journals[index];
        }

        /// Includes every preallocated channel, including unattached recovered
        /// journals and retired channels whose records still need delivery.
        pub fn activeJournals(self: *const Self) []const *Journal {
            return self.journals;
        }

        pub fn channelCount(self: *const Self) usize {
            return self.journals.len;
        }

        /// Hold the lifecycle mutex until endCut, so attachment cannot add a
        /// producer while all channel tails are being snapshotted. All gates
        /// are cut before waiting for counts; each successful pre-cut CAS is
        /// therefore included, and a post-cut CAS cannot acquire admission.
        pub fn beginCut(self: *Self) void {
            self.lifecycle_mutex.lockUncancelable(self.io);
            for (self.controls) |*control| _ = control.admission_gate.fetchOr(cut_bit, .acq_rel);
            self.waitAdmissions();
        }

        pub fn endCut(self: *Self) void {
            for (self.controls) |*control| {
                _ = control.admission_gate.fetchAnd(~cut_bit, .release);
                control.wake(self.io);
            }
            self.lifecycle_mutex.unlock(self.io);
        }

        /// Counts are stable at zero when called after beginCut or retireAll.
        /// Without a closed gate, this only waits to observe a zero count and
        /// yields instead of sleeping: ordinary producers perform no wake.
        pub fn waitAdmissions(self: *Self) void {
            for (self.controls) |*control| {
                while (true) {
                    const epoch = control.admission_epoch.load(.acquire);
                    const gate = control.admission_gate.load(.acquire);
                    if (gate & count_mask == 0) break;
                    if (gate & (closing_bit | cut_bit) != 0) {
                        self.io.futexWaitUncancelable(u32, &control.admission_epoch.raw, epoch);
                    } else {
                        std.Thread.yield() catch {};
                    }
                }
            }
        }

        pub fn activeAdmissions(self: *const Self) usize {
            var count: usize = 0;
            for (self.controls) |*control| count += control.activeAdmissions();
            return count;
        }

        /// Called from shutdown on any thread. SPSC ownership stays intact so
        /// admitted calls can finish and the owner can safely detach later.
        pub fn retireAll(self: *Self) void {
            self.closing.store(true, .release);
            for (self.controls) |*control| {
                _ = control.admission_gate.fetchOr(closing_bit, .acq_rel);
                _ = control.state.cmpxchgStrong(.attached, .retiring, .acq_rel, .acquire);
                control.wake(self.io);
            }
        }

        /// Stop all frontend, collector and sync callers before destruction.
        /// retireAll alone does not free memory or authorize stale pointer use.
        pub fn destroy(self: *Self) void {
            self.retireAll();
            for (self.controls) |*control| {
                std.debug.assert(control.activeAdmissions() == 0);
                control.channel.deinit();
            }
            const allocator = self.allocator;
            allocator.free(self.journals);
            allocator.free(self.controls);
            allocator.destroy(self);
        }
    };
}

pub fn ThreadOwner(comptime R: type) type {
    return struct {
        const Self = @This();
        pub const value_owner = true;
        registry: *Registry(R),
        control_index: usize,
        producer_token: ProducerToken,
        generation: u64,
        thread_id: std.Thread.Id,
        thread_cookie: u64,

        fn validate(self: Self) !*Registry(R).Control {
            if (self.control_index >= self.registry.controls.len) return error.InvalidToken;
            const control = &self.registry.controls[self.control_index];
            const state = control.state.load(.acquire);
            if (self.producer_token.journal != control.channel.journal) return error.InvalidToken;
            if (self.generation != self.producer_token.generation or
                self.generation != control.generation.load(.acquire) or
                self.generation != control.channel.control.generation()) return error.StaleToken;
            if (state == .available) return error.Retired;
            const cookie = spsc.currentThreadCookie();
            if (self.thread_id != std.Thread.getCurrentId() or
                self.thread_id != control.thread_id.load(.acquire) or cookie == 0 or
                self.thread_cookie != cookie or self.thread_cookie != control.channel.control.ownerCookie()) return error.WrongThread;
            return control;
        }

        pub fn copyScope(self: Self, destination: []u8) anyerror![]const u8 {
            const control = try self.validate();
            if (!control.acquire(self.registry.io)) return error.Closing;
            defer self.releaseChannel(control);
            const scope = control.scope();
            if (destination.len < scope.len) return error.BufferTooSmall;
            @memcpy(destination[0..scope.len], scope);
            return destination[0..scope.len];
        }

        pub fn enabled(self: Self, level: logger.Level, _: []const u8) bool {
            if (self.inHook()) return false;
            const control = self.validate() catch return false;
            if (control.state.load(.acquire) != .attached or self.admissionClosed(control)) return false;
            const decision = if (@hasDecl(R, "configuration_bound_filter")) cache_module.Decision{ .level = .off, .generation = 0 } else control.cache.decision();
            if (@hasDecl(R, "enabledThreadCached")) return self.registry.owner.enabledThreadCached(level, control.scope(), decision, @intCast(self.control_index + 1));
            if (@hasDecl(R, "enabledCached")) return self.registry.owner.enabledCached(level, control.scope(), decision);
            return self.registry.owner.enabled(level, control.scope());
        }

        pub fn begin(self: Self, level: logger.Level, _: []const u8) logger.BeginResult {
            if (self.inHook()) return .closed;
            const control = self.validate() catch |failure| {
                self.reportError(failure);
                return .closed;
            };
            if (control.state.load(.acquire) != .attached or self.admissionClosed(control)) return .closed;
            // Scope/cache can be read without acquiring channel admission:
            // token/cookie validation identifies the unique synchronous owner
            // thread; only its attach/detach can replace them. Shutdown changes
            // gate/state, never scope/cache, and destroy still requires callers
            // to stop. Thread handles do not support asynchronous migration.
            const decision = if (@hasDecl(R, "configuration_bound_filter")) cache_module.Decision{ .level = .off, .generation = 0 } else control.cache.decision();
            if ((@hasDecl(R, "filterThreadEnabled") or @hasDecl(R, "filterEnabled")) and @hasDecl(R, "filteredThread")) {
                const filter_enabled = if (@hasDecl(R, "filterThreadEnabled"))
                    self.registry.owner.filterThreadEnabled(level, control.scope(), decision, @intCast(self.control_index + 1))
                else
                    self.registry.owner.filterEnabled(level, control.scope(), decision);
                if (!filter_enabled) {
                    // Shutdown may start during the cache/route lookup. A
                    // disabled route is filtered only if admission is open at
                    // this check; worker failures do not enter this pure test.
                    if (self.admissionClosed(control)) return .closed;
                    self.registry.owner.filteredThread(@intCast(self.control_index + 1));
                    return .filtered;
                }
            }
            if (!control.acquire(self.registry.io)) return .closed;
            if (@hasDecl(R, "beginThread") and @hasDecl(R, "enterThreadAdmission") and @hasDecl(R, "endThread")) {
                if (!self.registry.owner.enterThreadAdmission()) {
                    self.releaseChannel(control);
                    return .closed;
                }
                const result = self.registry.owner.beginThread(level, control.scope(), decision, @intCast(self.control_index + 1));
                if (result != .ready) {
                    self.registry.owner.endThread();
                    self.releaseChannel(control);
                }
                return result;
            }
            const result = if (@hasDecl(R, "beginCached"))
                self.registry.owner.beginCached(level, control.scope(), decision)
            else
                self.registry.owner.begin(level, control.scope());
            if (result != .ready) self.releaseChannel(control);
            return result;
        }

        pub fn end(self: Self) void {
            const control = &self.registry.controls[self.control_index];
            std.debug.assert(control.generation.load(.acquire) == self.generation);
            if (@hasDecl(R, "beginThread") and @hasDecl(R, "enterThreadAdmission") and @hasDecl(R, "endThread")) {
                self.registry.owner.endThread();
            } else self.registry.owner.end();
            self.releaseChannel(control);
        }

        pub fn submit(self: Self, admission: logger.Admission, original: logger.Event) anyerror!logger.EmitResult {
            const control = try self.validate();
            var event = original;
            event.channel = @intCast(self.control_index + 1);
            event.scope = control.scope();
            return self.registry.owner.submitToJournal(admission, event, control.channel.journal, self.producer_token);
        }

        pub fn submitWithSchema(self: Self, admission: logger.Admission, original: logger.Event, binding: anytype) anyerror!logger.EmitResult {
            const control = try self.validate();
            if (binding.journal != control.channel.journal or
                binding.owner != @as(*anyopaque, @ptrCast(self.registry.owner))) return error.InvalidSchemaBinding;
            var event = original;
            event.channel = @intCast(self.control_index + 1);
            event.scope = control.scope();
            return self.registry.owner.submitToJournalWithSchema(admission, event, control.channel.journal, self.producer_token, binding);
        }

        pub fn nowNs(self: Self) i64 {
            return self.registry.owner.nowNs();
        }

        pub fn captureFailed(self: Self, failure: anyerror) void {
            self.registry.owner.captureFailed(failure);
        }

        pub fn reportError(self: Self, failure: anyerror) void {
            self.registry.owner.reportError(failure);
        }

        fn inHook(self: Self) bool {
            if (@hasField(R, "diagnostics")) return self.registry.owner.diagnostics.inHook();
            return false;
        }

        fn admissionClosed(self: Self, control: *const Registry(R).Control) bool {
            return self.registry.closing.load(.acquire) or
                control.admission_gate.load(.acquire) & closing_bit != 0 or
                self.registry.owner.state.load(.acquire) != .running;
        }

        fn releaseChannel(self: Self, control: *Registry(R).Control) void {
            control.release(self.registry.io);
            // Closing collectors must be notified after observing the final
            // channel count decrement; endThread's earlier dispatch cannot
            // serve as that wake without racing the worker's empty check.
            if (@hasDecl(R, "threadAdmissionEnded")) self.registry.owner.threadAdmissionEnded();
        }

        pub fn detach(self: Self) anyerror!void {
            // A callback inside an admitted event must fail before taking the
            // lifecycle mutex: beginCut may hold it while waiting for us.
            const current = try self.validate();
            if (current.activeAdmissions() != 0) return error.OutstandingAdmission;
            self.registry.lifecycle_mutex.lockUncancelable(self.registry.io);
            defer self.registry.lifecycle_mutex.unlock(self.registry.io);
            const control = try self.validate();
            if (control.activeAdmissions() != 0) return error.OutstandingAdmission;
            try control.channel.journal.retireSingleProducer(self.producer_token);
            if (@hasDecl(R, "releaseThreadConfigurationCache")) self.registry.owner.releaseThreadConfigurationCache(@intCast(self.control_index + 1));
            control.state.store(.available, .release);
        }
    };
}

const TestRuntime = struct {
    const State = enum(u8) { running, closing, closed };
    filter: *@import("../config/reload.zig").DynamicFilter,
    state: Atomic(State) = .init(.running),
    in_flight: Atomic(usize) = .init(0),
    cached_begins: Atomic(usize) = .init(0),
    thread_admissions: Atomic(usize) = .init(0),
    thread_begins: Atomic(usize) = .init(0),
    schema_submissions: Atomic(usize) = .init(0),
    thread_entries: Atomic(usize) = .init(0),
    clocks: Atomic(usize) = .init(0),
    filtered_counts: [3]Atomic(usize) = .{Atomic(usize).init(0)} ** 3,
    route_override: ?struct { scope: []const u8, level: logger.Level } = null,
    worker_failed: bool = false,
    close_during_filter: bool = false,
    reload_during_filter: ?[]const u8 = null,
    reject_thread_entry: bool = false,
    force_sample: bool = false,
    observer_registry: ?*Registry(TestRuntime) = null,
    post_release_count: usize = std.math.maxInt(usize),
    closing_notifies: Atomic(usize) = .init(0),
    last_error: ?anyerror = null,

    pub fn enabled(self: *TestRuntime, level: logger.Level, scope: []const u8) bool {
        return self.enabledCached(level, scope, self.filter.decision(scope));
    }

    pub fn enabledCached(self: *TestRuntime, level: logger.Level, scope: []const u8, decision: cache_module.Decision) bool {
        return self.state.load(.acquire) == .running and !self.worker_failed and self.routeMask(level, scope, decision) != 0;
    }

    fn routeMask(self: *TestRuntime, level: logger.Level, scope: []const u8, decision: cache_module.Decision) u64 {
        var mask: u64 = if (decision.enabled(level)) 1 else 0;
        if (self.route_override) |route| {
            if (std.mem.eql(u8, route.scope, scope) and route.level.allows(level)) mask |= 2;
        }
        return mask;
    }

    pub fn filterEnabled(self: *TestRuntime, level: logger.Level, scope: []const u8, decision: cache_module.Decision) bool {
        if (self.close_during_filter) {
            self.state.store(.closing, .release);
            if (self.observer_registry) |registry| registry.retireAll();
        }
        if (self.reload_during_filter) |spec| {
            self.reload_during_filter = null;
            self.filter.reload(spec) catch unreachable;
        }
        return self.routeMask(level, scope, decision) != 0;
    }

    pub fn filteredThread(self: *TestRuntime, channel: u32) void {
        _ = self.filtered_counts[channel - 1].fetchAdd(1, .monotonic);
    }

    pub fn begin(self: *TestRuntime, level: logger.Level, scope: []const u8) logger.BeginResult {
        return self.beginCached(level, scope, self.filter.decision(scope));
    }

    pub fn beginCached(self: *TestRuntime, level: logger.Level, scope: []const u8, decision: cache_module.Decision) logger.BeginResult {
        _ = self.cached_begins.fetchAdd(1, .monotonic);
        if (self.state.load(.acquire) != .running) return .closed;
        if (!self.enabledCached(level, scope, decision)) return .filtered;
        _ = self.in_flight.fetchAdd(1, .monotonic);
        return .{ .ready = .{ .route_mask = 1, .config_generation = decision.generation } };
    }

    pub fn end(self: *TestRuntime) void {
        std.debug.assert(self.in_flight.fetchSub(1, .monotonic) != 0);
    }

    pub fn enterThreadAdmission(self: *TestRuntime) bool {
        _ = self.thread_entries.fetchAdd(1, .monotonic);
        if (self.reject_thread_entry) return false;
        _ = self.thread_admissions.fetchAdd(1, .monotonic);
        return true;
    }

    pub fn beginThread(self: *TestRuntime, level: logger.Level, scope: []const u8, decision: cache_module.Decision, _: u32) logger.BeginResult {
        _ = self.thread_begins.fetchAdd(1, .monotonic);
        if (self.state.load(.acquire) != .running) return .closed;
        const mask = self.routeMask(level, scope, decision);
        if (mask == 0) return .filtered;
        if (self.force_sample) return .sampled;
        return .{ .ready = .{ .route_mask = mask, .config_generation = decision.generation } };
    }

    pub fn endThread(self: *TestRuntime) void {
        std.debug.assert(self.thread_admissions.fetchSub(1, .monotonic) != 0);
    }

    pub fn threadAdmissionEnded(self: *TestRuntime) void {
        if (self.state.load(.acquire) == .running) return;
        if (self.observer_registry) |registry| self.post_release_count = registry.activeAdmissions();
        _ = self.closing_notifies.fetchAdd(1, .monotonic);
    }

    pub fn submitToJournal(_: *TestRuntime, admission: logger.Admission, original: logger.Event, journal: *Journal, token: ?ProducerToken) !logger.EmitResult {
        var reservation = if (token) |producer| try journal.reserveSingleProducer(producer) else try journal.reserve();
        errdefer reservation.abort();
        var event = original;
        event.sequence = reservation.sequence;
        event.route_mask = admission.route_mask;
        event.config_generation = admission.config_generation;
        const encoded = try @import("codec.zig").encode(event, reservation.buffer());
        try reservation.commit(encoded.len);
        return .accepted;
    }

    pub fn submitToJournalWithSchema(self: *TestRuntime, admission: logger.Admission, event: logger.Event, journal: *Journal, token: ?ProducerToken, binding: anytype) !logger.EmitResult {
        _ = binding;
        _ = self.schema_submissions.fetchAdd(1, .monotonic);
        return self.submitToJournal(admission, event, journal, token);
    }

    pub fn nowNs(self: *TestRuntime) i64 {
        _ = self.clocks.fetchAdd(1, .monotonic);
        return 123;
    }

    pub fn captureFailed(self: *TestRuntime, failure: anyerror) void {
        self.reportError(failure);
    }

    pub fn reportError(self: *TestRuntime, failure: anyerror) void {
        self.last_error = failure;
    }
};

fn testOptions(tmp: *const std.testing.TmpDir, buffer: []u8, max_channels: usize) !Options {
    return .{
        .max_channels = max_channels,
        .journal_path_prefix = try std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/channels", .{tmp.sub_path}),
        .capacity = 4,
        .max_record_bytes = 1024,
    };
}

test "fixed channels copy scopes cache reloads and reject stale value owners" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "info,http=debug");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 1));
    defer registry.destroy();
    const journal = registry.getJournal(0);
    const journals = registry.activeJournals();
    try std.testing.expectEqual(@as(usize, 1), registry.channelCount());
    try std.testing.expect(registry.controls[0].channel.control.retired());
    var scope = "http.child".*;
    const first = try registry.attach(&scope);
    try std.testing.expect(@TypeOf(first.owner) == ThreadOwner(TestRuntime));
    @memset(&scope, 'x');
    try std.testing.expectEqualStrings("attached", first.scope);
    var scope_copy: [max_scope_bytes]u8 = undefined;
    try std.testing.expectEqualStrings("http.child", try first.copyScope(&scope_copy));
    try std.testing.expectError(error.ChannelsExhausted, registry.attach("extra"));
    try std.testing.expect(first.enabled(.debug));
    try filter.reload("off,http=trace");
    try std.testing.expect(first.enabled(.trace));
    try std.testing.expectEqual(logger.EmitResult.accepted, try first.withBorrowed(.{ .worker = 1 }).tryEmit(.debug, "first", .{}));
    try first.detach();
    const second = try registry.attach("db");
    try std.testing.expect(second.owner.generation > first.owner.generation);
    try std.testing.expectEqual(logger.EmitResult.rejected_closing, try first.tryEmit(.debug, "stale", .{}));
    try std.testing.expectEqual(error.StaleToken, runtime.last_error.?);
    try std.testing.expectError(error.StaleToken, first.detach());
    try std.testing.expectError(error.StaleToken, first.copyScope(&scope_copy));
    try std.testing.expectEqualStrings("attached", first.scope);
    try std.testing.expect(!first.enabled(.fatal));
    try std.testing.expect(!second.enabled(.info));
    try std.testing.expect(registry.getJournal(0) == journal);
    try std.testing.expect(registry.activeJournals().ptr == journals.ptr);
    try second.detach();
    const record = (try journal.peekChecked()).?;
    var scratch: [64]logger.Field = undefined;
    const event = try @import("codec.zig").decode(record.payload, &scratch);
    try std.testing.expectEqualStrings("http.child", event.scope);
    try std.testing.expectEqual(@as(u32, 1), event.channel);
    try std.testing.expectEqual(filter.generation(), event.config_generation);
    try journal.release(record);
    runtime.state.store(.closing, .release);
    try std.testing.expectError(error.Closing, registry.attach("closed"));
    try std.testing.expectError(error.ScopeTooLong, registry.attach("x" ** (max_scope_bytes + 1)));
}

test "wrong threads cannot use or detach handles and retired channels transfer ownership" {
    if (!@import("../platform/mapping.zig").supported or @import("builtin").single_threaded) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 1));
    defer registry.destroy();
    const first = try registry.attach("main");
    var invalid_cookie = first.owner;
    invalid_cookie.thread_cookie +%= 1;
    try std.testing.expectError(error.WrongThread, invalid_cookie.detach());
    const Harness = struct {
        fn misuse(handle: logger.Logger(ThreadOwner(TestRuntime), .trace), flags: *[2]bool) void {
            flags[0] = (handle.tryEmit(.info, "wrong", .{}) catch return) == .rejected_closing;
            handle.detach() catch |failure| {
                flags[1] = failure == error.WrongThread;
            };
        }
        fn attachOnWorker(registry_arg: *Registry(TestRuntime), success: *bool) void {
            const handle = registry_arg.attach("worker") catch return;
            defer handle.detach() catch {};
            success.* = (handle.tryEmit(.info, "worker event", .{}) catch return) == .accepted;
        }
    };
    var flags: [2]bool = .{ false, false };
    const wrong = try std.Thread.spawn(.{}, Harness.misuse, .{ first, &flags });
    wrong.join();
    try std.testing.expect(flags[0] and flags[1]);
    try std.testing.expectEqual(error.WrongThread, runtime.last_error.?);
    try first.detach();
    var success = false;
    const worker = try std.Thread.spawn(.{}, Harness.attachOnWorker, .{ registry, &success });
    worker.join();
    try std.testing.expect(success);
    try std.testing.expect(registry.controls[0].thread_id.load(.acquire) != first.owner.thread_id);
    try std.testing.expectError(error.StaleToken, first.detach());
    const journal = registry.getJournal(0);
    try journal.release((try journal.peekChecked()).?);
}

test "retireAll retains admitted calls and permits late detach without freeing controls" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 1));
    defer registry.destroy();
    const handle = try registry.attach("shutdown");
    const admission = handle.owner.begin(.info, handle.scope).ready;
    registry.retireAll();
    try std.testing.expect(!handle.enabled(.info));
    try std.testing.expectEqual(logger.EmitResult.rejected_closing, try handle.tryEmit(.info, "closed", .{}));
    try std.testing.expectError(error.Closing, registry.attach("new"));
    try std.testing.expectError(error.OutstandingAdmission, handle.detach());
    try std.testing.expectEqual(logger.EmitResult.accepted, try handle.owner.submit(admission, .{
        .level = .info,
        .scope = handle.scope,
        .message = "already admitted",
        .fields = &.{},
        .timestamp_ns = 123,
    }));
    handle.owner.end();
    try handle.detach();
    const journal = registry.getJournal(0);
    try std.testing.expectEqual(@as(usize, 1), journal.pending());
    try journal.release((try journal.peekChecked()).?);
}

test "unattached recovered channels remain visible and warmed attachment emits allocate nothing" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const options = try testOptions(&tmp, &path, 2);
    {
        const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, options);
        defer registry.destroy();
        const handle = try registry.attach("recovered");
        try std.testing.expectEqual(logger.EmitResult.accepted, try handle.tryEmit(.info, "persisted", .{}));
        try handle.detach();
    }
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const reopened = try Registry(TestRuntime).create(allocator.allocator(), std.testing.io, &runtime, options);
    defer reopened.destroy();
    allocator.fail_index = allocator.alloc_index;
    const allocations = allocator.allocations;
    try std.testing.expectEqual(@as(usize, 2), reopened.activeJournals().len);
    try std.testing.expectEqual(@as(usize, 1), reopened.activeJournals()[0].pending());
    try std.testing.expect(reopened.controls[0].channel.control.retired());
    const journal = reopened.getJournal(0);
    const recovered = (try journal.peekChecked()).?;
    var scratch: [64]logger.Field = undefined;
    try std.testing.expectEqualStrings("recovered", (try @import("codec.zig").decode(recovered.payload, &scratch)).scope);
    try journal.release(recovered);
    for (0..32) |_| {
        const handle = try reopened.attach("warm");
        try std.testing.expectEqual(logger.EmitResult.accepted, try handle.tryLogf(.info, "value {d}", .{@as(u16, 42)}, .{ .answer = 42 }));
        try handle.detach();
        try journal.release((try journal.peekChecked()).?);
    }
    try std.testing.expectEqual(allocations, allocator.allocations);
    try std.testing.expect(!allocator.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), runtime.in_flight.load(.monotonic));
}

test "registry creation allocation failures release every initialized channel" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const options = try testOptions(&tmp, &path, 2);
    const Harness = struct {
        fn create(allocator: std.mem.Allocator, runtime_arg: *TestRuntime, options_arg: Options) !void {
            const registry = try Registry(TestRuntime).create(allocator, std.testing.io, runtime_arg, options_arg);
            defer registry.destroy();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Harness.create, .{ &runtime, options });
}

test "channel gate balances all outcomes without acquiring global runtime admission" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "warn");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 1));
    defer registry.destroy();
    runtime.observer_registry = registry;
    const handle = try registry.attach("gate");
    try std.testing.expectEqual(logger.EmitResult.filtered, try handle.tryEmit(.info, "filtered", .{}));
    runtime.force_sample = true;
    try std.testing.expectEqual(logger.EmitResult.sampled, try handle.tryEmit(.err, "sampled", .{}));
    runtime.force_sample = false;
    runtime.reject_thread_entry = true;
    try std.testing.expectEqual(logger.EmitResult.rejected_closing, try handle.tryEmit(.err, "rejected entry", .{}));
    runtime.reject_thread_entry = false;
    try std.testing.expectEqual(@as(usize, 0), registry.activeAdmissions());
    try std.testing.expectEqual(@as(usize, 0), runtime.thread_admissions.load(.acquire));
    try std.testing.expect(handle.owner.begin(.err, handle.scope) == .ready);
    try std.testing.expectEqual(@as(usize, 1), registry.activeAdmissions());
    try std.testing.expectEqual(@as(usize, 0), runtime.in_flight.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), runtime.cached_begins.load(.acquire));
    runtime.state.store(.closing, .release);
    registry.retireAll();
    handle.owner.end();
    registry.waitAdmissions();
    try std.testing.expectEqual(@as(usize, 0), runtime.post_release_count);
    try std.testing.expectEqual(@as(usize, 1), runtime.closing_notifies.load(.acquire));
    try handle.detach();
}

test "channel cut drains admitted events blocks producers and prevents attachment until endCut" {
    if (!@import("../platform/mapping.zig").supported or @import("builtin").single_threaded) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 3));
    defer registry.destroy();
    const Worker = struct {
        registry: *Registry(TestRuntime),
        admitted: Atomic(bool) = .init(false),
        finish_first: Atomic(bool) = .init(false),
        attempted: Atomic(bool) = .init(false),
        completed: Atomic(bool) = .init(false),
        failed: Atomic(bool) = .init(false),

        fn run(self: *@This()) void {
            self.runChecked() catch self.failed.store(true, .release);
        }
        fn runChecked(self: *@This()) !void {
            const handle = try self.registry.attach("worker");
            defer handle.detach() catch {};
            const admission = handle.owner.begin(.info, handle.scope).ready;
            self.admitted.store(true, .release);
            while (!self.finish_first.load(.acquire)) std.atomic.spinLoopHint();
            // beginCut holds lifecycle_mutex here; this error must be returned
            // before attempting to lock that mutex while count is still one.
            try std.testing.expectError(error.OutstandingAdmission, handle.detach());
            // A provider inside the pre-cut event may use an enabled guard or
            // inspect its scope. These finish under the outer admission and
            // must not block that owner thread waiting for its own count.
            try std.testing.expect(handle.enabled(.info));
            var scope_buffer: [max_scope_bytes]u8 = undefined;
            try std.testing.expectEqualStrings("worker", try handle.copyScope(&scope_buffer));
            _ = try handle.owner.submit(admission, .{ .level = .info, .scope = handle.scope, .message = "before cut", .fields = &.{}, .timestamp_ns = 1 });
            handle.owner.end();
            self.attempted.store(true, .release);
            try std.testing.expectEqual(logger.EmitResult.accepted, try handle.tryEmit(.info, "after cut", .{}));
            self.completed.store(true, .release);
        }
    };
    const Cutter = struct {
        registry: *Registry(TestRuntime),
        ready: Atomic(bool) = .init(false),
        finish: Atomic(bool) = .init(false),
        fn run(self: *@This()) void {
            self.registry.beginCut();
            self.ready.store(true, .release);
            while (!self.finish.load(.acquire)) std.atomic.spinLoopHint();
            self.registry.endCut();
        }
    };
    const Attacher = struct {
        registry: *Registry(TestRuntime),
        attempted: Atomic(bool) = .init(false),
        completed: Atomic(bool) = .init(false),
        fn run(self: *@This()) void {
            self.attempted.store(true, .release);
            const handle = self.registry.attach("new attachment") catch return;
            handle.detach() catch return;
            self.completed.store(true, .release);
        }
    };
    var workers = [_]Worker{ .{ .registry = registry }, .{ .registry = registry } };
    var threads: [2]std.Thread = undefined;
    var started: usize = 0;
    defer {
        for (&workers) |*worker| worker.finish_first.store(true, .release);
        for (threads[0..started]) |thread| thread.join();
    }
    for (&workers, &threads) |*worker, *thread| {
        thread.* = try std.Thread.spawn(.{}, Worker.run, .{worker});
        started += 1;
    }
    for (&workers) |*worker| while (!worker.admitted.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expectEqual(@as(usize, 2), registry.activeAdmissions());
    var cutter: Cutter = .{ .registry = registry };
    const cutting = try std.Thread.spawn(.{}, Cutter.run, .{&cutter});
    defer {
        cutter.finish.store(true, .release);
        for (&workers) |*worker| worker.finish_first.store(true, .release);
        cutting.join();
    }
    for (registry.controls) |*control| while (control.admission_gate.load(.acquire) & cut_bit == 0) std.atomic.spinLoopHint();
    try std.testing.expect(!cutter.ready.load(.acquire));
    for (&workers) |*worker| worker.finish_first.store(true, .release);
    while (!cutter.ready.load(.acquire)) std.atomic.spinLoopHint();
    for (&workers) |*worker| {
        while (!worker.attempted.load(.acquire)) std.atomic.spinLoopHint();
        try std.testing.expect(!worker.completed.load(.acquire));
    }
    try std.testing.expectEqual(@as(usize, 0), registry.activeAdmissions());
    var targets: u64 = 0;
    for (registry.activeJournals()) |journal| targets += journal.reservationTarget();
    try std.testing.expectEqual(@as(u64, 2), targets);
    var attacher: Attacher = .{ .registry = registry };
    const attaching = try std.Thread.spawn(.{}, Attacher.run, .{&attacher});
    defer {
        cutter.finish.store(true, .release);
        attaching.join();
    }
    while (!attacher.attempted.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expect(!attacher.completed.load(.acquire));
    cutter.finish.store(true, .release);
    for (threads[0..started]) |thread| thread.join();
    started = 0;
    for (&workers) |*worker| try std.testing.expect(worker.completed.load(.acquire) and !worker.failed.load(.acquire));
    while (!attacher.completed.load(.acquire)) std.atomic.spinLoopHint();
    for (registry.activeJournals()) |journal| while (try journal.peekChecked()) |record| try journal.release(record);
}

test "retireAll wakes a producer blocked by cut and preserves closing through endCut" {
    if (!@import("../platform/mapping.zig").supported or @import("builtin").single_threaded) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 1));
    defer registry.destroy();
    const Worker = struct {
        registry: *Registry(TestRuntime),
        attached: Atomic(bool) = .init(false),
        start: Atomic(bool) = .init(false),
        attempted: Atomic(bool) = .init(false),
        rejected: Atomic(bool) = .init(false),
        detached: Atomic(bool) = .init(false),
        fn run(self: *@This()) void {
            const handle = self.registry.attach("shutdown") catch return;
            self.attached.store(true, .release);
            while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
            self.attempted.store(true, .release);
            const result = handle.tryEmit(.info, "blocked", .{}) catch return;
            self.rejected.store(result == .rejected_closing, .release);
            handle.detach() catch return;
            self.detached.store(true, .release);
        }
    };
    var worker: Worker = .{ .registry = registry };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    defer thread.join();
    defer worker.start.store(true, .release);
    while (!worker.attached.load(.acquire)) std.atomic.spinLoopHint();
    registry.beginCut();
    var cut_active = true;
    defer if (cut_active) registry.endCut();
    worker.start.store(true, .release);
    while (!worker.attempted.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expect(!worker.rejected.load(.acquire));
    registry.retireAll();
    while (!worker.rejected.load(.acquire)) std.atomic.spinLoopHint();
    registry.waitAdmissions();
    try std.testing.expectEqual(closing_bit | cut_bit, registry.controls[0].admission_gate.load(.acquire));
    registry.endCut();
    cut_active = false;
    while (!worker.detached.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expectEqual(closing_bit, registry.controls[0].admission_gate.load(.acquire));
}

test "disabled cached route bypasses cut gate TLS sampling clock and lazy fields" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "off");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter, .force_sample = true };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 1));
    defer registry.destroy();
    const handle = try registry.attach("disabled");
    try std.testing.expect(!handle.enabled(.info));
    registry.beginCut();
    var cut_active = true;
    defer if (cut_active) registry.endCut();
    const epoch = registry.controls[0].admission_epoch.load(.acquire);
    const Provider = struct {
        calls: *usize,
        pub fn fields(self: @This()) struct { costly: bool } {
            self.calls.* += 1;
            return .{ .costly = true };
        }
    };
    var calls: usize = 0;
    // count is zero under cut: acquire would wait for endCut. These return
    // synchronously while cut stays held, proving the gate is bypassed.
    for (0..16) |_| try std.testing.expectEqual(logger.EmitResult.filtered, try handle.tryEmitLazy(.info, "unused", Provider{ .calls = &calls }));
    try std.testing.expectEqual(logger.EmitResult.filtered, try handle.tryLogf(.info, "value {d}", .{@as(u16, 42)}, .{}));
    try std.testing.expect(!handle.enabled(.info));
    try std.testing.expectEqual(@as(usize, 17), runtime.filtered_counts[0].load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), calls);
    try std.testing.expectEqual(@as(usize, 0), runtime.thread_entries.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), runtime.thread_begins.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), runtime.thread_admissions.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), runtime.clocks.load(.acquire));
    try std.testing.expectEqual(cut_bit, registry.controls[0].admission_gate.load(.acquire));
    try std.testing.expectEqual(epoch, registry.controls[0].admission_epoch.load(.acquire));
    registry.endCut();
    cut_active = false;
    try handle.detach();
}

test "early route union preserves independent override and reload decision generations" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "off");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter, .route_override = .{ .scope = "route.scope", .level = .debug } };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 1));
    defer registry.destroy();
    const handle = try registry.attach("route.scope");
    const journal = registry.getJournal(0);
    try std.testing.expect(handle.enabled(.debug));
    try std.testing.expectEqual(logger.EmitResult.accepted, try handle.tryEmit(.debug, "override only", .{}));
    var scratch: [64]logger.Field = undefined;
    var record = (try journal.peekChecked()).?;
    try std.testing.expectEqual(@as(u64, 2), (try @import("codec.zig").decode(record.payload, &scratch)).route_mask);
    try journal.release(record);
    try filter.reload("info");
    try std.testing.expectEqual(logger.EmitResult.accepted, try handle.tryEmit(.info, "both routes", .{}));
    record = (try journal.peekChecked()).?;
    try std.testing.expectEqual(@as(u64, 3), (try @import("codec.zig").decode(record.payload, &scratch)).route_mask);
    try journal.release(record);
    runtime.worker_failed = true;
    try std.testing.expect(!handle.enabled(.info));
    // enabledCached's worker error is separate from the pure route mask.
    // This allowed route reaches admission instead of being counted filtered.
    try std.testing.expect(handle.owner.begin(.info, handle.scope) == .ready);
    handle.owner.end();
    try std.testing.expectEqual(@as(usize, 0), runtime.filtered_counts[0].load(.acquire));
    runtime.worker_failed = false;
    runtime.route_override = null;
    try filter.reload("off");
    runtime.reload_during_filter = "trace";
    try std.testing.expectEqual(logger.EmitResult.filtered, try handle.tryEmit(.debug, "old decision", .{}));
    try std.testing.expectEqual(logger.EmitResult.accepted, try handle.tryEmit(.debug, "new decision", .{}));
    record = (try journal.peekChecked()).?;
    const event = try @import("codec.zig").decode(record.payload, &scratch);
    try std.testing.expectEqual(@as(u64, 1), event.route_mask);
    try std.testing.expectEqual(filter.generation(), event.config_generation);
    try journal.release(record);
    try std.testing.expectEqual(@as(usize, 1), runtime.filtered_counts[0].load(.acquire));
    try handle.detach();
}

test "closing before or during early route check is never counted as filtered" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "off");
    defer filter.destroy();
    const Case = enum { runtime_state, registry_flag, channel_gate, during_filter };
    for (std.enums.values(Case)) |case| {
        var runtime: TestRuntime = .{ .filter = filter };
        var path: [256]u8 = undefined;
        const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 1));
        defer registry.destroy();
        runtime.observer_registry = registry;
        const handle = try registry.attach("closing");
        switch (case) {
            .runtime_state => runtime.state.store(.closing, .release),
            .registry_flag => registry.closing.store(true, .release),
            .channel_gate => _ = registry.controls[0].admission_gate.fetchOr(closing_bit, .acq_rel),
            .during_filter => runtime.close_during_filter = true,
        }
        try std.testing.expectEqual(logger.EmitResult.rejected_closing, try handle.tryEmit(.info, "closed", .{}));
        try std.testing.expect(!handle.enabled(.info));
        try std.testing.expectEqual(@as(usize, 0), runtime.filtered_counts[0].load(.acquire));
        try std.testing.expectEqual(@as(usize, 0), runtime.thread_entries.load(.acquire));
        try std.testing.expectEqual(@as(usize, 0), runtime.thread_begins.load(.acquire));
        try std.testing.expectEqual(@as(usize, 0), runtime.clocks.load(.acquire));
        try std.testing.expectEqual(@as(usize, 0), registry.activeAdmissions());
        try handle.detach();
    }
}

test "registry forwards the fixed schema budget to every preallocated journal" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    var options = try testOptions(&tmp, &path, 2);
    options.schema_capacity = 2;
    options.max_schema_bytes = 512;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, options);
    defer registry.destroy();
    for (registry.activeJournals()) |journal| {
        const schema = journal.schema.?;
        try std.testing.expectEqual(@as(usize, 2), schema.spec.capacity);
        try std.testing.expectEqual(@as(usize, 512), schema.spec.max_definition_bytes);
        try std.testing.expectEqual(schema.spec.size, journal.mapping.bytes.len);
    }
}

test "thread schema binding rejects foreign owner channel and stale attachment before delegation" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var runtime: TestRuntime = .{ .filter = filter };
    var other_runtime: TestRuntime = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const registry = try Registry(TestRuntime).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 2));
    defer registry.destroy();
    const handle = try registry.attach("prepared.scope");
    const Binding = struct { owner: *anyopaque, journal: *Journal };
    const journal = registry.getJournal(handle.owner.control_index);
    const binding: Binding = .{ .owner = @ptrCast(&runtime), .journal = journal };
    var foreign = binding;
    foreign.owner = @ptrCast(&other_runtime);
    var other_channel = binding;
    other_channel.journal = registry.getJournal(1);
    const event: logger.Event = .{ .level = .info, .scope = "caller label", .channel = 99, .message = "prepared", .fields = &.{}, .timestamp_ns = 7 };
    const admission = handle.owner.begin(.info, handle.scope).ready;
    try std.testing.expectError(error.InvalidSchemaBinding, handle.owner.submitWithSchema(admission, event, foreign));
    try std.testing.expectError(error.InvalidSchemaBinding, handle.owner.submitWithSchema(admission, event, other_channel));
    try std.testing.expectEqual(@as(usize, 0), runtime.schema_submissions.load(.acquire));
    try std.testing.expectEqual(logger.EmitResult.accepted, try handle.owner.submitWithSchema(admission, event, binding));
    handle.owner.end();
    try std.testing.expectEqual(@as(usize, 1), runtime.schema_submissions.load(.acquire));
    const record = (try journal.peekChecked()).?;
    var scratch: [64]logger.Field = undefined;
    const captured = try @import("codec.zig").decode(record.payload, &scratch);
    try std.testing.expectEqualStrings("prepared.scope", captured.scope);
    try std.testing.expectEqual(@as(u32, 1), captured.channel);
    try journal.release(record);
    try handle.detach();
    const replacement = try registry.attach("replacement");
    try std.testing.expectError(error.StaleToken, handle.owner.submitWithSchema(admission, event, binding));
    try std.testing.expectEqual(@as(usize, 1), runtime.schema_submissions.load(.acquire));
    try replacement.detach();
}

test "channel configuration hooks take precedence and release after retire before reuse" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    const RuntimeStub = struct {
        const Self = @This();
        const State = enum(u8) { running, closing, closed };
        const Observation = struct {
            enabled: usize = 0,
            filtered_checks: usize = 0,
            filtered: usize = 0,
            releases: usize = 0,
            cache_bound: bool = false,
            retired_before_release: bool = false,
            available_during_release: bool = true,
            admission_during_release: usize = 0,
            scope_matches: bool = false,
        };

        filter: *@import("../config/reload.zig").DynamicFilter,
        state: Atomic(State) = .init(.running),
        registry: ?*Registry(Self) = null,
        observations: [2]Observation = .{Observation{}} ** 2,
        legacy_called: bool = false,

        pub fn enabledThreadCached(self: *Self, level: logger.Level, scope: []const u8, decision: cache_module.Decision, channel: u32) bool {
            const observation = &self.observations[channel - 1];
            observation.enabled += 1;
            observation.cache_bound = true;
            observation.scope_matches = std.mem.eql(u8, scope, "hook.scope");
            return decision.enabled(level);
        }

        pub fn filterThreadEnabled(self: *Self, level: logger.Level, scope: []const u8, decision: cache_module.Decision, channel: u32) bool {
            const observation = &self.observations[channel - 1];
            observation.filtered_checks += 1;
            observation.cache_bound = true;
            observation.scope_matches = std.mem.eql(u8, scope, "hook.scope");
            return decision.enabled(level);
        }

        pub fn enabledCached(self: *Self, _: logger.Level, _: []const u8, _: cache_module.Decision) bool {
            self.legacy_called = true;
            return false;
        }

        pub fn filterEnabled(self: *Self, _: logger.Level, _: []const u8, _: cache_module.Decision) bool {
            self.legacy_called = true;
            return false;
        }

        pub fn filteredThread(self: *Self, channel: u32) void {
            self.observations[channel - 1].filtered += 1;
        }

        pub fn enterThreadAdmission(_: *Self) bool {
            return true;
        }

        pub fn beginThread(_: *Self, _: logger.Level, _: []const u8, decision: cache_module.Decision, _: u32) logger.BeginResult {
            return .{ .ready = .{ .route_mask = 1, .config_generation = decision.generation } };
        }

        pub fn endThread(_: *Self) void {}

        pub fn releaseThreadConfigurationCache(self: *Self, channel: u32) void {
            const observation = &self.observations[channel - 1];
            const control = &self.registry.?.controls[channel - 1];
            observation.releases += 1;
            observation.cache_bound = false;
            observation.retired_before_release = control.channel.control.retired();
            observation.available_during_release = control.state.load(.acquire) == .available;
            observation.admission_during_release = control.activeAdmissions();
        }

        pub fn submitToJournal(_: *Self, _: logger.Admission, _: logger.Event, _: *Journal, _: ?ProducerToken) anyerror!logger.EmitResult {
            return error.UnexpectedSubmission;
        }

        pub fn nowNs(_: *Self) i64 {
            return 123;
        }

        pub fn reportError(_: *Self, _: anyerror) void {}
        pub fn captureFailed(_: *Self, _: anyerror) void {}
    };
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const filter = try @import("../config/reload.zig").DynamicFilter.create(std.testing.allocator, std.testing.io, "info");
    defer filter.destroy();
    var runtime: RuntimeStub = .{ .filter = filter };
    var path: [256]u8 = undefined;
    const registry = try Registry(RuntimeStub).create(std.testing.allocator, std.testing.io, &runtime, try testOptions(&tmp, &path, 2));
    var registry_alive = true;
    defer if (registry_alive) registry.destroy();
    runtime.registry = registry;
    const first = try registry.attach("hook.scope");
    const second = try registry.attach("hook.scope");
    try std.testing.expect(first.enabled(.info));
    try std.testing.expect(second.enabled(.warn));
    try std.testing.expectEqual(logger.EmitResult.filtered, try second.tryEmit(.debug, "filtered", .{}));
    try std.testing.expectEqual(@as(usize, 1), runtime.observations[0].enabled);
    try std.testing.expectEqual(@as(usize, 1), runtime.observations[1].enabled);
    try std.testing.expectEqual(@as(usize, 0), runtime.observations[0].filtered_checks);
    try std.testing.expectEqual(@as(usize, 1), runtime.observations[1].filtered_checks);
    try std.testing.expectEqual(@as(usize, 1), runtime.observations[1].filtered);
    try std.testing.expect(runtime.observations[0].scope_matches and runtime.observations[1].scope_matches);
    try std.testing.expect(!runtime.legacy_called);
    try std.testing.expect(first.owner.begin(.info, first.scope) == .ready);
    var admitted = true;
    defer if (admitted) first.owner.end();
    try std.testing.expectError(error.OutstandingAdmission, first.detach());
    try std.testing.expectEqual(@as(usize, 0), runtime.observations[0].releases);
    first.owner.end();
    admitted = false;
    var reservation = try registry.getJournal(0).reserveSingleProducer(first.owner.producer_token);
    try std.testing.expectError(error.OutstandingReservation, first.detach());
    try std.testing.expectEqual(@as(usize, 0), runtime.observations[0].releases);
    reservation.abort();
    try first.detach();
    try std.testing.expectEqual(@as(usize, 1), runtime.observations[0].releases);
    try std.testing.expect(runtime.observations[0].retired_before_release);
    try std.testing.expect(!runtime.observations[0].available_during_release);
    try std.testing.expectEqual(@as(usize, 0), runtime.observations[0].admission_during_release);
    try std.testing.expect(registry.controls[0].state.load(.acquire) == .available);
    const replacement = try registry.attach("hook.scope");
    try std.testing.expect(replacement.enabled(.info));
    try std.testing.expectError(error.StaleToken, first.detach());
    try std.testing.expect(runtime.observations[0].cache_bound);
    try std.testing.expectEqual(@as(usize, 1), runtime.observations[0].releases);
    try replacement.detach();
    try std.testing.expectEqual(@as(usize, 2), runtime.observations[0].releases);
    try std.testing.expect(!runtime.observations[0].cache_bound);
    try std.testing.expect(try registry.getJournal(0).peekChecked() == null);
    // The parent clears remaining cache pins before registry destruction.
    // Destroy must not call back into Runtime to release them again.
    runtime.observations[1].cache_bound = false;
    runtime.registry = null;
    registry.destroy();
    registry_alive = false;
    try std.testing.expectEqual(@as(usize, 0), runtime.observations[1].releases);
}
