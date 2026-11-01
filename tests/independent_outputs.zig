const std = @import("std");
const kron = @import("kron");

test "independent outputs capture lazy fields and timestamp once with per-output sampling" {
    var a_bytes: [8192]u8 = undefined;
    var b_bytes: [8192]u8 = undefined;
    var a = std.Io.Writer.fixed(&a_bytes);
    var b = std.Io.Writer.fixed(&b_bytes);
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const logging = try kron.Logging.create(allocator.allocator(), std.testing.io, .{ .outputs = &.{ .{ .name = "a", .target = .{ .writer = &a }, .sampling = .{ .count = 0 }, .sample_bypass = .off, .format = .json }, .{ .name = "b", .target = .{ .writer = &b }, .sampling = .{ .count = 0 }, .format = .json } } });
    defer logging.destroy();
    allocator.fail_index = allocator.alloc_index;
    allocator.resize_fail_index = allocator.resize_index;
    const Provider = struct {
        calls: *usize,
        pub fn fields(self: @This()) struct { value: u32 } {
            self.calls.* += 1;
            return .{ .value = 42 };
        }
    };
    var calls: usize = 0;
    const log = logging.scoped("once");
    try std.testing.expectEqual(kron.EmitResult.sampled, try log.tryEmitLazy(.info, "skip", Provider{ .calls = &calls }));
    try std.testing.expectEqual(@as(usize, 0), calls);
    try std.testing.expectEqual(kron.EmitResult.sampled, logging.lastResults()[0].result);
    try std.testing.expectEqual(kron.EmitResult.sampled, logging.lastResults()[1].result);
    try std.testing.expectEqual(kron.EmitResult.accepted, try log.tryEmitLazy(.warn, "one", Provider{ .calls = &calls }));
    try std.testing.expectEqual(@as(usize, 1), calls);
    try std.testing.expectEqual(kron.EmitResult.sampled, logging.lastResults()[0].result);
    try std.testing.expectEqual(kron.EmitResult.accepted, logging.lastResults()[1].result);
    try logging.shutdown();
    try std.testing.expectEqual(@as(usize, 0), a.buffered().len);
    try std.testing.expect(!allocator.has_induced_failure);
}

test "independent outputs keep queue capacity overflow and synchronous delivery independent" {
    var a_bytes: [8192]u8 = undefined;
    var b_bytes: [8192]u8 = undefined;
    var c_bytes: [8192]u8 = undefined;
    var a = std.Io.Writer.fixed(&a_bytes);
    var b = std.Io.Writer.fixed(&b_bytes);
    var c = std.Io.Writer.fixed(&c_bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{
        .outputs = &.{
            .{ .name = "drop", .target = .{ .writer = &a }, .mode = .asynchronous, .overflow = .drop_newest, .queue = .{ .memory = .{ .capacity = 2, .max_record_bytes = 1024 } } },
            .{ .name = "block", .target = .{ .writer = &b }, .mode = .spsc, .max_threads = 1, .overflow = .block, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 2048 } } },
            .{ .name = "sync", .target = .{ .writer = &c }, .mode = .sync },
        },
    });
    defer logging.destroy();
    const drop = try logging.runtime("drop");
    var gap = try drop.journal.?.reserve();
    var reserved = true;
    defer if (reserved) gap.abort();
    const log = logging.scoped("pressure");
    try std.testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "first", .{}));
    try std.testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "second", .{}));
    try std.testing.expectEqual(kron.EmitResult.dropped_full, logging.lastResults()[0].result);
    try std.testing.expectEqual(kron.EmitResult.accepted, logging.lastResults()[1].result);
    try std.testing.expectEqual(kron.EmitResult.accepted, logging.lastResults()[2].result);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, c.buffered(), "\n"));
    try std.testing.expectEqual(kron.QueueStorage.mixed, logging.health().queue_storage);
    gap.abort();
    reserved = false;
    try logging.shutdown();
    try std.testing.expectEqual(@as(u64, 1), (try logging.outputHealth("drop")).written);
    try std.testing.expectEqual(@as(u64, 2), (try logging.outputHealth("block")).written);
    try std.testing.expectEqual(@as(u64, 5), logging.health().written);
}

