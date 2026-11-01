const std = @import("std");
const kron = @import("kron");

test "route policy defaults and overrides preserve sampling redaction timestamp and capture boundaries" {
    inline for (.{ "sync", "memory", "mmap", "spsc-memory", "spsc-mmap" }) |mode| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path: [256]u8 = undefined;
        const journal = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/route.journal", .{tmp.sub_path});
        var output_a: [32768]u8 = undefined;
        var output_b: [32768]u8 = undefined;
        var sink_a = kron.MemorySink.initBuffer(&output_a);
        var sink_b = kron.MemorySink.initBuffer(&output_b);
        const sync = comptime std.mem.eql(u8, mode, "sync");
        const mapped = comptime std.mem.endsWith(u8, mode, "mmap");
        const spsc = comptime std.mem.startsWith(u8, mode, "spsc");
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const runtime = try kron.Runtime.create(allocator.allocator(), std.testing.io, .{
            .submission = if (sync) .sync else if (spsc) .low_latency else .asynchronous,
            .memory_queue = if (!sync and !mapped) .{ .capacity = 32, .max_record_bytes = 4096 } else null,
            .journal = if (mapped) .{ .path = journal, .capacity = 32, .max_record_bytes = 4096 } else null,
            .max_thread_channels = if (spsc) 1 else 0,
            .thread_channel_capacity = 32,
            .clock = kron.Clock.zeroTimestamp(),
            .sampling = .{ .every = 2 },
            .redaction = &.{.{ .key = "token", .action = .mask }},
            .routes = &.{
                .{ .name = "sampled", .sink = sink_a.sink(), .recovery_identity = "route-a", .format = .json, .timestamp = .{}, .redaction = &.{.{ .key = "password", .action = .mask }} },
                .{ .name = "full", .sink = sink_b.sink(), .recovery_identity = "route-b", .format = .json, .sampling = .none },
            },
        });
        defer runtime.destroy();
        {
            const log = if (spsc) try runtime.attachThread(.{ .scope = "route" }) else runtime.scoped("route");
            defer if (spsc) log.detach() catch {};
            allocator.fail_index = allocator.alloc_index;
            allocator.resize_fail_index = allocator.resize_index;
            for (0..6) |i| {
                try std.testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "event", .{ .id = @as(u32, @intCast(i)), .password = "output-sensitive", .token = "capture-sensitive" }));
            }
        }
        try runtime.shutdown(.drain);
        try std.testing.expectEqual(@as(usize, 3), sink_a.records);
        try std.testing.expectEqual(@as(usize, 6), sink_b.records);
        try std.testing.expect(!allocator.has_induced_failure);
        var lines_a = std.mem.splitScalar(u8, sink_a.written(), '\n');
        for (0..3) |i| {
            const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, lines_a.next().?, .{});
            defer parsed.deinit();
            const fields = parsed.value.object.get("attributes").?.object;
            try std.testing.expectEqual(@as(i64, @intCast(i * 2)), fields.get("id").?.integer);
            try std.testing.expectEqualStrings("[REDACTED]", fields.get("password").?.string);
            try std.testing.expectEqualStrings("[REDACTED]", fields.get("token").?.string);
            try std.testing.expect(parsed.value.object.get("timestamp") != null);
        }
        var lines_b = std.mem.splitScalar(u8, sink_b.written(), '\n');
        for (0..6) |i| {
            const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, lines_b.next().?, .{});
            defer parsed.deinit();
            const fields = parsed.value.object.get("attributes").?.object;
            try std.testing.expectEqual(@as(i64, @intCast(i)), fields.get("id").?.integer);
            try std.testing.expectEqualStrings("output-sensitive", fields.get("password").?.string);
            try std.testing.expectEqualStrings("[REDACTED]", fields.get("token").?.string);
            try std.testing.expect(parsed.value.object.get("timestamp") == null);
        }
        if (mapped) {
            const store = if (spsc) runtime.thread_registry.?.getJournal(0) else runtime.journal.?;
            try std.testing.expect(std.mem.indexOf(u8, store.mapping.bytes, "capture-sensitive") == null);
            // Output redaction does not promise to erase the shared queue's
            // original value, which the other selected output still needs.
            try std.testing.expect(std.mem.indexOf(u8, store.mapping.bytes, "output-sensitive") != null);
        }
    }
}

