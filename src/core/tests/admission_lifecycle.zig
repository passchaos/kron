//! Admission lifecycle contracts observed only through active-owner helpers.
const std = @import("std");
const builtin = @import("builtin");
const admission = @import("../admission.zig");
const BoundDecision = @import("../../config/reload.zig").BoundDecision;
const Level = @import("../level.zig").Level;
const testing = std.testing;

fn decision(level: Level, generation: u64, configuration_generation: u64) BoundDecision {
    return .{ .decision = .{ .level = level, .generation = generation }, .configuration_generation = configuration_generation };
}

fn decisionMatches(actual: ?BoundDecision, expected: BoundDecision) bool {
    const value = actual orelse return false;
    return value.decision.level == expected.decision.level and
        value.decision.generation == expected.decision.generation and
        value.configuration_generation == expected.configuration_generation;
}

fn activeMatches(owner: *anyopaque, resource: *anyopaque, channel: u32, scope: []const u8, expected: BoundDecision) bool {
    return admission.contains(owner) and admission.getResource(owner) == resource and
        admission.getChannel(owner) == channel and decisionMatches(admission.getFilterDecision(owner, scope), expected);
}

fn expectBare(owner: *anyopaque, previous_scope: []const u8) !void {
    try testing.expect(admission.contains(owner));
    try testing.expect(admission.getResource(owner) == null);
    try testing.expectEqual(@as(u32, 0), admission.getChannel(owner));
    try testing.expect(admission.getFilterDecision(owner, previous_scope) == null);
    try testing.expect(admission.getFilterDecision(owner, "") == null);
}

fn expectInactive(owner: *anyopaque, previous_scope: []const u8) !void {
    // These getters search active owners. Never inspect inactive frame bytes.
    try testing.expect(!admission.contains(owner));
    try testing.expect(admission.getResource(owner) == null);
    try testing.expectEqual(@as(u32, 0), admission.getChannel(owner));
    try testing.expect(admission.getFilterDecision(owner, previous_scope) == null);
    try testing.expect(admission.getFilterDecision(owner, "") == null);
}

const ReleaseCounter = struct {
    calls: usize = 0,
    fn release(raw: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.calls += 1;
    }
};

test "admission lifecycle: owned bare borrowed reuse resets getters without repeating releases" {
    var owner: u8 = 0;
    var owned: ReleaseCounter = .{};
    var borrowed: ReleaseCounter = .{};
    const owned_decision = decision(.debug, 31, 41);
    const borrowed_decision = decision(.err, 51, 61);
    if (!admission.enter(&owner)) return error.AdmissionRejected;
    var active = true;
    defer if (active) admission.leave(&owner);
    try expectBare(&owner, "owned.scope");
    admission.attachResource(&owner, &owned, ReleaseCounter.release);
    admission.attachFilterDecision(&owner, "owned.scope", owned_decision);
    try testing.expect(activeMatches(&owner, &owned, 0, "owned.scope", owned_decision));
    admission.leave(&owner);
    active = false;
    try expectInactive(&owner, "owned.scope");
    try testing.expectEqual(@as(usize, 1), owned.calls);

    if (!admission.enter(&owner)) return error.AdmissionRejected;
    active = true;
    try expectBare(&owner, "owned.scope");
    try testing.expect(admission.getFilterDecision(&owner, "borrowed.scope") == null);
    admission.leave(&owner);
    active = false;
    try expectInactive(&owner, "owned.scope");
    try testing.expectEqual(@as(usize, 1), owned.calls);

    if (!admission.enter(&owner)) return error.AdmissionRejected;
    active = true;
    try expectBare(&owner, "owned.scope");
    admission.attachBorrowedResource(&owner, &borrowed, 19);
    admission.attachFilterDecision(&owner, "borrowed.scope", borrowed_decision);
    try testing.expect(activeMatches(&owner, &borrowed, 19, "borrowed.scope", borrowed_decision));
    try testing.expect(admission.getFilterDecision(&owner, "owned.scope") == null);
    admission.leave(&owner);
    active = false;
    try expectInactive(&owner, "borrowed.scope");

    if (!admission.enter(&owner)) return error.AdmissionRejected;
    active = true;
    try expectBare(&owner, "borrowed.scope");
    try testing.expect(admission.getFilterDecision(&owner, "owned.scope") == null);
    admission.leave(&owner);
    active = false;
    try expectInactive(&owner, "borrowed.scope");
    try testing.expectEqual(@as(usize, 1), owned.calls);
    try testing.expectEqual(@as(usize, 0), borrowed.calls);
    try testing.expect(!admission.full());
}

