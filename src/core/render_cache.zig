//! Volatile direct-mapped cache of producer-rendered JSON, indexed by journal
//! sequence. The journal ring guarantees that a sequence's slot cannot be
//! reused until the consumer releases it, so the producer owns the matching
//! cache slot exclusively. The consumer clears the entry before releasing the
//! journal record. Recovery starts with an empty cache and falls back to the
//! deferred renderer.

const std = @import("std");
const Atomic = std.atomic.Value;

pub const RenderCache = struct {
    allocator: std.mem.Allocator,
    capacity: usize,
    record_bytes: usize,
    slots: []Slot,
    storage: []u8,

    const Slot = struct {
        state: Atomic(u64) = .init(0),
        length: usize = 0,
    };

    pub const Claim = struct {
        cache: *RenderCache,
        sequence: u64,
        buffer: []u8,

        /// Publish the rendered length before the journal commit, so a
        /// committed record always has a visible render when the consumer
        /// reaches it.
        pub fn publish(self: Claim, length: usize) void {
            std.debug.assert(length <= self.buffer.len);
            const index = self.cache.slotIndex(self.sequence);
            const slot = &self.cache.slots[index];
            slot.length = length;
            slot.state.store(tag(self.sequence), .release);
        }

        /// Undo a claim that was never published or whose journal commit
        /// failed. Only the owning producer can observe this sequence.
        pub fn abort(self: Claim) void {
            const slot = &self.cache.slots[self.cache.slotIndex(self.sequence)];
            if (slot.state.load(.acquire) == tag(self.sequence)) slot.state.store(0, .release);
        }
    };

    pub fn create(allocator: std.mem.Allocator, capacity: usize, record_bytes: usize) !*RenderCache {
        if (capacity == 0 or record_bytes == 0) return error.InvalidRenderCache;
        const self = try allocator.create(RenderCache);
        errdefer allocator.destroy(self);
        const slots = try allocator.alloc(Slot, capacity);
        errdefer allocator.free(slots);
        @memset(slots, .{});
        const storage = try allocator.alloc(u8, capacity * record_bytes);
        errdefer allocator.free(storage);
        self.* = .{ .allocator = allocator, .capacity = capacity, .record_bytes = record_bytes, .slots = slots, .storage = storage };
        return self;
    }

    pub fn destroy(self: *RenderCache) void {
        const allocator = self.allocator;
        allocator.free(self.storage);
        allocator.free(self.slots);
        allocator.destroy(self);
    }

    fn slotIndex(self: *const RenderCache, sequence: u64) usize {
        return @intCast(sequence % self.capacity);
    }

    fn tag(sequence: u64) u64 {
        return (sequence << 1) | 1;
    }

    /// Claim the slot for a reserved journal sequence. A nonzero state means
    /// an older sequence still owns this slot; the producer falls back to the
    /// deferred renderer instead of overwriting it.
    pub fn claim(self: *RenderCache, sequence: u64) ?Claim {
        if (sequence == 0) return null;
        const index = self.slotIndex(sequence);
        const slot = &self.slots[index];
        if (slot.state.load(.acquire) != 0) return null;
        return .{ .cache = self, .sequence = sequence, .buffer = self.storage[index * self.record_bytes ..][0..self.record_bytes] };
    }

    pub fn lookup(self: *RenderCache, sequence: u64) ?[]const u8 {
        const index = self.slotIndex(sequence);
        const slot = &self.slots[index];
        if (slot.state.load(.acquire) != tag(sequence)) return null;
        if (slot.length > self.record_bytes) return null;
        return self.storage[index * self.record_bytes ..][0..slot.length];
    }

    /// Clear only the entry for this sequence; a newer producer claim is
    /// never disturbed.
    pub fn clear(self: *RenderCache, sequence: u64) void {
        const slot = &self.slots[self.slotIndex(sequence)];
        if (slot.state.load(.acquire) == tag(sequence)) slot.state.store(0, .release);
    }
};

test "render cache claim publish lookup clear and stale claim" {
    const cache = try RenderCache.create(std.testing.allocator, 4, 16);
    defer cache.destroy();
    const claim = cache.claim(1).?;
    @memcpy(claim.buffer[0..3], "one");
    claim.publish(3);
    try std.testing.expectEqualStrings("one", cache.lookup(1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), cache.lookup(2));
    try std.testing.expectEqual(@as(?RenderCache.Claim, null), cache.claim(1));
    try std.testing.expectEqual(@as(?RenderCache.Claim, null), cache.claim(5));
    cache.clear(1);
    try std.testing.expectEqual(@as(?[]const u8, null), cache.lookup(1));
    const next = cache.claim(5).?;
    @memcpy(next.buffer[0..4], "next");
    next.publish(4);
    try std.testing.expectEqualStrings("next", cache.lookup(5).?);
    next.abort();
    try std.testing.expectEqual(@as(?[]const u8, null), cache.lookup(5));
}

test "render cache wraps by capacity and keeps distinct sequences separate" {
    const cache = try RenderCache.create(std.testing.allocator, 8, 8);
    defer cache.destroy();
    const first = cache.claim(1).?;
    @memcpy(first.buffer[0..1], "a");
    first.publish(1);
    // Sequence 9 maps to the same direct-mapped slot while 1 is live.
    try std.testing.expectEqual(@as(?RenderCache.Claim, null), cache.claim(9));
    const second = cache.claim(10).?;
    @memcpy(second.buffer[0..1], "b");
    second.publish(1);
    try std.testing.expectEqualStrings("a", cache.lookup(1).?);
    try std.testing.expectEqualStrings("b", cache.lookup(10).?);
    cache.clear(1);
    cache.clear(10);
    const third = cache.claim(17).?;
    @memcpy(third.buffer[0..1], "c");
    third.publish(1);
    try std.testing.expectEqualStrings("c", cache.lookup(17).?);
}
