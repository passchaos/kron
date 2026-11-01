const std = @import("std");
const kron = @import("kron");

const Details = struct {
    calls: *usize,
    pub fn fields(self: @This()) struct { answer: u32 } {
        self.calls.* += 1;
        return .{ .answer = 42 };
    }
};

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .output = .stdout,
        .mode = .asynchronous,
        .format = .json,
        .timestamp = .{ .offset = try kron.time.UtcOffset.init(480) },
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer logging.destroy();
    const base = logging.scoped("http").withBorrowed(.{ .service = "example", .status = @as(u16, 0) });
    var name = "alice".*;
    {
        var owned = try base.withOwned(init.gpa, .{ .user = @as([]const u8, &name) });
        defer owned.destroy();
        @memset(&name, 'x');
        const log = owned.withTrace(.{ .trace_id = .{1} ** 16, .span_id = .{2} ** 8, .flags = 1 });
        const details = [_]kron.Field{ kron.kv("password", "private"), kron.kv("retries", @as(u32, 2)) };
        const items = [_]kron.Value{ kron.fields.fromAny("first"), kron.fields.fromAny(kron.group(&details)) };
        _ = try log.tryEmit(.info, "request completed", .{
            .status = @as(u16, 200),
            .results = kron.array(&items),
            .token = kron.secret("never captured"),
            .elapsed = kron.durationNs(1200),
            .payload = kron.bytes("abc"),
        });
        _ = try log.tryLogfAt(@src(), .info, "response {d} in {d}ns", .{ @as(u16, 200), @as(u64, 1200) }, .{});
    }
    var calls: usize = 0;
    const provider: Details = .{ .calls = &calls };
    const filtered = try base.tryEmitLazy(.debug, "expensive details", provider);
    if (filtered != .filtered or calls != 0) return error.LazyFilteringFailed;
    try logging.reloadFilter("info,http=debug");
    _ = try base.tryEmitLazy(.debug, "expensive details", provider);
    if (calls != 1) return error.LazyCaptureFailed;
    try logging.shutdown();
}
