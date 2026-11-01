const std = @import("std");
const routes = @import("routes.zig");
const types = @import("../core/runtime_types.zig");
const Level = @import("../core/level.zig").Level;
const Sink = @import("../sink/interface.zig").Sink;
const fields = @import("../core/field.zig");

const Target = struct {
    released: std.atomic.Value(usize) = .init(0),
    manager: ?*routes.Manager = null,
    reentered: bool = false,
    retiring_rejected: bool = false,
    replacement: ?*Target = null,
    installed: ?routes.Version = null,

    fn sink(self: *Target) Sink {
        return .{ .context = self, .vtable = &vtable, .recovery_identity = "stable-target" };
    }

    fn owner(self: *Target) types.SinkRelease {
        return .{ .context = self, .release = release };
    }

    fn release(context: *anyopaque) void {
        const self: *Target = @ptrCast(@alignCast(context));
        if (self.manager) |manager| {
            // Taking the mutex here proves last-owner callbacks are outside it.
            manager.writer_mutex.lockUncancelable(manager.io);
            manager.writer_mutex.unlock(manager.io);
            if (self.replacement) |replacement| {
                self.installed = manager.install(&.{.{ .name = "replacement", .sink = replacement.sink() }}, .{}) catch unreachable;
                self.reentered = true;
            } else {
                _ = manager.install(&.{.{ .name = "retiring", .sink = self.sink(), .release = self.owner() }}, .{}) catch |err| {
                    self.retiring_rejected = err == error.ConfigOwnerRetiring;
                    _ = manager.collectRetired() catch unreachable;
                    self.reentered = true;
                    _ = self.released.fetchAdd(1, .monotonic);
                    return;
                };
                _ = manager.collectRetired() catch unreachable;
                self.reentered = true;
            }
        }
        _ = self.released.fetchAdd(1, .monotonic);
    }

    fn write(_: *anyopaque, _: []const u8) anyerror!void {}
    fn flush(_: *anyopaque) anyerror!void {}
    fn sync(_: *anyopaque) anyerror!void {}
    const vtable: Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = sync };
};

test "route snapshots retain old pins while current routes change and reclaim slots" {
    var old_target: Target = .{};
    var new_target: Target = .{};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .capacity = 2,
        .initial_routes = &.{.{ .name = "old", .sink = old_target.sink(), .release = old_target.owner() }},
    });
    defer manager.destroy();
    const old = manager.acquire();
    const old_version = old.snapshot.version();
    const producer = old.pin();
    const accepted = producer.retain();
    old.release();
    const new_version = try manager.install(&.{.{ .name = "new", .sink = new_target.sink() }}, .{});
    try std.testing.expectEqual(@as(u64, 2), new_version.generation);
    const current = manager.acquire();
    try std.testing.expectEqualStrings("new", current.snapshot.routes[0].name);
    current.release();
    try std.testing.expectEqual(@as(usize, 0), try manager.collectRetired());
    try std.testing.expectError(error.ConfigSlotsExhausted, manager.install(&.{.{ .name = "third", .sink = new_target.sink() }}, .{}));
    const recovered = try manager.find(old_version.generation, old_version.fingerprint);
    try std.testing.expectEqualStrings("old", recovered.snapshot.routes[0].name);
    recovered.release();
    producer.release();
    try std.testing.expectEqual(@as(usize, 0), try manager.collectRetired());
    try std.testing.expectEqual(@as(usize, 0), old_target.released.load(.monotonic));
    accepted.release();
    try std.testing.expectEqual(@as(usize, 1), try manager.collectRetired());
    try std.testing.expectEqual(@as(usize, 1), old_target.released.load(.monotonic));
    try std.testing.expectError(error.RecoveryRouteMismatch, manager.find(old_version.generation, old_version.fingerprint));
    const third = try manager.install(&.{.{ .name = "third", .sink = new_target.sink() }}, .{});
    try std.testing.expectEqual(@as(u64, 3), third.generation);
}

