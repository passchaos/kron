const std = @import("std");
pub const TestingAudit = if (@import("builtin").is_test) struct {
    pub threadlocal var visited_values: usize = 0;
    pub threadlocal var compared_keys: usize = 0;
} else struct {};

/// A borrowed typed value. Every nested descriptor, key, string and byte slice
/// must remain valid for submission; the binary codec copies their contents
/// before asynchronous acceptance. Aggregate traversal requires an explicit wrapper.
pub const Value = union(enum) {
    null_value,
    boolean: bool,
    signed: i128,
    unsigned: u128,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    duration_ns: i64,
    timestamp_ns: i64,
    array: []const Value,
    group: []const Field,
};

pub const Field = struct {
    key: []const u8,
    value: Value,
};

pub const Bytes = struct { value: []const u8 };
pub const Duration = struct { value: i64 };
pub const Timestamp = struct { value: i64 };
pub const Array = struct { value: []const Value };
pub const Group = struct { value: []const Field };
/// Carries no original value, so the secret cannot reach deferred capture.
pub const Secret = struct {};
pub const redacted = "[REDACTED]";

pub fn bytes(value: []const u8) Bytes {
    return .{ .value = value };
}

pub fn durationNs(value: i64) Duration {
    return .{ .value = value };
}

pub fn timestampNs(value: i64) Timestamp {
    return .{ .value = value };
}

pub fn array(value: []const Value) Array {
    return .{ .value = value };
}

pub fn group(value: []const Field) Group {
    return .{ .value = value };
}

pub fn secret(value: anytype) Secret {
    _ = value;
    return .{};
}

pub fn kv(key: []const u8, value: anytype) Field {
    return .{ .key = key, .value = fromAny(value) };
}

/// Built-in capture performs no allocation, formatting, or pointer traversal.
/// Arbitrary pointers and aggregate objects require an explicit adapter.
pub fn fromAny(value: anytype) Value {
    const T = @TypeOf(value);
    if (T == Value) return value;
    if (T == Bytes) return .{ .bytes = value.value };
    if (T == Duration) return .{ .duration_ns = value.value };
    if (T == Timestamp) return .{ .timestamp_ns = value.value };
    if (T == Secret) return .{ .string = redacted };
    if (T == Array) return .{ .array = value.value };
    if (T == Group) return .{ .group = value.value };
    return switch (@typeInfo(T)) {
        .null => .null_value,
        .bool => .{ .boolean = value },
        .int => |info| blk: {
            if (info.bits > 128) @compileError("kron integer fields support at most 128 bits");
            break :blk if (info.signedness == .signed) .{ .signed = @intCast(value) } else .{ .unsigned = @intCast(value) };
        },
        .comptime_int => if (value < 0) .{ .signed = value } else .{ .unsigned = value },
        .float => |info| blk: {
            if (info.bits > 64) @compileError("kron float fields support at most 64 bits");
            break :blk .{ .float = @floatCast(value) };
        },
        .comptime_float => .{ .float = value },
        .@"enum" => .{ .string = @tagName(value) },
        .error_set => .{ .string = @errorName(value) },
        .optional => if (value) |present| fromAny(present) else .null_value,
        .pointer => |info| blk: {
            if (info.size == .slice and info.child == u8) break :blk .{ .string = value };
            if (info.size == .one) {
                switch (@typeInfo(info.child)) {
                    .array => |array_info| if (array_info.child == u8) break :blk .{ .string = value },
                    else => {},
                }
            }
            break :blk unsupported(T);
        },
        else => unsupported(T),
    };
}

fn unsupported(comptime T: type) Value {
    @compileError("kron cannot capture " ++ @typeName(T) ++ "; use a supported scalar or explicit bytes/secret/array/group wrapper");
}

/// The event budget includes every value, including container and scalar nodes.
/// Depth counts only containers: a top-level array/group has depth one.
pub const max_value_depth: usize = 8;
pub const max_value_nodes: usize = 256;
pub const ValidationError = error{ DuplicateKey, ValueTooDeep, TooManyValueNodes, CyclicValue };
pub const AppendError = error{TooManyFields} || ValidationError;

