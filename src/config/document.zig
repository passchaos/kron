//! Bounded JSON application configuration. Parsing owns every string and rule;
//! override/merge only borrow that storage and allocate nothing. A Document has
//! one owner: call deinit exactly once after the runtime copies its override.
const std = @import("std");
const sources = @import("sources.zig");
const filter = @import("filter.zig");
const redact = @import("../pipeline/redact.zig");
const sampling = @import("../pipeline/sampler.zig");
const predicate = @import("../pipeline/predicate.zig");

pub const max_document_bytes: usize = 16 * 1024;
pub const max_json_depth: usize = 16;
pub const maxDocumentBytes = max_document_bytes;
pub const maxJsonDepth = max_json_depth;
pub const ParseError = std.json.ParseError(std.json.Scanner) || filter.ParseError || redact.InitError || sampling.InitError || predicate.CompileError || error{
    DocumentTooLarge,
    JsonTooDeep,
    InvalidDocument,
    InvalidType,
    UnknownField,
    MissingField,
    DuplicateKey,
    InvalidSamplingKind,
    InvalidRedactionAction,
    InvalidNumber,
    NumericOverflow,
};

pub const Document = struct {
    parsed: std.json.Parsed(std.json.Value),
    values: sources.Override,

    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Document {
        try checkDocumentBudget(bytes);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{
            .allocate = .alloc_always,
            .duplicate_field_behavior = .@"error",
            .max_value_len = max_document_bytes,
            // Keep integers as exact text. In particular u64 values must never
            // round through float when they exceed JSON Value.integer's i64.
            .parse_numbers = false,
        });
        errdefer parsed.deinit();
        const values = try parseOverride(parsed.arena.allocator(), parsed.value);
        return .{ .parsed = parsed, .values = values };
    }

    /// Every slice remains valid until this Document is deinitialized. Copying
    /// the returned Override grants no ownership of its strings or rule array.
    pub fn override(self: *const Document) sources.Override {
        return self.values;
    }

    pub fn deinit(self: *Document) void {
        self.parsed.deinit();
        self.* = undefined;
    }
};

/// String-aware preflight rejects resource limits before the JSON parser can
/// allocate. JSON grammar, escape validity and UTF-8 remain the parser's job.
fn checkDocumentBudget(bytes: []const u8) error{ DocumentTooLarge, JsonTooDeep, InvalidDocument }!void {
    if (bytes.len > max_document_bytes) return error.DocumentTooLarge;
    var stack: [max_json_depth]u8 = undefined;
    var depth: usize = 0;
    var in_string = false;
    var escaped = false;
    for (bytes) |byte| {
        if (in_string) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
            continue;
        }
        switch (byte) {
            '"' => in_string = true,
            '{', '[' => {
                if (depth == max_json_depth) return error.JsonTooDeep;
                stack[depth] = byte;
                depth += 1;
            },
            '}', ']' => {
                if (depth == 0) return error.InvalidDocument;
                depth -= 1;
                if ((byte == '}' and stack[depth] != '{') or (byte == ']' and stack[depth] != '[')) return error.InvalidDocument;
            },
            else => {},
        }
    }
    if (in_string or depth != 0) return error.InvalidDocument;
}

fn asObject(value: std.json.Value) error{InvalidType}!std.json.ObjectMap {
    return if (value == .object) value.object else error.InvalidType;
}

fn asString(value: std.json.Value) error{InvalidType}![]const u8 {
    return if (value == .string) value.string else error.InvalidType;
}

fn required(object: std.json.ObjectMap, key: []const u8) error{MissingField}!std.json.Value {
    return object.get(key) orelse error.MissingField;
}

fn allowedKeys(object: std.json.ObjectMap, comptime keys: []const []const u8) error{UnknownField}!void {
    for (object.keys()) |key| {
        var known = false;
        inline for (keys) |allowed| {
            if (std.mem.eql(u8, key, allowed)) known = true;
        }
        if (!known) return error.UnknownField;
    }
}

