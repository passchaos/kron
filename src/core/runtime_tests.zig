const std = @import("std");
const Runtime = @import("runtime.zig").Runtime;
const EmitResult = @import("logger.zig").EmitResult;
const MemorySink = @import("../sink/memory.zig").MemorySink;
test {
    _ = @import("runtime_admission_view_tests.zig");
}
const fields = @import("field.zig");

test "admission paused after old snapshot retains its already completed filter overlay" {
    const Context = struct {
        runtime: *Runtime,
        entered: std.atomic.Value(bool) = .init(false),
        proceed: std.atomic.Value(bool) = .init(false),
        result: ?EmitResult = null,
        failure: ?anyerror = null,
        fn pause(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.entered.store(true, .release);
            while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
        }
        fn run(self: *@This()) void {
            Runtime.TestingHooks.after_snapshot = pause;
            Runtime.TestingHooks.context = self;
            defer {
                Runtime.TestingHooks.after_snapshot = null;
                Runtime.TestingHooks.context = null;
            }
            self.result = self.runtime.scoped("hot").tryEmit(.trace, "overlap", .{}) catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    var old_bytes: [8192]u8 = undefined;
    var new_bytes: [8192]u8 = undefined;
    var old = MemorySink.initBuffer(&old_bytes);
    var current = MemorySink.initBuffer(&new_bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{ .filter = "trace", .routes = &.{.{ .name = "old", .sink = old.sink() }} });
    defer runtime.destroy();
    try runtime.reloadFilter("off");
    var context: Context = .{ .runtime = runtime };
    const producer = try std.Thread.spawn(.{}, Context.run, .{&context});
    var joined = false;
    defer if (!joined) producer.join();
    defer context.proceed.store(true, .release);
    const deadline = @import("control.zig").Deadline.after(std.testing.io, 5 * std.time.ns_per_s);
    while (!context.entered.load(.acquire)) {
        if (deadline.expired(std.testing.io)) return error.ProducerDidNotEnter;
        std.atomic.spinLoopHint();
    }
    _ = try runtime.replaceConfiguration(&.{.{ .name = "new", .sink = current.sink() }}, .{ .default_filter = "trace" });
    context.proceed.store(true, .release);
    producer.join();
    joined = true;
    if (context.failure) |err| return err;
    try std.testing.expectEqual(EmitResult.filtered, context.result.?);
    try std.testing.expectEqual(@as(usize, 0), old.records);
    try std.testing.expectEqual(EmitResult.accepted, try runtime.scoped("hot").tryEmit(.trace, "new transaction", .{}));
    try std.testing.expectEqual(@as(usize, 1), current.records);
}

test "warmed SPSC configuration and filter guards perform no shared reader or pending RMW" {
    const routes = @import("../config/routes.zig");
    const reload = @import("../config/reload.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/audit.journal", .{tmp.sub_path});
    var memory_bytes: [16 * 1024]u8 = undefined;
    var memory = MemorySink.initBuffer(&memory_bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 1024 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 8,
        .filter = "info",
        .routes = &.{.{ .name = "audit", .sink = memory.sink(), .recovery_identity = "audit" }},
    });
    defer runtime.destroy();
    const log = try runtime.attachThread(.{ .scope = "audit" });
    defer log.detach() catch {};
    // Hold the consumer at a live reservation gap, so accepted records cannot
    // perform legitimate consumer-side snapshot lookup during measurement.
    const registry = runtime.thread_registry.?;
    const journal = registry.getJournal(0);
    var gap = try journal.reserveSingleProducer(log.owner.producer_token);
    defer gap.abort();
    try std.testing.expect(log.enabled(.info));
    const readers = routes.TestingAudit.reader_acquisitions.load(.monotonic);
    const pending = routes.TestingAudit.global_pending_rmw.load(.monotonic);
    const refreshes = routes.TestingAudit.channel_refreshes.load(.monotonic);
    const filter_readers = reload.TestingAudit.reader_rmw.load(.monotonic);
    for (0..1000) |_| {
        try std.testing.expect(log.enabled(.info));
        try std.testing.expect(!log.enabled(.debug));
        try std.testing.expectEqual(EmitResult.filtered, try log.tryEmit(.debug, "disabled", .{}));
    }
    for (0..4) |_| try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.info, "accepted", .{}));
    try std.testing.expectEqual(readers, routes.TestingAudit.reader_acquisitions.load(.monotonic));
    try std.testing.expectEqual(pending, routes.TestingAudit.global_pending_rmw.load(.monotonic));
    try std.testing.expectEqual(refreshes, routes.TestingAudit.channel_refreshes.load(.monotonic));
    try std.testing.expectEqual(filter_readers, reload.TestingAudit.reader_rmw.load(.monotonic));
    gap.abort();
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(u64, 4), runtime.health().written);
}

