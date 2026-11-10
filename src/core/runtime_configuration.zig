//! Cold configuration operations. Runtime admission and cleanup reentrancy
//! gates remain in the owner; these helpers isolate metadata and final-barrier
//! work from the producer/collector hot path.
const std = @import("std");
const configurations = @import("../config/routes.zig");
const types = @import("runtime_types.zig");
const Filter = @import("../config/filter.zig").Filter;
const max_routes = configurations.max_routes;

pub const Collection = struct {
    versions: [configurations.max_capacity]configurations.Version = undefined,
    count: usize = 0,
};

pub fn replace(owner: anytype, manager: *configurations.Manager, filter: *@import("../config/reload.zig").DynamicFilter, routes: []const types.RouteOptions, policy: types.RoutePolicy) !configurations.Version {
    for (routes) |route| if (route.max_encoded_record_bytes) |limit| if (limit > owner.output.len) return error.EncodedRecordBudgetExceeded;
    owner.configuration_mutex.lockUncancelable(owner.io);
    defer owner.configuration_mutex.unlock(owner.io);
    if (owner.state.load(.acquire) != .running) return error.Closed;
    if (owner.journal) |queue| if (!queue.isPersistent()) {
        for (routes) |*route| if (route.reclaim_after == .durable) return error.DurableReclaimRequiresMmap;
    };
    if (filter.generation() == std.math.maxInt(u64)) return error.FilterGenerationExhausted;
    const current = manager.acquire();
    defer current.release();
    const bound = filter.boundFilter();
    const effective = if (policy.default_filter) |spec| try Filter.parse(spec) else if (bound.configuration_generation == current.snapshot.generation) bound.filter else current.snapshot.default_filter.?;
    const filter_generation = filter.generation() + 1;
    const version = try manager.installWithFilter(routes, policy, effective, filter_generation);
    // During this second publication, readers of the new route snapshot use
    // its complete owning baseline unless the filter's binding matches it.
    filter.publishBound(effective, version.generation);
    for (routes) |*route| if (route.delivery == .required and !route.sink.supports_durable) owner.historical_durable_supported.store(false, .release);
    return version;
}

pub fn ready(manager: *configurations.Manager, version: configurations.Version) bool {
    const view = manager.find(version.generation, version.fingerprint) catch return false;
    defer view.release();
    return view.snapshot.state.load(.acquire) == .retired and view.snapshot.pendingCount() == 0 and view.snapshot.readers.load(.seq_cst) == 1;
}

/// Returns exact version tokens whose final barriers completed. The caller
/// releases every runtime lock before manager.collectVersions invokes leases.
pub fn prepareCollection(owner: anytype, manager: *configurations.Manager, comptime flush: anytype, comptime required_mask: anytype) !Collection {
    var collection: Collection = .{};
    owner.configuration_mutex.lockUncancelable(owner.io);
    defer owner.configuration_mutex.unlock(owner.io);
    // Owner-only caches must not be changed by collection: enabled/filtered
    // reads can occur outside channel admission. Idle owners retain versions
    // until their next refresh or detach.
    var storage: [max_routes]configurations.View = undefined;
    const views = try manager.retainedViews(&storage);
    defer for (views) |view| view.release();
    var delivery_locked = false;
    defer if (delivery_locked) owner.delivery_mutex.unlock(owner.io);
    for (views) |view| {
        const snapshot = view.snapshot;
        if (snapshot.state.load(.acquire) != .retired or snapshot.pendingCount() != 0 or snapshot.readers.load(.seq_cst) != 1) continue;
        if (!delivery_locked) {
            owner.delivery_mutex.lockUncancelable(owner.io);
            delivery_locked = true;
        }
        try flush(owner, snapshot, required_mask(snapshot), types.Flush.written, true);
        var durable_mask: u64 = 0;
        for (snapshot.routes, 0..) |*route, index| if (route.delivery == .required and route.sink.supports_durable) {
            durable_mask |= @as(u64, 1) << @intCast(index);
        };
        if (durable_mask != 0) flush(owner, snapshot, durable_mask, types.Flush.durable, true) catch |err| switch (err) {
            // All record pins are gone and the required written barrier above
            // has completed. This is an extra available-durability barrier;
            // a stale capability must not hold the metadata/lease forever.
            error.UnsupportedDurability => owner.historical_durable_supported.store(false, .release),
            else => return err,
        };
        collection.versions[collection.count] = snapshot.version();
        collection.count += 1;
    }
    return collection;
}
