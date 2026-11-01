//! Explicit object field selection with caller-owned descriptor storage.
//! Scalars are copied; strings, bytes and nested slices remain borrowed until
//! encoding accepts them. Only selected members are examined. No heap allocation,
//! formatter invocation or recursive object reflection occurs during capture.
const std = @import("std");
const field = @import("field.zig");

pub const max_selected_fields: usize = 64;
pub const CaptureError = field.ValidationError || error{TooManyFields};
pub const FieldMap = struct { member: []const u8, key: []const u8 };

/// Selects members by their original names. Hold this value at a stable address
/// while its returned Group is borrowed. Reusing capture invalidates the prior
/// view, including when the next capture returns a validation error.
///
///     var storage = Adapter(User, &.{ "id", "name" }).init();
///     const attributes = try storage.capture(&user);
///
/// Members omitted from selected, such as passwords or unsupported object
/// pointers, are never captured. Use Secret to redact a selected member.
pub fn Adapter(comptime T: type, comptime selected: []const []const u8) type {
    const mappings = comptime namesToMappings(selected);
    return MappedAdapter(T, &mappings);
}

/// The same bounded adapter with explicit output keys. Member names and output
/// keys are separately unique and checked at compile time.
pub fn MappedAdapter(comptime T: type, comptime selected: []const FieldMap) type {
    comptime validateSelection(T, selected);
    return struct {
        pub const ObjectType = T;
        pub const selection = selected;
        const Self = @This();

        fields: [selected.len]field.Field,

        pub fn init() Self {
            return .{ .fields = undefined };
        }

        pub fn capture(self: *Self, input: *const T) field.ValidationError!field.Group {
            return captureInto(T, selected, input, &self.fields);
        }
    };
}

/// Convenience capture directly into caller Field storage. Input must be a
/// pointer to a named struct, and storage must remain valid with the input's
/// borrowed strings/bytes/nested descriptors until encoding has accepted them.
/// No local descriptor array is returned. Extra destination entries are unused.
pub fn object(comptime selected: []const []const u8, input: anytype, storage: []field.Field) CaptureError!field.Group {
    const mappings = comptime namesToMappings(selected);
    return objectMapped(&mappings, input, storage);
}

pub fn objectMapped(comptime selected: []const FieldMap, input: anytype, storage: []field.Field) CaptureError!field.Group {
    const T = comptime inputObjectType(@TypeOf(input));
    comptime validateSelection(T, selected);
    if (selected.len > storage.len) return error.TooManyFields;
    return captureInto(T, selected, input, storage[0..selected.len]);
}

fn captureInto(comptime T: type, comptime selected: []const FieldMap, input: *const T, storage: []field.Field) field.ValidationError!field.Group {
    inline for (selected, 0..) |mapping, i| {
        storage[i] = .{ .key = mapping.key, .value = field.fromAny(@field(input.*, mapping.member)) };
    }
    const captured = field.group(storage[0..selected.len]);
    // Count the resulting group itself, so capture observes the same depth and
    // node limits as the event codec. Nested cycles and duplicate keys fail here.
    try field.validateValue(field.fromAny(captured));
    return captured;
}

fn namesToMappings(comptime selected: []const []const u8) [selected.len]FieldMap {
    var mappings: [selected.len]FieldMap = undefined;
    for (selected, 0..) |name, i| mappings[i] = .{ .member = name, .key = name };
    return mappings;
}

fn inputObjectType(comptime Input: type) type {
    const pointer = switch (@typeInfo(Input)) {
        .pointer => |info| info,
        else => @compileError("kron object adapter input must be a pointer to a named struct; keep the source alive until encoding accepts it"),
    };
    if (pointer.size != .one)
        @compileError("kron object adapter input must be a single pointer to a named struct");
    return pointer.child;
}

fn validateSelection(comptime T: type, comptime selected: []const FieldMap) void {
    @setEvalBranchQuota(100_000);
    const info = switch (@typeInfo(T)) {
        .@"struct" => |info| info,
        else => @compileError("kron object adapter requires a named struct type"),
    };
    if (info.is_tuple) @compileError("kron object adapter requires named struct members, not a tuple");
    if (selected.len > max_selected_fields)
        @compileError("kron object adapter exceeds its 64 selected-field budget");
    for (selected, 0..) |mapping, i| {
        if (!@hasField(T, mapping.member))
            @compileError("kron object adapter has no selected member '" ++ mapping.member ++ "' in " ++ @typeName(T));
        for (selected[0..i]) |previous| {
            if (std.mem.eql(u8, previous.member, mapping.member))
                @compileError("kron object adapter duplicate selected member '" ++ mapping.member ++ "'");
            if (std.mem.eql(u8, previous.key, mapping.key))
                @compileError("kron object adapter duplicate output key '" ++ mapping.key ++ "'");
        }
        for (info.fields) |member| {
            if (std.mem.eql(u8, member.name, mapping.member)) validateCaptureType(member.type, mapping.member);
        }
    }
}

fn validateCaptureType(comptime T: type, comptime member: []const u8) void {
    if (T == field.Value or T == field.Bytes or T == field.Duration or T == field.Timestamp or
        T == field.Array or T == field.Group or T == field.Secret) return;
    switch (@typeInfo(T)) {
        .null, .bool, .comptime_int, .comptime_float, .@"enum", .error_set => return,
        .int => |info| if (info.bits <= 128) return,
        .float => |info| if (info.bits <= 64) return,
        .optional => |info| return validateCaptureType(info.child, member),
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) return;
            // Existing capture treats pointers to byte arrays (including string
            // literals) as borrowed strings; it does not dereference other pointers.
            if (info.size == .one) switch (@typeInfo(info.child)) {
                .array => |array_info| if (array_info.child == u8) return,
                else => {},
            };
        },
        else => {},
    }
    @compileError("kron object adapter cannot capture selected member '" ++ member ++ "' of type " ++ @typeName(T) ++
        "; use a supported scalar, an explicit byte slice, or bytes/secret/array/group wrapper");
}

