//! Bounded route and producer-policy versions. The table and its reference
//! counters have stable addresses until the manager is destroyed.
const std = @import("std");
const types = @import("../core/runtime_types.zig");
const Level = @import("../core/level.zig").Level;
const Filter = @import("filter.zig").Filter;
const redact = @import("../pipeline/redact.zig");
const sampling = @import("../pipeline/sampler.zig");
const Predicate = @import("../pipeline/predicate.zig").Predicate;
const Selection = @import("route_selection.zig").Selection;
const Atomic = std.atomic.Value;
const routes_payload = @import("routes_payload.zig");
const Payload = routes_payload.Payload;
const freeRoutes = routes_payload.freeRoutes;
const sameOwner = routes_payload.sameOwner;
const routesEqual = routes_payload.routesEqual;
pub const fingerprint = routes_payload.fingerprint;
pub const TestingAudit = if (@import("builtin").is_test) struct {
    pub threadlocal var find_calls: usize = 0;
    pub var reader_acquisitions: Atomic(u64) = .init(0);
    pub var global_pending_rmw: Atomic(u64) = .init(0);
    pub var channel_refreshes: Atomic(u64) = .init(0);
} else struct {};

pub const Route = types.Route;
pub const RouteOptions = types.RouteOptions;
pub const max_routes = types.max_routes;
pub const max_capacity = types.max_capacity;
pub const max_channels = types.max_channels;
pub const default_capacity = 8;

pub const Policy = types.RoutePolicy;

pub const Options = struct {
    capacity: usize = default_capacity,
    initial_routes: []const RouteOptions,
    redaction: []const redact.Rule = &.{},
    sampling: sampling.Config = .none,
    sample_bypass: Level = .warn,
    default_filter: ?[]const u8 = null,
    predicate: ?[]const u8 = null,
    initial_generation: u64 = 1,
    require_recovery_identity: bool = false,
    /// Per-version route metadata, including fixed filter/predicate storage
    /// even when disabled, plus owned names and identities. Snapshot policies
    /// also have their own fixed filter/redaction/predicate budgets.
    max_config_bytes: usize = 1024 * 1024,
};

pub const Version = struct { generation: u64, fingerprint: u64 };
pub const State = enum(u8) { vacant, active, retired };