test "runtime sync structured context, deferred format, redaction and reload" {
    var memory = try MemorySink.init(std.testing.allocator, 16 * 1024);
    defer memory.deinit();
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
        .filter = "info,http=debug",
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("http.server").withBorrowed(.{ .service = "api", .request = 1 });
    try std.testing.expectEqual(EmitResult.filtered, try log.tryEmit(.trace, "disabled", .{}));
    try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.debug, "accepted", .{ .request = 2, .password = "never written" }));
    try std.testing.expectEqual(EmitResult.accepted, try log.tryLogf(.info, "request {d} took {d}ns", .{ 7, 42 }, .{ .secret = fields.secret("hidden") }));
    try runtime.reloadFilter("off,http=warn");
    try std.testing.expectEqual(EmitResult.filtered, try log.tryEmit(.info, "disabled again", .{}));
    try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.warn, "warning", .{}));
    try runtime.flush(.written);
    try std.testing.expectError(error.UnsupportedDurability, runtime.flush(.durable));
    const output = memory.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "request 7 took 42ns") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "never written") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hidden") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[REDACTED]") != null);
    var lines = std.mem.tokenizeScalar(u8, output, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
        defer parsed.deinit();
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(u64, 3), runtime.health().accepted);
    try std.testing.expectEqual(@as(u64, 2), runtime.health().filtered);
    try runtime.shutdown(.drain);
    try runtime.shutdown(.drain);
    try std.testing.expectEqual(EmitResult.rejected_closing, try log.tryEmit(.fatal, "closed", .{}));
}

test "runtime route union and best effort isolation" {
    var bad_storage: [4096]u8 = undefined;
    var good_storage: [4096]u8 = undefined;
    var bad = MemorySink.initBuffer(&bad_storage);
    var good = MemorySink.initBuffer(&good_storage);
    bad.fail_after_records = 0;
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .filter = "off",
        .routes = &.{
            .{ .name = "bad", .sink = bad.sink(), .filter = "trace", .delivery = .best_effort },
            .{ .name = "good", .sink = good.sink(), .filter = "warn,http=debug" },
        },
    });
    defer runtime.destroy();
    const log = runtime.scoped("http.client");
    try std.testing.expect(log.enabled(.debug));
    try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.debug, "delivered", .{}));
    try std.testing.expectEqual(@as(usize, 1), good.records);
    try std.testing.expectEqual(@as(u64, 1), runtime.health().write_errors);
    try std.testing.expectEqual(error.InjectedWriteFailure, runtime.health().last_error.?);
}

test "runtime sync and filter allocate nothing after initialization" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var storage: [8192]u8 = undefined;
    var memory = MemorySink.initBuffer(&storage);
    const runtime = try Runtime.create(failing.allocator(), std.testing.io, .{
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    const initialized = failing.alloc_index;
    failing.fail_index = initialized;
    const log = runtime.scoped("test");
    try std.testing.expectEqual(EmitResult.accepted, try log.tryLogf(.info, "value {d}", .{10}, .{ .value = 10 }));
    try std.testing.expectEqual(EmitResult.filtered, try log.tryEmit(.debug, "filtered", .{}));
    try std.testing.expectEqual(initialized, failing.alloc_index);
}

test "runtime asynchronous journal drains and snapshots borrowed inputs" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/runtime.journal", .{temporary.sub_path});
    var memory = try MemorySink.init(std.testing.allocator, 256 * 1024);
    defer memory.deinit();
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 2048 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("async");
    var mutable = [_]u8{ 'o', 'r', 'i', 'g', 'i', 'n', 'a', 'l' };
    try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.info, "snapshot", .{ .value = mutable[0..] }));
    @memset(&mutable, 'x');
    for (0..100) |i| try std.testing.expectEqual(EmitResult.accepted, try log.tryLogf(.info, "event {d}", .{i}, .{ .index = i }));
    try runtime.flush(.written);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "original") != null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "xxxxxxxx") == null);
    try std.testing.expectEqual(@as(usize, 101), memory.records);
    try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    try std.testing.expectEqual(@as(u64, 101), runtime.health().written);
    try runtime.shutdown(.drain);
}

