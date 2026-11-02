//! Shared admission protocol. Flags and count use a single atomic word so a
//! close/cut has one modification order with concurrent acquisitions. TLS
//! tracks callback reentrancy without a process-wide producer hotspot.
const std = @import("std");
const Atomic = std.atomic.Value;
const BoundDecision = @import("../config/reload.zig").BoundDecision;

pub const closing_bit: u64 = 1 << 63;
pub const cut_bit: u64 = 1 << 62;
pub const count_mask: u64 = cut_bit - 1;
const max_depth = 64;
const Frame = struct {
    owner: ?*anyopaque = null,
    resource: ?*anyopaque = null,
    release: ?*const fn (*anyopaque) void = null,
    channel: u32 = 0,
    filter_scope: []const u8 = "",
    filter_decision: ?BoundDecision = null,
    shared_token: ?*Atomic(u64) = null,
};
threadlocal var owners: [max_depth]Frame = @splat(.{});
threadlocal var depth: usize = 0;

pub fn contains(owner: *anyopaque) bool {
    for (owners[0..depth]) |value| if (value.owner == owner) return true;
    return false;
}

pub fn full() bool {
    return depth == max_depth;
}

pub fn enter(owner: *anyopaque) bool {
    if (full() or contains(owner)) return false;
    owners[depth] = .{ .owner = owner };
    depth += 1;
    return true;
}

pub fn leave(owner: *anyopaque) void {
    std.debug.assert(depth != 0 and owners[depth - 1].owner == owner);
    const frame = owners[depth - 1];
    if (frame.resource) |resource| if (frame.release) |release_callback| release_callback(resource);
    depth -= 1;
    owners[depth] = .{};
}

/// A shared admission carries its original shard through nested callbacks.
/// The token is cleared with the TLS frame and never cached past this call.
pub fn enterShared(owner: *anyopaque, token: *Atomic(u64)) bool {
    if (!enter(owner)) return false;
    owners[depth - 1].shared_token = token;
    return true;
}

/// Release the borrowed configuration before the caller decrements its shard.
pub fn leaveShared(owner: *anyopaque) *Atomic(u64) {
    std.debug.assert(depth != 0 and owners[depth - 1].owner == owner);
    const token = owners[depth - 1].shared_token.?;
    leave(owner);
    return token;
}

pub fn attachResource(owner: *anyopaque, resource: *anyopaque, release_callback: *const fn (*anyopaque) void) void {
    std.debug.assert(depth != 0 and owners[depth - 1].owner == owner);
    std.debug.assert(owners[depth - 1].resource == null);
    owners[depth - 1].resource = resource;
    owners[depth - 1].release = release_callback;
}

pub fn getResource(owner: *anyopaque) ?*anyopaque {
    var index = depth;
    while (index != 0) {
        index -= 1;
        if (owners[index].owner == owner) return owners[index].resource;
    }
    return null;
}

pub fn attachBorrowedResource(owner: *anyopaque, resource: *anyopaque, channel: u32) void {
    std.debug.assert(depth != 0 and owners[depth - 1].owner == owner);
    std.debug.assert(owners[depth - 1].resource == null and channel != 0);
    owners[depth - 1].resource = resource;
    owners[depth - 1].channel = channel;
}

pub fn getChannel(owner: *anyopaque) u32 {
    var index = depth;
    while (index != 0) {
        index -= 1;
        if (owners[index].owner == owner) return owners[index].channel;
    }
    return 0;
}

pub fn attachFilterDecision(owner: *anyopaque, scope: []const u8, decision: BoundDecision) void {
    std.debug.assert(depth != 0 and owners[depth - 1].owner == owner);
    owners[depth - 1].filter_scope = scope;
    owners[depth - 1].filter_decision = decision;
}

pub fn getFilterDecision(owner: *anyopaque, scope: []const u8) ?BoundDecision {
    var index = depth;
    while (index != 0) {
        index -= 1;
        if (owners[index].owner == owner and std.mem.eql(u8, owners[index].filter_scope, scope)) return owners[index].filter_decision;
    }
    return null;
}

