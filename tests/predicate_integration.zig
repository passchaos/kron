const std = @import("std");
const kron = @import("kron");
const testing = std.testing;

test "delivery predicates filter captured fields before journal reservation and preserve accepted decisions" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/predicates.journal", .{tmp.sub_path});
    var first_bytes: [16 * 1024]u8 = undefined;
    var second_bytes: [16 * 1024]u8 = undefined;
    var first = kron.MemorySink.initBuffer(&first_bytes);
    var second = kron.MemorySink.initBuffer(&second_bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 4096 },
        .predicate = "tenant == \"prod\"",
        .routes = &.{.{ .name = "errors", .sink = first.sink(), .recovery_identity = "predicate-one", .predicate = "status >= 500 && route =~ \"^/api/(users|orders)$\"" }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("http");
    const before = runtime.journal.?.reservationTarget();
    try testing.expectEqual(kron.EmitResult.filtered, try log.tryEmit(.info, "not prod", .{ .tenant = "dev", .status = 503, .route = "/api/users" }));
    try testing.expectEqual(kron.EmitResult.filtered, try log.tryEmit(.info, "not error", .{ .tenant = "prod", .status = 200, .route = "/api/users" }));
    try testing.expectEqual(before, runtime.journal.?.reservationTarget());
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "accepted old", .{ .tenant = "prod", .status = 503, .route = "/api/users" }));
    _ = try runtime.replaceConfiguration(&.{.{ .name = "different", .sink = second.sink(), .recovery_identity = "predicate-two", .predicate = "status < 500" }}, .{});
    try testing.expectEqual(kron.EmitResult.filtered, try log.tryEmit(.info, "new rejected", .{ .tenant = "prod", .status = 503, .route = "/api/users" }));
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "new accepted", .{ .tenant = "dev", .status = 200 }));
    gap.abort();
    try runtime.flush(.written);
    try testing.expectEqual(@as(usize, 1), first.records);
    try testing.expectEqual(@as(usize, 1), second.records);
    try testing.expect(std.mem.indexOf(u8, first.written(), "accepted old") != null);
    try testing.expect(std.mem.indexOf(u8, second.written(), "new accepted") != null);
    try testing.expectEqual(@as(u64, 3), runtime.health().filtered);
    try testing.expectEqual(@as(u64, 2), runtime.health().written);
}

test "predicates run after recursive redaction and bounded regex failure leaves no journal reservation" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/safe-regex.journal", .{tmp.sub_path});
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = journal_path, .capacity = 4, .max_record_bytes = 16 * 1024 },
        .routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "safe-regex" }},
        .redaction = &.{.{ .key = "secret", .action = .mask }},
        .predicate = "secret == \"[REDACTED]\" && @rendered_message *= \"error\"",
    });
    defer runtime.destroy();
    const log = runtime.scoped("safe");
    try testing.expectEqual(kron.EmitResult.filtered, try log.tryLogf(.info, "error {s}", .{"details"}, .{ .secret = "raw-secret" }));
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "rendered error", .{ .secret = "raw-secret" }));
    try runtime.flush(.written);
    try testing.expect(std.mem.indexOf(u8, runtime.journal.?.mapping.bytes, "raw-secret") == null);
    _ = try runtime.replaceConfiguration(&.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "safe-regex" }}, .{ .predicate = "@message =~ \"(a+)+b\"" });
    var long_message: [8193]u8 = @splat('a');
    const target = runtime.journal.?.reservationTarget();
    try testing.expectError(error.InputTooLong, log.tryEmit(.info, &long_message, .{}));
    try testing.expectEqual(target, runtime.journal.?.reservationTarget());
    const previous = runtime.currentConfiguration();
    try testing.expectError(error.InvalidRegex, runtime.replaceConfiguration(&.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "safe-regex" }}, .{ .predicate = "@message =~ \"(\"" }));
    try testing.expectEqualDeep(previous, runtime.currentConfiguration());
}