pub const Snapshot = struct {
    /// Each producer channel has a separate cache line. The consumer can
    /// release that channel's accepted records without bouncing a counter
    /// shared by every producer. Producer and consumer still share this one
    /// channel's line; this is not a split accepted/released counter scheme.
    pub const ChannelCounter = struct {
        value: Atomic(usize) align(64) = .init(0),
    };

    generation: u64 = 0,
    fingerprint: u64 = 0,
    routes: []Route = &.{},
    selection: Selection = .{},
    redactor: redact.Redactor = .{},
    sampler: sampling.Sampler = .{ .config = .none, .state = .init(0) },
    sample_bypass: Level = .warn,
    sampling_overrides: u64 = 0,
    default_filter: ?Filter = null,
    filter_generation: u64 = 1,
    predicate: ?Predicate = null,
    readers: Atomic(usize) = .init(0),
    /// Global/control and MPSC producer pins and accepted records. Dedicated
    /// channels use perchannel_pending instead. The last record pin must be
    /// released only after its required reclaim boundary is met.
    pending: Atomic(usize) = .init(0),
    perchannel_pending: [max_channels]ChannelCounter = @splat(.{}),
    state: Atomic(State) = .init(.vacant),

    // One atomic packs the incarnation and availability gate. Checking a raw
    // pointer's count is insufficient: a delayed registration can arrive after
    // retirement. Such registrations are safe here because the slot survives
    // and the changed gate makes them retry before reading its payload.
    gate: Atomic(u64) = .init(0),
    epoch: u64 = 0,
    collecting: bool = false, // protected by the manager's writer mutex
    lease_indices: [max_routes]?usize = .{null} ** max_routes,

    /// Retain only while holding a View or another pending pin for this slot.
    pub fn retain(self: *Snapshot) void {
        if (@import("builtin").is_test) _ = TestingAudit.global_pending_rmw.fetchAdd(1, .monotonic);
        _ = self.pending.fetchAdd(1, .seq_cst);
    }

    pub fn release(self: *Snapshot) void {
        if (@import("builtin").is_test) _ = TestingAudit.global_pending_rmw.fetchAdd(1, .monotonic);
        const before = self.pending.fetchSub(1, .seq_cst);
        std.debug.assert(before != 0);
    }

    /// Channel zero is the global/control path. A dedicated producer channel
    /// is 1..64 and must keep its cache pin alive while retaining records.
    /// As with retain, a View or an existing pin must protect this snapshot.
    pub fn retainChannel(self: *Snapshot, channel: u32) void {
        if (channel == 0) return self.retain();
        std.debug.assert(channel <= max_channels);
        _ = self.perchannel_pending[channel - 1].value.fetchAdd(1, .seq_cst);
    }

    pub fn releaseChannel(self: *Snapshot, channel: u32) void {
        self.releaseChannelCount(channel, 1);
    }

    /// Release a run of equal pins with one atomic update. Counts are
    /// interchangeable; observers only require that the total never drops
    /// below the records still owned by the consumer.
    pub fn releaseChannelCount(self: *Snapshot, channel: u32, count: usize) void {
        if (count == 0) return;
        if (channel == 0) {
            if (@import("builtin").is_test) _ = TestingAudit.global_pending_rmw.fetchAdd(@intCast(count), .monotonic);
            const before = self.pending.fetchSub(count, .seq_cst);
            std.debug.assert(before >= count);
            return;
        }
        std.debug.assert(channel <= max_channels);
        const before = self.perchannel_pending[channel - 1].value.fetchSub(count, .seq_cst);
        std.debug.assert(before >= count);
    }

    /// Cold lifecycle checks use the sum of all counters. It is a concurrent
    /// observation, not an atomic metric snapshot; each live channel cache
    /// keeps its own counter nonzero until refresh or quiescent detach.
    pub fn pendingCount(self: *const Snapshot) usize {
        var count = self.pending.load(.seq_cst);
        for (&self.perchannel_pending) |*counter| count += counter.value.load(.seq_cst);
        return count;
    }

    pub fn version(self: *const Snapshot) Version {
        return .{ .generation = self.generation, .fingerprint = self.fingerprint };
    }

    fn setState(self: *Snapshot, state: State) void {
        self.gate.store((self.epoch << 2) | @intFromEnum(state), .seq_cst);
        self.state.store(state, .release);
    }
};

pub const View = struct {
    snapshot: *Snapshot,
    /// Nonzero only for acquire of the current version. It is the exact token
    /// validated with this snapshot, even if a later install has published.
    publication: u64 = 0,

    pub fn release(self: View) void {
        const before = self.snapshot.readers.fetchSub(1, .seq_cst);
        std.debug.assert(before != 0);
    }

    pub fn pin(self: View) Pin {
        return Pin.init(self.snapshot);
    }

    pub fn retain(self: View) View {
        _ = self.snapshot.readers.fetchAdd(1, .seq_cst);
        return self;
    }
};

pub const Pin = struct {
    snapshot: *Snapshot,

    /// The caller must still hold a View or a Pin while creating another pin.
    pub fn init(snapshot: *Snapshot) Pin {
        snapshot.retain();
        return .{ .snapshot = snapshot };
    }

    pub fn retain(self: Pin) Pin {
        return init(self.snapshot);
    }

    pub fn release(self: Pin) void {
        self.snapshot.release();
    }
};

pub fn retain(snapshot: *Snapshot) void {
    snapshot.retain();
}

pub fn release(snapshot: *Snapshot) void {
    snapshot.release();
}

const Lease = struct {
    owner: ?types.SinkRelease = null,
    references: usize = 0,
    /// A last-reference callback runs outside the lock. Its entry stays
    /// reserved until it returns, so installation cannot adopt that owner.
    retiring: bool = false,
};

