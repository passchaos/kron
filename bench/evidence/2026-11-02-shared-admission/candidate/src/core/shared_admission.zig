//! Shared producer admission with one count per cache line. Global stores only
//! flags and a control revision; callers retain the exact acquired word until
//! their TLS frame and captured resources have been released.
//!
//! The SC order includes initial global read, shard increment, global recheck,
//! global cut publication and shard freezing. A successful recheck before cut
//! puts the increment before freezing, so wait sees its count. A recheck after
//! cut cannot pass the unchanged open revision. Frozen lines reject all later
//! increments, and a terminal close prevents revision wrap from creating ABA.
const std = @import("std");
const builtin = @import("builtin");
const Atomic = std.atomic.Value;

pub const closing_bit: u64 = 1 << 63;
pub const cut_bit: u64 = 1 << 62;
pub const count_mask: u64 = cut_bit - 1;
pub const revision_mask: u64 = count_mask;
pub const shard_count = 64;

pub const CacheLine = extern struct {
    word: Atomic(u64) align(64) = .init(0),
    padding: [64 - @sizeOf(Atomic(u64))]u8 = undefined,
};

pub const TestingPoint = enum {
    after_global_read,
    before_global_recheck,
    accepted,
    before_wait,
    after_cut_published,
    before_close_publish,
    before_end_cut_publish,
};

/// Thread-local hooks cannot perturb unrelated producers or retain a Runtime.
/// The entire hook path, including forced shard selection, disappears outside
/// tests. `accepted` runs while the returned token's count is still held.
pub const TestingHooks = if (builtin.is_test) struct {
    context: ?*anyopaque = null,
    pause: ?*const fn (?*anyopaque, TestingPoint) void = null,
    forced_shard: ?usize = null,
} else struct {};
pub threadlocal var testing_hooks: TestingHooks = .{};
threadlocal var cached_shard: u8 = shard_count;

inline fn testPoint(point: TestingPoint) void {
    if (builtin.is_test) if (testing_hooks.pause) |pause| pause(testing_hooks.context, point);
}

fn threadShard() usize {
    if (builtin.is_test) if (testing_hooks.forced_shard) |index| {
        std.debug.assert(index < shard_count);
        return index;
    };
    if (cached_shard == shard_count) {
        // OS thread IDs are consecutive on common targets. Hash once per OS
        // thread, rather than placing those low bits directly in adjacent lines.
        var hash: u64 = @intCast(std.Thread.getCurrentId());
        hash ^= hash >> 30;
        hash *%= 0xbf58476d1ce4e5b9;
        hash ^= hash >> 27;
        hash *%= 0x94d049bb133111eb;
        hash ^= hash >> 31;
        cached_shard = @intCast(hash & (shard_count - 1));
    }
    return cached_shard;
}