pub fn acquire(gate: *Atomic(u64), epoch: *Atomic(u32), io: std.Io) bool {
    var observed = gate.load(.acquire);
    while (true) {
        if (observed & closing_bit != 0) return false;
        if (observed & cut_bit != 0) {
            const version = epoch.load(.acquire);
            observed = gate.load(.acquire);
            if (observed & cut_bit != 0 and observed & closing_bit == 0) io.futexWaitUncancelable(u32, &epoch.raw, version);
            observed = gate.load(.acquire);
            continue;
        }
        if (observed & count_mask == count_mask) return false;
        if (gate.cmpxchgWeak(observed, observed + 1, .acq_rel, .acquire)) |actual| {
            observed = actual;
        } else return true;
    }
}

pub fn release(gate: *Atomic(u64)) u64 {
    const previous = gate.fetchSub(1, .acq_rel);
    std.debug.assert(previous & count_mask != 0);
    return previous;
}

pub fn wake(epoch: *Atomic(u32), io: std.Io) void {
    _ = epoch.fetchAdd(1, .release);
    io.futexWake(u32, &epoch.raw, std.math.maxInt(u32));
}

pub fn wait(gate: *Atomic(u64), epoch: *Atomic(u32), io: std.Io) void {
    while (gate.load(.acquire) & count_mask != 0) {
        const version = epoch.load(.acquire);
        if (gate.load(.acquire) & count_mask == 0) break;
        io.futexWaitUncancelable(u32, &epoch.raw, version);
    }
}

test "TLS owner stack rejects recursion and preserves nested independent runtimes" {
    var first: u8 = 0;
    var second: u8 = 0;
    try std.testing.expect(enter(&first));
    defer leave(&first);
    try std.testing.expect(!enter(&first));
    try std.testing.expect(enter(&second));
    try std.testing.expect(contains(&first));
    leave(&second);
    try std.testing.expect(!contains(&second));
}

test "closed admission preserves outstanding count and denies new producers" {
    var gate: Atomic(u64) = .init(0);
    var epoch: Atomic(u32) = .init(0);
    try std.testing.expect(acquire(&gate, &epoch, std.testing.io));
    _ = gate.fetchOr(closing_bit, .acq_rel);
    try std.testing.expect(!acquire(&gate, &epoch, std.testing.io));
    const previous = release(&gate);
    try std.testing.expectEqual(closing_bit | 1, previous);
    try std.testing.expectEqual(closing_bit, gate.load(.acquire));
}

test "outer runtime resource lookup survives nested independent runtime frames" {
    var outer: u8 = 0;
    var inner: u8 = 0;
    var resource: u8 = 0;
    try std.testing.expect(enter(&outer));
    defer leave(&outer);
    attachBorrowedResource(&outer, &resource, 3);
    try std.testing.expect(enter(&inner));
    try std.testing.expectEqual(@as(u32, 3), getChannel(&outer));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&resource)), getResource(&outer));
    try std.testing.expectEqual(@as(u32, 0), getChannel(&inner));
    try std.testing.expect(getResource(&inner) == null);
    leave(&inner);
    try std.testing.expectEqual(@as(u32, 3), getChannel(&outer));
}

test "shared admission tokens survive nested owners and release resources before their count" {
    const Observer = struct {
        token: *Atomic(u64),
        count_at_release: u64 = 0,
        fn release(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.count_at_release = self.token.load(.seq_cst) & count_mask;
        }
    };
    var first: u8 = 0;
    var second: u8 = 0;
    var first_token: Atomic(u64) = .init(1);
    var second_token: Atomic(u64) = .init(1);
    var observed: Observer = .{ .token = &first_token };
    try std.testing.expect(enterShared(&first, &first_token));
    attachResource(&first, &observed, Observer.release);
    try std.testing.expect(enterShared(&second, &second_token));
    const inner = leaveShared(&second);
    try std.testing.expect(inner == &second_token);
    _ = release(inner);
    try std.testing.expect(contains(&first));
    const outer = leaveShared(&first);
    try std.testing.expect(outer == &first_token);
    try std.testing.expectEqual(@as(u64, 1), observed.count_at_release);
    _ = release(outer);
    try std.testing.expectEqual(@as(u64, 0), first_token.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 0), second_token.load(.seq_cst));
    try std.testing.expect(!contains(&first));
}
