const std = @import("std");
const Sink = @import("interface.zig").Sink;

/// Borrows the writer and its backing resources. The caller serializes access
/// to the writer, including access outside this sink.
pub const WriterSink = struct {
    writer: *std.Io.Writer,
    failure: ?anyerror = null,

    pub fn init(writer: *std.Io.Writer) WriterSink {
        return .{ .writer = writer };
    }

    pub fn sink(self: *WriterSink) Sink {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn writeRecord(self: *WriterSink, record: []const u8) !void {
        if (self.failure) |err| return err;
        self.writer.writeAll(record) catch |err| {
            self.failure = err;
            return err;
        };
    }

    pub fn flush(self: *WriterSink) !void {
        if (self.failure) |err| return err;
        self.writer.flush() catch |err| {
            self.failure = err;
            return err;
        };
    }

    pub fn sync(_: *WriterSink) !void {
        return error.UnsupportedDurability;
    }

    fn writeErased(context: *anyopaque, record: []const u8) anyerror!void {
        return (@as(*WriterSink, @ptrCast(@alignCast(context)))).writeRecord(record);
    }
    fn flushErased(context: *anyopaque) anyerror!void {
        return (@as(*WriterSink, @ptrCast(@alignCast(context)))).flush();
    }
    fn syncErased(context: *anyopaque) anyerror!void {
        return (@as(*WriterSink, @ptrCast(@alignCast(context)))).sync();
    }
    const vtable: Sink.VTable = .{ .writeRecord = writeErased, .flush = flushErased, .sync = syncErased };
};

test "writer sink emits complete records and declares unsupported durability" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();
    var output = WriterSink.init(&writer.writer);
    try output.sink().writeRecord("first\n");
    try output.sink().writeRecord("second\n");
    try output.sink().flush();
    try std.testing.expectEqualStrings("first\nsecond\n", writer.written());
    try std.testing.expectError(error.UnsupportedDurability, output.sink().sync());
}
