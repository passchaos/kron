const std = @import("std");
const Level = @import("../core/level.zig").Level;
const filter_module = @import("filter.zig");
const Filter = filter_module.Filter;
pub const TestingAudit = if (@import("builtin").is_test) struct {
    pub var reader_rmw: std.atomic.Value(u64) = .init(0);
} else struct {};
pub const ParseDiagnostic = filter_module.ParseDiagnostic;
pub const ParseError = filter_module.ParseError;

pub const Decision = struct {
    level: Level,
    generation: u64,

    pub fn enabled(self: Decision, level: Level) bool {
        return filter_module.levelEnabled(level, self.level);
    }
};

pub const BoundDecision = struct {
    decision: Decision,
    configuration_generation: u64,
};
pub const BoundFilter = struct {
    filter: Filter,
    generation: u64,
    configuration_generation: u64,
};

/// Filter snapshots live in two fixed slots for the lifetime of this object.
/// A reader registers in a slot, then validates the publication generation
/// before touching non-atomic data. All registration/publication operations
/// are seq_cst: a reader that validates an old generation must be visible to
/// the writer before that slot can be reused. A late registration only retries
/// and never touches the snapshot, so no raw-pointer refcount race exists.
///
/// Owners must join concurrent calls before destroy, as with other owned APIs.
pub const DynamicFilter = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    writer_mutex: std.Io.Mutex = .init,
    published: std.atomic.Value(u64) = .init(1),
    slots: [2]Slot,

    const Slot = struct {
        readers: std.atomic.Value(u64) = .init(0),
        filter: Filter,
        configuration_generation: u64 = 0,
    };

    pub fn create(allocator: std.mem.Allocator, io: std.Io, initial_spec: []const u8) (std.mem.Allocator.Error || ParseError)!*DynamicFilter {
        const initial = try Filter.parse(initial_spec);
        const self = try allocator.create(DynamicFilter);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .slots = .{ .{ .filter = initial }, .{ .filter = initial } },
        };
        return self;
    }

    pub fn createBound(allocator: std.mem.Allocator, io: std.Io, initial_spec: []const u8, configuration_generation: u64) (std.mem.Allocator.Error || ParseError)!*DynamicFilter {
        const self = try create(allocator, io, initial_spec);
        for (&self.slots) |*slot| slot.configuration_generation = configuration_generation;
        return self;
    }

    /// Runtime writers serialize route and filter transactions externally.
    /// The supplied filter is already validated, so this cannot fail after a
    /// successful full configuration publication.
    pub fn publishBound(self: *DynamicFilter, filter: Filter, configuration_generation: u64) void {
        self.writer_mutex.lockUncancelable(self.io);
        defer self.writer_mutex.unlock(self.io);
        self.publishWithBinding(filter, configuration_generation);
    }

    pub fn destroy(self: *DynamicFilter) void {
        const allocator = self.allocator;
        std.debug.assert(self.slots[0].readers.load(.seq_cst) == 0);
        std.debug.assert(self.slots[1].readers.load(.seq_cst) == 0);
        allocator.destroy(self);
    }

    pub fn reload(self: *DynamicFilter, spec: []const u8) ParseError!void {
        const replacement = try Filter.parse(spec);
        self.writer_mutex.lockUncancelable(self.io);
        defer self.writer_mutex.unlock(self.io);
        self.publish(replacement);
    }

    pub fn reloadDetailed(self: *DynamicFilter, spec: []const u8, diagnostic: *?ParseDiagnostic) ParseError!void {
        const replacement = try Filter.parseDetailed(spec, diagnostic);
        self.writer_mutex.lockUncancelable(self.io);
        defer self.writer_mutex.unlock(self.io);
        self.publish(replacement);
    }

    /// Changes the default threshold while retaining all scope overrides.
    pub fn setLevel(self: *DynamicFilter, level: Level) void {
        self.writer_mutex.lockUncancelable(self.io);
        defer self.writer_mutex.unlock(self.io);
        const current = self.published.load(.seq_cst);
        var replacement = self.slots[@intCast(current & 1)].filter;
        replacement.default_level = level;
        self.publish(replacement);
    }

    pub fn decision(self: *DynamicFilter, scope: []const u8) Decision {
        return self.boundDecision(scope).decision;
    }

    pub fn boundDecision(self: *DynamicFilter, scope: []const u8) BoundDecision {
        if (@import("builtin").is_test) _ = TestingAudit.reader_rmw.fetchAdd(2, .monotonic);
        while (true) {
            const version = self.published.load(.seq_cst);
            const slot = &self.slots[@intCast(version & 1)];
            _ = slot.readers.fetchAdd(1, .seq_cst);
            if (self.published.load(.seq_cst) == version) {
                const level = slot.filter.threshold(scope);
                const binding = slot.configuration_generation;
                _ = slot.readers.fetchSub(1, .seq_cst);
                return .{ .decision = .{ .level = level, .generation = version }, .configuration_generation = binding };
            }
            _ = slot.readers.fetchSub(1, .seq_cst);
            std.atomic.spinLoopHint();
        }
    }

    /// Cold owning copy used to inherit the effective filter in a route
    /// transaction. Filter offsets keep the returned copy independent.
    pub fn boundFilter(self: *DynamicFilter) BoundFilter {
        while (true) {
            const version = self.published.load(.seq_cst);
            const slot = &self.slots[@intCast(version & 1)];
            _ = slot.readers.fetchAdd(1, .seq_cst);
            if (self.published.load(.seq_cst) == version) {
                const result: BoundFilter = .{ .filter = slot.filter, .generation = version, .configuration_generation = slot.configuration_generation };
                _ = slot.readers.fetchSub(1, .seq_cst);
                return result;
            }
            _ = slot.readers.fetchSub(1, .seq_cst);
        }
    }

    pub fn enabled(self: *DynamicFilter, level: Level, scope: []const u8) bool {
        return self.decision(scope).enabled(level);
    }

    /// Publication version for caller-owned decision caches. This does not
    /// acquire a snapshot; use decision to read its corresponding threshold.
    pub fn generation(self: *const DynamicFilter) u64 {
        return self.published.load(.seq_cst);
    }

    fn publish(self: *DynamicFilter, replacement: Filter) void {
        self.publishWithBinding(replacement, 0);
    }

    fn publishWithBinding(self: *DynamicFilter, replacement: Filter, configuration_generation: u64) void {
        const version = self.published.load(.seq_cst) +% 1;
        const slot = &self.slots[@intCast(version & 1)];
        while (slot.readers.load(.seq_cst) != 0) std.atomic.spinLoopHint();
        slot.filter = replacement;
        slot.configuration_generation = configuration_generation;
        self.published.store(version, .seq_cst);
    }
};

