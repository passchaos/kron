const std = @import("std");
const fields = @import("../core/field.zig");
const Field = fields.Field;
const Value = fields.Value;

pub const max_rules = 64;
pub const max_key_bytes = 4096;
pub const mask = fields.redacted;

pub const Action = enum { drop, mask };

pub const Rule = struct {
    key: []const u8,
    action: Action,
};

pub const InitError = error{ EmptyKey, TooManyRules, KeyBudgetExceeded };
pub const DeepError = fields.ValidationError || error{ScratchTooSmall};

/// An immutable owning policy with exact, case-sensitive key matching at every
/// group level. Dots in rule keys are literal bytes, not path separators. Last
/// duplicate wins. Secret wrappers are already irreversibly replaced by core
/// capture; this policy never sees or retains their original values.
pub const Redactor = struct {
    rule_count: usize = 0,
    key_bytes_used: usize = 0,
    rules: [max_rules]StoredRule = undefined,
    key_bytes: [max_key_bytes]u8 = undefined,

    const StoredRule = struct {
        offset: u16,
        len: u16,
        action: Action,
    };

    pub fn init(rules: []const Rule) InitError!Redactor {
        var result: Redactor = .{};
        for (rules) |rule| try result.put(rule);
        return result;
    }

    pub fn eql(self: *const Redactor, other: *const Redactor) bool {
        if (self.rule_count != other.rule_count or self.key_bytes_used != other.key_bytes_used or !std.mem.eql(u8, self.key_bytes[0..self.key_bytes_used], other.key_bytes[0..other.key_bytes_used])) return false;
        for (self.rules[0..self.rule_count], other.rules[0..other.rule_count]) |left, right| if (!std.meta.eql(left, right)) return false;
        return true;
    }

    pub fn hash(self: *const Redactor, digest: *std.hash.Wyhash) void {
        var count: [2]u8 = undefined;
        std.mem.writeInt(u16, &count, @intCast(self.rule_count), .little);
        digest.update(&count);
        for (self.rules[0..self.rule_count]) |rule| {
            var length: [2]u8 = undefined;
            std.mem.writeInt(u16, &length, rule.len, .little);
            digest.update(&length);
            digest.update(self.key_bytes[rule.offset..][0..rule.len]);
            digest.update(&.{@intFromEnum(rule.action)});
        }
    }

    /// Returns null for a dropped field, otherwise a borrowed field view.
    /// Masking changes the value to the static constant before typed capture.
    pub fn apply(self: *const Redactor, field: Field) ?Field {
        for (self.rules[0..self.rule_count]) |rule| {
            const key = self.key_bytes[rule.offset..][0..rule.len];
            if (std.mem.eql(u8, field.key, key)) return switch (rule.action) {
                .drop => null,
                .mask => .{ .key = field.key, .value = .{ .string = mask } },
            };
        }
        return field;
    }

    /// Compacts retained fields in caller-owned storage without allocation.
    pub fn applyInPlace(self: *const Redactor, input: []Field) []Field {
        var retained: usize = 0;
        for (input) |field| {
            if (self.apply(field)) |safe| {
                input[retained] = safe;
                retained += 1;
            }
        }
        // Clear references to discarded originals in the unused tail.
        for (input[retained..]) |*field| field.* = .{ .key = "", .value = .null_value };
        return input[0..retained];
    }

    /// Rebuilds container views in caller storage before producer capture.
    /// Member keys and retained scalar byte slices remain borrowed; arrays and
    /// groups point only into scratch. Input trees must not overlap scratch.
    /// max_value_nodes slots in each arena suffice for any validated tree.
    /// Unused storage and all storage on failure are cleared of stale views.
    pub fn applyDeep(self: *const Redactor, input: []const Field, field_scratch: []Field, value_scratch: []Value) DeepError![]Field {
        errdefer clearScratch(field_scratch, value_scratch);
        try fields.validateFields(input);
        var copier: DeepCopier = .{
            .redactor = self,
            .field_scratch = field_scratch,
            .value_scratch = value_scratch,
        };
        const safe = try copier.copyFields(input);
        clearScratch(field_scratch[copier.fields_used..], value_scratch[copier.values_used..]);
        return safe;
    }

    /// Preserves every top-level formatting argument slot and its key. Key
    /// rules apply only to members of groups inside argument values, so a
    /// dropped member cannot renumber arguments or change template selectors.
    /// The caller validates attributes and arguments together before redaction
    /// to enforce the original event's shared node budget.
    pub fn applyArgumentsDeep(self: *const Redactor, input: []const Field, field_scratch: []Field, value_scratch: []Value) DeepError![]Field {
        errdefer clearScratch(field_scratch, value_scratch);
        var validator: fields.ValueValidator = .{};
        try validator.arguments(input);
        var copier: DeepCopier = .{
            .redactor = self,
            .field_scratch = field_scratch,
            .value_scratch = value_scratch,
        };
        const safe = try copier.copyArguments(input);
        clearScratch(field_scratch[copier.fields_used..], value_scratch[copier.values_used..]);
        return safe;
    }

    fn put(self: *Redactor, rule: Rule) InitError!void {
        if (rule.key.len == 0) return error.EmptyKey;
        for (self.rules[0..self.rule_count]) |*stored| {
            const key = self.key_bytes[stored.offset..][0..stored.len];
            if (std.mem.eql(u8, key, rule.key)) {
                stored.action = rule.action;
                return;
            }
        }
        if (self.rule_count == max_rules) return error.TooManyRules;
        if (rule.key.len > max_key_bytes - self.key_bytes_used) return error.KeyBudgetExceeded;
        self.rules[self.rule_count] = .{
            .offset = @intCast(self.key_bytes_used),
            .len = @intCast(rule.key.len),
            .action = rule.action,
        };
        @memcpy(self.key_bytes[self.key_bytes_used..][0..rule.key.len], rule.key);
        self.key_bytes_used += rule.key.len;
        self.rule_count += 1;
    }
};