pub const Shards = struct {
    lines: [shard_count]CacheLine = @splat(.{}),

    pub fn acquire(self: *Shards, global: *Atomic(u64), epoch: *Atomic(u32), io: std.Io) ?*Atomic(u64) {
        const token = &self.lines[threadShard()].word;
        while (true) {
            const revision = global.load(.seq_cst);
            testPoint(.after_global_read);
            if (revision & closing_bit != 0) return null;
            if (revision & cut_bit != 0) {
                const version = epoch.load(.seq_cst);
                const current = global.load(.seq_cst);
                if (current & closing_bit != 0) return null;
                if (current & cut_bit != 0) {
                    testPoint(.before_wait);
                    io.futexWaitUncancelable(u32, &epoch.raw, version);
                }
                continue;
            }

            var observed = token.load(.seq_cst);
            while (observed & (closing_bit | cut_bit) == 0) {
                if (observed & count_mask == count_mask) return null;
                if (token.cmpxchgWeak(observed, observed + 1, .seq_cst, .seq_cst)) |actual| {
                    observed = actual;
                    continue;
                }
                testPoint(.before_global_recheck);
                const current = global.load(.seq_cst);
                if (current == revision) {
                    testPoint(.accepted);
                    return token;
                }
                const previous = release(token);
                if (previous & count_mask == 1 and previous & (closing_bit | cut_bit) != 0) wake(epoch, io);
                // Runtime notifies the worker for every rejected acquire. This
                // includes rollbacks whose zero preceded global close publication.
                if (current & closing_bit != 0 or previous & closing_bit != 0) return null;
                break;
            }
            if (observed & closing_bit != 0) return null;
        }
    }

    /// Calls to beginCut/endCut are serialized by the owner's cut mutex. Close
    /// may run concurrently: shard closing flags are permanent.
    pub fn beginCut(self: *Shards, global: *Atomic(u64)) void {
        const current = changeGlobal(global, cut_bit, 0);
        testPoint(.after_cut_published);
        for (&self.lines) |*line| _ = line.word.fetchOr(cut_bit, .seq_cst);
        // Never wrap a revision: an ancient initial read could otherwise pass
        // its recheck after 2^62 control transitions. Exhaustion closes admission
        // permanently, and closing is published only after all lines freeze.
        if (current & revision_mask == revision_mask) self.close(global);
    }

    pub fn endCut(self: *Shards, global: *Atomic(u64), epoch: *Atomic(u32), io: std.Io) void {
        // A saturated revision can no longer distinguish reopen cycles.
        if (global.load(.seq_cst) & revision_mask == revision_mask) self.close(global);
        for (&self.lines) |*line| _ = line.word.fetchAnd(~cut_bit, .seq_cst);
        testPoint(.before_end_cut_publish);
        _ = changeGlobal(global, 0, cut_bit);
        wake(epoch, io);
    }

    /// Freeze every line before publishing global closing. The owner must then
    /// wake the admission epoch and its worker, including when close races cut.
    pub fn close(self: *Shards, global: *Atomic(u64)) void {
        for (&self.lines) |*line| _ = line.word.fetchOr(closing_bit, .seq_cst);
        testPoint(.before_close_publish);
        _ = changeGlobal(global, closing_bit, 0);
    }

    /// After beginCut or close, zero is stable until endCut: every successful
    /// acquisition is either counted in a frozen line or fails its recheck.
    pub fn wait(self: *const Shards, epoch: *Atomic(u32), io: std.Io) void {
        while (self.activeCount() != 0) {
            const version = epoch.load(.seq_cst);
            if (self.activeCount() == 0) return;
            testPoint(.before_wait);
            io.futexWaitUncancelable(u32, &epoch.raw, version);
        }
    }

    /// A cold scan. During closing its SC observations cannot miss a preceding
    /// final release; saturation also prevents theoretical sum overflow to zero.
    pub fn activeCount(self: *const Shards) u64 {
        var count: u64 = 0;
        for (&self.lines) |*line| count +|= line.word.load(.seq_cst) & count_mask;
        return count;
    }
};

fn changeGlobal(global: *Atomic(u64), set: u64, clear: u64) u64 {
    var observed = global.load(.seq_cst);
    while (true) {
        const revision = observed & revision_mask;
        const next_revision = if (revision == revision_mask) revision else revision + 1;
        const next = ((observed | set) & ~clear & ~revision_mask) | next_revision;
        if (global.cmpxchgWeak(observed, next, .seq_cst, .seq_cst)) |actual| {
            observed = actual;
        } else return next;
    }
}

/// The owner releases its TLS frame/view first, then this exact token. It wakes
/// the admission epoch when the returned count is one and flags contain cut or
/// closing, and also notifies its worker for closing (as for the old protocol).
pub fn release(token: *Atomic(u64)) u64 {
    const previous = token.fetchSub(1, .seq_cst);
    std.debug.assert(previous & count_mask != 0);
    return previous;
}

pub fn wake(epoch: *Atomic(u32), io: std.Io) void {
    _ = epoch.fetchAdd(1, .seq_cst);
    io.futexWake(u32, &epoch.raw, std.math.maxInt(u32));
}

comptime {
    std.debug.assert(@sizeOf(CacheLine) == 64 and @alignOf(CacheLine) == 64);
    std.debug.assert(@sizeOf(Shards) == shard_count * 64 and @alignOf(Shards) == 64);
}

test {
    _ = @import("tests/shared_admission.zig");
}
