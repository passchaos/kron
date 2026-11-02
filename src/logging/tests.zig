const std = @import("std");
const Logging = @import("root.zig").Logging;
const EmitResult = @import("../core/logger.zig").EmitResult;

test "managed logging writer lifetime context snapshots filtering and shutdown allocate only at initialization" {
    inline for (.{ .sync, .asynchronous, .spsc }) |mode| {
        var bytes: [16384]u8 = undefined;
        var writer = std.Io.Writer.fixed(&bytes);
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const logging = try Logging.create(allocator.allocator(), std.testing.io, .{ .outputs = &.{.{ .target = .{ .writer = &writer }, .mode = mode, .format = .json, .redaction = &.{.{ .key = "password", .action = .mask }} }} });
        var live = true;
        defer if (live) logging.destroy();
        allocator.fail_index = allocator.alloc_index;
        allocator.resize_fail_index = allocator.resize_index;
        const base = if (mode == .spsc) try logging.attachThread("app") else logging.scoped("app");
        var attached = mode == .spsc;
        defer if (mode == .spsc) {
            if (attached) base.detach() catch {};
        };
        var name = "original".*;
        const log = base.withBorrowed(.{ .service = "test" });
        try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.info, "first", .{ .name = &name, .password = "secret-source" }));
        @memset(&name, 'x');
        try logging.reloadFilter("warn,app=debug");
        try std.testing.expectEqual(EmitResult.accepted, try log.tryLogf(.debug, "second {d}", .{@as(u64, 7)}, .{}));
        try logging.setLevel(.off);
        try std.testing.expect(logging.scoped("app").enabled(.debug));
        try std.testing.expectEqual(EmitResult.filtered, try logging.scoped("other").tryEmit(.fatal, "hidden", .{}));
        if (mode == .spsc) {
            try base.detach();
            attached = false;
        }
        try logging.flush();
        try logging.shutdown();
        try logging.shutdown();
        const health = logging.health();
        try std.testing.expectEqual(@as(u64, 2), health.written);
        try std.testing.expectEqual(@as(usize, 0), health.journal_pending);
        try std.testing.expect(!allocator.has_induced_failure);
        logging.destroy();
        live = false;
        try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "original") != null);
        try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "secret-source") == null);
        try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "[REDACTED]") != null);
        try writer.writeAll("writer survives owner\n");
    }
}

test "managed logging owns file cleanup and mmap close reopen including prepared thread helper" {
    inline for (.{ false, true }) |persistent| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var journal_path_bytes: [192]u8 = undefined;
        const journal_path = try std.fmt.bufPrint(&journal_path_bytes, ".zig-cache/tmp/{s}/managed.journal", .{tmp.sub_path});
        const options: Logging.Options = .{ .outputs = &.{.{ .target = .{ .file = .{ .dir = tmp.dir, .path = "managed.jsonl", .backend = .portable } }, .mode = .spsc, .max_threads = 1, .format = .json, .queue = if (persistent) .{ .mmap = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 } } else .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 } } }} };
        const shape: @import("../core/event.zig").Event = .{ .level = .info, .scope = "prepared", .message = "event {d}", .message_template = true, .timestamp_ns = 0, .fields = &.{@import("../core/field.zig").kv("n", @as(u64, 0))}, .format_args = &.{@import("../core/field.zig").kv("0", @as(u64, 0))} };
        const logging = try Logging.create(std.testing.allocator, std.testing.io, options);
        var live = true;
        defer if (live) logging.destroy();
        const log = try logging.attachPreparedThread(shape);
        var attached = true;
        defer if (attached) log.detach() catch {};
        _ = try log.tryLogf(.info, "event {d}", .{@as(u64, 5)}, .{ .n = @as(u64, 5) });
        try log.detach();
        attached = false;
        try logging.flushDurable();
        try logging.shutdown();
        try std.testing.expectEqual(@as(u64, 1), logging.health().written);
        logging.destroy();
        live = false;
        const first = try tmp.dir.readFileAlloc(std.testing.io, "managed.jsonl", std.testing.allocator, .limited(8192));
        defer std.testing.allocator.free(first);
        try std.testing.expect(std.mem.indexOf(u8, first, "event 5") != null);
        const reopened = try Logging.create(std.testing.allocator, std.testing.io, options);
        defer reopened.destroy();
        try reopened.flush();
        try std.testing.expectEqual(@as(usize, 0), reopened.health().journal_pending);
        _ = try reopened.scoped("plain").tryEmit(.info, "after reopen", .{});
        try reopened.shutdown();
        const second = try tmp.dir.readFileAlloc(std.testing.io, "managed.jsonl", std.testing.allocator, .limited(8192));
        defer std.testing.allocator.free(second);
        try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, second, "\n"));
    }
}

