//! Prepared measurement stays in the current safe runtime call; public codecs
//! and rewritten events still validate their complete borrowed value tree.
const std = @import("std");
const Runtime = @import("../runtime.zig").Runtime;
const types = @import("../runtime_types.zig");
const field = @import("../field.zig");
const Event = @import("../event.zig").Event;
const reference = @import("../schema_codec.zig");
const codec = @import("../codec.zig");
const MemorySink = @import("../../sink/memory.zig").MemorySink;

test "prepared runtime measure visits the final tree once while public reference codecs always validate" {
    inline for (.{ .asynchronous, .low_latency }) |submission| {
        inline for (.{ false, true }) |persistent| {
            var tmp = std.testing.tmpDir(.{});
            defer tmp.cleanup();
            var path_bytes: [160]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/prepared-measure.journal", .{tmp.sub_path});
            var bytes: [8192]u8 = undefined;
            var sink = MemorySink.initBuffer(&bytes);
            var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
            const runtime = try Runtime.create(allocator.allocator(), std.testing.io, .{
                .submission = submission,
                .memory_queue = if (persistent) null else .{ .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 },
                .journal = if (persistent) .{ .path = path, .capacity = 8, .max_record_bytes = 1024, .schema_capacity = 2, .max_schema_bytes = 1024 } else null,
                .max_thread_channels = if (submission == .low_latency) 1 else 0,
                .thread_channel_capacity = 8,
                .routes = &.{.{ .name = "out", .sink = sink.sink(), .recovery_identity = "prepared-measure" }},
            });
            defer runtime.destroy();
            const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = "measure" }) else runtime.scoped("measure");
            defer if (submission == .low_latency) log.detach() catch {};
            const journal = if (submission == .low_latency) log.owner.producer_token.journal else runtime.journal.?;
            const event: Event = .{ .level = .info, .scope = "measure", .message = "value {d}", .message_template = true, .timestamp_ns = 0, .fields = &.{ field.kv("nested", field.group(&.{ field.kv("u", @as(u64, 42)), field.kv("s", "hello") })), field.kv("flag", true) }, .format_args = &.{field.kv("", @as(u64, 7))} };
            const binding = if (submission == .low_latency) try runtime.prewarmThreadSchema(1, event) else try runtime.prewarmSchema(event);
            var gap = if (submission == .low_latency) try journal.reserveSingleProducer(log.owner.producer_token) else try journal.reserve();
            defer gap.abort();
            allocator.fail_index = allocator.alloc_index;
            allocator.resize_fail_index = allocator.resize_index;
            const admission = switch (if (submission == .low_latency) log.owner.begin(.info, "measure") else runtime.begin(.info, "measure")) {
                .ready => |ready| ready,
                else => return error.UnexpectedAdmission,
            };
            var admitted = true;
            defer if (admitted) {
                if (submission == .low_latency) log.owner.end() else runtime.end();
            };
            const before = field.TestingAudit.visited_values;
            const result = if (submission == .low_latency) try log.owner.submitWithSchema(admission, event, binding) else try runtime.submitWithSchema(admission, event, binding);
            try std.testing.expectEqual(types.EmitResult.accepted, result);
            try std.testing.expectEqual(@as(usize, 5), field.TestingAudit.visited_values - before);
            if (submission == .low_latency) log.owner.end() else runtime.end();
            admitted = false;
            var output: [1024]u8 = undefined;
            const public_before = field.TestingAudit.visited_values;
            _ = try reference.encodeReference(event, binding.definition, &output);
            try std.testing.expectEqual(@as(usize, 5), field.TestingAudit.visited_values - public_before);
            gap.abort();
            try runtime.flush(.written);
            try std.testing.expectEqual(@as(u64, 1), runtime.health().written);
            try std.testing.expect(std.mem.indexOf(u8, sink.written(), "value 7") != null);
            try std.testing.expect(!allocator.has_induced_failure);
        }
    }
}

test "prepared runtime measure preserves predicate before shape but complete tree before predicate" {
    var bytes: [8192]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 512, .schema_capacity = 2, .max_schema_bytes = 1024 },
        .predicate = "status >= 500",
        .routes = &.{.{ .name = "out", .sink = sink.sink() }},
    });
    defer runtime.destroy();
    var event: Event = .{ .level = .info, .scope = "predicate", .message = "event", .timestamp_ns = 0, .fields = &.{field.kv("status", @as(u64, 400))} };
    const binding = try runtime.prewarmSchema(event);
    const admission = switch (runtime.begin(.info, "predicate")) {
        .ready => |ready| ready,
        else => return error.UnexpectedAdmission,
    };
    defer runtime.end();
    const target = runtime.journal.?.reservationTarget();
    event.fields = &.{ field.kv("status", @as(u64, 400)), field.kv("wrong", true) };
    event.level = .off;
    event.tree_validated = true; // Public hints cannot bypass runtime checking.
    try std.testing.expectEqual(types.EmitResult.filtered, try runtime.submitWithSchema(admission, event, binding));
    var cycle: [1]field.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    event.fields = &.{ field.kv("status", @as(u64, 400)), field.kv("bad", field.array(&cycle)) };
    try std.testing.expectError(error.CyclicValue, runtime.submitWithSchema(admission, event, binding));
    try std.testing.expectEqual(target, runtime.journal.?.reservationTarget());
    try std.testing.expectEqual(@as(usize, 0), sink.records);
    var payload: [512]u8 = @splat(0xac);
    try std.testing.expectError(error.CyclicValue, reference.encodeReference(event, binding.definition, &payload));
    try std.testing.expectEqualSlices(u8, &(@as([512]u8, @splat(0xac))), &payload);
}