test "runtime SPSC attached logger uses copied generation and survives late detach" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/thread-runtime.journal", .{temporary.sub_path});
    var memory = try MemorySink.init(std.testing.allocator, 256 * 1024);
    defer memory.deinit();
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 2048 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 8,
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    var attached = try runtime.attachThread(.{ .scope = "thread.one" });
    const old = attached;
    try std.testing.expectEqual(EmitResult.accepted, try attached.tryLogf(.info, "thread event {d}", .{1}, .{}));
    try attached.detach();
    var reused = try runtime.attachThread(.{ .scope = "thread.two" });
    try std.testing.expectEqual(EmitResult.rejected_closing, try old.tryEmit(.info, "stale token", .{}));
    try std.testing.expectEqual(EmitResult.accepted, try reused.tryEmit(.info, "new generation", .{}));
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(usize, 2), memory.records);
    try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    try runtime.shutdown(.drain);
    try reused.detach();
    try std.testing.expectError(error.Closing, runtime.attachThread(.{ .scope = "closed" }));
}

test "runtime recovery refuses changed required route binding before acceptance" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/binding.journal", .{temporary.sub_path});
    var storage: [8192]u8 = undefined;
    var memory = MemorySink.initBuffer(&storage);
    memory.fail_after_records = 0;
    {
        const first = try Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = .asynchronous,
            .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 },
            .routes = &.{.{ .name = "audit", .sink = memory.sink(), .recovery_identity = "file-a" }},
        });
        defer first.destroy();
        try std.testing.expectEqual(EmitResult.accepted, try first.scoped("test").tryEmit(.info, "must remain", .{}));
        try std.testing.expectError(error.InjectedWriteFailure, first.flush(.written));
    }
    memory.fail_after_records = null;
    try std.testing.expectError(error.RecoveryRouteMismatch, Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "audit", .sink = memory.sink(), .recovery_identity = "file-b" }},
    }));
    const matched = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "audit", .sink = memory.sink(), .recovery_identity = "file-a" }},
    });
    defer matched.destroy();
    try matched.flush(.written);
    try std.testing.expectEqual(@as(usize, 1), memory.records);
}

test "typed producer clock skips callback dispatch without changing the pipeline" {
    const Fake = struct {
        calls: usize = 0,
        fn now(context: ?*anyopaque, _: std.Io) i64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            return 101;
        }
    };
    const Static = struct {
        pub inline fn realNow(_: std.Io) i64 {
            return 202;
        }
    };
    var fake: Fake = .{};
    var buffer: [8192]u8 = undefined;
    var memory = MemorySink.initBuffer(&buffer);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
        .clock = .{ .context = &fake, .real_now = Fake.now },
    });
    defer runtime.destroy();
    try std.testing.expectEqual(EmitResult.accepted, try runtime.scoped("dynamic").tryEmit(.info, "dynamic", .{}));
    const static_log = runtime.loggerWithClock(Static, "static").withBorrowed(.{ .context = true });
    try std.testing.expectEqual(EmitResult.accepted, try static_log.tryLogf(.info, "value {d}", .{3}, .{}));
    const no_clock = runtime.loggerWithClock(@import("../platform/static_clock.zig").ZeroClock, "zero");
    try std.testing.expectEqual(EmitResult.accepted, try no_clock.tryEmit(.info, "zero", .{}));
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "\"timestamp_ns\":202") != null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "\"timestamp_ns\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "value 3") != null);
}

