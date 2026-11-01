//! Consumer tests intentionally import only the installed public module.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const testing = std.testing;

fn journalPath(tmp: *const testing.TmpDir, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/integration.journal", .{tmp.sub_path});
}

fn linuxOnly() !void {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
}

fn wait(event: *std.Io.Event) !void {
    const timeout: std.Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(5) } };
    const deadline = timeout.toTimestamp(testing.io).?;
    while (!event.isSet()) event.waitTimeout(testing.io, .{ .deadline = deadline }) catch |err| {
        if (err != error.Timeout) return err;
        if (deadline.clock.now(testing.io).nanoseconds >= deadline.raw.nanoseconds and !event.isSet()) return error.Timeout;
    };
}

const Producer = struct {
    runtime: *kron.Runtime,
    start: *std.Io.Event,
    id: usize,
    count: usize = 1000,
    allow_closing: bool = false,
    accepted: usize = 0,
    rejected: usize = 0,
    failure: ?anyerror = null,
    done: std.Io.Event = .unset,

    fn run(self: *Producer) void {
        defer self.done.set(testing.io);
        self.start.waitUncancelable(testing.io);
        const log = self.runtime.scoped("integration.producer");
        for (0..self.count) |index| {
            const result = log.tryEmit(.info, "producer event", .{ .producer = self.id, .index = index }) catch |err| {
                self.failure = err;
                return;
            };
            switch (result) {
                .accepted => self.accepted += 1,
                .rejected_closing => if (self.allow_closing) {
                    self.rejected += 1;
                } else {
                    self.failure = error.UnexpectedClosing;
                    return;
                },
                else => {
                    self.failure = error.UnexpectedEmitResult;
                    return;
                },
            }
        }
    }
};

fn verifyProducers(output: []const u8, expected_count: usize, complete: bool) !void {
    var seen: [4][1000]bool = @splat(@splat(false));
    var previous_sequence: i64 = 0;
    var count: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, line, .{});
        defer parsed.deinit();
        const object = parsed.value.object;
        const sequence = object.get("sequence").?.integer;
        try testing.expect(sequence > previous_sequence);
        previous_sequence = sequence;
        const attributes = object.get("attributes").?.object;
        const producer: usize = @intCast(attributes.get("producer").?.integer);
        const index: usize = @intCast(attributes.get("index").?.integer);
        try testing.expect(producer < seen.len and index < seen[0].len);
        try testing.expect(!seen[producer][index]);
        seen[producer][index] = true;
        count += 1;
    }
    try testing.expectEqual(expected_count, count);
    if (complete) for (seen) |producer| for (producer) |present| try testing.expect(present);
}

test "external runtime: four producers each submit 1000 complete records in both modes" {
    try linuxOnly();
    inline for (.{ .sync, .asynchronous }) |submission| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buffer: [128]u8 = undefined;
        var memory = try kron.MemorySink.init(testing.allocator, 4 * 1024 * 1024);
        defer memory.deinit();
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = submission,
            .journal = if (submission == .asynchronous) .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 16, .max_record_bytes = 1024 } else null,
            .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
        });
        defer runtime.destroy();
        var start: std.Io.Event = .unset;
        var producers: [4]Producer = undefined;
        var threads: [4]std.Thread = undefined;
        var spawned: usize = 0;
        defer {
            start.set(testing.io);
            for (threads[0..spawned]) |thread| thread.join();
        }
        for (&producers, 0..) |*producer, id| {
            producer.* = .{ .runtime = runtime, .start = &start, .id = id };
            threads[id] = try std.Thread.spawn(.{}, Producer.run, .{producer});
            spawned += 1;
        }
        start.set(testing.io);
        for (&producers) |*producer| try wait(&producer.done);
        for (threads[0..spawned]) |thread| thread.join();
        spawned = 0;
        for (producers) |producer| {
            if (producer.failure) |err| return err;
            try testing.expectEqual(@as(usize, 1000), producer.accepted);
        }
        try runtime.flush(.written);
        const health = runtime.health();
        try testing.expectEqual(@as(u64, 4000), health.accepted);
        try testing.expectEqual(@as(u64, 4000), health.written);
        try testing.expectEqual(@as(usize, 0), health.journal_pending);
        try testing.expectEqual(@as(u64, 0), health.dropped_full);
        try verifyProducers(memory.written(), 4000, true);
        try runtime.shutdown(.drain);
    }
}

