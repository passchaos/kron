const std = @import("std");

/// Stable storage for asynchronous logical batches. IDs are never reused.
/// Completion order does not affect the contiguous written watermark. A slot
/// stays owned until its original request and all partial-write requests end.
pub const BufferPool = struct {
    allocator: std.mem.Allocator,
    storage: []u8,
    batches: []Batch,
    batch_bytes: usize,
    next_id: u64 = 1,
    retire_id: u64 = 1,
    next_offset: u64,
    written_offset: u64,
    failure: ?anyerror = null,

    pub const State = enum { free, needs_submit, pending, complete, failed };
    pub const Batch = struct {
        id: u64 = 0,
        offset: u64 = 0,
        len: usize = 0,
        done: usize = 0,
        state: State = .free,
    };

    pub fn init(allocator: std.mem.Allocator, depth: usize, batch_bytes: usize, offset: u64) !BufferPool {
        if (depth == 0 or batch_bytes == 0 or batch_bytes > std.math.maxInt(u32)) return error.InvalidBufferBudget;
        const total = std.math.mul(usize, depth, batch_bytes) catch return error.InvalidBufferBudget;
        const storage = try allocator.alloc(u8, total);
        errdefer allocator.free(storage);
        @memset(storage, 0);
        const batches = try allocator.alloc(Batch, depth);
        @memset(batches, .{});
        return .{
            .allocator = allocator,
            .storage = storage,
            .batches = batches,
            .batch_bytes = batch_bytes,
            .next_offset = offset,
            .written_offset = offset,
        };
    }

    /// Precondition: no request can still reference storage.
    pub fn deinit(self: *BufferPool) void {
        for (self.batches) |batch| std.debug.assert(batch.state != .pending);
        self.allocator.free(self.batches);
        self.allocator.free(self.storage);
        self.* = undefined;
    }

    pub fn acquire(self: *BufferPool, data: []const u8) !*Batch {
        if (self.failure) |err| return err;
        if (data.len == 0 or data.len > self.batch_bytes) return error.InvalidBatchLength;
        if (self.next_id == std.math.maxInt(u64)) return error.OperationIdExhausted;
        if (data.len > std.math.maxInt(u64) - self.next_offset) return error.OffsetOverflow;
        const slot_index = self.index(self.next_id);
        const batch = &self.batches[slot_index];
        if (batch.state != .free) return error.BufferPoolFull;
        @memcpy(self.storage[slot_index * self.batch_bytes ..][0..data.len], data);
        batch.* = .{ .id = self.next_id, .offset = self.next_offset, .len = data.len, .state = .needs_submit };
        self.next_id += 1;
        self.next_offset += data.len;
        return batch;
    }

    pub fn bytes(self: *BufferPool, batch: *const Batch) []const u8 {
        const start = self.index(batch.id) * self.batch_bytes;
        return self.storage[start..][batch.done..batch.len];
    }

    pub fn markPending(_: *BufferPool, batch: *Batch) void {
        std.debug.assert(batch.state == .needs_submit);
        batch.state = .pending;
    }

    /// Applies one original/subrequest CQE. A short completion retains ownership
    /// and changes the batch to needs_submit; a caller must submit the remainder.
    pub fn complete(self: *BufferPool, id: u64, result: i32) !void {
        if (id == 0) return error.UnexpectedCompletion;
        const batch = &self.batches[self.index(id)];
        if (batch.id != id or batch.state != .pending) return error.UnexpectedCompletion;
        if (result < 0) {
            self.fail(batch, completionError(result));
            return;
        }
        const count: usize = @intCast(result);
        if (count == 0) {
            self.fail(batch, error.WriteZero);
            return;
        }
        if (count > batch.len - batch.done) {
            self.fail(batch, error.InvalidWriteResult);
            return;
        }
        batch.done += count;
        batch.state = if (batch.done == batch.len) .complete else .needs_submit;
        self.retire();
    }

    pub fn fail(self: *BufferPool, batch: *Batch, err: anyerror) void {
        batch.state = .failed;
        if (self.failure == null) self.failure = err;
    }

    fn retire(self: *BufferPool) void {
        while (self.retire_id < self.next_id) {
            const batch = &self.batches[self.index(self.retire_id)];
            if (batch.id != self.retire_id or batch.state != .complete) break;
            self.written_offset = batch.offset + batch.len;
            batch.state = .free;
            self.retire_id += 1;
        }
    }

    fn index(self: *const BufferPool, id: u64) usize {
        return @intCast((id - 1) % self.batches.len);
    }
};

