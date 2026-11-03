//! External consumers qualify the volatile and mapped async storage choices.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const testing = std.testing;

test "async storage: failed memory durable release and policy replacement preserve ownership" {
    const Release = struct {
        calls: usize = 0,
        fn release(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
        }
    };
    inline for (.{ false, true }) |single| {
        const options: @typeInfo(@TypeOf(kron.Journal.createMemory)).@"fn".params[2].type.? = .{ .path = "", .capacity = 4, .max_record_bytes = 128 };
        const journal = if (single) try kron.Journal.createMemorySingleProducer(testing.allocator, testing.io, options) else try kron.Journal.createMemory(testing.allocator, testing.io, options);
        defer journal.deinit();
        var reservation = if (single) try journal.reserveSingleProducer(try journal.singleProducerToken()) else try journal.reserve();
        @memcpy(reservation.buffer()[0..7], "payload");
        try reservation.commit(7);
        const record = (try journal.peekChecked()).?;
        const written = journal.writtenTarget();
        try testing.expectError(error.UnsupportedDurability, journal.releaseAfter(record, .durable));
        try testing.expectEqual(@as(usize, 1), journal.pending());
        try testing.expectEqual(record.sequence, (try journal.peekChecked()).?.sequence);
        try testing.expectEqual(written, journal.writtenTarget());
        try testing.expectEqual(@as(u64, 0), journal.durableReclaimedTarget());
        try journal.releaseAfter(record, .written);
        try testing.expectEqual(@as(usize, 0), journal.pending());
    }
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .submission = .asynchronous, .memory_queue = .{ .capacity = 4, .max_record_bytes = 1024 }, .routes = &.{.{ .name = "old", .sink = memory.sink() }} });
    defer runtime.destroy();
    const version = runtime.currentConfiguration();
    const generation = runtime.currentFilterGeneration();
    var owner: Release = .{};
    try testing.expectError(error.DurableReclaimRequiresMmap, runtime.replaceConfiguration(&.{.{ .name = "invalid", .sink = memory.sink(), .reclaim_after = .durable, .release = .{ .context = &owner, .release = Release.release } }}, .{ .default_filter = "off" }));
    try testing.expectEqualDeep(version, runtime.currentConfiguration());
    try testing.expectEqual(generation, runtime.currentFilterGeneration());
    try testing.expectEqual(@as(usize, 0), owner.calls);
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("still-valid").tryEmit(.info, "old policy", .{}));
    try runtime.flush(.written);
    try testing.expectEqual(@as(usize, 1), memory.records);
}

fn wait(event: *std.Io.Event) !void {
    const deadline = kron.Deadline.after(testing.io, 5 * std.time.ns_per_s);
    while (!event.isSet()) event.waitTimeout(testing.io, .{ .deadline = deadline.timestamp }) catch |err| {
        if (err != error.Timeout) return err;
        if (deadline.expired(testing.io) and !event.isSet()) return error.TestHandshakeTimeout;
    };
}

const NoFiles = struct {
    var calls: std.atomic.Value(u32) = .init(0);
    fn openDir(_: ?*anyopaque, _: std.Io.Dir, _: []const u8, _: std.Io.Dir.OpenOptions) std.Io.Dir.OpenError!std.Io.Dir {
        _ = calls.fetchAdd(1, .monotonic);
        return error.AccessDenied;
    }
    fn openFile(_: ?*anyopaque, _: std.Io.Dir, _: []const u8, _: std.Io.Dir.OpenFileOptions) std.Io.File.OpenError!std.Io.File {
        _ = calls.fetchAdd(1, .monotonic);
        return error.AccessDenied;
    }
    fn createFile(_: ?*anyopaque, _: std.Io.Dir, _: []const u8, _: std.Io.Dir.CreateFileOptions) std.Io.File.OpenError!std.Io.File {
        _ = calls.fetchAdd(1, .monotonic);
        return error.AccessDenied;
    }
    fn install(vtable: *std.Io.VTable) std.Io {
        calls.store(0, .release);
        vtable.* = testing.io.vtable.*;
        vtable.dirOpenDir = openDir;
        vtable.dirOpenFile = openFile;
        vtable.dirCreateFile = createFile;
        return .{ .userdata = testing.io.userdata, .vtable = vtable };
    }
};

