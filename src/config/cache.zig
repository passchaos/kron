const std = @import("std");
const Level = @import("../core/level.zig").Level;
const reload = @import("reload.zig");
const DynamicFilter = reload.DynamicFilter;
pub const Decision = reload.Decision;

pub const max_cached_generation: u64 = std.math.maxInt(u56);

/// Caller-owned cache permanently bound to one filter instance and scope.
/// The owner and borrowed scope bytes must outlive all uses, and the scope
/// contents must remain unchanged. Concurrent readers may share this object.
///
/// A hit reads only the owner generation and one packed atomic value. A reload
/// after the first load may leave this call using its previous decision, as
/// permitted for calls that already started. One word keeps the threshold and
/// its generation inseparable even when several readers refresh concurrently.
pub const CachedFilter = struct {
    owner: *DynamicFilter,
    scope: []const u8,
    cache_word: std.atomic.Value(u64) = .init(0),

    pub fn init(owner: *DynamicFilter, scope: []const u8) CachedFilter {
        return .{ .owner = owner, .scope = scope };
    }

    pub fn decision(self: *CachedFilter) Decision {
        const generation = self.owner.generation();
        const word = self.cache_word.load(.acquire);
        if (cacheable(generation) and unpackGeneration(word) == generation) {
            return .{ .level = unpackLevel(word), .generation = generation };
        }

        const fresh = self.owner.decision(self.scope);
        self.publishIfCurrent(fresh);
        return fresh;
    }

    pub fn enabled(self: *CachedFilter, level: Level) bool {
        return self.decision().enabled(level);
    }

    fn publishIfCurrent(self: *CachedFilter, fresh: Decision) void {
        // Never truncate a full u64 generation into the 56-bit cache key.
        // Zero is the empty cache sentinel, including after a full u64 wrap.
        if (!cacheable(fresh.generation) or self.owner.generation() != fresh.generation) return;
        const replacement = pack(fresh);
        var previous = self.cache_word.load(.acquire);
        while (unpackGeneration(previous) < fresh.generation) {
            if (self.cache_word.cmpxchgWeak(previous, replacement, .acq_rel, .acquire)) |actual| {
                previous = actual;
            } else return;
        }
        // A newer refresh wins if it raced this call's older snapshot. A stale
        // cache publication after reload is harmless: the next hit compares
        // the full owner generation and will take the snapshot path again.
    }
};

fn cacheable(generation: u64) bool {
    return generation != 0 and generation <= max_cached_generation;
}

fn pack(decision_: Decision) u64 {
    std.debug.assert(cacheable(decision_.generation));
    return decision_.generation << 8 | @intFromEnum(decision_.level);
}

fn unpackGeneration(word: u64) u64 {
    return word >> 8;
}

fn unpackLevel(word: u64) Level {
    return @enumFromInt(@as(u8, @truncate(word)));
}

test "cached filter refreshes reload and preserves old decisions" {
    const filter = try DynamicFilter.create(std.testing.allocator, std.testing.io, "info,http=debug");
    defer filter.destroy();
    var cache = CachedFilter.init(filter, "http.client");
    const before = cache.decision();
    try std.testing.expectEqual(Level.debug, before.level);
    try std.testing.expectEqual(filter.generation(), before.generation);
    try std.testing.expectEqualDeep(before, cache.decision());
    try std.testing.expect(cache.enabled(.debug));
    try std.testing.expect(!cache.enabled(.trace));
    try filter.reload("trace,http=off");
    const after = cache.decision();
    try std.testing.expectEqual(Level.off, after.level);
    try std.testing.expectEqual(before.generation + 1, after.generation);
    try std.testing.expect(!cache.enabled(.fatal));
    try std.testing.expect(before.enabled(.debug));
    try std.testing.expectError(error.InvalidLevel, filter.reload("http=invalid"));
    try std.testing.expectEqualDeep(after, cache.decision());
}

test "cached filter bindings isolate owners and namespace scopes" {
    const first = try DynamicFilter.create(std.testing.allocator, std.testing.io, "warn,http=trace,http.server=off");
    defer first.destroy();
    const second = try DynamicFilter.create(std.testing.allocator, std.testing.io, "info,http=err");
    defer second.destroy();
    var scope = "http.client".*;
    var first_cache = CachedFilter.init(first, &scope);
    var second_cache = CachedFilter.init(second, &scope);
    var server_cache = CachedFilter.init(first, "http.server.request");
    var boundary_cache = CachedFilter.init(first, "httpx");
    try std.testing.expect(first_cache.owner == first);
    try std.testing.expect(first_cache.scope.ptr == scope[0..].ptr);
    try std.testing.expectEqual(Level.trace, first_cache.decision().level);
    try std.testing.expectEqual(Level.err, second_cache.decision().level);
    try std.testing.expectEqual(Level.off, server_cache.decision().level);
    try std.testing.expectEqual(Level.warn, boundary_cache.decision().level);
    try first.reload("off,http=debug");
    try std.testing.expectEqual(Level.debug, first_cache.decision().level);
    try std.testing.expectEqual(Level.err, second_cache.decision().level);
    try std.testing.expectEqual(@as(u64, 1), second_cache.decision().generation);
    try std.testing.expectEqual(Level.debug, server_cache.decision().level);
    try std.testing.expectEqual(Level.off, boundary_cache.decision().level);
}

