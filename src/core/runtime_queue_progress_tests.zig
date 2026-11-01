//! Space wait registration and terminal broadcasts use each stable SPSC queue.
const std = @import("std");
const Runtime = @import("runtime.zig").Runtime;
const JournalModule = @import("../journal/journal.zig");
const MemorySink = @import("../sink/memory.zig").MemorySink;
const types = @import("runtime_types.zig");

const Observer = struct {
    var active: ?*Observer = null;
    entered: std.Io.Event = .unset,
    permit: std.Io.Event = .unset,
    target: std.atomic.Value(usize) = .init(0),
    wakes: std.atomic.Value(usize) = .init(0),
    abort_on_wait: bool = false,
    runtime: *Runtime = undefined,
    threadlocal var reservations: ?*[2]JournalModule.Reservation = null;

    fn wait(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
        const self = active.?;
        if (@intFromPtr(ptr) == self.target.load(.acquire)) {
            self.entered.set(std.testing.io);
            if (self.abort_on_wait) {
                for (reservations.?) |*reservation| reservation.abort();
                _ = self.runtime.wake_epoch.fetchAdd(1, .seq_cst);
                std.Io.futexWake(self.runtime.io, u32, &self.runtime.wake_epoch.raw, std.math.maxInt(u32));
            } else self.permit.waitUncancelable(std.testing.io);
        }
        std.testing.io.vtable.futexWaitUncancelable(userdata, ptr, expected);
    }

    fn wake(userdata: ?*anyopaque, ptr: *const u32, max: u32) void {
        const self = active.?;
        if (@intFromPtr(ptr) == self.target.load(.acquire)) _ = self.wakes.fetchAdd(1, .release);
        std.testing.io.vtable.futexWake(userdata, ptr, max);
    }
};

const Producer = struct {
    runtime: *Runtime,
    result: ?types.EmitResult = null,
    failure: ?anyerror = null,
    done: std.Io.Event = .unset,
    fn run(self: *@This()) void {
        defer self.done.set(std.testing.io);
        self.emit() catch |err| {
            self.failure = err;
        };
    }
    fn emit(self: *@This()) !void {
        const log = try self.runtime.attachThread(.{ .scope = "waiting" });
        defer log.detach() catch {};
        var gaps: [2]JournalModule.Reservation = undefined;
        gaps[0] = try log.owner.producer_token.journal.reserveSingleProducer(log.owner.producer_token);
        defer gaps[0].abort();
        gaps[1] = try log.owner.producer_token.journal.reserveSingleProducer(log.owner.producer_token);
        defer gaps[1].abort();
        Observer.reservations = &gaps;
        defer Observer.reservations = null;
        self.result = try log.tryEmit(.info, "after space", .{});
    }
};

const Shutdown = struct {
    runtime: *Runtime,
    failure: ?anyerror = null,
    fn run(self: *@This()) void {
        self.runtime.shutdown(.drain) catch |err| {
            self.failure = err;
        };
    }
};

fn wait(event: *std.Io.Event) !void {
    try event.waitTimeout(std.testing.io, .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(5) } });
}

test "queue progress unrelated written batches never notify the SPSC space waiter and shutdown before wait cannot be lost" {
    inline for (.{ false, true }) |persistent| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_bytes: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/progress.journal", .{tmp.sub_path});
        var bytes: [8192]u8 = undefined;
        var memory = MemorySink.initBuffer(&bytes);
        var observer: Observer = .{};
        Observer.active = &observer;
        defer Observer.active = null;
        var vtable = std.testing.io.vtable.*;
        vtable.futexWaitUncancelable = Observer.wait;
        vtable.futexWake = Observer.wake;
        const io: std.Io = .{ .userdata = std.testing.io.userdata, .vtable = &vtable };
        const runtime = try Runtime.create(std.testing.allocator, io, .{
            .submission = .low_latency,
            .memory_queue = if (persistent) null else .{ .capacity = 2, .max_record_bytes = 512 },
            .journal = if (persistent) .{ .path = path, .capacity = 2, .max_record_bytes = 512 } else null,
            .max_thread_channels = 1,
            .thread_channel_capacity = 2,
            .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "queue-space" }},
        });
        defer runtime.destroy();
        const journal = runtime.thread_registry.?.getJournal(0);
        observer.target.store(@intFromPtr(&journal.single.space_epoch.raw), .release);
        observer.runtime = runtime;
        var producer: Producer = .{ .runtime = runtime };
        const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
        var closing_thread: ?std.Thread = null;
        defer {
            observer.permit.set(std.testing.io);
            runtime.shutdown(.drain) catch {};
            thread.join();
            if (closing_thread) |closing| closing.join();
        }
        try wait(&observer.entered);
        try std.testing.expect(journal.single.space_waiting.load(.seq_cst));
        const before = journal.single.space_epoch.load(.seq_cst);
        for (0..3) |index| {
            _ = try runtime.scoped("peer").tryEmit(.info, "unrelated", .{});
            const deadline = @import("control.zig").Deadline.after(std.testing.io, 5 * std.time.ns_per_s);
            while (runtime.health().written != index + 1) {
                if (deadline.expired(std.testing.io)) return error.PeerDidNotWrite;
                std.atomic.spinLoopHint();
            }
        }
        try std.testing.expectEqual(before, journal.single.space_epoch.load(.seq_cst));
        try std.testing.expectEqual(@as(usize, 0), observer.wakes.load(.acquire));
        var shutdown: Shutdown = .{ .runtime = runtime };
        closing_thread = try std.Thread.spawn(.{}, Shutdown.run, .{&shutdown});
        const deadline = @import("control.zig").Deadline.after(std.testing.io, 5 * std.time.ns_per_s);
        while (observer.wakes.load(.acquire) == 0) {
            if (deadline.expired(std.testing.io)) return error.CloseDidNotNotify;
            std.atomic.spinLoopHint();
        }
        try std.testing.expect(journal.single.space_epoch.load(.seq_cst) != before);
        observer.permit.set(std.testing.io); // Only now enters the real futex syscall.
        try wait(&producer.done);
        if (producer.failure) |err| return err;
        try std.testing.expectEqual(types.EmitResult.rejected_closing, producer.result.?);
        try std.testing.expect(!journal.single.space_waiting.load(.seq_cst));
    }
}

