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
    verify_crc: bool = true,
    text_format: bool = false,
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
                    .verify_crc = options.verify_crc,
                    .text_format = options.text_format,
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

test {
    _ = @import("tests/thread_registry.zig");
}
