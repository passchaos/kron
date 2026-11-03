const std = @import("std");
const kron = @import("kron");
const testing = std.testing;

const FinalSyncSink = struct {
    memory: kron.MemorySink,
    sync_error: ?anyerror = null,
    releases: usize = 0,
    sync_calls: usize = 0,
    fn cast(raw: *anyopaque) *@This() {
        return @ptrCast(@alignCast(raw));
    }
    fn write(raw: *anyopaque, bytes: []const u8) anyerror!void {
        try cast(raw).memory.writeRecord(bytes);
    }
    fn flush(raw: *anyopaque) anyerror!void {
        try cast(raw).memory.flush();
    }
    fn sync(raw: *anyopaque) anyerror!void {
        const self = cast(raw);
        self.sync_calls += 1;
        if (self.sync_error) |err| return err;
    }
    fn release(raw: *anyopaque) void {
        cast(raw).releases += 1;
    }
    fn sink(self: *@This()) kron.Sink {
        return .{ .context = self, .vtable = &.{ .writeRecord = write, .flush = flush, .sync = sync }, .supports_durable = true };
    }
    fn route(self: *@This(), name: []const u8) kron.RouteOptions {
        return .{ .name = name, .sink = self.sink(), .release = .{ .context = self, .release = release } };
    }
};

test "retired written configuration is collected when extra durability becomes unavailable" {
    var old_bytes: [8192]u8 = undefined;
    var next_bytes: [8192]u8 = undefined;
    var old: FinalSyncSink = .{ .memory = kron.MemorySink.initBuffer(&old_bytes), .sync_error = error.UnsupportedDurability };
    var next: FinalSyncSink = .{ .memory = kron.MemorySink.initBuffer(&next_bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .configuration_slots = 2, .routes = &.{old.route("old")} });
    defer runtime.destroy();
    const old_version = runtime.currentConfiguration();
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("collect").tryEmit(.info, "written", .{}));
    _ = try runtime.replaceConfiguration(&.{next.route("new")}, .{});
    try testing.expect(runtime.historical_durable_supported.load(.acquire));
    try testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 1), old.releases);
    try testing.expectEqual(@as(usize, 1), old.sync_calls);
    try testing.expect(!runtime.configurationReadyToCollect(old_version));
    try testing.expectError(error.UnsupportedDurability, runtime.flush(.durable));
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("collect").tryEmit(.info, "new policy", .{}));
}

test "real retired sync I/O failure preserves the configuration lease for retry" {
    var old_bytes: [8192]u8 = undefined;
    var next_bytes: [8192]u8 = undefined;
    var old: FinalSyncSink = .{ .memory = kron.MemorySink.initBuffer(&old_bytes), .sync_error = error.InputOutput };
    var next: FinalSyncSink = .{ .memory = kron.MemorySink.initBuffer(&next_bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .configuration_slots = 2, .routes = &.{old.route("old")} });
    defer runtime.destroy();
    const old_version = runtime.currentConfiguration();
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("collect").tryEmit(.info, "written", .{}));
    _ = try runtime.replaceConfiguration(&.{next.route("new")}, .{});
    try testing.expectError(error.InputOutput, runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 0), old.releases);
    try testing.expect(runtime.configurationReadyToCollect(old_version));
    try testing.expect(runtime.historical_durable_supported.load(.acquire));
    old.sync_error = null;
    try testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 1), old.releases);
    try testing.expectEqual(@as(usize, 2), old.sync_calls);
}

fn journalOptions(tmp: *const testing.TmpDir, path: []u8) !@import("kron").RuntimeOptions {
    const name = try std.fmt.bufPrint(path, ".zig-cache/tmp/{s}/configuration.journal", .{tmp.sub_path});
    return .{ .routes = &.{}, .submission = .asynchronous, .journal = .{ .path = name, .capacity = 8, .max_record_bytes = 4096 } };
}

const LeaseState = struct {
    runtime: ?*kron.Runtime = null,
    memory: *kron.MemorySink,
    released: usize = 0,
    lock_free: bool = true,

    fn release(context: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(context));
        self.released += 1;
        if (self.runtime) |runtime| {
            const delivery_free = runtime.delivery_mutex.tryLock();
            if (delivery_free) runtime.delivery_mutex.unlock(runtime.io);
            const configuration_free = runtime.configuration_mutex.tryLock();
            if (configuration_free) runtime.configuration_mutex.unlock(runtime.io);
            self.lock_free = self.lock_free and delivery_free and configuration_free;
        }
    }

    fn route(self: *@This(), identity: []const u8) kron.RouteOptions {
        return .{ .name = "output", .sink = self.memory.sink(), .recovery_identity = identity, .release = .{ .context = self, .release = release } };
    }
};