test "route snapshots held views protect metadata and shared leases release once" {
    var shared: Target = .{};
    var other: Target = .{};
    const options = [_]routes.RouteOptions{.{ .name = "same", .sink = shared.sink(), .release = shared.owner() }};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .capacity = 3,
        .initial_routes = &options,
    });
    const held = manager.acquire();
    const retained = held.retain();
    held.release();
    const second = try manager.install(&options, .{ .sampling = .{ .every = 3 } });
    try std.testing.expectEqual(retained.snapshot.fingerprint, second.fingerprint);
    try std.testing.expectEqual(@as(usize, 0), try manager.collectRetired());
    retained.release();
    try std.testing.expectEqual(@as(usize, 1), try manager.collectRetired());
    try std.testing.expectEqual(@as(usize, 0), shared.released.load(.monotonic));
    _ = try manager.install(&.{.{ .name = "other", .sink = other.sink() }}, .{});
    shared.manager = manager;
    try std.testing.expectEqual(@as(usize, 1), try manager.collectRetired());
    try std.testing.expect(shared.reentered);
    try std.testing.expect(shared.retiring_rejected);
    try std.testing.expectEqual(@as(usize, 1), shared.released.load(.monotonic));
    shared.manager = null;
    manager.destroy();
    try std.testing.expectEqual(@as(usize, 1), shared.released.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), other.released.load(.monotonic));
}

test "route snapshots reject invalid transactions without ownership transfer" {
    var initial: Target = .{};
    var replacement: Target = .{};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &.{.{ .name = "initial", .sink = initial.sink() }},
        .require_recovery_identity = true,
    });
    defer manager.destroy();
    const before = manager.currentVersion();
    const valid = [_]routes.RouteOptions{.{ .name = "next", .sink = replacement.sink(), .release = replacement.owner() }};
    try std.testing.expectError(error.InvalidSampleRate, manager.install(&valid, .{ .sampling = .{ .every = 0 } }));
    try std.testing.expectError(error.EmptyKey, manager.install(&valid, .{ .redaction = &.{.{ .key = "", .action = .drop }} }));
    try std.testing.expectError(error.InvalidLevel, manager.install(&valid, .{ .default_filter = "verbose" }));
    try std.testing.expectError(error.InvalidSyntax, manager.install(&valid, .{ .predicate = "exists(" }));
    try std.testing.expectError(error.InvalidSyntax, manager.install(&.{.{ .name = "next", .sink = replacement.sink(), .predicate = "exists(" }}, .{}));
    try std.testing.expectError(error.InvalidRouteName, manager.install(&.{.{ .name = "", .sink = replacement.sink(), .release = replacement.owner() }}, .{}));
    try std.testing.expectError(error.DuplicateRoute, manager.install(&.{ valid[0], valid[0] }, .{}));
    try std.testing.expectError(error.UnsupportedDurability, manager.install(&.{.{ .name = "next", .sink = replacement.sink(), .reclaim_after = .durable }}, .{}));
    var unidentified = replacement.sink();
    unidentified.recovery_identity = null;
    try std.testing.expectError(error.RecoveryIdentityRequired, manager.install(&.{.{ .name = "next", .sink = unidentified }}, .{}));
    try std.testing.expectEqualDeep(before, manager.currentVersion());
    try std.testing.expectEqual(@as(usize, 0), replacement.released.load(.monotonic));
}

test "route snapshots own filters names identities and redaction keys" {
    var target: Target = .{};
    var name = "audit".*;
    var identity = "audit-target".*;
    var filter = "warn,http=trace".*;
    var default_filter = "err,http=debug".*;
    var key = "password".*;
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &.{.{ .name = &name, .sink = target.sink(), .filter = &filter, .recovery_identity = &identity }},
        .redaction = &.{.{ .key = &key, .action = .mask }},
        .default_filter = &default_filter,
        .sampling = .{ .every = 2 },
        .sample_bypass = .err,
    });
    defer manager.destroy();
    @memset(&name, 'x');
    @memset(&identity, 'x');
    @memset(&filter, 'x');
    @memset(&default_filter, 'x');
    @memset(&key, 'x');
    const view = manager.acquire();
    defer view.release();
    const snapshot = view.snapshot;
    try std.testing.expectEqualStrings("audit", snapshot.routes[0].name);
    try std.testing.expectEqualStrings("audit-target", snapshot.routes[0].recovery_identity.?);
    try std.testing.expectEqualStrings("audit-target", snapshot.routes[0].sink.recovery_identity.?);
    try std.testing.expectEqual(Level.trace, snapshot.routes[0].filter.?.threshold("http.child"));
    try std.testing.expectEqual(Level.debug, snapshot.default_filter.?.threshold("http.child"));
    try std.testing.expectEqual(Level.err, snapshot.sample_bypass);
    try std.testing.expectEqualStrings(fields.redacted, snapshot.redactor.apply(fields.kv("password", "secret")).?.value.string);
    try std.testing.expect(snapshot.sampler.allow(0));
    try std.testing.expect(!snapshot.sampler.allow(0));
}