fn parseOverride(allocator: std.mem.Allocator, value: std.json.Value) ParseError!sources.Override {
    const object = try asObject(value);
    try allowedKeys(object, &.{ "filter", "redaction", "sampling", "sample_bypass", "predicate" });
    var result: sources.Override = .{};
    if (object.get("filter")) |entry| {
        const spec = try asString(entry);
        _ = try filter.Filter.parse(spec);
        result.filter_spec = spec;
    }
    if (object.get("redaction")) |entry| result.redaction = try parseRedaction(allocator, entry);
    if (object.get("sampling")) |entry| result.sampling = try parseSampling(entry);
    if (object.get("sample_bypass")) |entry| result.sample_bypass = try sources.Level.parse(try asString(entry));
    if (object.get("predicate")) |entry| {
        if (entry == .null) {
            result.predicate = .clear;
        } else {
            const spec = try asString(entry);
            _ = try predicate.Predicate.parse(spec);
            result.predicate = .{ .expression = spec };
        }
    }
    return result;
}

fn parseRedaction(allocator: std.mem.Allocator, value: std.json.Value) ParseError![]const sources.Rule {
    if (value != .array) return error.InvalidType;
    const entries = value.array.items;
    if (entries.len > redact.max_rules) return error.TooManyRules;
    const rules = try allocator.alloc(sources.Rule, entries.len);
    for (entries, 0..) |entry, i| {
        const object = try asObject(entry);
        try allowedKeys(object, &.{ "key", "action" });
        const key = try asString(try required(object, "key"));
        if (key.len == 0) return error.EmptyKey;
        for (rules[0..i]) |previous| if (std.mem.eql(u8, previous.key, key)) return error.DuplicateKey;
        const action = try asString(try required(object, "action"));
        rules[i] = .{
            .key = key,
            .action = if (std.mem.eql(u8, action, "mask")) .mask else if (std.mem.eql(u8, action, "drop")) .drop else return error.InvalidRedactionAction,
        };
    }
    _ = try redact.Redactor.init(rules);
    return rules;
}

fn parseSampling(value: std.json.Value) ParseError!sampling.Config {
    const object = try asObject(value);
    const kind = try asString(try required(object, "kind"));
    const result: sampling.Config = if (std.mem.eql(u8, kind, "none")) blk: {
        try allowedKeys(object, &.{"kind"});
        break :blk .none;
    } else if (std.mem.eql(u8, kind, "count")) blk: {
        try allowedKeys(object, &.{ "kind", "count" });
        break :blk .{ .count = try unsigned(u64, try required(object, "count")) };
    } else if (std.mem.eql(u8, kind, "every")) blk: {
        try allowedKeys(object, &.{ "kind", "every" });
        break :blk .{ .every = try unsigned(u64, try required(object, "every")) };
    } else if (std.mem.eql(u8, kind, "token_bucket")) blk: {
        try allowedKeys(object, &.{ "kind", "capacity", "refill_interval_ns", "start_ns" });
        break :blk .{ .token_bucket = .{
            .capacity = try unsigned(u32, try required(object, "capacity")),
            .refill_interval_ns = try unsigned(u64, try required(object, "refill_interval_ns")),
            .start_ns = if (object.get("start_ns")) |entry| try unsigned(u64, entry) else 0,
        } };
    } else return error.InvalidSamplingKind;
    _ = try sampling.Sampler.init(result);
    return result;
}

fn unsigned(comptime T: type, value: std.json.Value) error{ InvalidType, InvalidNumber, NumericOverflow }!T {
    if (value != .number_string) return error.InvalidType;
    const text = value.number_string;
    if (text.len == 0) return error.InvalidNumber;
    for (text) |byte| if (byte < '0' or byte > '9') return error.InvalidNumber;
    return std.fmt.parseInt(T, text, 10) catch |err| switch (err) {
        error.Overflow => error.NumericOverflow,
        error.InvalidCharacter => error.InvalidNumber,
    };
}