test "failed reload is atomic and setLevel retains overrides" {
    const filter = try DynamicFilter.create(std.testing.allocator, std.testing.io, "info,http=debug");
    defer filter.destroy();
    const before = filter.decision("http.client");
    var diagnostic: ?ParseDiagnostic = null;
    try std.testing.expectError(error.InvalidLevel, filter.reloadDetailed("trace,http=garbage", &diagnostic));
    try std.testing.expectEqual(@as(usize, 11), diagnostic.?.offset);
    try std.testing.expectEqualDeep(before, filter.decision("http.client"));
    try std.testing.expectEqual(Level.info, filter.decision("other").level);
    filter.setLevel(.err);
    try std.testing.expectEqual(Level.err, filter.decision("other").level);
    try std.testing.expectEqual(Level.debug, filter.decision("http.client").level);
    try std.testing.expectEqual(before.generation + 1, filter.decision("other").generation);
    try filter.reload("off,http=trace");
    try std.testing.expect(filter.enabled(.trace, "http"));
    try std.testing.expect(!filter.enabled(.fatal, "other"));
    // A captured decision retains its generation and threshold after reload.
    try std.testing.expect(before.enabled(.debug));
}

test "runtime filter instances never share decisions" {
    const first = try DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer first.destroy();
    const second = try DynamicFilter.create(std.testing.allocator, std.testing.io, "off");
    defer second.destroy();
    try first.reload("debug");
    try std.testing.expect(first.enabled(.debug, "same.scope"));
    try std.testing.expect(!second.enabled(.fatal, "same.scope"));
    try std.testing.expectEqual(@as(u64, 1), second.decision("same.scope").generation);
}