test "runtime error hooks run outside delivery locks and reject logger recursion" {
    const HookState = struct {
        runtime: ?*Runtime = null,
        calls: usize = 0,
        lock_was_free: bool = false,
        recursive_result: ?EmitResult = null,

        fn hook(context: ?*anyopaque, _: @import("diagnostics.zig").ErrorEvent) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            const runtime = self.runtime.?;
            self.calls += 1;
            self.lock_was_free = runtime.delivery_mutex.tryLock();
            if (self.lock_was_free) runtime.delivery_mutex.unlock(runtime.io);
            self.recursive_result = runtime.scoped("hook").tryEmit(.err, "must not recurse", .{}) catch unreachable;
        }
    };
    var state: HookState = .{};
    var bad_buffer: [4096]u8 = undefined;
    var good_buffer: [4096]u8 = undefined;
    var bad = MemorySink.initBuffer(&bad_buffer);
    var good = MemorySink.initBuffer(&good_buffer);
    bad.fail_after_records = 0;
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .routes = &.{
            .{ .name = "bad", .sink = bad.sink(), .delivery = .best_effort },
            .{ .name = "good", .sink = good.sink() },
        },
        .diagnostics = .{ .hook = HookState.hook, .context = &state },
    });
    defer runtime.destroy();
    state.runtime = runtime;
    try std.testing.expectEqual(EmitResult.accepted, try runtime.scoped("test").tryEmit(.info, "delivered", .{}));
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    try std.testing.expect(state.lock_was_free);
    try std.testing.expectEqual(EmitResult.rejected_closing, state.recursive_result.?);
    try std.testing.expectEqual(@as(usize, 1), good.records);
}

test "sleeping SPSC worker wakes when shutdown observes the final channel admission end" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    const Context = struct {
        runtime: *Runtime,
        submitted: std.Io.Event = .unset,
        finish: std.Io.Event = .unset,
        failure: ?anyerror = null,

        fn producer(self: *@This()) void {
            self.run() catch |err| {
                self.failure = err;
                self.submitted.set(self.runtime.io);
            };
        }

        fn run(self: *@This()) !void {
            const log = try self.runtime.attachThread(.{ .scope = "last-admission" });
            defer log.detach() catch {};
            const admission = switch (log.owner.begin(.info, "ignored")) {
                .ready => |value| value,
                else => return error.UnexpectedAdmission,
            };
            defer log.owner.end();
            _ = try log.owner.submit(admission, .{ .level = .info, .scope = "ignored", .message = "last", .fields = &.{}, .timestamp_ns = 0 });
            self.submitted.set(self.runtime.io);
            self.finish.waitUncancelable(self.runtime.io);
        }

        fn shutdown(runtime: *Runtime) void {
            runtime.shutdown(.drain) catch unreachable;
        }
    };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/sleep-final.journal", .{temporary.sub_path});
    var storage: [4096]u8 = undefined;
    var memory = MemorySink.initBuffer(&storage);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .low_latency,
        .idle = .sleep,
        .journal = .{ .path = path, .capacity = 2, .max_record_bytes = 1024 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 2,
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    var context: Context = .{ .runtime = runtime };
    const producer = try std.Thread.spawn(.{}, Context.producer, .{&context});
    context.submitted.waitUncancelable(runtime.io);
    if (context.failure) |err| {
        producer.join();
        return err;
    }
    const deadline = std.Io.Clock.awake.now(runtime.io).nanoseconds + 2 * std.time.ns_per_s;
    while (!runtime.worker_sleeping.load(.seq_cst) or runtime.health().journal_pending != 0) {
        if (std.Io.Clock.awake.now(runtime.io).nanoseconds > deadline) {
            context.finish.set(runtime.io);
            producer.join();
            return error.WorkerDidNotSleep;
        }
        std.Thread.yield() catch {};
    }
    const shutdown = try std.Thread.spawn(.{}, Context.shutdown, .{runtime});
    while (runtime.state.load(.acquire) == .running) std.Thread.yield() catch {};
    // Closing wakes the worker; wait until it sleeps again while the final
    // producer still holds its channel admission, then release that producer.
    while (!runtime.worker_sleeping.load(.seq_cst)) std.Thread.yield() catch {};
    context.finish.set(runtime.io);
    producer.join();
    shutdown.join();
    try std.testing.expectEqual(@as(usize, 1), memory.records);
    try std.testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
}