test "external runtime: required write and flush failures retain recoverable journal records" {
    try linuxOnly();
    inline for (.{ false, true }) |fail_flush| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buffer: [128]u8 = undefined;
        const path = try journalPath(&tmp, &path_buffer);
        var storage: [4096]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&storage);
        memory.fail_flush = fail_flush;
        memory.fail_after_records = if (fail_flush) null else 0;
        var owner: ?*kron.Runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = .asynchronous,
            .journal = .{ .path = path, .capacity = 4, .max_record_bytes = 1024 },
            .routes = &.{.{ .name = "required", .sink = memory.sink(), .recovery_identity = "test-fault" }},
        });
        defer if (owner) |runtime| runtime.destroy();
        const runtime = owner.?;
        try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("failure").tryEmit(.info, "retain this event", .{ .answer = 42 }));
        const expected = if (fail_flush) error.InjectedFlushFailure else error.InjectedWriteFailure;
        try testing.expectError(expected, runtime.flush(.written));
        try testing.expectError(expected, runtime.shutdown(.drain));
        const health = runtime.health();
        try testing.expectEqual(@as(usize, 1), health.journal_pending);
        try testing.expectEqual(@as(u64, 0), health.written);
        try testing.expectEqual(expected, health.last_error.?);
        try testing.expect(!health.worker_alive);
        try testing.expectEqual(.closed, health.state);
        runtime.destroy();
        owner = null;
        const reopened = try kron.Journal.create(testing.allocator, testing.io, .{ .path = path, .capacity = 4, .max_record_bytes = 1024 });
        defer reopened.deinit();
        try testing.expectEqual(@as(usize, 1), reopened.pending());
        var scratch: [8]kron.Field = undefined;
        const record = (try reopened.peekChecked()).?;
        const event = try kron.codec.decode(record.payload, &scratch);
        try testing.expectEqualStrings("retain this event", event.message);
        try testing.expectEqual(@as(u128, 42), event.fields[0].value.unsigned);
        try reopened.release(record);
    }
}

test "external runtime: asynchronous best effort failures leave required output and worker healthy" {
    try linuxOnly();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var bad_bytes: [4096]u8 = undefined;
    var good = try kron.MemorySink.init(testing.allocator, 128 * 1024);
    defer good.deinit();
    var bad = kron.MemorySink.initBuffer(&bad_bytes);
    bad.fail_after_records = 0;
    bad.fail_flush = true;
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 8, .max_record_bytes = 1024 },
        .routes = &.{
            .{ .name = "best effort", .sink = bad.sink(), .delivery = .best_effort, .recovery_identity = "test-best-effort" },
            .{ .name = "required", .sink = good.sink(), .recovery_identity = "test-memory" },
        },
    });
    defer runtime.destroy();
    for (0..100) |index| try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("isolation").tryEmit(.info, "required receives", .{ .index = index }));
    try runtime.flush(.written);
    try testing.expectEqual(@as(usize, 100), good.records);
    try testing.expectEqual(@as(u64, 100), runtime.health().written);
    try testing.expectEqual(@as(u64, 100), runtime.health().write_errors);
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    try testing.expect(runtime.health().worker_alive);
    try runtime.shutdown(.drain);
}