test "async storage: memory shared and SPSC copy borrowed inputs and retain old configuration without file opens" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var vtable: std.Io.VTable = undefined;
        const io = NoFiles.install(&vtable);
        var old_bytes: [16 * 1024]u8 = undefined;
        var new_bytes: [16 * 1024]u8 = undefined;
        var old = kron.MemorySink.initBuffer(&old_bytes);
        var current = kron.MemorySink.initBuffer(&new_bytes);
        const runtime = try kron.Runtime.create(testing.allocator, io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 8, .max_record_bytes = 4096 },
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 8,
            .routes = &.{.{ .name = "output", .sink = old.sink() }},
            .redaction = &.{.{ .key = "password", .action = .mask }},
        });
        defer runtime.destroy();
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "memory.copy" }) else runtime.scoped("memory.copy");
        defer if (submission == .low_latency) log.detach() catch {};
        const queue = if (submission == .low_latency) log.owner.producer_token.journal else runtime.journal.?;
        var gap = if (submission == .low_latency) try queue.reserveSingleProducer(log.owner.producer_token) else try queue.reserve();
        defer gap.abort();
        var value = "original input".*;
        const group = [_]kron.Field{ kron.kv("password", "raw-password"), kron.kv("value", value[0..]) };
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogf(.info, "before {s}", .{value[0..]}, .{ .group = kron.group(&group), .secret = kron.secret("raw-secret") }));
        @memset(&value, 'x');
        const version = try runtime.replaceConfiguration(&.{.{ .name = "output", .sink = current.sink() }}, .{ .redaction = &.{.{ .key = "token", .action = .drop }} });
        try testing.expectEqual(@as(u64, 2), version.generation);
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "after replacement", .{ .token = "raw-token", .kept = true }));
        gap.abort();
        try runtime.flush(.written);
        try testing.expectEqual(@as(usize, 1), old.records);
        try testing.expectEqual(@as(usize, 1), current.records);
        try testing.expect(std.mem.indexOf(u8, old.written(), "original input") != null);
        try testing.expect(std.mem.indexOf(u8, old.written(), "xxxxxxxxxxxxxx") == null);
        try testing.expect(std.mem.indexOf(u8, old.written(), "raw-password") == null);
        try testing.expect(std.mem.indexOf(u8, old.written(), "raw-secret") == null);
        try testing.expect(std.mem.indexOf(u8, old.written(), "[REDACTED]") != null);
        try testing.expect(std.mem.indexOf(u8, current.written(), "raw-token") == null);
        try testing.expectEqual(.memory, runtime.queueStorage());
        try testing.expectEqual(.memory, runtime.health().queue_storage);
        try testing.expect(runtime.health().queue_reserved_bytes > 0);
        try testing.expectEqual(@as(usize, 0), runtime.health().journal_reserved_bytes);
        try testing.expectEqual(@as(u64, 2), runtime.health().written);
        try runtime.shutdown(.drain);
        try testing.expectEqual(@as(u32, 0), NoFiles.calls.load(.acquire));
    }
}

test "async storage: preallocated memory channels and hot logging allocate nothing after runtime init" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var bytes: [512 * 1024]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&bytes);
        var failing = testing.FailingAllocator.init(testing.allocator, .{});
        const runtime = try kron.Runtime.create(failing.allocator(), testing.io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 8, .max_record_bytes = 2048 },
            .max_thread_channels = if (submission == .low_latency) 2 else 0,
            .thread_channel_capacity = 8,
            .routes = &.{.{ .name = "output", .sink = memory.sink() }},
        });
        defer runtime.destroy();
        const initialized = failing.alloc_index;
        failing.fail_index = initialized;
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "noalloc" }) else runtime.scoped("noalloc");
        defer if (submission == .low_latency) log.detach() catch {};
        for (0..100) |index| {
            try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogf(.info, "memory {d}", .{index}, .{ .index = index, .secret = kron.secret("not captured") }));
            try testing.expectEqual(kron.EmitResult.filtered, try log.tryEmit(.debug, "filtered", .{}));
        }
        try runtime.flush(.written);
        try testing.expectEqual(initialized, failing.alloc_index);
        try testing.expect(!failing.has_induced_failure);
        try testing.expectEqual(@as(usize, 100), memory.records);
        try testing.expectEqual(@as(u64, 100), runtime.health().written);
        try runtime.shutdown(.drain);
    }
}

const BlockObserver = struct {
    var target: std.atomic.Value(usize) = .init(0);
    var entered: std.Io.Event = .unset;
    fn observe(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
        if (@intFromPtr(ptr) == target.load(.acquire)) entered.set(testing.io);
        testing.io.vtable.futexWaitUncancelable(userdata, ptr, expected);
    }
};