test "enabled and policy updates allocate nothing after creation" {
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const filter = try DynamicFilter.create(allocator.allocator(), std.testing.io, "info,http=debug");
    defer filter.destroy();
    for (0..1000) |_| {
        try std.testing.expect(filter.enabled(.debug, "http.child"));
        try std.testing.expect(!filter.enabled(.trace, "http.child"));
    }
    try filter.reload("warn,http=trace");
    filter.setLevel(.err);
    try std.testing.expect(filter.enabled(.trace, "http"));
    try std.testing.expectEqual(@as(usize, 1), allocator.allocations);
    try std.testing.expect(!allocator.has_induced_failure);
}

test "snapshot reuse waits for a registered reader" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        filter: *DynamicFilter,
        entered: std.atomic.Value(bool) = .init(false),
        done: std.atomic.Value(bool) = .init(false),

        fn write(context: *@This()) void {
            context.filter.writer_mutex.lockUncancelable(context.filter.io);
            defer context.filter.writer_mutex.unlock(context.filter.io);
            context.entered.store(true, .release);
            context.filter.publish(Filter.parse("debug") catch unreachable);
            context.done.store(true, .release);
        }
    };
    const filter = try DynamicFilter.create(std.testing.allocator, std.testing.io, "trace");
    defer filter.destroy();
    // Hold generation 1 as a validated reader while generation 2 is published.
    const pinned = &filter.slots[1];
    _ = pinned.readers.fetchAdd(1, .seq_cst);
    var is_pinned = true;
    defer if (is_pinned) {
        _ = pinned.readers.fetchSub(1, .seq_cst);
    };
    try filter.reload("warn");
    var context: Context = .{ .filter = filter };
    const thread = try std.Thread.spawn(.{}, Context.write, .{&context});
    // A failed assertion must still release the pin before joining the writer.
    defer {
        if (is_pinned) {
            _ = pinned.readers.fetchSub(1, .seq_cst);
            is_pinned = false;
        }
        thread.join();
    }
    while (!context.entered.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expect(!context.done.load(.acquire));
    try std.testing.expectEqual(Level.trace, pinned.filter.threshold("any"));
    try std.testing.expectEqual(Level.warn, filter.decision("any").level);
    _ = pinned.readers.fetchSub(1, .seq_cst);
    is_pinned = false;
    while (!context.done.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expectEqual(Level.debug, filter.decision("any").level);
}

test "concurrent writers serialize configuration transactions" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        filter: *DynamicFilter,

        fn write(context: *@This()) void {
            for (0..500) |i| {
                if (i & 1 == 0) {
                    context.filter.reload("warn,http=trace") catch unreachable;
                } else context.filter.setLevel(.debug);
            }
        }
    };
    const filter = try DynamicFilter.create(std.testing.allocator, std.testing.io, "info");
    defer filter.destroy();
    var context: Context = .{ .filter = filter };
    {
        const first = try std.Thread.spawn(.{}, Context.write, .{&context});
        defer first.join();
        const second = try std.Thread.spawn(.{}, Context.write, .{&context});
        defer second.join();
    }
    try std.testing.expectEqual(@as(u64, 1001), filter.decision("http").generation);
    try std.testing.expectEqual(Level.trace, filter.decision("http").level);
}

test "concurrent reload returns a threshold from its exact generation" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        filter: *DynamicFilter,
        stop: std.atomic.Value(bool) = .init(false),
        bad: std.atomic.Value(bool) = .init(false),
        observations: std.atomic.Value(u64) = .init(0),

        fn read(context: *@This()) void {
            while (!context.stop.load(.acquire)) {
                const decision_ = context.filter.decision("http.child");
                const expected: Level = if (decision_.generation & 1 == 1) .debug else .warn;
                if (decision_.level != expected) context.bad.store(true, .release);
                _ = context.observations.fetchAdd(1, .monotonic);
            }
        }
    };
    const filter = try DynamicFilter.create(std.testing.allocator, std.testing.io, "trace,http=debug");
    defer filter.destroy();
    var context: Context = .{ .filter = filter };
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
    for (0..3000) |i| {
        try filter.reload(if (i & 1 == 0) "err,http=warn" else "trace,http=debug");
    }
    context.stop.store(true, .release);
    for (threads[0..started]) |thread| thread.join();
    started = 0;
    try std.testing.expect(!context.bad.load(.acquire));
    try std.testing.expect(context.observations.load(.monotonic) > 0);
}
