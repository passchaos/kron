//! Independent old decoder/renderer oracle, not a second call into new code.
const std = @import("std");
const before = @import("before").api;
const after = @import("after").api;
const before_wire = @import("before").wire;
const after_wire = @import("after").wire;

fn compareWire(payload: []const u8) !void {
    const old_header = before.codec.readHeader(payload, before.codec.version) catch return;
    const new_header = try after.codec.readHeader(payload, after.codec.version);
    inline for (.{ "json", "text", "logfmt" }) |name| {
        comparison: {
            var old_bytes: [65536]u8 = undefined;
            var new_bytes: [65536]u8 = undefined;
            var old_scratch: [256]before.Field = undefined;
            var new_scratch: [256]after.Field = undefined;
            const old_result = before_wire.render(@field(before_wire.Format, name), payload, old_header, &old_bytes, &old_scratch, null) catch |old_error| {
                _ = after_wire.render(@field(after_wire.Format, name), payload, new_header, &new_bytes, &new_scratch, null) catch |new_error| {
                    if (!std.mem.eql(u8, @errorName(old_error), @errorName(new_error))) return error.DifferentFusedError;
                    break :comparison;
                };
                return error.NewFusedAcceptedInvalid;
            };
            const new_result = after_wire.render(@field(after_wire.Format, name), payload, new_header, &new_bytes, &new_scratch, null) catch return error.NewFusedRejectedValid;
            if (!std.mem.eql(u8, old_result, new_result)) return error.DifferentFusedBytes;
        }
    }
}

fn compare(payload: []const u8) !bool {
    try compareWire(payload);
    var old_scratch: [256]before.Field = undefined;
    var new_scratch: [256]after.Field = undefined;
    const old_event = before.codec.decode(payload, &old_scratch) catch |old_error| {
        _ = after.codec.decode(payload, &new_scratch) catch |new_error| {
            if (!std.mem.eql(u8, @errorName(old_error), @errorName(new_error))) return error.DifferentDecodeError;
            return false;
        };
        return error.NewDecoderAcceptedInvalid;
    };
    const new_event = after.codec.decode(payload, &new_scratch) catch return error.NewDecoderRejectedValid;
    inline for (.{ "json", "text", "logfmt" }) |name| {
        var old_bytes: [65536]u8 = undefined;
        var new_bytes: [65536]u8 = undefined;
        var old_output = std.Io.Writer.fixed(&old_bytes);
        var new_output = std.Io.Writer.fixed(&new_bytes);
        try before.encoder.encode(@field(before.encoder.Format, name), old_event, &old_output);
        try after.encoder.encode(@field(after.encoder.Format, name), new_event, &new_output);
        if (!std.mem.eql(u8, old_output.buffered(), new_output.buffered())) return error.DifferentRecordBytes;
    }
    return true;
}

pub fn main(init: std.process.Init) !void {
    const entries = [_]before.Field{
        before.kv("signed", std.math.minInt(i128)),                       before.kv("unsigned", std.math.maxInt(u128)),
        before.kv("boolean", true),                                       before.kv("float", 1.25),
        before.kv("nan", std.math.nan(f64)),                              before.kv("neg_inf", -std.math.inf(f64)),
        before.kv("zero", @as(f64, -0.0)),                                before.kv("string", "quote\"\n\xff"),
        before.kv("bytes", before.bytes(&.{ 0, 1, 0xff })),               before.kv("duration", before.durationNs(std.math.minInt(i64))),
        before.kv("timestamp", before.timestampNs(std.math.maxInt(i64))), before.kv("null", null),
    };
    const nested = [_]before.Field{
        before.kv("array", before.array(&.{ .null_value, .{ .boolean = false }, .{ .unsigned = 1 } })),
        before.kv("group", before.group(&.{ before.kv("a", -1), before.kv("b", "\xe4\xb8\xad") })),
    };
    var leaves: [255]before.Value = undefined;
    for (&leaves, 0..) |*value, index| value.* = .{ .signed = @as(i128, @intCast(index)) - 127 };
    const maximal = [_]before.Field{before.kv("maximal", before.array(&leaves))};
    var rng = std.Random.DefaultPrng.init(0x7769726576697369);
    var comparisons: usize = 0;
    var valid: usize = 0;
    for ([_][]const before.Field{ &entries, &nested, &maximal }) |fields| {
        var payload_bytes: [16384]u8 = undefined;
        const payload = try before.codec.encode(.{ .level = .warn, .scope = "wire.differential", .message = "unchanged", .fields = fields, .timestamp_ns = -1, .session = 7, .sequence = 9, .channel = 3, .route_mask = 1, .config_generation = 1, .route_generation = 1, .route_fingerprint = 0x1234, .trace_id = @splat(1), .span_id = @splat(2), .source = .{ .module = "app", .file = "src/net/worker.zig", .fn_name = "serve", .line = 42, .column = 7 } }, &payload_bytes);
        _ = try compare(payload);
        for (0..payload.len) |length| {
            _ = try compare(payload[0..length]);
            comparisons += 1;
        }
        for (0..4096) |_| {
            var changed: [16384]u8 = undefined;
            @memcpy(changed[0..payload.len], payload);
            const index = rng.random().uintLessThan(usize, payload.len);
            changed[index] ^= @as(u8, 1) << rng.random().int(u3);
            if (try compare(changed[0..payload.len])) valid += 1;
            comparisons += 1;
        }
    }
    var output_bytes: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_bytes);
    try std.json.Stringify.value(.{ .comparisons = comparisons, .valid_mutations_with_three_equal_formats = valid, .independent_before = true }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