test "route snapshots recovery generations require exact binding and legacy ambiguity fails" {
    var current_target: Target = .{};
    var old_target: Target = .{};
    const current = [_]routes.RouteOptions{.{ .name = "audit", .sink = current_target.sink() }};
    const old = [_]routes.RouteOptions{.{ .name = "audit", .sink = old_target.sink() }};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &current,
        .initial_generation = 10,
        .capacity = 4,
    });
    defer manager.destroy();
    try manager.addRecovery(3, &old, .{});
    try manager.addRecovery(20, &current, .{ .sampling = .{ .count = 2 } });
    try std.testing.expectError(error.DuplicateConfigGeneration, manager.addRecovery(3, &old, .{}));
    try std.testing.expectError(error.InvalidConfigGeneration, manager.addRecovery(0, &old, .{}));
    const version = manager.currentVersion();
    try std.testing.expectEqual(@as(u64, 10), version.generation);
    const recovered = try manager.find(3, version.fingerprint);
    try std.testing.expectEqual(old_target.sink().context, recovered.snapshot.routes[0].sink.context);
    recovered.release();
    try std.testing.expectError(error.RecoveryRouteMismatch, manager.find(999, version.fingerprint));
    try std.testing.expectError(error.RecoveryRouteMismatch, manager.find(3, version.fingerprint ^ 1));
    try std.testing.expectError(error.AmbiguousRecoveryRoute, manager.find(0, version.fingerprint));
    try std.testing.expectError(error.RecoveryBindingsSealed, manager.addRecovery(4, &old, .{}));
    const next = try manager.install(&current, .{});
    try std.testing.expectEqual(@as(u64, 21), next.generation);
}

test "route snapshots legacy fingerprint compares full metadata and stable identical targets" {
    var target: Target = .{};
    const options = [_]routes.RouteOptions{.{ .name = "audit", .sink = target.sink(), .min_level = .info }};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{ .initial_routes = &options, .capacity = 4 });
    defer manager.destroy();
    try manager.addRecovery(5, &options, .{});
    const before = manager.currentVersion();
    const legacy = try manager.find(0, before.fingerprint);
    legacy.release();
    var changed = options;
    changed[0].min_level = .warn;
    const next = try manager.install(&changed, .{});
    try std.testing.expectEqual(before.fingerprint, next.fingerprint);
    try std.testing.expectError(error.AmbiguousRecoveryRoute, manager.find(0, before.fingerprint));
    const exact = try manager.find(next.generation, next.fingerprint);
    try std.testing.expectEqual(Level.warn, exact.snapshot.routes[0].min_level.?);
    exact.release();
}

test "route snapshots lookup pin and misses allocate nothing" {
    var target: Target = .{};
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const manager = try routes.Manager.create(allocator.allocator(), std.testing.io, .{
        .initial_routes = &.{.{ .name = "audit", .sink = target.sink() }},
    });
    defer manager.destroy();
    const allocations = allocator.allocations;
    allocator.fail_index = allocations;
    const version = manager.currentVersion();
    var views: [routes.max_capacity]routes.View = undefined;
    for (0..1000) |_| {
        const view = manager.acquire();
        const pin = view.pin();
        const accepted = pin.retain();
        view.release();
        const exact = try manager.find(version.generation, version.fingerprint);
        exact.release();
        const legacy = try manager.find(0, version.fingerprint);
        legacy.release();
        for (try manager.retainedViews(&views)) |held| held.release();
        try std.testing.expectError(error.RecoveryRouteMismatch, manager.find(version.generation + 1, version.fingerprint));
        accepted.release();
        pin.release();
    }
    try std.testing.expectEqual(allocations, allocator.allocations);
    try std.testing.expect(!allocator.has_induced_failure);
}

test "route snapshots retained views cover history and capacity errors release every reader" {
    var target: Target = .{};
    const options = [_]routes.RouteOptions{.{ .name = "audit", .sink = target.sink() }};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{ .initial_routes = &options, .capacity = 3 });
    defer manager.destroy();
    const second = try manager.install(&options, .{});
    var small: [1]routes.View = undefined;
    try std.testing.expectError(error.TooManyConfigViews, manager.retainedViews(&small));
    for (manager.slots) |*slot| try std.testing.expectEqual(@as(usize, 0), slot.readers.load(.seq_cst));
    var destination: [3]routes.View = undefined;
    const held = try manager.retainedViews(&destination);
    try std.testing.expectEqual(@as(usize, 2), held.len);
    try std.testing.expectEqual(@as(u64, 1), held[0].snapshot.generation);
    try std.testing.expectEqual(second.generation, held[1].snapshot.generation);
    try std.testing.expectEqual(@as(usize, 0), try manager.collectRetired());
    for (held) |view| view.release();
    try std.testing.expectEqual(@as(usize, 1), try manager.collectRetired());
}