test "selection copies scalars and borrows only selected bytes and descriptors" {
    const User = struct { id: u64, name: []const u8, password: *const u64, state: ?bool, protected: field.Secret };
    const ignored: u64 = 42;
    var name = "alice".*;
    var user: User = .{ .id = 7, .name = &name, .password = &ignored, .state = null, .protected = field.secret("unretained") };
    var storage = Adapter(User, &.{ "id", "name", "state", "protected" }).init();
    const captured = try storage.capture(&user);
    user.id = 99;
    name[0] = 'A';
    try std.testing.expectEqual(@as(u128, 7), captured.value[0].value.unsigned);
    try std.testing.expectEqualStrings("Alice", captured.value[1].value.string);
    try std.testing.expect(captured.value[2].value == .null_value);
    try std.testing.expectEqualStrings(field.redacted, captured.value[3].value.string);
    try std.testing.expectEqual(@intFromPtr(&storage.fields), @intFromPtr(captured.value.ptr));
}

test "caller storage factory and mapped names never return local descriptors" {
    const User = struct { id: u64, name: []const u8 };
    var user: User = .{ .id = 1, .name = "alice" };
    var storage: [2]field.Field = undefined;
    const captured = try object(&.{ "id", "name" }, &user, &storage);
    try std.testing.expectEqual(@intFromPtr(&storage), @intFromPtr(captured.value.ptr));
    const mappings = &.{ FieldMap{ .member = "id", .key = "user.id" }, FieldMap{ .member = "name", .key = "display_name" } };
    var mapped = MappedAdapter(User, mappings).init();
    const renamed = try mapped.capture(&user);
    try std.testing.expectEqualStrings("user.id", renamed.value[0].key);
    try std.testing.expectEqualStrings("display_name", renamed.value[1].key);
    var small: [1]field.Field = undefined;
    try std.testing.expectError(error.TooManyFields, object(&.{ "id", "name" }, &user, &small));
    const empty = try object(&.{}, &user, &.{});
    try std.testing.expectEqual(@as(usize, 0), empty.value.len);
}

test "explicit nested adapters retain group traversal limits" {
    const Input = struct { values: field.Array };
    var descriptors: [1]field.Value = undefined;
    descriptors[0] = .{ .array = &descriptors };
    var input: Input = .{ .values = field.array(&descriptors) };
    var adapter = Adapter(Input, &.{"values"}).init();
    try std.testing.expectError(error.CyclicValue, adapter.capture(&input));
    var nodes: [field.max_value_nodes]field.Value = @splat(.null_value);
    input.values = field.array(nodes[0 .. field.max_value_nodes - 2]);
    _ = try adapter.capture(&input); // group + array + 254 scalar leaves.
    input.values = field.array(nodes[0 .. field.max_value_nodes - 1]);
    try std.testing.expectError(error.TooManyValueNodes, adapter.capture(&input));
    var chain: [field.max_value_depth]field.Value = undefined;
    chain[0] = .{ .array = &.{} };
    for (1..chain.len) |i| chain[i] = .{ .array = chain[i - 1 .. i] };
    input.values = field.array(chain[chain.len - 2 .. chain.len - 1]);
    try std.testing.expectError(error.ValueTooDeep, adapter.capture(&input));
}

test "maximum selected members stay within fixed caller storage" {
    @setEvalBranchQuota(100_000);
    const Maximum = struct { f0: u8 = 0, f1: u8 = 0, f2: u8 = 0, f3: u8 = 0, f4: u8 = 0, f5: u8 = 0, f6: u8 = 0, f7: u8 = 0, f8: u8 = 0, f9: u8 = 0, f10: u8 = 0, f11: u8 = 0, f12: u8 = 0, f13: u8 = 0, f14: u8 = 0, f15: u8 = 0, f16: u8 = 0, f17: u8 = 0, f18: u8 = 0, f19: u8 = 0, f20: u8 = 0, f21: u8 = 0, f22: u8 = 0, f23: u8 = 0, f24: u8 = 0, f25: u8 = 0, f26: u8 = 0, f27: u8 = 0, f28: u8 = 0, f29: u8 = 0, f30: u8 = 0, f31: u8 = 0, f32: u8 = 0, f33: u8 = 0, f34: u8 = 0, f35: u8 = 0, f36: u8 = 0, f37: u8 = 0, f38: u8 = 0, f39: u8 = 0, f40: u8 = 0, f41: u8 = 0, f42: u8 = 0, f43: u8 = 0, f44: u8 = 0, f45: u8 = 0, f46: u8 = 0, f47: u8 = 0, f48: u8 = 0, f49: u8 = 0, f50: u8 = 0, f51: u8 = 0, f52: u8 = 0, f53: u8 = 0, f54: u8 = 0, f55: u8 = 0, f56: u8 = 0, f57: u8 = 0, f58: u8 = 0, f59: u8 = 0, f60: u8 = 0, f61: u8 = 0, f62: u8 = 0, f63: u8 = 0 };
    const names = comptime blk: {
        var selected: [max_selected_fields][]const u8 = undefined;
        for (&selected, 0..) |*name, i| name.* = std.fmt.comptimePrint("f{d}", .{i});
        break :blk selected;
    };
    var input: Maximum = .{};
    var adapter = Adapter(Maximum, &names).init();
    const captured = try adapter.capture(&input);
    try std.testing.expectEqual(max_selected_fields, captured.value.len);
    try std.testing.expectEqualStrings("f63", captured.value[63].key);
}
