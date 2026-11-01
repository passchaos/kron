const std = @import("std");
const Sink = @import("interface.zig").Sink;
const FileSink = @import("file.zig").FileSink;
const BackendKind = @import("file.zig").BackendKind;
const directory_sync = @import("../backend/directory_sync.zig");
const Clock = @import("../platform/clock.zig").Clock;

/// Size/time-based, whole-record rolling. path is active, path.1 is newest, and
/// path.retention is oldest. This sink owns its files and archive path storage.
/// A single owner must serialize calls. A failed rotation latches rather than
/// silently appending to an unexpected destination or retrying shifted names.
pub const RollingFileSink = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    path: []u8,
    recovery_identity: []u8,
    archive_paths: [][]u8,
    archive_present: []bool,
    parent_dir: std.Io.Dir,
    current: ?*FileSink,
    failure: ?anyerror = null,
    rollover_count: usize = 0,
    closed: bool = false,
    rotation_epoch_ns: u64 = 0,
    last_rotation_clock_ns: u64 = 0,
    rotation_deadline_ns: ?u64 = null,
    /// External reopen can close an old target whose name the library does
    /// not control. Without its target directory, later sync cannot certify
    /// that forgotten generation even when the old file data was synchronized.
    historical_durable_supported: bool = true,

    pub const Options = struct {
        path: []const u8,
        dir: ?std.Io.Dir = null,
        /// null disables size rotation; then rotation_interval_ns is required.
        max_bytes: ?u64 = null,
        /// Number of archived files in addition to the active file; zero
        /// truncates at rollover. Automatic retention is intentionally bounded.
        retention: u16,
        buffer_bytes: usize = 64 * 1024,
        backend: BackendKind = .auto,
        queue_depth: u16 = 4,
        /// Optional monotonic interval, checked only at nonempty record
        /// boundaries. null retains size-only rolling without clock reads.
        /// Creation and successful reopen reset the epoch; mtime and elapsed
        /// time from an earlier process are intentionally not recovered.
        rotation_interval_ns: ?u64 = null,
        /// Only monotonic_now is used. Context is borrowed for the sink lifetime.
        clock: Clock = .{},

        pub fn validate(self: Options) !void {
            if (self.path.len == 0 or self.retention > 1024) return error.InvalidRollingOptions;
            if (self.max_bytes) |limit| if (limit == 0) return error.InvalidRollingOptions;
            if (self.max_bytes == null and self.rotation_interval_ns == null) return error.InvalidRollingOptions;
            if (std.fs.path.isSep(self.path[self.path.len - 1])) return error.InvalidRollingOptions;
            if (self.rotation_interval_ns) |interval| if (interval == 0) return error.InvalidRollingOptions;
        }
    };

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*RollingFileSink {
        try options.validate();
        const dir = options.dir orelse std.Io.Dir.cwd();
        const self = try allocator.create(RollingFileSink);
        errdefer allocator.destroy(self);
        // Bind all future opens and renames to our owned parent directory.
        // A borrowed initialization directory may close or cwd may change.
        const path = try allocator.dupe(u8, std.fs.path.basename(options.path));
        errdefer allocator.free(path);
        const paths = try allocator.alloc([]u8, options.retention);
        var initialized: usize = 0;
        errdefer {
            for (paths[0..initialized]) |archive| allocator.free(archive);
            allocator.free(paths);
        }
        for (paths, 1..) |*archive, number| {
            archive.* = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ path, number });
            initialized += 1;
        }
        const parent_dir = try dir.openDir(io, std.fs.path.dirname(options.path) orelse ".", .{ .iterate = true });
        errdefer parent_dir.close(io);
        const present = try allocator.alloc(bool, paths.len);
        errdefer allocator.free(present);
        for (paths, present) |archive, *exists| {
            const stat = parent_dir.statFile(io, archive, .{ .follow_symlinks = false }) catch |err| switch (err) {
                error.FileNotFound => {
                    exists.* = false;
                    continue;
                },
                else => return err,
            };
            if (stat.kind != .file) return error.NotRegularFile;
            exists.* = true;
        }
        var resolved_options = options;
        resolved_options.path = path;
        resolved_options.dir = parent_dir;
        const current = try FileSink.create(allocator, io, fileOptions(resolved_options, path, true));
        errdefer current.deinit();
        // Own the logical active target separately from each file generation,
        // so borrowed Sink identities stay valid across rollover and reopen.
        const recovery_identity = try allocator.dupe(u8, current.recovery_identity);
        self.* = .{ .allocator = allocator, .io = io, .options = resolved_options, .path = path, .recovery_identity = recovery_identity, .archive_paths = paths, .archive_present = present, .parent_dir = parent_dir, .current = current };
        if (options.rotation_interval_ns != null) self.resetRotationEpoch(options.clock.monotonicNow(io));
        return self;
    }

    pub fn deinit(self: *RollingFileSink) void {
        if (self.current) |current| current.deinit();
        self.parent_dir.close(self.io);
        const allocator = self.allocator;
        for (self.archive_paths) |archive| allocator.free(archive);
        allocator.free(self.archive_paths);
        allocator.free(self.archive_present);
        allocator.free(self.path);
        allocator.free(self.recovery_identity);
        allocator.destroy(self);
    }

    pub fn sink(self: *RollingFileSink) Sink {
        return .{ .context = self, .vtable = &vtable, .supports_durable = directory_sync.supported and self.historical_durable_supported, .recovery_identity = self.recovery_identity };
    }

    pub fn writeRecord(self: *RollingFileSink, record: []const u8) !void {
        try self.check();
        if (record.len > self.options.buffer_bytes) return error.RecordTooLarge;
        if (self.options.max_bytes) |limit| if (record.len > limit) return error.RecordTooLarge;
        const size = self.current.?.acceptedBytes();
        const now = if (self.options.rotation_interval_ns != null and record.len != 0) self.rotationNow() else null;
        const size_due = if (self.options.max_bytes) |limit| size > limit or record.len > limit - size else false;
        const time_due = if (now) |value| size != 0 and self.rotationTimeDue(value) else false;
        if (size_due or time_due) {
            self.rollover() catch |err| {
                self.failure = err;
                return err;
            };
            if (now) |value| self.resetRotationEpoch(value) else if (self.options.rotation_interval_ns != null) self.resetRotationEpoch(self.last_rotation_clock_ns);
        }
        self.current.?.writeRecord(record) catch |err| {
            self.failure = err;
            return err;
        };
        // Long idle periods with an empty active file produce no empty archive.
        // Start its interval when the first actual bytes are accepted.
        if (size == 0 and !size_due and !time_due) if (now) |value| self.resetRotationEpoch(value);
    }

    pub fn flush(self: *RollingFileSink) !void {
        try self.check();
        self.current.?.flush() catch |err| {
            self.failure = err;
            return err;
        };
    }

    pub fn sync(self: *RollingFileSink) !void {
        if (!directory_sync.supported or !self.historical_durable_supported) return error.UnsupportedDurability;
        try self.check();
        self.current.?.syncData() catch |err| {
            if (err != error.UnsupportedDurability) self.failure = err;
            return err;
        };
        // Explicit durability covers all retained file generations, including
        // archives that predate this process. Reopen one bounded path at a
        // time; no allocation or persistent descriptor list is required.
        for (self.archive_paths, self.archive_present) |archive, present| {
            if (!present) continue;
            const file = self.parent_dir.openFile(self.io, archive, .{ .mode = .read_write }) catch |err| {
                self.failure = err;
                return err;
            };
            defer file.close(self.io);
            directory_sync.syncFile(self.io, file) catch |err| {
                if (err != error.UnsupportedDurability) self.failure = err;
                return err;
            };
        }
        directory_sync.sync(self.io, self.parent_dir) catch |err| {
            if (err != error.UnsupportedDurability) self.failure = err;
            return err;
        };
    }

    /// Explicitly reopen path after an external rename. The old file data is
    /// drained and strict sync is attempted before freeing its descriptor. The
    /// external destination directory is unknown, so successful reopen retires
    /// historical durable capability. Written logging can continue normally.
    /// Reopen does not repair an already failed or partially shifted file set.
    pub fn reopen(self: *RollingFileSink) !void {
        try self.check();
        self.finishCurrent() catch |err| {
            self.failure = err;
            return err;
        };
        self.current.?.syncData() catch |err| switch (err) {
            error.UnsupportedDurability => self.historical_durable_supported = false,
            else => {
                self.failure = err;
                return err;
            },
        };
        const replacement = FileSink.create(self.allocator, self.io, fileOptions(self.options, self.path, true)) catch |err| {
            self.failure = err;
            return err;
        };
        self.current.?.deinit();
        self.current = replacement;
        self.historical_durable_supported = false;
        if (self.options.rotation_interval_ns != null) self.resetRotationEpoch(self.rotationNow());
    }

    pub fn shutdown(self: *RollingFileSink) !void {
        if (self.closed) {
            if (self.current) |current| try current.shutdown();
            if (self.failure) |err| return err;
            return;
        }
        self.closed = true;
        if (self.current) |current| current.shutdown() catch |err| {
            self.failure = err;
            return err;
        };
        if (self.failure) |err| return err;
    }

    fn check(self: *const RollingFileSink) !void {
        if (self.failure) |err| return err;
        if (self.closed) return error.Closed;
        if (self.current == null) return error.Closed;
    }

    fn finishCurrent(self: *RollingFileSink) !void {
        try self.current.?.flush();
        try self.current.?.backend.shutdown();
    }

    /// Ignore backwards observations without moving the high-water reading.
    /// Size-triggered rotations may still proceed using the retained epoch.
    fn rotationNow(self: *RollingFileSink) u64 {
        const observed = self.options.clock.monotonicNow(self.io);
        if (observed >= self.last_rotation_clock_ns) self.last_rotation_clock_ns = observed;
        return self.last_rotation_clock_ns;
    }

    fn resetRotationEpoch(self: *RollingFileSink, now: u64) void {
        self.rotation_epoch_ns = now;
        self.last_rotation_clock_ns = now;
        self.rotation_deadline_ns = now +| self.options.rotation_interval_ns.?;
    }

    fn rotationTimeDue(self: *const RollingFileSink, now: u64) bool {
        // The elapsed check prevents a saturated deadline from firing early at
        // maxInt, or rotating repeatedly when the injected clock stops there.
        return now >= self.rotation_deadline_ns.? and now - self.rotation_epoch_ns >= self.options.rotation_interval_ns.?;
    }

    fn rollover(self: *RollingFileSink) !void {
        try self.finishCurrent();
        // All original CQEs have been consumed before rename/close.
        self.current.?.deinit();
        self.current = null;
        if (self.archive_paths.len > 0) {
            const oldest = self.archive_paths[self.archive_paths.len - 1];
            self.options.dir.?.deleteFile(self.io, oldest) catch |err| switch (err) {
                error.FileNotFound => if (self.archive_present[self.archive_present.len - 1]) return err,
                else => return err,
            };
            var index = self.archive_paths.len - 1;
            while (index > 0) : (index -= 1) {
                self.options.dir.?.rename(self.archive_paths[index - 1], self.options.dir.?, self.archive_paths[index], self.io) catch |err| switch (err) {
                    error.FileNotFound => if (self.archive_present[index - 1]) return err,
                    else => return err,
                };
            }
            try self.options.dir.?.rename(self.path, self.options.dir.?, self.archive_paths[0], self.io);
        }
        self.current = try FileSink.create(self.allocator, self.io, fileOptions(self.options, self.path, false));
        var index = self.archive_present.len;
        while (index > 1) {
            index -= 1;
            self.archive_present[index] = self.archive_present[index - 1];
        }
        if (self.archive_present.len != 0) self.archive_present[0] = true;
        self.rollover_count += 1;
    }

    fn fileOptions(options: Options, path: []const u8, append: bool) FileSink.Options {
        return .{ .path = path, .dir = options.dir, .buffer_bytes = options.buffer_bytes, .backend = options.backend, .queue_depth = options.queue_depth, .append = append };
    }

    fn writeErased(context: *anyopaque, record: []const u8) anyerror!void {
        return (@as(*RollingFileSink, @ptrCast(@alignCast(context)))).writeRecord(record);
    }
    fn flushErased(context: *anyopaque) anyerror!void {
        return (@as(*RollingFileSink, @ptrCast(@alignCast(context)))).flush();
    }
    fn syncErased(context: *anyopaque) anyerror!void {
        return (@as(*RollingFileSink, @ptrCast(@alignCast(context)))).sync();
    }
    const vtable: Sink.VTable = .{ .writeRecord = writeErased, .flush = flushErased, .sync = syncErased };
};