test "external runtime: reservation gap deterministically fills queue and counts full and oversize drops" {
    try linuxOnly();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var bytes: [4096]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .overflow = .drop_newest,
        .journal = .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 512 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    const log = runtime.scoped("capacity");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "after gap", .{}));
    for (0..50) |_| try testing.expectEqual(kron.EmitResult.dropped_full, try log.tryEmit(.info, "full", .{}));
    try testing.expectEqual(@as(u64, 50), runtime.health().dropped_full);
    try testing.expectEqual(@as(usize, 2), runtime.health().journal_pending);
    try testing.expectEqual(@as(usize, 2), runtime.health().journal_high_water);
    gap.abort();
    try runtime.flush(.written);
    var large: [1024]u8 = @splat('x');
    try testing.expectEqual(kron.EmitResult.dropped_oversize, try log.tryEmit(.info, "oversize", .{ .large = large[0..] }));
    try runtime.flush(.drain);
    try testing.expectEqual(@as(u64, 1), runtime.health().dropped_oversize);
    try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
    try testing.expectEqual(@as(usize, 1), memory.records);
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
}

// Observe the real Runtime futex path without replacing its wait/wakeup logic.
// Keeping the original userdata lets every unmodified Io operation forward to
// the testing implementation. Events establish each schedule without sleeps.
const FutexObserver = struct {
    target: std.atomic.Value(usize) = .init(0),
    entered: std.Io.Event = .unset,
    var current: std.atomic.Value(?*FutexObserver) = .init(null);

    fn observe(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
        if (current.load(.acquire)) |observer| {
            if (@intFromPtr(ptr) == observer.target.load(.acquire)) observer.entered.set(testing.io);
        }
        testing.io.vtable.futexWaitUncancelable(userdata, ptr, expected);
    }
};

test "external runtime: idle batch progress avoids waking unregistered waiters in Memory and Mmap" {
    try linuxOnly();
    const WakeObserver = struct {
        target: std.atomic.Value(usize) = .init(0),
        wakes: std.atomic.Value(usize) = .init(0),
        var current: std.atomic.Value(?*@This()) = .init(null);
        fn wake(userdata: ?*anyopaque, ptr: *const u32, count: u32) void {
            if (current.load(.acquire)) |self| {
                if (@intFromPtr(ptr) == self.target.load(.acquire)) _ = self.wakes.fetchAdd(1, .monotonic);
            }
            testing.io.vtable.futexWake(userdata, ptr, count);
        }
    };
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        inline for (.{ false, true }) |persistent| {
            var tmp = testing.tmpDir(.{});
            defer tmp.cleanup();
            var path_buffer: [128]u8 = undefined;
            var bytes: [4096]u8 = undefined;
            var memory = kron.MemorySink.initBuffer(&bytes);
            var observer: WakeObserver = .{};
            WakeObserver.current.store(&observer, .release);
            defer WakeObserver.current.store(null, .release);
            var vtable = testing.io.vtable.*;
            vtable.futexWake = WakeObserver.wake;
            const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
            const runtime = try kron.Runtime.create(testing.allocator, io, .{
                .submission = submission,
                .journal = if (persistent) .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 512 } else null,
                .memory_queue = if (persistent) null else .{ .capacity = 4, .max_record_bytes = 512 },
                .max_thread_channels = if (submission == .low_latency) 1 else 0,
                .thread_channel_capacity = 4,
                .idle = .sleep,
                .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "progress-output" }},
            });
            defer runtime.destroy();
            observer.target.store(@intFromPtr(&runtime.progress_epoch.raw), .release);
            const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "progress" }) else runtime.scoped("progress");
            defer if (submission == .low_latency) log.detach() catch {};
            try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "one complete batch", .{}));
            // Observe completed writes without registering a progress waiter.
            // Taking the existing delivery lock then waits for the whole
            // batch notification to finish, so an old unconditional wake
            // cannot slip past the assertion merely because of scheduling.
            const deadline = std.Io.Clock.awake.now(testing.io).nanoseconds + 5 * std.time.ns_per_s;
            while (runtime.health().written == 0) {
                if (std.Io.Clock.awake.now(testing.io).nanoseconds >= deadline) return error.Timeout;
                std.atomic.spinLoopHint();
            }
            runtime.delivery_mutex.lockUncancelable(io);
            const wakes = observer.wakes.load(.monotonic);
            const records = memory.records;
            runtime.delivery_mutex.unlock(io);
            try testing.expectEqual(@as(usize, 0), wakes);
            try testing.expectEqual(@as(usize, 1), records);
            try runtime.flush(.written);
            try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
        }
    }
}

