const std = @import("std");
const Sink = @import("interface.zig").Sink;
const Backend = @import("../backend/interface.zig").Backend;
const directory_sync = @import("../backend/directory_sync.zig");
pub const BackendKind = @import("../backend/interface.zig").Kind;

/// Owns a file, a bounded staging buffer and its backend resources. One owner
/// serializes records. Successful writeRecord means accepted; flush drains all
/// staging and kernel requests before it reports written. Errors after partial
/// I/O latch and prohibit blind retry of a possibly written prefix.
pub const FileSink = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    parent_dir: std.Io.Dir,
    path: []u8,
    recovery_identity: []u8,
    file: std.Io.File,
    backend: Backend,
    buffer: []u8,
    buffered: usize = 0,
    accepted_offset: u64,
    failure: ?anyerror = null,
    closed: bool = false,

    pub const Options = struct {
        path: []const u8,
        /// Borrowed during initialization; the sink owns its parent directory.
        /// cwd is the default.
        dir: ?std.Io.Dir = null,
        buffer_bytes: usize = 64 * 1024,
        backend: BackendKind = .auto,
        queue_depth: u16 = 4,
        append: bool = true,
    };

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*FileSink {
        if (options.path.len == 0 or options.buffer_bytes == 0 or options.buffer_bytes > std.math.maxInt(u32)) return error.InvalidFileOptions;
        if (std.fs.path.isSep(options.path[options.path.len - 1])) return error.InvalidFileOptions;
        const dir = options.dir orelse std.Io.Dir.cwd();
        const self = try allocator.create(FileSink);
        errdefer allocator.destroy(self);
        const path = try allocator.dupe(u8, options.path);
        errdefer allocator.free(path);
        const buffer = try allocator.alloc(u8, options.buffer_bytes);
        errdefer allocator.free(buffer);
        @memset(buffer, 0);
        const parent_dir = try dir.openDir(io, std.fs.path.dirname(path) orelse ".", .{ .iterate = true });
        errdefer parent_dir.close(io);
        var parent_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const parent_path_len = try parent_dir.realPath(io, &parent_path_buffer);
        const recovery_identity = try std.fs.path.join(allocator, &.{ parent_path_buffer[0..parent_path_len], std.fs.path.basename(path) });
        errdefer allocator.free(recovery_identity);
        // Explicit offsets require a normal writable file, without O_APPEND.
        // Open through the same owned parent that supplied the identity.
        const file = try parent_dir.createFile(io, std.fs.path.basename(path), .{ .truncate = !options.append });
        errdefer file.close(io);
        const stat = try file.stat(io);
        if (stat.kind != .file) return error.NotRegularFile;
        const backend = try Backend.init(allocator, io, file, stat.size, options.buffer_bytes, options.queue_depth, options.backend);
        self.* = .{ .allocator = allocator, .io = io, .dir = parent_dir, .parent_dir = parent_dir, .path = path, .recovery_identity = recovery_identity, .file = file, .backend = backend, .buffer = buffer, .accepted_offset = stat.size };
        return self;
    }

    /// Call flush/sync/shutdown explicitly when an error needs to be observed.
    /// deinit attempts flush and always drains original kernel requests before
    /// freeing resources. An undrainable ring transport failure is fatal.
    pub fn deinit(self: *FileSink) void {
        self.flush() catch {};
        self.backend.deinit();
        self.file.close(self.io);
        self.parent_dir.close(self.io);
        const allocator = self.allocator;
        allocator.free(self.buffer);
        allocator.free(self.path);
        allocator.free(self.recovery_identity);
        allocator.destroy(self);
    }

    pub fn sink(self: *FileSink) Sink {
        return .{ .context = self, .vtable = &vtable, .supports_durable = directory_sync.supported, .recovery_identity = self.recovery_identity };
    }

    pub fn selectedBackend(self: *const FileSink) BackendKind {
        return self.backend.kind();
    }

    pub fn acceptedBytes(self: *const FileSink) u64 {
        return self.accepted_offset;
    }

    /// Byte progress is diagnostic. Record acknowledgement requires flush to
    /// succeed; a failed partial write can leave an incomplete trailing record.
    pub fn writtenBytes(self: *const FileSink) u64 {
        return self.backend.writtenOffset();
    }

    pub fn writeRecord(self: *FileSink, record: []const u8) !void {
        try self.check();
        if (record.len > self.buffer.len) return error.RecordTooLarge;
        if (record.len > std.math.maxInt(u64) - self.acceptedBytes()) return error.OffsetOverflow;
        if (record.len > self.buffer.len - self.buffered) try self.sendBuffered();
        @memcpy(self.buffer[self.buffered..][0..record.len], record);
        self.buffered += record.len;
        self.accepted_offset += record.len;
    }

    pub fn flush(self: *FileSink) !void {
        try self.check();
        try self.sendBuffered();
        self.backend.flush() catch |err| {
            self.failure = err;
            return err;
        };
    }

    pub fn sync(self: *FileSink) !void {
        if (!directory_sync.supported) return error.UnsupportedDurability;
        try self.syncData();
        directory_sync.sync(self.io, self.parent_dir) catch |err| {
            if (err != error.UnsupportedDurability) self.failure = err;
            return err;
        };
    }

    /// Flush completed file data without certifying the containing entry.
    pub fn syncData(self: *FileSink) !void {
        try self.flush();
        self.backend.sync() catch |err| {
            if (err != error.UnsupportedDurability) self.failure = err;
            return err;
        };
    }

    pub fn shutdown(self: *FileSink) !void {
        if (self.closed) {
            // A prior transport error can leave owned requests in flight.
            // Repeated shutdown still retries their completion barrier.
            self.backend.shutdown() catch |err| {
                if (self.failure == null) self.failure = err;
                return err;
            };
            if (self.failure) |err| return err;
            return;
        }
        var failure: ?anyerror = null;
        self.flush() catch |err| {
            failure = err;
        };
        self.backend.shutdown() catch |err| {
            if (failure == null) failure = err;
        };
        // The backend can report a transport error while references remain.
        // closed only rejects admissions; deinit still drains the backend.
        self.closed = true;
        if (failure) |err| {
            self.failure = err;
            return err;
        }
    }

    fn check(self: *const FileSink) !void {
        if (self.failure) |err| return err;
        if (self.closed) return error.Closed;
    }

    fn sendBuffered(self: *FileSink) !void {
        if (self.buffered == 0) return;
        self.backend.writeBatch(self.buffer[0..self.buffered]) catch |err| {
            self.failure = err;
            return err;
        };
        self.buffered = 0;
    }

    fn writeErased(context: *anyopaque, record: []const u8) anyerror!void {
        return (@as(*FileSink, @ptrCast(@alignCast(context)))).writeRecord(record);
    }
    fn flushErased(context: *anyopaque) anyerror!void {
        return (@as(*FileSink, @ptrCast(@alignCast(context)))).flush();
    }
    fn syncErased(context: *anyopaque) anyerror!void {
        return (@as(*FileSink, @ptrCast(@alignCast(context)))).sync();
    }
    const vtable: Sink.VTable = .{ .writeRecord = writeErased, .flush = flushErased, .sync = syncErased };
};