test "route policy all-route sampling skips lazy construction and explicit bypass differs per route" {
    var bytes_a: [8192]u8 = undefined;
    var bytes_b: [8192]u8 = undefined;
    var sink_a = kron.MemorySink.initBuffer(&bytes_a);
    var sink_b = kron.MemorySink.initBuffer(&bytes_b);
    const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .routes = &.{
            .{ .name = "a", .sink = sink_a.sink(), .sampling = .{ .count = 0 }, .sample_bypass = .off },
            .{ .name = "b", .sink = sink_b.sink(), .sampling = .{ .count = 0 }, .sample_bypass = .warn },
        },
    });
    defer runtime.destroy();
    const Provider = struct {
        calls: *usize,
        pub fn fields(self: @This()) struct { value: u32 } {
            self.calls.* += 1;
            return .{ .value = 1 };
        }
    };
    var calls: usize = 0;
    const log = runtime.scoped("route");
    try std.testing.expectEqual(kron.EmitResult.sampled, try log.tryEmitLazy(.info, "skip", Provider{ .calls = &calls }));
    try std.testing.expectEqual(@as(usize, 0), calls);
    try std.testing.expectEqual(kron.EmitResult.accepted, try log.tryEmitLazy(.warn, "keep one", Provider{ .calls = &calls }));
    try runtime.shutdown(.drain);
    try std.testing.expectEqual(@as(usize, 1), calls);
    try std.testing.expectEqual(@as(usize, 0), sink_a.records);
    try std.testing.expectEqual(@as(usize, 1), sink_b.records);
}

test "route policy managed defaults support explicit empty redaction and disabled inherited metadata" {
    var bytes_a: [8192]u8 = undefined;
    var bytes_b: [8192]u8 = undefined;
    var writer_a = std.Io.Writer.fixed(&bytes_a);
    var writer_b = std.Io.Writer.fixed(&bytes_b);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{
        .defaults = .{ .format = .json, .timestamp = .{}, .sampling = .{ .count = 0 }, .redaction = &.{.{ .key = "password", .action = .mask }}, .predicate = "status >= 500" },
        .capture = .{ .redaction = &.{.{ .key = "token", .action = .mask }} },
        .output = .{ .multiple = &.{
            .{ .name = "inherited", .target = .{ .writer = &writer_a } },
            .{ .name = "override", .target = .{ .writer = &writer_b }, .sampling = .none, .timestamp_enabled = false, .redaction = &.{}, .predicate_enabled = false },
        } },
    });
    defer logging.destroy();
    _ = try logging.scoped("route").tryEmit(.info, "overridden", .{ .status = @as(u16, 200), .password = "keep-for-output", .token = "never-queue" });
    try logging.shutdown();
    try std.testing.expectEqual(@as(usize, 0), writer_a.buffered().len);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer_b.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("timestamp") == null);
    try std.testing.expectEqualStrings("keep-for-output", parsed.value.object.get("attributes").?.object.get("password").?.string);
    try std.testing.expectEqualStrings("[REDACTED]", parsed.value.object.get("attributes").?.object.get("token").?.string);
}

test "route policy output budgets fail required routes and skip best effort routes without writing prefixes" {
    inline for (.{ false, true }) |required| {
        var bytes_a: [8192]u8 = undefined;
        var bytes_b: [8192]u8 = undefined;
        var sink_a = kron.MemorySink.initBuffer(&bytes_a);
        var sink_b = kron.MemorySink.initBuffer(&bytes_b);
        const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{ .routes = &.{
            .{ .name = "small", .sink = sink_a.sink(), .max_encoded_record_bytes = 1, .delivery = if (required) .required else .best_effort },
            .{ .name = "full", .sink = sink_b.sink() },
        } });
        defer runtime.destroy();
        if (required) {
            try std.testing.expectError(error.EncodedRecordTooLarge, runtime.scoped("route").tryEmit(.info, "record", .{}));
            try std.testing.expectEqual(@as(usize, 0), sink_b.records);
        } else {
            try std.testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("route").tryEmit(.info, "record", .{}));
            try std.testing.expectEqual(@as(usize, 1), sink_b.records);
        }
        try std.testing.expectEqual(@as(usize, 0), sink_a.records);
        try std.testing.expectEqual(@as(usize, 0), sink_a.written().len);
    }
}

