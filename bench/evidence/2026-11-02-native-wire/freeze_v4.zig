//! Run only against the archived pre-upgrade module; output is a wire fixture.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedFixture;
    const scalar = [_]kron.Field{
        kron.kv("zero", @as(u64, 0)),         kron.kv("safe", @as(u64, 9007199254740991)),
        kron.kv("max", std.math.maxInt(u64)), kron.kv("min", std.math.minInt(i64)),
        kron.kv("negative", @as(i64, -7)),
    };
    const wide = [_]kron.Field{ kron.kv("unsigned", std.math.maxInt(u128)), kron.kv("signed", std.math.minInt(i128)) };
    const nested = [_]kron.Field{ kron.kv("group", kron.group(&scalar)), kron.kv("array", kron.array(&.{ .{ .unsigned = 42 }, .{ .signed = -7 }, .null_value })) };
    const arguments = [_]kron.Field{ kron.kv("0", @as(u64, 42)), kron.kv("1", @as(i64, -7)) };
    var event: kron.Event = .{
        .level = .info,
        .scope = "v4.fixture",
        .message = "frozen event",
        .fields = &scalar,
        .timestamp_ns = -123,
        .session = 9,
        .sequence = 10,
        .channel = 3,
        .route_mask = 1,
        .config_generation = 2,
        .route_fingerprint = 17,
        .route_generation = 4,
        .trace_id = @splat(0xab),
        .span_id = @splat(0xcd),
        .trace_flags = 1,
        .source = .{ .module = "fixture", .file = "fixture.zig", .fn_name = "frozen", .line = 42, .column = 9 },
    };
    const schema_output = std.mem.startsWith(u8, args[1], "schema-");
    if (std.mem.eql(u8, args[1], "wide")) event.fields = &wide else if (std.mem.eql(u8, args[1], "nested")) event.fields = &nested else if (std.mem.eql(u8, args[1], "deferred")) {
        event.message = "{d} {d}";
        event.message_template = true;
        event.format_args = &arguments;
    } else if (!std.mem.eql(u8, args[1], "scalar") and !schema_output) return error.InvalidFixture;
    var bytes: [4096]u8 = undefined;
    if (schema_output) {
        var region: [1088]u8 align(64) = @splat(0);
        var registry = try kron.schema.Registry.init(init.gpa, init.io, &region, try kron.schema.layout(4096, 1, 1024));
        defer registry.deinit();
        var fields: [5]kron.schema.FieldSchema = undefined;
        var arguments_meta: [2]kron.schema.FieldSchema = undefined;
        const metadata = try kron.schema_codec.eventMetadata(event, &fields, &arguments_meta);
        const definition = try registry.resolve((try registry.register(metadata)).ref);
        if (std.mem.eql(u8, args[1], "schema-definition")) {
            try std.Io.File.stdout().writeStreamingAll(init.io, &region);
        } else if (std.mem.eql(u8, args[1], "schema-reference")) {
            try std.Io.File.stdout().writeStreamingAll(init.io, try kron.schema_codec.encodeReference(event, definition, &bytes));
        } else return error.InvalidFixture;
        return;
    }
    const payload = try kron.codec.encode(event, &bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, payload);
}