test "independent outputs protect each mmap queue and preserve caller data and common event time" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var journal_path_bytes: [256]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&journal_path_bytes, ".zig-cache/tmp/{s}/protected.journal", .{tmp.sub_path});
    var original_bytes: [8192]u8 = undefined;
    var original = std.Io.Writer.fixed(&original_bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{ .{ .name = "protected", .target = .{ .file = .{ .dir = tmp.dir, .path = "protected.jsonl", .backend = .portable } }, .mode = .spsc, .max_threads = 1, .queue = .{ .mmap = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 2048 } }, .redaction = &.{.{ .key = "password", .action = .mask }}, .format = .json }, .{ .name = "original", .target = .{ .writer = &original }, .mode = .asynchronous, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 2048 } }, .format = .json } } });
    defer logging.destroy();
    var scope = "original-scope".*;
    const log = try logging.attachThread(&scope);
    var attached = true;
    defer if (attached) log.detach() catch {};
    @memset(&scope, 'x');
    const values = [_]kron.Field{ kron.kv("password", "private-original"), kron.kv("status", @as(u16, 200)) };
    _ = try log.tryLogf(.info, "details {any}", .{kron.group(&values)}, .{ .nested = kron.group(&values) });
    try log.detach();
    attached = false;
    try logging.flushOutputsDurable(&.{"protected"});
    try logging.shutdown();
    const protected = try logging.runtime("protected");
    try std.testing.expect(std.mem.indexOf(u8, protected.thread_registry.?.getJournal(0).mapping.bytes, "private-original") == null);
    const memory = try logging.runtime("original");
    try std.testing.expect(std.mem.indexOf(u8, memory.journal.?.mapping.bytes, "private-original") != null);
    try std.testing.expectEqualStrings("private-original", values[0].value.string);
    const file = try tmp.dir.readFileAlloc(std.testing.io, "protected.jsonl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(file);
    const parsed_a = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, file, .{});
    defer parsed_a.deinit();
    const parsed_b = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, original.buffered(), .{});
    defer parsed_b.deinit();
    try std.testing.expectEqualStrings("original-scope", parsed_a.value.object.get("scope").?.string);
    const time_a = parsed_a.value.object.get("timestamp_ns").?;
    const time_b = parsed_b.value.object.get("timestamp_ns").?;
    if (time_a == .string) try std.testing.expectEqualStrings(time_a.string, time_b.string) else try std.testing.expectEqual(time_a.integer, time_b.integer);
    try std.testing.expect(std.mem.indexOf(u8, file, "private-original") == null);
    try std.testing.expect(std.mem.indexOf(u8, original.buffered(), "private-original") != null);
}

test "independent outputs attempt healthy routes after required and best-effort errors" {
    inline for (.{ false, true }) |required| {
        var bad_bytes: [1]u8 = undefined;
        var good_bytes: [8192]u8 = undefined;
        var bad = std.Io.Writer.fixed(&bad_bytes);
        var good = std.Io.Writer.fixed(&good_bytes);
        const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{
            .outputs = &.{
                .{ .name = "bad", .target = .{ .writer = &bad }, .delivery = if (required) .required else .best_effort },
                .{ .name = "good", .target = .{ .writer = &good } },
            },
        });
        defer logging.destroy();
        if (required) try std.testing.expectError(error.WriteFailed, logging.scoped("failure").tryEmit(.info, "healthy output", .{})) else try std.testing.expectEqual(kron.EmitResult.accepted, try logging.scoped("failure").tryEmit(.info, "healthy output", .{}));
        try std.testing.expectEqual(error.WriteFailed, logging.lastResults()[0].err);
        try std.testing.expectEqual(kron.EmitResult.accepted, logging.lastResults()[1].result);
        try std.testing.expect(std.mem.indexOf(u8, good.buffered(), "healthy output") != null);
        if (required) try std.testing.expectError(error.WriteFailed, logging.shutdown()) else try logging.shutdown();
    }
    var bytes: [1]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    const single = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{.{ .target = .{ .writer = &writer }, .delivery = .best_effort }} });
    defer single.destroy();
    try std.testing.expectEqual(kron.EmitResult.filtered, try single.scoped("single").tryEmit(.info, "too long", .{}));
    try std.testing.expectEqual(error.WriteFailed, single.lastResults()[0].err);
    try single.shutdown();
}