test "admission lifecycle: all levels full width generations and channels survive decision overwrite and bare reuse" {
    const levels = std.meta.tags(Level);
    const generations = [_]u64{ 0, 1, std.math.maxInt(i64), @as(u64, std.math.maxInt(i64)) + 1, std.math.maxInt(u64) };
    const channels = [_]u32{ 1, 64, std.math.maxInt(u32) };
    const scopes = [_][]const u8{ "", "boundary.scope" };
    var owner: u8 = 0;
    for (levels, 0..) |level, level_index| {
        for (generations, 0..) |generation, generation_index| {
            // Independent rotation covers every configuration generation for
            // each filter generation, including both sides of the i64 bound.
            for (0..generations.len) |rotation| {
                const configuration_index = (generation_index + rotation) % generations.len;
                for (channels) |channel| {
                    for (scopes) |scope| {
                        const other_scope: []const u8 = if (scope.len == 0) "boundary.scope" else "";
                        var resource: ReleaseCounter = .{};
                        if (!admission.enter(&owner)) return error.AdmissionRejected;
                        var active = true;
                        defer if (active) admission.leave(&owner);
                        try expectBare(&owner, "boundary.scope");
                        admission.attachBorrowedResource(&owner, &resource, channel);
                        const initial = decision(level, generation, generations[configuration_index]);
                        admission.attachFilterDecision(&owner, scope, initial);
                        const initial_read = admission.getFilterDecision(&owner, scope) orelse return error.MissingFilterDecision;
                        try testing.expectEqualDeep(initial, initial_read);
                        try testing.expectEqual(channel, admission.getChannel(&owner));
                        try testing.expectEqual(@as(?*anyopaque, &resource), admission.getResource(&owner));
                        try testing.expect(admission.getFilterDecision(&owner, other_scope) == null);
                        try testing.expect(admission.getFilterDecision(&owner, "mismatch.boundary") == null);

                        // Reattaching the same scope replaces ALL fields. Each
                        // replacement component differs from its prior value.
                        const replacement = decision(
                            levels[(level_index + 1) % levels.len],
                            generations[(generation_index + 1) % generations.len],
                            generations[(configuration_index + 2) % generations.len],
                        );
                        admission.attachFilterDecision(&owner, scope, replacement);
                        const replacement_read = admission.getFilterDecision(&owner, scope) orelse return error.MissingFilterDecision;
                        try testing.expectEqualDeep(replacement, replacement_read);
                        try testing.expectEqual(channel, admission.getChannel(&owner));

                        // Changing scope discards the previous binding rather
                        // than retaining an old per-scope decision to merge.
                        admission.attachFilterDecision(&owner, other_scope, initial);
                        const moved_read = admission.getFilterDecision(&owner, other_scope) orelse return error.MissingFilterDecision;
                        try testing.expectEqualDeep(initial, moved_read);
                        try testing.expect(admission.getFilterDecision(&owner, scope) == null);
                        try testing.expect(admission.getFilterDecision(&owner, "mismatch.boundary") == null);
                        try testing.expectEqual(channel, admission.getChannel(&owner));
                        admission.leave(&owner);
                        active = false;
                        try expectInactive(&owner, "boundary.scope");

                        if (!admission.enter(&owner)) return error.AdmissionRejected;
                        active = true;
                        try expectBare(&owner, "boundary.scope");
                        try testing.expect(admission.getFilterDecision(&owner, "mismatch.boundary") == null);
                        admission.leave(&owner);
                        active = false;
                        try expectInactive(&owner, "boundary.scope");
                        try testing.expectEqual(@as(usize, 0), resource.calls);
                    }
                }
            }
        }
    }
    try testing.expect(!admission.full());
}