test "route replacement keeps queued old events on old targets and releases leases after acknowledgement" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    var old_bytes: [16 * 1024]u8 = undefined;
    var new_bytes: [16 * 1024]u8 = undefined;
    var old = kron.MemorySink.initBuffer(&old_bytes);
    var current = kron.MemorySink.initBuffer(&new_bytes);
    var old_lease: LeaseState = .{ .memory = &old };
    var options = try journalOptions(&tmp, &path);
    options.routes = &.{old_lease.route("old-output")};
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, options);
    defer runtime.destroy();
    old_lease.runtime = runtime;
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    const log = runtime.scoped("hot");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "old event", .{ .version = @as(u8, 1) }));
    const version = try runtime.replaceConfiguration(&.{.{ .name = "output", .sink = current.sink(), .recovery_identity = "new-output" }}, .{});
    try testing.expectEqual(@as(u64, 2), version.generation);
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "new event", .{ .version = @as(u8, 2) }));
    try testing.expectEqual(@as(usize, 0), try runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 0), old_lease.released);
    gap.abort();
    try runtime.flush(.written);
    try testing.expectEqual(@as(usize, 1), old.records);
    try testing.expectEqual(@as(usize, 1), current.records);
    try testing.expect(std.mem.indexOf(u8, old.written(), "old event") != null);
    try testing.expect(std.mem.indexOf(u8, old.written(), "new event") == null);
    try testing.expect(std.mem.indexOf(u8, current.written(), "new event") != null);
    try testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 1), old_lease.released);
    try testing.expect(old_lease.lock_free);
}

test "an admitted producer retains the old policy while new scopes use the atomic replacement" {
    const Replace = struct {
        runtime: *kron.Runtime,
        next: kron.RouteOptions,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            _ = self.runtime.replaceConfiguration(&.{self.next}, .{
                .default_filter = "off,hot=debug",
                .redaction = &.{.{ .key = "token", .action = .drop }},
            }) catch |err| {
                self.failure = err;
            };
        }
    };
    var first_bytes: [8192]u8 = undefined;
    var second_bytes: [8192]u8 = undefined;
    var first = kron.MemorySink.initBuffer(&first_bytes);
    var second = kron.MemorySink.initBuffer(&second_bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "output", .sink = first.sink() }},
        .redaction = &.{.{ .key = "token", .action = .mask }},
    });
    defer runtime.destroy();
    const admission = switch (runtime.begin(.info, "hot")) {
        .ready => |value| value,
        else => return error.UnexpectedAdmission,
    };
    var replacement: Replace = .{ .runtime = runtime, .next = .{ .name = "output", .sink = second.sink() } };
    const thread = try std.Thread.spawn(.{}, Replace.run, .{&replacement});
    thread.join();
    if (replacement.failure) |err| {
        runtime.end();
        return err;
    }
    _ = runtime.submit(admission, .{ .level = .info, .scope = "hot", .message = "old admitted", .fields = &.{kron.kv("token", "old-secret")}, .timestamp_ns = 0 }) catch |err| {
        runtime.end();
        return err;
    };
    runtime.end();
    const log = runtime.scoped("hot");
    try testing.expect(log.enabled(.debug));
    _ = try log.tryEmit(.debug, "new policy", .{ .token = "new-secret", .visible = true });
    try testing.expectEqual(kron.EmitResult.filtered, try runtime.scoped("other").tryEmit(.fatal, "off", .{}));
    try testing.expect(std.mem.indexOf(u8, first.written(), "[REDACTED]") != null);
    try testing.expect(std.mem.indexOf(u8, first.written(), "old-secret") == null);
    try testing.expect(std.mem.indexOf(u8, second.written(), "\"token\"") == null);
    try testing.expect(std.mem.indexOf(u8, second.written(), "new-secret") == null);
    try testing.expectEqual(@as(usize, 1), first.records);
    try testing.expectEqual(@as(usize, 1), second.records);
}