test "independent outputs capture failure releases all admissions and records only selected failures" {
    var a_bytes: [8192]u8 = undefined;
    var b_bytes: [8192]u8 = undefined;
    var a = std.Io.Writer.fixed(&a_bytes);
    var b = std.Io.Writer.fixed(&b_bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{
        .{ .name = "a", .target = .{ .writer = &a } },
        .{ .name = "b", .target = .{ .writer = &b }, .filter = "warn" },
    } });
    defer logging.destroy();
    const duplicate = [_]kron.Field{ kron.kv("id", 1), kron.kv("id", 2) };
    try std.testing.expectError(error.DuplicateKey, logging.scoped("capture").tryEmit(.info, "invalid", @as([]const kron.Field, &duplicate)));
    try std.testing.expectEqual(error.DuplicateKey, logging.lastResults()[0].err);
    try std.testing.expectEqual(kron.EmitResult.filtered, logging.lastResults()[1].result);
    try std.testing.expectEqual(@as(u64, 1), (try logging.outputHealth("a")).capture_errors);
    try std.testing.expectEqual(@as(u64, 0), (try logging.outputHealth("b")).capture_errors);
    try std.testing.expectEqual(@as(u64, 0), (try logging.runtime("a")).activeAdmissions());
    try std.testing.expectEqual(kron.EmitResult.accepted, try logging.scoped("capture").tryEmit(.warn, "valid", .{}));
    try logging.shutdown();
}

test "independent outputs prepared attachments rollback and stale thread handles cannot be reused" {
    var a_bytes: [8192]u8 = undefined;
    var b_bytes: [8192]u8 = undefined;
    var a = std.Io.Writer.fixed(&a_bytes);
    var b = std.Io.Writer.fixed(&b_bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{ .{ .name = "a", .target = .{ .writer = &a }, .mode = .spsc, .max_threads = 1, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 } } }, .{ .name = "b", .target = .{ .writer = &b }, .mode = .spsc, .max_threads = 1, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 } } } } });
    defer logging.destroy();
    const shape: kron.Event = .{ .level = .info, .scope = "prepared", .message = "ready", .timestamp_ns = 0, .fields = &.{kron.kv("id", @as(u32, 0))} };
    const first = try logging.attachPreparedThread(shape);
    try std.testing.expectError(error.ChannelsExhausted, logging.attachThread("extra"));
    _ = try first.tryEmit(.info, "ready", .{ .id = @as(u32, 1) });
    try first.detach();
    const second = try logging.attachPreparedThread(shape);
    var attached = true;
    defer if (attached) second.detach() catch {};
    try std.testing.expectError(error.StaleToken, first.detach());
    try std.testing.expectEqual(kron.EmitResult.rejected_closing, try first.tryEmit(.info, "stale", .{ .id = @as(u32, 2) }));
    _ = try second.tryEmit(.info, "ready", .{ .id = @as(u32, 3) });
    try second.detach();
    attached = false;
    try logging.shutdown();
    try std.testing.expectEqual(@as(u64, 4), logging.health().written);
}

