//! A fixed-capacity control executor. Timed callers never lend stack memory
//! to blocking sink operations. A timeout detaches the caller; the operation
//! continues on the owned thread and retains all referenced resources.
const std = @import("std");
const builtin = @import("builtin");
const Atomic = std.atomic.Value;

pub const Deadline = struct {
    timestamp: std.Io.Clock.Timestamp,

    pub fn after(io: std.Io, nanoseconds: u64) Deadline {
        const now = std.Io.Clock.awake.now(io).nanoseconds;
        return .{ .timestamp = .{ .clock = .awake, .raw = .{ .nanoseconds = now +| nanoseconds } } };
    }

    pub fn fromTimestamp(timestamp: std.Io.Clock.Timestamp) error{InvalidDeadlineClock}!Deadline {
        if (timestamp.clock != .awake and timestamp.clock != .boot) return error.InvalidDeadlineClock;
        return .{ .timestamp = timestamp };
    }

    pub fn expired(self: Deadline, io: std.Io) bool {
        return self.timestamp.clock.now(io).nanoseconds >= self.timestamp.raw.nanoseconds;
    }
};

pub const Lifetime = struct {
    context: *anyopaque,
    retain: *const fn (*anyopaque) void,
    release: *const fn (*anyopaque) void,
};

pub const Task = union(enum) {
    flush: struct {
        route_mask: u64,
        boundary: u8,
        route_generation: u64 = 0,
        route_fingerprint: u64 = 0,
        all_versions: bool = false,
        lifetime: ?Lifetime = null,
    },
    shutdown,

    fn retainResources(self: Task) void {
        if (self == .flush) if (self.flush.lifetime) |lease| lease.retain(lease.context);
    }

    fn releaseResources(self: Task) void {
        if (self == .flush) if (self.flush.lifetime) |lease| lease.release(lease.context);
    }
};

pub const Callback = *const fn (*anyopaque, Task) anyerror!void;
const State = enum(u32) { idle, reserved, queued, queued_detached, running, running_detached, done };

pub const Status = struct {
    available: bool = true,
    busy: bool,
    detached: bool,
    completed_operations: u64,
    timed_out_operations: u64,
    last_error: ?anyerror,
};

