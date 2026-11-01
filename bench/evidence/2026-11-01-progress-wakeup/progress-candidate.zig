//! Progress publication shared by blocked producers and flush cuts. The two
//! seq_cst handshake pairs make conditional waking safe without a mutex.
const std = @import("std");
const Atomic = std.atomic.Value;

pub fn notify(epoch: *Atomic(u32), waiters: *Atomic(usize), io: std.Io) void {
    // If registration follows this load in the seq_cst order, its subsequent
    // epoch check sees the increment and cannot park on the old epoch.
    _ = epoch.fetchAdd(1, .seq_cst);
    if (waiters.load(.seq_cst) != 0) io.futexWake(u32, &epoch.raw, std.math.maxInt(u32));
}

pub fn wait(epoch: *Atomic(u32), waiters: *Atomic(usize), io: std.Io, observed: u32) void {
    _ = waiters.fetchAdd(1, .seq_cst);
    defer _ = waiters.fetchSub(1, .seq_cst);
    // A notification between this check and the syscall is covered by futex's
    // expected-value check. Spurious returns simply let the caller retry its
    // journal/cut/error predicate. Registration includes that syscall window.
    if (epoch.load(.seq_cst) == observed) io.futexWaitUncancelable(u32, &epoch.raw, observed);
}

test "progress changed before registration skips wait and no waiter skips wake" {
    const Observer = struct {
        waits: usize = 0,
        wakes: usize = 0,
        fn wait(raw: ?*anyopaque, _: *const u32, _: u32) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.waits += 1;
        }
        fn wake(raw: ?*anyopaque, _: *const u32, _: u32) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.wakes += 1;
        }
    };
    var observer: Observer = .{};
    var vtable = std.testing.io.vtable.*;
    vtable.futexWaitUncancelable = Observer.wait;
    vtable.futexWake = Observer.wake;
    const io: std.Io = .{ .userdata = &observer, .vtable = &vtable };
    var epoch: Atomic(u32) = .init(std.math.maxInt(u32));
    var waiters: Atomic(usize) = .init(0);
    notify(&epoch, &waiters, io);
    try std.testing.expectEqual(@as(u32, 0), epoch.load(.seq_cst));
    wait(&epoch, &waiters, io, std.math.maxInt(u32));
    try std.testing.expectEqual(@as(usize, 0), observer.waits);
    try std.testing.expectEqual(@as(usize, 0), observer.wakes);
    // A spurious futex return still removes its waiter registration.
    wait(&epoch, &waiters, io, 0);
    try std.testing.expectEqual(@as(usize, 1), observer.waits);
    try std.testing.expectEqual(@as(usize, 0), waiters.load(.seq_cst));
}

test "progress notification in the syscall window cannot strand a waiter" {
    const Context = struct {
        epoch: Atomic(u32) = .init(0),
        waiters: Atomic(usize) = .init(0),
        notifications: usize = 0,
        fn entering(raw: ?*anyopaque, ptr: *const u32, expected: u32) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            std.debug.assert(self.waiters.load(.seq_cst) == 1);
            var vtable = std.testing.io.vtable.*;
            vtable.futexWake = waking;
            // Publish after the caller's epoch check, before the real futex
            // registration. The kernel's value comparison must reject sleep.
            notify(&self.epoch, &self.waiters, .{ .userdata = self, .vtable = &vtable });
            std.testing.io.vtable.futexWaitUncancelable(std.testing.io.userdata, ptr, expected);
        }
        fn waking(raw: ?*anyopaque, _: *const u32, _: u32) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.notifications += 1;
        }
    };
    var context: Context = .{};
    var vtable = std.testing.io.vtable.*;
    vtable.futexWaitUncancelable = Context.entering;
    wait(&context.epoch, &context.waiters, .{ .userdata = &context, .vtable = &vtable }, 0);
    try std.testing.expectEqual(@as(usize, 1), context.notifications);
    try std.testing.expectEqual(@as(u32, 1), context.epoch.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 0), context.waiters.load(.seq_cst));
}

test "one progress publication releases all registered waiters across repeated epochs" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const Context = struct {
        epoch: Atomic(u32) = .init(0),
        waiters: Atomic(usize) = .init(0),
        entered: Atomic(usize) = .init(0),
        ready: std.Io.Event = .unset,
        done: Atomic(usize) = .init(0),
        fn observedWait(raw: ?*anyopaque, ptr: *const u32, expected: u32) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (self.entered.fetchAdd(1, .acq_rel) + 1 == 4) self.ready.set(std.testing.io);
            std.testing.io.vtable.futexWaitUncancelable(std.testing.io.userdata, ptr, expected);
        }
        fn run(self: *@This()) void {
            var vtable = std.testing.io.vtable.*;
            vtable.futexWaitUncancelable = observedWait;
            // Each context has one initial epoch; cleanup notification also
            // releases threads that have not reached registration yet.
            wait(&self.epoch, &self.waiters, .{ .userdata = self, .vtable = &vtable }, 0);
            _ = self.done.fetchAdd(1, .release);
        }
    };
    for (0..32) |_| {
        var context: Context = .{};
        var threads: [4]?std.Thread = @splat(null);
        defer {
            notify(&context.epoch, &context.waiters, std.testing.io);
            for (threads) |thread| if (thread) |handle| handle.join();
        }
        for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Context.run, .{&context});
        try context.ready.waitTimeout(std.testing.io, .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(5) } });
        notify(&context.epoch, &context.waiters, std.testing.io);
        for (&threads) |*thread| {
            thread.*.?.join();
            thread.* = null;
        }
        try std.testing.expectEqual(@as(usize, 4), context.done.load(.acquire));
        try std.testing.expectEqual(@as(usize, 0), context.waiters.load(.seq_cst));
    }
}