test "route snapshots collection tokens skip versions retired during callback installation" {
    var initial: Target = .{};
    var intermediate: Target = .{};
    var replacement: Target = .{};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .capacity = 3,
        .initial_routes = &.{.{ .name = "initial", .sink = initial.sink(), .release = initial.owner() }},
    });
    defer manager.destroy();
    const first = manager.currentVersion();
    const second = try manager.install(&.{.{ .name = "intermediate", .sink = intermediate.sink(), .release = intermediate.owner() }}, .{});
    initial.manager = manager;
    initial.replacement = &replacement;
    try std.testing.expectEqual(@as(usize, 0), try manager.collectVersions(&.{.{ .generation = first.generation, .fingerprint = first.fingerprint ^ 1 }}));
    try std.testing.expectEqual(@as(usize, 1), try manager.collectVersions(&.{first}));
    try std.testing.expect(initial.reentered);
    try std.testing.expectEqual(@as(u64, 3), initial.installed.?.generation);
    try std.testing.expectEqual(@as(usize, 1), initial.released.load(.monotonic));
    // The callback retired generation 2 after the selected barrier cut.
    try std.testing.expectEqual(@as(usize, 0), intermediate.released.load(.monotonic));
    const retained = try manager.find(second.generation, second.fingerprint);
    retained.release();
    try std.testing.expectEqual(@as(usize, 0), try manager.collectVersions(&.{first}));
    try std.testing.expectEqual(@as(usize, 1), try manager.collectVersions(&.{second}));
    try std.testing.expectEqual(@as(usize, 1), intermediate.released.load(.monotonic));
    const fourth = try manager.install(&.{.{ .name = "fourth", .sink = replacement.sink() }}, .{});
    try std.testing.expectEqual(@as(u64, 4), fourth.generation);
    // A recycled slot still cannot match an earlier generation's token.
    try std.testing.expectEqual(@as(usize, 0), try manager.collectVersions(&.{first}));
}

test "route snapshots owner shutdown discards local record pins before abandon" {
    var target: Target = .{};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &.{.{ .name = "audit", .sink = target.sink(), .release = target.owner() }},
    });
    const view = manager.acquire();
    view.snapshot.retain(); // failed delivery still has a process-local pin
    view.snapshot.retainChannel(1);
    view.snapshot.retainChannel(64);
    view.release();
    manager.discardPinsAfterStop();
    for (manager.slots) |*slot| try std.testing.expectEqual(@as(usize, 0), slot.pendingCount());
    manager.abandon();
    try std.testing.expectEqual(@as(usize, 0), target.released.load(.monotonic));
}

test "route snapshots channel counters have separate cache lines and preserve global pins" {
    try std.testing.expectEqual(@as(usize, 64), @alignOf(routes.Snapshot.ChannelCounter));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(routes.Snapshot.ChannelCounter));
    var snapshot: routes.Snapshot = .{};
    snapshot.retainChannel(0);
    snapshot.retainChannel(1);
    snapshot.retainChannel(64);
    try std.testing.expectEqual(@as(usize, 3), snapshot.pendingCount());
    try std.testing.expectEqual(@as(usize, 1), snapshot.pending.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 1), snapshot.perchannel_pending[0].value.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 1), snapshot.perchannel_pending[63].value.load(.seq_cst));
    for (&snapshot.perchannel_pending) |*counter| {
        try std.testing.expectEqual(@as(usize, 0), @intFromPtr(&counter.value) % 64);
    }
    snapshot.releaseChannel(1);
    snapshot.releaseChannel(64);
    snapshot.releaseChannel(0);
    try std.testing.expectEqual(@as(usize, 0), snapshot.pendingCount());
}