const Shutdown = struct {
    runtime: *kron.Runtime,
    failure: ?anyerror = null,
    done: std.Io.Event = .unset,
    fn run(self: *Shutdown) void {
        defer self.done.set(testing.io);
        self.runtime.shutdown(.drain) catch |err| {
            self.failure = err;
        };
    }
};

test "external runtime: shutdown wakes a producer actually waiting on a full blocking queue" {
    try linuxOnly();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var bytes: [4096]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    var observer: FutexObserver = .{};
    FutexObserver.current.store(&observer, .release);
    defer FutexObserver.current.store(null, .release);
    var vtable = testing.io.vtable.*;
    vtable.futexWaitUncancelable = FutexObserver.observe;
    const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
    const runtime = try kron.Runtime.create(testing.allocator, io, .{
        .submission = .asynchronous,
        .overflow = .block,
        .journal = .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 512 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    var first = try runtime.journal.?.reserve();
    defer first.abort();
    var second = try runtime.journal.?.reserve();
    defer second.abort();
    observer.target.store(@intFromPtr(&runtime.progress_epoch.raw), .release);
    var start: std.Io.Event = .is_set;
    var producer: Producer = .{ .runtime = runtime, .start = &start, .id = 0, .count = 1, .allow_closing = true };
    const producer_thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    var shutdown_thread: ?std.Thread = null;
    defer {
        // Even a failed assertion must unblock both threads before joining.
        first.abort();
        second.abort();
        _ = runtime.wake_epoch.fetchAdd(1, .release);
        io.futexWake(u32, &runtime.wake_epoch.raw, std.math.maxInt(u32));
        _ = runtime.progress_epoch.fetchAdd(1, .release);
        io.futexWake(u32, &runtime.progress_epoch.raw, std.math.maxInt(u32));
        producer_thread.join();
        if (shutdown_thread) |thread| thread.join();
    }
    try wait(&observer.entered);
    try testing.expect(!producer.done.isSet());
    try testing.expectEqual(@as(u64, 1), runtime.activeAdmissions());
    var shutdown: Shutdown = .{ .runtime = runtime };
    shutdown_thread = try std.Thread.spawn(.{}, Shutdown.run, .{&shutdown});
    try wait(&producer.done);
    first.abort();
    second.abort();
    // flush sends the worker notification needed after manually aborting gaps.
    try runtime.flush(.drain);
    try wait(&shutdown.done);
    if (producer.failure) |err| return err;
    if (shutdown.failure) |err| return err;
    try testing.expectEqual(@as(usize, 1), producer.rejected);
    try testing.expectEqual(@as(u64, 1), runtime.health().rejected_closing);
    try testing.expectEqual(@as(u64, 0), runtime.health().accepted);
    try testing.expectEqual(.closed, runtime.health().state);
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
}

test "external runtime: Memory and Mmap SPSC full wait wakes on shutdown" {
    try linuxOnly();
    const Blocked = struct {
        runtime: *kron.Runtime,
        failure: ?anyerror = null,
        result: ?kron.EmitResult = null,
        done: std.Io.Event = .unset,

        fn run(self: *@This()) void {
            defer self.done.set(testing.io);
            self.emit() catch |err| {
                self.failure = err;
            };
        }
        fn emit(self: *@This()) !void {
            const log = try self.runtime.attachThread(.{ .scope = "full.channel" });
            defer log.detach() catch {};
            const journal = self.runtime.thread_registry.?.getJournal(0);
            var first = try journal.reserveSingleProducer(log.owner.producer_token);
            defer first.abort();
            var second = try journal.reserveSingleProducer(log.owner.producer_token);
            defer second.abort();
            self.result = try log.tryEmit(.info, "blocked", .{ .field = @as(u64, 1) });
        }
    };
    inline for (.{ false, true }) |persistent| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buffer: [128]u8 = undefined;
        var bytes: [4096]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&bytes);
        var observer: FutexObserver = .{};
        FutexObserver.current.store(&observer, .release);
        defer FutexObserver.current.store(null, .release);
        var vtable = testing.io.vtable.*;
        vtable.futexWaitUncancelable = FutexObserver.observe;
        const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
        const runtime = try kron.Runtime.create(testing.allocator, io, .{
            .submission = .low_latency,
            .overflow = .block,
            .journal = if (persistent) .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 512 } else null,
            .memory_queue = if (persistent) null else .{ .capacity = 2, .max_record_bytes = 512 },
            .max_thread_channels = 1,
            .thread_channel_capacity = 2,
            .idle = .sleep,
            .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "full-channel-output" }},
        });
        defer runtime.destroy();
        observer.target.store(@intFromPtr(&runtime.progress_epoch.raw), .release);
        var producer: Blocked = .{ .runtime = runtime };
        const thread = try std.Thread.spawn(.{}, Blocked.run, .{&producer});
        var shutdown_thread: ?std.Thread = null;
        defer {
            // Closing wakes the admitted producer so its owner can abort the
            // manual reservations before join; flush notifies those tombstones.
            runtime.shutdown(.drain) catch {};
            thread.join();
            if (shutdown_thread) |handle| handle.join();
        }
        try wait(&observer.entered);
        try testing.expect(!producer.done.isSet());
        var shutdown: Shutdown = .{ .runtime = runtime };
        shutdown_thread = try std.Thread.spawn(.{}, Shutdown.run, .{&shutdown});
        try wait(&producer.done);
        try runtime.flush(.drain);
        try wait(&shutdown.done);
        if (producer.failure) |err| return err;
        if (shutdown.failure) |err| return err;
        try testing.expectEqual(@as(?kron.EmitResult, .rejected_closing), producer.result);
        try testing.expectEqual(@as(u64, 1), runtime.health().rejected_closing);
        try testing.expectEqual(@as(u64, 0), runtime.health().accepted);
        try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
        try testing.expectEqual(@as(usize, 0), memory.records);
    }
}