pub fn completionError(result: i32) anyerror {
    const E = std.os.linux.E;
    return switch (result) {
        -@as(i32, @intFromEnum(E.NOSPC)) => error.NoSpaceLeft,
        -@as(i32, @intFromEnum(E.DQUOT)) => error.DiskQuota,
        -@as(i32, @intFromEnum(E.FBIG)) => error.FileTooBig,
        -@as(i32, @intFromEnum(E.IO)) => error.InputOutput,
        -@as(i32, @intFromEnum(E.BADF)) => error.FileDescriptorInvalid,
        -@as(i32, @intFromEnum(E.CANCELED)) => error.Canceled,
        -@as(i32, @intFromEnum(E.INVAL)) => error.InvalidWrite,
        -@as(i32, @intFromEnum(E.OPNOTSUPP)) => error.Unsupported,
        -@as(i32, @intFromEnum(E.ACCES)), -@as(i32, @intFromEnum(E.PERM)) => error.AccessDenied,
        -@as(i32, @intFromEnum(E.INTR)) => error.SignalInterrupt,
        -@as(i32, @intFromEnum(E.AGAIN)) => error.WouldBlock,
        else => error.UnexpectedWriteError,
    };
}

test "out of order completions retain buffers and only advance contiguous written offset" {
    var pool = try BufferPool.init(std.testing.allocator, 2, 8, 10);
    defer pool.deinit();
    const first = try pool.acquire("first");
    const second = try pool.acquire("two");
    pool.markPending(first);
    pool.markPending(second);
    try pool.complete(second.id, 3);
    try std.testing.expectEqual(@as(u64, 10), pool.written_offset);
    try std.testing.expectError(error.BufferPoolFull, pool.acquire("x"));
    try pool.complete(first.id, 2);
    try std.testing.expectEqualStrings("rst", pool.bytes(first));
    try std.testing.expectEqual(BufferPool.State.needs_submit, first.state);
    pool.markPending(first);
    try pool.complete(first.id, 3);
    try std.testing.expectEqual(@as(u64, 18), pool.written_offset);
    const third = try pool.acquire("new");
    try std.testing.expectEqual(@as(u64, 3), third.id);
    try std.testing.expectError(error.UnexpectedCompletion, pool.complete(1, 5));
    try std.testing.expectError(error.UnexpectedCompletion, pool.complete(0, 5));
}

test "failed and zero completions cannot retire an earlier gap" {
    var pool = try BufferPool.init(std.testing.allocator, 2, 8, 0);
    defer pool.deinit();
    const first = try pool.acquire("one");
    const second = try pool.acquire("two");
    pool.markPending(first);
    pool.markPending(second);
    try pool.complete(first.id, -@as(i32, @intFromEnum(std.os.linux.E.NOSPC)));
    try pool.complete(second.id, 3);
    try std.testing.expectEqual(@as(u64, 0), pool.written_offset);
    try std.testing.expectError(error.NoSpaceLeft, pool.acquire("next"));
    var zero = try BufferPool.init(std.testing.allocator, 1, 8, 0);
    defer zero.deinit();
    const batch = try zero.acquire("x");
    zero.markPending(batch);
    try zero.complete(batch.id, 0);
    try std.testing.expect(zero.failure.? == error.WriteZero);
}