/// Cold writes are serialized; acquiring either the current or an explicitly
/// identified version requires no allocation and takes no mutex. A reader
/// registers in a stable slot and validates its publication before reading
/// any ordinary payload fields. Publication, gates and counts are seq_cst,
/// so a validated reader must be visible before that payload can be freed.
/// Join all View/Pin users and concurrent manager operations before destroy.
pub const Manager = struct {
    /// Internal runtime cache: one owner thread, one immutable channel, and
    /// one manager for its lifetime. Its snapshot is protected by a channel
    /// pin until refresh/detach. Administrative access requires a producer
    /// cut stopping every cache use, including enabled/filtered calls that
    /// hold no admission. An admission-only gate is insufficient. Copying
    /// this value does not retain it. Idle attached owners can keep a retired
    /// slot occupied until their next refresh or explicit detach.
    pub const ChannelCache = struct {
        snapshot: ?*Snapshot = null,
        publication: u64 = 0,
        channel: u32,
        filter_decision: @import("reload.zig").BoundDecision = .{ .decision = .{ .level = .off, .generation = 0 }, .configuration_generation = 0 },
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    writer_mutex: std.Io.Mutex = .init,
    slots: []Snapshot,
    leases: []Lease,
    published: Atomic(u64) = .init(0), // low six bits: index; remaining: epoch
    // Odd only during the short in-lock publication/gating transition. find
    // retries misses across a transition, including a retirement probe that
    // briefly closed a gate and then discovered an existing reader.
    table_version: Atomic(u64) = .init(0),
    recovery_sealed: Atomic(bool) = .init(false),
    last_generation: u64,
    last_epoch: u64,
    require_recovery_identity: bool,
    max_config_bytes: usize,

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Manager {
        if (options.capacity == 0 or options.capacity > max_capacity or
            options.initial_generation == 0 or options.max_config_bytes == 0)
            return error.InvalidOptions;
        const payload = try Payload.init(allocator, io, options.initial_routes, .{
            .redaction = options.redaction,
            .sampling = options.sampling,
            .sample_bypass = options.sample_bypass,
            .default_filter = options.default_filter,
            .predicate = options.predicate,
        }, options.require_recovery_identity, options.max_config_bytes);
        errdefer payload.deinit(allocator);
        const self = try allocator.create(Manager);
        errdefer allocator.destroy(self);
        const slots = try allocator.alloc(Snapshot, options.capacity);
        errdefer allocator.free(slots);
        const leases = try allocator.alloc(Lease, options.capacity * max_routes);
        errdefer allocator.free(leases);
        for (slots) |*slot| slot.* = .{};
        for (leases) |*lease| lease.* = .{};
        self.* = .{
            .allocator = allocator,
            .io = io,
            .slots = slots,
            .leases = leases,
            .last_generation = options.initial_generation,
            .last_epoch = 1,
            .require_recovery_identity = options.require_recovery_identity,
            .max_config_bytes = options.max_config_bytes,
        };
        try self.adopt(&slots[0], payload, options.initial_generation, 1, .active);
        self.published.store(1 << 6, .seq_cst);
        return self;
    }

    pub fn acquire(self: *Manager) View {
        self.sealRecovery();
        while (true) {
            const token = self.published.load(.seq_cst);
            std.debug.assert(token != 0);
            const slot = &self.slots[@intCast(token & 63)];
            if (@import("builtin").is_test) _ = TestingAudit.reader_acquisitions.fetchAdd(1, .monotonic);
            _ = slot.readers.fetchAdd(1, .seq_cst);
            if (self.published.load(.seq_cst) == token) return .{ .snapshot = slot, .publication = token };
            _ = slot.readers.fetchSub(1, .seq_cst);
            std.atomic.spinLoopHint();
        }
    }

    pub fn currentPublication(self: *const Manager) u64 {
        return self.published.load(.acquire);
    }

    /// A hit reads only publication and owner-local cache data. On refresh a
    /// registered View validates the snapshot/token pair before the new cache
    /// pin is retained. The old cache pin is released only after that handoff.
    /// Publication may change immediately after validation; using that pinned
    /// version for this call is valid and the next call refreshes the cache.
    pub fn acquireChannel(self: *Manager, cache: *ChannelCache) !*Snapshot {
        if (cache.channel == 0 or cache.channel > max_channels) return error.InvalidConfigChannel;
        const publication = self.currentPublication();
        if (cache.publication == publication) {
            if (cache.snapshot) |snapshot| return snapshot;
        }
        if (@import("builtin").is_test) _ = TestingAudit.channel_refreshes.fetchAdd(1, .monotonic);
        const view = self.acquire();
        const snapshot = view.snapshot;
        snapshot.retainChannel(cache.channel);
        const previous = cache.snapshot;
        cache.snapshot = snapshot;
        cache.publication = view.publication;
        view.release();
        if (previous) |old| old.releaseChannel(cache.channel);
        return snapshot;
    }

    /// Called by the owner or after all uses of the cache have stopped,
    /// including enabled/filtered calls outside admission. Accepted records
    /// may keep separate pins after cache detach.
    pub fn releaseChannelCache(_: *Manager, cache: *ChannelCache) void {
        if (cache.snapshot) |snapshot| {
            std.debug.assert(cache.channel != 0 and cache.channel <= max_channels);
            snapshot.releaseChannel(cache.channel);
        }
        cache.snapshot = null;
        cache.publication = 0;
    }

    pub fn currentVersion(self: *Manager) Version {
        const view = self.acquire();
        defer view.release();
        return view.snapshot.version();
    }

    pub fn currentGeneration(self: *Manager) u64 {
        return self.currentVersion().generation;
    }

    /// Ownership transfers only after all validation and allocation succeeds
    /// and the new version is published. Slot exhaustion preserves the old
    /// version; collectRetired can make idle slots available for another try.
    pub fn install(self: *Manager, routes: []const RouteOptions, policy: Policy) !Version {
        return self.installWithFilter(routes, policy, null, 1);
    }

    /// A prevalidated effective default filter can be inherited by a runtime
    /// transaction without serializing/parsing its owned offsets again.
    pub fn installWithFilter(self: *Manager, routes: []const RouteOptions, policy: Policy, effective_filter: ?Filter, filter_generation: u64) !Version {
        var payload = try Payload.init(self.allocator, self.io, routes, policy, self.require_recovery_identity, self.max_config_bytes);
        errdefer payload.deinit(self.allocator);
        if (effective_filter) |filter| payload.default_filter = filter;
        payload.filter_generation = filter_generation;
        self.writer_mutex.lockUncancelable(self.io);
        defer self.writer_mutex.unlock(self.io);
        if (self.last_generation == std.math.maxInt(u64)) return error.ConfigGenerationExhausted;
        if (self.last_epoch == std.math.maxInt(u64) >> 6) return error.ConfigEpochExhausted;
        const index = self.vacantSlot() orelse return error.ConfigSlotsExhausted;
        const generation = self.last_generation + 1;
        const epoch = self.last_epoch + 1;
        const slot = &self.slots[index];
        self.beginMutation();
        defer self.endMutation();
        try self.adopt(slot, payload, generation, epoch, .active);
        self.last_generation = generation;
        self.last_epoch = epoch;
        self.recovery_sealed.store(true, .seq_cst);
        const previous = self.published.swap((epoch << 6) | index, .seq_cst);
        self.slots[@intCast(previous & 63)].setState(.retired);
        return slot.version();
    }

    /// Register every explicit recovery binding before acquire/find/install.
    /// Generation zero is reserved for legacy records without a version.
    pub fn addRecovery(self: *Manager, generation: u64, routes: []const RouteOptions, policy: Policy) !void {
        if (generation == 0) return error.InvalidConfigGeneration;
        const payload = try Payload.init(self.allocator, self.io, routes, policy, self.require_recovery_identity, self.max_config_bytes);
        errdefer payload.deinit(self.allocator);
        self.writer_mutex.lockUncancelable(self.io);
        defer self.writer_mutex.unlock(self.io);
        if (self.recovery_sealed.load(.seq_cst)) return error.RecoveryBindingsSealed;
        for (self.slots) |*slot| {
            if (slot.state.load(.acquire) != .vacant and slot.generation == generation)
                return error.DuplicateConfigGeneration;
        }
        if (self.last_epoch == std.math.maxInt(u64) >> 6) return error.ConfigEpochExhausted;
        const index = self.vacantSlot() orelse return error.ConfigSlotsExhausted;
        const epoch = self.last_epoch + 1;
        self.beginMutation();
        defer self.endMutation();
        try self.adopt(&self.slots[index], payload, generation, epoch, .retired);
        self.last_generation = @max(self.last_generation, generation);
        self.last_epoch = epoch;
    }

    /// A nonzero generation must match both version and fingerprint. Legacy
    /// records can bind by fingerprint only when all matches describe the
    /// same complete target configuration. No current-version fallback is
    /// allowed on an unknown or ambiguous binding.
    pub fn find(self: *Manager, generation: u64, expected_fingerprint: u64) !View {
        if (@import("builtin").is_test) TestingAudit.find_calls += 1;
        self.sealRecovery();
        while (true) {
            const table_version = self.table_version.load(.seq_cst);
            if (table_version & 1 != 0) {
                std.atomic.spinLoopHint();
                continue;
            }
            var selected: ?View = null;
            errdefer if (selected) |view| view.release();
            for (self.slots) |*slot| {
                const view = acquireSlot(slot) orelse continue;
                if (generation != 0) {
                    if (slot.generation != generation) {
                        view.release();
                        continue;
                    }
                    if (slot.fingerprint != expected_fingerprint) {
                        view.release();
                        return error.RecoveryRouteMismatch;
                    }
                    return view;
                }
                if (slot.fingerprint != expected_fingerprint) {
                    view.release();
                    continue;
                }
                if (selected) |previous| {
                    if (!routesEqual(previous.snapshot.routes, slot.routes)) {
                        view.release();
                        return error.AmbiguousRecoveryRoute;
                    }
                    view.release();
                } else selected = view;
            }
            if (self.table_version.load(.seq_cst) != table_version) {
                if (selected) |view| view.release();
                continue;
            }
            return selected orelse error.RecoveryRouteMismatch;
        }
    }

    /// Acquire every currently retained version into caller-owned storage.
    /// The views keep historical targets alive while the runtime serializes
    /// its final required flushes before releasing them and collecting.
    pub fn retainedViews(self: *Manager, destination: []View) ![]View {
        self.sealRecovery();
        while (true) {
            const table_version = self.table_version.load(.seq_cst);
            if (table_version & 1 != 0) {
                std.atomic.spinLoopHint();
                continue;
            }
            var count: usize = 0;
            for (self.slots) |*slot| {
                const view = acquireSlot(slot) orelse continue;
                if (count == destination.len) {
                    view.release();
                    for (destination[0..count]) |held| held.release();
                    return error.TooManyConfigViews;
                }
                destination[count] = view;
                count += 1;
            }
            if (self.table_version.load(.seq_cst) != table_version) {
                for (destination[0..count]) |view| view.release();
                continue;
            }
            return destination[0..count];
        }
    }

    /// Pending zero means the runtime has already completed every accepted
    /// record's required flush/durable boundary. Collection performs no sink
    /// IO, which could otherwise race a current version sharing that sink.
    /// Last-owner callbacks run outside writer_mutex; a collecting slot is
    /// unavailable to both readers and installers until those callbacks end.
    pub fn collectRetired(self: *Manager) !usize {
        return self.collect(null);
    }

    /// Collect only versions whose final barrier the runtime has completed.
    /// Matching the complete token under writer_mutex prevents a concurrent
    /// install from adding a newly retired version to an earlier barrier cut.
    pub fn collectVersions(self: *Manager, expected: []const Version) !usize {
        return self.collect(expected);
    }

    fn collect(self: *Manager, expected: ?[]const Version) !usize {
        self.sealRecovery();
        var collected: usize = 0;
        for (self.slots) |*slot| {
            self.writer_mutex.lockUncancelable(self.io);
            if (slot.state.load(.acquire) != .retired or slot.collecting) {
                self.writer_mutex.unlock(self.io);
                continue;
            }
            if (expected) |versions| {
                var selected = false;
                for (versions) |version| {
                    if (version.generation == slot.generation and version.fingerprint == slot.fingerprint) {
                        selected = true;
                        break;
                    }
                }
                if (!selected) {
                    self.writer_mutex.unlock(self.io);
                    continue;
                }
            }
            if (slot.readers.load(.seq_cst) != 0 or slot.pendingCount() != 0) {
                self.writer_mutex.unlock(self.io);
                continue;
            }
            self.beginMutation();
            slot.setState(.vacant);
            if (slot.readers.load(.seq_cst) != 0 or slot.pendingCount() != 0) {
                slot.setState(.retired);
                self.endMutation();
                self.writer_mutex.unlock(self.io);
                continue;
            }
            slot.collecting = true;
            var released: [max_routes]usize = undefined;
            const count = self.detachLeases(slot, &released);
            self.endMutation();
            self.writer_mutex.unlock(self.io);

            // Entries are reserved as retiring, and immutable until released.
            for (released[0..count]) |index| {
                const owner = self.leases[index].owner.?;
                owner.release(owner.context);
            }
            freeRoutes(self.allocator, slot.routes);
            slot.routes = &.{};

            self.writer_mutex.lockUncancelable(self.io);
            for (released[0..count]) |index| self.leases[index] = .{};
            slot.collecting = false;
            self.writer_mutex.unlock(self.io);
            collected += 1;
        }
        return collected;
    }

    /// Initial runtime construction can fail after manager creation. In that
    /// case ownership remains with the caller: release metadata without ever
    /// invoking sink callbacks. This has the same quiescence rule as destroy.
    pub fn abandon(self: *Manager) void {
        self.dispose(false);
    }

    /// Owner-only shutdown operation. All frontends, workers, controls and
    /// other pin users must already be stopped. This drops process-local pins
    /// after delivery failure; it does not acknowledge or reclaim any journal
    /// data, which remains available for explicit recovery on the next start.
    /// Detach channel caches first; this clears their counters as well.
    pub fn discardPinsAfterStop(self: *Manager) void {
        for (self.slots) |*slot| {
            std.debug.assert(slot.readers.load(.seq_cst) == 0);
            slot.pending.store(0, .seq_cst);
            for (&slot.perchannel_pending) |*counter| counter.value.store(0, .seq_cst);
        }
    }

    pub fn destroy(self: *Manager) void {
        self.dispose(true);
    }

    fn dispose(self: *Manager, release_owners: bool) void {
        for (self.slots) |*slot| {
            std.debug.assert(!slot.collecting);
            std.debug.assert(slot.readers.load(.seq_cst) == 0);
            std.debug.assert(slot.pendingCount() == 0);
        }
        if (release_owners) for (self.leases) |lease| {
            if (lease.owner) |owner| owner.release(owner.context);
        };
        for (self.slots) |slot| freeRoutes(self.allocator, slot.routes);
        const allocator = self.allocator;
        allocator.free(self.leases);
        allocator.free(self.slots);
        allocator.destroy(self);
    }

    fn vacantSlot(self: *Manager) ?usize {
        for (self.slots, 0..) |*slot, index| {
            if (slot.state.load(.acquire) == .vacant and !slot.collecting and
                slot.readers.load(.seq_cst) == 0 and slot.pendingCount() == 0)
                return index;
        }
        return null;
    }

    fn beginMutation(self: *Manager) void {
        const before = self.table_version.fetchAdd(1, .seq_cst);
        std.debug.assert(before & 1 == 0);
    }

    fn sealRecovery(self: *Manager) void {
        // After initialization readers only load this shared cache line.
        if (!self.recovery_sealed.load(.acquire)) self.recovery_sealed.store(true, .seq_cst);
    }

    fn endMutation(self: *Manager) void {
        const before = self.table_version.fetchAdd(1, .seq_cst);
        std.debug.assert(before & 1 == 1);
    }

    // Called only on a vacant slot under the writer lock, or during create.
    // Plan every lease before mutating the registry, so failure never adopts
    // even a subset of the caller's owned sinks.
    fn adopt(self: *Manager, slot: *Snapshot, payload: Payload, generation: u64, epoch: u64, state: State) !void {
        var indices: [max_routes]?usize = .{null} ** max_routes;
        for (payload.routes, 0..) |route, route_index| {
            const owner = route.release orelse continue;
            var found: ?usize = null;
            for (self.leases, 0..) |lease, index| {
                if (lease.owner) |existing| if (sameOwner(owner, existing)) {
                    if (lease.retiring) return error.ConfigOwnerRetiring;
                    found = index;
                    break;
                };
            }
            if (found == null) {
                for (payload.routes[0..route_index], 0..) |previous, previous_index| {
                    if (previous.release) |existing| if (sameOwner(owner, existing)) {
                        found = indices[previous_index];
                        break;
                    };
                }
            }
            if (found == null) {
                for (self.leases, 0..) |lease, index| {
                    if (lease.owner != null) continue;
                    var reserved = false;
                    for (indices[0..route_index]) |planned| if (planned == index) {
                        reserved = true;
                        break;
                    };
                    if (!reserved) {
                        found = index;
                        break;
                    }
                }
            }
            indices[route_index] = found orelse return error.ConfigLeaseSlotsExhausted;
        }
        for (payload.routes, indices[0..payload.routes.len]) |route, maybe_index| {
            const index = maybe_index orelse continue;
            const lease = &self.leases[index];
            lease.owner = route.release;
            lease.references += 1;
        }
        slot.generation = generation;
        slot.fingerprint = payload.fingerprint;
        slot.routes = payload.routes;
        slot.selection = Selection.init(payload.routes);
        slot.redactor = payload.redactor;
        slot.sampler = payload.sampler;
        slot.sample_bypass = payload.sample_bypass;
        slot.sampling_overrides = payload.sampling_overrides;
        slot.default_filter = payload.default_filter;
        slot.filter_generation = payload.filter_generation;
        slot.predicate = payload.predicate;
        slot.lease_indices = indices;
        slot.epoch = epoch;
        slot.setState(state);
    }

    fn detachLeases(self: *Manager, slot: *Snapshot, released: *[max_routes]usize) usize {
        var count: usize = 0;
        for (slot.lease_indices[0..slot.routes.len]) |maybe_index| {
            const index = maybe_index orelse continue;
            const lease = &self.leases[index];
            std.debug.assert(lease.references != 0 and !lease.retiring);
            lease.references -= 1;
            if (lease.references == 0) {
                lease.retiring = true;
                released[count] = index;
                count += 1;
            }
        }
        return count;
    }
};

fn acquireSlot(slot: *Snapshot) ?View {
    if (@import("builtin").is_test) _ = TestingAudit.reader_acquisitions.fetchAdd(1, .monotonic);
    const gate = slot.gate.load(.seq_cst);
    if (gate & 3 == @intFromEnum(State.vacant)) return null;
    _ = slot.readers.fetchAdd(1, .seq_cst);
    if (slot.gate.load(.seq_cst) == gate) return .{ .snapshot = slot };
    _ = slot.readers.fetchSub(1, .seq_cst);
    return null;
}

test {
    _ = @import("routes_tests.zig");
}
