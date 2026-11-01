const std = @import("std");
const Atomic = std.atomic.Value;

pub const ReportSource = enum(u8) { capture, write, sync, worker, bridge, flush };
pub const ErrorEvent = struct {
    err: anyerror,
    count: u64,
    source: ReportSource,
};
pub const Hook = *const fn (?*anyopaque, ErrorEvent) void;
pub const Options = struct {
    hook: ?Hook = null,
    context: ?*anyopaque = null,
};
pub const Stats = struct {
    recorded: u64,
    dispatched: u64,
    coalesced: u64,
    pending: u64,
    hook_calls: u64,
    recursive_dispatches: u64,
    concurrent_dispatches: u64,
    last_error: ?anyerror,
    last_source: ?ReportSource,
};

const HookFrame = struct {
    reporter: *const Reporter,
    previous: ?*const HookFrame,
};
threadlocal var active_hook: ?*const HookFrame = null;

/// A bounded, allocation-free diagnostic mailbox. The Reporter must have a
/// stable address while a hook is active, and options must stay immutable.
/// record is safe under sink/runtime locks; only dispatch invokes user code.
pub const Reporter = struct {
    options: Options,
    // Error identity and source share one atomic so snapshots never mismatch.
    last: Atomic(u32) = .init(0),
    pending: Atomic(u64) = .init(0),
    coalesced: Atomic(u64) = .init(0),
    hook_active: Atomic(bool) = .init(false),
    recorded: Atomic(u64) = .init(0),
    dispatched: Atomic(u64) = .init(0),
    hook_calls: Atomic(u64) = .init(0),
    recursive_dispatches: Atomic(u64) = .init(0),
    concurrent_dispatches: Atomic(u64) = .init(0),

    pub fn init(options: Options) Reporter {
        return .{ .options = options };
    }

    pub fn record(self: *Reporter, err: anyerror, source: ReportSource) void {
        // Publish a concrete identity before pending becomes visible. An
        // overlapping record may supply the latest identity to a coalesced
        // snapshot, but a nonempty snapshot never becomes an unknown error.
        self.last.store(pack(err, source), .release);
        _ = self.recorded.fetchAdd(1, .monotonic);
        if (self.pending.fetchAdd(1, .release) != 0) _ = self.coalesced.fetchAdd(1, .monotonic);
    }

    /// Dispatch exactly one snapshot. Records arriving after exchange remain
    /// pending for a later explicit dispatch, bounding work under an error storm.
    /// Callers must invoke this outside their sink/runtime locks.
    pub fn dispatch(self: *Reporter) void {
        if (self.inHook()) {
            _ = self.recursive_dispatches.fetchAdd(1, .monotonic);
            return;
        }
        if (self.hook_active.cmpxchgStrong(false, true, .acquire, .monotonic) != null) {
            _ = self.concurrent_dispatches.fetchAdd(1, .monotonic);
            return;
        }
        defer self.hook_active.store(false, .release);
        const count = self.pending.swap(0, .acquire);
        if (count == 0) return;
        const last = self.last.load(.acquire);
        std.debug.assert(last != 0);
        _ = self.dispatched.fetchAdd(count, .monotonic);
        const hook = self.options.hook orelse return;
        const frame: HookFrame = .{ .reporter = self, .previous = active_hook };
        active_hook = &frame;
        defer active_hook = frame.previous;
        _ = self.hook_calls.fetchAdd(1, .monotonic);
        hook(self.options.context, .{ .err = unpackError(last), .count = count, .source = unpackSource(last) });
    }

    /// Runtime admission checks this before attempting its locks. The stack
    /// also detects returning to A through a nested A-hook -> B-hook call.
    pub fn inHook(self: *const Reporter) bool {
        var current = active_hook;
        while (current) |frame| : (current = frame.previous) {
            if (frame.reporter == self) return true;
        }
        return false;
    }

    /// Counters are individually atomic; a concurrent read is observational,
    /// not a transaction across every statistic.
    pub fn stats(self: *const Reporter) Stats {
        const last = self.last.load(.acquire);
        return .{
            .recorded = self.recorded.load(.monotonic),
            .dispatched = self.dispatched.load(.monotonic),
            .coalesced = self.coalesced.load(.monotonic),
            .pending = self.pending.load(.acquire),
            .hook_calls = self.hook_calls.load(.monotonic),
            .recursive_dispatches = self.recursive_dispatches.load(.monotonic),
            .concurrent_dispatches = self.concurrent_dispatches.load(.monotonic),
            .last_error = if (last == 0) null else unpackError(last),
            .last_source = if (last == 0) null else unpackSource(last),
        };
    }
};