fn clearScratch(field_scratch: []Field, value_scratch: []Value) void {
    for (field_scratch) |*field| field.* = .{ .key = "", .value = .null_value };
    for (value_scratch) |*value| value.* = .null_value;
}

const DeepCopier = struct {
    redactor: *const Redactor,
    field_scratch: []Field,
    value_scratch: []Value,
    fields_used: usize = 0,
    values_used: usize = 0,

    fn copyArguments(self: *DeepCopier, input: []const Field) DeepError![]Field {
        if (input.len > self.field_scratch.len - self.fields_used) return error.ScratchTooSmall;
        const start = self.fields_used;
        self.fields_used += input.len;
        for (input, 0..) |argument, index| {
            self.field_scratch[start + index] = .{ .key = argument.key, .value = try self.copyValue(argument.value) };
        }
        return self.field_scratch[start..][0..input.len];
    }

    fn copyFields(self: *DeepCopier, input: []const Field) DeepError![]Field {
        if (input.len > self.field_scratch.len - self.fields_used) return error.ScratchTooSmall;
        const start = self.fields_used;
        // Reserve all sibling slots before descendants, so retained siblings
        // remain contiguous even when a group allocates further field views.
        self.fields_used += input.len;
        var retained: usize = 0;
        for (input) |field| {
            if (self.redactor.apply(field)) |safe| {
                self.field_scratch[start + retained] = .{ .key = safe.key, .value = try self.copyValue(safe.value) };
                retained += 1;
            }
        }
        clearScratch(self.field_scratch[start + retained .. start + input.len], &.{});
        return self.field_scratch[start..][0..retained];
    }

    fn copyValue(self: *DeepCopier, value: Value) DeepError!Value {
        return switch (value) {
            .group => |members| .{ .group = try self.copyFields(members) },
            .array => |items| blk: {
                if (items.len > self.value_scratch.len - self.values_used) return error.ScratchTooSmall;
                const start = self.values_used;
                self.values_used += items.len;
                for (items, 0..) |item, index| self.value_scratch[start + index] = try self.copyValue(item);
                break :blk .{ .array = self.value_scratch[start..][0..items.len] };
            },
            else => value,
        };
    }
};