test {
    _ = @import("rolling_file_time_tests.zig");
    _ = @import("rolling_file_reliability_tests.zig");
}

test "whole records rotate at size boundary and retention keeps newest archives" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log", .dir = tmp.dir, .max_bytes = 8, .retention = 2, .buffer_bytes = 8, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("one\n");
    try output.writeRecord("two\n");
    try output.writeRecord("three\n");
    try output.writeRecord("four\n");
    try output.writeRecord("five\n");
    try output.writeRecord("six\n");
    if (directory_sync.supported) try output.sync() else try output.flush();
    try std.testing.expectEqual(@as(usize, 4), output.rollover_count);
    const active = try tmp.dir.readFileAlloc(std.testing.io, "output.log", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(active);
    const newest = try tmp.dir.readFileAlloc(std.testing.io, "output.log.1", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(newest);
    const older = try tmp.dir.readFileAlloc(std.testing.io, "output.log.2", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(older);
    try std.testing.expectEqualStrings("six\n", active);
    try std.testing.expectEqualStrings("five\n", newest);
    try std.testing.expectEqualStrings("four\n", older);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "output.log.3", .{}));
    try std.testing.expectError(error.RecordTooLarge, output.writeRecord("oversized\n"));
    try std.testing.expectEqual(@as(usize, 4), output.rollover_count);
}

