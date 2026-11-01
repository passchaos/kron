//! Typed capture contracts through public Runtime/logger factories.
const std = @import("std");
const kron = @import("kron");
const testing = std.testing;

fn NamedInput(comptime count: usize) type {
    @setEvalBranchQuota(100000);
    var names: [count][:0]const u8 = undefined;
    for (&names, 0..) |*name, index| name.* = std.fmt.comptimePrint("field{d}", .{index});
    return @Struct(.auto, null, &names, &@splat(u64), &@splat(.{}));
}

fn namedInput(comptime count: usize) NamedInput(count) {
    var value: NamedInput(count) = undefined;
    inline for (0..count) |index| @field(value, std.fmt.comptimePrint("field{d}", .{index})) = index;
    return value;
}

fn parse(line: []const u8) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, testing.allocator, line, .{});
}

test "capture: named five and ten scalar fields and empty deferred arguments use default sync logger" {
    var bytes: [16 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "memory", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    const log = runtime.logger(.{});
    const five = .{ .value = kron.Value{ .unsigned = 42 }, .optional = @as(?u8, 7), .bytes = kron.bytes("\x00\xff"), .float = @as(f64, 1.25), .wide = std.math.maxInt(u128) };
    const ten = .{ .value = kron.Value{ .boolean = true }, .optional = @as(?u8, null), .bytes = kron.bytes("\x01\x02"), .float = @as(f32, -2.5), .wide = std.math.minInt(i128), .null = @as(?bool, null), .text = "named", .signed = @as(i32, -17), .duration = kron.durationNs(9), .timestamp = kron.timestampNs(123) };
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "five", five));
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogf(.info, "typed {d} {s}", .{ @as(u16, 9), "args" }, ten));
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogf(.info, "no arguments", .{}, .{}));
    var lines = std.mem.tokenizeScalar(u8, memory.written(), '\n');
    const first = try parse(lines.next().?);
    defer first.deinit();
    const first_attributes = first.value.object.get("attributes").?.object;
    try testing.expectEqual(@as(usize, 5), first_attributes.count());
    try testing.expectEqual(@as(i64, 42), first_attributes.get("value").?.integer);
    try testing.expectEqual(@as(i64, 7), first_attributes.get("optional").?.integer);
    try testing.expectEqualStrings("hex:00ff", first_attributes.get("bytes").?.string);
    try testing.expectEqual(@as(f64, 1.25), first_attributes.get("float").?.float);
    try testing.expectEqualStrings("340282366920938463463374607431768211455", first_attributes.get("wide").?.string);
    const second = try parse(lines.next().?);
    defer second.deinit();
    const second_attributes = second.value.object.get("attributes").?.object;
    try testing.expectEqual(@as(usize, 10), second_attributes.count());
    try testing.expect(second_attributes.get("value").?.bool);
    try testing.expect(second_attributes.get("optional").? == .null);
    try testing.expect(second_attributes.get("null").? == .null);
    try testing.expectEqualStrings("hex:0102", second_attributes.get("bytes").?.string);
    try testing.expectEqual(@as(f64, -2.5), second_attributes.get("float").?.float);
    try testing.expectEqualStrings("-170141183460469231731687303715884105728", second_attributes.get("wide").?.string);
    try testing.expectEqualStrings("typed 9 args", second.value.object.get("message").?.string);
    const third = try parse(lines.next().?);
    defer third.deinit();
    try testing.expectEqual(@as(usize, 0), third.value.object.get("attributes").?.object.count());
    try testing.expectEqualStrings("no arguments", third.value.object.get("message").?.string);
    try testing.expect(lines.next() == null);
    try testing.expectEqual(@as(usize, 3), memory.records);
}

