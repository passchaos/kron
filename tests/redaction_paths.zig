const std = @import("std");
const kron = @import("kron");
const testing = std.testing;

test "configured nested redaction scratch stays valid through a forced synchronous fallback" {
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 1, .max_record_bytes = 2048 },
        .overflow = .fallback_sync,
        .redaction = &.{.{ .key = "password", .action = .mask }},
        .routes = &.{.{ .name = "output", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    var name = "alice".*;
    var password = "private".*;
    var descriptor = [_]kron.Field{ kron.kv("name", @as([]const u8, &name)), kron.kv("password", @as([]const u8, &password)) };
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("fallback").tryLogf(.info, "object {any}", .{kron.group(&descriptor)}, .{ .object = kron.group(&descriptor) }));
    @memset(&name, 'x');
    @memset(&password, 'x');
    descriptor = @splat(kron.kv("overwritten", false));
    try testing.expectEqual(@as(usize, 1), memory.records);
    try testing.expectEqual(@as(usize, 1), runtime.journal.?.pending());
    try testing.expect(std.mem.indexOf(u8, memory.written(), "private") == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, std.mem.trimEnd(u8, memory.written(), "\n"), .{});
    defer parsed.deinit();
    const object = parsed.value.object.get("attributes").?.object.get("object").?.object;
    try testing.expectEqualStrings("alice", object.get("name").?.string);
    try testing.expectEqualStrings("[REDACTED]", object.get("password").?.string);
    try testing.expect(std.mem.indexOf(u8, parsed.value.object.get("message").?.string, "[REDACTED]") != null);
    gap.abort();
    try runtime.flush(.written);
}

test "empty redaction path validates raw nested events before reserving a journal slot" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/validated.journal", .{tmp.sub_path});
    var output_bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&output_bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .submission = .asynchronous, .journal = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 1024 }, .routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "validated" }} });
    defer runtime.destroy();
    var cycle: [1]kron.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    var chain: [kron.fields.max_value_depth + 1]kron.Value = undefined;
    for (&chain, 0..) |*node, i| node.* = if (i + 1 < chain.len) .{ .array = chain[i + 1 ..][0..1] } else .{ .group = &.{} };
    const too_many = [_]kron.Value{.null_value} ** kron.fields.max_value_nodes;
    const cases = [_]struct { fields: []const kron.Field, arguments: []const kron.Field = &.{}, failure: anyerror }{
        .{ .fields = &.{kron.kv("cycle", kron.array(&cycle))}, .failure = error.CyclicValue },
        .{ .fields = &.{kron.kv("deep", chain[0])}, .failure = error.ValueTooDeep },
        .{ .fields = &.{kron.kv("nodes", kron.array(&too_many))}, .failure = error.TooManyValueNodes },
        .{ .fields = &.{ kron.kv("same", 1), kron.kv("same", 2) }, .failure = error.DuplicateKey },
        .{ .fields = &.{}, .arguments = &.{kron.kv("", kron.array(&cycle))}, .failure = error.CyclicValue },
    };
    for (cases) |case| {
        const admission = switch (runtime.begin(.info, "raw")) {
            .ready => |value| value,
            else => return error.UnexpectedAdmission,
        };
        defer runtime.end();
        try testing.expectError(case.failure, runtime.submit(admission, .{ .level = .info, .scope = "raw", .message = "invalid", .timestamp_ns = 0, .fields = case.fields, .format_args = case.arguments }));
        try testing.expectEqual(@as(u64, 0), runtime.journal.?.reservationTarget());
        try testing.expectEqual(@as(usize, 0), runtime.journal.?.pending());
    }
    try testing.expectEqual(@as(u64, 0), runtime.health().accepted);
}

test "empty and configured redaction paths preserve async bytes secrets and source ownership" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/paths.journal", .{tmp.sub_path});
    var bytes: [16 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const route = kron.RouteOptions{ .name = "output", .sink = memory.sink(), .recovery_identity = "paths" };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .submission = .asynchronous, .journal = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 2048 }, .routes = &.{route} });
    defer runtime.destroy();
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    var message = "borrowed".*;
    var name = "alice".*;
    var password = "private".*;
    var descriptor = [_]kron.Field{ kron.kv("name", @as([]const u8, &name)), kron.kv("password", @as([]const u8, &password)), kron.kv("secret", kron.secret("never captured")) };
    const log = runtime.scoped("paths");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, &message, .{ .object = kron.group(&descriptor) }));
    _ = try runtime.replaceConfiguration(&.{route}, .{ .redaction = &.{.{ .key = "password", .action = .mask }} });
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogf(.info, "object {any}", .{kron.group(&descriptor)}, .{ .object = kron.group(&descriptor) }));
    _ = try runtime.replaceConfiguration(&.{route}, .{});
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "empty again", .{ .object = kron.group(&descriptor) }));
    // Both capture paths have already copied before accepted.
    try testing.expectEqualStrings("private", password[0..]);
    @memset(&message, 'x');
    @memset(&name, 'x');
    @memset(&password, 'x');
    descriptor = @splat(kron.kv("overwritten", false));
    gap.abort();
    try runtime.flush(.written);
    var lines = std.mem.tokenizeScalar(u8, memory.written(), '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, line, .{});
        defer parsed.deinit();
        const object = parsed.value.object.get("attributes").?.object.get("object").?.object;
        try testing.expectEqualStrings("alice", object.get("name").?.string);
        try testing.expectEqualStrings(if (count == 1) "[REDACTED]" else "private", object.get("password").?.string);
        try testing.expectEqualStrings("[REDACTED]", object.get("secret").?.string);
        if (count == 1) {
            try testing.expect(std.mem.indexOf(u8, parsed.value.object.get("message").?.string, "private") == null);
            try testing.expect(std.mem.indexOf(u8, parsed.value.object.get("message").?.string, "[REDACTED]") != null);
        }
        count += 1;
    }
    try testing.expectEqual(@as(usize, 3), count);
}