test "independent outputs reject aggregate queue budget and duplicate journals before allocation" {
    var forbidden = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.JournalBudgetExceeded, kron.Logging.create(forbidden.allocator(), std.testing.io, .{
        .max_total_queue_bytes = 1,
        .outputs = &.{.{ .mode = .asynchronous }},
    }));
    try std.testing.expectError(error.DuplicateJournalPath, kron.Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{ .{ .name = "a", .target = .{ .file = .{ .path = "a.jsonl" } }, .mode = .asynchronous, .queue = .{ .mmap = .{ .path = "same.journal", .capacity = 8, .max_record_bytes = 1024 } } }, .{ .name = "b", .target = .{ .file = .{ .path = "b.jsonl" } }, .mode = .asynchronous, .queue = .{ .mmap = .{ .path = "same.journal", .capacity = 8, .max_record_bytes = 1024 } } } } }));
    try std.testing.expect(!forbidden.has_induced_failure);
}

test "independent outputs reject reentrant control and detach before changing another pipeline" {
    var a_bytes: [8192]u8 = undefined;
    var b_bytes: [8192]u8 = undefined;
    var a = std.Io.Writer.fixed(&a_bytes);
    var b = std.Io.Writer.fixed(&b_bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{ .{ .name = "a", .target = .{ .writer = &a }, .mode = .spsc, .max_threads = 1, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024 } } }, .{ .name = "b", .target = .{ .writer = &b }, .mode = .spsc, .max_threads = 1, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024 } } } } });
    defer logging.destroy();
    const log = try logging.attachThread("callback");
    var attached = true;
    defer if (attached) log.detach() catch {};
    const Provider = struct {
        logging: *kron.Logging,
        log: kron.Logging.Logger,
        failure: *?anyerror,
        pub fn fields(self: @This()) struct { id: u32 } {
            self.exercise() catch |err| {
                self.failure.* = err;
            };
            return .{ .id = 1 };
        }
        fn exercise(self: @This()) !void {
            try std.testing.expectError(error.ProducerReentrant, self.logging.shutdown());
            try std.testing.expectError(error.ProducerReentrant, self.logging.flush());
            try std.testing.expectError(error.OutstandingAdmission, self.log.detach());
            try std.testing.expectEqual(kron.EmitResult.rejected_closing, try self.log.tryEmit(.info, "recursive", .{}));
        }
    };
    var failure: ?anyerror = null;
    _ = try log.tryEmitLazy(.info, "outer", Provider{ .logging = logging, .log = log, .failure = &failure });
    if (failure) |err| return err;
    _ = try log.tryEmit(.info, "still live", .{});
    try log.detach();
    attached = false;
    try logging.shutdown();
    try std.testing.expectEqual(@as(u64, 4), logging.health().written);
}

test "independent outputs preserve outer single-owner outcomes across nested independent logging" {
    var a_bytes: [8192]u8 = undefined;
    var b_bytes: [8192]u8 = undefined;
    var a = std.Io.Writer.fixed(&a_bytes);
    var b = std.Io.Writer.fixed(&b_bytes);
    const outer = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{.{ .target = .{ .writer = &a } }} });
    defer outer.destroy();
    const inner = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{.{ .target = .{ .writer = &b } }} });
    defer inner.destroy();
    const Provider = struct {
        inner: *kron.Logging,
        pub fn fields(self: @This()) struct { id: u32 } {
            self.inner.scoped("inner").info("nested", .{});
            return .{ .id = 1 };
        }
    };
    _ = try outer.scoped("outer").tryEmitLazy(.info, "outer", Provider{ .inner = inner });
    try std.testing.expectEqual(kron.EmitResult.accepted, outer.lastResults()[0].result);
    try std.testing.expectEqual(@as(usize, 0), inner.lastResults().len);
    try outer.shutdown();
    try inner.shutdown();
}

