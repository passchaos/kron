const std = @import("std");
const builtin = @import("builtin");
const BufferPool = @import("buffer_pool.zig").BufferPool;
const completionError = @import("buffer_pool.zig").completionError;
const LinuxRing = if (builtin.os.tag == .linux) std.os.linux.IoUring else void;

/// One owner, explicit offsets, bounded stable batch storage, and no cancellation.
/// Pending SQEs count as owned requests even before the kernel accepts them.
/// shutdown waits for every original/partial request; an I/O failure never frees
/// storage while a different request still references it.
pub const LinuxUring = struct {
    ring: LinuxRing,
    pool: BufferPool,
    file: std.Io.File,
    requests: u32 = 0,
    transport_failure: ?anyerror = null,
    sync_id: u64 = 0,
    sync_pending: bool = false,
    sync_failure: ?anyerror = null,

    pub fn probe() anyerror!void {
        if (builtin.os.tag != .linux) return error.Unsupported;
        var ring = try initRing(2);
        defer ring.deinit();
        try checkOperations(&ring);
    }

    pub fn init(allocator: std.mem.Allocator, file: std.Io.File, start_offset: u64, batch_bytes: usize, depth: u16) anyerror!LinuxUring {
        if (builtin.os.tag != .linux) return error.Unsupported;
        if (depth == 0 or depth > 32768 or !std.math.isPowerOfTwo(depth)) return error.InvalidQueueDepth;
        var ring = try initRing(depth);
        errdefer ring.deinit();
        try checkOperations(&ring);
        const pool = try BufferPool.init(allocator, depth, batch_bytes, start_offset);
        return .{ .ring = ring, .pool = pool, .file = file };
    }

    pub fn writeBatch(self: *LinuxUring, bytes: []const u8) !void {
        if (builtin.os.tag != .linux) return error.Unsupported;
        if (self.transport_failure) |err| return err;
        if (self.pool.failure) |err| return err;
        if (bytes.len == 0) return;
        // Reap completions without blocking, allowing encoding to overlap writes.
        try self.reap(false);
        const batch = self.pool.acquire(bytes) catch |err| switch (err) {
            error.BufferPoolFull => blk: {
                try self.flush();
                break :blk try self.pool.acquire(bytes);
            },
            else => return err,
        };
        self.prepare(batch) catch |err| {
            self.pool.fail(batch, err);
            return err;
        };
        if (self.ring.sq_ready() == self.pool.batches.len) try self.submitPending();
    }

    pub fn flush(self: *LinuxUring) !void {
        if (builtin.os.tag != .linux) return error.Unsupported;
        try self.drainRequests();
        if (self.transport_failure) |err| return err;
        if (self.pool.failure) |err| return err;
    }

    pub fn sync(self: *LinuxUring) !void {
        if (builtin.os.tag != .linux) return error.Unsupported;
        // An actual completion barrier precedes fsync. Queue order alone is
        // insufficient: a separately submitted fsync can outrun pending writes.
        try self.flush();
        if (self.pool.next_id == std.math.maxInt(u64)) return error.OperationIdExhausted;
        self.sync_id = self.pool.next_id;
        self.pool.next_id += 1;
        // The sync ID does not occupy a batch slot; adjust retire_id so the
        // subsequent batch's monotonically increasing ID has no watermark gap.
        self.pool.retire_id = self.pool.next_id;
        _ = try self.ring.fsync(self.sync_id, self.file.handle, 0);
        self.sync_pending = true;
        self.requests += 1;
        try self.drainRequests();
        if (self.sync_failure) |err| return err;
        if (self.transport_failure) |err| return err;
    }

    /// On failure, retained resources remain valid if requests could not drain.
    /// The owner may retry shutdown. There is no deadline or unsafe cancellation.
    pub fn shutdown(self: *LinuxUring) !void {
        if (builtin.os.tag != .linux) return;
        try self.drainRequests();
        if (self.transport_failure) |err| return err;
        if (self.pool.failure) |err| return err;
        if (self.sync_failure) |err| return err;
    }

    pub fn deinit(self: *LinuxUring) void {
        if (builtin.os.tag != .linux) return;
        self.shutdown() catch {
            // Ordinary write/fsync faults have terminal CQEs and are safe to
            // tear down. A transport failure with outstanding references is
            // fatal: returning after freeing those buffers would cause UAF.
            if (self.requests != 0) @panic("io_uring could not drain outstanding requests; resources cannot be released");
        };
        std.debug.assert(self.requests == 0);
        self.ring.deinit();
        self.pool.deinit();
        self.* = undefined;
    }

    pub fn offset(self: *const LinuxUring) u64 {
        return self.pool.next_offset;
    }

    pub fn writtenOffset(self: *const LinuxUring) u64 {
        return self.pool.written_offset;
    }

    fn prepare(self: *LinuxUring, batch: *BufferPool.Batch) !void {
        _ = try self.ring.write(batch.id, self.file.handle, self.pool.bytes(batch), batch.offset + batch.done);
        self.pool.markPending(batch);
        self.requests += 1;
    }

    fn submitPending(self: *LinuxUring) !void {
        while (self.ring.sq_ready() > 0) {
            const submitted = self.ring.submit() catch |err| switch (err) {
                error.SignalInterrupt => continue,
                else => {
                    self.transport_failure = err;
                    return err;
                },
            };
            if (submitted == 0 and self.ring.sq_ready() > 0) {
                self.transport_failure = error.SubmitZero;
                return error.SubmitZero;
            }
        }
    }

    fn drainRequests(self: *LinuxUring) !void {
        while (self.requests > 0) {
            try self.submitPending();
            try self.reap(true);
        }
    }

    fn reap(self: *LinuxUring, wait: bool) !void {
        var completions: [64]std.os.linux.io_uring_cqe = undefined;
        const count = self.ring.copy_cqes(&completions, if (wait) 1 else 0) catch |err| switch (err) {
            error.SignalInterrupt => return,
            else => {
                self.transport_failure = err;
                return err;
            },
        };
        var completion_failure: ?anyerror = null;
        for (completions[0..count]) |cqe| {
            if (self.sync_pending and cqe.user_data == self.sync_id) {
                std.debug.assert(self.requests > 0);
                self.requests -= 1;
                self.sync_pending = false;
                if (cqe.res < 0) self.sync_failure = completionError(cqe.res);
                continue;
            }
            self.pool.complete(cqe.user_data, cqe.res) catch |err| {
                self.transport_failure = err;
                completion_failure = err;
                // Process the remaining copied CQEs. An unrecognized CQE does
                // not prove any of our owned requests have completed.
                continue;
            };
            std.debug.assert(self.requests > 0);
            self.requests -= 1;
        }
        // Requeue partial writes only after processing every copied CQE; no
        // completion can be discarded by a prepare failure in the same batch.
        for (self.pool.batches) |*batch| {
            if (batch.state != .needs_submit) continue;
            if (self.pool.failure) |err| {
                self.pool.fail(batch, err);
                continue;
            }
            self.prepare(batch) catch |err| {
                self.pool.fail(batch, err);
            };
        }
        if (completion_failure) |err| return err;
    }
};