test "route snapshots channel caches keep global and per-route predicates from the same version" {
    var target: Target = .{};
    var global_spec = "tenant == \"prod\"".*;
    var route_spec = "status >= 500".*;
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &.{.{ .name = "audit", .sink = target.sink(), .predicate = &route_spec }},
        .predicate = &global_spec,
        .capacity = 2,
    });
    defer manager.destroy();
    @memset(&global_spec, 'x');
    @memset(&route_spec, 'x');
    var cache: routes.Manager.ChannelCache = .{ .channel = 1 };
    defer manager.releaseChannelCache(&cache);
    const old = try manager.acquireChannel(&cache);
    const old_version = old.version();
    old.retainChannel(1);
    defer old.releaseChannel(1);
    const before = [_]fields.Field{ fields.kv("tenant", "prod"), fields.kv("status", 503) };
    const old_event: @import("../core/event.zig").Event = .{ .level = .info, .scope = "app", .message = "request", .fields = &before, .timestamp_ns = 0 };
    try std.testing.expect(try old.predicate.?.matches(old_event));
    try std.testing.expect(try old.routes[0].predicate.?.matches(old_event));
    const next = try manager.install(&.{.{ .name = "audit", .sink = target.sink(), .predicate = "status < 500" }}, .{ .predicate = "tenant == \"dev\"" });
    try std.testing.expectEqual(old_version.fingerprint, next.fingerprint);
    const current = try manager.acquireChannel(&cache);
    try std.testing.expectEqual(next.generation, current.generation);
    try std.testing.expect(!try current.predicate.?.matches(old_event));
    try std.testing.expect(!try current.routes[0].predicate.?.matches(old_event));
    try std.testing.expect(try old.predicate.?.matches(old_event));
    try std.testing.expect(try old.routes[0].predicate.?.matches(old_event));
}

test "route snapshots channel cache hits preserve pin counts and allocate nothing" {
    var target: Target = .{};
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const manager = try routes.Manager.create(allocator.allocator(), std.testing.io, .{
        .initial_routes = &.{.{ .name = "audit", .sink = target.sink() }},
    });
    defer manager.destroy();
    const allocations = allocator.allocations;
    allocator.fail_index = allocations;
    var cache: routes.Manager.ChannelCache = .{ .channel = 64 };
    defer manager.releaseChannelCache(&cache);
    const snapshot = try manager.acquireChannel(&cache);
    try std.testing.expectEqual(manager.currentPublication(), cache.publication);
    try std.testing.expectEqual(@as(usize, 1), snapshot.perchannel_pending[63].value.load(.seq_cst));
    for (0..10000) |_| {
        const hit = try manager.acquireChannel(&cache);
        try std.testing.expectEqual(snapshot, hit);
        try std.testing.expectEqual(@as(usize, 1), snapshot.pendingCount());
        hit.retainChannel(64);
        try std.testing.expectEqual(@as(usize, 2), hit.pendingCount());
        hit.releaseChannel(64);
    }
    try std.testing.expectEqual(@as(usize, 0), snapshot.readers.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 0), snapshot.pending.load(.seq_cst));
    try std.testing.expectEqual(allocations, allocator.allocations);
    try std.testing.expect(!allocator.has_induced_failure);
    manager.releaseChannelCache(&cache);
    try std.testing.expect(cache.snapshot == null);
    try std.testing.expectEqual(@as(u64, 0), cache.publication);
    try std.testing.expectEqual(@as(u32, 64), cache.channel);
    try std.testing.expectEqual(@as(usize, 0), snapshot.pendingCount());
    // An empty cache can be acquired again without allocation.
    try std.testing.expectEqual(snapshot, try manager.acquireChannel(&cache));
}

test "route snapshots channel caches validate channels before changing ownership" {
    var target: Target = .{};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &.{.{ .name = "audit", .sink = target.sink() }},
    });
    defer manager.destroy();
    var global: routes.Manager.ChannelCache = .{ .channel = 0 };
    var oversized: routes.Manager.ChannelCache = .{ .channel = 65 };
    try std.testing.expectError(error.InvalidConfigChannel, manager.acquireChannel(&global));
    try std.testing.expectError(error.InvalidConfigChannel, manager.acquireChannel(&oversized));
    manager.releaseChannelCache(&global);
    manager.releaseChannelCache(&oversized);
    try std.testing.expect(global.snapshot == null and oversized.snapshot == null);
    try std.testing.expectEqual(@as(usize, 0), manager.slots[0].pendingCount());
}

test "route snapshots legacy full metadata compares compiled per-route predicates" {
    var target: Target = .{};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &.{.{ .name = "audit", .sink = target.sink(), .predicate = "status >= 500" }},
        .capacity = 3,
    });
    defer manager.destroy();
    const initial = manager.currentVersion();
    _ = try manager.install(&.{.{ .name = "audit", .sink = target.sink(), .predicate = " status >= 500 " }}, .{});
    const equivalent = try manager.find(0, initial.fingerprint);
    equivalent.release();
    _ = try manager.install(&.{.{ .name = "audit", .sink = target.sink(), .predicate = "status >= 400" }}, .{});
    try std.testing.expectError(error.AmbiguousRecoveryRoute, manager.find(0, initial.fingerprint));
}