test "file buffering flush append sync and oversize records" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log", .dir = tmp.dir, .buffer_bytes = 8, .backend = .portable });
    try output.sink().writeRecord("one\n");
    try std.testing.expectEqual(@as(u64, 0), (try output.file.stat(std.testing.io)).size);
    try std.testing.expectError(error.RecordTooLarge, output.sink().writeRecord("oversized\n"));
    try output.sink().writeRecord("two\n");
    try output.sink().writeRecord("three\n");
    try std.testing.expectEqual(@as(u64, 8), output.writtenBytes());
    try output.sink().flush();
    try std.testing.expectEqual(@as(u64, 14), output.writtenBytes());
    if (directory_sync.supported) try output.sink().sync() else try std.testing.expectError(error.UnsupportedDurability, output.sink().sync());
    output.deinit();
    const reopened = try FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log", .dir = tmp.dir, .buffer_bytes = 8, .backend = .portable });
    defer reopened.deinit();
    try reopened.writeRecord("four\n");
    try reopened.flush();
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "output.log", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("one\ntwo\nthree\nfour\n", bytes);
    try reopened.shutdown();
    try reopened.shutdown();
    try std.testing.expectError(error.Closed, reopened.writeRecord("late\n"));
}

test "auto selects a visible backend and explicit unsupported io_uring does not fall back" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "auto.log", .dir = tmp.dir, .backend = .auto });
    defer output.deinit();
    try output.writeRecord("auto\n");
    try output.flush();
    @import("../backend/linux_uring.zig").LinuxUring.probe() catch |err| switch (err) {
        error.Unsupported => {
            try std.testing.expectEqual(BackendKind.portable, output.selectedBackend());
            try std.testing.expectError(error.Unsupported, FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "uring.log", .dir = tmp.dir, .backend = .linux_uring }));
            return;
        },
        else => return err,
    };
    try std.testing.expectEqual(BackendKind.linux_uring, output.selectedBackend());
}