test "runtime SPSC closing publication drains every successfully accepted event" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    const Context = struct {
        runtime: *Runtime,
        ready: std.atomic.Value(u32) = .init(0),
        start: std.Io.Event = .unset,
        first: std.Io.Event = .unset,
        accepted: [4]u64 = @splat(0),
        failures: [4]?anyerror = @splat(null),

        fn producer(self: *@This(), index: usize) void {
            const log = self.runtime.attachThread(.{ .scope = "closing-stress" }) catch |err| {
                self.failures[index] = err;
                _ = self.ready.fetchAdd(1, .release);
                self.first.set(self.runtime.io);
                return;
            };
            defer log.detach() catch |err| {
                self.failures[index] = err;
            };
            _ = self.ready.fetchAdd(1, .release);
            self.start.waitUncancelable(self.runtime.io);
            for (0..1000) |event| {
                const result = log.tryEmit(.info, "concurrent closing", .{ .producer = index, .index = event }) catch |err| {
                    self.failures[index] = err;
                    self.first.set(self.runtime.io);
                    return;
                };
                if (result == .accepted) {
                    self.accepted[index] += 1;
                    self.first.set(self.runtime.io);
                } else if (result != .rejected_closing) {
                    self.failures[index] = error.UnexpectedOutcome;
                    return;
                }
            }
        }
    };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/closing-stress.journal", .{temporary.sub_path});
    var memory = try MemorySink.init(std.testing.allocator, 2 * 1024 * 1024);
    defer memory.deinit();
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = path, .capacity = 16, .max_record_bytes = 1024 },
        .max_thread_channels = 4,
        .thread_channel_capacity = 16,
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    var context: Context = .{ .runtime = runtime };
    var threads: [4]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer {
        context.start.set(runtime.io);
        for (threads[0..spawned]) |thread| thread.join();
    }
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Context.producer, .{ &context, index });
        spawned += 1;
    }
    while (context.ready.load(.acquire) != threads.len) std.Thread.yield() catch {};
    context.start.set(runtime.io);
    context.first.waitUncancelable(runtime.io);
    try runtime.shutdown(.drain);
    for (threads) |thread| thread.join();
    spawned = 0;
    var accepted: u64 = 0;
    for (context.accepted, context.failures) |count, failure| {
        if (failure) |err| return err;
        accepted += count;
    }
    try std.testing.expect(accepted > 0);
    try std.testing.expectEqual(accepted, runtime.health().accepted);
    try std.testing.expectEqual(accepted, runtime.health().written);
    try std.testing.expectEqual(accepted, memory.records);
    try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
}

test "prepared runtime schema removes static capture bytes and keeps output self contained" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/prepared-runtime.journal", .{temporary.sub_path});
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var memory = try MemorySink.init(std.testing.allocator, 16 * 1024);
    defer memory.deinit();
    const runtime = try Runtime.create(allocator.allocator(), std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 4, .max_record_bytes = 1024, .schema_capacity = 4, .max_schema_bytes = 1024 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    const example: @import("event.zig").Event = .{
        .level = .info,
        .scope = "prepared.worker",
        .message = "request {d}",
        .message_template = true,
        .fields = &.{ fields.kv("status", @as(u16, 200)), fields.kv("password", "raw-placeholder") },
        .format_args = &.{fields.kv("0", @as(u64, 1))},
        .timestamp_ns = 0,
    };
    const binding = try runtime.prewarmSchema(example);
    const same = try runtime.prewarmSchema(example);
    try std.testing.expectEqual(binding.reference.id, same.reference.id);
    const log = try runtime.loggerWithSchema(binding);
    allocator.fail_index = allocator.alloc_index;
    const allocations = allocator.alloc_index;
    try std.testing.expectEqual(EmitResult.accepted, try log.tryLogf(.info, "request {d}", .{@as(u64, 42)}, .{ .status = @as(u16, 201), .password = "never capture this" }));
    try runtime.flush(.written);
    try std.testing.expectEqual(allocations, allocator.alloc_index);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "request 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "never capture this") == null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "[REDACTED]") != null);
    try std.testing.expectError(error.SchemaMismatch, log.tryLogf(.info, "different {d}", .{@as(u64, 42)}, .{ .status = @as(u16, 201), .password = "never capture this" }));
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(usize, 1), memory.records);
    try std.testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
}

