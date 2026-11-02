//! Public encoder key-length controls; output bytes and hashes consumed.
const std = @import("std");
const kron = @import("kron");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedFormat;
    const format = std.meta.stringToEnum(kron.encoder.Format, args[1]) orelse return error.InvalidFormat;
    if (format == .binary) return error.InvalidFormat;
    var key_bytes: [5][64]u8 = undefined;
    var attributes: [5]kron.Field = undefined;
    var outer_keys: [4][64]u8 = undefined;
    var nested: [4]kron.Field = undefined;
    var event: kron.Event = .{
        .level = .info,
        .scope = "key.shapes",
        .message = "event",
        .fields = &.{},
        .timestamp_ns = 1793462400000000000,
        .session = 1,
        .sequence = 1,
        .route_mask = 1,
        .config_generation = 1,
    };
    var report_bytes: [16384]u8 = undefined;
    var report = std.Io.Writer.fixed(&report_bytes);
    var output_bytes: [16384]u8 = undefined;
    for ([_]usize{ 1, 3, 4, 6, 8, 9, 16, 32, 64 }) |length| {
        for (&attributes, &key_bytes, 0..) |*entry, *key, index| {
            @memset(key, 'f');
            key[length - 1] = '0' + @as(u8, @intCast(index));
            entry.* = kron.kv(key[0..length], @as(u64, index));
        }
        for (&nested, &outer_keys, 0..) |*entry, *key, index| {
            @memset(key, 'g');
            key[length - 1] = '0' + @as(u8, @intCast(index));
            entry.* = kron.kv(key[0..length], kron.group(&attributes));
        }
        for ([_]bool{ false, true }) |is_nested| {
            event.fields = if (is_nested) &nested else &attributes;
            var checksum: u64 = 0;
            var written: u64 = 0;
            const count = 100000;
            const started = std.Io.Clock.awake.now(init.io).nanoseconds;
            for (0..count) |index| {
                for (&attributes, 0..) |*entry, offset| entry.value = .{ .unsigned = index + offset };
                event.sequence = index + 1;
                event.timestamp_ns = 1793462400000000000 + @as(i64, @intCast(index));
                var output = std.Io.Writer.fixed(&output_bytes);
                try kron.encoder.encode(format, event, &output);
                checksum +%= std.hash.Wyhash.hash(index, output.buffered());
                written += output.end;
                std.mem.doNotOptimizeAway(output.buffered());
            }
            const elapsed = std.Io.Clock.awake.now(init.io).nanoseconds - started;
            try report.print("{{\"case\":\"keys{d}-{s}\",\"iterations\":{d},\"ns_per_record\":{d},\"checksum\":{d},\"output_bytes\":{d}}}\n", .{
                length,                                   if (is_nested) "nested" else "scalar", count,
                @as(f64, @floatFromInt(elapsed)) / count, checksum,                              written,
            });
        }
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, report.buffered());
}
