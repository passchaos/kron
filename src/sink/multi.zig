const std = @import("std");
const Sink = @import("interface.zig").Sink;

/// Borrows the children and the slice. Calls every child and returns the first
/// error. A failed fanout can already have delivered to other children; callers
/// must not retry it as if it were an atomic transaction.
pub const MultiSink = struct {
    children: []const Sink,
    recovery_identity: ?[]const u8 = null,

    pub fn init(children: []const Sink) MultiSink {
        return .{ .children = children };
    }

    /// The caller supplies a stable identity for the complete fanout target.
    /// It must change when required child targets change, and its borrowed bytes
    /// must remain valid and unchanged for this sink's lifetime.
    pub fn initWithIdentity(children: []const Sink, recovery_identity: []const u8) MultiSink {
        return .{ .children = children, .recovery_identity = recovery_identity };
    }

    pub fn sink(self: *MultiSink) Sink {
        var durable = self.children.len > 0;
        for (self.children) |child| durable = durable and child.supports_durable;
        return .{ .context = self, .vtable = &vtable, .supports_durable = durable, .recovery_identity = self.recovery_identity };
    }

    pub fn writeRecord(self: *MultiSink, record: []const u8) !void {
        var failure: ?anyerror = null;
        for (self.children) |child| child.writeRecord(record) catch |err| {
            if (failure == null) failure = err;
        };
        if (failure) |err| return err;
    }

    pub fn flush(self: *MultiSink) !void {
        var failure: ?anyerror = null;
        for (self.children) |child| child.flush() catch |err| {
            if (failure == null) failure = err;
        };
        if (failure) |err| return err;
    }

    pub fn sync(self: *MultiSink) !void {
        if (!self.sink().supports_durable) return error.UnsupportedDurability;
        var failure: ?anyerror = null;
        for (self.children) |child| child.sync() catch |err| {
            if (failure == null) failure = err;
        };
        if (failure) |err| return err;
    }

    fn writeErased(context: *anyopaque, record: []const u8) anyerror!void {
        return (@as(*MultiSink, @ptrCast(@alignCast(context)))).writeRecord(record);
    }
    fn flushErased(context: *anyopaque) anyerror!void {
        return (@as(*MultiSink, @ptrCast(@alignCast(context)))).flush();
    }
    fn syncErased(context: *anyopaque) anyerror!void {
        return (@as(*MultiSink, @ptrCast(@alignCast(context)))).sync();
    }
    const vtable: Sink.VTable = .{ .writeRecord = writeErased, .flush = flushErased, .sync = syncErased };
};

test "fanout continues after one child fails" {
    const MemorySink = @import("memory.zig").MemorySink;
    var first_bytes: [32]u8 = undefined;
    var second_bytes: [32]u8 = undefined;
    var first = MemorySink.initBuffer(&first_bytes);
    var second = MemorySink.initBuffer(&second_bytes);
    first.fail_after_records = 0;
    const children = [_]Sink{ first.sink(), second.sink() };
    var output = MultiSink.init(&children);
    try std.testing.expectError(error.InjectedWriteFailure, output.sink().writeRecord("kept\n"));
    try std.testing.expectEqualStrings("kept\n", second.written());
    first.fail_flush = true;
    try std.testing.expectError(error.InjectedFlushFailure, output.sink().flush());
    try std.testing.expectEqual(@as(usize, 1), second.flush_count);
    try std.testing.expectError(error.UnsupportedDurability, output.sink().sync());
}

test "memory writer and fanout keep optional recovery identity explicit" {
    const MemorySink = @import("memory.zig").MemorySink;
    const WriterSink = @import("writer.zig").WriterSink;
    var bytes: [16]u8 = undefined;
    var memory = MemorySink.initBuffer(&bytes);
    var writer: std.Io.Writer.Discarding = .init(&.{});
    var output = WriterSink.init(&writer.writer);
    try std.testing.expect(memory.sink().recovery_identity == null);
    try std.testing.expect(output.sink().recovery_identity == null);
    const children = [_]Sink{ memory.sink(), output.sink() };
    var implicit = MultiSink.init(&children);
    try std.testing.expect(implicit.sink().recovery_identity == null);
    var explicit = MultiSink.initWithIdentity(&children, "audit-group:v1");
    try std.testing.expectEqualStrings("audit-group:v1", explicit.sink().recovery_identity.?);
}
