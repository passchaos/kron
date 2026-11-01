//! Public object adapter lifetime and allocation contract tests.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const testing = std.testing;

const User = struct {
    id: u64,
    name: []const u8,
    password: *const u64,
    values: kron.fields.Array,
    hidden: kron.fields.Secret,
};
const UserAdapter = kron.Adapter(User, &.{ "id", "name", "values", "hidden" });

fn expectUser(line: []const u8, id: i64, name: []const u8) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, line, .{});
    defer parsed.deinit();
    const user = parsed.value.object.get("attributes").?.object.get("user").?.object;
    try testing.expectEqual(id, user.get("id").?.integer);
    try testing.expectEqualStrings(name, user.get("name").?.string);
    try testing.expectEqualStrings(kron.fields.redacted, user.get("hidden").?.string);
    try testing.expect(user.get("password") == null);
}

test "object adapter JSON selects explicit fields and copies scalar values" {
    var bytes: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    const password: u64 = 42;
    var name = "alice".*;
    var input: User = .{ .id = 7, .name = &name, .password = &password, .values = kron.array(&.{kron.fields.fromAny(true)}), .hidden = kron.secret("raw-selected-secret") };
    var adapter = UserAdapter.init();
    const captured = try adapter.capture(&input);
    input.id = 99;
    try kron.encoder.encode(.json, .{ .level = .info, .scope = "object", .message = "selected", .timestamp_ns = 0, .fields = &.{kron.kv("user", captured)} }, &writer);
    try expectUser(writer.buffered(), 7, "alice");
    try testing.expect(std.mem.indexOf(u8, writer.buffered(), "raw-selected-secret") == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    try testing.expect(parsed.value.object.get("attributes").?.object.get("user").?.object.get("values").?.array.items[0].bool);
}

test "object adapter async acceptance snapshots source and reusable caller descriptors" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/adapter.journal", .{tmp.sub_path});
    var output: [16 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&output);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 4096 },
        .routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "adapter-snapshot", .format = .json }},
    });
    defer runtime.destroy();
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    const password: u64 = 123;
    var name = "alice".*;
    var nested = "first".*;
    var values = [_]kron.Value{kron.fields.fromAny(@as([]const u8, &nested))};
    var input: User = .{ .id = 7, .name = &name, .password = &password, .values = kron.array(&values), .hidden = kron.secret("raw-selected-secret") };
    var adapter = UserAdapter.init();
    const log = runtime.scoped("adapter.snapshot");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "first", .{ .user = try adapter.capture(&input) }));
    name = "bravo".*;
    nested = "later".*;
    input.id = 8;
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "second", .{ .user = try adapter.capture(&input) }));
    @memset(&name, 'x');
    @memset(&nested, 'x');
    values[0] = .null_value;
    adapter.fields = @splat(kron.kv("changed", false));
    gap.abort();
    try runtime.flush(.written);
    var lines = std.mem.tokenizeScalar(u8, memory.written(), '\n');
    const first = lines.next().?;
    const second = lines.next().?;
    try expectUser(first, 7, "alice");
    try expectUser(second, 8, "bravo");
    const first_parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, first, .{});
    defer first_parsed.deinit();
    const second_parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, second, .{});
    defer second_parsed.deinit();
    try testing.expectEqualStrings("first", first_parsed.value.object.get("attributes").?.object.get("user").?.object.get("values").?.array.items[0].string);
    try testing.expectEqualStrings("later", second_parsed.value.object.get("attributes").?.object.get("user").?.object.get("values").?.array.items[0].string);
    try testing.expect(lines.next() == null);
    try testing.expect(std.mem.indexOf(u8, runtime.journal.?.mapping.bytes, "raw-selected-secret") == null);
}