test "route snapshots channel cache refresh keeps old accepted records until channel release" {
    var old_target: Target = .{};
    var new_target: Target = .{};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .capacity = 2,
        .initial_routes = &.{.{ .name = "old", .sink = old_target.sink(), .release = old_target.owner() }},
    });
    defer manager.destroy();
    var cache: routes.Manager.ChannelCache = .{ .channel = 1 };
    defer manager.releaseChannelCache(&cache);
    const old = try manager.acquireChannel(&cache);
    const old_version = old.version();
    _ = try manager.install(&.{.{ .name = "new", .sink = new_target.sink() }}, .{});
    // Even an idle cache alone keeps the retired version's target alive.
    try std.testing.expectEqual(@as(usize, 1), old.pendingCount());
    try std.testing.expectEqual(@as(usize, 0), try manager.collectVersions(&.{old_version}));
    old.retainChannel(1); // independently accepted record from the cached call
    const current = try manager.acquireChannel(&cache);
    try std.testing.expect(current != old);
    try std.testing.expectEqualStrings("new", current.routes[0].name);
    try std.testing.expectEqual(@as(usize, 1), current.pendingCount());
    try std.testing.expectEqual(@as(usize, 1), old.pendingCount());
    try std.testing.expectEqual(@as(usize, 0), old.pending.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 0), try manager.collectVersions(&.{old_version}));
    old.releaseChannel(1);
    try std.testing.expectEqual(@as(usize, 1), try manager.collectVersions(&.{old_version}));
    try std.testing.expectEqual(@as(usize, 1), old_target.released.load(.monotonic));
    manager.releaseChannelCache(&cache);
    try std.testing.expectEqual(@as(usize, 0), current.pendingCount());
}

test "route snapshots four owner caches avoid global counters during parallel records" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        manager: *routes.Manager,
        channel: u32,
        ready: std.atomic.Value(bool) = .init(false),
        release: *std.atomic.Value(bool),
        failed: std.atomic.Value(bool) = .init(false),

        fn run(self: *@This()) void {
            var cache: routes.Manager.ChannelCache = .{ .channel = self.channel };
            defer self.manager.releaseChannelCache(&cache);
            const initial = self.manager.acquireChannel(&cache) catch {
                self.failed.store(true, .release);
                self.ready.store(true, .release);
                return;
            };
            for (0..10000) |_| {
                const snapshot = self.manager.acquireChannel(&cache) catch unreachable;
                snapshot.retainChannel(self.channel);
                if (snapshot != initial or snapshot.pending.load(.seq_cst) != 0)
                    self.failed.store(true, .release);
                snapshot.releaseChannel(self.channel);
            }
            self.ready.store(true, .release);
            while (!self.release.load(.acquire)) std.atomic.spinLoopHint();
        }
    };
    var target: Target = .{};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &.{.{ .name = "audit", .sink = target.sink() }},
    });
    defer manager.destroy();
    var release: std.atomic.Value(bool) = .init(false);
    var contexts: [4]Context = undefined;
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    defer {
        release.store(true, .release);
        for (threads[0..started]) |thread| thread.join();
    }
    for (&contexts, &threads, 1..) |*context, *thread, channel| {
        context.* = .{ .manager = manager, .channel = @intCast(channel), .release = &release };
        thread.* = try std.Thread.spawn(.{}, Context.run, .{context});
        started += 1;
    }
    for (&contexts) |*context| {
        while (!context.ready.load(.acquire)) std.atomic.spinLoopHint();
        try std.testing.expect(!context.failed.load(.acquire));
    }
    const snapshot = &manager.slots[0];
    try std.testing.expectEqual(@as(usize, 4), snapshot.pendingCount());
    try std.testing.expectEqual(@as(usize, 0), snapshot.pending.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 0), snapshot.readers.load(.seq_cst));
    for (snapshot.perchannel_pending[0..4]) |*counter| try std.testing.expectEqual(@as(usize, 1), counter.value.load(.seq_cst));
    release.store(true, .release);
    for (threads[0..started]) |thread| thread.join();
    started = 0;
    try std.testing.expectEqual(@as(usize, 0), snapshot.pendingCount());
}

