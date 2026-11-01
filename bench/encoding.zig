//! Batch encoding microbenchmark through public APIs. Every measured call uses
//! the same shape with slightly changing scalar values. No heap allocation or
//! per-call clock read occurs in any measured batch. Full output is consumed by
//! Wyhash inside encode/archive timing, so that consumer cost is explicit.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");

pub const Options = struct {
    iterations: usize = 10000,
    repetitions: usize = 5,
    label: []const u8 = "unspecified",
    source_hash: []const u8 = "unspecified",
};

pub fn parseOptions(args: []const []const u8) !Options {
    var options: Options = .{};
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--iterations=")) {
            options.iterations = std.fmt.parseInt(usize, arg[13..], 10) catch return error.InvalidIterations;
        } else if (std.mem.startsWith(u8, arg, "--repetitions=")) {
            options.repetitions = std.fmt.parseInt(usize, arg[14..], 10) catch return error.InvalidRepetitions;
        } else if (std.mem.startsWith(u8, arg, "--label=")) {
            options.label = arg[8..];
        } else if (std.mem.startsWith(u8, arg, "--source-hash=")) {
            options.source_hash = arg[14..];
        } else return error.UnknownArgument;
    }
    if (options.iterations == 0 or options.iterations > 10000) return error.InvalidIterations;
    if (options.repetitions < 5 or options.repetitions > 9) return error.InvalidRepetitions;
    return options;
}

const Case = enum { flat5typednumbers, nested_depth2_array_group, max256nodes };
const Operation = enum { size_only, value_size_only, encode, binary_archive, reference_size_only, reference_encode };
const buffer_budget = 16 * 1024;

/// Initialize in its final address. Every aggregate descriptor points to these
/// owned arrays, never to by-value temporary copies or fabricated pointers.
const Fixture = struct {
    kind: Case,
    flat: [5]kron.Field,
    leaves: [255]kron.Value,
    nested: [2]kron.Field,
    attributes: [2]kron.Field,

    fn init(self: *Fixture, kind: Case) void {
        self.kind = kind;
        self.flat = .{
            kron.kv("signed", @as(i64, -123)),
            kron.kv("unsigned", @as(u64, 456)),
            kron.kv("ratio", @as(f64, 1.25)),
            kron.kv("duration", kron.durationNs(789)),
            kron.kv("timestamp", kron.timestampNs(123456789)),
        };
        for (&self.leaves, 0..) |*leaf, index| leaf.* = .{ .signed = @as(i128, @intCast(index)) - 127 };
        self.nested = .{
            kron.kv("items", kron.Value{ .array = self.leaves[0..4] }),
            kron.kv("latency", kron.durationNs(789)),
        };
        self.attributes = .{
            kron.kv("group", kron.Value{ .group = &self.nested }),
            kron.kv("status", @as(u16, 200)),
        };
        if (kind == .max256nodes) self.attributes[0] = kron.kv("values", kron.Value{ .array = &self.leaves });
    }

    fn update(self: *Fixture, iteration: usize) void {
        const delta: i128 = @intCast(iteration % 17);
        self.flat[0].value = .{ .signed = -123 - delta };
        self.flat[1].value = .{ .unsigned = 456 + @as(u128, @intCast(delta)) };
        self.flat[2].value = .{ .float = 1.25 + @as(f64, @floatFromInt(delta)) / 32 };
        self.flat[3].value = .{ .duration_ns = 789 + @as(i64, @intCast(delta)) };
        self.flat[4].value = .{ .timestamp_ns = 123456789 + @as(i64, @intCast(delta)) };
        self.leaves[0] = .{ .signed = -127 - delta };
        self.nested[1].value = .{ .duration_ns = 789 + @as(i64, @intCast(delta)) };
        self.attributes[1].value = .{ .unsigned = 200 + @as(u128, @intCast(delta)) };
    }

    fn event(self: *const Fixture, iteration: usize) kron.Event {
        return .{
            .level = .info,
            .scope = "bench.encoding",
            .message = "typed capture",
            .fields = switch (self.kind) {
                .flat5typednumbers => &self.flat,
                .nested_depth2_array_group => &self.attributes,
                .max256nodes => self.attributes[0..1],
            },
            .timestamp_ns = 123456789,
            .session = 1,
            .sequence = @intCast(iteration + 1),
            .channel = 1,
        };
    }

    fn nodes(self: *const Fixture) usize {
        return switch (self.kind) {
            .flat5typednumbers => 5,
            .nested_depth2_array_group => 8,
            .max256nodes => 256,
        };
    }

    fn depth(self: *const Fixture) usize {
        return switch (self.kind) {
            .flat5typednumbers => 0,
            .nested_depth2_array_group => 2,
            .max256nodes => 1,
        };
    }
};

const Sample = struct { elapsed_ns: u64, checksum: u64, output_bytes: u64 };