test "configuration capacity and failed validation never take ownership of unpublished sinks" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    var buffers: [3][8192]u8 = undefined;
    var memories = [_]kron.MemorySink{ kron.MemorySink.initBuffer(&buffers[0]), kron.MemorySink.initBuffer(&buffers[1]), kron.MemorySink.initBuffer(&buffers[2]) };
    var leases = [_]LeaseState{ .{ .memory = &memories[0] }, .{ .memory = &memories[1] }, .{ .memory = &memories[2] } };
    var options = try journalOptions(&tmp, &path);
    options.configuration_slots = 2;
    options.routes = &.{leases[0].route("one")};
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, options);
    defer runtime.destroy();
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    _ = try runtime.scoped("capacity").tryEmit(.info, "held", .{});
    const version = try runtime.replaceConfiguration(&.{leases[1].route("two")}, .{});
    try testing.expectError(error.ConfigSlotsExhausted, runtime.replaceConfiguration(&.{leases[2].route("three")}, .{}));
    try testing.expectEqual(@as(usize, 0), leases[2].released);
    try testing.expectEqualDeep(version, runtime.currentConfiguration());
    try testing.expectError(error.InvalidLevel, runtime.replaceConfiguration(&.{leases[2].route("three")}, .{ .default_filter = "nonsense" }));
    try testing.expectEqual(@as(usize, 0), leases[2].released);
    gap.abort();
    try runtime.flush(.written);
    _ = try runtime.collectConfigurations();
    _ = try runtime.replaceConfiguration(&.{leases[2].route("three")}, .{});
    try testing.expectEqual(@as(usize, 1), leases[0].released);
}

test "recovery requires every historical route generation and replays to explicitly bound old targets" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    var old_buffer: [8192]u8 = undefined;
    var new_buffer: [8192]u8 = undefined;
    var old = kron.MemorySink.initBuffer(&old_buffer);
    var current = kron.MemorySink.initBuffer(&new_buffer);
    old.fail_after_records = 0;
    const old_route: kron.RouteOptions = .{ .name = "output", .sink = old.sink(), .recovery_identity = "recover-old" };
    const new_route: kron.RouteOptions = .{ .name = "output", .sink = current.sink(), .recovery_identity = "recover-new" };
    var options = try journalOptions(&tmp, &path);
    options.routes = &.{old_route};
    {
        const first = try kron.Runtime.create(testing.allocator, testing.io, options);
        defer first.destroy();
        var gap = try first.journal.?.reserve();
        defer gap.abort();
        _ = try first.scoped("recover").tryEmit(.info, "old retained", .{});
        _ = try first.replaceConfiguration(&.{new_route}, .{});
        _ = try first.scoped("recover").tryEmit(.info, "new retained", .{});
        gap.abort();
        try testing.expectError(error.InjectedWriteFailure, first.flush(.written));
        try testing.expectEqual(@as(usize, 2), first.health().journal_pending);
    }
    old.fail_after_records = null;
    options.routes = &.{new_route};
    options.initial_route_generation = 2;
    try testing.expectError(error.RecoveryRouteMismatch, kron.Runtime.create(testing.allocator, testing.io, options));
    options.recovery_versions = &.{.{ .generation = 1, .routes = &.{old_route} }};
    const recovered = try kron.Runtime.create(testing.allocator, testing.io, options);
    defer recovered.destroy();
    try recovered.flush(.written);
    try testing.expectEqual(@as(usize, 1), old.records);
    try testing.expectEqual(@as(usize, 1), current.records);
    try testing.expect(std.mem.indexOf(u8, old.written(), "old retained") != null);
    try testing.expect(std.mem.indexOf(u8, current.written(), "new retained") != null);
}

test "nested redaction runs before journal acceptance for fields and deferred arguments" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    var output_bytes: [16 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&output_bytes);
    var options = try journalOptions(&tmp, &path);
    options.routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "nested-output" }};
    options.redaction = &.{ .{ .key = "password", .action = .mask }, .{ .key = "token", .action = .drop } };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, options);
    defer runtime.destroy();
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    const nested = [_]kron.Field{ kron.kv("password", "raw-password"), kron.kv("token", "raw-token"), kron.kv("visible", true) };
    const values = [_]kron.Value{ kron.fields.fromAny(kron.group(&nested)), kron.fields.fromAny(kron.secret("raw-secret")) };
    const log = runtime.scoped("nested");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogf(.info, "group {any}", .{kron.group(&nested)}, .{ .array = kron.array(&values) }));
    const image = runtime.journal.?.mapping.bytes;
    try testing.expect(std.mem.indexOf(u8, image, "raw-password") == null);
    try testing.expect(std.mem.indexOf(u8, image, "raw-token") == null);
    try testing.expect(std.mem.indexOf(u8, image, "raw-secret") == null);
    gap.abort();
    try runtime.flush(.written);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, memory.written(), .{});
    defer parsed.deinit();
    const array = parsed.value.object.get("attributes").?.object.get("array").?.array;
    const group = array.items[0].object;
    try testing.expectEqualStrings("[REDACTED]", group.get("password").?.string);
    try testing.expect(group.get("token") == null);
    try testing.expectEqualStrings("[REDACTED]", array.items[1].string);
    try testing.expect(std.mem.indexOf(u8, parsed.value.object.get("message").?.string, "raw-password") == null);
    try testing.expect(std.mem.indexOf(u8, parsed.value.object.get("message").?.string, "[REDACTED]") != null);
}