test "independent outputs reject generated SPSC journal and output path conflicts" {
    var forbidden = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.DuplicateJournalPath, kron.Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{
        .{ .name = "a", .target = .{ .file = .{ .path = "a.jsonl" } }, .mode = .spsc, .max_threads = 1, .queue = .{ .mmap = .{ .path = "a.journal", .capacity = 8, .max_record_bytes = 1024 } } },
        .{ .name = "b", .target = .{ .file = .{ .path = "b.jsonl" } }, .mode = .asynchronous, .queue = .{ .mmap = .{ .path = "a.journal.thread-0.journal", .capacity = 8, .max_record_bytes = 1024 } } },
    } }));
    try std.testing.expectError(error.JournalOutputConflict, kron.Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{
        .{ .name = "a", .target = .{ .file = .{ .path = "a.jsonl" } }, .mode = .asynchronous, .queue = .{ .mmap = .{ .path = "b.jsonl", .capacity = 8, .max_record_bytes = 1024 } } },
        .{ .name = "b", .target = .{ .file = .{ .path = "b.jsonl" } } },
    } }));
    var bytes: [16]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try std.testing.expectError(error.DuplicateOutputTarget, kron.Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{
        .{ .name = "a", .target = .{ .writer = &writer } },
        .{ .name = "b", .target = .{ .writer = &writer } },
    } }));
    try std.testing.expect(!forbidden.has_induced_failure);
}

const BlockingWriter = struct {
    interface: std.Io.Writer = .{ .vtable = &.{ .drain = drain }, .buffer = &.{} },
    entered: std.Io.Event = .unset,
    release: std.Io.Event = .unset,
    fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *BlockingWriter = @fieldParentPtr("interface", writer);
        self.entered.set(std.testing.io);
        self.release.waitUncancelable(std.testing.io);
        writer.end = 0;
        var bytes: usize = 0;
        for (data[0 .. data.len - 1]) |part| bytes += part.len;
        return bytes + data[data.len - 1].len * splat;
    }
};

test "independent outputs shutdown timeout closes all admissions and retains blocked writer" {
    var blocked: BlockingWriter = .{};
    var good_bytes: [8192]u8 = undefined;
    var good = std.Io.Writer.fixed(&good_bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{ .{ .name = "first", .target = .{ .writer = &blocked.interface }, .mode = .asynchronous, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024 } } }, .{ .name = "later", .target = .{ .writer = &good }, .mode = .asynchronous, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024 } } } } });
    defer logging.destroy();
    defer blocked.release.set(std.testing.io);
    _ = try logging.scoped("shutdown").tryEmit(.info, "pending", .{});
    try blocked.entered.waitTimeout(std.testing.io, .{ .deadline = kron.Deadline.after(std.testing.io, 5 * std.time.ns_per_s).timestamp });
    try std.testing.expectError(error.Timeout, logging.shutdownUntil(kron.Deadline.after(std.testing.io, 10 * std.time.ns_per_ms)));
    try std.testing.expectEqual(kron.EmitResult.rejected_closing, try logging.scoped("shutdown").tryEmit(.info, "after timeout", .{}));
    try std.testing.expectEqual(kron.EmitResult.rejected_closing, try (try logging.scopedOutput("later", "shutdown")).tryEmit(.info, "direct after timeout", .{}));
    try std.testing.expectEqual(@as(u64, 1), (try logging.outputHealth("later")).accepted);
    blocked.release.set(std.testing.io);
    try logging.shutdown();
    try std.testing.expectEqual(@as(u64, 2), logging.health().written);
}