test "route snapshots channel cache publication races preserve the validated version" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        manager: *routes.Manager,
        channel: u32,
        stop: *std.atomic.Value(bool),
        bad: *std.atomic.Value(bool),
        observations: *std.atomic.Value(usize),

        fn read(self: *@This()) void {
            var cache: routes.Manager.ChannelCache = .{ .channel = self.channel };
            defer self.manager.releaseChannelCache(&cache);
            while (!self.stop.load(.acquire)) {
                const snapshot = self.manager.acquireChannel(&cache) catch unreachable;
                snapshot.retainChannel(self.channel);
                for (0..3) |_| std.atomic.spinLoopHint();
                const odd = snapshot.generation & 1 == 1;
                const name = if (odd) "odd" else "even";
                const threshold: Level = if (odd) .debug else .warn;
                const token_matches = cache.publication >> 6 == snapshot.epoch and
                    &self.manager.slots[@intCast(cache.publication & 63)] == snapshot;
                if (!token_matches or !std.mem.eql(u8, snapshot.routes[0].name, name) or
                    snapshot.default_filter.?.threshold("http.child") != threshold or
                    snapshot.pending.load(.seq_cst) != 0)
                    self.bad.store(true, .release);
                snapshot.releaseChannel(self.channel);
                _ = self.observations.fetchAdd(1, .monotonic);
            }
        }
    };
    var target: Target = .{};
    const odd = [_]routes.RouteOptions{.{ .name = "odd", .sink = target.sink() }};
    const even = [_]routes.RouteOptions{.{ .name = "even", .sink = target.sink() }};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &odd,
        .default_filter = "info,http=debug",
        .capacity = 8,
    });
    defer manager.destroy();
    var stop: std.atomic.Value(bool) = .init(false);
    var bad: std.atomic.Value(bool) = .init(false);
    var observations: std.atomic.Value(usize) = .init(0);
    var contexts: [4]Context = undefined;
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    defer {
        stop.store(true, .release);
        for (threads[0..started]) |thread| thread.join();
    }
    for (&contexts, &threads, 1..) |*context, *thread, channel| {
        context.* = .{ .manager = manager, .channel = @intCast(channel), .stop = &stop, .bad = &bad, .observations = &observations };
        thread.* = try std.Thread.spawn(.{}, Context.read, .{context});
        started += 1;
    }
    while (observations.load(.monotonic) < threads.len) std.atomic.spinLoopHint();
    for (0..1500) |i| {
        const is_even = i & 1 == 0;
        while (true) {
            _ = manager.install(if (is_even) &even else &odd, .{
                .default_filter = if (is_even) "err,http=warn" else "info,http=debug",
            }) catch |err| {
                if (err != error.ConfigSlotsExhausted) return err;
                _ = try manager.collectRetired();
                std.atomic.spinLoopHint();
                continue;
            };
            break;
        }
        _ = try manager.collectRetired();
    }
    stop.store(true, .release);
    for (threads[0..started]) |thread| thread.join();
    started = 0;
    try std.testing.expect(!bad.load(.acquire));
    for (manager.slots) |*slot| try std.testing.expectEqual(@as(usize, 0), slot.pendingCount());
}

test "route snapshots allocation failures preserve ownership and current version" {
    const Case = struct {
        fn run(allocator: std.mem.Allocator) !void {
            var initial: Target = .{};
            var replacement: Target = .{};
            const manager = try routes.Manager.create(allocator, std.testing.io, .{
                .initial_routes = &.{.{ .name = "initial", .sink = initial.sink(), .release = initial.owner() }},
            });
            defer manager.abandon();
            var cache: routes.Manager.ChannelCache = .{ .channel = 1 };
            defer manager.releaseChannelCache(&cache);
            const cached = try manager.acquireChannel(&cache);
            const publication = cache.publication;
            const before = manager.currentVersion();
            _ = manager.install(&.{.{ .name = "replacement", .sink = replacement.sink(), .release = replacement.owner() }}, .{}) catch |err| {
                try std.testing.expectEqualDeep(before, manager.currentVersion());
                try std.testing.expectEqual(cached, cache.snapshot.?);
                try std.testing.expectEqual(publication, cache.publication);
                try std.testing.expectEqual(@as(usize, 1), cached.pendingCount());
                try std.testing.expectEqual(@as(usize, 0), cached.pending.load(.seq_cst));
                try std.testing.expectEqual(@as(usize, 0), initial.released.load(.monotonic));
                try std.testing.expectEqual(@as(usize, 0), replacement.released.load(.monotonic));
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Case.run, .{});
}

test "route snapshots abandon and duplicate leases across routes do not double release" {
    var target: Target = .{};
    const options = [_]routes.RouteOptions{
        .{ .name = "one", .sink = target.sink(), .release = target.owner() },
        .{ .name = "two", .sink = target.sink(), .release = target.owner() },
    };
    const abandoned = try routes.Manager.create(std.testing.allocator, std.testing.io, .{ .initial_routes = &options });
    abandoned.abandon();
    try std.testing.expectEqual(@as(usize, 0), target.released.load(.monotonic));
    const owned = try routes.Manager.create(std.testing.allocator, std.testing.io, .{ .initial_routes = &options });
    _ = try owned.install(&options, .{});
    owned.destroy();
    try std.testing.expectEqual(@as(usize, 1), target.released.load(.monotonic));
}

test "route snapshots bounded metadata and version overflow fail atomically" {
    var target: Target = .{};
    const options = [_]routes.RouteOptions{.{ .name = "audit", .sink = target.sink() }};
    try std.testing.expectError(error.InvalidOptions, routes.Manager.create(std.testing.allocator, std.testing.io, .{ .initial_routes = &options, .capacity = 65 }));
    try std.testing.expectError(error.ConfigBudgetExceeded, routes.Manager.create(std.testing.allocator, std.testing.io, .{ .initial_routes = &options, .max_config_bytes = 1 }));
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{ .initial_routes = &options, .initial_generation = std.math.maxInt(u64) });
    defer manager.destroy();
    const before = manager.currentVersion();
    try std.testing.expectError(error.ConfigGenerationExhausted, manager.install(&options, .{}));
    try std.testing.expectEqualDeep(before, manager.currentVersion());
}

test "route snapshots configured metadata budget supports the full 64-route table" {
    var target: Target = .{};
    var names: [routes.max_routes][16]u8 = undefined;
    var options: [routes.max_routes]routes.RouteOptions = undefined;
    for (&options, &names, 0..) |*option, *name, index| {
        option.* = .{ .name = try std.fmt.bufPrint(name, "route-{d}", .{index}), .sink = target.sink() };
    }
    try std.testing.expectError(error.ConfigBudgetExceeded, routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &options,
        .capacity = 1,
        .max_config_bytes = 1024 * 1024,
    }));
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &options,
        .capacity = 1,
        .max_config_bytes = 2 * 1024 * 1024,
    });
    defer manager.destroy();
    const view = manager.acquire();
    defer view.release();
    try std.testing.expectEqual(@as(usize, 64), view.snapshot.routes.len);
    try std.testing.expectEqualStrings("route-63", view.snapshot.routes[63].name);
}