test "route policy prepared records are redacted at output and hot replacement keeps old decisions" {
    inline for (.{ false, true }) |mapped| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path: [256]u8 = undefined;
        const journal = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/prepared-route.journal", .{tmp.sub_path});
        var old_bytes: [32768]u8 = undefined;
        var next_bytes: [32768]u8 = undefined;
        var old = kron.MemorySink.initBuffer(&old_bytes);
        var next = kron.MemorySink.initBuffer(&next_bytes);
        const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = .asynchronous,
            .memory_queue = if (!mapped) .{ .capacity = 128, .max_record_bytes = 2048, .schema_capacity = 2 } else null,
            .journal = if (mapped) .{ .path = journal, .capacity = 128, .max_record_bytes = 2048, .schema_capacity = 2 } else null,
            .routes = &.{.{ .name = "old", .sink = old.sink(), .recovery_identity = "old", .redaction = &.{.{ .key = "password", .action = .mask }}, .sampling = .{ .every = 2 } }},
        });
        defer runtime.destroy();
        const template: kron.Event = .{ .level = .info, .scope = "route", .message = "prepared", .timestamp_ns = 0, .fields = &.{ kron.kv("password", "example"), kron.kv("id", @as(u32, 0)) } };
        const log = try runtime.loggerWithSchema(try runtime.prewarmSchema(template));
        var gap = try runtime.journal.?.reserve();
        var reserved = true;
        defer if (reserved) gap.abort();
        for (0..64) |i| {
            const result = try log.tryEmit(.info, "prepared", .{ .password = "old-raw", .id = @as(u32, @intCast(i)) });
            try std.testing.expectEqual(if (i % 2 == 0) kron.EmitResult.accepted else .sampled, result);
        }
        try runtime.reloadFilter("info");
        try std.testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "prepared", .{ .password = "old-raw", .id = @as(u32, 64) }));
        const before = runtime.currentConfiguration();
        const after = try runtime.replaceConfiguration(&.{.{ .name = "next", .sink = next.sink(), .recovery_identity = "next", .redaction = &.{.{ .key = "password", .action = .drop }}, .sampling = .none }}, .{});
        try std.testing.expect(before.fingerprint != after.fingerprint);
        _ = try log.tryEmit(.info, "prepared", .{ .password = "next-raw", .id = @as(u32, 65) });
        gap.abort();
        reserved = false;
        try runtime.shutdown(.drain);
        try std.testing.expectEqual(@as(usize, 33), old.records);
        try std.testing.expectEqual(@as(usize, 1), next.records);
        try std.testing.expect(std.mem.indexOf(u8, old.written(), "old-raw") == null);
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, next.written(), .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("attributes").?.object.get("password") == null);
    }
}