test "managed logging reports write and shutdown errors before ordered cleanup" {
    var bytes: [1]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    const logging = try Logging.create(std.testing.allocator, std.testing.io, .{
        .outputs = &.{.{ .target = .{ .writer = &writer } }},
    });
    defer logging.destroy();
    try std.testing.expectError(error.WriteFailed, logging.scoped("bad").tryEmit(.info, "too long", .{}));
    try std.testing.expectError(error.WriteFailed, logging.shutdown());
    try std.testing.expect(logging.health().last_error != null);
}

test "managed logging rejects invalid configurations before touching files or allocator" {
    var forbidden = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.QueueRequiresAsyncMode, Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{.{ .queue = .{ .memory = .{} } }} }));
    try std.testing.expectError(error.InvalidThreadBudget, Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{.{ .mode = .spsc, .max_threads = 0 }} }));
    try std.testing.expectError(error.MmapRequiresFileOutput, Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{.{ .mode = .asynchronous, .queue = .{ .mmap = .{ .path = "must-not-create.journal", .capacity = 8, .max_record_bytes = 512 } } }} }));
    try std.testing.expectError(error.JournalBudgetExceeded, Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{.{ .mode = .asynchronous, .max_journal_bytes = 1 }} }));
    try std.testing.expectError(error.InvalidLevel, Logging.create(forbidden.allocator(), std.testing.io, .{ .outputs = &.{.{ .target = .{ .file = .{ .path = "must-not-truncate", .append = false } }, .filter = "invalid" }} }));
    try std.testing.expect(!forbidden.has_induced_failure);
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var bytes: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    const logging = try Logging.create(allocator, std.testing.io, .{
        .outputs = &.{.{ .target = .{ .writer = &writer } }},
    });
    defer logging.destroy();
    _ = try logging.scoped("oom").tryEmit(.info, "valid", .{});
    try logging.shutdown();
}
test "managed logging allocation failure rolls back runtime and output resources" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

fn fileAllocationCase(allocator: std.mem.Allocator, dir: std.Io.Dir) !void {
    const logging = try Logging.create(allocator, std.testing.io, .{ .outputs = &.{.{ .target = .{ .file = .{ .dir = dir, .path = "oom.jsonl", .backend = .portable } }, .format = .json }} });
    defer logging.destroy();
    _ = try logging.scoped("oom").tryEmit(.info, "valid", .{});
    try logging.shutdown();
}

test "managed logging file initialization rolls back each allocation failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, fileAllocationCase, .{tmp.dir});
}

test "managed logging failed prepared attachment releases its channel and shared prepared logger works" {
    const event = @import("../core/event.zig");
    const field = @import("../core/field.zig");
    inline for (.{ .asynchronous, .spsc }) |mode| {
        var bytes: [8192]u8 = undefined;
        var writer = std.Io.Writer.fixed(&bytes);
        const logging = try Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{.{ .target = .{ .writer = &writer }, .mode = mode, .max_threads = 1, .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 } } }} });
        defer logging.destroy();
        const shape: event.Event = .{ .level = .info, .scope = "prepared", .message = "ready", .timestamp_ns = 0, .fields = &.{field.kv("id", @as(u64, 0))} };
        if (mode == .spsc) {
            var bad = shape;
            bad.fields = &.{ field.kv("id", @as(u64, 0)), field.kv("id", @as(u64, 1)) };
            try std.testing.expectError(error.DuplicateKey, logging.attachPreparedThread(bad));
            const log = try logging.attachPreparedThread(shape);
            defer log.detach() catch {};
            try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.info, "ready", .{ .id = @as(u64, 9) }));
        } else {
            const log = try logging.prepared(shape);
            try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.info, "ready", .{ .id = @as(u64, 9) }));
        }
        try logging.shutdown();
        try std.testing.expectEqual(@as(u64, 1), logging.health().written);
    }
}