fn initRing(depth: u16) !LinuxRing {
    if (builtin.os.tag != .linux) return error.Unsupported;
    return std.os.linux.IoUring.init(depth, 0) catch |err| switch (err) {
        error.PermissionDenied, error.SystemOutdated, error.ArgumentsInvalid => error.Unsupported,
        else => return err,
    };
}

fn checkOperations(ring: *LinuxRing) !void {
    if (builtin.os.tag != .linux) return error.Unsupported;
    const probe = ring.get_probe() catch |err| switch (err) {
        error.ArgumentsInvalid => return error.Unsupported,
        else => return err,
    };
    var write_supported = false;
    var fsync_supported = false;
    for (probe.ops[0..probe.ops_len]) |op| {
        if (!op.is_supported()) continue;
        if (op.op == .WRITE) write_supported = true;
        if (op.op == .FSYNC) fsync_supported = true;
    }
    if (!write_supported or !fsync_supported) return error.Unsupported;
}

test "io_uring probe reports unavailable capability explicitly" {
    LinuxUring.probe() catch |err| switch (err) {
        error.Unsupported => return error.SkipZigTest,
        else => return err,
    };
}

test "io_uring batches drain before fsync and shutdown" {
    LinuxUring.probe() catch |err| switch (err) {
        error.Unsupported => return error.SkipZigTest,
        else => return err,
    };
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(std.testing.io, "output.log", .{});
    defer file.close(std.testing.io);
    var output = try LinuxUring.init(std.testing.allocator, file, 0, 8, 4);
    defer output.deinit();
    try output.writeBatch("one\n");
    try output.writeBatch("two\n");
    try output.writeBatch("three\n");
    try output.flush();
    try std.testing.expectEqual(@as(u64, 14), output.writtenOffset());
    try output.sync();
    try output.writeBatch("four\n");
    try output.shutdown();
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "output.log", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("one\ntwo\nthree\nfour\n", bytes);
}

test "io_uring write faults still reap every original request before shutdown" {
    LinuxUring.probe() catch |err| switch (err) {
        error.Unsupported => return error.SkipZigTest,
        else => return err,
    };
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const writable = try tmp.dir.createFile(std.testing.io, "readonly.log", .{});
    writable.close(std.testing.io);
    const readonly = try tmp.dir.openFile(std.testing.io, "readonly.log", .{});
    defer readonly.close(std.testing.io);
    var output = try LinuxUring.init(std.testing.allocator, readonly, 0, 8, 4);
    defer output.deinit();
    try output.writeBatch("one\n");
    try output.writeBatch("two\n");
    try output.writeBatch("three\n");
    try std.testing.expectError(error.FileDescriptorInvalid, output.flush());
    try std.testing.expectEqual(@as(u32, 0), output.requests);
    try std.testing.expectEqual(@as(u64, 0), output.writtenOffset());
    try std.testing.expectError(error.FileDescriptorInvalid, output.writeBatch("four\n"));
    try std.testing.expectError(error.FileDescriptorInvalid, output.shutdown());
    try std.testing.expectEqual(@as(u32, 0), output.requests);
}

test "depth one reuses buffers only after completion and deinit drains final request" {
    LinuxUring.probe() catch |err| switch (err) {
        error.Unsupported => return error.SkipZigTest,
        else => return err,
    };
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(std.testing.io, "depth-one.log", .{});
    defer file.close(std.testing.io);
    var output = try LinuxUring.init(std.testing.allocator, file, 0, 8, 1);
    for (0..20) |_| {
        try output.writeBatch("hello\n");
        try output.sync();
    }
    try output.writeBatch("end\n");
    output.deinit();
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "depth-one.log", std.testing.allocator, .limited(256));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 124), bytes.len);
    for (0..20) |index| try std.testing.expectEqualStrings("hello\n", bytes[index * 6 ..][0..6]);
    try std.testing.expectEqualStrings("end\n", bytes[120..]);
}