test "prepared thread schema retains SPSC ownership and metadata across collector output" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/prepared-thread.journal", .{temporary.sub_path});
    var memory = try MemorySink.init(std.testing.allocator, 16 * 1024);
    defer memory.deinit();
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = path, .capacity = 4, .max_record_bytes = 1024, .schema_capacity = 4, .max_schema_bytes = 1024 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 4,
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    const attached = try runtime.attachThread(.{ .scope = "prepared.thread" });
    const binding = try runtime.prewarmThreadSchema(@intCast(attached.owner.control_index + 1), .{
        .level = .info,
        .scope = "prepared.thread",
        .message = "number {d}",
        .message_template = true,
        .fields = &.{fields.kv("count", @as(u64, 1))},
        .format_args = &.{fields.kv("0", @as(u64, 1))},
        .timestamp_ns = 0,
    });
    const prepared = try runtime.threadLoggerWithSchema(attached, binding);
    try std.testing.expectEqual(EmitResult.accepted, try prepared.tryLogf(.info, "number {d}", .{@as(u64, 99)}, .{ .count = @as(u64, 99) }));
    var scope_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings("prepared.thread", try prepared.copyScope(&scope_buffer));
    try runtime.flush(.written);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "number 99") != null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "prepared.thread") != null);
    try prepared.detach();
    try std.testing.expectEqual(EmitResult.rejected_closing, try attached.tryEmit(.info, "retired", .{}));
    try std.testing.expectEqual(@as(u64, 1), runtime.health().written);
}

test "same-format routes share exact encoded records while mixed formats keep their contracts" {
    var first_bytes: [8192]u8 = undefined;
    var second_bytes: [8192]u8 = undefined;
    var text_bytes: [8192]u8 = undefined;
    var first = MemorySink.initBuffer(&first_bytes);
    var second = MemorySink.initBuffer(&second_bytes);
    var text = MemorySink.initBuffer(&text_bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .routes = &.{
            .{ .name = "json-one", .sink = first.sink(), .format = .json },
            .{ .name = "text", .sink = text.sink(), .format = .text },
            .{ .name = "json-two", .sink = second.sink(), .format = .json },
        },
    });
    defer runtime.destroy();
    const log = runtime.scoped("fanout");
    _ = try log.tryLogf(.info, "request {d}", .{123}, .{ .status = @as(u16, 200) });
    _ = try log.tryEmit(.warn, "warning", .{ .flag = true });
    try runtime.flush(.written);
    try std.testing.expectEqualSlices(u8, first.written(), second.written());
    try std.testing.expectEqual(@as(usize, 2), first.records);
    try std.testing.expectEqual(@as(usize, 2), text.records);
    try std.testing.expect(std.mem.indexOf(u8, first.written(), "\"attributes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text.written(), "request 123") != null);
}

test "prepared binding definitions cannot relabel values and full fallback preserves shape checks" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/binding-shape.journal", .{temporary.sub_path});
    var memory_bytes: [8192]u8 = undefined;
    var memory = MemorySink.initBuffer(&memory_bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .overflow = .fallback_sync,
        .journal = .{ .path = path, .capacity = 2, .max_record_bytes = 1024, .schema_capacity = 4, .max_schema_bytes = 1024 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
    });
    defer runtime.destroy();
    var binding = try runtime.prewarmSchema(.{ .level = .info, .scope = "binding", .message = "event", .fields = &.{fields.kv("user_id", @as(u64, 1))}, .timestamp_ns = 0 });
    const other = try runtime.prewarmSchema(.{ .level = .info, .scope = "binding", .message = "event", .fields = &.{fields.kv("amount", @as(u64, 1))}, .timestamp_ns = 0 });
    binding.definition = other.definition;
    var log = try runtime.loggerWithSchema(binding);
    log.owner.binding.definition = other.definition; // The public value is not trusted at submission.
    try std.testing.expectError(error.SchemaMismatch, log.tryEmit(.info, "event", .{ .amount = @as(u64, 42) }));
    try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.info, "event", .{ .user_id = @as(u64, 42) }));
    try runtime.flush(.written);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "\"user_id\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "\"amount\"") == null);
    var first = try runtime.journal.?.reserve();
    var second = try runtime.journal.?.reserve();
    defer first.abort();
    defer second.abort();
    try std.testing.expectError(error.SchemaMismatch, log.tryEmit(.info, "event", .{ .amount = @as(u64, 99) }));
    try std.testing.expectEqual(@as(usize, 1), memory.records);
    first.abort();
    second.abort();
    try runtime.flush(.written);
}