test "shared leases survive version collection and release once after final shutdown" {
    var output: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&output);
    var lease: LeaseState = .{ .memory = &memory };
    const route = lease.route("shared");
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .routes = &.{route} });
    lease.runtime = runtime;
    _ = try runtime.scoped("shared").tryEmit(.info, "one", .{});
    _ = try runtime.replaceConfiguration(&.{route}, .{ .default_filter = "debug" });
    _ = try runtime.scoped("shared").tryEmit(.debug, "two", .{});
    try testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 0), lease.released);
    runtime.destroy();
    lease.runtime = null;
    try testing.expectEqual(@as(usize, 1), lease.released);
    try testing.expect(lease.lock_free);
}

test "old lease callbacks run outside runtime locks and can install a new version" {
    const ReentrantLease = struct {
        runtime: ?*kron.Runtime = null,
        next: kron.RouteOptions,
        version: ?kron.ConfigurationVersion = null,
        shutdown_error: ?anyerror = null,
        fn release(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            const runtime = self.runtime.?;
            self.version = runtime.replaceConfiguration(&.{self.next}, .{}) catch unreachable;
            runtime.shutdown(.drain) catch |err| {
                self.shutdown_error = err;
            };
        }
    };
    var buffers: [3][8192]u8 = undefined;
    var old = kron.MemorySink.initBuffer(&buffers[0]);
    var middle = kron.MemorySink.initBuffer(&buffers[1]);
    var next = kron.MemorySink.initBuffer(&buffers[2]);
    var lease: ReentrantLease = .{ .next = .{ .name = "next", .sink = next.sink() } };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "old", .sink = old.sink(), .release = .{ .context = &lease, .release = ReentrantLease.release } }},
    });
    defer runtime.destroy();
    lease.runtime = runtime;
    _ = try runtime.scoped("reentrant").tryEmit(.info, "old", .{});
    const middle_version = try runtime.replaceConfiguration(&.{.{ .name = "middle", .sink = middle.sink() }}, .{});
    try testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
    try testing.expectEqual(@as(u64, 3), lease.version.?.generation);
    try testing.expectEqual(error.ConfigurationReentrant, lease.shutdown_error.?);
    try testing.expect(runtime.configurationReadyToCollect(middle_version));
    _ = try runtime.scoped("reentrant").tryEmit(.info, "new callback target", .{});
    try testing.expectEqual(@as(usize, 1), next.records);
}

test "runtime initialization failure never adopts an unpublished resource lease" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/missing-directory/never.journal", .{tmp.sub_path});
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    var lease: LeaseState = .{ .memory = &memory };
    // Failure occurs after the manager copied/adopted its initial metadata;
    // abandon must retain caller ownership instead of invoking the callback.
    try testing.expectError(error.FileNotFound, kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{lease.route("init-failure")},
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 4, .max_record_bytes = 1024 },
    }));
    try testing.expectEqual(@as(usize, 0), lease.released);
}

