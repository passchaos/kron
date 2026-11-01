//! Consumer-owned configuration views for one bounded delivery batch. Each
//! distinct snapshot remains protected until all writes, barriers and record
//! acknowledgements finish, or the batch returns an error. No global cache or
//! allocation is involved; deinit releases only views, never record pins.
const std = @import("std");
const configurations = @import("../config/routes.zig");
const types = @import("runtime_types.zig");
const Atomic = std.atomic.Value;

pub const TestingAudit = if (@import("builtin").is_test) struct {
    pub var written_updates: Atomic(usize) = .init(0);
} else struct {};

pub const max_records = 64;

pub const Group = struct {
    view: configurations.View,
    route_mask: u64 = 0,
    durable_mask: u64 = 0,
    required_durable_routes: u64 = 0,

    pub fn snapshot(self: *const Group) *configurations.Snapshot {
        return self.view.snapshot;
    }

    pub fn include(self: *Group, mask: u64) @import("../journal/journal.zig").ReclaimBoundary {
        self.route_mask |= mask;
        if (mask & self.required_durable_routes == 0) return .written;
        // Preserve the existing barrier: when any required route needs durable
        // reclaim, synchronize every required target selected for this event.
        self.durable_mask |= mask;
        return .durable;
    }
};

fn requiredDurableRoutes(routes: []const types.Route) u64 {
    std.debug.assert(routes.len <= 64);
    var mask: u64 = 0;
    for (routes, 0..) |*route, index| {
        if (route.delivery == .required and route.reclaim_after == .durable) mask |= @as(u64, 1) << @intCast(index);
    }
    return mask;
}

/// Consumer-local count of successfully acknowledged records. A channel
/// change publishes its prior run; error unwinding flushes the acknowledged
/// prefix as well. Use defer flush and explicitly flush before notifying a
/// completed batch. Concurrent sync/fallback writes still use the same atomic.
pub const WrittenCounts = struct {
    counter: ?*Atomic(u64) = null,
    count: u64 = 0,

    pub fn acknowledged(self: *WrittenCounts, counter: *Atomic(u64)) void {
        if (self.counter != counter) {
            self.flush();
            self.counter = counter;
        }
        self.count += 1;
    }

    pub fn flush(self: *WrittenCounts) void {
        if (self.count == 0) return;
        if (@import("builtin").is_test) _ = TestingAudit.written_updates.fetchAdd(1, .monotonic);
        _ = self.counter.?.fetchAdd(self.count, .monotonic);
        self.count = 0;
    }
};

pub const Configurations = struct {
    manager: *configurations.Manager,
    storage: [max_records]Group = undefined,
    count: usize = 0,

    pub fn init(manager: *configurations.Manager) Configurations {
        return .{ .manager = manager };
    }

    pub fn select(self: *Configurations, generation: u64, fingerprint: u64) !*Group {
        // Captured records bind a nonzero generation and exact fingerprint.
        // The view protects both immutable fields for every cache hit. Legacy
        // generation zero must still run Manager.find's full ambiguity check.
        if (generation != 0) for (self.storage[0..self.count]) |*group| {
            const snapshot = group.snapshot();
            if (snapshot.generation == generation and snapshot.fingerprint == fingerprint) return group;
        };
        const view = try self.manager.find(generation, fingerprint);
        for (self.storage[0..self.count]) |*group| if (group.snapshot() == view.snapshot) {
            view.release();
            return group;
        };
        if (self.count == max_records) {
            view.release();
            return error.DeliveryBatchTooLarge;
        }
        const group = &self.storage[self.count];
        group.* = .{ .view = view, .required_durable_routes = requiredDurableRoutes(view.snapshot.routes) };
        self.count += 1;
        return group;
    }

    pub fn groups(self: *Configurations) []Group {
        return self.storage[0..self.count];
    }

    pub fn deinit(self: *Configurations) void {
        for (self.groups()) |group| group.view.release();
        self.count = 0;
    }
};

const Sink = @import("../sink/interface.zig").Sink;
const EmptySink = struct {
    fn write(_: *anyopaque, _: []const u8) anyerror!void {}
    fn flush(_: *anyopaque) anyerror!void {}
    const vtable: Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = flush };
};