/// A fixed-stack validator. Share one instance across attributes and arguments
/// to enforce one event-wide node budget without allocation.
pub const ValueValidator = struct {
    nodes: usize = 0,
    depth: usize = 0,
    ancestors: [max_value_depth]Region = undefined,

    const Region = struct { start: usize, end: usize };

    const NoopVisitor = struct {
        pub const Error = error{};
        pub fn onValue(_: *@This(), _: Value) Error!void {}
        pub fn onField(_: *@This(), _: Field) Error!void {}
    };

    pub fn value(self: *ValueValidator, input: Value) ValidationError!void {
        var visitor: NoopVisitor = .{};
        try self.valueWith(input, &visitor);
    }

    /// Traverse and validate with one callback per value and Field descriptor.
    /// Visitor callbacks must preserve the borrowed tree during the traversal.
    /// A typed visitor pointer supplies Error, onValue and onField methods.
    /// A visitor error immediately stops traversal and may precede validation
    /// errors in not-yet-visited nodes; no-op observers preserve validation order.
    pub fn valueWith(self: *ValueValidator, input: Value, visitor: anytype) (ValidationError || @TypeOf(visitor.*).Error)!void {
        if (self.nodes == max_value_nodes) return error.TooManyValueNodes;
        self.nodes += 1;
        if (@import("builtin").is_test) TestingAudit.visited_values += 1;
        try visitor.onValue(input);
        switch (input) {
            .array => |values| {
                if (values.len > max_value_nodes - self.nodes) return error.TooManyValueNodes;
                try self.enter(Value, values);
                defer self.depth -= 1;
                for (values) |child| try self.valueWith(child, visitor);
            },
            .group => |entries| {
                if (entries.len > max_value_nodes - self.nodes) return error.TooManyValueNodes;
                try self.enter(Field, entries);
                defer self.depth -= 1;
                try self.fieldsWith(entries, visitor);
            },
            else => {},
        }
    }

    fn enter(self: *ValueValidator, comptime T: type, items: []const T) ValidationError!void {
        const start = @intFromPtr(items.ptr);
        const length = std.math.mul(usize, items.len, @sizeOf(T)) catch return error.TooManyValueNodes;
        const end = std.math.add(usize, start, length) catch return error.TooManyValueNodes;
        // Revisiting the same active descriptor slice is a cycle. Overlapping
        // but distinct slices may share scalar leaves, so overlap alone is valid.
        if (length != 0) for (self.ancestors[0..self.depth]) |ancestor| {
            if (start == ancestor.start and end == ancestor.end) return error.CyclicValue;
        };
        if (self.depth == max_value_depth) return error.ValueTooDeep;
        self.ancestors[self.depth] = .{ .start = start, .end = end };
        self.depth += 1;
    }

    pub fn fields(self: *ValueValidator, entries: []const Field) ValidationError!void {
        var visitor: NoopVisitor = .{};
        try self.fieldsWith(entries, &visitor);
    }

    pub fn fieldsWith(self: *ValueValidator, entries: []const Field, visitor: anytype) (ValidationError || @TypeOf(visitor.*).Error)!void {
        if (entries.len > max_value_nodes - self.nodes) return error.TooManyValueNodes;
        for (entries, 0..) |entry, i| {
            try checkUnique(entries[0..i], entry.key);
            try visitor.onField(entry);
            try self.valueWith(entry.value, visitor);
        }
    }

    /// Positional formatting argument keys may repeat; nested group keys may not.
    pub fn arguments(self: *ValueValidator, entries: []const Field) ValidationError!void {
        var visitor: NoopVisitor = .{};
        try self.argumentsWith(entries, &visitor);
    }

    pub fn argumentsWith(self: *ValueValidator, entries: []const Field, visitor: anytype) (ValidationError || @TypeOf(visitor.*).Error)!void {
        if (entries.len > max_value_nodes - self.nodes) return error.TooManyValueNodes;
        for (entries) |entry| {
            try visitor.onField(entry);
            try self.valueWith(entry.value, visitor);
        }
    }
};

pub fn validateValue(value: Value) ValidationError!void {
    var validator: ValueValidator = .{};
    try validator.value(value);
}

pub fn validateFields(fields: []const Field) ValidationError!void {
    var validator: ValueValidator = .{};
    try validator.fields(fields);
}