test "queue progress own abort reclaim wakes registered producer across u32 epoch wrap" {
    var bytes: [8192]u8 = undefined;
    var memory = MemorySink.initBuffer(&bytes);
    var observer: Observer = .{ .abort_on_wait = true };
    Observer.active = &observer;
    defer Observer.active = null;
    var vtable = std.testing.io.vtable.*;
    vtable.futexWaitUncancelable = Observer.wait;
    vtable.futexWake = Observer.wake;
    const io: std.Io = .{ .userdata = std.testing.io.userdata, .vtable = &vtable };
    const runtime = try Runtime.create(std.testing.allocator, io, .{
        .submission = .low_latency,
        .memory_queue = .{ .capacity = 2, .max_record_bytes = 512 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 2,
        .routes = &.{.{ .name = "memory", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    const journal = runtime.thread_registry.?.getJournal(0);
    observer.target.store(@intFromPtr(&journal.single.space_epoch.raw), .release);
    observer.runtime = runtime;
    journal.single.space_epoch.store(std.math.maxInt(u32), .seq_cst);
    var producer: Producer = .{ .runtime = runtime };
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    defer {
        runtime.shutdown(.drain) catch {};
        thread.join();
    }
    try wait(&producer.done);
    if (producer.failure) |err| return err;
    try std.testing.expectEqual(types.EmitResult.accepted, producer.result.?);
    try runtime.flush(.written);
    try std.testing.expect(!journal.single.space_waiting.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 3), journal.writtenTarget());
    try std.testing.expect(journal.single.space_epoch.load(.seq_cst) < 10);
}

test "queue progress worker failure on another journal broadcasts the original error to SPSC waiter" {
    inline for (.{ false, true }) |persistent| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_bytes: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/cross-failure.journal", .{tmp.sub_path});
        var bytes: [8192]u8 = undefined;
        var memory = MemorySink.initBuffer(&bytes);
        memory.fail_after_records = 0;
        var observer: Observer = .{};
        Observer.active = &observer;
        defer Observer.active = null;
        var vtable = std.testing.io.vtable.*;
        vtable.futexWaitUncancelable = Observer.wait;
        vtable.futexWake = Observer.wake;
        const io: std.Io = .{ .userdata = std.testing.io.userdata, .vtable = &vtable };
        const runtime = try Runtime.create(std.testing.allocator, io, .{
            .submission = .low_latency,
            .memory_queue = if (persistent) null else .{ .capacity = 2, .max_record_bytes = 512 },
            .journal = if (persistent) .{ .path = path, .capacity = 2, .max_record_bytes = 512 } else null,
            .max_thread_channels = 1,
            .thread_channel_capacity = 2,
            .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "cross-failure" }},
        });
        defer runtime.destroy();
        const journal = runtime.thread_registry.?.getJournal(0);
        observer.target.store(@intFromPtr(&journal.single.space_epoch.raw), .release);
        observer.runtime = runtime;
        var producer: Producer = .{ .runtime = runtime };
        const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
        defer {
            observer.permit.set(std.testing.io);
            runtime.shutdown(.drain) catch {};
            thread.join();
        }
        try wait(&observer.entered);
        const before = journal.single.space_epoch.load(.seq_cst);
        _ = try runtime.scoped("shared.failure").tryEmit(.info, "fails on different journal", .{});
        const deadline = @import("control.zig").Deadline.after(std.testing.io, 5 * std.time.ns_per_s);
        while (observer.wakes.load(.acquire) == 0) {
            if (deadline.expired(std.testing.io)) return error.WorkerErrorDidNotNotify;
            std.atomic.spinLoopHint();
        }
        try std.testing.expect(journal.single.space_epoch.load(.seq_cst) != before);
        observer.permit.set(std.testing.io);
        try wait(&producer.done);
        try std.testing.expectEqual(error.InjectedWriteFailure, producer.failure.?);
        try std.testing.expect(producer.result == null);
        try std.testing.expect(!journal.single.space_waiting.load(.seq_cst));
        try std.testing.expectEqual(@as(u64, 1), runtime.health().accepted);
        try std.testing.expectEqual(@as(u64, 0), runtime.health().written);
        try std.testing.expectError(error.InjectedWriteFailure, runtime.flush(.written));
    }
}