const ReentrantRelease = struct {
    outer: *anyopaque,
    inner: *anyopaque,
    outer_decision: BoundDecision,
    inner_decision: BoundDecision,
    borrowed_decision: BoundDecision,
    calls: usize = 0,
    inner_calls: usize = 0,
    observations_ok: bool = true,

    const InnerResource = struct {
        parent: *ReentrantRelease,
        borrowed: bool = false,
        fn release(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const parent = self.parent;
            parent.inner_calls += 1;
            parent.check(!self.borrowed);
            parent.check(activeMatches(parent.outer, parent, 0, "outer.scope", parent.outer_decision));
            parent.check(activeMatches(parent.inner, self, 0, "inner.scope", parent.inner_decision));
        }
    };

    fn check(self: *@This(), okay: bool) void {
        if (!okay) self.observations_ok = false;
    }

    fn release(raw: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.calls += 1;
        // leave must retain the outer frame throughout its release callback.
        self.check(activeMatches(self.outer, self, 0, "outer.scope", self.outer_decision));
        const recursive = admission.enter(self.outer);
        self.check(!recursive);
        if (recursive) admission.leave(self.outer);

        var owned: InnerResource = .{ .parent = self };
        if (!admission.enter(self.inner)) {
            self.check(false);
            return;
        }
        var inner_active = true;
        defer if (inner_active) admission.leave(self.inner);
        self.check(admission.getResource(self.inner) == null and admission.getChannel(self.inner) == 0);
        self.check(admission.getFilterDecision(self.inner, "inner.scope") == null);
        admission.attachResource(self.inner, &owned, InnerResource.release);
        admission.attachFilterDecision(self.inner, "inner.scope", self.inner_decision);
        self.check(activeMatches(self.inner, &owned, 0, "inner.scope", self.inner_decision));
        self.check(activeMatches(self.outer, self, 0, "outer.scope", self.outer_decision));
        admission.leave(self.inner);
        inner_active = false;
        self.check(self.inner_calls == 1 and !admission.contains(self.inner));

        var borrowed: InnerResource = .{ .parent = self, .borrowed = true };
        if (!admission.enter(self.inner)) {
            self.check(false);
            return;
        }
        inner_active = true;
        self.check(admission.getResource(self.inner) == null and admission.getChannel(self.inner) == 0);
        self.check(admission.getFilterDecision(self.inner, "inner.scope") == null);
        admission.attachBorrowedResource(self.inner, &borrowed, 37);
        admission.attachFilterDecision(self.inner, "inner.borrowed", self.borrowed_decision);
        self.check(activeMatches(self.inner, &borrowed, 37, "inner.borrowed", self.borrowed_decision));
        self.check(admission.getFilterDecision(self.inner, "inner.scope") == null);
        self.check(activeMatches(self.outer, self, 0, "outer.scope", self.outer_decision));
        admission.leave(self.inner);
        inner_active = false;
        self.check(self.inner_calls == 1 and !admission.contains(self.inner));
        self.check(activeMatches(self.outer, self, 0, "outer.scope", self.outer_decision));
    }
};

test "admission lifecycle: release callbacks retain outer ownership and balance independent nested frames" {
    var outer: u8 = 0;
    var inner: u8 = 0;
    var resource: ReentrantRelease = .{
        .outer = &outer,
        .inner = &inner,
        .outer_decision = decision(.trace, 71, 81),
        .inner_decision = decision(.warn, 91, 101),
        .borrowed_decision = decision(.fatal, 111, 121),
    };
    if (!admission.enter(&outer)) return error.AdmissionRejected;
    var active = true;
    defer if (active) admission.leave(&outer);
    admission.attachResource(&outer, &resource, ReentrantRelease.release);
    admission.attachFilterDecision(&outer, "outer.scope", resource.outer_decision);
    admission.leave(&outer);
    active = false;
    try testing.expect(resource.observations_ok);
    try testing.expectEqual(@as(usize, 1), resource.calls);
    try testing.expectEqual(@as(usize, 1), resource.inner_calls);
    try expectInactive(&outer, "outer.scope");
    try expectInactive(&inner, "inner.scope");
    try expectInactive(&inner, "inner.borrowed");
    try testing.expect(!admission.full());
}