const ClosingCalls = struct {
    runtime: *kron.Runtime,
    result: ?kron.EmitResult = null,
    producer_error: ?anyerror = null,
    shutdown_error: ?anyerror = null,
    producer_done: std.Io.Event = .unset,
    shutdown_done: std.Io.Event = .unset,
    fn producer(self: *ClosingCalls) void {
        defer self.producer_done.set(testing.io);
        self.result = self.runtime.scoped("blocking").tryEmit(.info, "blocked", .{}) catch |err| {
            self.producer_error = err;
            return;
        };
    }
    fn shutdown(self: *ClosingCalls) void {
        defer self.shutdown_done.set(testing.io);
        self.runtime.shutdown(.drain) catch |err| {
            self.shutdown_error = err;
        };
    }
};

test "async storage: bounded memory drops full records and shutdown wakes a blocked producer" {
    var bytes: [4096]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    var vtable = testing.io.vtable.*;
    vtable.futexWaitUncancelable = BlockObserver.observe;
    const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
    const runtime = try kron.Runtime.create(testing.allocator, io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 2, .max_record_bytes = 512 },
        .overflow = .drop_newest,
        .routes = &.{.{ .name = "output", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    BlockObserver.entered = .unset;
    BlockObserver.target.store(@intFromPtr(&runtime.progress_epoch.raw), .release);
    defer BlockObserver.target.store(0, .release);
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("capacity").tryEmit(.info, "kept", .{}));
    for (0..20) |_| try testing.expectEqual(kron.EmitResult.dropped_full, try runtime.scoped("capacity").tryEmit(.info, "dropped", .{}));
    try testing.expectEqual(@as(u64, 20), runtime.health().dropped_full);
    runtime.overflow = .block;
    var calls: ClosingCalls = .{ .runtime = runtime };
    const producer_thread = try std.Thread.spawn(.{}, ClosingCalls.producer, .{&calls});
    var shutdown_thread: ?std.Thread = null;
    defer {
        gap.abort();
        _ = runtime.wake_epoch.fetchAdd(1, .seq_cst);
        io.futexWake(u32, &runtime.wake_epoch.raw, std.math.maxInt(u32));
        _ = runtime.progress_epoch.fetchAdd(1, .release);
        io.futexWake(u32, &runtime.progress_epoch.raw, std.math.maxInt(u32));
        producer_thread.join();
        if (shutdown_thread) |thread| thread.join();
    }
    try wait(&BlockObserver.entered);
    try testing.expect(!calls.producer_done.isSet());
    shutdown_thread = try std.Thread.spawn(.{}, ClosingCalls.shutdown, .{&calls});
    try wait(&calls.producer_done);
    gap.abort();
    try runtime.flush(.drain);
    try wait(&calls.shutdown_done);
    if (calls.producer_error) |err| return err;
    if (calls.shutdown_error) |err| return err;
    try testing.expectEqual(kron.EmitResult.rejected_closing, calls.result.?);
    try testing.expectEqual(@as(u64, 1), runtime.health().written);
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    try testing.expectEqual(.closed, runtime.health().state);
}

test "async storage: queue choices are explicit and mmap cannot be combined with memory" {
    var bytes: [4096]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const routes = &.{kron.RouteOptions{ .name = "output", .sink = memory.sink(), .recovery_identity = "storage-test" }};
    try testing.expectError(error.ConflictingQueueStorage, kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = "must-not-create.journal", .capacity = 2, .max_record_bytes = 512 },
        .memory_queue = .{ .capacity = 2, .max_record_bytes = 512 },
        .routes = routes,
    }));
    const sync_runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .routes = routes });
    defer sync_runtime.destroy();
    try testing.expectEqual(.none, sync_runtime.queueStorage());
    try testing.expectEqual(@as(usize, 0), sync_runtime.health().queue_reserved_bytes);
    if (builtin.os.tag == .linux) {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_bytes: [128]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/mapped.journal", .{tmp.sub_path});
        const mapped = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = .asynchronous,
            .journal = .{ .path = path, .capacity = 2, .max_record_bytes = 512 },
            .routes = routes,
        });
        defer mapped.destroy();
        try testing.expectEqual(.mmap, mapped.queueStorage());
        try testing.expect(mapped.health().journal_reserved_bytes > 0);
        try testing.expectEqual(mapped.health().queue_reserved_bytes, mapped.health().journal_reserved_bytes);
    }
}