test "managed logging validates policy and budgets before truncating existing output" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "existing.log", .data = "preserved\n" });
    const output: Logging.Target = .{ .file = .{ .dir = tmp.dir, .path = "existing.log", .append = false, .backend = .portable } };
    const invalid = [_]Logging.Options{
        .{ .outputs = &.{.{ .target = output, .mode = .asynchronous, .max_journal_bytes = 1 }} },
        .{ .outputs = &.{.{ .target = output, .consumer_batches_per_queue = 0 }} },
        .{ .outputs = &.{.{ .target = output, .redaction = &.{.{ .key = "", .action = .mask }} }} },
        .{ .outputs = &.{.{ .target = output, .sampling = .{ .every = 0 } }} },
        .{ .outputs = &.{.{ .target = output, .predicate = "status ==" }} },
        .{ .outputs = &.{.{ .target = output, .format = .binary, .timestamp = .{} }} },
        .{ .outputs = &.{.{ .target = output, .mode = .asynchronous, .reclaim_after = .durable }} },
    };
    for (invalid) |options| {
        const created = Logging.create(std.testing.allocator, std.testing.io, options);
        if (created) |unexpected| {
            unexpected.destroy();
            return error.InvalidConfigurationAccepted;
        } else |_| {}
        const retained = try tmp.dir.readFileAlloc(std.testing.io, "existing.log", std.testing.allocator, .limited(32));
        defer std.testing.allocator.free(retained);
        try std.testing.expectEqualStrings("preserved\n", retained);
    }
}

test "managed logging multiple outputs retain independent formats filters and writer lifetimes" {
    inline for (.{ .sync, .asynchronous, .spsc }) |mode| {
        var json_bytes: [8192]u8 = undefined;
        var text_bytes: [8192]u8 = undefined;
        var json = std.Io.Writer.fixed(&json_bytes);
        var text = std.Io.Writer.fixed(&text_bytes);
        const logging = try Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{ .{ .name = "json", .target = .{ .writer = &json }, .format = .json, .filter = "info", .mode = mode }, .{ .name = "warnings", .target = .{ .writer = &text }, .format = .text, .filter = "warn", .mode = mode } } });
        var live = true;
        defer if (live) logging.destroy();
        {
            const log = if (mode == .spsc) try logging.attachThread("multi") else logging.scoped("multi");
            defer if (mode == .spsc) log.detach() catch {};
            try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.info, "only json", .{ .id = @as(u32, 1) }));
            try std.testing.expectEqual(EmitResult.accepted, try log.tryEmit(.warn, "both outputs", .{ .id = @as(u32, 2) }));
        }
        try logging.flushOutputs(&.{"json"});
        try std.testing.expectError(error.UnsupportedDurability, logging.flushOutputsDurable(&.{"json"}));
        try logging.shutdown();
        try std.testing.expectEqual(@as(u64, 3), logging.health().written);
        logging.destroy();
        live = false;
        try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, json.buffered(), "\n"));
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text.buffered(), "\n"));
        try std.testing.expect(std.mem.indexOf(u8, json.buffered(), "only json") != null);
        try std.testing.expect(std.mem.indexOf(u8, text.buffered(), "only json") == null);
        try std.testing.expect(std.mem.indexOf(u8, text.buffered(), "both outputs") != null);
        try json.writeAll("still owned by caller\n");
        try text.writeAll("still owned by caller\n");
    }
}

fn multiFileAllocationCase(allocator: std.mem.Allocator, dir: std.Io.Dir) !void {
    var bytes: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    const logging = try Logging.create(allocator, std.testing.io, .{
        .outputs = &.{
            .{ .name = "file", .target = .{ .file = .{ .dir = dir, .path = "multi-oom.jsonl", .backend = .portable } } },
            .{ .name = "rolling", .target = .{ .rolling_file = .{ .dir = dir, .path = "rolling-oom.jsonl", .max_bytes = 4096, .retention = 2, .backend = .portable } } },
            .{ .name = "writer", .target = .{ .writer = &writer } },
        },
    });
    defer logging.destroy();
    _ = try logging.scoped("multi").tryEmit(.info, "complete", .{});
    try logging.shutdown();
}

test "managed logging multiple output initialization rolls back partial resources on every allocation failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, multiFileAllocationCase, .{tmp.dir});
}