test "document owns filter predicate rule keys and keeps missing versus explicit values" {
    var bytes = "{\"filter\":\"info,http=trace\",\"redaction\":[{\"key\":\"password\",\"action\":\"mask\"}],\"sampling\":{\"kind\":\"count\",\"count\":7},\"sample_bypass\":\"error\",\"predicate\":\"exists(status)\"}".*;
    var document = try Document.parse(std.testing.allocator, &bytes);
    defer document.deinit();
    @memset(&bytes, 'x');
    const override = document.override();
    try std.testing.expectEqualStrings("info,http=trace", override.filter_spec.?);
    try std.testing.expectEqualStrings("password", override.redaction.?[0].key);
    try std.testing.expectEqual(redact.Action.mask, override.redaction.?[0].action);
    try std.testing.expectEqualDeep(sampling.Config{ .count = 7 }, override.sampling.?);
    try std.testing.expectEqual(sources.Level.err, override.sample_bypass.?);
    try std.testing.expectEqualStrings("exists(status)", override.predicate.expression);

    var missing = try Document.parse(std.testing.allocator, "{}");
    defer missing.deinit();
    const inherited = missing.override();
    try std.testing.expect(inherited.filter_spec == null and inherited.redaction == null and inherited.sampling == null and inherited.sample_bypass == null);
    try std.testing.expect(inherited.predicate == .inherit);
    var clear = try Document.parse(std.testing.allocator, "{\"filter\":\"\",\"redaction\":[],\"sampling\":{\"kind\":\"none\"},\"predicate\":null}");
    defer clear.deinit();
    const config = sources.merge(.{
        .defaults = .{ .filter_spec = "off", .redaction = &.{.{ .key = "secret", .action = .drop }}, .sampling = .{ .every = 2 }, .predicate = "exists(secret)" },
        .file = clear.override(),
    });
    try std.testing.expectEqualStrings("", config.filter_spec);
    try std.testing.expectEqual(@as(usize, 0), config.redaction.len);
    try std.testing.expect(config.sampling == .none);
    try std.testing.expect(config.predicate == null);
}

test "document sampling variants retain exact full width integers and existing policy checks" {
    const cases = [_]struct { json: []const u8, expected: sampling.Config }{
        .{ .json = "{\"sampling\":{\"kind\":\"none\"}}", .expected = .none },
        .{ .json = "{\"sampling\":{\"kind\":\"count\",\"count\":0}}", .expected = .{ .count = 0 } },
        .{ .json = "{\"sampling\":{\"kind\":\"count\",\"count\":18446744073709551615}}", .expected = .{ .count = std.math.maxInt(u64) } },
        .{ .json = "{\"sampling\":{\"kind\":\"every\",\"every\":3}}", .expected = .{ .every = 3 } },
        .{ .json = "{\"sampling\":{\"kind\":\"token_bucket\",\"capacity\":3,\"refill_interval_ns\":10}}", .expected = .{ .token_bucket = .{ .capacity = 3, .refill_interval_ns = 10 } } },
        .{ .json = "{\"sampling\":{\"kind\":\"token_bucket\",\"capacity\":3,\"refill_interval_ns\":10,\"start_ns\":100}}", .expected = .{ .token_bucket = .{ .capacity = 3, .refill_interval_ns = 10, .start_ns = 100 } } },
    };
    for (cases) |case| {
        var document = try Document.parse(std.testing.allocator, case.json);
        defer document.deinit();
        try std.testing.expectEqualDeep(case.expected, document.override().sampling.?);
    }
    var policy = try Document.parse(std.testing.allocator, "{\"filter\":\"warn,db=trace\",\"redaction\":[{\"key\":\"password\",\"action\":\"mask\"},{\"key\":\"token\",\"action\":\"drop\"}],\"sample_bypass\":\"off\",\"predicate\":\"status >= 500 && route =~ \\\"^/api/\\\"\"}");
    defer policy.deinit();
    try std.testing.expectEqual(sources.Level.off, policy.override().sample_bypass.?);
    try std.testing.expectEqual(redact.Action.drop, policy.override().redaction.?[1].action);
}

