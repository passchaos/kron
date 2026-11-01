const std = @import("std");
const kron = @import("kron");
const consumer = @import("consumer");

test "independent consumer uses managed public setup and keeps its writer" {
    var bytes: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    const logging = try kron.Logging.create(std.testing.allocator, std.testing.io, .{ .output = .{ .writer = &writer }, .format = .json });
    var alive = true;
    defer if (alive) logging.destroy();
    try std.testing.expectEqual(kron.EmitResult.accepted, try logging.scoped("managed").tryEmit(.info, "package owner", .{ .answer = @as(u32, 42) }));
    try logging.shutdown();
    try std.testing.expectEqual(@as(u64, 1), logging.health().written);
    logging.destroy();
    alive = false;
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "package owner") != null);
    try writer.writeAll("writer remains usable\n");
}

test "independent consumer imports the module and analyzes public runtime paths" {
    std.testing.refAllDecls(consumer);
    try std.testing.expectEqual(consumer.Mode.memory, try consumer.parseMode("memory"));
    try std.testing.expectError(error.InvalidMode, consumer.parseMode("invalid"));
    var bytes: [8192]u8 = undefined;
    var sink = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{ .routes = &.{.{ .name = "consumer", .sink = sink.sink() }} });
    defer runtime.destroy();
    try std.testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("consumer").tryEmit(.info, "public package", .{ .answer = @as(u32, 42) }));
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(usize, 1), sink.records);
    try runtime.shutdown(.drain);
}

test "native Zig host suite verifies files and preserves an existing qualification" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var directory: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &directory);
    const report = try consumer.platform_host.run(std.testing.allocator, std.testing.io, directory[0..length]);
    try std.testing.expectEqual(kron.platform.target, report.target);
    try std.testing.expectEqual(@as(usize, 2), report.rolling_archives);
    try std.testing.expectEqual(@as(usize, 1), report.journals[0].recovered);
    try std.testing.expectEqual(@as(usize, 1), report.journals[1].recovered);
    try std.testing.expectEqual(@as(u64, 2), report.modes[0].?.written);
    const first = try temporary.dir.readFileAlloc(std.testing.io, "native-check/sync/日志.jsonl", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(first);
    try std.testing.expectError(error.PathAlreadyExists, consumer.platform_host.run(std.testing.allocator, std.testing.io, directory[0..length]));
    const retained = try temporary.dir.readFileAlloc(std.testing.io, "native-check/sync/日志.jsonl", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(retained);
    try std.testing.expectEqualSlices(u8, first, retained);
}