fn pack(err: anyerror, source: ReportSource) u32 {
    return @as(u32, @intFromError(err)) | (@as(u32, @intFromEnum(source)) << 16);
}

fn unpackError(last: u32) anyerror {
    return @errorFromInt(@as(u16, @truncate(last)));
}

fn unpackSource(last: u32) ReportSource {
    return @enumFromInt(@as(u8, @truncate(last >> 16)));
}

test "record does not invoke hooks and dispatch supplies one coalesced snapshot outside locks" {
    const State = struct {
        reporter: ?*Reporter = null,
        lock_held: bool = false,
        bad_context: bool = false,
        calls: usize = 0,
        event: ?ErrorEvent = null,

        fn hook(context: ?*anyopaque, event: ErrorEvent) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.bad_context = self.lock_held or !self.reporter.?.inHook();
            self.calls += 1;
            self.event = event;
        }
    };
    var state: State = .{};
    var reporter = Reporter.init(.{ .hook = State.hook, .context = &state });
    state.reporter = &reporter;
    try std.testing.expect(reporter.stats().last_error == null);
    state.lock_held = true;
    reporter.record(error.CaptureFailed, .capture);
    reporter.record(error.WriteFailed, .write);
    try std.testing.expectEqual(@as(usize, 0), state.calls);
    try std.testing.expectEqual(@as(u64, 2), reporter.stats().pending);
    try std.testing.expectEqual(@as(u64, 1), reporter.stats().coalesced);
    state.lock_held = false;
    reporter.dispatch();
    try std.testing.expect(!state.bad_context);
    try std.testing.expect(!reporter.inHook());
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    try std.testing.expectEqual(error.WriteFailed, state.event.?.err);
    try std.testing.expectEqual(ReportSource.write, state.event.?.source);
    try std.testing.expectEqual(@as(u64, 2), state.event.?.count);
    try std.testing.expectEqual(@as(u64, 2), reporter.stats().dispatched);
    try std.testing.expectEqual(@as(u64, 0), reporter.stats().pending);
    reporter.dispatch();
    try std.testing.expectEqual(@as(usize, 1), state.calls);
}

test "hook errors remain pending and recursive dispatch never calls the hook twice" {
    const State = struct {
        reporter: ?*Reporter = null,
        calls: usize = 0,
        event: ?ErrorEvent = null,

        fn hook(context: ?*anyopaque, event: ErrorEvent) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            self.event = event;
            if (self.calls == 1) {
                self.reporter.?.record(error.NewWorkerFailure, .worker);
                self.reporter.?.dispatch();
            }
        }
    };
    var state: State = .{};
    var reporter = Reporter.init(.{ .hook = State.hook, .context = &state });
    state.reporter = &reporter;
    reporter.record(error.Original, .sync);
    reporter.dispatch();
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    try std.testing.expectEqual(@as(u64, 1), reporter.stats().pending);
    try std.testing.expectEqual(@as(u64, 1), reporter.stats().recursive_dispatches);
    try std.testing.expectEqual(error.NewWorkerFailure, reporter.stats().last_error.?);
    reporter.dispatch();
    try std.testing.expectEqual(@as(usize, 2), state.calls);
    try std.testing.expectEqual(error.NewWorkerFailure, state.event.?.err);
    try std.testing.expectEqual(@as(u64, 1), state.event.?.count);
    try std.testing.expectEqual(@as(u64, 0), reporter.stats().pending);
}

test "disabled hooks still expose errors and bounded dispatch statistics" {
    var reporter = Reporter.init(.{});
    reporter.record(error.NoHook, .bridge);
    reporter.dispatch();
    const stats = reporter.stats();
    try std.testing.expectEqual(@as(u64, 1), stats.recorded);
    try std.testing.expectEqual(@as(u64, 1), stats.dispatched);
    try std.testing.expectEqual(@as(u64, 0), stats.pending);
    try std.testing.expectEqual(@as(u64, 0), stats.hook_calls);
    try std.testing.expectEqual(error.NoHook, stats.last_error.?);
    try std.testing.expectEqual(ReportSource.bridge, stats.last_source.?);
}