test "named timed flush retains its original resource lease across replacement and timeout" {
    const Blocking = struct {
        memory: *kron.MemorySink,
        entered: std.Io.Event = .unset,
        released: std.Io.Event = .unset,
        block: bool = false,
        lease_released: usize = 0,
        fn sink(self: *@This()) kron.Sink {
            return .{ .context = self, .vtable = &vtable };
        }
        fn write(context: *anyopaque, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try self.memory.writeRecord(bytes);
        }
        fn flush(context: *anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.block) {
                self.entered.set(testing.io);
                self.released.waitUncancelable(testing.io);
            }
            try self.memory.flush();
        }
        fn sync(_: *anyopaque) !void {
            return error.UnsupportedDurability;
        }
        fn release(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.lease_released += 1;
        }
        const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = sync };
    };
    var old_bytes: [8192]u8 = undefined;
    var new_bytes: [8192]u8 = undefined;
    var old = kron.MemorySink.initBuffer(&old_bytes);
    var current = kron.MemorySink.initBuffer(&new_bytes);
    var target: Blocking = .{ .memory = &old };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "named", .sink = target.sink(), .release = .{ .context = &target, .release = Blocking.release } }},
    });
    defer runtime.destroy();
    _ = try runtime.scoped("timed-resource").tryEmit(.info, "before timeout", .{});
    target.block = true;
    defer target.released.set(testing.io);
    try testing.expectError(error.Timeout, runtime.flushRoutesUntil(&.{"named"}, .written, kron.Deadline.after(testing.io, 10 * std.time.ns_per_ms)));
    target.entered.waitUncancelable(testing.io);
    try testing.expect(runtime.controlStatus().detached);
    const old_version = runtime.currentConfiguration();
    _ = try runtime.replaceConfiguration(&.{.{ .name = "replacement", .sink = current.sink() }}, .{});
    // Collection must not even wait on the blocked delivery mutex while a
    // detached control task pins this old resource.
    try testing.expectEqual(@as(usize, 0), try runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 0), target.lease_released);
    target.released.set(testing.io);
    try runtime.flushRoutesUntil(&.{"replacement"}, .written, kron.Deadline.after(testing.io, std.time.ns_per_s));
    try testing.expect(runtime.configurationReadyToCollect(old_version));
    try testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 1), target.lease_released);
}

test "SPSC producers keep all accepted records while routes and redaction are repeatedly replaced" {
    const Context = struct {
        runtime: *kron.Runtime,
        start: std.Io.Event = .unset,
        ready: std.atomic.Value(u32) = .init(0),
        accepted: [4]u64 = @splat(0),
        failure: [4]?anyerror = @splat(null),
        fn producer(self: *@This(), index: usize) void {
            const log = self.runtime.attachThread(.{ .scope = "replacement.concurrent" }) catch |err| {
                self.failure[index] = err;
                _ = self.ready.fetchAdd(1, .release);
                return;
            };
            defer log.detach() catch |err| {
                self.failure[index] = err;
            };
            _ = self.ready.fetchAdd(1, .release);
            self.start.waitUncancelable(testing.io);
            for (0..500) |record| {
                const result = log.tryEmit(.info, "during replacements", .{
                    .producer = index,
                    .record = record,
                    .password = "raw-hot-password",
                }) catch |err| {
                    self.failure[index] = err;
                    return;
                };
                if (result != .accepted) {
                    self.failure[index] = error.UnexpectedOutcome;
                    return;
                }
                self.accepted[index] += 1;
            }
        }
    };
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    var first = try kron.MemorySink.init(testing.allocator, 1024 * 1024);
    defer first.deinit();
    var second = try kron.MemorySink.init(testing.allocator, 1024 * 1024);
    defer second.deinit();
    const first_route: kron.RouteOptions = .{ .name = "output", .sink = first.sink(), .recovery_identity = "concurrent-one" };
    const second_route: kron.RouteOptions = .{ .name = "output", .sink = second.sink(), .recovery_identity = "concurrent-two" };
    var options = try journalOptions(&tmp, &path);
    options.submission = .low_latency;
    options.max_thread_channels = 4;
    options.thread_channel_capacity = 32;
    options.configuration_slots = 4;
    options.routes = &.{first_route};
    options.redaction = &.{.{ .key = "password", .action = .mask }};
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, options);
    defer runtime.destroy();
    var context: Context = .{ .runtime = runtime };
    var threads: [4]std.Thread = undefined;
    var spawned: usize = 0;
    var joined = false;
    defer if (!joined) {
        context.start.set(testing.io);
        for (threads[0..spawned]) |thread| thread.join();
    };
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Context.producer, .{ &context, index });
        spawned += 1;
    }
    while (context.ready.load(.acquire) != threads.len) std.Thread.yield() catch {};
    context.start.set(testing.io);
    for (0..20) |replacement| {
        const target = if (replacement % 2 == 0) second_route else first_route;
        const policy: kron.Configuration = .{ .redaction = &.{.{ .key = "password", .action = if (replacement % 2 == 0) .drop else .mask }} };
        _ = runtime.replaceConfiguration(&.{target}, policy) catch |err| switch (err) {
            error.ConfigSlotsExhausted => blk: {
                try runtime.flush(.written);
                _ = try runtime.collectConfigurations();
                break :blk try runtime.replaceConfiguration(&.{target}, policy);
            },
            else => return err,
        };
        _ = try runtime.collectConfigurations();
    }
    try runtime.flush(.written);
    // A cut includes the producers already in flight but may precede their
    // future iterations; closing admission is not used for this stress trial.
    for (threads) |thread| thread.join();
    joined = true;
    try runtime.flush(.written);
    var accepted: u64 = 0;
    for (context.accepted, context.failure) |count, failure| {
        if (failure) |err| return err;
        accepted += count;
    }
    try testing.expectEqual(@as(u64, 2000), accepted);
    try testing.expectEqual(accepted, runtime.health().accepted);
    try testing.expectEqual(accepted, runtime.health().written);
    try testing.expectEqual(accepted, first.records + second.records);
    try testing.expect(std.mem.indexOf(u8, first.written(), "raw-hot-password") == null);
    try testing.expect(std.mem.indexOf(u8, second.written(), "raw-hot-password") == null);
}