test "capture: named 64 fields fit while named 65 and dynamic duplicates fail before queue reservation" {
    var bytes: [16 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 4, .max_record_bytes = 8192 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("field.boundary");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "64", namedInput(64)));
    const target = runtime.journal.?.reservationTarget();
    try testing.expectError(error.TooManyFields, log.tryEmit(.info, "65", namedInput(65)));
    const duplicate = [_]kron.Field{ kron.kv("same", 1), kron.kv("same", 2) };
    try testing.expectError(error.DuplicateKey, log.tryEmit(.info, "slice duplicate", duplicate[0..]));
    try testing.expectError(error.DuplicateKey, log.tryEmit(.info, "tuple duplicate", .{ kron.kv("same", 1), kron.kv("same", 2) }));
    try testing.expectEqual(target, runtime.journal.?.reservationTarget());
    try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
    try testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
    var fields: [4]kron.Field = undefined;
    var count: usize = 0;
    try kron.fields.appendFields(&fields, &count, .{ .existing = 1 });
    try testing.expectError(error.DuplicateKey, kron.fields.appendFields(&fields, &count, .{ .existing = 2, .new = 3 }));
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqual(@as(u128, 1), fields[0].value.unsigned);
    try runtime.flush(.written);
    const encoded = try parse(memory.written());
    defer encoded.deinit();
    const attributes = encoded.value.object.get("attributes").?.object;
    try testing.expectEqual(@as(usize, 64), attributes.count());
    inline for (0..64) |index| try testing.expectEqual(@as(i64, index), attributes.get(std.fmt.comptimePrint("field{d}", .{index})).?.integer);
}

test "capture: shared memory and SPSC snapshot source strings keys and deferred values behind a gap" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var bytes: [8192]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&bytes);
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 4, .max_record_bytes = 4096 },
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 4,
            .routes = &.{.{ .name = "memory", .sink = memory.sink() }},
        });
        defer runtime.destroy();
        var scope = "capture.snapshot".*;
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = scope[0..] }) else runtime.scoped(scope[0..]);
        defer if (submission == .low_latency) log.detach() catch {};
        const queue = if (submission == .low_latency) log.owner.producer_token.journal else runtime.journal.?;
        var gap = if (submission == .low_latency) try queue.reserveSingleProducer(log.owner.producer_token) else try queue.reserve();
        defer gap.abort();
        var text = "borrowed original".*;
        var key = "dynamic".*;
        var blob = [_]u8{ 0, 255 };
        var module: [7:0]u8 = "capture".*;
        var file: [10:0]u8 = "source.zig".*;
        var function: [5:0]u8 = "input".*;
        const source: std.builtin.SourceLocation = .{ .module = &module, .file = &file, .fn_name = &function, .line = 17, .column = 4 };
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryLogfAt(source, .info, "value {s}", .{text[0..]}, .{ kron.kv(key[0..], text[0..]), kron.kv("blob", kron.bytes(&blob)) }));
        @memset(&scope, 'x');
        @memset(&text, 'x');
        @memset(&key, 'x');
        @memset(&blob, 42);
        @memset(module[0..module.len], 'x');
        @memset(file[0..file.len], 'x');
        @memset(function[0..function.len], 'x');
        gap.abort();
        try runtime.flush(.written);
        const encoded = try parse(memory.written());
        defer encoded.deinit();
        const object = encoded.value.object;
        try testing.expectEqualStrings("capture.snapshot", object.get("scope").?.string);
        try testing.expectEqualStrings("value borrowed original", object.get("message").?.string);
        try testing.expectEqualStrings("borrowed original", object.get("attributes").?.object.get("dynamic").?.string);
        try testing.expectEqualStrings("hex:00ff", object.get("attributes").?.object.get("blob").?.string);
        const restored = object.get("source").?.object;
        try testing.expectEqualStrings("capture", restored.get("module").?.string);
        try testing.expectEqualStrings("source.zig", restored.get("file").?.string);
        try testing.expectEqualStrings("input", restored.get("function").?.string);
        try testing.expectEqual(@as(i64, 17), restored.get("line").?.integer);
        try testing.expectEqual(@as(i64, 4), restored.get("column").?.integer);
    }
}