test "document rejects malformed shape duplicates unknown fields and numeric policy errors" {
    const cases = [_]struct { json: []const u8, expected: anyerror }{
        .{ .json = "[]", .expected = error.InvalidType },
        .{ .json = "{\"unknown\":1}", .expected = error.UnknownField },
        .{ .json = "{\"filter\":\"info\",\"filter\":\"warn\"}", .expected = error.DuplicateField },
        .{ .json = "{\"filt\\u0065r\":\"info\",\"filter\":\"warn\"}", .expected = error.DuplicateField },
        .{ .json = "{\"filter\":false}", .expected = error.InvalidType },
        .{ .json = "{\"filter\":\"verbose\"}", .expected = error.InvalidLevel },
        .{ .json = "{\"sample_bypass\":\"verbose\"}", .expected = error.InvalidLevel },
        .{ .json = "{\"sample_bypass\":2}", .expected = error.InvalidType },
        .{ .json = "{\"predicate\":false}", .expected = error.InvalidType },
        .{ .json = "{\"predicate\":\"status >=\"}", .expected = error.InvalidSyntax },
        .{ .json = "{\"redaction\":{}}", .expected = error.InvalidType },
        .{ .json = "{\"redaction\":[{}]}", .expected = error.MissingField },
        .{ .json = "{\"redaction\":[{\"key\":\"\",\"action\":\"mask\"}]}", .expected = error.EmptyKey },
        .{ .json = "{\"redaction\":[{\"key\":\"secret\",\"action\":\"unknown\"}]}", .expected = error.InvalidRedactionAction },
        .{ .json = "{\"redaction\":[{\"key\":\"secret\",\"action\":\"mask\",\"extra\":true}]}", .expected = error.UnknownField },
        .{ .json = "{\"redaction\":[{\"key\":\"secret\",\"key\":\"other\",\"action\":\"mask\"}]}", .expected = error.DuplicateField },
        .{ .json = "{\"redaction\":[{\"key\":\"secret\",\"action\":\"mask\"},{\"key\":\"secret\",\"action\":\"drop\"}]}", .expected = error.DuplicateKey },
        .{ .json = "{\"sampling\":{}}", .expected = error.MissingField },
        .{ .json = "{\"sampling\":{\"kind\":\"other\"}}", .expected = error.InvalidSamplingKind },
        .{ .json = "{\"sampling\":{\"kind\":\"count\"}}", .expected = error.MissingField },
        .{ .json = "{\"sampling\":{\"kind\":\"none\",\"count\":1}}", .expected = error.UnknownField },
        .{ .json = "{\"sampling\":{\"kind\":\"count\",\"count\":\"1\"}}", .expected = error.InvalidType },
        .{ .json = "{\"sampling\":{\"kind\":\"count\",\"count\":-1}}", .expected = error.InvalidNumber },
        .{ .json = "{\"sampling\":{\"kind\":\"count\",\"count\":1.0}}", .expected = error.InvalidNumber },
        .{ .json = "{\"sampling\":{\"kind\":\"count\",\"count\":1e2}}", .expected = error.InvalidNumber },
        .{ .json = "{\"sampling\":{\"kind\":\"count\",\"count\":18446744073709551616}}", .expected = error.NumericOverflow },
        .{ .json = "{\"sampling\":{\"kind\":\"every\",\"every\":0}}", .expected = error.InvalidSampleRate },
        .{ .json = "{\"sampling\":{\"kind\":\"every\",\"every\":1,\"every\":2}}", .expected = error.DuplicateField },
        .{ .json = "{\"sampling\":{\"kind\":\"token_bucket\",\"capacity\":4294967296,\"refill_interval_ns\":1}}", .expected = error.NumericOverflow },
        .{ .json = "{\"sampling\":{\"kind\":\"token_bucket\",\"capacity\":0,\"refill_interval_ns\":1}}", .expected = error.InvalidBucketCapacity },
        .{ .json = "{\"sampling\":{\"kind\":\"token_bucket\",\"capacity\":1,\"refill_interval_ns\":0}}", .expected = error.InvalidSampleRate },
        .{ .json = "{\"sampling\":{\"kind\":\"token_bucket\",\"capacity\":1,\"refill_interval_ns\":1,\"start_ns\":18446744073709551615}}", .expected = error.SampleWindowOverflow },
    };
    for (cases) |case| try std.testing.expectError(case.expected, Document.parse(std.testing.allocator, case.json));
    const malformed = [_][]const u8{ "", "{", "{]", "{\"filter\":\"unterminated}", "{\"filter\":}", "{} trailing", "{\"filter\":\"\\x\"}", "{\"filter\":\"\xff\"}" };
    for (malformed) |json| {
        if (Document.parse(std.testing.allocator, json)) |parsed| {
            var unexpected = parsed;
            unexpected.deinit();
            return error.ExpectedParseFailure;
        } else |_| {}
    }
}

