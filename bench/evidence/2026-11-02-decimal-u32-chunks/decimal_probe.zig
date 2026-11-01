//! Primitive output probe. Full bytes match std before/after timing; each
//! timed batch exposes its complete buffer without per-value clock/hash work.
const std = @import("std");
const decimal = @import("decimal");
const Case = enum { small, record, full, signed, wide };

fn measure(comptime T: type, values: []const T, io: std.Io, repetitions: usize) !struct { ns: i96, bytes: usize, checksum: u64 } {
    var actual_bytes: [4096 * 40]u8 = undefined;
    var expected_bytes: [4096 * 40]u8 = undefined;
    var actual = std.Io.Writer.fixed(&actual_bytes);
    var expected = std.Io.Writer.fixed(&expected_bytes);
    for (values) |value| {
        try decimal.write(&actual, value);
        try expected.print("{d}", .{value});
    }
    if (!std.mem.eql(u8, expected.buffered(), actual.buffered())) return error.DifferentOutput;
    const start = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..repetitions) |_| {
        actual.end = 0;
        for (values) |value| try decimal.write(&actual, value);
        std.mem.doNotOptimizeAway(actual.buffered());
    }
    const elapsed = std.Io.Clock.awake.now(io).nanoseconds - start;
    if (!std.mem.eql(u8, expected.buffered(), actual.buffered())) return error.DifferentTimedOutput;
    return .{ .ns = elapsed, .bytes = actual.end, .checksum = std.hash.Wyhash.hash(0, actual.buffered()) };
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.ExpectedCaseRepetitions;
    const kind = std.meta.stringToEnum(Case, args[1]) orelse return error.InvalidCase;
    const repetitions = try std.fmt.parseInt(usize, args[2], 10);
    if (repetitions < 100 or repetitions > 10000) return error.InvalidRepetitions;
    var rng = std.Random.DefaultPrng.init(0x646563696d616c32);
    var native: [4096]u64 = undefined;
    var signed: [4096]i64 = undefined;
    var wide: [4096]u128 = undefined;
    for (&native, &signed, &wide, 0..) |*value, *negative, *large, index| {
        value.* = switch (kind) {
            .small => index * 239 % 1000000,
            .record => switch (index % 6) {
                0 => 1_800_000_000_000_000_000 + index * 79,
                1 => 0x0123456789abcdef,
                2 => index,
                3 => 7,
                4 => 42,
                else => index * 131,
            },
            else => rng.random().int(u64),
        };
        negative.* = @bitCast(value.*);
        large.* = @as(u128, value.*) << 64 | rng.random().int(u64);
    }
    const result = switch (kind) {
        .signed => try measure(i64, &signed, init.io, repetitions),
        .wide => try measure(u128, &wide, init.io, repetitions),
        else => try measure(u64, &native, init.io, repetitions),
    };
    var output_bytes: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_bytes);
    try std.json.Stringify.value(.{ .case = @tagName(kind), .repetitions = repetitions, .values = native.len,
        .elapsed_ns = result.ns, .bytes_per_batch = result.bytes, .checksum = result.checksum,
        .ns_per_value = @as(f64, @floatFromInt(result.ns)) / @as(f64, @floatFromInt(repetitions * native.len)),
        .output_verified = true, .optimize = @tagName(@import("builtin").mode) }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