test "a validated thread cache keeps its old version through admitted reentrant guards" {
    const Replace = struct {
        runtime: *kron.Runtime,
        route: kron.RouteOptions,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            _ = self.runtime.replaceConfiguration(&.{self.route}, .{ .default_filter = "off" }) catch |err| {
                self.failure = err;
            };
        }
    };
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/cache-lifetime.journal", .{tmp.sub_path});
    var first_bytes: [8192]u8 = undefined;
    var second_bytes: [8192]u8 = undefined;
    var first = kron.MemorySink.initBuffer(&first_bytes);
    var second = kron.MemorySink.initBuffer(&second_bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = journal_path, .capacity = 4, .max_record_bytes = 1024 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 4,
        .routes = &.{.{ .name = "old", .sink = first.sink(), .recovery_identity = "cache-old" }},
    });
    defer runtime.destroy();
    const attached = try runtime.attachThread(.{ .scope = "cache" });
    defer attached.detach() catch {};
    const old = runtime.currentConfiguration();
    const admission = switch (attached.owner.begin(.info, "cache")) {
        .ready => |value| value,
        else => return error.UnexpectedAdmission,
    };
    var replacement: Replace = .{ .runtime = runtime, .route = .{ .name = "new", .sink = second.sink(), .recovery_identity = "cache-new" } };
    const thread = try std.Thread.spawn(.{}, Replace.run, .{&replacement});
    thread.join();
    if (replacement.failure) |err| {
        attached.owner.end();
        return err;
    }
    // A nested distinct Runtime frame must not hide this outer event's
    // borrowed resource, otherwise enabled could refresh/drop its only pin.
    var nested_bytes: [4096]u8 = undefined;
    var nested_sink = kron.MemorySink.initBuffer(&nested_bytes);
    const nested = try kron.Runtime.create(testing.allocator, testing.io, .{ .routes = &.{.{ .name = "nested", .sink = nested_sink.sink() }} });
    defer nested.destroy();
    switch (nested.begin(.info, "nested")) {
        .ready => {},
        else => return error.UnexpectedAdmission,
    }
    try testing.expect(attached.enabled(.info));
    nested.end();
    // Public release cannot drop a live borrowed snapshot before detach.
    runtime.releaseThreadConfigurationCache(1);
    try testing.expectEqual(error.OutstandingAdmission, runtime.health().last_error.?);
    _ = attached.owner.submit(admission, .{ .level = .info, .scope = "cache", .message = "old admitted", .fields = &.{}, .timestamp_ns = 0 }) catch |err| {
        attached.owner.end();
        return err;
    };
    attached.owner.end();
    try runtime.flush(.written);
    // The idle owner cache deliberately retains its old version.
    try testing.expect(!runtime.configurationReadyToCollect(old));
    try testing.expectEqual(@as(usize, 0), try runtime.collectConfigurations());
    try testing.expect(!attached.enabled(.info)); // Refreshes to new off policy.
    try testing.expect(runtime.configurationReadyToCollect(old));
    try testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
    try testing.expectEqual(@as(usize, 1), first.records);
    try testing.expectEqual(@as(usize, 0), second.records);
}

test "static channel caches and compiled predicates allocate nothing after preparation" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/predicate-noalloc.journal", .{tmp.sub_path});
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    var bytes: [16 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(failing.allocator(), testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 1024 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 8,
        .routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "noalloc-predicate", .predicate = "status >= 500" }},
    });
    defer runtime.destroy();
    const log = try runtime.attachThreadWithClock(kron.ZeroClock, .{ .scope = "noalloc" });
    defer log.detach() catch {};
    _ = try log.tryEmit(.info, "warm", .{ .status = @as(u16, 503) });
    try runtime.flush(.written);
    failing.fail_index = failing.alloc_index;
    const before = failing.alloc_index;
    for (0..8) |_| {
        try testing.expect(log.enabled(.info));
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "accepted", .{ .status = @as(u16, 503) }));
        try testing.expectEqual(kron.EmitResult.filtered, try log.tryEmit(.info, "filtered", .{ .status = @as(u16, 200) }));
    }
    try runtime.flush(.written);
    try testing.expectEqual(before, failing.alloc_index);
    try testing.expectEqual(@as(u64, 9), runtime.health().written);
    try testing.expectEqual(@as(u64, 8), runtime.health().filtered);
}

test "public channel cache queries reject a different thread without touching owner state" {
    const Context = struct {
        runtime: *kron.Runtime,
        rejected: bool = false,
        fn run(self: *@This()) void {
            const decision: kron.FilterDecision = .{ .level = .info, .generation = self.runtime.currentFilterGeneration() };
            self.rejected = !self.runtime.enabledThreadCached(.info, "owner", decision, 1) and
                !self.runtime.filterThreadEnabled(.info, "owner", decision, 1);
            self.runtime.releaseThreadConfigurationCache(1);
        }
    };
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/cache-owner.journal", .{tmp.sub_path});
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = journal_path, .capacity = 4, .max_record_bytes = 1024 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 4,
        .routes = &.{.{ .name = "owner", .sink = memory.sink(), .recovery_identity = "owner" }},
    });
    defer runtime.destroy();
    const log = try runtime.attachThread(.{ .scope = "owner" });
    defer log.detach() catch {};
    try testing.expect(log.enabled(.info));
    var context: Context = .{ .runtime = runtime };
    const thread = try std.Thread.spawn(.{}, Context.run, .{&context});
    thread.join();
    try testing.expect(context.rejected);
    try testing.expectEqual(error.InvalidDetachCapability, runtime.health().last_error.?);
    try testing.expect(log.enabled(.info));
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "owner unchanged", .{}));
    try runtime.flush(.written);
    try testing.expectEqual(@as(usize, 1), memory.records);
}