test "independent outputs per-route samplers keep distinct concurrent producer budgets" {
    inline for (.{ false, true }) |spsc| {
        var a_bytes: [32768]u8 = undefined;
        var b_bytes: [32768]u8 = undefined;
        var a = std.Io.Writer.fixed(&a_bytes);
        var b = std.Io.Writer.fixed(&b_bytes);
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const logging = try kron.Logging.create(allocator.allocator(), std.testing.io, .{ .outputs = &.{ .{ .name = "inherited", .target = .{ .writer = &a }, .mode = if (spsc) .spsc else .asynchronous, .max_threads = 4, .sampling = .{ .count = 37 }, .queue = .{ .memory = .{ .capacity = 64, .max_record_bytes = 1024 } } }, .{ .name = "override", .target = .{ .writer = &b }, .sampling = .{ .count = 61 }, .mode = if (spsc) .spsc else .asynchronous, .max_threads = 4, .queue = .{ .memory = .{ .capacity = 64, .max_record_bytes = 1024 } } } } });
        defer logging.destroy();
        allocator.fail_index = allocator.alloc_index;
        allocator.resize_fail_index = allocator.resize_index;
        const Worker = struct {
            logging: *kron.Logging,
            failure: ?anyerror = null,
            fn run(self: *@This()) void {
                self.work() catch |err| {
                    self.failure = err;
                };
            }
            fn work(self: *@This()) !void {
                const log = if (spsc) try self.logging.attachThread("concurrent") else self.logging.scoped("concurrent");
                defer if (spsc) log.detach() catch {};
                for (0..100) |id| _ = try log.tryEmit(.info, "budget", .{ .id = @as(u32, @intCast(id)) });
            }
        };
        var workers: [4]Worker = @splat(.{ .logging = logging });
        var threads: [4]?std.Thread = @splat(null);
        {
            defer for (threads) |thread| if (thread) |active| active.join();
            for (&threads, &workers) |*thread, *worker| thread.* = try std.Thread.spawn(.{}, Worker.run, .{worker});
        }
        for (workers) |worker| if (worker.failure) |err| return err;
        try logging.shutdown();
        try std.testing.expectEqual(@as(u64, 37), (try logging.outputHealth("inherited")).written);
        try std.testing.expectEqual(@as(u64, 61), (try logging.outputHealth("override")).written);
        try std.testing.expect(!allocator.has_induced_failure);
    }
}

test "independent outputs support all 64 pipelines and aggregate each result" {
    var buffers: [64][1024]u8 = undefined;
    var writers: [64]std.Io.Writer = undefined;
    var names: [64][16]u8 = undefined;
    var routes: [64]kron.Logging.Route = undefined;
    for (&routes, &writers, &buffers, &names, 0..) |*route, *writer, *buffer, *name, i| {
        writer.* = .fixed(buffer);
        route.* = .{ .name = try std.fmt.bufPrint(name, "output-{d}", .{i}), .target = .{ .writer = writer } };
    }
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &routes });
    defer logging.destroy();
    _ = try logging.scoped("all").tryEmit(.info, "64 routes", .{});
    try std.testing.expectEqual(@as(usize, 64), logging.lastResults().len);
    for (logging.lastResults()) |result| try std.testing.expectEqual(kron.EmitResult.accepted, result.result);
    try logging.shutdown();
    try std.testing.expectEqual(@as(u64, 64), logging.health().written);
}

test "independent outputs later attachment exhaustion rolls back earlier acquired channel" {
    var a_bytes: [8192]u8 = undefined;
    var b_bytes: [8192]u8 = undefined;
    var a = std.Io.Writer.fixed(&a_bytes);
    var b = std.Io.Writer.fixed(&b_bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{ .{ .name = "a", .target = .{ .writer = &a }, .mode = .spsc, .max_threads = 1, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024 } } }, .{ .name = "b", .target = .{ .writer = &b }, .mode = .spsc, .max_threads = 1, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024 } } } } });
    defer logging.destroy();
    const b_runtime = try logging.runtime("b");
    const occupied = try b_runtime.attachThread(.{ .scope = "occupied" });
    var occupied_live = true;
    defer if (occupied_live) occupied.detach() catch {};
    try std.testing.expectError(error.ChannelsExhausted, logging.attachThread("rollback"));
    try occupied.detach();
    occupied_live = false;
    const attached = try logging.attachThread("works");
    var live = true;
    defer if (live) attached.detach() catch {};
    _ = try attached.tryEmit(.info, "all channels released", .{});
    try attached.detach();
    live = false;
    try logging.shutdown();
    try std.testing.expectEqual(@as(u64, 2), logging.health().written);
}