test "external runtime: worker failure wakes a full SPSC producer in Memory and Mmap" {
    try linuxOnly();
    const FailingSink = struct {
        entered: std.Io.Event = .unset,
        proceed: std.Io.Event = .unset,
        fn write(raw: *anyopaque, _: []const u8) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.entered.set(testing.io);
            self.proceed.waitUncancelable(testing.io);
            return error.InjectedWriteFailure;
        }
        fn flush(_: *anyopaque) anyerror!void {}
        fn sink(self: *@This()) kron.Sink {
            return .{ .context = self, .vtable = &.{ .writeRecord = write, .flush = flush, .sync = flush }, .recovery_identity = "blocked-producer-failure" };
        }
    };
    const Blocked = struct {
        runtime: *kron.Runtime,
        failure: ?anyerror = null,
        accepted: usize = 0,
        done: std.Io.Event = .unset,
        fn run(self: *@This()) void {
            defer self.done.set(testing.io);
            self.emit() catch |err| {
                self.failure = err;
            };
        }
        fn emit(self: *@This()) !void {
            const log = try self.runtime.attachThread(.{ .scope = "blocked.failure" });
            defer log.detach() catch {};
            for (0..3) |index| {
                if (try log.tryEmit(.info, "pending", .{ .index = index }) != .accepted) return error.UnexpectedOutcome;
                self.accepted += 1;
            }
        }
    };
    inline for (.{ false, true }) |persistent| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buffer: [128]u8 = undefined;
        var sink: FailingSink = .{};
        var observer: FutexObserver = .{};
        FutexObserver.current.store(&observer, .release);
        defer FutexObserver.current.store(null, .release);
        var vtable = testing.io.vtable.*;
        vtable.futexWaitUncancelable = FutexObserver.observe;
        const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
        const runtime = try kron.Runtime.create(testing.allocator, io, .{
            .submission = .low_latency,
            .journal = if (persistent) .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 2, .max_record_bytes = 512 } else null,
            .memory_queue = if (persistent) null else .{ .capacity = 2, .max_record_bytes = 512 },
            .max_thread_channels = 1,
            .thread_channel_capacity = 2,
            .idle = .sleep,
            .routes = &.{.{ .name = "output", .sink = sink.sink() }},
        });
        defer runtime.destroy();
        observer.target.store(@intFromPtr(&runtime.progress_epoch.raw), .release);
        var producer: Blocked = .{ .runtime = runtime };
        const thread = try std.Thread.spawn(.{}, Blocked.run, .{&producer});
        defer {
            sink.proceed.set(testing.io);
            thread.join();
        }
        try wait(&sink.entered);
        try wait(&observer.entered);
        try testing.expect(!producer.done.isSet());
        sink.proceed.set(testing.io);
        try wait(&producer.done);
        const failure = producer.failure orelse return error.ExpectedWorkerFailure;
        try testing.expectEqual(error.InjectedWriteFailure, failure);
        try testing.expectEqual(@as(usize, 2), producer.accepted);
        try testing.expectError(error.InjectedWriteFailure, runtime.flush(.written));
        try testing.expectEqual(@as(u64, 2), runtime.health().accepted);
        try testing.expectEqual(@as(u64, 0), runtime.health().written);
        try testing.expectEqual(@as(usize, 2), runtime.health().journal_pending);
        try testing.expectEqual(@as(usize, 0), runtime.progress_waiters.load(.seq_cst));
    }
}

