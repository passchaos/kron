//! Real executable gate: imported tests cannot hide thread spawning behind skips.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    comptime std.debug.assert(builtin.single_threaded);
    const io = init.io;
    const allocator = init.gpa;
    var identity: [8]u8 = undefined;
    try io.randomSecure(&identity);
    var path_buffer: [80]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/kron-single-{x}", .{std.mem.readInt(u64, &identity, .little)});
    const cwd = std.Io.Dir.cwd();
    try cwd.createDir(io, path, .default_dir);
    defer cwd.deleteTree(io, path) catch {};
    const dir = try cwd.openDir(io, path, .{ .iterate = true });
    defer dir.close(io);

    const file = try kron.FileSink.create(allocator, io, .{ .dir = dir, .path = "events.jsonl", .backend = .portable });
    defer file.deinit();
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    const runtime = try kron.Runtime.create(failing.allocator(), io, .{
        .submission = .sync,
        .routes = &.{.{ .name = "file", .sink = file.sink(), .format = .json }},
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    try expect(!runtime.controlStatus().available);
    try expect(!runtime.health().worker_alive);
    try onlyOneThread(io);

    const log = runtime.loggerWithClock(kron.NativeClock, "single").withBorrowed(.{ .service = "local" });
    const User = struct { id: u64, name: []const u8, password: []const u8 };
    var user: User = .{ .id = 42, .name = "alice", .password = "omitted" };
    var adapter = kron.Adapter(User, &.{ "id", "name" }).init();
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try expect(try log.tryEmit(.info, "selected", .{ .user = try adapter.capture(&user), .password = "sensitive" }) == .accepted);
    try expect(try log.tryEmit(.debug, "filtered", .{}) == .filtered);
    try runtime.reloadFilter("warn,single=debug");
    try expect(try log.tryEmit(.debug, "reload", .{ .answer = @as(u32, 7) }) == .accepted);
    try runtime.flush(.written);
    try runtime.flushRoutes(&.{"file"}, .durable);
    try expect(!failing.has_induced_failure);

    // Timed APIs fail before any task, sink callback, or admission closure.
    const deadline = kron.Deadline.after(io, std.time.ns_per_s);
    try std.testing.expectError(error.TimedControlUnavailable, runtime.flushUntil(.written, deadline));
    try std.testing.expectError(error.TimedControlUnavailable, runtime.flushRoutesUntil(&.{"file"}, .written, deadline));
    try std.testing.expectError(error.TimedControlUnavailable, runtime.shutdownUntil(deadline));
    try expect(runtime.health().state == .running);
    try expect(!runtime.controlStatus().busy);
    try onlyOneThread(io);

    // Unsupported modes reject before allocating or creating journal files.
    var forbidden = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        try std.testing.expectError(error.ThreadsUnavailable, kron.Runtime.create(forbidden.allocator(), io, .{
            .submission = submission,
            .routes = &.{.{ .name = "file", .sink = file.sink() }},
        }));
    }
    try expect(!forbidden.has_induced_failure);

    // The application owner preserves sync/no-thread behavior and rejects
    // unsupported modes before opening or truncating its managed output.
    inline for (.{ .asynchronous, .spsc }) |mode| {
        try std.testing.expectError(error.ThreadsUnavailable, kron.Logging.create(forbidden.allocator(), io, .{
            .output = .{ .file = .{ .dir = dir, .path = "must-not-create.jsonl", .append = false } },
            .mode = mode,
        }));
    }
    try expect(!forbidden.has_induced_failure);
    var managed_bytes: [4096]u8 = undefined;
    var managed_writer = std.Io.Writer.fixed(&managed_bytes);
    const logging = try kron.Logging.create(allocator, io, .{ .output = .{ .writer = &managed_writer }, .format = .json });
    defer logging.destroy();
    try expect(try logging.scoped("managed").tryEmit(.info, "single", .{}) == .accepted);
    try logging.flush();
    try std.testing.expectError(error.TimedControlUnavailable, logging.flushUntil(deadline));
    try std.testing.expectError(error.TimedControlUnavailable, logging.flushDurableUntil(deadline));
    try std.testing.expectError(error.TimedControlUnavailable, logging.shutdownUntil(deadline));
    try logging.shutdown();
    try expect(logging.health().written == 1 and !logging.runtime().controlStatus().available);
    try onlyOneThread(io);

    try runtime.shutdown(.drain);
    try runtime.shutdown(.drain);
    try expect(runtime.health().state == .closed);
    try expect(runtime.health().accepted == 2 and runtime.health().written == 2);
    const output = try dir.readFileAlloc(io, "events.jsonl", allocator, .limited(16 * 1024));
    defer allocator.free(output);
    var lines = std.mem.splitScalar(u8, output, '\n');
    const first = try std.json.parseFromSlice(std.json.Value, allocator, lines.next().?, .{});
    defer first.deinit();
    const attributes = first.value.object.get("attributes").?.object;
    try expect(std.mem.eql(u8, attributes.get("service").?.string, "local"));
    try expect(attributes.get("user").?.object.get("id").?.integer == 42);
    try expect(std.mem.eql(u8, attributes.get("user").?.object.get("name").?.string, "alice"));
    try expect(!std.mem.eql(u8, attributes.get("password").?.string, "sensitive"));
    const second = try std.json.parseFromSlice(std.json.Value, allocator, lines.next().?, .{});
    defer second.deinit();
    try expect(second.value.object.get("attributes").?.object.get("answer").?.integer == 7);
    try expect(lines.next().?.len == 0 and lines.next() == null);
    try onlyOneThread(io);
    std.debug.print("single-threaded: real JSON file, selected fields, redaction, reload, durable flush, shutdown, no allocations, unavailable timed/async paths passed\n", .{});
}

fn expect(condition: bool) !void {
    if (!condition) return error.SingleThreadedAssertionFailed;
}

fn onlyOneThread(io: std.Io) !void {
    if (comptime builtin.os.tag != .linux) return;
    const tasks = try std.Io.Dir.openDirAbsolute(io, "/proc/self/task", .{ .iterate = true });
    defer tasks.close(io);
    var iterator = tasks.iterate();
    var count: usize = 0;
    while (try iterator.next(io)) |_| count += 1;
    try expect(count == 1);
}
