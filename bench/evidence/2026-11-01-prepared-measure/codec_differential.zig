//! Compare two independently compiled library snapshots on generated payloads/errors.
const std = @import("std");
const baseline = @import("baseline");
const candidate = @import("kron");

const Outcome = struct {
    err: ?anyerror = null,
    length: usize = 0,
    checksum: u64 = 0,
    untouched: bool = false,
};

fn exercise(comptime lib: type, allocator: std.mem.Allocator, io: std.Io, iteration: usize, output: []u8) !Outcome {
    const version: usize = iteration % 12;
    var values = [_]lib.Value{
        .null_value,
        .{ .boolean = iteration % 2 == 0 },
        .{ .unsigned = @as(u128, iteration) << 64 | iteration },
        .{ .signed = -@as(i128, @intCast(iteration)) - 1 },
        .{ .float = @bitCast(@as(u64, 0x7ff8000000000000) | iteration) },
        .{ .string = "雪\n\xff\x00" },
        .{ .bytes = "\x00\xff" },
        .{ .duration_ns = -123 },
        .{ .timestamp_ns = 1234567890 },
    };
    var cycle: [1]lib.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    var fields = [_]lib.Field{
        lib.kv("nested", lib.group(&.{lib.kv("values", lib.array(&values))})),
        lib.kv("scalar", @as(u64, iteration)),
    };
    var arguments = [_]lib.Field{lib.kv("", @as(u64, iteration))};
    var event: lib.Event = .{
        .level = .info,
        .scope = "differential",
        .timestamp_ns = -123,
        .message = "value {d}",
        .message_template = true,
        .fields = &fields,
        .format_args = &arguments,
        .source = @src(),
        .trace_id = @splat(0xab),
        .span_id = @splat(0xcd),
        .sequence = 17,
        .session = std.math.maxInt(u64),
        .channel = 3,
        .route_mask = 1,
    };
    var region: [4160]u8 align(64) = @splat(0);
    var registry = try lib.schema.Registry.init(allocator, io, &region, try lib.schema.layout(4096, 1, 4096));
    defer registry.deinit();
    var field_metadata: [2]lib.schema.FieldSchema = undefined;
    var arg_metadata: [1]lib.schema.FieldSchema = undefined;
    var definition = try registry.resolve((try registry.register(try lib.schema_codec.eventMetadata(event, &field_metadata, &arg_metadata))).ref);
    switch (version) {
        0 => {},
        1 => fields[0].key = "wrong",
        2 => arguments[0].key = "wrong",
        3 => fields[1].value = .{ .boolean = true },
        4 => {
            fields[0].key = "wrong";
            fields[1].value = .{ .array = &cycle };
        },
        5 => {
            fields[1].key = fields[0].key;
        },
        6 => {
            event.scope = "wrong";
            definition.fields_wire = &.{};
        },
        7 => {
            definition.fields_wire = &.{};
        },
        8 => {
            event.level = .off;
        },
        9 => {
            event.level = .off;
            fields[1].value = .{ .boolean = true };
        },
        10 => {
            event.fields = fields[0..1];
        },
        11 => {
            definition.arguments_wire = &.{};
            arguments[0].value = .{ .array = &cycle };
        },
        else => unreachable,
    }
    @memset(output, 0xac);
    const limit = if (iteration % 3 == 0) output.len else iteration % output.len;
    const result = lib.schema_codec.encodeReference(event, definition, output[0..limit]);
    if (result) |bytes| {
        return .{ .length = bytes.len, .checksum = std.hash.Wyhash.hash(0, bytes) };
    } else |err| {
        return .{ .err = err, .untouched = std.mem.allEqual(u8, output, 0xac) };
    }
}

pub fn main(init: std.process.Init) !void {
    var before: [2048]u8 = undefined;
    var after: [2048]u8 = undefined;
    var successes: usize = 0;
    var failures: usize = 0;
    for (0..4096) |iteration| {
        const old = try exercise(baseline, init.gpa, init.io, iteration, &before);
        const new = try exercise(candidate, init.gpa, init.io, iteration, &after);
        if (!std.meta.eql(old, new)) return error.DifferentialMismatch;
        if (old.err != null) {
            if (!old.untouched or !new.untouched) return error.RejectedOutputChanged;
            failures += 1;
        } else {
            if (!std.mem.eql(u8, before[0..old.length], after[0..new.length])) return error.OutputMismatch;
            successes += 1;
        }
    }
    if (successes == 0 or failures == 0) return error.MissingCoverage;
    std.debug.print("reference differential:4096 outcomes, success={d}, rejected={d}, exact errors/bytes/untouched rejected buffers matched\n", .{ successes, failures });
}