test "independent outputs void logging keeps error diagnostics local to failed output" {
    var bad_bytes: [1]u8 = undefined;
    var good_bytes: [8192]u8 = undefined;
    var bad = std.Io.Writer.fixed(&bad_bytes);
    var good = std.Io.Writer.fixed(&good_bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{
        .{ .name = "bad", .target = .{ .writer = &bad } },
        .{ .name = "good", .target = .{ .writer = &good } },
    } });
    defer logging.destroy();
    logging.scoped("failure").info("healthy output", .{});
    try std.testing.expectEqual(error.WriteFailed, (try logging.outputHealth("bad")).last_error.?);
    try std.testing.expectEqual(@as(?anyerror, null), (try logging.outputHealth("good")).last_error);
    try std.testing.expectEqual(@as(u64, 1), (try logging.outputHealth("good")).written);
    try std.testing.expectError(error.WriteFailed, logging.shutdown());
}

test "independent outputs mixed singleton and fanout nesting rejects the ninth call and releases every frame" {
    var buffers: [9][2][4096]u8 = undefined;
    var writers: [9][2]std.Io.Writer = undefined;
    var owners: [9]*kron.Logging = undefined;
    var initialized: usize = 0;
    defer {
        while (initialized != 0) {
            initialized -= 1;
            owners[initialized].destroy();
        }
    }
    for (&owners, &writers, &buffers, 0..) |*owner, *outputs, *storage, index| {
        for (outputs, storage) |*writer, *buffer| writer.* = .fixed(buffer);
        const routes = [_]kron.Logging.Route{
            .{ .name = "a", .target = .{ .writer = &outputs[0] } },
            .{ .name = "b", .target = .{ .writer = &outputs[1] } },
        };
        owner.* = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = routes[0..if (index % 2 == 0) 1 else 2] });
        initialized += 1;
    }
    const Provider = struct {
        owners: []*kron.Logging,
        index: usize,
        calls: *usize,
        failure: *?anyerror,
        pub fn fields(self: @This()) struct { id: u32 } {
            self.calls.* += 1;
            self.next() catch |err| {
                self.failure.* = err;
            };
            return .{ .id = @intCast(self.index) };
        }
        fn next(self: @This()) !void {
            const next_index = self.index + 1;
            if (next_index == self.owners.len) return;
            const result = try self.owners[next_index].scoped("nested").tryEmitLazy(.info, "event", @This(){
                .owners = self.owners,
                .index = next_index,
                .calls = self.calls,
                .failure = self.failure,
            });
            try std.testing.expectEqual(if (next_index == 8) kron.EmitResult.rejected_closing else .accepted, result);
            for (self.owners[next_index].lastResults()) |outcome| try std.testing.expectEqual(result, outcome.result);
        }
    };
    var calls: usize = 0;
    var failure: ?anyerror = null;
    const provider: Provider = .{ .owners = &owners, .index = 0, .calls = &calls, .failure = &failure };
    try std.testing.expectEqual(kron.EmitResult.accepted, try owners[0].scoped("nested").tryEmitLazy(.info, "event", provider));
    if (failure) |err| return err;
    try std.testing.expectEqual(@as(usize, 8), calls);
    try std.testing.expectEqual(kron.EmitResult.accepted, owners[0].lastResults()[0].result);
    for (owners, 0..) |owner, index| {
        const expected: u64 = if (index == 8) 0 else if (index % 2 == 0) 1 else 2;
        try std.testing.expectEqual(expected, owner.health().written);
        try std.testing.expectEqual(@as(u64, 0), (try owner.runtime("a")).activeAdmissions());
        try std.testing.expectEqual(kron.EmitResult.accepted, try owner.scoped("after").tryEmit(.info, "frame reused", .{}));
        try owner.shutdown();
    }
}
