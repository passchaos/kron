//! One-owner byte storage shared by the journal algorithms. `bytes` borrows
//! the backing allocation/mapping; moving a Storage transfers ownership and
//! copying it does not create another owner. Stop users before deinitializing.
const std = @import("std");
const platform = @import("../platform/mapping.zig");

pub const Storage = struct {
    bytes: []align(4096) u8,
    fresh: bool,
    backing: Backing,

    pub const Backing = union(enum) {
        mapped: platform.Mapping,
        memory: std.mem.Allocator,
    };

    pub fn openFile(io: std.Io, path: []const u8, length: usize) !Storage {
        const mapping = try platform.Mapping.open(io, path, length);
        return .{ .bytes = mapping.bytes, .fresh = mapping.fresh, .backing = .{ .mapped = mapping } };
    }

    /// Allocate only through the caller's allocator. The returned bytes are
    /// zeroed and writable-touched; no mapping or filesystem operation occurs.
    /// Journal header initialization may therefore skip a second full clear.
    pub fn createMemory(allocator: std.mem.Allocator, length: usize) !Storage {
        if (length == 0 or std.math.cast(i64, length) == null) return error.InvalidSize;
        const bytes = try allocator.alignedAlloc(u8, .fromByteUnits(4096), length);
        @memset(bytes, 0);
        return .{ .bytes = bytes, .fresh = true, .backing = .{ .memory = allocator } };
    }

    /// Publish before setting process-local schema readiness. Memory storage
    /// needs no persistence operation and this does not imply durability.
    pub fn publish(self: *Storage) !void {
        switch (self.backing) {
            .mapped => |*mapping| try mapping.publish(),
            .memory => {},
        }
    }

    pub fn sync(self: *Storage) !void {
        switch (self.backing) {
            .mapped => |*mapping| try mapping.sync(),
            .memory => return error.UnsupportedDurability,
        }
    }

    pub fn syncFile(self: *Storage) !void {
        switch (self.backing) {
            .mapped => |*mapping| try mapping.syncFile(),
            .memory => return error.UnsupportedDurability,
        }
    }

    pub fn isPersistent(self: *const Storage) bool {
        return switch (self.backing) {
            .mapped => true,
            .memory => false,
        };
    }

    pub fn durableSupported(self: *const Storage) bool {
        return switch (self.backing) {
            .mapped => platform.durable_supported,
            .memory => false,
        };
    }

    pub fn deinit(self: *Storage) void {
        switch (self.backing) {
            .mapped => |*mapping| mapping.deinit(),
            .memory => |allocator| allocator.free(self.bytes),
        }
        self.* = undefined;
    }
};

test "memory Storage is aligned zeroed and uses only caller memory" {
    var buffer: [3 * 4096]u8 align(4096) = undefined;
    @memset(&buffer, 0xa5);
    var allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var storage = try Storage.createMemory(allocator.allocator(), 2 * 4096 + 1);
    defer storage.deinit();
    try std.testing.expectEqual(@intFromPtr(&buffer), @intFromPtr(storage.bytes.ptr));
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(storage.bytes.ptr) % 4096);
    try std.testing.expectEqual(@as(usize, 2 * 4096 + 1), storage.bytes.len);
    try std.testing.expect(std.mem.allEqual(u8, storage.bytes, 0));
    try std.testing.expect(std.mem.allEqual(u8, buffer[storage.bytes.len..], 0xa5));
    try std.testing.expect(storage.fresh);
    try std.testing.expect(!storage.isPersistent());
    try std.testing.expect(!storage.durableSupported());
}

test "memory Storage publication and durability errors allocate nothing after creation" {
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var storage = try Storage.createMemory(allocator.allocator(), 4097);
    var live = true;
    defer if (live) storage.deinit();
    const allocation_count = allocator.alloc_index;
    allocator.fail_index = allocation_count;
    for (0..128) |index| {
        storage.bytes[index] = @intCast(index);
        try storage.publish();
    }
    try std.testing.expectError(error.UnsupportedDurability, storage.sync());
    try std.testing.expectError(error.UnsupportedDurability, storage.syncFile());
    try std.testing.expectEqual(allocation_count, allocator.alloc_index);
    try std.testing.expect(!allocator.has_induced_failure);
    storage.deinit();
    live = false;
    try std.testing.expectEqual(@as(usize, 1), allocator.allocations);
    try std.testing.expectEqual(@as(usize, 1), allocator.deallocations);
    try std.testing.expectEqual(allocator.allocated_bytes, allocator.freed_bytes);
}

test "memory Storage invalid size and OOM leave no owned allocation" {
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.InvalidSize, Storage.createMemory(allocator.allocator(), 0));
    if (@sizeOf(usize) >= @sizeOf(u64)) {
        try std.testing.expectError(error.InvalidSize, Storage.createMemory(allocator.allocator(), std.math.maxInt(usize)));
    }
    try std.testing.expectError(error.OutOfMemory, Storage.createMemory(allocator.allocator(), 4096));
    try std.testing.expectEqual(@as(usize, 0), allocator.allocations);
    try std.testing.expectEqual(@as(usize, 0), allocator.deallocations);
    try std.testing.expectEqual(@as(usize, 0), allocator.allocated_bytes);
}
