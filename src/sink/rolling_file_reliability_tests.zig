const std = @import("std");
const RollingFileSink = @import("rolling_file.zig").RollingFileSink;
const FileSink = @import("file.zig").FileSink;
const directory_sync = @import("../backend/directory_sync.zig");
const testing = std.testing;

fn unsupportedFile(_: std.Io, _: std.Io.File) anyerror!void {
    return error.UnsupportedDurability;
}
fn unsupportedDirectory(_: std.Io, _: std.Io.Dir) anyerror!void {
    return error.UnsupportedDurability;
}

test "ordinary size rotation makes no implicit file or directory sync request" {
    const Fault = struct {
        threadlocal var calls: usize = 0;
        fn sync(_: ?*anyopaque, _: std.Io.File) std.Io.File.SyncError!void {
            calls += 1;
            return error.InputOutput;
        }
    };
    Fault.calls = 0;
    var vtable = testing.io.vtable.*;
    vtable.fileSync = Fault.sync;
    const io: std.Io = .{ .userdata = testing.io.userdata, .vtable = &vtable };
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(testing.allocator, io, .{ .path = "written.log", .dir = tmp.dir, .max_bytes = 4, .retention = 1, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("one\n");
    try output.writeRecord("two\n");
    try output.flush();
    try testing.expectEqual(@as(usize, 0), Fault.calls);
    try testing.expectEqual(@as(usize, 1), output.rollover_count);
}

test "tracked archive disappearance is an error before durable directory confirmation" {
    if (!directory_sync.supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(testing.allocator, testing.io, .{ .path = "missing.log", .dir = tmp.dir, .max_bytes = 4, .retention = 2, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("one\n");
    try output.writeRecord("two\n");
    try output.flush();
    try tmp.dir.deleteFile(testing.io, "missing.log.1");
    try testing.expectError(error.FileNotFound, output.sync());
    try testing.expectError(error.FileNotFound, output.writeRecord("bad\n"));
}

test "ordinary rotation remains written when strict media durability is unsupported" {
    if (!directory_sync.supported) return error.SkipZigTest;
    directory_sync.TestingHooks.strict_file = unsupportedFile;
    directory_sync.TestingHooks.strict_directory = unsupportedDirectory;
    defer {
        directory_sync.TestingHooks.strict_file = null;
        directory_sync.TestingHooks.strict_directory = null;
    }
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(testing.allocator, testing.io, .{ .path = "ordinary.log", .dir = tmp.dir, .max_bytes = 4, .retention = 2, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("one\n");
    try output.writeRecord("two\n");
    try output.flush();
    try testing.expectEqual(@as(usize, 1), output.rollover_count);
    try testing.expectError(error.UnsupportedDurability, output.sync());
    try testing.expect(output.failure == null);
    try output.writeRecord("tri\n");
    try output.flush();
    try testing.expectEqual(@as(usize, 2), output.rollover_count);
    const active = try tmp.dir.readFileAlloc(testing.io, "ordinary.log", testing.allocator, .limited(64));
    defer testing.allocator.free(active);
    try testing.expectEqualStrings("tri\n", active);
    const oldest = try tmp.dir.readFileAlloc(testing.io, "ordinary.log.2", testing.allocator, .limited(64));
    defer testing.allocator.free(oldest);
    try testing.expectEqualStrings("one\n", oldest);
}

test "explicit rolling sync covers current and preexisting retained archives before directory confirmation" {
    if (!directory_sync.supported) return error.SkipZigTest;
    const Tracker = struct {
        threadlocal var sizes: [4]u64 = @splat(0);
        threadlocal var files: usize = 0;
        threadlocal var directory_after: usize = 0;
        fn file(io: std.Io, handle: std.Io.File) anyerror!void {
            sizes[files] = (try handle.stat(io)).size;
            files += 1;
            try handle.sync(io);
        }
        fn directory(io: std.Io, dir: std.Io.Dir) anyerror!void {
            directory_after = files;
            const handle: std.Io.File = .{ .handle = dir.handle, .flags = .{ .nonblocking = false } };
            try handle.sync(io);
        }
    };
    Tracker.files = 0;
    Tracker.directory_after = 0;
    directory_sync.TestingHooks.strict_file = Tracker.file;
    directory_sync.TestingHooks.strict_directory = Tracker.directory;
    defer {
        directory_sync.TestingHooks.strict_file = null;
        directory_sync.TestingHooks.strict_directory = null;
    }
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "retained.log.1", .data = "old\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "retained.log.2", .data = "older\n" });
    const output = try RollingFileSink.create(testing.allocator, testing.io, .{ .path = "retained.log", .dir = tmp.dir, .max_bytes = 64, .retention = 3, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("active\n");
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    output.allocator = failing.allocator();
    defer output.allocator = testing.allocator;
    try output.sync();
    try testing.expectEqual(@as(usize, 3), Tracker.files);
    try testing.expectEqual(@as(usize, 3), Tracker.directory_after);
    try testing.expectEqualSlices(u64, &.{ 7, 4, 6 }, Tracker.sizes[0..3]);
    try testing.expect(!failing.has_induced_failure);
}

test "external reopen remembers unsupported old media durability without blocking later written logs" {
    directory_sync.TestingHooks.strict_file = unsupportedFile;
    defer directory_sync.TestingHooks.strict_file = null;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(testing.allocator, testing.io, .{ .path = "reopened.log", .dir = tmp.dir, .max_bytes = 64, .retention = 1, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("old\n");
    try tmp.dir.rename("reopened.log", tmp.dir, "external.log", testing.io);
    try output.reopen();
    try testing.expect(!output.historical_durable_supported);
    try testing.expect(!output.sink().supports_durable);
    try output.writeRecord("new\n");
    try output.flush();
    try testing.expectError(error.UnsupportedDurability, output.sync());
    try testing.expect(output.failure == null);
    const old = try tmp.dir.readFileAlloc(testing.io, "external.log", testing.allocator, .limited(64));
    defer testing.allocator.free(old);
    try testing.expectEqualStrings("old\n", old);
}

test "cross-directory external reopen cannot certify the unknown destination even after file sync succeeds" {
    if (!directory_sync.supported) return error.SkipZigTest;
    const Flush = struct {
        fn file(io: std.Io, handle: std.Io.File) anyerror!void {
            try handle.sync(io);
        }
    };
    directory_sync.TestingHooks.strict_file = Flush.file;
    defer directory_sync.TestingHooks.strict_file = null;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(testing.io, "a", .default_dir);
    try tmp.dir.createDir(testing.io, "b", .default_dir);
    const output = try RollingFileSink.create(testing.allocator, testing.io, .{ .path = "a/current.log", .dir = tmp.dir, .max_bytes = 64, .retention = 1, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    const borrowed_sink = output.sink();
    try testing.expect(borrowed_sink.supports_durable);
    try output.writeRecord("old\n");
    try tmp.dir.rename("a/current.log", tmp.dir, "b/external.log", testing.io);
    try output.reopen();
    try output.writeRecord("new\n");
    try output.flush();
    try testing.expectError(error.UnsupportedDurability, borrowed_sink.sync());
    try testing.expectError(error.UnsupportedDurability, output.sink().sync());
    try testing.expect(output.failure == null);
    const old = try tmp.dir.readFileAlloc(testing.io, "b/external.log", testing.allocator, .limited(64));
    defer testing.allocator.free(old);
    const current = try tmp.dir.readFileAlloc(testing.io, "a/current.log", testing.allocator, .limited(64));
    defer testing.allocator.free(current);
    try testing.expectEqualStrings("old\n", old);
    try testing.expectEqualStrings("new\n", current);
}

test "unsupported file or directory durability does not poison ordinary FileSink writes" {
    if (!directory_sync.supported) return error.SkipZigTest;
    inline for (.{ false, true }) |directory| {
        if (directory) directory_sync.TestingHooks.strict_directory = unsupportedDirectory else directory_sync.TestingHooks.strict_file = unsupportedFile;
        defer {
            directory_sync.TestingHooks.strict_file = null;
            directory_sync.TestingHooks.strict_directory = null;
        }
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        const output = try FileSink.create(testing.allocator, testing.io, .{ .path = "file.log", .dir = tmp.dir, .backend = .portable, .buffer_bytes = 16 });
        defer output.deinit();
        try output.writeRecord("before\n");
        try testing.expectError(error.UnsupportedDurability, output.sync());
        try testing.expect(output.failure == null);
        try output.writeRecord("after\n");
        try output.flush();
        try testing.expectEqual(@as(u64, 13), output.writtenBytes());
    }
}

test "rolling archive I/O sync failure latches and stops later admission" {
    if (!directory_sync.supported) return error.SkipZigTest;
    const Fault = struct {
        threadlocal var calls: usize = 0;
        fn file(io: std.Io, handle: std.Io.File) anyerror!void {
            calls += 1;
            if (calls == 2) return error.InputOutput;
            try handle.sync(io);
        }
    };
    Fault.calls = 0;
    directory_sync.TestingHooks.strict_file = Fault.file;
    defer directory_sync.TestingHooks.strict_file = null;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "failure.log.1", .data = "archive\n" });
    const output = try RollingFileSink.create(testing.allocator, testing.io, .{ .path = "failure.log", .dir = tmp.dir, .max_bytes = 64, .retention = 1, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("active\n");
    try testing.expectError(error.InputOutput, output.sync());
    try testing.expectEqual(@as(usize, 2), Fault.calls);
    try testing.expectError(error.InputOutput, output.writeRecord("blocked\n"));
    try testing.expectError(error.InputOutput, output.flush());
}

test "rolling initialization allocation failures release tracked archive metadata" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const Context = struct {
        fn create(allocator: std.mem.Allocator, dir: std.Io.Dir) !void {
            const output = try RollingFileSink.create(allocator, testing.io, .{ .path = "oom.log", .dir = dir, .max_bytes = 64, .retention = 3, .buffer_bytes = 16, .backend = .portable });
            defer output.deinit();
        }
    };
    try testing.checkAllAllocationFailures(testing.allocator, Context.create, .{tmp.dir});
}
