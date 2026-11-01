//! Cross-compilation entry which forces the real public runtime paths to compile.
const std = @import("std");
const kron = @import("root.zig");

export fn kron_platform_check(allocator: *const std.mem.Allocator, io: *const std.Io, path: [*]const u8, length: usize) u16 {
    check(allocator.*, io.*, path[0..length]) catch |err| return @intFromError(err);
    return 0;
}

fn check(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const managed = try kron.Logging.create(allocator, io, .{
        .output = .{ .file = .{ .path = path, .backend = .portable } },
        .mode = .spsc,
        .max_threads = 1,
        .queue = .{ .memory = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 } },
    });
    defer managed.destroy();
    const managed_shape: kron.Event = .{ .level = .info, .scope = "managed", .message = "cross", .timestamp_ns = 0, .fields = &.{} };
    const managed_shared = try managed.prepared(managed_shape);
    _ = try managed_shared.tryEmit(.info, "cross", .{});
    const managed_thread = try managed.attachPreparedThread(managed_shape);
    _ = try managed_thread.tryEmit(.info, "cross", .{});
    try managed_thread.detach();
    try managed.reloadFilter("debug");
    try managed.setLevel(.info);
    _ = managed.health();
    _ = managed.runtime();
    try managed.flush();
    try managed.flushOutputs(&.{"output"});
    managed.flushOutputsDurable(&.{"output"}) catch {};
    managed.flushUntil(kron.Deadline.after(io, std.time.ns_per_s)) catch {};
    managed.flushDurableUntil(kron.Deadline.after(io, std.time.ns_per_s)) catch {};
    managed.flushDurable() catch {};
    managed.shutdownUntil(kron.Deadline.after(io, std.time.ns_per_s)) catch {};
    try managed.shutdown();
    const console = try kron.Logging.create(allocator, io, .{});
    defer console.destroy();
    _ = try console.scoped("managed").tryEmit(.info, "console", .{});
    try console.shutdown();
    const local_logging = try kron.Logging.create(allocator, io, .{ .timestamp = .{ .zone = .local } });
    defer local_logging.destroy();
    _ = try local_logging.scoped("local").tryEmit(.info, "system local", .{});
    try local_logging.shutdown();
    const file = try kron.FileSink.create(allocator, io, .{ .path = path, .backend = .portable });
    defer file.deinit();
    const sync = try kron.Runtime.create(allocator, io, .{ .routes = &.{.{ .name = "file", .sink = file.sink(), .timestamp = .{ .offset = try kron.time.UtcOffset.init(480) } }} });
    defer sync.destroy();
    const log = sync.loggerWithClock(kron.NativeClock, "platform");
    _ = try log.tryEmitAt(kron.source.fromModule("src", @src()), .info, "cross", .{ .id = @as(u64, 1), .name = "native" });
    _ = try log.tryEmit(.info, "empty", .{});
    _ = try log.withBorrowed(.{ .request = @as(u64, 1) }).tryEmit(.info, "context", .{ .request = @as(u64, 2) });
    var encoded_bytes: [2048]u8 = undefined;
    var encoded_output = std.Io.Writer.fixed(&encoded_bytes);
    try kron.encoder.encode(.binary, .{ .level = .info, .scope = "platform", .message = "framed", .fields = &.{kron.kv("value", @as(u64, 4))}, .timestamp_ns = 0 }, &encoded_output);
    try sync.reloadFilter("debug,platform=trace");
    _ = try sync.replaceConfigurationSources(&.{.{ .name = "file", .sink = file.sink() }}, .{ .explicit = .{ .filter_spec = "trace" } });
    _ = try sync.collectConfigurations();
    var document = try kron.configuration_document.Document.parse(allocator, "{\"filter\":\"info\",\"predicate\":null}");
    defer document.deinit();
    _ = try sync.replaceConfigurationSources(&.{.{ .name = "file", .sink = file.sink() }}, .{ .file = document.override() });
    try sync.flush(.written);
    const date = try kron.time.rfc3339.parse("2000-02-29T12:34:56.123456789+08:00");
    var date_bytes: [kron.time.rfc3339.max_length]u8 = undefined;
    _ = try kron.time.rfc3339.format(date.timestamp, .{ .offset = date.offset }, &date_bytes);
    _ = try (try kron.time.Date.init(2024, 1, 31)).addMonths(1, .clamp);
    _ = sync.controlStatus();
    sync.flushUntil(.written, kron.Deadline.after(io, std.time.ns_per_s)) catch {};
    sync.flush(.durable) catch {};
    try sync.shutdown(.drain);

    const async_path = try std.fmt.allocPrint(allocator, "{s}.journal", .{path});
    defer allocator.free(async_path);
    const runtime = try kron.Runtime.create(allocator, io, .{
        .submission = .low_latency,
        .journal = .{ .path = async_path, .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 8 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 8,
        .routes = &.{.{ .name = "file", .sink = file.sink() }},
    });
    defer runtime.destroy();
    var thread = try runtime.attachThreadWithClock(kron.NativeClock, .{ .scope = "platform.thread" });
    _ = try thread.tryEmit(.info, "thread", .{ .id = @as(u64, 2) });
    try thread.detach();
    _ = runtime.health();
    try runtime.flush(.written);
    runtime.flush(.durable) catch {};
    try runtime.shutdown(.drain);

    const reader = try kron.archive.Reader.open(allocator, io, async_path);
    defer reader.deinit();
    _ = try reader.next();

    const volatile_runtime = try kron.Runtime.create(allocator, io, .{
        .submission = .low_latency,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 8 },
        .max_thread_channels = 1,
        .thread_channel_capacity = 8,
        .sampling = .{ .every = 2 },
        .routes = &.{.{ .name = "volatile-file", .sink = file.sink() }},
    });
    defer volatile_runtime.destroy();
    const volatile_log = try volatile_runtime.attachThread(.{ .scope = "memory" });
    _ = try volatile_log.tryEmit(.info, "memory", .{ .value = @as(u32, 3) });
    try volatile_log.detach();
    try volatile_runtime.flush(.written);
    volatile_runtime.flush(.durable) catch {};
    _ = volatile_runtime.health();
    try volatile_runtime.shutdown(.drain);

    const rolling_path = try std.fmt.allocPrint(allocator, "{s}.rolling", .{path});
    defer allocator.free(rolling_path);
    const rolling = try kron.RollingFileSink.create(allocator, io, .{ .path = rolling_path, .max_bytes = 8, .retention = 2, .buffer_bytes = 32, .backend = .portable });
    defer rolling.deinit();
    try rolling.writeRecord("one\n");
    try rolling.writeRecord("two\n");
    try rolling.writeRecord("tri\n");
    try rolling.flush();
    rolling.sync() catch {};
    try rolling.reopen();
    try rolling.shutdown();
}