test "admission lifecycle: sixty four active owners reject overflow then pop and reuse with all defaults" {
    var owners: [65]u8 = @splat(0);
    var resources: [64]ReleaseCounter = @splat(.{});
    var active: usize = 0;
    defer while (active != 0) {
        active -= 1;
        admission.leave(&owners[active]);
    };
    for (0..64) |index| {
        if (!admission.enter(&owners[index])) return error.AdmissionRejected;
        active += 1; // Register cleanup before any fallible assertion.
        try expectBare(&owners[index], "capacity.scope");
        if (index % 2 == 0)
            admission.attachResource(&owners[index], &resources[index], ReleaseCounter.release)
        else
            admission.attachBorrowedResource(&owners[index], &resources[index], @intCast(index + 1));
        const expected = decision(if (index % 2 == 0) .debug else .err, index + 1_000, index + 2_000);
        admission.attachFilterDecision(&owners[index], "capacity.scope", expected);
        try testing.expect(activeMatches(&owners[index], &resources[index], if (index % 2 == 0) 0 else @intCast(index + 1), "capacity.scope", expected));
    }
    try testing.expect(admission.full());
    const overflow_entered = admission.enter(&owners[64]);
    if (overflow_entered) admission.leave(&owners[64]);
    try testing.expect(!overflow_entered);
    try expectInactive(&owners[64], "capacity.scope");
    while (active != 0) {
        const index = active - 1;
        const expected = decision(if (index % 2 == 0) .debug else .err, index + 1_000, index + 2_000);
        try testing.expect(activeMatches(&owners[index], &resources[index], if (index % 2 == 0) 0 else @intCast(index + 1), "capacity.scope", expected));
        admission.leave(&owners[index]);
        active -= 1;
        try expectInactive(&owners[index], "capacity.scope");
        try testing.expectEqual(@as(usize, if (index % 2 == 0) 1 else 0), resources[index].calls);
    }
    try testing.expect(!admission.full());
    // Reuse every physical stack position as a bare owner. Prior owned and
    // borrowed resource/channel/filter decisions must never become visible.
    for (0..64) |index| {
        if (!admission.enter(&owners[index])) return error.AdmissionRejected;
        active += 1;
        try expectBare(&owners[index], "capacity.scope");
    }
    try testing.expect(admission.full());
    const reuse_overflow_entered = admission.enter(&owners[64]);
    if (reuse_overflow_entered) admission.leave(&owners[64]);
    try testing.expect(!reuse_overflow_entered);
    while (active != 0) {
        const index = active - 1;
        admission.leave(&owners[index]);
        active -= 1;
        try expectInactive(&owners[index], "capacity.scope");
        try testing.expectEqual(@as(usize, if (index % 2 == 0) 1 else 0), resources[index].calls);
    }
    for (&owners) |*owner| try expectInactive(owner, "capacity.scope");
    try testing.expect(!admission.full());
}

const ThreadLease = struct {
    owner: *anyopaque,
    expected: BoundDecision,
    scope: []const u8,
    calls: usize = 0,
    visible_on_release: bool = false,
    fn release(raw: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.calls += 1;
        self.visible_on_release = activeMatches(self.owner, self, 0, self.scope, self.expected);
    }
};

const ThreadWorker = struct {
    owner: *anyopaque,
    owned: ThreadLease,
    borrowed: ThreadLease,
    channel: u32,
    release_owned: *std.Io.Event,
    release_borrowed: *std.Io.Event,
    owned_ready: std.Io.Event = .unset,
    borrowed_ready: std.Io.Event = .unset,
    observations_ok: bool = true,
    seen_owned: ?BoundDecision = null,
    seen_borrowed: ?BoundDecision = null,
    seen_channel: u32 = 0,
    seen_resource: ?*anyopaque = null,

    fn check(self: *@This(), okay: bool) void {
        if (!okay) self.observations_ok = false;
    }

    fn run(self: *@This()) void {
        // Always signal both phases on early exit; the parent unblocks both
        // gates and joins every spawned thread even if an assertion fails.
        defer {
            self.owned_ready.set(testing.io);
            self.borrowed_ready.set(testing.io);
        }
        if (!admission.enter(self.owner)) {
            self.check(false);
            return;
        }
        var active = true;
        defer if (active) admission.leave(self.owner);
        admission.attachResource(self.owner, &self.owned, ThreadLease.release);
        admission.attachFilterDecision(self.owner, self.owned.scope, self.owned.expected);
        self.owned_ready.set(testing.io);
        self.release_owned.waitUncancelable(testing.io);
        self.seen_owned = admission.getFilterDecision(self.owner, self.owned.scope);
        self.check(activeMatches(self.owner, &self.owned, 0, self.owned.scope, self.owned.expected));
        admission.leave(self.owner);
        active = false;
        self.check(self.owned.calls == 1 and self.owned.visible_on_release);
        self.check(!admission.contains(self.owner) and admission.getResource(self.owner) == null);

        if (!admission.enter(self.owner)) {
            self.check(false);
            return;
        }
        active = true;
        self.check(admission.getResource(self.owner) == null and admission.getChannel(self.owner) == 0);
        self.check(admission.getFilterDecision(self.owner, self.owned.scope) == null);
        self.check(admission.getFilterDecision(self.owner, "") == null);
        admission.attachBorrowedResource(self.owner, &self.borrowed, self.channel);
        admission.attachFilterDecision(self.owner, self.borrowed.scope, self.borrowed.expected);
        self.borrowed_ready.set(testing.io);
        self.release_borrowed.waitUncancelable(testing.io);
        self.seen_borrowed = admission.getFilterDecision(self.owner, self.borrowed.scope);
        self.seen_channel = admission.getChannel(self.owner);
        self.seen_resource = admission.getResource(self.owner);
        self.check(activeMatches(self.owner, &self.borrowed, self.channel, self.borrowed.scope, self.borrowed.expected));
        self.check(admission.getFilterDecision(self.owner, self.owned.scope) == null);
        admission.leave(self.owner);
        active = false;
        self.check(!admission.contains(self.owner) and admission.getResource(self.owner) == null and admission.getChannel(self.owner) == 0);
        self.check(admission.getFilterDecision(self.owner, self.borrowed.scope) == null);
        self.check(self.owned.calls == 1 and self.borrowed.calls == 0 and !admission.full());
    }
};