test "shared async producers keep all accepted records while routes and redaction are repeatedly replaced" {
    const Context = struct {
        runtime: *kron.Runtime,
        start: std.Io.Event = .unset,
        ready: std.atomic.Value(u32) = .init(0),
        accepted: [4]u64 = @splat(0),
        failure: [4]?anyerror = @splat(null),
        fn producer(self: *@This(), index: usize) void {
            _ = self.ready.fetchAdd(1, .release);
            self.start.waitUncancelable(testing.io);
            for (0..500) |record| {
                const log = self.runtime.scoped("replacement.concurrent");
                const result = log.tryEmit(.info, "during replacements", .{
                    .producer = index,
                    .record = record,
                    .password = "raw-hot-password",
                }) catch |err| {
                    self.failure[index] = err;
                    return;
                };
                if (result != .accepted) {
                    self.failure[index] = error.UnexpectedOutcome;
                    return;
                }
                self.accepted[index] += 1;
            }
        }
    };
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    var first = try kron.MemorySink.init(testing.allocator, 1024 * 1024);
    defer first.deinit();
    var second = try kron.MemorySink.init(testing.allocator, 1024 * 1024);
    defer second.deinit();
    const first_route: kron.RouteOptions = .{ .name = "output", .sink = first.sink(), .recovery_identity = "shared-concurrent-one" };
    const second_route: kron.RouteOptions = .{ .name = "output", .sink = second.sink(), .recovery_identity = "shared-concurrent-two" };
    var options = try journalOptions(&tmp, &path);
    options.submission = .asynchronous;
    options.configuration_slots = 4;
    options.routes = &.{first_route};
    options.redaction = &.{.{ .key = "password", .action = .mask }};
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, options);
    defer runtime.destroy();
    var context: Context = .{ .runtime = runtime };
    var threads: [4]std.Thread = undefined;
    var spawned: usize = 0;
    var joined = false;
    defer if (!joined) {
        context.start.set(testing.io);
        for (threads[0..spawned]) |thread| thread.join();
    };
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Context.producer, .{ &context, index });
        spawned += 1;
    }
    while (context.ready.load(.acquire) != threads.len) std.Thread.yield() catch {};
    context.start.set(testing.io);
    for (0..20) |replacement| {
        const target = if (replacement % 2 == 0) second_route else first_route;
        const policy: kron.Configuration = .{ .redaction = &.{.{ .key = "password", .action = if (replacement % 2 == 0) .drop else .mask }} };
        _ = runtime.replaceConfiguration(&.{target}, policy) catch |err| switch (err) {
            error.ConfigSlotsExhausted => blk: {
                try runtime.flush(.written);
                _ = try runtime.collectConfigurations();
                break :blk try runtime.replaceConfiguration(&.{target}, policy);
            },
            else => return err,
        };
        _ = try runtime.collectConfigurations();
    }
    try runtime.flush(.written);
    for (threads) |thread| thread.join();
    joined = true;
    try runtime.flush(.written);
    var accepted: u64 = 0;
    for (context.accepted, context.failure) |count, failure| {
        if (failure) |err| return err;
        accepted += count;
    }
    try testing.expectEqual(@as(u64, 2000), accepted);
    try testing.expectEqual(accepted, runtime.health().accepted);
    try testing.expectEqual(accepted, runtime.health().written);
    try testing.expectEqual(accepted, first.records + second.records);
    try testing.expect(std.mem.indexOf(u8, first.written(), "raw-hot-password") == null);
    try testing.expect(std.mem.indexOf(u8, second.written(), "raw-hot-password") == null);
}