test "external runtime: closing waits for an admitted event and rejects a later logger call" {
    var bytes: [4096]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    var observer: FutexObserver = .{};
    FutexObserver.current.store(&observer, .release);
    defer FutexObserver.current.store(null, .release);
    var vtable = testing.io.vtable.*;
    vtable.futexWaitUncancelable = FutexObserver.observe;
    const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
    const runtime = try kron.Runtime.create(testing.allocator, io, .{
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    const admission = runtime.begin(.info, "closing").ready;
    observer.target.store(@intFromPtr(&runtime.admission_epoch.raw), .release);
    var shutdown: Shutdown = .{ .runtime = runtime };
    var ended = false;
    const thread = std.Thread.spawn(.{}, Shutdown.run, .{&shutdown}) catch |err| {
        runtime.end();
        return err;
    };
    defer {
        if (!ended) runtime.end();
        thread.join();
    }
    try wait(&observer.entered);
    try testing.expectEqual(.closing, runtime.health().state);
    try testing.expect(!shutdown.done.isSet());
    try testing.expectEqual(kron.EmitResult.rejected_closing, try runtime.scoped("late logger").tryEmit(.fatal, "rejected", .{}));
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.submit(admission, .{
        .level = .info,
        .scope = "closing",
        .message = "admitted before closing",
        .fields = &.{},
        .timestamp_ns = 1,
    }));
    runtime.end();
    ended = true;
    try wait(&shutdown.done);
    if (shutdown.failure) |err| return err;
    try testing.expectEqual(@as(usize, 1), memory.records);
    try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
    try testing.expectEqual(@as(u64, 1), runtime.health().written);
    try testing.expectEqual(@as(u64, 1), runtime.health().rejected_closing);
    try testing.expectEqual(.closed, runtime.health().state);
}

test "external runtime: producer logging races closing without losing accepted records" {
    try linuxOnly();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var memory = try kron.MemorySink.init(testing.allocator, 4 * 1024 * 1024);
    defer memory.deinit();
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 16, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    var start: std.Io.Event = .unset;
    var producers: [4]Producer = undefined;
    var threads: [4]std.Thread = undefined;
    var spawned: usize = 0;
    defer {
        start.set(testing.io);
        for (threads[0..spawned]) |thread| thread.join();
    }
    for (&producers, 0..) |*producer, id| {
        producer.* = .{ .runtime = runtime, .start = &start, .id = id, .allow_closing = true };
        threads[id] = try std.Thread.spawn(.{}, Producer.run, .{producer});
        spawned += 1;
    }
    start.set(testing.io);
    try runtime.shutdown(.drain);
    for (&producers) |*producer| try wait(&producer.done);
    for (threads[0..spawned]) |thread| thread.join();
    spawned = 0;
    var accepted: usize = 0;
    var rejected: usize = 0;
    for (producers) |producer| {
        if (producer.failure) |err| return err;
        accepted += producer.accepted;
        rejected += producer.rejected;
    }
    try testing.expectEqual(@as(usize, 4000), accepted + rejected);
    try testing.expectEqual(@as(u64, @intCast(accepted)), runtime.health().accepted);
    try testing.expectEqual(@as(u64, @intCast(accepted)), runtime.health().written);
    try testing.expectEqual(@as(u64, @intCast(rejected)), runtime.health().rejected_closing);
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    try testing.expectEqual(.closed, runtime.health().state);
    try verifyProducers(memory.written(), accepted, false);
    try testing.expectEqual(kron.EmitResult.rejected_closing, try runtime.scoped("after shutdown").tryEmit(.fatal, "closed", .{}));
}

const PausedProducer = struct {
    runtime: *kron.Runtime,
    ready: std.Io.Event = .unset,
    resume_event: std.Io.Event = .unset,
    done: std.Io.Event = .unset,
    failure: ?anyerror = null,
    result: ?kron.EmitResult = null,

    fn run(self: *PausedProducer) void {
        defer self.done.set(testing.io);
        const admission = switch (self.runtime.begin(.info, "flush.cut")) {
            .ready => |admission| admission,
            else => {
                self.failure = error.AdmissionRejected;
                self.ready.set(testing.io);
                return;
            },
        };
        defer self.runtime.end();
        self.ready.set(testing.io);
        self.resume_event.waitUncancelable(testing.io);
        self.result = self.runtime.submit(admission, .{
            .level = .info,
            .scope = "flush.cut",
            .message = "captured before the flush cut",
            .fields = &.{},
            .timestamp_ns = 1,
        }) catch |err| {
            self.failure = err;
            return;
        };
    }
};

const Flusher = struct {
    runtime: *kron.Runtime,
    failure: ?anyerror = null,
    done: std.Io.Event = .unset,
    fn run(self: *Flusher) void {
        defer self.done.set(testing.io);
        self.runtime.flush(.written) catch |err| {
            self.failure = err;
        };
    }
};

test "external runtime: flush cut waits for a producer admitted before its journal reservation" {
    try linuxOnly();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var bytes: [4096]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    var observer: FutexObserver = .{};
    FutexObserver.current.store(&observer, .release);
    defer FutexObserver.current.store(null, .release);
    var vtable = testing.io.vtable.*;
    vtable.futexWaitUncancelable = FutexObserver.observe;
    const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
    const runtime = try kron.Runtime.create(testing.allocator, io, .{
        .submission = .asynchronous,
        .journal = .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    observer.target.store(@intFromPtr(&runtime.admission_epoch.raw), .release);
    var producer: PausedProducer = .{ .runtime = runtime };
    const producer_thread = try std.Thread.spawn(.{}, PausedProducer.run, .{&producer});
    var flush_thread: ?std.Thread = null;
    defer {
        producer.resume_event.set(testing.io);
        producer_thread.join();
        if (flush_thread) |thread| thread.join();
    }
    try wait(&producer.ready);
    if (producer.failure) |err| return err;
    try testing.expectEqual(@as(u64, 1), runtime.activeAdmissions());
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    var flusher: Flusher = .{ .runtime = runtime };
    flush_thread = try std.Thread.spawn(.{}, Flusher.run, .{&flusher});
    try wait(&observer.entered);
    try testing.expect(!flusher.done.isSet());
    producer.resume_event.set(testing.io);
    try wait(&producer.done);
    try wait(&flusher.done);
    if (producer.failure) |err| return err;
    if (flusher.failure) |err| return err;
    try testing.expectEqual(kron.EmitResult.accepted, producer.result.?);
    try testing.expectEqual(@as(usize, 1), memory.records);
    try testing.expectEqual(@as(u64, 1), runtime.health().written);
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    try testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
}

test "external runtime: same producer cannot flush or shut down while holding admission" {
    var bytes: [4096]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    const admission = runtime.begin(.info, "producer.reentrant").ready;
    defer runtime.end();
    try testing.expectError(error.ProducerReentrant, runtime.flush(.written));
    try testing.expectError(error.ProducerReentrant, runtime.shutdown(.drain));
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.submit(admission, .{
        .level = .info,
        .scope = "producer.reentrant",
        .message = "admission remains usable",
        .fields = &.{},
        .timestamp_ns = 1,
    }));
}

const ReentrantSink = struct {
    runtime: ?*kron.Runtime = null,
    memory: kron.MemorySink,
    flush_error: ?anyerror = null,
    shutdown_error: ?anyerror = null,

    fn write(context: *anyopaque, record: []const u8) anyerror!void {
        const self: *ReentrantSink = @ptrCast(@alignCast(context));
        self.runtime.?.flush(.written) catch |err| {
            self.flush_error = err;
        };
        self.runtime.?.shutdown(.drain) catch |err| {
            self.shutdown_error = err;
        };
        const flush_error = self.flush_error orelse return error.ExpectedWorkerReentrant;
        const shutdown_error = self.shutdown_error orelse return error.ExpectedWorkerReentrant;
        if (flush_error != error.WorkerReentrant or shutdown_error != error.WorkerReentrant) return error.ExpectedWorkerReentrant;
        try self.memory.writeRecord(record);
    }
    fn flush(_: *anyopaque) anyerror!void {}
    fn sync(_: *anyopaque) anyerror!void {
        return error.UnsupportedDurability;
    }
    const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = sync };
    fn sink(self: *ReentrantSink) kron.Sink {
        return .{ .context = self, .vtable = &vtable };
    }
};

test "external runtime: a worker sink callback cannot recursively flush or shut down" {
    try linuxOnly();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var bytes: [4096]u8 = undefined;
    var sink: ReentrantSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "reentrant", .sink = sink.sink(), .recovery_identity = "test-reentrant" }},
    });
    defer runtime.destroy();
    sink.runtime = runtime;
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("worker.reentrant").tryEmit(.info, "worker remains healthy", .{}));
    try runtime.flush(.written);
    try testing.expectEqual(error.WorkerReentrant, sink.flush_error.?);
    try testing.expectEqual(error.WorkerReentrant, sink.shutdown_error.?);
    try testing.expectEqual(@as(usize, 1), sink.memory.records);
    try testing.expectEqual(@as(u64, 1), runtime.health().written);
    try runtime.shutdown(.drain);
}