test "managed logging mmap supports owned file rolling and best effort writer through one entry" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var bytes: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    var journal_path_bytes: [192]u8 = undefined;
    const path = try std.fmt.bufPrint(&journal_path_bytes, ".zig-cache/tmp/{s}/multi.journal", .{tmp.sub_path});
    const options: Logging.Options = .{ .outputs = &.{ .{ .name = "file", .target = .{ .file = .{ .dir = tmp.dir, .path = "multi.jsonl", .backend = .portable } }, .format = .json, .queue = .{ .mmap = .{ .path = path, .capacity = 8, .max_record_bytes = 1024 } }, .mode = .asynchronous }, .{ .name = "rolling", .target = .{ .rolling_file = .{ .dir = tmp.dir, .path = "multi-rolling.jsonl", .max_bytes = 4096, .retention = 2, .backend = .portable } }, .format = .json, .mode = .asynchronous }, .{ .name = "console", .target = .{ .writer = &writer }, .delivery = .best_effort, .filter = "warn", .mode = .asynchronous } } };
    {
        const logging = try Logging.create(std.testing.allocator, std.testing.io, options);
        defer logging.destroy();
        _ = try logging.scoped("multi").tryEmit(.info, "both files", .{});
        _ = try logging.scoped("multi").tryEmit(.warn, "all outputs", .{});
        try logging.flushOutputsDurable(&.{ "file", "rolling" });
        try logging.shutdown();
        try std.testing.expectEqual(@as(u64, 5), logging.health().written);
    }
    const first = try tmp.dir.readFileAlloc(std.testing.io, "multi.jsonl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(first);
    const rolling = try tmp.dir.readFileAlloc(std.testing.io, "multi-rolling.jsonl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(rolling);
    try std.testing.expect(std.mem.indexOf(u8, rolling, "both files") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, first, "\n"));
    const reopened = try Logging.create(std.testing.allocator, std.testing.io, options);
    defer reopened.destroy();
    try reopened.shutdown();
    try std.testing.expectEqual(@as(usize, 0), reopened.health().journal_pending);
}

test "managed logging rejects invalid multiple outputs before allocating" {
    var forbidden = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.InvalidOutputs, Logging.create(forbidden.allocator(), std.testing.io, .{
        .outputs = &.{},
    }));
    try std.testing.expectError(error.DuplicateRoute, Logging.create(forbidden.allocator(), std.testing.io, .{
        .outputs = &.{ .{ .name = "same", .target = .stderr }, .{ .name = "same", .target = .stdout } },
    }));
    try std.testing.expectError(error.InvalidLevel, Logging.create(forbidden.allocator(), std.testing.io, .{
        .outputs = &.{.{ .name = "bad", .target = .stderr, .filter = "bad-level" }},
    }));
    try std.testing.expectError(error.DuplicateOutputTarget, Logging.create(forbidden.allocator(), std.testing.io, .{
        .outputs = &.{
            .{ .name = "first", .target = .{ .file = .{ .path = "must-not-create.jsonl", .append = false } } },
            .{ .name = "second", .target = .{ .file = .{ .path = "must-not-create.jsonl", .append = false } } },
        },
    }));
    try std.testing.expect(!forbidden.has_induced_failure);
}

test "managed logging std log binding cleanup cannot unbind another owner" {
    var first_bytes: [4096]u8 = undefined;
    var second_bytes: [4096]u8 = undefined;
    var first_writer = std.Io.Writer.fixed(&first_bytes);
    var second_writer = std.Io.Writer.fixed(&second_bytes);
    const first = try Logging.create(std.testing.allocator, std.testing.io, .{
        .outputs = &.{.{ .target = .{ .writer = &first_writer } }},
    });
    var first_live = true;
    defer if (first_live) first.destroy();
    const second = try Logging.create(std.testing.allocator, std.testing.io, .{
        .outputs = &.{.{ .target = .{ .writer = &second_writer } }},
    });
    defer second.destroy();
    try first.bindStdLog();
    try std.testing.expectError(error.AlreadyBound, second.bindStdLog());
    Logging.std_log.logFn(.info, .managed, "first {d}", .{@as(u32, 1)});
    first.unbindStdLog();
    try second.bindStdLog();
    first.destroy();
    first_live = false;
    Logging.std_log.logFn(.info, .managed, "second {d}", .{@as(u32, 2)});
    second.unbindStdLog();
    try second.shutdown();
    try std.testing.expect(std.mem.indexOf(u8, first_writer.buffered(), "first 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, second_writer.buffered(), "second 2") != null);
}

test "managed logging accepts memory-only CRC opt-out" {
    inline for (.{ .asynchronous, .spsc }) |mode| {
        var bytes: [4096]u8 = undefined;
        var writer = std.Io.Writer.fixed(&bytes);
        const logging = try Logging.create(std.testing.allocator, std.testing.io, .{ .outputs = &.{.{
            .target = .{ .writer = &writer },
            .mode = mode,
            .max_threads = 1,
            .format = .json,
            .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 512, .verify_crc = false } },
        }} });
        var live = true;
        defer if (live) logging.destroy();
        const base = if (mode == .spsc) try logging.attachThread("fast") else logging.scoped("fast");
        var attached = mode == .spsc;
        defer if (attached) base.detach() catch {};
        _ = try base.tryEmit(.info, "fast", .{});
        if (mode == .spsc) {
            try base.detach();
            attached = false;
        }
        try logging.flush();
        try logging.shutdown();
        live = false;
        logging.destroy();
        try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "fast") != null);
    }
}
