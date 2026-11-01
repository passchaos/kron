const std = @import("std");
const kron = @import("kron");

test "system local time conversion stays on async consumer including fused inline and schema output" {
    if (!kron.time.local.supported) return error.SkipZigTest;
    inline for (.{ false, true }) |spsc| {
        inline for (.{ false, true }) |prepared| {
            inline for (.{ false, true }) |mapped| {
                var tmp = std.testing.tmpDir(.{});
                defer tmp.cleanup();
                var path_bytes: [256]u8 = undefined;
                const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/local.journal", .{tmp.sub_path});
                var bytes: [32768]u8 = undefined;
                var sink = kron.MemorySink.initBuffer(&bytes);
                var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
                const runtime = try kron.Runtime.create(allocator.allocator(), std.testing.io, .{
                    .submission = if (spsc) .low_latency else .asynchronous,
                    .memory_queue = if (!mapped) .{ .capacity = 128, .max_record_bytes = 1024, .schema_capacity = if (prepared) 2 else 0 } else null,
                    .journal = if (mapped) .{ .path = path, .capacity = 128, .max_record_bytes = 1024, .schema_capacity = if (prepared) 2 else 0 } else null,
                    .max_thread_channels = if (spsc) 1 else 0,
                    .thread_channel_capacity = 128,
                    .routes = &.{.{ .name = "local", .sink = sink.sink(), .recovery_identity = "local-fixture", .timestamp = .{ .zone = .local } }},
                });
                defer runtime.destroy();
                const base = if (spsc) try runtime.attachThread(.{ .scope = "local" }) else runtime.scoped("local");
                defer if (spsc) base.detach() catch {};
                const store = if (spsc) base.owner.producer_token.journal else runtime.journal.?;
                var gap = if (spsc) try store.reserveSingleProducer(base.owner.producer_token) else try store.reserve();
                var reserved = true;
                defer if (reserved) gap.abort();
                const template: kron.Event = .{ .level = .info, .scope = "local", .message = "queued", .timestamp_ns = 1_700_000_000_123_456_789, .fields = &.{kron.kv("id", @as(u64, 0))} };
                const binding: ?kron.SchemaBinding = if (prepared) (if (spsc) try runtime.prewarmThreadSchema(1, template) else try runtime.prewarmSchema(template)) else null;
                const before = kron.time.local.TestingAudit.conversions.load(.acquire);
                allocator.fail_index = allocator.alloc_index;
                allocator.resize_fail_index = allocator.resize_index;
                for (0..96) |index| {
                    const admission = base.owner.begin(.info, "local").ready;
                    defer base.owner.end();
                    var event = template;
                    event.timestamp_ns += @as(i64, @intCast(index));
                    event.fields = &.{kron.kv("id", @as(u64, @intCast(index)))};
                    const result = if (binding) |schema|
                        (if (spsc) try base.owner.submitWithSchema(admission, event, schema) else try runtime.submitWithSchema(admission, event, schema))
                    else
                        (if (spsc) try base.owner.submit(admission, event) else try runtime.submit(admission, event));
                    try std.testing.expectEqual(kron.EmitResult.accepted, result);
                }
                // The gap prevents delivery: accepted events have triggered no
                // calendar conversion, including the producer/prepared paths.
                try std.testing.expectEqual(before, kron.time.local.TestingAudit.conversions.load(.acquire));
                gap.abort();
                reserved = false;
                try runtime.flush(.written);
                try std.testing.expectEqual(before + 1, kron.time.local.TestingAudit.conversions.load(.acquire));
                try std.testing.expect(kron.time.local.TestingAudit.thread_id.load(.acquire) != std.Thread.getCurrentId());
                try std.testing.expectEqual(@as(usize, 96), sink.records);
                try std.testing.expect(!allocator.has_induced_failure);
                try runtime.shutdown(.drain);
                var lines = std.mem.splitScalar(u8, sink.written(), '\n');
                for (0..96) |index| {
                    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, lines.next().?, .{});
                    defer parsed.deinit();
                    const expected = template.timestamp_ns + @as(i64, @intCast(index));
                    const timestamp = try kron.time.rfc3339.parse(parsed.value.object.get("timestamp").?.string);
                    try std.testing.expectEqual(expected, timestamp.timestamp.nanoseconds);
                }
            }
        }
    }
}

test "system local time initialization rolls back and multi format routes preserve timestamps" {
    if (!kron.time.local.supported) return error.SkipZigTest;
    var buffers: [3][4096]u8 = undefined;
    var sinks = [_]kron.MemorySink{ kron.MemorySink.initBuffer(&buffers[0]), kron.MemorySink.initBuffer(&buffers[1]), kron.MemorySink.initBuffer(&buffers[2]) };
    const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
        .clock = kron.Clock.zeroTimestamp(),
        .routes = &.{
            .{ .name = "json", .sink = sinks[0].sink(), .format = .json, .timestamp = .{ .zone = .local } },
            .{ .name = "text", .sink = sinks[1].sink(), .format = .text, .timestamp = .{ .zone = .local } },
            .{ .name = "logfmt", .sink = sinks[2].sink(), .format = .logfmt, .timestamp = .{ .zone = .local } },
        },
    });
    defer runtime.destroy();
    _ = try runtime.scoped("local").tryEmit(.info, "three formats", .{});
    try runtime.shutdown(.drain);
    var expected_bytes: [kron.time.rfc3339.max_length]u8 = undefined;
    const expected = try kron.time.rfc3339.format(.{ .nanoseconds = 0 }, .{ .zone = .local }, &expected_bytes);
    for (&sinks) |*sink| try std.testing.expect(std.mem.indexOf(u8, sink.written(), expected) != null);
    const Fixture = struct {
        fn create(allocator: std.mem.Allocator, output: kron.Sink) !void {
            const owner = try kron.Runtime.create(allocator, std.testing.io, .{ .routes = &.{.{ .name = "local", .sink = output, .timestamp = .{ .zone = .local } }} });
            defer owner.destroy();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Fixture.create, .{sinks[0].sink()});
}