test "drop, mask, exact keys, and mandatory secret replacement" {
    const redactor = try Redactor.init(&.{
        .{ .key = "password", .action = .mask },
        .{ .key = "token", .action = .drop },
    });
    try std.testing.expect(redactor.apply(fields.kv("token", "never capture")) == null);
    const hidden = redactor.apply(fields.kv("password", "password-value")).?;
    try std.testing.expectEqualStrings(mask, hidden.value.string);
    const ordinary = redactor.apply(fields.kv("password_hint", "visible")).?;
    try std.testing.expectEqualStrings("visible", ordinary.value.string);
    const secret = redactor.apply(fields.kv("unmatched_key", fields.secret("raw-secret"))).?;
    try std.testing.expectEqualStrings(mask, secret.value.string);
}

test "policy snapshots own keys and duplicate last wins" {
    var key = "credential".*;
    const redactor = try Redactor.init(&.{
        .{ .key = &key, .action = .drop },
        .{ .key = &key, .action = .mask },
    });
    @memset(&key, 'x');
    const copied = redactor;
    try std.testing.expectEqual(@as(usize, 1), copied.rule_count);
    try std.testing.expectEqualStrings(mask, copied.apply(fields.kv("credential", "raw")).?.value.string);
    try std.testing.expectError(error.EmptyKey, Redactor.init(&.{.{ .key = "", .action = .drop }}));
}

test "in-place redaction removes original references from storage" {
    const redactor = try Redactor.init(&.{
        .{ .key = "token", .action = .drop },
        .{ .key = "password", .action = .mask },
    });
    var input = [_]Field{
        fields.kv("token", "drop-original"),
        fields.kv("user", "alice"),
        fields.kv("password", "mask-original"),
    };
    const safe = redactor.applyInPlace(&input);
    try std.testing.expectEqual(@as(usize, 2), safe.len);
    try std.testing.expectEqualStrings("user", safe[0].key);
    try std.testing.expectEqualStrings("alice", safe[0].value.string);
    try std.testing.expectEqualStrings(mask, safe[1].value.string);
    try std.testing.expectEqualStrings("", input[2].key);
    try std.testing.expectEqual(fields.Value.null_value, input[2].value);
}

test "redaction key and rule budgets are fixed" {
    var key: [max_key_bytes + 1]u8 = undefined;
    @memset(&key, 'k');
    const full = try Redactor.init(&.{.{ .key = key[0..max_key_bytes], .action = .mask }});
    try std.testing.expectEqual(@as(usize, max_key_bytes), full.key_bytes_used);
    try std.testing.expectError(error.KeyBudgetExceeded, Redactor.init(&.{.{ .key = &key, .action = .drop }}));
    var names: [max_rules + 1][8]u8 = undefined;
    var rules: [max_rules + 1]Rule = undefined;
    for (&rules, 0..) |*rule, i| {
        rule.* = .{ .key = try std.fmt.bufPrint(&names[i], "k{d}", .{i}), .action = .mask };
    }
    const bounded = try Redactor.init(rules[0..max_rules]);
    try std.testing.expectEqual(@as(usize, max_rules), bounded.rule_count);
    try std.testing.expectError(error.TooManyRules, Redactor.init(&rules));
}

test "deep redaction rebuilds immutable arrays and groups and clears all unused views" {
    const redactor = try Redactor.init(&.{
        .{ .key = "token", .action = .drop },
        .{ .key = "password", .action = .mask },
        .{ .key = "literal.key", .action = .mask },
    });
    const members = [_]Field{
        fields.kv("token", "drop-original"),
        fields.kv("password", "mask-original"),
        fields.kv("literal.key", "literal-original"),
        fields.kv("keep", fields.secret("secret-original")),
    };
    const items = [_]Value{ fields.fromAny(fields.group(&members)), fields.fromAny("public") };
    const input = [_]Field{
        fields.kv("root", fields.array(&items)),
        fields.kv("token", fields.group(&members)),
    };
    var field_scratch = [_]Field{fields.kv("stale", "stale-original")} ** fields.max_value_nodes;
    var value_scratch = [_]Value{.{ .string = "stale-original" }} ** fields.max_value_nodes;
    const safe = try redactor.applyDeep(&input, &field_scratch, &value_scratch);
    try std.testing.expectEqual(@as(usize, 1), safe.len);
    const retained = safe[0].value.array[0].group;
    try std.testing.expectEqual(@as(usize, 3), retained.len);
    try std.testing.expectEqualStrings("password", retained[0].key);
    for (retained) |member| try std.testing.expectEqualStrings(mask, member.value.string);
    try std.testing.expectEqualStrings("public", safe[0].value.array[1].string);
    try std.testing.expect(safe[0].value.array.ptr != items[0..].ptr);
    try std.testing.expect(retained.ptr != members[0..].ptr);
    try std.testing.expectEqualStrings("drop-original", members[0].value.string);
    try std.testing.expectEqualStrings("mask-original", members[1].value.string);
    // Reserved dropped sibling slots and all tail slots carry no originals.
    try std.testing.expectEqualStrings("", field_scratch[1].key);
    try std.testing.expect(field_scratch[1].value == .null_value);
    for (field_scratch[5..]) |member| {
        try std.testing.expectEqualStrings("", member.key);
        try std.testing.expect(member.value == .null_value);
    }
    for (value_scratch[2..]) |value| try std.testing.expect(value == .null_value);
}