test "cached filter hits and refreshes allocate nothing" {
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const filter = try DynamicFilter.create(allocator.allocator(), std.testing.io, "info,http=debug");
    defer filter.destroy();
    var cache = CachedFilter.init(filter, "http.client");
    for (0..1000) |_| try std.testing.expect(cache.enabled(.debug));
    try filter.reload("warn,http=trace");
    for (0..1000) |_| try std.testing.expect(cache.enabled(.trace));
    try std.testing.expectEqual(@as(usize, 1), allocator.allocations);
    try std.testing.expect(!allocator.has_induced_failure);
}

test "cached filter stale refresh cannot overwrite a new generation" {
    const filter = try DynamicFilter.create(std.testing.allocator, std.testing.io, "debug");
    defer filter.destroy();
    var cache = CachedFilter.init(filter, "scope");
    const older = filter.decision("scope");
    try filter.reload("off");
    const newer = cache.decision();
    cache.publishIfCurrent(older);
    try std.testing.expectEqual(newer.generation, unpackGeneration(cache.cache_word.load(.acquire)));
    try std.testing.expectEqualDeep(newer, cache.decision());
}

test "cached filter preserves full generations beyond its packing capacity" {
    const filter = try DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    var cache = CachedFilter.init(filter, "scope");
    _ = cache.decision();
    // Tests adjust the version only while there are no concurrent calls; the
    // selected slot already contains the corresponding complete snapshot.
    filter.published.store(max_cached_generation, .seq_cst);
    const last_cached = cache.decision();
    try std.testing.expectEqual(max_cached_generation, last_cached.generation);
    try std.testing.expectEqual(max_cached_generation, unpackGeneration(cache.cache_word.load(.acquire)));
    try filter.reload("off");
    const beyond = cache.decision();
    try std.testing.expectEqual(max_cached_generation + 1, beyond.generation);
    try std.testing.expectEqual(Level.off, beyond.level);
    try std.testing.expectEqual(max_cached_generation, unpackGeneration(cache.cache_word.load(.acquire)));

    // A truncated generation of 1 would alias the original cached trace rule.
    var alias_cache = CachedFilter.init(filter, "scope");
    alias_cache.cache_word.store(pack(.{ .level = .trace, .generation = 1 }), .release);
    try filter.reload("off");
    const alias = alias_cache.decision();
    try std.testing.expectEqual(max_cached_generation + 2, alias.generation);
    try std.testing.expectEqual(Level.off, alias.level);
    try std.testing.expect(!alias_cache.enabled(.fatal));
    filter.published.store(0, .seq_cst);
    try std.testing.expectEqual(@as(u64, 0), cache.decision().generation);
    try std.testing.expectEqual(Level.off, cache.decision().level);
}

test "cached filter concurrent readers and reload never mix level and generation" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        cache: *CachedFilter,
        stop: std.atomic.Value(bool) = .init(false),
        bad: std.atomic.Value(bool) = .init(false),
        observations: std.atomic.Value(u64) = .init(0),

        fn read(context: *@This()) void {
            var previous_generation: u64 = 0;
            while (!context.stop.load(.acquire)) {
                const decision_ = context.cache.decision();
                const expected: Level = if (decision_.generation & 1 == 1) .debug else .warn;
                if (decision_.level != expected or decision_.generation < previous_generation)
                    context.bad.store(true, .release);
                previous_generation = decision_.generation;
                _ = context.observations.fetchAdd(1, .monotonic);
            }
        }
    };
    const filter = try DynamicFilter.create(std.testing.allocator, std.testing.io, "trace,http=debug");
    defer filter.destroy();
    var cache = CachedFilter.init(filter, "http.client");
    var context: Context = .{ .cache = &cache };
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
    for (0..4000) |i| try filter.reload(if (i & 1 == 0) "err,http=warn" else "trace,http=debug");
    context.stop.store(true, .release);
    for (threads[0..started]) |thread| thread.join();
    started = 0;
    try std.testing.expect(!context.bad.load(.acquire));
    try std.testing.expect(context.observations.load(.monotonic) > 0);
    try std.testing.expectEqual(@as(u64, 4001), cache.decision().generation);
    try std.testing.expectEqual(Level.debug, cache.decision().level);
}