fn batch(io: std.Io, fixture: *Fixture, definition: kron.schema_codec.Definition, operation: Operation, iterations: usize, buffer: []u8) !Sample {
    var checksum: u64 = 0;
    var output_bytes: u64 = 0;
    const started = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..iterations) |iteration| {
        fixture.update(iteration);
        const captured = fixture.event(iteration);
        switch (operation) {
            .size_only => {
                const size = try kron.codec.encodedSize(captured);
                std.mem.doNotOptimizeAway(size);
                checksum +%= size;
            },
            .value_size_only => {
                var size: usize = 0;
                for (captured.fields) |field| size += try kron.codec.encodedValueSize(field.value);
                std.mem.doNotOptimizeAway(size);
                checksum +%= size;
            },
            .encode => {
                const payload = try kron.codec.encode(captured, buffer);
                std.mem.doNotOptimizeAway(payload);
                checksum +%= std.hash.Wyhash.hash(@intCast(iteration), payload);
                output_bytes += payload.len;
            },
            .binary_archive => {
                var writer = std.Io.Writer.fixed(buffer);
                try kron.encoder.binary.encode(captured, &writer);
                const bytes = writer.buffered();
                std.mem.doNotOptimizeAway(bytes);
                checksum +%= std.hash.Wyhash.hash(@intCast(iteration), bytes);
                output_bytes += bytes.len;
            },
            .reference_size_only => {
                const size = try kron.schema_codec.encodedReferenceSize(captured, definition);
                std.mem.doNotOptimizeAway(size);
                checksum +%= size;
            },
            .reference_encode => {
                const payload = try kron.schema_codec.encodeReference(captured, definition, buffer);
                std.mem.doNotOptimizeAway(payload);
                checksum +%= std.hash.Wyhash.hash(@intCast(iteration), payload);
                output_bytes += payload.len;
            },
        }
    }
    const elapsed = std.Io.Clock.awake.now(io).nanoseconds - started;
    std.mem.doNotOptimizeAway(checksum);
    return .{ .elapsed_ns = @intCast(@max(0, elapsed)), .checksum = checksum, .output_bytes = output_bytes };
}

fn referenceDefinition(fixture: *Fixture, registry: *kron.schema.Registry) !kron.schema_codec.Definition {
    var fields: [5]kron.schema.FieldSchema = undefined;
    const metadata = try kron.schema_codec.eventMetadata(fixture.event(0), &fields, &.{});
    return registry.resolve((try registry.register(metadata)).ref);
}

fn verifyReference(fixture: *Fixture, definition: kron.schema_codec.Definition, buffer: []u8) !usize {
    fixture.update(0);
    const captured = fixture.event(0);
    const payload = try kron.schema_codec.encodeReference(captured, definition, buffer);
    if (payload.len != try kron.schema_codec.encodedReferenceSize(captured, definition)) return error.InvalidReferenceSize;
    var scratch: [256]kron.Field = undefined;
    const restored = try kron.schema_codec.resolve(payload, definition, &scratch);
    var expected_bytes: [buffer_budget]u8 = undefined;
    var restored_bytes: [buffer_budget]u8 = undefined;
    const expected = try kron.codec.encode(captured, &expected_bytes);
    const materialized = try kron.codec.encode(restored, &restored_bytes);
    if (!std.mem.eql(u8, expected, materialized)) return error.InvalidReferenceRoundtrip;
    return payload.len;
}