test "reopen drains buffered old generation and opens the external replacement" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log", .dir = tmp.dir, .max_bytes = 64, .retention = 1, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("before\n");
    try tmp.dir.rename("output.log", tmp.dir, "external.log", std.testing.io);
    try output.reopen();
    try output.writeRecord("after\n");
    try output.flush();
    const before = try tmp.dir.readFileAlloc(std.testing.io, "external.log", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(before);
    const after = try tmp.dir.readFileAlloc(std.testing.io, "output.log", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings("before\n", before);
    try std.testing.expectEqualStrings("after\n", after);
}

test "rotation failure is explicit and does not accept the triggering record" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log", .dir = tmp.dir, .max_bytes = 4, .retention = 1, .buffer_bytes = 8, .backend = .portable });
    defer output.deinit();
    try tmp.dir.createDir(std.testing.io, "output.log.1", .default_dir);
    try output.writeRecord("one\n");
    if (output.writeRecord("two\n")) |_| return error.TestExpectedError else |_| {}
    try std.testing.expect(output.failure != null);
    if (output.writeRecord("x\n")) |_| return error.TestExpectedError else |_| {}
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "output.log", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("one\n", bytes);
}

test "io_uring rotation drains original writes before moving file generations" {
    @import("../backend/linux_uring.zig").LinuxUring.probe() catch |err| switch (err) {
        error.Unsupported => return error.SkipZigTest,
        else => return err,
    };
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "uring.log", .dir = tmp.dir, .max_bytes = 8, .retention = 2, .buffer_bytes = 8, .backend = .linux_uring, .queue_depth = 4 });
    defer output.deinit();
    try output.writeRecord("one\n");
    try output.writeRecord("two\n");
    try output.writeRecord("three\n");
    try output.writeRecord("four\n");
    try output.sync();
    const old = try tmp.dir.readFileAlloc(std.testing.io, "uring.log.2", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(old);
    const recent = try tmp.dir.readFileAlloc(std.testing.io, "uring.log.1", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(recent);
    const active = try tmp.dir.readFileAlloc(std.testing.io, "uring.log", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(active);
    try std.testing.expectEqualStrings("one\ntwo\n", old);
    try std.testing.expectEqualStrings("three\n", recent);
    try std.testing.expectEqualStrings("four\n", active);
    try output.shutdown();
    try output.shutdown();
    try std.testing.expectError(error.Closed, output.writeRecord("late\n"));
}

test "failed reopen latches and keeps the original generation alive for cleanup" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const output = try RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log", .dir = tmp.dir, .max_bytes = 64, .retention = 1, .buffer_bytes = 16, .backend = .portable });
    defer output.deinit();
    try output.writeRecord("before\n");
    try tmp.dir.rename("output.log", tmp.dir, "external.log", std.testing.io);
    try tmp.dir.createDir(std.testing.io, "output.log", .default_dir);
    if (output.reopen()) |_| return error.TestExpectedError else |_| {}
    try std.testing.expect(output.current != null);
    try std.testing.expect(output.failure != null);
    if (output.writeRecord("after\n")) |_| return error.TestExpectedError else |_| {}
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "external.log", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("before\n", bytes);
}

test "rolling owns its directory after the initialization directory closes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "nested", .default_dir);
    const borrowed = try tmp.dir.openDir(std.testing.io, "nested", .{});
    const output = RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log", .dir = borrowed, .max_bytes = 8, .retention = 1, .buffer_bytes = 8, .backend = .portable }) catch |err| {
        borrowed.close(std.testing.io);
        return err;
    };
    borrowed.close(std.testing.io);
    defer output.deinit();
    const borrowed_sink = output.sink();
    const identity = try std.testing.allocator.dupe(u8, borrowed_sink.recovery_identity.?);
    defer std.testing.allocator.free(identity);
    try std.testing.expect(std.fs.path.isAbsolute(identity));
    try output.writeRecord("one\n");
    try output.writeRecord("two\n");
    try output.writeRecord("three\n");
    try output.reopen();
    try output.flush();
    try std.testing.expectEqualStrings(identity, borrowed_sink.recovery_identity.?);
    try std.testing.expectEqualStrings(identity, output.sink().recovery_identity.?);
    try std.testing.expect(borrowed_sink.recovery_identity.?.ptr == output.sink().recovery_identity.?.ptr);
    const old = try tmp.dir.readFileAlloc(std.testing.io, "nested/output.log.1", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(old);
    const active = try tmp.dir.readFileAlloc(std.testing.io, "nested/output.log", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(active);
    try std.testing.expectEqualStrings("one\ntwo\n", old);
    try std.testing.expectEqualStrings("three\n", active);
}

test "rolling recovery identity is independent of active generation and binds the logical file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectError(error.InvalidRollingOptions, RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log/", .dir = tmp.dir, .max_bytes = 8, .retention = 1, .backend = .portable }));
    const original = try RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "output.log", .dir = tmp.dir, .max_bytes = 8, .retention = 1, .buffer_bytes = 8, .backend = .portable });
    defer original.deinit();
    const renamed = try RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "different.log", .dir = tmp.dir, .max_bytes = 8, .retention = 1, .buffer_bytes = 8, .backend = .portable });
    defer renamed.deinit();
    const borrowed_sink = original.sink();
    const identity = try std.testing.allocator.dupe(u8, borrowed_sink.recovery_identity.?);
    defer std.testing.allocator.free(identity);
    try std.testing.expect(!std.mem.eql(u8, identity, renamed.sink().recovery_identity.?));
    try original.writeRecord("one\n");
    try original.writeRecord("two\n");
    try original.writeRecord("three\n");
    try original.reopen();
    try std.testing.expectEqualStrings(identity, borrowed_sink.recovery_identity.?);
    try std.testing.expectEqualStrings(identity, original.sink().recovery_identity.?);
    // A restarted sink with a different size/retention budget still names the
    // same logical destination; the runtime also binds route name and format.
    const restarted = try RollingFileSink.create(std.testing.allocator, std.testing.io, .{ .path = "./output.log", .dir = tmp.dir, .max_bytes = 64, .retention = 2, .buffer_bytes = 16, .backend = .portable });
    defer restarted.deinit();
    try std.testing.expectEqualStrings(identity, restarted.sink().recovery_identity.?);
}