test "batch configuration selects one protected view per exact version and keeps retired leases alive" {
    const Lease = struct {
        released: usize = 0,
        fn release(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.released += 1;
        }
        fn route(self: *@This()) configurations.RouteOptions {
            return .{ .name = "old", .sink = .{ .context = self, .vtable = &EmptySink.vtable }, .release = .{ .context = self, .release = release } };
        }
    };
    var old: Lease = .{};
    var next: u8 = 0;
    const manager = try configurations.Manager.create(std.testing.allocator, std.testing.io, .{ .capacity = 2, .initial_routes = &.{old.route()} });
    defer manager.destroy();
    const version = manager.currentVersion();
    var batch = Configurations.init(manager);
    defer batch.deinit();
    const before = configurations.TestingAudit.find_calls;
    const first = try batch.select(version.generation, version.fingerprint);
    for (0..64) |_| try std.testing.expect(first == try batch.select(version.generation, version.fingerprint));
    try std.testing.expectEqual(@as(usize, 1), configurations.TestingAudit.find_calls - before);
    try std.testing.expectEqual(@as(usize, 1), first.snapshot().readers.load(.seq_cst));
    const replacement = try manager.install(&.{.{ .name = "next", .sink = .{ .context = &next, .vtable = &EmptySink.vtable } }}, .{});
    const second = try batch.select(replacement.generation, replacement.fingerprint);
    try std.testing.expect(first != second);
    try std.testing.expectEqual(@as(usize, 0), try manager.collectRetired());
    try std.testing.expectEqual(@as(usize, 0), old.released);
    try std.testing.expectError(error.RecoveryRouteMismatch, batch.select(version.generation, version.fingerprint ^ 1));
    try std.testing.expectError(error.RecoveryRouteMismatch, batch.select(replacement.generation + 1, replacement.fingerprint));
    batch.deinit();
    try std.testing.expectEqual(@as(usize, 1), try manager.collectRetired());
    try std.testing.expectEqual(@as(usize, 1), old.released);
}

test "legacy batch lookups retain manager validation and batch views allocate nothing" {
    var context: u8 = 0;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const route: configurations.RouteOptions = .{ .name = "same", .sink = .{ .context = &context, .vtable = &EmptySink.vtable } };
    const manager = try configurations.Manager.create(failing.allocator(), std.testing.io, .{ .initial_routes = &.{route} });
    defer manager.destroy();
    const version = try manager.install(&.{route}, .{});
    var batch = Configurations.init(manager);
    defer batch.deinit();
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    const before = configurations.TestingAudit.find_calls;
    const group = try batch.select(0, version.fingerprint);
    for (0..8) |_| try std.testing.expect(group == try batch.select(0, version.fingerprint));
    try std.testing.expectEqual(@as(usize, 9), configurations.TestingAudit.find_calls - before);
    try std.testing.expectEqual(@as(usize, 1), batch.count);
    try std.testing.expect(!failing.has_induced_failure);
    batch.deinit();
    try std.testing.expectEqual(@as(usize, 1), try manager.collectRetired());
}

test "batch views cover the maximum 64 versions and deduplicate equal targets by exact generation" {
    var context: u8 = 0;
    const route: configurations.RouteOptions = .{ .name = "target", .sink = .{ .context = &context, .vtable = &EmptySink.vtable } };
    const manager = try configurations.Manager.create(std.testing.allocator, std.testing.io, .{ .capacity = 64, .initial_routes = &.{route} });
    defer manager.destroy();
    var versions: [64]configurations.Version = undefined;
    versions[0] = manager.currentVersion();
    for (versions[1..]) |*version| version.* = try manager.install(&.{route}, .{});
    var batch = Configurations.init(manager);
    defer batch.deinit();
    const initial = configurations.TestingAudit.find_calls;
    for (versions) |version| _ = try batch.select(version.generation, version.fingerprint);
    for (0..3) |_| {
        for (versions) |version| _ = try batch.select(version.generation, version.fingerprint);
    }
    try std.testing.expectEqual(@as(usize, 64), configurations.TestingAudit.find_calls - initial);
    try std.testing.expectEqual(@as(usize, 64), batch.count);
    try std.testing.expectEqual(@as(usize, 0), try manager.collectRetired());
    batch.deinit();
    try std.testing.expectEqual(@as(usize, 63), try manager.collectRetired());
}