test "concurrent recording and dispatch preserve counts without overlapping hooks" {
    const State = struct {
        reporter: ?*Reporter = null,
        entered: Atomic(bool) = .init(false),
        release_hook: Atomic(bool) = .init(false),
        active: Atomic(usize) = .init(0),
        bad_hook: Atomic(bool) = .init(false),
        calls: Atomic(usize) = .init(0),
        observed_count: Atomic(u64) = .init(0),
        observed_error: Atomic(u16) = .init(0),

        fn hook(context: ?*anyopaque, event: ErrorEvent) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.active.fetchAdd(1, .acq_rel) != 0 or !self.reporter.?.inHook()) self.bad_hook.store(true, .release);
            defer _ = self.active.fetchSub(1, .release);
            _ = self.calls.fetchAdd(1, .monotonic);
            self.observed_count.store(event.count, .release);
            self.observed_error.store(@intFromError(event.err), .release);
            self.entered.store(true, .release);
            while (!self.release_hook.load(.acquire)) std.atomic.spinLoopHint();
        }

        fn dispatch(reporter: *Reporter) void {
            reporter.dispatch();
        }

        fn worker(reporter: *Reporter) void {
            for (0..100) |_| {
                reporter.record(error.ConcurrentFailure, .worker);
                reporter.dispatch();
            }
        }
    };
    var state: State = .{};
    var reporter = Reporter.init(.{ .hook = State.hook, .context = &state });
    state.reporter = &reporter;
    reporter.record(error.FirstFailure, .write);
    const dispatcher = try std.Thread.spawn(.{}, State.dispatch, .{&reporter});
    var dispatcher_joined = false;
    defer if (!dispatcher_joined) {
        state.release_hook.store(true, .release);
        dispatcher.join();
    };
    while (!state.entered.load(.acquire)) std.atomic.spinLoopHint();
    var workers: [4]std.Thread = undefined;
    var started: usize = 0;
    defer for (workers[0..started]) |worker| worker.join();
    for (&workers) |*worker| {
        worker.* = try std.Thread.spawn(.{}, State.worker, .{&reporter});
        started += 1;
    }
    for (workers[0..started]) |worker| worker.join();
    started = 0;
    try std.testing.expect(!reporter.inHook()); // TLS state is local to the hook thread.
    try std.testing.expectEqual(@as(usize, 1), state.calls.load(.acquire));
    try std.testing.expectEqual(@as(u64, 401), reporter.stats().recorded);
    try std.testing.expectEqual(@as(u64, 400), reporter.stats().pending);
    try std.testing.expectEqual(@as(u64, 399), reporter.stats().coalesced);
    try std.testing.expectEqual(@as(u64, 400), reporter.stats().concurrent_dispatches);
    state.release_hook.store(true, .release);
    dispatcher.join();
    dispatcher_joined = true;
    reporter.dispatch();
    try std.testing.expect(!state.bad_hook.load(.acquire));
    try std.testing.expectEqual(@as(usize, 2), state.calls.load(.acquire));
    try std.testing.expectEqual(@as(u64, 400), state.observed_count.load(.acquire));
    try std.testing.expectEqual(@intFromError(error.ConcurrentFailure), state.observed_error.load(.acquire));
    try std.testing.expectEqual(@as(u64, 401), reporter.stats().dispatched);
    try std.testing.expectEqual(@as(u64, 0), reporter.stats().pending);
}

test "nested distinct reporter hooks still reject returning to an active reporter" {
    const State = struct {
        first: ?*Reporter = null,
        second: ?*Reporter = null,
        first_calls: usize = 0,
        second_calls: usize = 0,
        bad_hook: bool = false,

        fn firstHook(context: ?*anyopaque, _: ErrorEvent) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.first_calls += 1;
            if (!self.first.?.inHook() or self.second.?.inHook()) self.bad_hook = true;
            if (self.first_calls == 1) {
                self.second.?.record(error.SecondReporter, .sync);
                self.second.?.dispatch();
            }
        }

        fn secondHook(context: ?*anyopaque, _: ErrorEvent) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.second_calls += 1;
            if (!self.first.?.inHook() or !self.second.?.inHook()) self.bad_hook = true;
            self.first.?.record(error.NestedFailure, .bridge);
            self.first.?.dispatch();
        }
    };
    var state: State = .{};
    var first = Reporter.init(.{ .hook = State.firstHook, .context = &state });
    var second = Reporter.init(.{ .hook = State.secondHook, .context = &state });
    state.first = &first;
    state.second = &second;
    first.record(error.FirstReporter, .capture);
    first.dispatch();
    try std.testing.expect(!state.bad_hook);
    try std.testing.expectEqual(@as(usize, 1), state.first_calls);
    try std.testing.expectEqual(@as(usize, 1), state.second_calls);
    try std.testing.expectEqual(@as(u64, 1), first.stats().recursive_dispatches);
    try std.testing.expectEqual(@as(u64, 1), first.stats().pending);
    try std.testing.expectEqual(error.NestedFailure, first.stats().last_error.?);
    try std.testing.expect(!first.inHook());
    try std.testing.expect(!second.inHook());
    first.dispatch();
    try std.testing.expectEqual(@as(usize, 2), state.first_calls);
    try std.testing.expectEqual(@as(u64, 0), first.stats().pending);
}