test "async storage: memory cannot acknowledge durable reclaim but can flush a file destination durably" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/output.jsonl", .{tmp.sub_path});
    const file = try kron.FileSink.create(testing.allocator, testing.io, .{ .path = path, .backend = .portable, .buffer_bytes = 8192 });
    defer file.deinit();
    try testing.expectError(error.DurableReclaimRequiresMmap, kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 4, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "file", .sink = file.sink(), .reclaim_after = .durable }},
    }));
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 4, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "file", .sink = file.sink() }},
    });
    defer runtime.destroy();
    try testing.expectError(error.UnsupportedDurability, runtime.journal.?.sync());
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("durable.output").tryEmit(.info, "file is durable; capture remains volatile", .{}));
    try runtime.flush(.durable);
    try testing.expectEqual(@as(u64, 0), runtime.journal.?.durableReclaimedTarget());
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_reserved_bytes);
    const output = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(8192));
    defer testing.allocator.free(output);
    try testing.expect(std.mem.indexOf(u8, output, "file is durable; capture remains volatile") != null);
}

test "async storage: memory schema prewarm is ready without persistence and both frontends emit references" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var vtable: std.Io.VTable = undefined;
        const io = NoFiles.install(&vtable);
        var bytes: [8192]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&bytes);
        const runtime = try kron.Runtime.create(testing.allocator, io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 4, .max_record_bytes = 2048, .schema_capacity = 4, .max_schema_bytes = 4096 },
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 4,
            .routes = &.{.{ .name = "output", .sink = memory.sink() }},
        });
        defer runtime.destroy();
        const base = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "schema.memory" }) else runtime.scoped("schema.memory");
        defer if (submission == .low_latency) base.detach() catch {};
        const shape: kron.Event = .{
            .level = .info,
            .scope = "schema.memory",
            .message = "value {d}",
            .message_template = true,
            .fields = &.{kron.kv("secret", kron.secret("raw secret"))},
            .format_args = &.{kron.kv("0", @as(usize, 1))},
            .timestamp_ns = 0,
        };
        const binding = if (submission == .low_latency) try runtime.prewarmThreadSchema(@intCast(base.owner.control_index + 1), shape) else try runtime.prewarmSchema(shape);
        const ready = try binding.journal.resolveReadySchema(binding.reference);
        try testing.expectEqualStrings("schema.memory", ready.scope);
        try testing.expectError(error.UnsupportedDurability, binding.journal.sync());
        const log = if (submission == .low_latency) try runtime.threadLoggerWithSchema(base, binding) else try runtime.loggerWithSchema(binding);
        var gap = if (submission == .low_latency) try binding.journal.reserveSingleProducer(base.owner.producer_token) else try binding.journal.reserve();
        defer gap.abort();
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogf(.info, "value {d}", .{@as(usize, 42)}, .{ .secret = kron.secret("raw secret") }));
        gap.abort();
        try runtime.flush(.written);
        try testing.expectEqual(@as(usize, 1), memory.records);
        try testing.expect(std.mem.indexOf(u8, memory.written(), "value 42") != null);
        try testing.expect(std.mem.indexOf(u8, memory.written(), "raw secret") == null);
        try testing.expectEqual(@as(u64, 0), binding.journal.durableReclaimedTarget());
        try runtime.shutdown(.drain);
        try testing.expectEqual(@as(u32, 0), NoFiles.calls.load(.acquire));
    }
}

const ConcurrentProducer = struct {
    runtime: *kron.Runtime,
    id: usize,
    records: usize,
    gate: *std.atomic.Value(bool),
    accepted: usize = 0,
    failure: ?anyerror = null,

    fn run(self: *@This()) void {
        while (!self.gate.load(.acquire)) std.atomic.spinLoopHint();
        const log = self.runtime.scoped("concurrent");
        for (0..self.records) |index| {
            const result = log.tryEmit(.info, "producer", .{ .producer = self.id, .index = index }) catch |err| {
                self.failure = err;
                return;
            };
            if (result != .accepted) {
                self.failure = error.RecordRejected;
                return;
            }
            self.accepted += 1;
        }
    }
};

test "async storage: concurrent shared producers deliver every accepted record" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const producer_count = 4;
    const per_producer = 250;
    const total = producer_count * per_producer;
    var round: usize = 0;
    while (round < 2) : (round += 1) {
        var bytes: [512 * 1024]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&bytes);
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = .asynchronous,
            .memory_queue = .{ .capacity = 64, .max_record_bytes = 512 },
            .overflow = .block,
            .consumer_batches_per_queue = 4,
            .routes = &.{.{ .name = "output", .sink = memory.sink() }},
        });
        defer runtime.destroy();
        var gate: std.atomic.Value(bool) = .init(false);
        var workers: [producer_count]ConcurrentProducer = undefined;
        var threads: [producer_count]std.Thread = undefined;
        for (&workers, 0..) |*worker, index| {
            worker.* = .{ .runtime = runtime, .id = index, .records = per_producer, .gate = &gate };
            threads[index] = try std.Thread.spawn(.{}, ConcurrentProducer.run, .{worker});
        }
        gate.store(true, .release);
        for (&threads) |thread| thread.join();
        for (&workers) |*worker| if (worker.failure) |err| return err;
        try runtime.flush(.written);
        try runtime.shutdown(.drain);
        const health = runtime.health();
        try testing.expectEqual(@as(u64, total), health.accepted);
        try testing.expectEqual(@as(u64, total), health.written);
        try testing.expectEqual(@as(usize, 0), health.journal_pending);
        try testing.expectEqual(total, memory.records);
    }
}

