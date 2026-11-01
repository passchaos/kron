//! Encoder-only probe: includes scalar mutation and complete-output hashing.
//! Used to investigate noisy file-workflow regressions, not rank logging APIs.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    var attributes = [_]kron.Field{
        kron.kv("field0", @as(u64, 0)), kron.kv("field1", @as(u64, 1)),
        kron.kv("field2", @as(u64, 2)), kron.kv("field3", @as(u64, 3)),
        kron.kv("field4", @as(u64, 4)),
    };
    const nested = [_]kron.Field{
        kron.kv("group0", kron.group(&attributes)),
        kron.kv("group1", kron.group(&attributes)),
        kron.kv("group2", kron.group(&attributes)),
        kron.kv("group3", kron.group(&attributes)),
    };
    var event: kron.Event = .{
        .level = .info,
        .scope = "reference",
        .message = "event",
        .fields = &.{},
        .timestamp_ns = 1793462400000000000,
        .session = std.math.maxInt(u64),
        .channel = 1,
        .sequence = 1,
        .route_mask = 1,
        .config_generation = 1,
    };
    var report_bytes: [4096]u8 = undefined;
    var report = std.Io.Writer.fixed(&report_bytes);
    var bytes: [8192]u8 = undefined;
    for (0..3) |variant| {
        event.fields = if (variant == 1) &nested else &attributes;
        var checksum: u64 = 0;
        var written: u64 = 0;
        const count = 300000;
        const started = std.Io.Clock.awake.now(init.io).nanoseconds;
        for (0..count) |index| {
            for (&attributes, 0..) |*field, offset| field.value = if (variant == 2) .{ .unsigned = @as(u128, std.math.maxInt(u128)) - index - offset } else .{ .unsigned = index + offset };
            event.sequence = index + 1;
            event.timestamp_ns = 1793462400000000000 + @as(i64, @intCast(index));
            var output = std.Io.Writer.fixed(&bytes);
            try kron.encoder.encode(.json, event, &output);
            checksum +%= std.hash.Wyhash.hash(index, output.buffered());
            written += output.end;
            std.mem.doNotOptimizeAway(output.buffered());
        }
        const elapsed = std.Io.Clock.awake.now(init.io).nanoseconds - started;
        std.mem.doNotOptimizeAway(checksum);
        try report.print("{{\"case\":\"{s}\",\"iterations\":{d},\"elapsed_ns\":{d},\"ns_per_record\":{d},\"checksum\":{d},\"output_bytes\":{d}}}\n", .{
            switch (variant) {
                0 => "scalar5",
                1 => "nested20",
                else => "wide5",
            },
            count,
            elapsed,
            @as(f64, @floatFromInt(elapsed)) / count,
            checksum,
            written,
        });
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, report.buffered());
}