test "owned object context survives freeing every source and descriptor allocation" {
    var output: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&output);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .routes = &.{.{ .name = "output", .sink = memory.sink(), .format = .json }} });
    defer runtime.destroy();
    var owned = snapshot: {
        const name = try testing.allocator.dupe(u8, "alice");
        defer testing.allocator.free(name);
        const key = try testing.allocator.dupe(u8, "role");
        defer testing.allocator.free(key);
        const role = try testing.allocator.dupe(u8, "worker");
        defer testing.allocator.free(role);
        const blob = try testing.allocator.dupe(u8, &.{ 0, 255 });
        defer testing.allocator.free(blob);
        const nested = try testing.allocator.alloc(kron.Field, 1);
        defer testing.allocator.free(nested);
        nested[0] = kron.kv(key, role);
        const values = try testing.allocator.alloc(kron.Value, 2);
        defer testing.allocator.free(values);
        values[0] = kron.fields.fromAny(kron.group(nested));
        values[1] = kron.fields.fromAny(kron.bytes(blob));
        const input = try testing.allocator.create(User);
        defer testing.allocator.destroy(input);
        const password: u64 = 42;
        input.* = .{ .id = 7, .name = name, .password = &password, .values = kron.array(values), .hidden = kron.secret("forgotten") };
        var adapter = UserAdapter.init();
        break :snapshot try runtime.scoped("owned.adapter").withOwned(testing.allocator, .{ .user = try adapter.capture(input) });
    };
    defer owned.destroy();
    try testing.expectEqual(kron.EmitResult.accepted, try owned.tryEmit(.info, "source freed", .{}));
    try expectUser(memory.written(), 7, "alice");
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, memory.written(), .{});
    defer parsed.deinit();
    const values = parsed.value.object.get("attributes").?.object.get("user").?.object.get("values").?.array.items;
    try testing.expectEqualStrings("worker", values[0].object.get("role").?.string);
    try testing.expectEqualStrings("hex:00ff", values[1].string);
}

test "object adapter and repeated runtime emits allocate nothing after initialization" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    inline for (.{ .sync, .asynchronous }) |submission| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path: [128]u8 = undefined;
        const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/adapter-noalloc.journal", .{tmp.sub_path});
        var output: [16 * 1024]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&output);
        var failing = testing.FailingAllocator.init(testing.allocator, .{});
        const runtime = try kron.Runtime.create(failing.allocator(), testing.io, .{
            .submission = submission,
            .journal = if (submission == .asynchronous) .{ .path = journal_path, .capacity = 8, .max_record_bytes = 4096 } else null,
            .routes = &.{.{ .name = "output", .sink = memory.sink(), .recovery_identity = "adapter-noalloc", .format = .json }},
        });
        defer runtime.destroy();
        const password: u64 = 42;
        var input: User = .{ .id = 0, .name = "alice", .password = &password, .values = kron.array(&.{kron.fields.fromAny(true)}), .hidden = kron.secret("never-retained") };
        var adapter = UserAdapter.init();
        const before = failing.alloc_index;
        failing.fail_index = before;
        failing.resize_fail_index = failing.resize_index;
        const log = runtime.scoped("adapter.noalloc");
        for (0..8) |i| {
            input.id = i;
            const captured = try adapter.capture(&input);
            try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "selected", .{ .user = captured }));
        }
        try runtime.flush(.written);
        try testing.expectEqual(before, failing.alloc_index);
        try testing.expect(!failing.has_induced_failure);
        try testing.expectEqual(@as(usize, 8), memory.records);
    }
}

// Convenience capture has no descriptor storage hidden in its return value.
test "public object factory writes caller storage with renamed selected members" {
    const Record = struct { id: u64, name: []const u8, password: *const u8 };
    const password: u8 = 42;
    var input: Record = .{ .id = 7, .name = "alice", .password = &password };
    var storage: [2]kron.Field = undefined;
    const captured = try kron.object(&.{ "id", "name" }, &input, &storage);
    try testing.expectEqual(@intFromPtr(&storage), @intFromPtr(captured.value.ptr));
    const mapped = try kron.objectMapped(&.{
        .{ .member = "id", .key = "user_id" },
        .{ .member = "name", .key = "display_name" },
    }, &input, &storage);
    try testing.expectEqualStrings("user_id", mapped.value[0].key);
    try testing.expectEqualStrings("display_name", mapped.value[1].key);
}