test "file sink observes short writes zero progress disk errors and failed sync" {
    const Fault = struct {
        var active: ?*@This() = null;
        original: std.Io,
        writes: usize = 0,
        fail_after: ?usize = null,
        zero_after: ?usize = null,
        fail_sync: bool = false,

        fn write(userdata: ?*anyopaque, file: std.Io.File, _: []const u8, data: []const []const u8, _: usize, offset: u64) std.Io.File.WritePositionalError!usize {
            const self = active.?;
            if (self.fail_after) |limit| if (self.writes >= limit) return error.NoSpaceLeft;
            if (self.zero_after) |limit| if (self.writes >= limit) return 0;
            self.writes += 1;
            const bytes = data[0][0..@min(2, data[0].len)];
            return self.original.vtable.fileWritePositional(userdata, file, &.{}, &.{bytes}, 1, offset);
        }

        fn sync(userdata: ?*anyopaque, file: std.Io.File) std.Io.File.SyncError!void {
            const self = active.?;
            if (self.fail_sync) return error.InputOutput;
            return self.original.vtable.fileSync(userdata, file);
        }
    };
    var fault: Fault = .{ .original = std.testing.io };
    Fault.active = &fault;
    defer Fault.active = null;
    var vtable_copy = std.testing.io.vtable.*;
    vtable_copy.fileWritePositional = Fault.write;
    vtable_copy.fileSync = Fault.sync;
    const io: std.Io = .{ .userdata = std.testing.io.userdata, .vtable = &vtable_copy };
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const short = try FileSink.create(std.testing.allocator, io, .{ .path = "short.log", .dir = tmp.dir, .buffer_bytes = 8, .backend = .portable });
    defer short.deinit();
    try short.writeRecord("hello");
    try short.flush();
    try std.testing.expectEqual(@as(usize, 3), fault.writes);
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "short.log", std.testing.allocator, .limited(32));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("hello", bytes);

    fault.writes = 0;
    fault.zero_after = 1;
    const zero = try FileSink.create(std.testing.allocator, io, .{ .path = "zero.log", .dir = tmp.dir, .buffer_bytes = 8, .backend = .portable });
    defer zero.deinit();
    try zero.writeRecord("hello");
    try std.testing.expectError(error.WriteZero, zero.flush());
    try std.testing.expectEqual(@as(u64, 2), zero.writtenBytes());
    try std.testing.expectEqual(@as(u64, 5), zero.acceptedBytes());
    try std.testing.expectError(error.WriteZero, zero.writeRecord("next"));
    try std.testing.expectError(error.WriteZero, zero.shutdown());
    try std.testing.expectError(error.WriteZero, zero.shutdown());

    fault.writes = 0;
    fault.zero_after = null;
    fault.fail_after = 1;
    const disk = try FileSink.create(std.testing.allocator, io, .{ .path = "disk.log", .dir = tmp.dir, .buffer_bytes = 8, .backend = .portable });
    defer disk.deinit();
    try disk.writeRecord("hello");
    try std.testing.expectError(error.NoSpaceLeft, disk.flush());
    try std.testing.expectEqual(@as(u64, 2), disk.writtenBytes());
    try std.testing.expectError(error.NoSpaceLeft, disk.flush());

    fault.writes = 0;
    fault.fail_after = null;
    fault.fail_sync = true;
    const sync_error = try FileSink.create(std.testing.allocator, io, .{ .path = "sync.log", .dir = tmp.dir, .buffer_bytes = 8, .backend = .portable });
    defer sync_error.deinit();
    try sync_error.writeRecord("hello");
    if (directory_sync.supported) {
        try std.testing.expectError(error.InputOutput, sync_error.sync());
        try std.testing.expectEqual(@as(u64, 5), sync_error.writtenBytes());
        try std.testing.expectError(error.InputOutput, sync_error.writeRecord("next"));
    } else {
        try std.testing.expectError(error.UnsupportedDurability, sync_error.sync());
    }
}