test "deep redaction clears partial results after scratch or validation failure" {
    const redactor = try Redactor.init(&.{});
    const input = [_]Field{fields.kv("group", fields.group(&.{fields.kv("key", "original")}))};
    var field_scratch = [_]Field{fields.kv("stale", "original")};
    var value_scratch = [_]Value{.{ .string = "original" }};
    try std.testing.expectError(error.ScratchTooSmall, redactor.applyDeep(&input, &field_scratch, &value_scratch));
    try std.testing.expect(field_scratch[0].value == .null_value);
    try std.testing.expectEqualStrings("", field_scratch[0].key);
    try std.testing.expect(value_scratch[0] == .null_value);
    var cyclic: [1]Value = undefined;
    cyclic[0] = .{ .array = &cyclic };
    try std.testing.expectError(error.CyclicValue, redactor.applyDeep(&.{fields.kv("cycle", fields.array(&cyclic))}, &field_scratch, &value_scratch));
    try std.testing.expect(field_scratch[0].value == .null_value);
    try std.testing.expect(value_scratch[0] == .null_value);
    try std.testing.expectEqualStrings("original", input[0].value.group[0].value.string);
}

test "argument redaction preserves top slots and applies rules inside all containers" {
    const redactor = try Redactor.init(&.{
        .{ .key = "token", .action = .drop },
        .{ .key = "password", .action = .mask },
    });
    const members = [_]Field{ fields.kv("token", "nested-token-original"), fields.kv("password", "nested-password-original") };
    const args = [_]Field{
        fields.kv("token", "top-public"),
        fields.kv("", fields.group(&members)),
        fields.kv("", fields.array(&.{fields.fromAny(fields.group(&members))})),
    };
    var field_scratch: [fields.max_value_nodes]Field = undefined;
    var value_scratch: [fields.max_value_nodes]Value = undefined;
    const safe = try redactor.applyArgumentsDeep(&args, &field_scratch, &value_scratch);
    try std.testing.expectEqual(@as(usize, args.len), safe.len);
    try std.testing.expectEqualStrings("token", safe[0].key);
    try std.testing.expectEqualStrings("top-public", safe[0].value.string);
    try std.testing.expectEqualStrings("", safe[1].key);
    try std.testing.expectEqualStrings("", safe[2].key);
    try std.testing.expectEqual(@as(usize, 1), safe[1].value.group.len);
    try std.testing.expectEqualStrings(mask, safe[1].value.group[0].value.string);
    try std.testing.expectEqual(@as(usize, 1), safe[2].value.array[0].group.len);
    try std.testing.expectEqualStrings(mask, safe[2].value.array[0].group[0].value.string);
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try @import("../submit/format.zig").render("{s} {any} {any}", safe, &writer);
    try std.testing.expectEqualStrings("top-public {\"password\":\"[REDACTED]\"} [{\"password\":\"[REDACTED]\"}]", writer.buffered());
    try std.testing.expectEqualStrings("nested-token-original", members[0].value.string);
    try std.testing.expectEqualStrings("nested-password-original", members[1].value.string);
}