test "external runtime: accepted, filtered and deferred paths allocate nothing after init in both modes" {
    try linuxOnly();
    inline for (.{ .sync, .asynchronous }) |submission| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buffer: [128]u8 = undefined;
        var memory = try kron.MemorySink.init(testing.allocator, 128 * 1024);
        defer memory.deinit();
        var failing = testing.FailingAllocator.init(testing.allocator, .{});
        const runtime = try kron.Runtime.create(failing.allocator(), testing.io, .{
            .submission = submission,
            .journal = if (submission == .asynchronous) .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 8, .max_record_bytes = 1024 } else null,
            .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
            .redaction = &.{.{ .key = "password", .action = .mask }},
        });
        defer runtime.destroy();
        const initialized = failing.alloc_index;
        failing.fail_index = initialized;
        const log = runtime.scoped("no allocation").withBorrowed(.{ .service = "integration" });
        for (0..100) |index| {
            try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogf(.info, "event {d} {s}", .{ index, "snapshot" }, .{ .password = "hidden", .secret = kron.fields.secret("raw secret") }));
            try testing.expectEqual(kron.EmitResult.filtered, try log.tryEmit(.debug, "filtered", .{}));
        }
        try runtime.flush(.written);
        try runtime.shutdown(.drain);
        try testing.expectEqual(initialized, failing.alloc_index);
        try testing.expect(!failing.has_induced_failure);
        try testing.expectEqual(@as(usize, 100), memory.records);
    }
}