test "validating visitors share attributes and arguments budgets and visit each nested descriptor once" {
    const Visitor = struct {
        pub const Error = error{VisitorStopped};
        values: usize = 0,
        fields_seen: usize = 0,
        stop_at: ?usize = null,
        pub fn onValue(self: *@This(), _: Value) Error!void {
            if (self.stop_at == self.values) return error.VisitorStopped;
            self.values += 1;
        }
        pub fn onField(self: *@This(), _: Field) Error!void {
            self.fields_seen += 1;
        }
    };
    const nested = [_]Field{
        kv("items", array(&.{ fromAny(@as(u64, 7)), .null_value })),
        kv("inner", group(&.{kv("secret", secret("never captured"))})),
    };
    var visitor: Visitor = .{};
    var validator: ValueValidator = .{};
    try validator.fieldsWith(&.{kv("root", group(&nested))}, &visitor);
    try validator.argumentsWith(&.{kv("", true)}, &visitor);
    try std.testing.expectEqual(@as(usize, 7), visitor.values);
    try std.testing.expectEqual(@as(usize, 5), visitor.fields_seen);
    try std.testing.expectEqual(visitor.values, validator.nodes);
    try std.testing.expectEqual(@as(usize, 0), validator.depth);

    visitor = .{ .stop_at = 3 };
    validator = .{};
    try std.testing.expectError(error.VisitorStopped, validator.fieldsWith(&.{kv("root", group(&nested))}, &visitor));
    try std.testing.expectEqual(@as(usize, 0), validator.depth);
    try std.testing.expectEqual(@as(usize, 3), visitor.values);

    const leaves = [_]Value{.null_value} ** (max_value_nodes - 1);
    visitor = .{};
    validator = .{};
    try validator.fieldsWith(&.{kv("full", array(&leaves))}, &visitor);
    try std.testing.expectEqual(max_value_nodes, visitor.values);
    try std.testing.expectError(error.TooManyValueNodes, validator.argumentsWith(&.{kv("", true)}, &visitor));
}

/// Appends one field layer transactionally. Named struct keys are unique by
/// construction; dynamic keys are checked against all fields already appended.
/// Context precedence is applied by the runtime before calling this helper.
pub fn appendFields(destination: []Field, count: *usize, input: anytype) AppendError!void {
    const T = @TypeOf(input);
    if (count.* > destination.len) return error.TooManyFields;
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (info.fields.len > destination.len - count.*) return error.TooManyFields;
            const start = count.*;
            var next = start;
            // Store beyond count first. On failure count stays unchanged, so no
            // partially accepted field layer becomes visible to the caller.
            inline for (info.fields) |member| {
                const field: Field = if (info.is_tuple) blk: {
                    if (member.type != Field) @compileError("kron field tuples must contain Field values");
                    break :blk @field(input, member.name);
                } else kv(member.name, @field(input, member.name));
                // Named members are distinct at comptime. Tuple Field keys are
                // dynamic, so they retain the complete sibling duplicate check.
                try checkUnique(destination[0..(if (info.is_tuple) next else start)], field.key);
                destination[next] = field;
                next += 1;
            }
            if (comptime info.is_tuple) {
                try validateFields(destination[0..next]);
            } else {
                // New named keys are unique by construction and already checked
                // against the original prefix. Validate all values with one
                // shared budget, preserving validation of any existing prefix.
                if (next > max_value_nodes) return error.TooManyValueNodes;
                var validator: ValueValidator = .{};
                try validator.fields(destination[0..start]);
                inline for (info.fields, 0..) |member, index| {
                    if (comptime mayContainContainer(member.type)) {
                        try validator.value(destination[start + index].value);
                    } else {
                        // fromAny already proves this type captures a scalar.
                        // Account its one node without dispatching through a
                        // dynamic Value or relaxing the combined-tree budget.
                        if (validator.nodes == max_value_nodes) return error.TooManyValueNodes;
                        validator.nodes += 1;
                    }
                }
            }
            count.* = next;
        },
        .array => |info| {
            if (info.child != Field) @compileError("kron field arrays must contain Field values");
            try appendSlice(destination, count, &input);
        },
        .pointer => |info| {
            if (info.size == .slice and info.child == Field) {
                try appendSlice(destination, count, input);
            } else if (info.size == .one and @typeInfo(info.child) == .array and @typeInfo(info.child).array.child == Field) {
                try appendSlice(destination, count, input);
            } else if (info.size == .one and @typeInfo(info.child) == .@"struct") {
                try appendFields(destination, count, input.*);
            } else @compileError("kron fields must be a named struct or Field slice");
        },
        else => @compileError("kron fields must be a named struct or Field slice"),
    }
}

fn mayContainContainer(comptime T: type) bool {
    if (T == Value or T == Array or T == Group) return true;
    return switch (@typeInfo(T)) {
        .optional => |info| mayContainContainer(info.child),
        else => false,
    };
}

fn appendSlice(destination: []Field, count: *usize, fields: []const Field) AppendError!void {
    if (fields.len > destination.len - count.*) return error.TooManyFields;
    for (fields, 0..) |field, i| {
        try checkUnique(destination[0..count.*], field.key);
        try checkUnique(fields[0..i], field.key);
    }
    var validator: ValueValidator = .{};
    try validator.fields(destination[0..count.*]);
    try validator.fields(fields);
    @memcpy(destination[count.*..][0..fields.len], fields);
    count.* += fields.len;
}