test "precomputed durable masks retain required best effort and full event barrier semantics" {
    const delivery = @import("delivery.zig");
    var context: u8 = 0;
    const sink: Sink = .{ .context = &context, .vtable = &EmptySink.vtable, .supports_durable = true };
    var options: [64]configurations.RouteOptions = undefined;
    var names: [64][12]u8 = undefined;
    for (&options, &names, 0..) |*route, *name, index| {
        route.* = .{ .name = try std.fmt.bufPrint(name, "route-{d}", .{index}), .sink = sink, .delivery = if (index % 3 == 0) .best_effort else .required, .reclaim_after = if (index % 2 == 0) .durable else .written };
    }
    const manager = try configurations.Manager.create(std.testing.allocator, std.testing.io, .{ .max_config_bytes = 4 * 1024 * 1024, .initial_routes = &options });
    defer manager.destroy();
    const version = manager.currentVersion();
    var batch = Configurations.init(manager);
    defer batch.deinit();
    const group = try batch.select(version.generation, version.fingerprint);
    var expected_union: u64 = 0;
    var expected_durable: u64 = 0;
    var random = std.Random.DefaultPrng.init(0x6261746368647572);
    for (0..1024) |index| {
        const mask = if (index < 64) @as(u64, 1) << @intCast(index) else random.random().int(u64);
        const needs = delivery.needsDurableReclaim(group.snapshot().routes, mask);
        try std.testing.expectEqual(if (needs) @import("../journal/journal.zig").ReclaimBoundary.durable else .written, group.include(mask));
        expected_union |= mask;
        if (needs) expected_durable |= mask;
        try std.testing.expectEqual(expected_union, group.route_mask);
        try std.testing.expectEqual(expected_durable, group.durable_mask);
    }
    // The top bit must work for an explicitly required durable route too.
    group.required_durable_routes = @as(u64, 1) << 63;
    group.route_mask = 0;
    group.durable_mask = 0;
    try std.testing.expectEqual(@import("../journal/journal.zig").ReclaimBoundary.durable, group.include(std.math.maxInt(u64)));
    try std.testing.expectEqual(std.math.maxInt(u64), group.durable_mask);
}

test "written batch counts publish only acknowledged runs and preserve concurrent increments" {
    var first: Atomic(u64) = .init(7);
    var second: Atomic(u64) = .init(11);
    var counts: WrittenCounts = .{};
    const updates = TestingAudit.written_updates.load(.monotonic);
    for (0..31) |_| counts.acknowledged(&first);
    try std.testing.expectEqual(@as(u64, 7), first.load(.monotonic));
    counts.acknowledged(&second);
    try std.testing.expectEqual(@as(u64, 38), first.load(.monotonic));
    counts.acknowledged(&first);
    try std.testing.expectEqual(@as(u64, 12), second.load(.monotonic));
    // A synchronous/fallback owner can increment the same counter before the
    // pending batch count is published; fetchAdd preserves that update.
    _ = first.fetchAdd(5, .monotonic);
    counts.flush();
    counts.flush();
    try std.testing.expectEqual(@as(u64, 44), first.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 3), TestingAudit.written_updates.load(.monotonic) - updates);
}

test "written batch counts compose with a concurrent sync or fallback counter owner" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Concurrent = struct {
        counter: Atomic(u64) = .init(0),
        start: std.Io.Event = .unset,

        fn run(self: *@This()) void {
            self.start.waitUncancelable(std.testing.io);
            for (0..10000) |_| _ = self.counter.fetchAdd(1, .monotonic);
        }
    };
    var context: Concurrent = .{};
    const thread = try std.Thread.spawn(.{}, Concurrent.run, .{&context});
    context.start.set(std.testing.io);
    for (0..1000) |_| {
        var counts: WrittenCounts = .{};
        for (0..31) |_| counts.acknowledged(&context.counter);
        counts.flush();
    }
    thread.join();
    try std.testing.expectEqual(@as(u64, 41000), context.counter.load(.monotonic));
}