test "capture: borrowed and owned child layers retain key positions and event priority" {
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "memory", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    var mutable = "original context".*;
    const parent = runtime.scoped("contexts").withBorrowed(.{ .request = 1, .parent = true, .snapshot = mutable[0..] });
    const borrowed = parent.withBorrowed(.{ .request = 2, .child = true });
    var owned = try parent.withOwned(testing.allocator, .{ .request = 2, .owned = true });
    defer owned.destroy();
    try testing.expectEqual(kron.EmitResult.accepted, try borrowed.tryEmit(.info, "borrowed", .{ .request = 4, .event = true }));
    @memset(&mutable, 'x');
    const owned_child = owned.withBorrowed(.{ .request = 3, .child = true });
    try testing.expectEqual(kron.EmitResult.accepted, try owned_child.tryEmit(.info, "owned", .{ .request = 4, .event = true }));
    var lines = std.mem.tokenizeScalar(u8, memory.written(), '\n');
    const expected_borrowed = [_][]const u8{ "request", "parent", "snapshot", "child", "event" };
    const expected_owned = [_][]const u8{ "request", "parent", "snapshot", "owned", "child", "event" };
    inline for (.{ expected_borrowed[0..], expected_owned[0..] }) |expected| {
        const encoded = try parse(lines.next().?);
        defer encoded.deinit();
        const attributes = encoded.value.object.get("attributes").?.object;
        try testing.expectEqual(@as(i64, 4), attributes.get("request").?.integer);
        try testing.expectEqualStrings("original context", attributes.get("snapshot").?.string);
        try testing.expectEqual(expected.len, attributes.count());
        var iterator = attributes.iterator();
        for (expected) |key| try testing.expectEqualStrings(key, iterator.next().?.key_ptr.*);
    }
    var merged: [64]kron.Field = undefined;
    var count: usize = 0;
    try owned.appendContext(&merged, &count);
    try testing.expectEqual(@as(u128, 2), merged[0].value.unsigned);
    try testing.expectEqualStrings("original context", merged[2].value.string);
}