pub fn checkUnique(fields: []const Field, key: []const u8) error{DuplicateKey}!void {
    for (fields) |field| {
        if (@import("builtin").is_test) TestingAudit.compared_keys += 1;
        if (std.mem.eql(u8, field.key, key)) return error.DuplicateKey;
    }
}

test "named append uses compile-time unique keys but retains invalid prefix and joint value budgets" {
    var storage: [5]Field = undefined;
    var count: usize = 0;
    const before = TestingAudit.compared_keys;
    try appendFields(&storage, &count, .{ .a = @as(u64, 1), .b = true, .c = @as(f64, 1.5) });
    try std.testing.expectEqual(before, TestingAudit.compared_keys);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectError(error.DuplicateKey, appendFields(&storage, &count, .{ .b = false }));
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expect(storage[1].value.boolean);

    var invalid: [3]Field = .{ kv("dup", 1), kv("dup", 2), kv("tail", 3) };
    var invalid_count: usize = 2;
    try std.testing.expectError(error.DuplicateKey, appendFields(&invalid, &invalid_count, .{}));
    try std.testing.expectEqual(@as(usize, 2), invalid_count);

    const leaves = [_]Value{.null_value} ** (max_value_nodes - 1);
    var full: [2]Field = .{ kv("full", array(&leaves)), kv("untouched", false) };
    var full_count: usize = 1;
    try std.testing.expectError(error.TooManyValueNodes, appendFields(&full, &full_count, .{ .new = true }));
    try std.testing.expectEqual(@as(usize, 1), full_count);

    var cyclic: [1]Value = undefined;
    cyclic[0] = .{ .array = &cyclic };
    var prior: [2]Field = .{ kv("cycle", array(&cyclic)), kv("untouched", false) };
    var prior_count: usize = 1;
    try std.testing.expectError(error.CyclicValue, appendFields(&prior, &prior_count, .{ .new = true }));
    try std.testing.expectEqual(@as(usize, 1), prior_count);

    // The tail is walked in original order. A bad first value still wins over
    // the eventual combined node overflow from its later named siblings.
    var mixed: [5]Field = undefined;
    mixed[0] = kv("near_limit", array(leaves[0 .. max_value_nodes - 4]));
    var mixed_count: usize = 1;
    try std.testing.expectError(error.CyclicValue, appendFields(&mixed, &mixed_count, .{
        .first = array(&cyclic),
        .second = true,
        .third = true,
        .fourth = true,
    }));
    try std.testing.expectEqual(@as(usize, 1), mixed_count);
}

test "static scalar capture skips dynamic dispatch while retaining mixed tree budgets" {
    const E = enum { ready };
    var output: [16]Field = undefined;
    var count: usize = 0;
    const before = TestingAudit.visited_values;
    try appendFields(&output, &count, .{
        .number = @as(u128, std.math.maxInt(u128)),
        .float = @as(f64, 1.25),
        .optional = @as(?u8, null),
        .string = "scalar",
        .bytes = bytes("\x00\xff"),
        .tag = E.ready,
        .error_value = error.Example,
        .secret = secret("never retained"),
    });
    try std.testing.expectEqual(@as(usize, 8), count);
    try std.testing.expectEqual(before, TestingAudit.visited_values);
    try std.testing.expectEqual(std.math.maxInt(u128), output[0].value.unsigned);
    try std.testing.expect(output[2].value == .null_value);
    try std.testing.expectEqualStrings(redacted, output[7].value.string);

    const leaves = [_]Value{.null_value} ** (max_value_nodes - 2);
    count = 0;
    try appendFields(&output, &count, .{
        .tree = array(&leaves),
        .scalar = @as(u64, 1),
    });
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectError(error.TooManyValueNodes, appendFields(&output, &count, .{ .extra = true }));
    try std.testing.expectEqual(@as(usize, 2), count);

    var cyclic: [1]Value = undefined;
    cyclic[0] = .{ .array = &cyclic };
    count = 0;
    try std.testing.expectError(error.CyclicValue, appendFields(&output, &count, .{
        .scalar = @as(u64, 1),
        .dynamic = Value{ .array = &cyclic },
    }));
    try std.testing.expectEqual(@as(usize, 0), count);
    try std.testing.expectError(error.CyclicValue, appendFields(&output, &count, .{
        .maybe = @as(?Array, array(&cyclic)),
    }));
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "capture built-in values and erase secrets before capture" {
    const E = enum { ready };
    const yes: ?u16 = 42;
    const no: ?u16 = null;
    try std.testing.expectEqual(@as(i128, std.math.minInt(i128)), fromAny(std.math.minInt(i128)).signed);
    try std.testing.expectEqual(@as(u128, std.math.maxInt(u128)), fromAny(std.math.maxInt(u128)).unsigned);
    try std.testing.expectEqual(@as(u128, 42), fromAny(yes).unsigned);
    try std.testing.expect(fromAny(no) == .null_value);
    try std.testing.expectEqualStrings("ready", fromAny(E.ready).string);
    try std.testing.expectEqualStrings("Denied", fromAny(error.Denied).string);
    try std.testing.expectEqualStrings("hello", fromAny("hello").string);
    try std.testing.expectEqualStrings("\xff", fromAny(bytes("\xff")).bytes);
    try std.testing.expectEqual(@as(i64, -10), fromAny(durationNs(-10)).duration_ns);
    try std.testing.expectEqual(@as(i64, 12), fromAny(timestampNs(12)).timestamp_ns);
    const hidden = secret("this secret is never retained");
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(hidden)));
    try std.testing.expectEqualStrings(redacted, fromAny(hidden).string);
}

