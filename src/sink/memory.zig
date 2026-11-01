const std = @import("std");
const Sink = @import("interface.zig").Sink;

/// A bounded, single-owner test sink. Allocation happens only in init.
/// Injected failures occur before a record is accepted, so record boundaries
/// remain intact. Memory does not provide durable acknowledgement.
pub const MemorySink = struct {
    buffer: []u8,
    allocator: ?std.mem.Allocator = null,
    len: usize = 0,
    records: usize = 0,
    flush_count: usize = 0,
    fail_after_records: ?usize = null,
    fail_flush: bool = false,

    pub fn init(allocator: std.mem.Allocator, max_bytes: usize) !MemorySink {
        return .{ .buffer = try allocator.alloc(u8, max_bytes), .allocator = allocator };
    }

    pub fn initBuffer(buffer: []u8) MemorySink {
        return .{ .buffer = buffer };
    }

    pub fn deinit(self: *MemorySink) void {
        if (self.allocator) |allocator| allocator.free(self.buffer);
        self.* = undefined;
    }

    pub fn sink(self: *MemorySink) Sink {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn written(self: *const MemorySink) []const u8 {
        return self.buffer[0..self.len];
    }

    pub fn clear(self: *MemorySink) void {
        self.len = 0;
        self.records = 0;
    }

    pub fn writeRecord(self: *MemorySink, record: []const u8) !void {
        if (self.fail_after_records) |limit| if (self.records >= limit) return error.InjectedWriteFailure;
        if (record.len > self.buffer.len) return error.RecordTooLarge;
        if (record.len > self.buffer.len - self.len) return error.BufferFull;
        @memcpy(self.buffer[self.len..][0..record.len], record);
        self.len += record.len;
        self.records += 1;
    }

    pub fn flush(self: *MemorySink) !void {
        if (self.fail_flush) return error.InjectedFlushFailure;
        self.flush_count += 1;
    }

    pub fn sync(_: *MemorySink) !void {
        return error.UnsupportedDurability;
    }

    fn writeErased(context: *anyopaque, record: []const u8) anyerror!void {
        return (@as(*MemorySink, @ptrCast(@alignCast(context)))).writeRecord(record);
    }
    fn flushErased(context: *anyopaque) anyerror!void {
        return (@as(*MemorySink, @ptrCast(@alignCast(context)))).flush();
    }
    fn syncErased(context: *anyopaque) anyerror!void {
        return (@as(*MemorySink, @ptrCast(@alignCast(context)))).sync();
    }
    const vtable: Sink.VTable = .{ .writeRecord = writeErased, .flush = flushErased, .sync = syncErased };
};

test "memory sink never partially accepts records at its capacity" {
    var bytes: [8]u8 = undefined;
    var output = MemorySink.initBuffer(&bytes);
    try output.sink().writeRecord("hello");
    try std.testing.expectError(error.BufferFull, output.sink().writeRecord("four"));
    try std.testing.expectError(error.RecordTooLarge, output.sink().writeRecord("123456789"));
    try std.testing.expectEqualStrings("hello", output.written());
    output.fail_after_records = 1;
    try std.testing.expectError(error.InjectedWriteFailure, output.sink().writeRecord("x"));
}