fn waitReady(event: *std.Io.Event) !void {
    const deadline = @import("../control.zig").Deadline.after(testing.io, 5 * std.time.ns_per_s);
    while (!event.isSet()) event.waitTimeout(testing.io, .{ .deadline = deadline.timestamp }) catch |err| {
        if (err != error.Timeout) return err;
        if (deadline.expired(testing.io) and !event.isSet()) return error.TestHandshakeTimeout;
    };
}

test "admission lifecycle: OS threads isolate the same owner address across simultaneous TLS phases" {
    if (builtin.single_threaded) return error.SkipZigTest;
    var owner: u8 = 0;
    var release_owned: std.Io.Event = .unset;
    var release_borrowed: std.Io.Event = .unset;
    var workers: [2]ThreadWorker = undefined;
    var threads: [2]std.Thread = undefined;
    var spawned: usize = 0;
    defer {
        release_owned.set(testing.io);
        release_borrowed.set(testing.io);
        for (threads[0..spawned]) |thread| thread.join();
    }
    for (&workers, 0..) |*worker, index| {
        worker.* = .{
            .owner = &owner,
            .owned = .{ .owner = &owner, .scope = "tls.owned", .expected = decision(if (index == 0) .debug else .err, index + 101, index + 201) },
            .borrowed = .{ .owner = &owner, .scope = "tls.borrowed", .expected = decision(if (index == 0) .warn else .fatal, index + 301, index + 401) },
            .channel = @intCast(index + 17),
            .release_owned = &release_owned,
            .release_borrowed = &release_borrowed,
        };
        threads[index] = try std.Thread.spawn(.{}, ThreadWorker.run, .{worker});
        spawned += 1;
    }
    for (&workers) |*worker| try waitReady(&worker.owned_ready);
    // Both worker threads hold the exact same owner address now. The parent
    // has its own empty TLS stack and reads no worker-owned plain fields.
    try expectInactive(&owner, "tls.owned");
    release_owned.set(testing.io);
    for (&workers) |*worker| try waitReady(&worker.borrowed_ready);
    try expectInactive(&owner, "tls.borrowed");
    release_borrowed.set(testing.io);
    for (threads[0..spawned]) |thread| thread.join();
    spawned = 0;
    // All plain observations and release counts are read ONLY after joining.
    for (&workers) |*worker| {
        try testing.expect(worker.observations_ok);
        try testing.expectEqual(@as(usize, 1), worker.owned.calls);
        try testing.expect(worker.owned.visible_on_release);
        try testing.expectEqual(@as(usize, 0), worker.borrowed.calls);
        try testing.expectEqualDeep(worker.owned.expected, worker.seen_owned.?);
        try testing.expectEqualDeep(worker.borrowed.expected, worker.seen_borrowed.?);
        try testing.expectEqual(worker.channel, worker.seen_channel);
        try testing.expectEqual(@as(?*anyopaque, &worker.borrowed), worker.seen_resource);
    }
    try expectInactive(&owner, "tls.owned");
    try expectInactive(&owner, "tls.borrowed");
    try testing.expect(!admission.full());
}