pub const Control = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    context: *anyopaque,
    callback: Callback,
    state: Atomic(State) = .init(.idle),
    epoch: Atomic(u32) = .init(0),
    stopping: Atomic(bool) = .init(false),
    worker_id: Atomic(std.Thread.Id) = .init(0),
    task: Task = undefined,
    result: ?anyerror = null,
    last_error: Atomic(u16) = .init(0),
    completed: Atomic(u64) = .init(0),
    timed_out: Atomic(u64) = .init(0),
    thread: std.Thread,

    pub fn create(allocator: std.mem.Allocator, io: std.Io, context: *anyopaque, callback: Callback) !*Control {
        if (builtin.single_threaded) return error.ThreadsUnavailable;
        const self = try allocator.create(Control);
        errdefer allocator.destroy(self);
        self.* = .{ .allocator = allocator, .io = io, .context = context, .callback = callback, .thread = undefined };
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }

    pub fn isWorker(self: *const Control) bool {
        return self.worker_id.load(.acquire) == std.Thread.getCurrentId();
    }

    /// One slot is shared by control callers. Waiting for a prior operation is
    /// included in the deadline. Timeout before reservation starts no task.
    pub fn invoke(self: *Control, task: Task, deadline: Deadline) !void {
        if (self.isWorker()) return error.ControlReentrant;
        while (true) {
            const epoch = self.epoch.load(.acquire);
            if (self.stopping.load(.acquire)) return error.Closed;
            if (deadline.expired(self.io)) return error.Timeout;
            if (self.state.cmpxchgStrong(.idle, .reserved, .acq_rel, .acquire) == null) break;
            self.wait(epoch, deadline) catch |err| {
                if (err == error.Timeout) _ = self.timed_out.fetchAdd(1, .monotonic);
                return err;
            };
        }
        self.task = task;
        self.result = null;
        // The submitting caller still holds its view while this retain runs.
        // A published task then owns its lease independently of caller timeout.
        task.retainResources();
        self.state.store(.queued, .release);
        self.wake();
        // All exits after publication either acknowledge done or detach the
        // caller. No timeout/cancellation can leave an owned slot abandoned.
        var owns = true;
        defer if (owns) self.detach();
        while (true) {
            const epoch = self.epoch.load(.acquire);
            if (self.state.load(.acquire) == .done) {
                const result = self.result;
                self.state.store(.idle, .release);
                owns = false;
                self.wake();
                if (result) |err| return err;
                return;
            }
            if (deadline.expired(self.io)) {
                _ = self.timed_out.fetchAdd(1, .monotonic);
                return error.Timeout;
            }
            self.wait(epoch, deadline) catch |err| {
                if (err == error.Timeout) _ = self.timed_out.fetchAdd(1, .monotonic);
                return err;
            };
        }
    }

    fn wait(self: *Control, epoch: u32, deadline: Deadline) !void {
        try self.io.futexWaitTimeout(u32, &self.epoch.raw, epoch, .{ .deadline = deadline.timestamp });
    }

    fn wake(self: *Control) void {
        _ = self.epoch.fetchAdd(1, .release);
        self.io.futexWake(u32, &self.epoch.raw, std.math.maxInt(u32));
    }

    fn detach(self: *Control) void {
        var state = self.state.load(.acquire);
        while (true) {
            const replacement: State = switch (state) {
                .queued => .queued_detached,
                .running => .running_detached,
                .done => .idle,
                else => unreachable,
            };
            if (self.state.cmpxchgWeak(state, replacement, .acq_rel, .acquire)) |actual| {
                state = actual;
            } else {
                self.wake();
                return;
            }
        }
    }

    fn run(self: *Control) void {
        self.worker_id.store(std.Thread.getCurrentId(), .release);
        defer self.worker_id.store(0, .release);
        while (true) {
            const epoch = self.epoch.load(.acquire);
            var state = self.state.load(.acquire);
            if (state == .queued or state == .queued_detached) {
                const running: State = if (state == .queued) .running else .running_detached;
                if (self.state.cmpxchgStrong(state, running, .acq_rel, .acquire) != null) continue;
                const task = self.task;
                self.result = if (self.callback(self.context, task)) |_| null else |err| err;
                task.releaseResources();
                self.last_error.store(if (self.result) |err| @intFromError(err) else 0, .release);
                _ = self.completed.fetchAdd(1, .monotonic);
                state = self.state.load(.acquire);
                while (true) {
                    const finished: State = if (state == .running_detached) .idle else .done;
                    if (self.state.cmpxchgWeak(state, finished, .release, .acquire)) |actual| {
                        state = actual;
                    } else break;
                }
                self.wake();
                continue;
            }
            if (self.stopping.load(.acquire) and (state == .idle or state == .done)) return;
            self.io.futexWaitUncancelable(u32, &self.epoch.raw, epoch);
        }
    }

    pub fn status(self: *const Control) Status {
        const state = self.state.load(.acquire);
        const err = self.last_error.load(.acquire);
        return .{
            .busy = state != .idle and state != .done,
            .detached = state == .queued_detached or state == .running_detached,
            .completed_operations = self.completed.load(.monotonic),
            .timed_out_operations = self.timed_out.load(.monotonic),
            .last_error = if (err == 0) null else @errorFromInt(err),
        };
    }

    /// All invoke callers must have returned. A detached operation is joined,
    /// not canceled; its buffers and callback context remain owned until then.
    pub fn destroy(self: *Control) void {
        std.debug.assert(!self.isWorker());
        self.stopping.store(true, .release);
        self.wake();
        self.thread.join();
        self.allocator.destroy(self);
    }
};