fn verifyFixture(fixture: *Fixture, buffer: []u8) !struct { payload: usize, archive: usize, values: usize } {
    fixture.update(0);
    const captured = fixture.event(0);
    const payload = try kron.codec.encode(captured, buffer);
    const size = try kron.codec.encodedSize(captured);
    if (payload.len != size) return error.InvalidPayloadSize;
    var scratch: [256]kron.Field = undefined;
    const decoded = try kron.codec.decode(payload, &scratch);
    if (decoded.fields.len != captured.fields.len or decoded.sequence != captured.sequence or !std.mem.eql(u8, decoded.message, captured.message)) return error.InvalidRoundtrip;
    var validator: kron.fields.ValueValidator = .{};
    try validator.fields(decoded.fields);
    if (validator.nodes != fixture.nodes()) return error.InvalidNodeCount;
    var values: usize = 0;
    for (captured.fields) |field| values += try kron.codec.encodedValueSize(field.value);
    var writer = std.Io.Writer.fixed(buffer);
    try kron.encoder.binary.encode(captured, &writer);
    const frame = try kron.encoder.binary.format.validate(writer.buffered());
    if (frame.payload_len != size or frame.crc32 != kron.encoder.binary.format.frameCRC(writer.buffered()[24..])) return error.InvalidArchive;
    const restored = try kron.codec.decode(writer.buffered()[24..], &scratch);
    if (restored.fields.len != captured.fields.len) return error.InvalidArchiveRoundtrip;
    return .{ .payload = size, .archive = writer.end, .values = values };
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = try parseOptions(args[1..]);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const writer = &output.interface;
    const cpu_info = std.Io.Dir.cwd().readFileAlloc(init.io, "/proc/cpuinfo", init.gpa, .limited(128 * 1024)) catch null;
    defer if (cpu_info) |bytes| init.gpa.free(bytes);
    var cpu_name: []const u8 = builtin.cpu.model.name;
    if (cpu_info) |bytes| {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| if (std.mem.startsWith(u8, line, "model name")) {
            if (std.mem.findScalar(u8, line, ':')) |colon| cpu_name = std.mem.trim(u8, line[colon + 1 ..], " \t");
            break;
        };
    }
    var fixture: Fixture = undefined;
    var buffer: [buffer_budget]u8 = undefined;
    var schema_region: [3 * 1088]u8 align(64) = @splat(0);
    var registry = try kron.schema.Registry.init(init.gpa, init.io, &schema_region, try kron.schema.layout(4096, 3, 1024));
    defer registry.deinit();
    for (std.enums.values(Case)) |kind| {
        fixture.init(kind);
        const verified = try verifyFixture(&fixture, &buffer);
        const definition = try referenceDefinition(&fixture, &registry);
        const reference_size = try verifyReference(&fixture, definition, &buffer);
        for (std.enums.values(Operation)) |operation| {
            _ = try batch(init.io, &fixture, definition, operation, @min(options.iterations, 100), &buffer);
            for (0..options.repetitions) |repetition| {
                const sample = try batch(init.io, &fixture, definition, operation, options.iterations, &buffer);
                try writer.writeAll("{\"benchmark\":\"encoding\",\"case\":");
                try std.json.Stringify.value(@tagName(kind), .{}, writer);
                try writer.writeAll(",\"operation\":");
                try std.json.Stringify.value(@tagName(operation), .{}, writer);
                try writer.print(",\"repetition\":{d},\"iterations\":{d},\"elapsed_ns\":{d},\"ns_per_call\":{d},\"numfields\":{d},\"nodes\":{d},\"container_depth\":{d},\"max_nodes\":256,\"max_depth\":8,\"buffer_budget\":{d},\"payload_bytes\":{d},\"archive_bytes\":{d},\"value_bytes\":{d},\"output_bytes\":{d},\"checksum\":{d},\"clock_pairs\":1,\"clock\":\"std.Io.Clock.awake\",\"heap_allocations_in_batch\":0,\"consume\":\"full-output Wyhash inside encode/archive batch\",\"cpu\":", .{
                    repetition, options.iterations, sample.elapsed_ns, @as(f64, @floatFromInt(sample.elapsed_ns)) / @as(f64, @floatFromInt(options.iterations)), fixture.event(0).fields.len, fixture.nodes(), fixture.depth(), buffer_budget, verified.payload, verified.archive, verified.values, sample.output_bytes, sample.checksum,
                });
                try std.json.Stringify.value(cpu_name, .{}, writer);
                try writer.print(",\"reference_bytes\":{d}", .{reference_size});
                try writer.writeAll(",\"arch\":");
                try std.json.Stringify.value(@tagName(builtin.cpu.arch), .{}, writer);
                try writer.writeAll(",\"build\":");
                try std.json.Stringify.value(@tagName(builtin.mode), .{}, writer);
                try writer.writeAll(",\"zig\":");
                try std.json.Stringify.value(builtin.zig_version_string, .{}, writer);
                try writer.writeAll(",\"label\":");
                try std.json.Stringify.value(options.label, .{}, writer);
                try writer.writeAll(",\"source_hash\":");
                try std.json.Stringify.value(options.source_hash, .{}, writer);
                try writer.writeAll("}\n");
            }
        }
    }
    try writer.flush();
}

test "encoding benchmark bounds repetitions iterations and validates all shapes" {
    try std.testing.expectEqual(@as(usize, 10000), (try parseOptions(&.{})).iterations);
    try std.testing.expectError(error.InvalidIterations, parseOptions(&.{"--iterations=10001"}));
    try std.testing.expectError(error.InvalidIterations, parseOptions(&.{"--iterations=0"}));
    try std.testing.expectError(error.InvalidRepetitions, parseOptions(&.{"--repetitions=4"}));
    try std.testing.expectError(error.InvalidRepetitions, parseOptions(&.{"--repetitions=10"}));
    try std.testing.expectError(error.UnknownArgument, parseOptions(&.{"--other=1"}));
    var fixture: Fixture = undefined;
    var buffer: [buffer_budget]u8 = undefined;
    var schema_region: [3 * 1088]u8 align(64) = @splat(0);
    var registry = try kron.schema.Registry.init(std.testing.allocator, std.testing.io, &schema_region, try kron.schema.layout(4096, 3, 1024));
    defer registry.deinit();
    for (std.enums.values(Case)) |kind| {
        fixture.init(kind);
        _ = try verifyFixture(&fixture, &buffer);
        _ = try verifyReference(&fixture, try referenceDefinition(&fixture, &registry), &buffer);
    }
}
