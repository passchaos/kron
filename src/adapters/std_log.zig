//! Application-owned std.log binding. Set root std_options.logFn to
//! Bridge(Runtime).logFn and set std_options.log_level to .debug when runtime
//! filtering must control all four standard levels.
//!
//! Bind/unbind belong to application lifecycle code. A bound owner must stay
//! at a stable address until unbind returns; unbind drains current log calls.
//! Do not call bind/unbind from a formatter, sink or error hook invoked by log.
//! Standard formatting uses an explicit 16 KiB preencoded message budget, so
//! custom {f} formatters run on the producer. Their allocation behavior is the
//! formatter's responsibility. Unbound and recursive calls return silently.
const std = @import("std");
const Level = @import("../core/level.zig").Level;
const Atomic = std.atomic.Value;

pub const max_message_bytes = 16 * 1024;
pub const BindingError = error{AlreadyBound};
pub const Statistics = struct {
    accepted: u64,
    unbound: u64,
    oversize: u64,
    errors: u64,
    recursive: u64,
};

pub fn Bridge(comptime Owner: type) type {
    return struct {
        var binding: Atomic(?*Owner) = .init(null);
        var readers: Atomic(usize) = .init(0);
        var lifecycle_lock: Atomic(bool) = .init(false);
        var accepted: Atomic(u64) = .init(0);
        var unbound: Atomic(u64) = .init(0);
        var oversize: Atomic(u64) = .init(0);
        var errors: Atomic(u64) = .init(0);
        var recursive: Atomic(u64) = .init(0);
        threadlocal var inside_log: bool = false;

        /// Explicit initialization is binding; a second bind to the same
        /// owner is harmless. A different owner requires unbind first.
        pub fn init(owner: *Owner) BindingError!void {
            try bind(owner);
        }

        pub fn bind(owner: *Owner) BindingError!void {
            lockLifecycle();
            defer lifecycle_lock.store(false, .release);
            if (binding.load(.seq_cst)) |current| {
                if (current == owner) return;
                return error.AlreadyBound;
            }
            binding.store(owner, .seq_cst);
        }

        /// Removes the binding before waiting. New calls cannot borrow the
        /// detached owner; after return it may be destroyed or replaced.
        pub fn unbind() void {
            lockLifecycle();
            defer lifecycle_lock.store(false, .release);
            _ = binding.swap(null, .seq_cst);
            while (readers.load(.seq_cst) != 0) yieldThread();
        }

        /// Detach only this owner, so cleanup of a former binding cannot
        /// remove a newer application's binding. Drains calls borrowing owner.
        pub fn unbindOwner(owner: *Owner) void {
            lockLifecycle();
            defer lifecycle_lock.store(false, .release);
            if (binding.load(.seq_cst) != owner) return;
            _ = binding.swap(null, .seq_cst);
            while (readers.load(.seq_cst) != 0) yieldThread();
        }

        /// Cumulative adapter counters survive bind/unbind. Runtime health
        /// independently tracks admission, capture and delivery outcomes.
        pub fn statistics() Statistics {
            return .{
                .accepted = accepted.load(.monotonic),
                .unbound = unbound.load(.monotonic),
                .oversize = oversize.load(.monotonic),
                .errors = errors.load(.monotonic),
                .recursive = recursive.load(.monotonic),
            };
        }

        pub fn logFn(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime fmt: []const u8, args: anytype) void {
            if (inside_log) {
                _ = recursive.fetchAdd(1, .monotonic);
                return;
            }
            const owner = acquire() orelse {
                _ = unbound.fetchAdd(1, .monotonic);
                return;
            };
            defer release();
            inside_log = true;
            defer inside_log = false;
            var buffer: [max_message_bytes]u8 = undefined;
            const result = owner.scoped(@tagName(scope)).tryLogfPreencoded(Level.fromStd(level), &buffer, fmt, args, .{}) catch |failure| {
                if (failure == error.NoSpaceLeft) {
                    _ = oversize.fetchAdd(1, .monotonic);
                } else {
                    _ = errors.fetchAdd(1, .monotonic);
                }
                owner.reportError(failure);
                return;
            };
            if (result == .accepted) _ = accepted.fetchAdd(1, .monotonic);
        }

        fn acquire() ?*Owner {
            // The first read is only a null fast path, never a dereference.
            // Sequential consistency orders reader registration before the
            // second pointer read against unbind's exchange and drain check.
            if (binding.load(.seq_cst) == null) return null;
            _ = readers.fetchAdd(1, .seq_cst);
            return binding.load(.seq_cst) orelse {
                release();
                return null;
            };
        }

        fn release() void {
            const previous = readers.fetchSub(1, .seq_cst);
            std.debug.assert(previous != 0);
        }

        fn lockLifecycle() void {
            while (lifecycle_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) yieldThread();
        }

        fn yieldThread() void {
            std.atomic.spinLoopHint();
            std.Thread.yield() catch {};
        }
    };
}