test "document size and string aware depth budgets reject before allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var oversized: [max_document_bytes + 1]u8 = @splat(' ');
    try std.testing.expectError(error.DocumentTooLarge, Document.parse(failing.allocator(), &oversized));
    var nested: [2 * (max_json_depth + 1)]u8 = undefined;
    @memset(nested[0 .. max_json_depth + 1], '[');
    @memset(nested[max_json_depth + 1 ..], ']');
    try std.testing.expectError(error.JsonTooDeep, Document.parse(failing.allocator(), &nested));
    try std.testing.expectEqual(@as(usize, 0), failing.alloc_index);
    try std.testing.expect(!failing.has_induced_failure);
    try checkDocumentBudget(nested[1 .. nested.len - 1]);
    var document = try Document.parse(std.testing.allocator, "{\"predicate\":\"text == \\\"[[[[[[[[[[[[[[[[[[[\\\"\"}");
    defer document.deinit();
    try std.testing.expect(document.override().predicate == .expression);
    var maximum: [max_document_bytes]u8 = @splat(' ');
    @memcpy(maximum[0..2], "{}");
    var boundary = try Document.parse(std.testing.allocator, &maximum);
    defer boundary.deinit();
}

test "document rule budgets reuse redactor validation" {
    var buffer: [max_document_bytes]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.writeAll("{\"redaction\":[");
    for (0..redact.max_rules + 1) |i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("{{\"key\":\"key{d}\",\"action\":\"mask\"}}", .{i});
    }
    try writer.writeAll("]}");
    try std.testing.expectError(error.TooManyRules, Document.parse(std.testing.allocator, writer.buffered()));
    writer = std.Io.Writer.fixed(&buffer);
    try writer.writeAll("{\"redaction\":[{\"key\":\"");
    try writer.splatByteAll('a', redact.max_key_bytes + 1);
    try writer.writeAll("\",\"action\":\"mask\"}]}");
    try std.testing.expectError(error.KeyBudgetExceeded, Document.parse(std.testing.allocator, writer.buffered()));
}

test "document allocation failures release all parsed and policy storage and override allocates nothing" {
    const Harness = struct {
        fn parse(allocator: std.mem.Allocator) !void {
            var document = try Document.parse(allocator, "{\"filter\":\"warn,http=trace\",\"redaction\":[{\"key\":\"password\",\"action\":\"mask\"},{\"key\":\"token\",\"action\":\"drop\"}],\"sampling\":{\"kind\":\"token_bucket\",\"capacity\":3,\"refill_interval_ns\":10,\"start_ns\":100},\"sample_bypass\":\"warn\",\"predicate\":\"exists(status)\"}");
            defer document.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Harness.parse, .{});
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var document = try Document.parse(failing.allocator(), "{\"filter\":\"info\",\"redaction\":[{\"key\":\"password\",\"action\":\"mask\"}],\"predicate\":null}");
    defer document.deinit();
    const before = failing.alloc_index;
    failing.fail_index = before;
    for (0..100) |_| {
        const config = sources.merge(.{ .file = document.override() });
        try std.testing.expectEqualStrings("info", config.filter_spec);
        try std.testing.expectEqualStrings("password", config.redaction[0].key);
        try std.testing.expect(config.predicate == null);
    }
    try std.testing.expectEqual(before, failing.alloc_index);
    try std.testing.expect(!failing.has_induced_failure);
}