test "file record writes and flushes use only initialization allocations" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const kinds = [_]BackendKind{ .portable, .auto };
    for (kinds, 0..) |kind, index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const output = try FileSink.create(failing.allocator(), std.testing.io, .{ .path = if (index == 0) "portable.log" else "auto.log", .dir = tmp.dir, .buffer_bytes = 16, .backend = kind });
        defer output.deinit();
        const initialization_allocations = failing.allocations;
        failing.fail_index = failing.alloc_index;
        failing.resize_fail_index = failing.resize_index;
        for (0..100) |record| {
            try output.writeRecord("hello\n");
            if (record % 20 == 0) try output.flush();
        }
        try output.flush();
        if (directory_sync.supported) try output.sync();
        try std.testing.expectEqual(@as(u64, 600), output.writtenBytes());
        try std.testing.expectEqual(initialization_allocations, failing.allocations);
        try std.testing.expect(!failing.has_induced_failure);
    }
}

test "file recovery identity canonicalizes the owned parent and distinguishes targets" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "first", .default_dir);
    try tmp.dir.createDir(std.testing.io, "second", .default_dir);
    try std.testing.expectError(error.InvalidFileOptions, FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "first/", .dir = tmp.dir, .backend = .portable }));
    const original = try FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "first/output.log", .dir = tmp.dir, .backend = .portable });
    defer original.deinit();
    const first_dir = try tmp.dir.openDir(std.testing.io, "first", .{});
    const equivalent = FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "./output.log", .dir = first_dir, .backend = .portable }) catch |err| {
        first_dir.close(std.testing.io);
        return err;
    };
    first_dir.close(std.testing.io);
    defer equivalent.deinit();
    const renamed = try FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "first/different.log", .dir = tmp.dir, .backend = .portable });
    defer renamed.deinit();
    const relocated = try FileSink.create(std.testing.allocator, std.testing.io, .{ .path = "second/output.log", .dir = tmp.dir, .backend = .portable });
    defer relocated.deinit();
    const identity = original.sink().recovery_identity.?;
    try std.testing.expect(std.fs.path.isAbsolute(identity));
    try std.testing.expectEqualStrings(identity, equivalent.sink().recovery_identity.?);
    try std.testing.expect(!std.mem.eql(u8, identity, renamed.sink().recovery_identity.?));
    try std.testing.expect(!std.mem.eql(u8, identity, relocated.sink().recovery_identity.?));
    var absolute_parent: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const parent_len = try original.parent_dir.realPath(std.testing.io, &absolute_parent);
    const expected = try std.fs.path.join(std.testing.allocator, &.{ absolute_parent[0..parent_len], "output.log" });
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, identity);
    // The initialization directory is already closed. Identity is stored on
    // the sink, so emitting and flushing cannot recalculate it from cwd.
    try equivalent.writeRecord("bound\n");
    try equivalent.flush();
    try std.testing.expectEqualStrings(identity, equivalent.sink().recovery_identity.?);
}