test "capture: named root borrowed and owned emissions allocate nothing after initialization" {
    var bytes: [128 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const runtime = try kron.Runtime.create(failing.allocator(), testing.io, .{
        .routes = &.{.{ .name = "memory", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    const root = runtime.scoped("noalloc");
    const borrowed = root.withBorrowed(.{ .context = "borrowed" });
    var owned = try root.withOwned(failing.allocator(), .{ .context = "owned" });
    defer owned.destroy();
    const initialized = failing.alloc_index;
    failing.fail_index = initialized;
    for (0..50) |index| {
        try testing.expectEqual(kron.EmitResult.accepted, try root.tryEmit(.info, "named five", namedInput(5)));
        try testing.expectEqual(kron.EmitResult.accepted, try root.tryLogf(.info, "named ten {d}", .{index}, namedInput(10)));
        try testing.expectEqual(kron.EmitResult.accepted, try borrowed.tryEmit(.info, "child", .{ .index = index }));
        try testing.expectEqual(kron.EmitResult.accepted, try owned.tryLogf(.info, "owned {d}", .{index}, .{}));
    }
    try runtime.flush(.written);
    try testing.expectEqual(initialized, failing.alloc_index);
    try testing.expect(!failing.has_induced_failure);
    try testing.expectEqual(@as(usize, 200), memory.records);
}

test "capture: clock mutation of a borrowed tree is validated again before reservation" {
    const MutatingClock = struct {
        tree: *[1]kron.Value,
        calls: usize = 0,
        mutate: bool = true,

        fn real(raw: ?*anyopaque, _: std.Io) i64 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            if (self.mutate) self.tree[0] = .{ .array = self.tree };
            return 123;
        }
    };
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        var values = [_]kron.Value{.{ .unsigned = 1 }};
        var clock: MutatingClock = .{ .tree = &values };
        var bytes: [8192]u8 = undefined;
        var memory = kron.MemorySink.initBuffer(&bytes);
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = submission,
            .memory_queue = .{ .capacity = 4, .max_record_bytes = 1024 },
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .thread_channel_capacity = 4,
            .routes = &.{.{ .name = "output", .sink = memory.sink() }},
            .clock = .{ .context = &clock, .real_now = MutatingClock.real },
        });
        defer runtime.destroy();
        const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "mutation" }) else runtime.scoped("mutation");
        defer if (submission == .low_latency) log.detach() catch {};
        const journal = if (submission == .low_latency) runtime.thread_registry.?.getJournal(0) else runtime.journal.?;
        const target = journal.reservationTarget();
        try testing.expectError(error.CyclicValue, log.tryEmit(.info, "mutated", .{
            .scalar = @as(u64, 42),
            .tree = kron.array(&values),
        }));
        try testing.expectEqual(@as(usize, 1), clock.calls);
        try testing.expectEqual(target, journal.reservationTarget());
        try testing.expectEqual(@as(u64, 0), runtime.health().accepted);
        values[0] = .{ .unsigned = 7 };
        clock.mutate = false;
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "valid", .{
            .scalar = @as(u64, 42),
            .tree = kron.array(&values),
        }));
        try runtime.flush(.written);
        const decoded = try parse(memory.written());
        defer decoded.deinit();
        const attributes = decoded.value.object.get("attributes").?.object;
        try testing.expectEqual(@as(i64, 42), attributes.get("scalar").?.integer);
        try testing.expectEqual(@as(i64, 7), attributes.get("tree").?.array.items[0].integer);
    }
}

const CountClock = struct {
    calls: usize = 0,
    fn real(context: ?*anyopaque, _: std.Io) i64 {
        const self: *CountClock = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        return 42;
    }
    fn clock(self: *CountClock) kron.Clock {
        return .{ .context = self, .real_now = real };
    }
};

test "capture: invalid nested cycles nodes depth and sibling keys fail before timestamp and queue reservation" {
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    var clock: CountClock = .{};
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 4, .max_record_bytes = 4096 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink() }},
        .clock = clock.clock(),
    });
    defer runtime.destroy();
    const log = runtime.scoped("invalid");
    const target = runtime.journal.?.reservationTarget();
    var cycle: [1]kron.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    try testing.expectError(error.CyclicValue, log.tryEmit(.info, "cycle", .{ .cycle = kron.array(&cycle) }));
    var nodes: [kron.fields.max_value_nodes]kron.Value = @splat(.null_value);
    try testing.expectError(error.TooManyValueNodes, log.tryEmit(.info, "nodes", .{ .array = kron.array(&nodes) }));
    var chain: [kron.fields.max_value_depth + 1]kron.Value = undefined;
    chain[0] = .{ .array = &.{} };
    for (1..chain.len) |index| chain[index] = .{ .array = chain[index - 1 .. index] };
    try testing.expectError(error.ValueTooDeep, log.tryEmit(.info, "depth", .{ .root = chain[chain.len - 1] }));
    const duplicates = [_]kron.Field{ kron.kv("same", 1), kron.kv("same", 2) };
    try testing.expectError(error.DuplicateKey, log.tryEmit(.info, "group keys", .{ .group = kron.group(&duplicates) }));
    try testing.expectEqual(@as(usize, 0), clock.calls);
    try testing.expectEqual(target, runtime.journal.?.reservationTarget());
    try testing.expectEqual(@as(u64, 0), runtime.health().accepted);
    try testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "valid after failures", .{ .valid = true }));
    try runtime.flush(.written);
    try testing.expectEqual(@as(usize, 1), clock.calls);
    try testing.expectEqual(@as(usize, 1), memory.records);
}