test "prepared runtime measure retains full drop fallback and shape level capacity ordering" {
    inline for (.{ .drop_newest, .fallback_sync }) |overflow| {
        var bytes: [8192]u8 = undefined;
        var sink = MemorySink.initBuffer(&bytes);
        const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = .asynchronous,
            .overflow = overflow,
            .memory_queue = .{ .capacity = 2, .max_record_bytes = 512, .schema_capacity = 2, .max_schema_bytes = 1024 },
            .routes = &.{.{ .name = "out", .sink = sink.sink() }},
        });
        defer runtime.destroy();
        var event: Event = .{ .level = .info, .scope = "full", .message = "event", .timestamp_ns = 0, .fields = &.{field.kv("right", @as(u64, 1))} };
        const binding = try runtime.prewarmSchema(event);
        const admission = switch (runtime.begin(.info, "full")) {
            .ready => |ready| ready,
            else => return error.UnexpectedAdmission,
        };
        var admitted = true;
        defer if (admitted) runtime.end();
        var first = try runtime.journal.?.reserve();
        defer first.abort();
        var second = try runtime.journal.?.reserve();
        defer second.abort();
        const full_target = runtime.journal.?.reservationTarget();
        event.fields = &.{field.kv("wrong", @as(u64, 1))};
        if (overflow == .drop_newest) {
            try std.testing.expectEqual(types.EmitResult.dropped_full, try runtime.submitWithSchema(admission, event, binding));
        } else try std.testing.expectError(error.SchemaMismatch, runtime.submitWithSchema(admission, event, binding));
        try std.testing.expectEqual(full_target, runtime.journal.?.reservationTarget());
        try std.testing.expectEqual(@as(usize, 0), sink.records);
        runtime.end();
        admitted = false;
        first.abort();
        second.abort();
        try runtime.flush(.written);
        var ready = switch (runtime.begin(.info, "full")) {
            .ready => |value| value,
            else => return error.UnexpectedAdmission,
        };
        var ready_open = true;
        defer if (ready_open) runtime.end();
        const target = runtime.journal.?.reservationTarget();
        try std.testing.expectError(error.SchemaMismatch, runtime.submitWithSchema(ready, event, binding));
        try std.testing.expectEqual(target + 1, runtime.journal.?.reservationTarget());
        runtime.end();
        ready_open = false;
        try runtime.flush(.written);
        ready = switch (runtime.begin(.info, "full")) {
            .ready => |value| value,
            else => return error.UnexpectedAdmission,
        };
        ready_open = true;
        event.fields = &.{field.kv("right", @as(u64, 1))};
        event.message = @as([*]const u8, @ptrFromInt(1))[0..std.math.maxInt(usize)];
        event.level = .off;
        try std.testing.expectError(error.InvalidLevel, runtime.submitWithSchema(ready, event, binding));
        runtime.end();
        ready_open = false;
        try runtime.flush(.written);
        ready = switch (runtime.begin(.info, "full")) {
            .ready => |value| value,
            else => return error.UnexpectedAdmission,
        };
        ready_open = true;
        event.level = .info;
        try std.testing.expectEqual(types.EmitResult.dropped_oversize, try runtime.submitWithSchema(ready, event, binding));
        try std.testing.expectEqual(@as(usize, 0), sink.records);
    }
}

test "prepared runtime measure leaves rewritten redaction and canonical binding checks independent" {
    var bytes: [8192]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 512, .schema_capacity = 2, .max_schema_bytes = 1024 },
        .redaction = &.{.{ .key = "hidden", .action = .drop }},
        .routes = &.{.{ .name = "out", .sink = sink.sink() }},
    });
    defer runtime.destroy();
    const event: Event = .{ .level = .info, .scope = "rewrite", .message = "event", .timestamp_ns = 0, .fields = &.{ field.kv("visible", @as(u64, 1)), field.kv("hidden", "original secret") } };
    const binding = try runtime.prewarmSchema(event);
    const log = try runtime.loggerWithSchema(binding);
    _ = try log.tryEmit(.info, "event", .{ .visible = @as(u64, 1), .hidden = "original secret" });
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(u64, 1), runtime.health().written);
    try std.testing.expect(std.mem.indexOf(u8, sink.written(), "hidden") == null);
    try std.testing.expect(std.mem.indexOf(u8, sink.written(), "original secret") == null);
    var forged = log;
    forged.owner.binding.definition.fields_wire = &.{};
    _ = try forged.tryEmit(.info, "event", .{ .visible = @as(u64, 2), .hidden = "not stored" });
    try runtime.flush(.written);
    try std.testing.expectEqual(@as(u64, 2), runtime.health().written);
}