test "route policy recovery rejects changed redaction and replays the original output policy" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [256]u8 = undefined;
    const journal = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/recover-route.journal", .{tmp.sub_path});
    var failed_bytes: [4096]u8 = undefined;
    var failed = kron.MemorySink.initBuffer(&failed_bytes);
    failed.fail_after_records = 0;
    {
        const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = .asynchronous,
            .journal = .{ .path = journal, .capacity = 8, .max_record_bytes = 2048 },
            .routes = &.{.{ .name = "out", .sink = failed.sink(), .recovery_identity = "same", .redaction = &.{.{ .key = "password", .action = .mask }} }},
        });
        defer runtime.destroy();
        _ = try runtime.scoped("route").tryEmit(.info, "recover", .{ .password = "original-raw" });
        try std.testing.expectError(error.InjectedWriteFailure, runtime.flush(.written));
    }
    var bytes: [4096]u8 = undefined;
    var restored = kron.MemorySink.initBuffer(&bytes);
    try std.testing.expectError(error.RecoveryRouteMismatch, kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = journal, .capacity = 8, .max_record_bytes = 2048 },
        .routes = &.{.{ .name = "out", .sink = restored.sink(), .recovery_identity = "same", .redaction = &.{.{ .key = "password", .action = .drop }} }},
    }));
    const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = journal, .capacity = 8, .max_record_bytes = 2048 },
        .routes = &.{.{ .name = "out", .sink = restored.sink(), .recovery_identity = "same", .redaction = &.{.{ .key = "password", .action = .mask }}, .sampling = .{ .count = 0 } }},
    });
    defer runtime.destroy();
    try runtime.shutdown(.drain);
    try std.testing.expectEqual(@as(usize, 1), restored.records);
    try std.testing.expect(std.mem.indexOf(u8, restored.written(), "original-raw") == null);
    try std.testing.expect(std.mem.indexOf(u8, restored.written(), "[REDACTED]") != null);
}

test "route policy initialization allocation failures release output policy resources" {
    var bytes: [8192]u8 = undefined;
    var sink = kron.MemorySink.initBuffer(&bytes);
    const Fixture = struct {
        fn create(allocator: std.mem.Allocator, output: kron.Sink) !void {
            const runtime = try kron.Runtime.create(allocator, std.testing.io, .{
                .routes = &.{.{ .name = "route", .sink = output, .timestamp = .{}, .redaction = &.{.{ .key = "password", .action = .mask }}, .sampling = .{ .every = 3 }, .max_encoded_record_bytes = 4096 }},
            });
            defer runtime.destroy();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Fixture.create, .{sink.sink()});
    try std.testing.expectError(error.EncodedRecordBudgetExceeded, kron.Runtime.create(std.testing.allocator, std.testing.io, .{ .max_encoded_record_bytes = 512, .routes = &.{.{ .name = "route", .sink = sink.sink(), .max_encoded_record_bytes = 4096 }} }));
}

test "route policy output redaction recurses through attributes and deferred arguments without modifying caller storage" {
    var bytes_a: [8192]u8 = undefined;
    var bytes_b: [8192]u8 = undefined;
    var writer_a = std.Io.Writer.fixed(&bytes_a);
    var writer_b = std.Io.Writer.fixed(&bytes_b);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{
        .mode = .asynchronous,
        .defaults = .{ .format = .json },
        .output = .{ .multiple = &.{
            .{ .name = "private", .target = .{ .writer = &writer_a }, .redaction = &.{.{ .key = "password", .action = .mask }} },
            .{ .name = "original", .target = .{ .writer = &writer_b } },
        } },
    });
    defer logging.destroy();
    const values = [_]kron.Field{ kron.kv("password", "original-secret"), kron.kv("status", @as(u16, 200)) };
    const group = kron.group(&values);
    _ = try logging.scoped("route").tryLogf(.info, "details {any}", .{group}, .{ .nested = group });
    try logging.shutdown();
    try std.testing.expect(std.mem.indexOf(u8, writer_a.buffered(), "original-secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, writer_b.buffered(), "original-secret") != null);
    try std.testing.expectEqualStrings("original-secret", values[0].value.string);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer_a.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("[REDACTED]", parsed.value.object.get("attributes").?.object.get("nested").?.object.get("password").?.string);
}

test "route policy independent sample budgets are shared by concurrent producers and immutable accepted masks" {
    inline for (.{ false, true }) |spsc| {
        var bytes_a: [32768]u8 = undefined;
        var bytes_b: [32768]u8 = undefined;
        var sink_a = kron.MemorySink.initBuffer(&bytes_a);
        var sink_b = kron.MemorySink.initBuffer(&bytes_b);
        const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = if (spsc) .low_latency else .asynchronous,
            .memory_queue = .{ .capacity = 64, .max_record_bytes = 1024 },
            .max_thread_channels = if (spsc) 4 else 0,
            .thread_channel_capacity = 64,
            .routes = &.{
                .{ .name = "budget-a", .sink = sink_a.sink(), .sampling = .{ .count = 37 } },
                .{ .name = "budget-b", .sink = sink_b.sink(), .sampling = .{ .count = 61 } },
            },
        });
        defer runtime.destroy();
        const Worker = struct {
            runtime: *kron.Runtime,
            failure: ?anyerror = null,
            fn run(self: *@This()) void {
                self.work() catch |err| {
                    self.failure = err;
                };
            }
            fn work(self: *@This()) !void {
                const log = if (spsc) try self.runtime.attachThread(.{ .scope = "route" }) else self.runtime.scoped("route");
                defer if (spsc) log.detach() catch {};
                for (0..100) |id| _ = try log.tryEmit(.info, "budget", .{ .id = @as(u32, @intCast(id)) });
            }
        };
        var workers: [4]Worker = @splat(.{ .runtime = runtime });
        var threads: [4]?std.Thread = @splat(null);
        {
            defer for (threads) |thread| if (thread) |worker| worker.join();
            for (&threads, &workers) |*thread, *worker| thread.* = try std.Thread.spawn(.{}, Worker.run, .{worker});
        }
        for (workers) |worker| if (worker.failure) |err| return err;
        try runtime.shutdown(.drain);
        try std.testing.expectEqual(@as(usize, 37), sink_a.records);
        try std.testing.expectEqual(@as(usize, 61), sink_b.records);
    }
}