test "append struct, tuple and slices with duplicate and capacity rejection" {
    var storage: [6]Field = undefined;
    var count: usize = 0;
    try appendFields(&storage, &count, .{ .answer = @as(u16, 42), .enabled = true });
    try appendFields(&storage, &count, .{kv("other", null)});
    try appendFields(&storage, &count, &.{kv("fourth", "value")});
    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expectEqualStrings("answer", storage[0].key);
    try std.testing.expectError(error.DuplicateKey, appendFields(&storage, &count, &.{ kv("dup", 1), kv("dup", 2) }));
    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expectError(error.DuplicateKey, appendFields(&storage, &count, .{ .answer = 3 }));
    try std.testing.expectError(error.TooManyFields, appendFields(&storage, &count, .{ .a = 1, .b = 2, .c = 3 }));
    try std.testing.expectEqual(@as(usize, 4), count);
}

test "explicit array and group capture validates nested keys and fixed traversal budgets" {
    const values = [_]Value{ fromAny(true), fromAny(bytes("\x00\xff")), fromAny(null) };
    const entries = [_]Field{ kv("values", array(&values)), kv("empty", group(&.{})) };
    try std.testing.expectEqual(@as(usize, 3), fromAny(array(&values)).array.len);
    try std.testing.expectEqual(@as(usize, 2), fromAny(group(&entries)).group.len);
    try validateValue(fromAny(group(&entries)));
    const duplicate = [_]Field{ kv("same", true), kv("same", false) };
    try std.testing.expectError(error.DuplicateKey, validateValue(fromAny(group(&duplicate))));

    var cyclic_array: [1]Value = undefined;
    cyclic_array[0] = .{ .array = &cyclic_array };
    try std.testing.expectError(error.CyclicValue, validateValue(cyclic_array[0]));
    var cyclic_group: [1]Field = undefined;
    cyclic_group[0] = kv("self", group(&cyclic_group));
    try std.testing.expectError(error.CyclicValue, validateValue(cyclic_group[0].value));

    var chain: [max_value_depth + 1]Value = undefined;
    chain[0] = .{ .array = &.{} };
    for (1..chain.len) |i| chain[i] = .{ .array = chain[i - 1 .. i] };
    try validateValue(chain[max_value_depth - 1]);
    try std.testing.expectError(error.ValueTooDeep, validateValue(chain[max_value_depth]));

    var maximum: [max_value_nodes]Value = @splat(.null_value);
    try validateValue(.{ .array = maximum[0 .. maximum.len - 1] });
    try std.testing.expectError(error.TooManyValueNodes, validateValue(.{ .array = &maximum }));
    // Branch reuse retains borrowed views and is not a cycle.
    try validateValue(.{ .array = &.{ .{ .array = values[0..1] }, .{ .array = values[0..1] } } });
    var shared: [2]Value = undefined;
    shared[0] = .null_value;
    shared[1] = .{ .array = shared[0..1] };
    try validateValue(.{ .array = &shared });
}

test "failed nested append leaves visible field count unchanged" {
    var destination: [4]Field = undefined;
    var count: usize = 0;
    try appendFields(&destination, &count, .{ .good = true });
    try std.testing.expectError(error.DuplicateKey, appendFields(&destination, &count, .{ .bad = group(&.{ kv("dup", 1), kv("dup", 2) }) }));
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expect(destination[0].value.boolean);
}