test "route snapshots concurrent acquire install and collect preserve exact payloads" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        manager: *routes.Manager,
        stop: std.atomic.Value(bool) = .init(false),
        bad: std.atomic.Value(bool) = .init(false),
        observations: std.atomic.Value(usize) = .init(0),

        fn read(context: *@This()) void {
            while (!context.stop.load(.acquire)) {
                const view = context.manager.acquire();
                const snapshot = view.snapshot;
                const odd = snapshot.generation & 1 == 1;
                const name = if (odd) "odd" else "even";
                const threshold: Level = if (odd) .debug else .warn;
                const pin = view.pin();
                view.release();
                for (0..3) |_| std.atomic.spinLoopHint();
                if (!std.mem.eql(u8, snapshot.routes[0].name, name) or
                    snapshot.default_filter.?.threshold("http.child") != threshold)
                    context.bad.store(true, .release);
                const found = context.manager.find(snapshot.generation, snapshot.fingerprint) catch {
                    context.bad.store(true, .release);
                    pin.release();
                    continue;
                };
                if (found.snapshot != snapshot) context.bad.store(true, .release);
                found.release();
                pin.release();
                _ = context.observations.fetchAdd(1, .monotonic);
            }
        }
    };
    var target: Target = .{};
    const odd = [_]routes.RouteOptions{.{ .name = "odd", .sink = target.sink() }};
    const even = [_]routes.RouteOptions{.{ .name = "even", .sink = target.sink() }};
    const manager = try routes.Manager.create(std.testing.allocator, std.testing.io, .{
        .initial_routes = &odd,
        .default_filter = "info,http=debug",
        .capacity = 8,
    });
    defer manager.destroy();
    var context: Context = .{ .manager = manager };
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    defer {
        context.stop.store(true, .release);
        for (threads[0..started]) |thread| thread.join();
    }
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Context.read, .{&context});
        started += 1;
    }
    while (context.observations.load(.monotonic) < threads.len) std.atomic.spinLoopHint();
    for (0..1500) |i| {
        const is_even = i & 1 == 0;
        while (true) {
            _ = manager.install(if (is_even) &even else &odd, .{
                .default_filter = if (is_even) "err,http=warn" else "info,http=debug",
            }) catch |err| {
                if (err != error.ConfigSlotsExhausted) return err;
                _ = try manager.collectRetired();
                std.atomic.spinLoopHint();
                continue;
            };
            break;
        }
        _ = try manager.collectRetired();
    }
    context.stop.store(true, .release);
    for (threads[0..started]) |thread| thread.join();
    started = 0;
    try std.testing.expect(!context.bad.load(.acquire));
    try std.testing.expect(context.observations.load(.monotonic) >= threads.len);
}
