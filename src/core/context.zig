//! Context views are immutable. A layer is validated independently before its
//! keys replace parent keys; ownership is explicit and never needed by emit.
const std = @import("std");
const field = @import("field.zig");
pub const Field = field.Field;
pub const max_fields = 64;
pub const MergeError = field.AppendError;

pub const EmptyContext = struct {
    pub fn appendContext(_: EmptyContext, _: []Field, _: *usize) MergeError!void {}
};

/// Input is stored by value. Slices, pointers, keys and string/bytes values
/// remain borrowed and must outlive every call using this context.
pub fn BorrowedContext(comptime Parent: type, comptime Input: type) type {
    return struct {
        parent: Parent,
        fields: Input,

        pub fn appendContext(self: @This(), destination: []Field, count: *usize) MergeError!void {
            try self.parent.appendContext(destination, count);
            try mergeFields(destination, count, self.fields);
        }
    };
}

/// Merges one independently checked layer. Existing keys keep their position
/// and take the newer value. Errors leave the visible destination unchanged.
pub fn mergeFields(destination: []Field, count: *usize, input: anytype) MergeError!void {
    if (count.* > destination.len or count.* > max_fields) return error.TooManyFields;
    var layer: [max_fields]Field = undefined;
    var layer_len: usize = 0;
    try field.appendFields(&layer, &layer_len, input);
    var added: usize = 0;
    for (layer[0..layer_len]) |entry| {
        if (indexOf(destination[0..count.*], entry.key) == null) added += 1;
    }
    if (added > @min(destination.len, max_fields) - count.*) return error.TooManyFields;
    for (layer[0..layer_len]) |entry| {
        if (indexOf(destination[0..count.*], entry.key)) |index| {
            destination[index] = entry;
        } else {
            destination[count.*] = entry;
            count.* += 1;
        }
    }
}

fn indexOf(fields: []const Field, key: []const u8) ?usize {
    for (fields, 0..) |entry, index| {
        if (std.mem.eql(u8, entry.key, key)) return index;
    }
    return null;
}

/// Owns every nested descriptor, key, string and byte slice. Copies of this
/// value share ownership: destroy exactly once, after all borrowed users end.
pub const OwnedContext = struct {
    allocator: std.mem.Allocator,
    fields: []Field,
    storage: []align(@alignOf(Field)) u8,

    pub fn init(allocator: std.mem.Allocator, input: anytype) (std.mem.Allocator.Error || MergeError || error{ContextTooLarge})!OwnedContext {
        var scratch: [max_fields]Field = undefined;
        var count: usize = 0;
        try field.appendFields(&scratch, &count, input);
        return cloneFields(allocator, scratch[0..count]);
    }

    fn cloneFields(allocator: std.mem.Allocator, fields: []const Field) (std.mem.Allocator.Error || error{ContextTooLarge})!OwnedContext {
        var size: usize = 0;
        for (fields) |entry| try ownedFieldSize(&size, entry);
        const owned_fields = try allocator.alloc(Field, fields.len);
        errdefer allocator.free(owned_fields);
        const storage = try allocator.alignedAlloc(u8, .of(Field), size);
        var arena: OwnedArena = .{ .storage = storage };
        for (fields, owned_fields) |entry, *owned| owned.* = arena.cloneField(entry);
        std.debug.assert(arena.cursor == size);
        return .{ .allocator = allocator, .fields = owned_fields, .storage = storage };
    }

    pub fn appendContext(self: OwnedContext, destination: []Field, count: *usize) MergeError!void {
        try mergeFields(destination, count, self.fields);
    }

    pub fn destroy(self: *OwnedContext) void {
        self.allocator.free(self.fields);
        self.allocator.free(self.storage);
        self.fields = &.{};
        self.storage = &.{};
    }

    pub fn deinit(self: *OwnedContext) void {
        self.destroy();
    }
};

fn ownedAdd(size: *usize, amount: usize) error{ContextTooLarge}!void {
    size.* = std.math.add(usize, size.*, amount) catch return error.ContextTooLarge;
}

fn ownedDescriptors(size: *usize, comptime T: type, count: usize) error{ContextTooLarge}!void {
    try ownedAdd(size, @alignOf(T) - 1);
    size.* &= ~@as(usize, @alignOf(T) - 1);
    try ownedAdd(size, std.math.mul(usize, count, @sizeOf(T)) catch return error.ContextTooLarge);
}

fn ownedFieldSize(size: *usize, entry: Field) error{ContextTooLarge}!void {
    try ownedAdd(size, entry.key.len);
    try ownedValueSize(size, entry.value);
}

fn ownedValueSize(size: *usize, value: field.Value) error{ContextTooLarge}!void {
    switch (value) {
        .string, .bytes => |bytes| try ownedAdd(size, bytes.len),
        .array => |values| {
            try ownedDescriptors(size, field.Value, values.len);
            for (values) |child| try ownedValueSize(size, child);
        },
        .group => |entries| {
            try ownedDescriptors(size, Field, entries.len);
            for (entries) |entry| try ownedFieldSize(size, entry);
        },
        else => {},
    }
}