const TestOwner = struct {
    const Logger = @import("../core/logger.zig");
    const Event = @import("../core/event.zig").Event;
    const Pause = struct { entered: Atomic(bool) = .init(false), release_call: Atomic(bool) = .init(false) };

    io: std.Io = std.testing.io,
    count: Atomic(usize) = .init(0),
    failures: Atomic(usize) = .init(0),
    captures: Atomic(usize) = .init(0),
    level: Level = .off,
    scope: []const u8 = "",
    message: [max_message_bytes]u8 = undefined,
    message_len: usize = 0,
    pause: ?*Pause = null,
    pause_in_hook: bool = false,
    fail: bool = false,
    recursive_hook: bool = false,

    pub fn scoped(self: *TestOwner, scope: []const u8) Logger.Logger(TestOwner, .trace) {
        return .init(self, scope);
    }

    pub fn enabled(_: *TestOwner, _: Level, _: []const u8) bool {
        return true;
    }

    pub fn begin(_: *TestOwner, _: Level, _: []const u8) Logger.BeginResult {
        return .{ .ready = .{ .route_mask = 1, .config_generation = 1 } };
    }

    pub fn end(_: *TestOwner) void {}

    pub fn nowNs(_: *TestOwner) i64 {
        return 123;
    }

    pub fn submit(self: *TestOwner, _: Logger.Admission, event: Event) anyerror!Logger.EmitResult {
        if (!self.pause_in_hook) self.waitPause();
        _ = self.count.fetchAdd(1, .monotonic);
        if (self.fail) return error.SinkFailed;
        self.level = event.level;
        self.scope = event.scope;
        @memcpy(self.message[0..event.message.len], event.message);
        self.message_len = event.message.len;
        return .accepted;
    }

    pub fn captureFailed(self: *TestOwner, _: anyerror) void {
        _ = self.captures.fetchAdd(1, .monotonic);
    }

    pub fn reportError(self: *TestOwner, _: anyerror) void {
        _ = self.failures.fetchAdd(1, .monotonic);
        if (self.pause_in_hook) self.waitPause();
        if (self.recursive_hook) Bridge(TestOwner).logFn(.err, .hook, "recursive", .{});
    }

    fn waitPause(self: *TestOwner) void {
        if (self.pause) |pause| {
            pause.entered.store(true, .release);
            while (!pause.release_call.load(.acquire)) std.atomic.spinLoopHint();
        }
    }
};

test "standard level mapping, scopes, unbound calls and explicit rebinding" {
    const B = Bridge(TestOwner);
    B.unbind();
    const before = B.statistics();
    B.logFn(.info, .default, "unbound", .{});
    try std.testing.expectEqual(before.unbound + 1, B.statistics().unbound);
    var first: TestOwner = .{};
    var second: TestOwner = .{};
    try B.init(&first);
    defer B.unbind();
    try B.bind(&first);
    try std.testing.expectError(error.AlreadyBound, B.bind(&second));
    inline for ([4]std.log.Level{ .debug, .info, .warn, .err }, [4]Level{ .debug, .info, .warn, .err }) |standard, expected| {
        B.logFn(standard, .http, "value {d}", .{@as(u16, 42)});
        try std.testing.expectEqual(expected, first.level);
        try std.testing.expectEqualStrings("http", first.scope);
        try std.testing.expectEqualStrings("value 42", first.message[0..first.message_len]);
    }
    B.unbind();
    try B.bind(&second);
    B.logFn(.info, .default, "replacement", .{});
    try std.testing.expectEqual(@as(usize, 4), first.count.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), second.count.load(.monotonic));
}

test "standard custom formatting, oversize reporting and error hook recursion" {
    const B = Bridge(TestOwner);
    const Custom = struct {
        pub fn format(_: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.writeAll("custom");
        }
    };
    var owner: TestOwner = .{ .recursive_hook = true };
    try B.bind(&owner);
    defer B.unbind();
    B.logFn(.info, .default, "{f}", .{Custom{}});
    try std.testing.expectEqualStrings("custom", owner.message[0..owner.message_len]);
    const before = B.statistics();
    B.logFn(.warn, .default, "{s}", .{"x" ** (max_message_bytes + 1)});
    try std.testing.expectEqual(before.oversize + 1, B.statistics().oversize);
    try std.testing.expectEqual(before.recursive + 1, B.statistics().recursive);
    try std.testing.expectEqual(@as(usize, 1), owner.captures.load(.monotonic));
    owner.fail = true;
    B.logFn(.err, .default, "failure", .{});
    try std.testing.expectEqual(before.errors + 1, B.statistics().errors);
    try std.testing.expectEqual(before.recursive + 2, B.statistics().recursive);
}

test "unbind drains concurrent submission and error hook before owner destruction" {
    const B = Bridge(TestOwner);
    const Harness = struct {
        fn emit() void {
            B.logFn(.info, .worker, "in flight", .{});
        }
        fn detach(finished: *Atomic(bool)) void {
            B.unbind();
            finished.store(true, .release);
        }
    };
    for ([2]bool{ false, true }) |pause_in_hook| {
        var pause: TestOwner.Pause = .{};
        var owner: TestOwner = .{ .pause = &pause, .pause_in_hook = pause_in_hook, .fail = pause_in_hook };
        try B.bind(&owner);
        defer B.unbind();
        const emitter = try std.Thread.spawn(.{}, Harness.emit, .{});
        defer emitter.join();
        defer pause.release_call.store(true, .release);
        while (!pause.entered.load(.acquire)) std.atomic.spinLoopHint();
        var finished: Atomic(bool) = .init(false);
        const detacher = try std.Thread.spawn(.{}, Harness.detach, .{&finished});
        defer {
            pause.release_call.store(true, .release);
            detacher.join();
        }
        while (B.binding.load(.seq_cst) != null) std.atomic.spinLoopHint();
        try std.testing.expect(!finished.load(.acquire));
        try std.testing.expectEqual(@as(usize, 1), B.readers.load(.seq_cst));
        // New callers see the detached binding and cannot prolong owner lifetime.
        B.logFn(.info, .worker, "after detach", .{});
        pause.release_call.store(true, .release);
        while (!finished.load(.acquire)) std.atomic.spinLoopHint();
        try std.testing.expectEqual(@as(usize, 1), owner.count.load(.monotonic));
        try std.testing.expectEqual(@as(usize, 0), B.readers.load(.seq_cst));
    }
}