test "route policy managed validation rejects malformed output overrides before truncating files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "existing.log", .data = "preserved\n" });
    const target: kron.Logging.Target = .{ .file = .{ .dir = tmp.dir, .path = "existing.log", .append = false, .backend = .portable } };
    const routes = [_]kron.Logging.Route{
        .{ .name = "bad", .target = target, .redaction = &.{.{ .key = "", .action = .mask }} },
        .{ .name = "bad", .target = target, .sampling = .{ .every = 0 } },
        .{ .name = "bad", .target = target, .max_encoded_record_bytes = 0 },
        .{ .name = "bad", .target = target, .max_encoded_record_bytes = 128 * 1024 },
    };
    for (routes) |route| {
        if (kron.Logging.create(std.testing.allocator, std.testing.io, .{ .output = .{ .multiple = &.{route} } })) |owner| {
            owner.destroy();
            return error.InvalidOverrideAccepted;
        } else |_| {}
        const bytes = try tmp.dir.readFileAlloc(std.testing.io, "existing.log", std.testing.allocator, .limited(32));
        defer std.testing.allocator.free(bytes);
        try std.testing.expectEqualStrings("preserved\n", bytes);
    }
}

test "route policy recovery fingerprint binds output rules and limits while sampling phase is not identity" {
    var bytes: [4096]u8 = undefined;
    var sink = kron.MemorySink.initBuffer(&bytes);
    const base = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{ .routes = &.{.{ .name = "out", .sink = sink.sink() }} });
    defer base.destroy();
    const sampled = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{ .routes = &.{.{ .name = "out", .sink = sink.sink(), .sampling = .{ .every = 3 } }} });
    defer sampled.destroy();
    try std.testing.expectEqual(base.currentConfiguration().fingerprint, sampled.currentConfiguration().fingerprint);
    const limited = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{ .routes = &.{.{ .name = "out", .sink = sink.sink(), .max_encoded_record_bytes = 4096 }} });
    defer limited.destroy();
    try std.testing.expect(base.currentConfiguration().fingerprint != limited.currentConfiguration().fingerprint);
    const redacted = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{ .routes = &.{.{ .name = "out", .sink = sink.sink(), .redaction = &.{.{ .key = "password", .action = .mask }} }} });
    defer redacted.destroy();
    try std.testing.expect(base.currentConfiguration().fingerprint != redacted.currentConfiguration().fingerprint);
}