test "deadline rejects wall clocks and zero duration expires" {
    try std.testing.expectError(error.InvalidDeadlineClock, Deadline.fromTimestamp(.now(std.testing.io, .real)));
    try std.testing.expect(Deadline.after(std.testing.io, 0).expired(std.testing.io));
}

test "timed control detaches safely and next caller observes completion" {
    const Context = struct {
        io: std.Io,
        entered: std.Io.Event = .unset,
        release: std.Io.Event = .unset,
        calls: usize = 0,
        fn callback(context: *anyopaque, _: Task) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.calls += 1;
            if (self.calls == 1) {
                self.entered.set(self.io);
                self.release.waitUncancelable(self.io);
            }
        }
    };
    var context: Context = .{ .io = std.testing.io };
    const control = try Control.create(std.testing.allocator, context.io, &context, Context.callback);
    defer control.destroy();
    try std.testing.expectError(error.Timeout, control.invoke(.shutdown, Deadline.after(context.io, 10 * std.time.ns_per_ms)));
    context.entered.waitUncancelable(context.io);
    try std.testing.expect(control.status().detached);
    try std.testing.expectError(error.Timeout, control.invoke(.shutdown, Deadline.after(context.io, 0)));
    context.release.set(context.io);
    try control.invoke(.shutdown, Deadline.after(context.io, std.time.ns_per_s));
    try std.testing.expectEqual(@as(usize, 2), context.calls);
    try std.testing.expectEqual(@as(u64, 2), control.status().completed_operations);
}

test "completed callback failures remain inspectable and do not strand the mailbox" {
    const CallbackContext = struct {
        fn callback(_: *anyopaque, _: Task) !void {
            return error.InjectedControlFailure;
        }
    };
    var context: u8 = 0;
    const control = try Control.create(std.testing.allocator, std.testing.io, &context, CallbackContext.callback);
    defer control.destroy();
    try std.testing.expectError(error.InjectedControlFailure, control.invoke(.shutdown, Deadline.after(std.testing.io, std.time.ns_per_s)));
    try std.testing.expectEqual(error.InjectedControlFailure, control.status().last_error.?);
    try std.testing.expectError(error.InjectedControlFailure, control.invoke(.shutdown, Deadline.after(std.testing.io, std.time.ns_per_s)));
}

threadlocal var cancel_next_wait = false;

test "cancellation after publication detaches instead of abandoning a running slot" {
    const Context = struct {
        io: std.Io,
        entered: std.Io.Event = .unset,
        released: std.Io.Event = .unset,
        calls: usize = 0,

        fn callback(raw: *anyopaque, _: Task) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            if (self.calls == 1) {
                self.entered.set(self.io);
                self.released.waitUncancelable(self.io);
            }
        }

        fn futexWait(context: ?*anyopaque, pointer: *const u32, expected: u32, timeout: std.Io.Timeout) std.Io.Cancelable!void {
            if (cancel_next_wait) {
                cancel_next_wait = false;
                return error.Canceled;
            }
            return std.testing.io.vtable.futexWait(context, pointer, expected, timeout);
        }
    };
    var vtable = std.testing.io.vtable.*;
    vtable.futexWait = Context.futexWait;
    const io: std.Io = .{ .userdata = std.testing.io.userdata, .vtable = &vtable };
    var context: Context = .{ .io = io };
    const control = try Control.create(std.testing.allocator, io, &context, Context.callback);
    defer control.destroy();
    cancel_next_wait = true;
    try std.testing.expectError(error.Canceled, control.invoke(.shutdown, Deadline.after(io, std.time.ns_per_s)));
    context.entered.waitUncancelable(io);
    try std.testing.expect(control.status().detached);
    context.released.set(io);
    try control.invoke(.shutdown, Deadline.after(io, std.time.ns_per_s));
    try std.testing.expectEqual(@as(usize, 2), context.calls);
}