test "instance clocks remain producer-specific while sharing the same runtime" {
    const FakeClock = struct {
        timestamp: i64,
        calls: usize = 0,
        fn real(context: ?*anyopaque, _: std.Io) i64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            return self.timestamp;
        }
        fn clock(self: *@This()) kron.Clock {
            return .{ .context = self, .real_now = real };
        }
    };
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/instance-clocks.journal", .{tmp.sub_path});
    var memory_bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&memory_bytes);
    var first_clock: FakeClock = .{ .timestamp = 111 };
    var second_clock: FakeClock = .{ .timestamp = 222 };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .low_latency,
        .journal = .{ .path = journal_path, .capacity = 4, .max_record_bytes = 1024 },
        .max_thread_channels = 2,
        .thread_channel_capacity = 4,
        .clock = kron.Clock.zeroTimestamp(),
        .routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "instance-clock" }},
    });
    defer runtime.destroy();
    const first = try runtime.attachThreadWithInstanceClock(first_clock.clock(), .{ .scope = "first" });
    defer first.detach() catch {};
    const second = try runtime.attachThreadWithInstanceClock(second_clock.clock(), .{ .scope = "second" });
    defer second.detach() catch {};
    _ = try first.withBorrowed(.{ .producer = @as(u8, 1) }).tryEmit(.info, "one", .{});
    _ = try second.tryEmit(.info, "two", .{});
    try runtime.flush(.written);
    try testing.expectEqual(@as(usize, 1), first_clock.calls);
    try testing.expectEqual(@as(usize, 1), second_clock.calls);
    try testing.expect(std.mem.indexOf(u8, memory.written(), "\"timestamp_ns\":111") != null);
    try testing.expect(std.mem.indexOf(u8, memory.written(), "\"timestamp_ns\":222") != null);
    var scope: [128]u8 = undefined;
    try testing.expectEqualStrings("first", try first.copyScope(&scope));
    try testing.expectEqualStrings("second", try second.copyScope(&scope));
}

test "admission measurement preserves pre-filter tree errors and post-filter level errors" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/measure.journal", .{tmp.sub_path});
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = journal_path, .capacity = 4, .max_record_bytes = 4096 },
        .routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "measure" }},
        .predicate = "tenant == \"prod\"",
    });
    defer runtime.destroy();
    {
        // Complete-tree validation still happens before a route predicate can
        // suppress the event; invalid input must never be reported as filtered.
        const admission = switch (runtime.begin(.info, "measure")) {
            .ready => |value| value,
            else => return error.UnexpectedAdmission,
        };
        defer runtime.end();
        var duplicate = [_]kron.Field{ kron.kv("same", 1), kron.kv("same", 2) };
        const target = runtime.journal.?.reservationTarget();
        try testing.expectError(error.DuplicateKey, runtime.submit(admission, .{ .level = .info, .scope = "measure", .message = "duplicate", .fields = &duplicate, .timestamp_ns = 0, .tree_validated = true }));
        try testing.expectEqual(target, runtime.journal.?.reservationTarget());
    }
    {
        // Admission measurement deliberately leaves level rejection to the
        // accepted write, so a predicate-filtered invalid level stays filtered.
        const admission = switch (runtime.begin(.info, "measure")) {
            .ready => |value| value,
            else => return error.UnexpectedAdmission,
        };
        defer runtime.end();
        const target = runtime.journal.?.reservationTarget();
        try testing.expectEqual(kron.EmitResult.filtered, try runtime.submit(admission, .{ .level = .off, .scope = "measure", .message = "filtered level", .fields = &.{}, .timestamp_ns = 0 }));
        try testing.expectEqual(target, runtime.journal.?.reservationTarget());
    }
    {
        // The accepted sized write keeps every nested value and the measured
        // wire bytes intact through the journal roundtrip.
        const admission = switch (runtime.begin(.info, "measure")) {
            .ready => |value| value,
            else => return error.UnexpectedAdmission,
        };
        defer runtime.end();
        var leaf_values = [_]kron.Value{ .null_value, kron.kv("z", 7).value };
        var nested_fields = [_]kron.Field{ kron.kv("x", true), kron.kv("y", kron.array(&leaf_values)) };
        var fields = [_]kron.Field{
            kron.kv("tenant", "prod"),
            kron.kv("nested", kron.group(&nested_fields)),
        };
        try testing.expectEqual(kron.EmitResult.accepted, try runtime.submit(admission, .{ .level = .info, .scope = "measure", .message = "accepted", .fields = &fields, .timestamp_ns = 0 }));
    }
    try runtime.flush(.written);
    const output = memory.written();
    try testing.expect(std.mem.indexOf(u8, output, "\"message\":\"accepted\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"tenant\":\"prod\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"nested\":{\"x\":true,\"y\":[null,7]}") != null);
    try testing.expectEqual(@as(usize, 1), memory.records);
}