test "comptime prepared format preserves optional masks and transforms redacted metadata" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/static-optional.journal", .{temporary.sub_path});
    var buffer: [8192]u8 = undefined;
    var memory = MemorySink.initBuffer(&buffer);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 4, .max_record_bytes = 1024, .schema_capacity = 1, .max_schema_bytes = 2048 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink(), .recovery_identity = "test-memory" }},
        .redaction = &.{.{ .key = "token", .action = .mask }},
    });
    defer runtime.destroy();
    const Args = struct { number: ?u64 };
    const Attributes = struct { value: ?i64, token: i64 };
    const binding = try runtime.prewarmFormat("optional", null, "number {[number]d}", Args, Attributes);
    const log = try runtime.loggerWithSchema(binding);
    _ = try log.tryLogf(.info, "number {[number]d}", Args{ .number = null }, Attributes{ .value = null, .token = 123 });
    _ = try log.tryLogf(.info, "number {[number]d}", Args{ .number = 42 }, Attributes{ .value = -3, .token = 456 });
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(usize, 2), memory.records);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "number null") != null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "number 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, memory.written(), "\"token\":\"[REDACTED]\"") != null);
    // Timestamp/session values can legitimately contain the same digits as a
    // secret. Inspect the attribute semantically rather than the whole line.
    var lines = std.mem.tokenizeScalar(u8, memory.written(), '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
        defer parsed.deinit();
        const attrs = parsed.value.object.get("attributes").?.object;
        try std.testing.expectEqualStrings("[REDACTED]", attrs.get("token").?.string);
        if (count == 0) {
            try std.testing.expect(attrs.get("value").? == .null);
        } else {
            try std.testing.expectEqual(@as(i64, -3), attrs.get("value").?.integer);
        }
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "new snapshot uses its complete baseline while bound filter publication is delayed" {
    const Writer = struct {
        runtime: *Runtime,
        route: @import("runtime_types.zig").RouteOptions,
        done: std.atomic.Value(bool) = .init(false),
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            _ = self.runtime.replaceConfiguration(&.{self.route}, .{ .default_filter = "off,hot=warn", .redaction = &.{.{ .key = "password", .action = .drop }} }) catch |err| {
                self.failure = err;
            };
            self.done.store(true, .release);
        }
    };
    var old_bytes: [8192]u8 = undefined;
    var new_bytes: [8192]u8 = undefined;
    var old = MemorySink.initBuffer(&old_bytes);
    var current = MemorySink.initBuffer(&new_bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{ .filter = "off,hot=debug", .routes = &.{.{ .name = "old", .sink = old.sink() }} });
    defer runtime.destroy();
    const filter: *@import("../config/reload.zig").DynamicFilter = @ptrCast(@alignCast(runtime.filter_handle));
    filter.writer_mutex.lockUncancelable(std.testing.io);
    var writer: Writer = .{ .runtime = runtime, .route = .{ .name = "new", .sink = current.sink() } };
    const thread = try std.Thread.spawn(.{}, Writer.run, .{&writer});
    defer thread.join();
    var locked = true;
    defer if (locked) filter.writer_mutex.unlock(std.testing.io);
    const deadline = @import("control.zig").Deadline.after(std.testing.io, 5 * std.time.ns_per_s);
    while (runtime.currentConfiguration().generation != 2) {
        if (writer.done.load(.acquire) or deadline.expired(std.testing.io)) return error.PublicationNotObserved;
        std.atomic.spinLoopHint();
    }
    try std.testing.expect(!writer.done.load(.acquire));
    const log = runtime.scoped("hot");
    try std.testing.expect(!log.enabled(.debug));
    try std.testing.expectEqual(EmitResult.filtered, try log.tryEmit(.debug, "old overlay must not leak", .{}));
    try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.warn, "complete baseline", .{ .password = "private" }));
    try std.testing.expectEqual(@as(usize, 0), old.records);
    try std.testing.expectEqual(@as(usize, 1), current.records);
    try std.testing.expect(std.mem.indexOf(u8, current.written(), "password") == null);
    try std.testing.expect(std.mem.indexOf(u8, current.written(), "\"config_generation\":2") != null);
    filter.writer_mutex.unlock(std.testing.io);
    locked = false;
}
