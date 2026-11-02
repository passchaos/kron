//! Consumer-only fused render probe. Payload setup and oracle are outside timing.
const std = @import("std");
const module = @import("kron");
const kron = module.api;
const wire = module.wire;

pub fn main(init: std.process.Init) !void {
    var fields: [64]kron.Field = undefined;
    var names: [64][16]u8 = undefined;
    for (&fields, 0..) |*entry, index| {
        const name = try std.fmt.bufPrint(&names[index], "field{d}", .{index});
        entry.* = kron.kv(name, @as(u64, index + 123));
    }
    const nested = [_]kron.Field{
        kron.kv("one", kron.group(fields[0..5])),
        kron.kv("two", kron.group(fields[5..10])),
        kron.kv("three", kron.array(&.{ .null_value, .{ .boolean = true }, .{ .unsigned = 123 } })),
    };
    var leaves: [255]kron.Value = undefined;
    for (&leaves, 0..) |*leaf, index| leaf.* = .{ .signed = @as(i128, @intCast(index)) - 127 };
    const maximal = [_]kron.Field{kron.kv("maximal", kron.array(&leaves))};
    const cases = [_][]const kron.Field{ fields[0..5], &fields, &nested, &maximal };
    var payload_bytes: [16384]u8 = undefined;
    var output_bytes: [32768]u8 = undefined;
    var reference_bytes: [32768]u8 = undefined;
    var scratch: [kron.codec.decode_scratch_fields]kron.Field = undefined;
    var reference_scratch: [kron.codec.decode_scratch_fields]kron.Field = undefined;
    var report_bytes: [4096]u8 = undefined;
    var report = std.Io.File.stdout().writerStreaming(init.io, &report_bytes);
    for (cases, 0..) |entries, case| {
        const payload = try kron.codec.encode(.{
            .level = .info,
            .scope = "reference.app",
            .message = "unchanged",
            .timestamp_ns = 1793462400000000000,
            .session = std.math.maxInt(u64),
            .sequence = 123456,
            .channel = 1,
            .route_mask = 1,
            .config_generation = 1,
            .fields = entries,
        }, &payload_bytes);
        const header = try kron.codec.readHeader(payload, kron.codec.version);
        const decoded = try kron.codec.decode(payload, &reference_scratch);
        inline for (.{ "json", "text", "logfmt" }) |format| {
            var expected = std.Io.Writer.fixed(&reference_bytes);
            try kron.encoder.encode(@field(kron.encoder.Format, format), decoded, &expected);
            const rendered = try wire.render(@field(wire.Format, format), payload, header, &output_bytes, &scratch, null);
            try std.testing.expectEqualSlices(u8, expected.buffered(), rendered);
            for (0..5) |repetition| {
                var checksum: u64 = 0;
                var bytes: u64 = 0;
                const iterations = 10000;
                const start = std.Io.Clock.awake.now(init.io);
                for (0..iterations) |iteration| {
                    const result = try wire.render(@field(wire.Format, format), payload, header, &output_bytes, &scratch, null);
                    checksum +%= std.hash.Wyhash.hash(iteration, result);
                    bytes += result.len;
                    std.mem.doNotOptimizeAway(result);
                }
                const elapsed = start.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds();
                try std.json.Stringify.value(.{
                    .benchmark = "fused-render",
                    .case = case,
                    .format = format,
                    .iterations = iterations,
                    .repetition = repetition,
                    .ns_per_record = @as(f64, @floatFromInt(elapsed)) / iterations,
                    .checksum = checksum,
                    .output_bytes = bytes,
                    .payload_bytes = payload.len,
                    .scope = "Fused consumer rendering only, output Wyhash included; not logging throughput",
                }, .{}, &report.interface);
                try report.interface.writeByte('\n');
            }
        }
    }
    try report.interface.flush();
}