const OwnedArena = struct {
    storage: []align(@alignOf(Field)) u8,
    cursor: usize = 0,

    fn bytes(self: *OwnedArena, input: []const u8) []const u8 {
        const copied = self.storage[self.cursor..][0..input.len];
        @memcpy(copied, input);
        self.cursor += input.len;
        return copied;
    }

    fn descriptors(self: *OwnedArena, comptime T: type, count: usize) []T {
        self.cursor = std.mem.alignForward(usize, self.cursor, @alignOf(T));
        const pointer: [*]T = @ptrCast(@alignCast(self.storage[self.cursor..].ptr));
        self.cursor += count * @sizeOf(T);
        return pointer[0..count];
    }

    fn cloneField(self: *OwnedArena, entry: Field) Field {
        const key = self.bytes(entry.key);
        return .{ .key = key, .value = self.cloneValue(entry.value) };
    }

    fn cloneValue(self: *OwnedArena, value: field.Value) field.Value {
        return switch (value) {
            .string => |input| .{ .string = self.bytes(input) },
            .bytes => |input| .{ .bytes = self.bytes(input) },
            .array => |input| blk: {
                const values = self.descriptors(field.Value, input.len);
                for (input, values) |child, *owned| owned.* = self.cloneValue(child);
                break :blk .{ .array = values };
            },
            .group => |input| blk: {
                const entries = self.descriptors(Field, input.len);
                for (input, entries) |entry, *owned| owned.* = self.cloneField(entry);
                break :blk .{ .group = entries };
            },
            else => value,
        };
    }
};

test "context precedence replaces keys and rejects duplicate siblings transactionally" {
    var scratch: [max_fields]Field = undefined;
    var count: usize = 0;
    try mergeFields(&scratch, &count, .{ .request = 1, .parent = true });
    try mergeFields(&scratch, &count, .{ .request = 2, .child = true });
    try mergeFields(&scratch, &count, .{ .request = 3 });
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(u128, 3), scratch[0].value.unsigned);
    try std.testing.expectError(error.DuplicateKey, mergeFields(&scratch, &count, &.{ field.kv("request", 4), field.kv("request", 5) }));
    try std.testing.expectEqual(@as(u128, 3), scratch[0].value.unsigned);
    var small: [1]Field = .{field.kv("request", 1)};
    var small_len: usize = 1;
    try std.testing.expectError(error.TooManyFields, mergeFields(&small, &small_len, .{ .request = 2, .extra = true }));
    try std.testing.expectEqual(@as(u128, 1), small[0].value.unsigned);
}

test "owned context deeply copies key, string and bytes" {
    var key = [_]u8{ 'k', 'e', 'y' };
    var string = [_]u8{ 't', 'e', 'x', 't' };
    var bytes = [_]u8{ 0, 1, 255 };
    var owned = try OwnedContext.init(std.testing.allocator, &.{
        field.kv(&key, @as([]const u8, &string)),
        field.kv("bytes", field.bytes(&bytes)),
    });
    defer owned.destroy();
    @memset(&key, 'x');
    @memset(&string, 'x');
    @memset(&bytes, 42);
    try std.testing.expectEqualStrings("key", owned.fields[0].key);
    try std.testing.expectEqualStrings("text", owned.fields[0].value.string);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 255 }, owned.fields[1].value.bytes);
}

test "maximum fields permit replacements but reject additional keys" {
    @setEvalBranchQuota(30000);
    var scratch: [max_fields]Field = undefined;
    inline for (0..max_fields) |index| {
        scratch[index] = field.kv(std.fmt.comptimePrint("field{d}", .{index}), index);
    }
    var count: usize = max_fields;
    try mergeFields(&scratch, &count, .{ .field0 = 100 });
    try std.testing.expectEqual(@as(u128, 100), scratch[0].value.unsigned);
    try std.testing.expectError(error.TooManyFields, mergeFields(&scratch, &count, .{ .field0 = 101, .extra = true }));
    try std.testing.expectEqual(@as(u128, 100), scratch[0].value.unsigned);
    try std.testing.expectEqual(@as(usize, max_fields), count);
}

test "owned context releases descriptors when copying storage fails" {
    const Harness = struct {
        fn create(allocator: std.mem.Allocator) !void {
            var owned = try OwnedContext.init(allocator, .{ .name = "context", .bytes = field.bytes("data") });
            defer owned.destroy();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Harness.create, .{});
}

test "owned context copies every nested descriptor key string and bytes" {
    var key = "nested".*;
    var text = "original".*;
    var data = [_]u8{ 0, 255 };
    var values = [_]field.Value{ field.fromAny(@as([]const u8, &text)), field.fromAny(field.bytes(&data)) };
    var entries = [_]Field{field.kv(&key, field.array(&values))};
    var owned = try OwnedContext.init(std.testing.allocator, .{ .root = field.group(&entries) });
    defer owned.deinit();
    @memset(&key, 'x');
    @memset(&text, 'x');
    @memset(&data, 42);
    values = @splat(.null_value);
    entries[0] = field.kv("changed", false);
    const restored = owned.fields[0].value.group[0];
    try std.testing.expectEqualStrings("nested", restored.key);
    try std.testing.expectEqualStrings("original", restored.value.array[0].string);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255 }, restored.value.array[1].bytes);
}

test "nested owned context rejects cycles and releases partial allocation failures" {
    var cycle: [1]field.Value = undefined;
    cycle[0] = .{ .array = &cycle };
    try std.testing.expectError(error.CyclicValue, OwnedContext.init(std.testing.allocator, .{ .cycle = field.array(&cycle) }));
    const Harness = struct {
        fn create(allocator: std.mem.Allocator) !void {
            var owned = try OwnedContext.init(allocator, .{ .root = field.group(&.{
                field.kv("values", field.array(&.{ field.fromAny("text"), field.fromAny(field.bytes("\xff")) })),
                field.kv("empty", field.group(&.{})),
            }) });
            defer owned.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Harness.create, .{});
}