const ClosingProducer = struct {
    runtime: *kron.Runtime,
    id: usize,
    accepted: usize = 0,
    rejected: usize = 0,
    failure: ?anyerror = null,

    fn run(self: *@This()) void {
        while (true) {
            const result = self.runtime.scoped("closing-concurrent").tryEmit(.info, "producer", .{ .producer = self.id, .index = self.accepted }) catch |err| {
                self.failure = err;
                return;
            };
            switch (result) {
                .accepted => self.accepted += 1,
                .rejected_closing => {
                    self.rejected += 1;
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

test "async storage: shutdown drains accepted records and rejects concurrent producers" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const producer_count = 4;
    var round: usize = 0;
    while (round < 2) : (round += 1) {
        var bytes: [1024 * 1024]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&bytes);
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = .asynchronous,
            .memory_queue = .{ .capacity = 64, .max_record_bytes = 512 },
            .overflow = .block,
            .consumer_batches_per_queue = 4,
            .routes = &.{.{ .name = "output", .sink = memory.sink() }},
        });
        defer runtime.destroy();
        var workers: [producer_count]ClosingProducer = undefined;
        var threads: [producer_count]std.Thread = undefined;
        for (&workers, 0..) |*worker, index| {
            worker.* = .{ .runtime = runtime, .id = index };
            threads[index] = try std.Thread.spawn(.{}, ClosingProducer.run, .{worker});
        }
        var spins: usize = 0;
        while (runtime.health().accepted == 0 and spins < 10_000_000) : (spins += 1) std.atomic.spinLoopHint();
        try runtime.shutdown(.drain);
        for (&threads) |thread| thread.join();
        var accepted: u64 = 0;
        var rejected: u64 = 0;
        for (&workers) |*worker| {
            if (worker.failure) |err| return err;
            accepted += worker.accepted;
            rejected += worker.rejected;
        }
        const health = runtime.health();
        try testing.expectEqual(accepted, health.accepted);
        try testing.expectEqual(health.accepted, health.written);
        try testing.expectEqual(@as(usize, 0), health.journal_pending);
        try testing.expectEqual(@as(usize, @intCast(health.written)), memory.records);
        try testing.expectEqual(.closed, health.state);
        try testing.expect(rejected != 0);
    }
}

test "async storage: concurrent shared producers drain an mmap journal and reopen cleanly" {
    if (builtin.single_threaded) return error.SkipZigTest;
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_bytes: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/concurrent.journal", .{tmp.sub_path});
    const producer_count = 4;
    const per_producer = 100;
    const total = producer_count * per_producer;
    var bytes: [512 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 64, .max_record_bytes = 512, .recover = true },
        .overflow = .block,
        .consumer_batches_per_queue = 4,
        .routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "concurrent-mmap" }},
    });
    var live = true;
    defer if (live) runtime.destroy();
    var gate: std.atomic.Value(bool) = .init(false);
    var workers: [producer_count]ConcurrentProducer = undefined;
    var threads: [producer_count]std.Thread = undefined;
    for (&workers, 0..) |*worker, index| {
        worker.* = .{ .runtime = runtime, .id = index, .records = per_producer, .gate = &gate };
        threads[index] = try std.Thread.spawn(.{}, ConcurrentProducer.run, .{worker});
    }
    gate.store(true, .release);
    for (&threads) |thread| thread.join();
    for (&workers) |*worker| if (worker.failure) |err| return err;
    try runtime.flush(.written);
    try runtime.shutdown(.drain);
    const health = runtime.health();
    try testing.expectEqual(@as(u64, total), health.accepted);
    try testing.expectEqual(@as(u64, total), health.written);
    try testing.expectEqual(@as(usize, 0), health.journal_pending);
    try testing.expectEqual(total, memory.records);
    runtime.destroy();
    live = false;
    const reopened = try kron.Journal.create(testing.allocator, testing.io, .{ .path = path, .capacity = 64, .max_record_bytes = 512, .recover = true });
    defer reopened.deinit();
    try testing.expectEqual(@as(usize, 0), reopened.pending());
    try testing.expect((try reopened.peekChecked()) == null);
}
