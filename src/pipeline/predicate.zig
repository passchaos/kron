//! Fixed-budget delivery predicates. Compile configuration before publication;
//! evaluate before acceptance. Matching never allocates or renders logf bodies.
//! Field keys are exact byte strings; only explicit path segments traverse groups.
const std = @import("std");
const fields = @import("../core/field.zig");
const Event = @import("../core/event.zig").Event;
const Value = fields.Value;

pub const max_rules = 64;
pub const max_storage_bytes = 8192;
pub const max_regex_states = 128;
pub const max_regex_input_bytes = 8192;
pub const max_path_segments = 8;
pub const Operator = enum { exists, eq, ne, lt, le, gt, ge, prefix, contains, pattern };
pub const Target = enum { field, scope, level, message, rendered_message };
pub const Rule = struct {
    key: []const u8 = "",
    operator: Operator,
    value: Value = .null_value,
    target: Target = .field,
    path: ?[]const []const u8 = null,
};
pub const CompileError = error{ TooManyRules, StorageExhausted, InvalidType, InvalidSyntax, InvalidPath, InvalidRegex, UnsupportedRegex, TooManyRegexStates, RegexNestingTooDeep };
pub const MatchError = error{InputTooLong};
pub const Diagnostic = struct { err: CompileError, offset: usize };
pub const ParseResult = union(enum) { predicate: Predicate, diagnostic: Diagnostic };

const Slice = struct { offset: u16 = 0, length: u16 = 0 };
const StoredValue = union(enum) { null_value, boolean: bool, signed: i128, unsigned: u128, float: f64, string: Slice, bytes: Slice, duration_ns: i64, timestamp_ns: i64 };
const CompiledRule = struct {
    key: Slice,
    operator: Operator,
    target: Target,
    value: StoredValue,
    path: [max_path_segments]Slice = undefined,
    path_len: u8 = 0,
    regex: ?Regex = null,
};

/// Contains only fixed arrays and relative offsets, so returning/copying this
/// value never retains pointers to temporary configuration storage.
pub const Predicate = struct {
    storage: [max_storage_bytes]u8 = undefined,
    storage_len: usize = 0,
    rules: [max_rules]CompiledRule = undefined,
    rule_count: usize = 0,
    states: [max_regex_states]State = undefined,
    state_count: usize = 0,

    pub fn init(rules: []const Rule) CompileError!Predicate {
        var result: Predicate = .{};
        for (rules) |rule| try result.append(rule);
        return result;
    }

    pub fn parse(spec: []const u8) CompileError!Predicate {
        return switch (parseDiagnostic(spec)) {
            .predicate => |predicate| predicate,
            .diagnostic => |diagnostic| diagnostic.err,
        };
    }

    /// AND-only grammar: key >= 500 && tenant == "prod". Metadata uses @scope,
    /// @level, @message, @rendered_message. exists(key), ^= (prefix), *=
    /// (contains), and =~ (regex) are supported. A dotted key stays literal.
    pub fn parseDiagnostic(spec: []const u8) ParseResult {
        var result: Predicate = .{};
        var parser: SpecParser = .{ .input = spec, .predicate = &result };
        parser.parse() catch |err| return .{ .diagnostic = .{ .err = err, .offset = parser.index } };
        return .{ .predicate = result };
    }

    fn append(self: *Predicate, rule: Rule) CompileError!void {
        if (self.rule_count == max_rules) return error.TooManyRules;
        if (rule.path != null and rule.target != .field) return error.InvalidPath;
        switch (rule.operator) {
            .exists => {},
            .prefix, .contains, .pattern => if (rule.value != .string and rule.value != .bytes) return error.InvalidType,
            .lt, .le, .gt, .ge => if (!isNumber(rule.value)) return error.InvalidType,
            .eq, .ne => if (rule.value == .array or rule.value == .group) return error.InvalidType,
        }
        var compiled: CompiledRule = .{ .key = try self.copy(rule.key), .operator = rule.operator, .target = rule.target, .value = try self.storeValue(rule.value) };
        if (rule.path) |path| {
            if (path.len == 0 or path.len > max_path_segments) return error.InvalidPath;
            for (path, 0..) |segment, index| {
                if (segment.len == 0) return error.InvalidPath;
                compiled.path[index] = try self.copy(segment);
            }
            compiled.path_len = @intCast(path.len);
        }
        if (rule.operator == .pattern) {
            const pattern = switch (rule.value) {
                .string, .bytes => |value| value,
                else => unreachable,
            };
            var compiler: RegexCompiler = .{ .input = pattern, .states = &self.states, .count = &self.state_count };
            compiled.regex = try compiler.compile();
        }
        self.rules[self.rule_count] = compiled;
        self.rule_count += 1;
    }

    fn copy(self: *Predicate, bytes: []const u8) CompileError!Slice {
        if (bytes.len > self.storage.len - self.storage_len) return error.StorageExhausted;
        const result: Slice = .{ .offset = @intCast(self.storage_len), .length = @intCast(bytes.len) };
        @memcpy(self.storage[self.storage_len..][0..bytes.len], bytes);
        self.storage_len += bytes.len;
        return result;
    }

    fn slice(self: *const Predicate, bytes: Slice) []const u8 {
        return self.storage[bytes.offset..][0..bytes.length];
    }

    fn storeValue(self: *Predicate, value: Value) CompileError!StoredValue {
        return switch (value) {
            .null_value => .null_value,
            .boolean => |v| .{ .boolean = v },
            .signed => |v| .{ .signed = v },
            .unsigned => |v| .{ .unsigned = v },
            .float => |v| .{ .float = v },
            .string => |v| .{ .string = try self.copy(v) },
            .bytes => |v| .{ .bytes = try self.copy(v) },
            .duration_ns => |v| .{ .duration_ns = v },
            .timestamp_ns => |v| .{ .timestamp_ns = v },
            .array, .group => error.InvalidType,
        };
    }

    fn loadValue(self: *const Predicate, stored: StoredValue) Value {
        return switch (stored) {
            .null_value => .null_value,
            .boolean => |v| .{ .boolean = v },
            .signed => |v| .{ .signed = v },
            .unsigned => |v| .{ .unsigned = v },
            .float => |v| .{ .float = v },
            .string => |v| .{ .string = self.slice(v) },
            .bytes => |v| .{ .bytes = self.slice(v) },
            .duration_ns => |v| .{ .duration_ns = v },
            .timestamp_ns => |v| .{ .timestamp_ns = v },
        };
    }

    pub fn matches(self: *const Predicate, event: Event) MatchError!bool {
        for (self.rules[0..self.rule_count]) |rule| {
            const actual = self.lookup(rule, event) orelse return false;
            if (rule.operator == .exists) continue;
            const expected = self.loadValue(rule.value);
            const matched = switch (rule.operator) {
                .exists => unreachable,
                .eq, .ne, .lt, .le, .gt, .ge => compare(actual, expected, rule.operator),
                .prefix, .contains, .pattern => blk: {
                    const bytes = switch (actual) {
                        .string, .bytes => |v| v,
                        else => break :blk false,
                    };
                    const pattern = switch (expected) {
                        .string, .bytes => |v| v,
                        else => unreachable,
                    };
                    break :blk switch (rule.operator) {
                        .prefix => std.mem.startsWith(u8, bytes, pattern),
                        .contains => std.mem.find(u8, bytes, pattern) != null,
                        .pattern => try rule.regex.?.matches(self.states[0..self.state_count], bytes),
                        else => unreachable,
                    };
                },
            };
            if (!matched) return false;
        }
        return true;
    }

    /// Compares only initialized configuration. The unused tails of fixed
    /// arrays are undefined and must never join recovery compatibility checks.
    pub fn eql(self: *const Predicate, other: *const Predicate) bool {
        if (self.rule_count != other.rule_count or self.storage_len != other.storage_len or self.state_count != other.state_count) return false;
        if (!std.mem.eql(u8, self.storage[0..self.storage_len], other.storage[0..other.storage_len])) return false;
        for (self.rules[0..self.rule_count], other.rules[0..other.rule_count]) |left, right| {
            if (left.operator != right.operator or left.target != right.target or !std.meta.eql(left.key, right.key) or left.path_len != right.path_len or !std.meta.eql(left.regex, right.regex)) return false;
            if (std.meta.activeTag(left.value) != std.meta.activeTag(right.value)) return false;
            const same_value = switch (left.value) {
                .float => |number| @as(u64, @bitCast(number)) == @as(u64, @bitCast(right.value.float)),
                else => std.meta.eql(left.value, right.value),
            };
            if (!same_value) return false;
            for (left.path[0..left.path_len], right.path[0..right.path_len]) |a, b| if (!std.meta.eql(a, b)) return false;
        }
        for (self.states[0..self.state_count], other.states[0..other.state_count]) |a, b| if (!std.meta.eql(a, b)) return false;
        return true;
    }

    fn lookup(self: *const Predicate, rule: CompiledRule, event: Event) ?Value {
        switch (rule.target) {
            .scope => return .{ .string = event.scope },
            .level => return .{ .string = @tagName(event.level) },
            .message => return .{ .string = event.message },
            // Deferred rendering is never performed in a delivery predicate.
            // Explicit preencoded events carry the rendered message already.
            .rendered_message => return if (event.message_template) null else .{ .string = event.message },
            .field => {},
        }
        if (rule.path_len == 0) return find(event.fields, self.slice(rule.key));
        var group = event.fields;
        for (rule.path[0..rule.path_len], 0..) |segment, index| {
            const found = find(group, self.slice(segment)) orelse return null;
            if (index + 1 == rule.path_len) return found;
            group = switch (found) {
                .group => |nested| nested,
                else => return null,
            };
        }
        return null;
    }
};

fn find(group: []const fields.Field, key: []const u8) ?Value {
    for (group) |field| if (std.mem.eql(u8, field.key, key)) return field.value;
    return null;
}

fn isNumber(value: Value) bool {
    return switch (value) {
        .signed, .unsigned, .float, .duration_ns, .timestamp_ns => true,
        else => false,
    };
}

fn compare(left: Value, right: Value, operator: Operator) bool {
    if (left == .array or left == .group or right == .array or right == .group) return false;
    if ((left == .float and std.math.isNan(left.float)) or (right == .float and std.math.isNan(right.float))) return false;
    const order = numericOrder(left, right) orelse blk: {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
        break :blk switch (left) {
            .null_value => std.math.Order.eq,
            .boolean => |v| std.math.order(@intFromBool(v), @intFromBool(right.boolean)),
            .string => |v| std.mem.order(u8, v, right.string),
            .bytes => |v| std.mem.order(u8, v, right.bytes),
            else => return false,
        };
    };
    return switch (operator) {
        .eq => order == .eq,
        .ne => order != .eq,
        .lt => order == .lt,
        .le => order != .gt,
        .gt => order == .gt,
        .ge => order != .lt,
        else => false,
    };
}

const Integer = struct { negative: bool, magnitude: u128 };
fn asInteger(value: Value) ?Integer {
    return switch (value) {
        .signed => |v| .{ .negative = v < 0, .magnitude = @abs(v) },
        .unsigned => |v| .{ .negative = false, .magnitude = v },
        else => null,
    };
}

fn numericOrder(left: Value, right: Value) ?std.math.Order {
    // Nanosecond wrappers keep their unit/type: duration and timestamp do not
    // become interchangeable with generic integer attributes.
    if (left == .duration_ns) return if (right == .duration_ns) std.math.order(left.duration_ns, right.duration_ns) else null;
    if (left == .timestamp_ns) return if (right == .timestamp_ns) std.math.order(left.timestamp_ns, right.timestamp_ns) else null;
    if (left == .float) {
        if (right == .float) return std.math.order(left.float, right.float);
        if (asInteger(right)) |integer| return integerFloatOrder(integer, left.float).invert();
        return null;
    }
    const integer = asInteger(left) orelse return null;
    if (right == .float) return integerFloatOrder(integer, right.float);
    const other = asInteger(right) orelse return null;
    if (integer.negative != other.negative) return if (integer.negative) .lt else .gt;
    const order = std.math.order(integer.magnitude, other.magnitude);
    return if (integer.negative) order.invert() else order;
}

/// Compare to a float's exact binary value, without rounding a large integer
/// through f64. Fractional parts and exponents outside u128 are handled directly.
fn integerFloatOrder(integer: Integer, number: f64) std.math.Order {
    const negative = number < 0;
    if (integer.negative != negative) return if (integer.negative) .lt else .gt;
    const bits: u64 = @bitCast(@abs(number));
    const exponent: i32 = @as(i32, @intCast((bits >> 52) & 0x7ff)) - 1023;
    var order: std.math.Order = undefined;
    if (std.math.isInf(number) or exponent >= 128) {
        order = .lt;
    } else if (number == 0) {
        order = std.math.order(integer.magnitude, @as(u128, 0));
    } else if (exponent < 0) {
        order = if (integer.magnitude == 0) .lt else .gt;
    } else {
        const mantissa: u128 = (bits & ((@as(u64, 1) << 52) - 1)) | (@as(u64, 1) << 52);
        var whole: u128 = undefined;
        var fractional = false;
        if (exponent >= 52) {
            whole = mantissa << @as(u7, @intCast(exponent - 52));
        } else {
            const shift: u7 = @intCast(52 - exponent);
            whole = mantissa >> shift;
            fractional = mantissa & ((@as(u128, 1) << shift) - 1) != 0;
        }
        order = std.math.order(integer.magnitude, whole);
        if (order == .eq and fractional) order = .lt;
    }
    return if (integer.negative) order.invert() else order;
}

const no_state: u8 = 255;
const no_patch: u16 = 65535;
const State = struct {
    op: enum { byte, any, class, split, jump, bol, eol, accept },
    out: u8 = no_state,
    out2: u8 = no_state,
    byte: u8 = 0,
    set: [32]u8 = @splat(0),
};

/// Byte-oriented regular expressions, compiled as a Thompson NFA. Search
/// injects a start state at each position and merges active states, avoiding
/// restart/backtracking behavior even for nested quantifiers and alternation.
pub const Regex = struct {
    start: u8,
    minimum_state: u8,
    state_count: u8,

    pub fn matches(self: Regex, states: []const State, input: []const u8) MatchError!bool {
        if (input.len > max_regex_input_bytes) return error.InputTooLong;
        var active: [max_regex_states]bool = @splat(false);
        var next: [max_regex_states]bool = @splat(false);
        for (0..input.len + 1) |position| {
            active[self.start] = true;
            self.closure(states, &active, position, input.len);
            for (self.minimum_state..@as(usize, self.minimum_state) + self.state_count) |index| if (active[index] and states[index].op == .accept) return true;
            if (position == input.len) break;
            @memset(&next, false);
            for (self.minimum_state..@as(usize, self.minimum_state) + self.state_count) |index| {
                if (!active[index]) continue;
                const state = states[index];
                const consumes = switch (state.op) {
                    .byte => state.byte == input[position],
                    .any => input[position] != '\n',
                    .class => state.set[input[position] >> 3] & (@as(u8, 1) << @as(u3, @truncate(input[position]))) != 0,
                    else => false,
                };
                if (consumes) next[state.out] = true;
            }
            active = next;
        }
        return false;
    }

    fn closure(self: Regex, states: []const State, active: *[max_regex_states]bool, position: usize, length: usize) void {
        var queue: [max_regex_states]u8 = undefined;
        var count: usize = 0;
        var cursor: usize = 0;
        var visited: [max_regex_states]bool = @splat(false);
        for (self.minimum_state..@as(usize, self.minimum_state) + self.state_count) |index| if (active[index]) {
            queue[count] = @intCast(index);
            count += 1;
            visited[index] = true;
        };
        while (cursor < count) : (cursor += 1) {
            const index = queue[cursor];
            const state = states[index];
            const follows = switch (state.op) {
                .split, .jump => true,
                .bol => position == 0,
                .eol => position == length,
                else => false,
            };
            if (!follows) continue;
            for ([_]u8{ state.out, if (state.op == .split) state.out2 else no_state }) |out| {
                if (out == no_state or visited[out]) continue;
                visited[out] = true;
                active[out] = true;
                queue[count] = out;
                count += 1;
            }
        }
    }
};

const Fragment = struct { start: u8, head: u16, tail: u16 };
const RegexCompiler = struct {
    input: []const u8,
    index: usize = 0,
    states: *[max_regex_states]State,
    count: *usize,
    depth: usize = 0,
    links: [max_regex_states * 2]u16 = @splat(no_patch),

    fn add(self: *RegexCompiler, state: State) CompileError!u8 {
        if (self.count.* == max_regex_states) return error.TooManyRegexStates;
        const index: u8 = @intCast(self.count.*);
        self.states[index] = state;
        self.count.* += 1;
        return index;
    }

    fn dangling(self: *RegexCompiler, start: u8, second: bool) Fragment {
        const patch_index: u16 = @as(u16, start) * 2 + @intFromBool(second);
        self.links[patch_index] = no_patch;
        return .{ .start = start, .head = patch_index, .tail = patch_index };
    }

    fn join(self: *RegexCompiler, first: Fragment, second: Fragment, start: u8) Fragment {
        self.links[first.tail] = second.head;
        return .{ .start = start, .head = first.head, .tail = second.tail };
    }

    fn patch(self: *RegexCompiler, fragment: Fragment, target: u8) void {
        var current = fragment.head;
        while (current != no_patch) {
            if (current & 1 == 0) self.states[current / 2].out = target else self.states[current / 2].out2 = target;
            current = self.links[current];
        }
    }

    fn compile(self: *RegexCompiler) CompileError!Regex {
        const minimum = self.count.*;
        const fragment = try self.alternate();
        if (self.index != self.input.len) return error.InvalidRegex;
        const accept = try self.add(.{ .op = .accept });
        self.patch(fragment, accept);
        return .{ .start = fragment.start, .minimum_state = @intCast(minimum), .state_count = @intCast(self.count.* - minimum) };
    }

    fn alternate(self: *RegexCompiler) CompileError!Fragment {
        var fragment = try self.concatenate();
        while (self.index < self.input.len and self.input[self.index] == '|') {
            self.index += 1;
            const other = try self.concatenate();
            const split = try self.add(.{ .op = .split, .out = fragment.start, .out2 = other.start });
            fragment = self.join(fragment, other, split);
        }
        return fragment;
    }

    fn concatenate(self: *RegexCompiler) CompileError!Fragment {
        var result: ?Fragment = null;
        while (self.index < self.input.len and self.input[self.index] != ')' and self.input[self.index] != '|') {
            const fragment = try self.quantified();
            if (result) |previous| {
                self.patch(previous, fragment.start);
                result = .{ .start = previous.start, .head = fragment.head, .tail = fragment.tail };
            } else result = fragment;
        }
        return result orelse self.dangling(try self.add(.{ .op = .jump }), false);
    }

    fn quantified(self: *RegexCompiler) CompileError!Fragment {
        var fragment = try self.atom();
        if (self.index < self.input.len) {
            const quantifier = self.input[self.index];
            if (quantifier == '*' or quantifier == '+' or quantifier == '?') {
                self.index += 1;
                const split = try self.add(.{ .op = .split, .out = fragment.start });
                const exit = self.dangling(split, true);
                switch (quantifier) {
                    '*' => {
                        self.patch(fragment, split);
                        fragment = exit;
                    },
                    '+' => {
                        self.patch(fragment, split);
                        fragment = .{ .start = fragment.start, .head = exit.head, .tail = exit.tail };
                    },
                    '?' => fragment = self.join(fragment, exit, split),
                    else => unreachable,
                }
                if (self.index < self.input.len and (self.input[self.index] == '*' or self.input[self.index] == '+' or self.input[self.index] == '?')) return error.InvalidRegex;
            }
        }
        return fragment;
    }

    fn atom(self: *RegexCompiler) CompileError!Fragment {
        if (self.index == self.input.len) return error.InvalidRegex;
        const byte = self.input[self.index];
        self.index += 1;
        if (byte == '(') {
            self.depth += 1;
            if (self.depth > 32) return error.RegexNestingTooDeep;
            const fragment = try self.alternate();
            self.depth -= 1;
            if (self.index == self.input.len or self.input[self.index] != ')') return error.InvalidRegex;
            self.index += 1;
            return fragment;
        }
        const state: State = switch (byte) {
            '.' => .{ .op = .any },
            '^' => .{ .op = .bol },
            '$' => .{ .op = .eol },
            '[' => try self.characterClass(),
            '\\' => blk: {
                const escaped = try self.escapeByte();
                break :blk .{ .op = .byte, .byte = escaped };
            },
            '*', '+', '?', ')' => return error.InvalidRegex,
            '{', '}' => return error.UnsupportedRegex,
            else => .{ .op = .byte, .byte = byte },
        };
        return self.dangling(try self.add(state), false);
    }

    fn escapeByte(self: *RegexCompiler) CompileError!u8 {
        if (self.index == self.input.len) return error.InvalidRegex;
        const byte = self.input[self.index];
        self.index += 1;
        return switch (byte) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '0'...'9', 'd', 'w', 's', 'b' => error.UnsupportedRegex,
            else => byte,
        };
    }

    fn characterClass(self: *RegexCompiler) CompileError!State {
        var result: State = .{ .op = .class };
        const negate = self.index < self.input.len and self.input[self.index] == '^';
        if (negate) self.index += 1;
        var count: usize = 0;
        while (self.index < self.input.len and self.input[self.index] != ']') {
            const start = try self.classByte();
            var end = start;
            if (self.index + 1 < self.input.len and self.input[self.index] == '-' and self.input[self.index + 1] != ']') {
                self.index += 1;
                end = try self.classByte();
                if (start > end) return error.InvalidRegex;
            }
            for (@as(usize, start)..@as(usize, end) + 1) |item| result.set[item >> 3] |= @as(u8, 1) << @as(u3, @truncate(item));
            count += 1;
        }
        if (self.index == self.input.len or count == 0) return error.InvalidRegex;
        self.index += 1;
        if (negate) {
            for (&result.set) |*byte| byte.* = ~byte.*;
        }
        return result;
    }

    fn classByte(self: *RegexCompiler) CompileError!u8 {
        const byte = self.input[self.index];
        self.index += 1;
        return if (byte == '\\') self.escapeByte() else byte;
    }
};

pub const Pattern = struct {
    states: [max_regex_states]State = undefined,
    state_count: usize = 0,
    regex: Regex = undefined,

    pub fn init(pattern: []const u8) CompileError!Pattern {
        var result: Pattern = .{};
        var compiler: RegexCompiler = .{ .input = pattern, .states = &result.states, .count = &result.state_count };
        result.regex = try compiler.compile();
        return result;
    }

    pub fn matches(self: *const Pattern, input: []const u8) MatchError!bool {
        return self.regex.matches(self.states[0..self.state_count], input);
    }
};

const SpecParser = struct {
    input: []const u8,
    index: usize = 0,
    predicate: *Predicate,
    string_buffer: [max_storage_bytes]u8 = undefined,

    fn whitespace(self: *SpecParser) void {
        while (self.index < self.input.len and std.ascii.isWhitespace(self.input[self.index])) self.index += 1;
    }

    fn parse(self: *SpecParser) CompileError!void {
        self.whitespace();
        if (self.index == self.input.len) return;
        while (true) {
            try self.rule();
            self.whitespace();
            if (self.index == self.input.len) return;
            if (!std.mem.startsWith(u8, self.input[self.index..], "&&")) return error.InvalidSyntax;
            self.index += 2;
            self.whitespace();
            if (self.index == self.input.len) return error.InvalidSyntax;
        }
    }

    fn key(self: *SpecParser) CompileError![]const u8 {
        self.whitespace();
        const start = self.index;
        while (self.index < self.input.len) {
            const byte = self.input[self.index];
            if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.' and byte != '-' and byte != '@' and byte != '/' and byte != ':') break;
            self.index += 1;
        }
        if (self.index == start) return error.InvalidSyntax;
        return self.input[start..self.index];
    }

    fn rule(self: *SpecParser) CompileError!void {
        self.whitespace();
        var exists = false;
        if (std.mem.startsWith(u8, self.input[self.index..], "exists(")) {
            self.index += 7;
            exists = true;
        }
        const name = try self.key();
        const target: Target = if (name[0] != '@') .field else if (std.mem.eql(u8, name, "@scope")) .scope else if (std.mem.eql(u8, name, "@level")) .level else if (std.mem.eql(u8, name, "@message")) .message else if (std.mem.eql(u8, name, "@rendered_message")) .rendered_message else return error.InvalidSyntax;
        self.whitespace();
        if (exists) {
            if (self.index == self.input.len or self.input[self.index] != ')') return error.InvalidSyntax;
            self.index += 1;
            try self.predicate.append(.{ .key = name, .operator = .exists, .target = target });
            return;
        }
        const start = self.index;
        const operators = [_]struct { text: []const u8, operator: Operator }{
            .{ .text = "==", .operator = .eq },      .{ .text = "!=", .operator = .ne },
            .{ .text = "<=", .operator = .le },      .{ .text = ">=", .operator = .ge },
            .{ .text = "^=", .operator = .prefix },  .{ .text = "*=", .operator = .contains },
            .{ .text = "=~", .operator = .pattern }, .{ .text = "<", .operator = .lt },
            .{ .text = ">", .operator = .gt },
        };
        for (operators) |operator| {
            if (std.mem.startsWith(u8, self.input[start..], operator.text)) {
                self.index += operator.text.len;
                const operand = try self.literal();
                try self.predicate.append(.{ .key = name, .operator = operator.operator, .value = operand, .target = target });
                return;
            }
        }
        return error.InvalidSyntax;
    }

    fn literal(self: *SpecParser) CompileError!Value {
        self.whitespace();
        if (self.index == self.input.len) return error.InvalidSyntax;
        if (self.input[self.index] == '"') return .{ .string = try self.string() };
        const start = self.index;
        while (self.index < self.input.len and !std.ascii.isWhitespace(self.input[self.index]) and self.input[self.index] != '&') self.index += 1;
        const token = self.input[start..self.index];
        if (std.mem.eql(u8, token, "true")) return .{ .boolean = true };
        if (std.mem.eql(u8, token, "false")) return .{ .boolean = false };
        if (std.mem.eql(u8, token, "null")) return .null_value;
        if (std.mem.startsWith(u8, token, "duration_ns:")) return .{ .duration_ns = std.fmt.parseInt(i64, token[12..], 0) catch return error.InvalidSyntax };
        if (std.mem.startsWith(u8, token, "timestamp_ns:")) return .{ .timestamp_ns = std.fmt.parseInt(i64, token[13..], 0) catch return error.InvalidSyntax };
        if (token.len == 0) return error.InvalidSyntax;
        if (std.mem.findAny(u8, token, ".eE") != null and !std.mem.startsWith(u8, token, "0x") and !std.mem.startsWith(u8, token, "-0x")) return .{ .float = std.fmt.parseFloat(f64, token) catch return error.InvalidSyntax };
        if (token[0] == '-') return .{ .signed = std.fmt.parseInt(i128, token, 0) catch return error.InvalidSyntax };
        return .{ .unsigned = std.fmt.parseInt(u128, token, 0) catch return error.InvalidSyntax };
    }

    fn string(self: *SpecParser) CompileError![]const u8 {
        self.index += 1;
        var count: usize = 0;
        while (self.index < self.input.len) {
            var byte = self.input[self.index];
            self.index += 1;
            if (byte == '"') {
                if (!std.unicode.utf8ValidateSlice(self.string_buffer[0..count])) return error.InvalidSyntax;
                return self.string_buffer[0..count];
            }
            if (byte < 0x20) return error.InvalidSyntax;
            if (byte == '\\') {
                if (self.index == self.input.len) return error.InvalidSyntax;
                byte = self.input[self.index];
                self.index += 1;
                byte = switch (byte) {
                    '"', '\\', '/' => byte,
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    'b' => 8,
                    'f' => 12,
                    'x' => blk: {
                        if (self.input.len - self.index < 2) return error.InvalidSyntax;
                        const result = std.fmt.parseInt(u8, self.input[self.index..][0..2], 16) catch return error.InvalidSyntax;
                        self.index += 2;
                        break :blk result;
                    },
                    else => return error.InvalidSyntax,
                };
            }
            if (count == self.string_buffer.len) return error.StorageExhausted;
            self.string_buffer[count] = byte;
            count += 1;
        }
        return error.InvalidSyntax;
    }
};

fn testEvent(values: []const fields.Field) Event {
    return .{ .level = .warn, .scope = "http.server", .message = "request failed", .fields = values, .timestamp_ns = 0 };
}

test "predicate AND parser metadata fields strings and diagnostics" {
    const predicate = try Predicate.parse("status >= 500 && tenant == \"prod\" && exists(request.id) && @scope ^= \"http.\" && @level == \"warn\" && @message *= \"failed\"");
    try std.testing.expect(try predicate.matches(testEvent(&.{ fields.kv("status", 503), fields.kv("tenant", "prod"), fields.kv("request.id", "id") })));
    try std.testing.expect(!try predicate.matches(testEvent(&.{ fields.kv("status", 404), fields.kv("tenant", "prod"), fields.kv("request.id", "id") })));
    try std.testing.expect(!try predicate.matches(testEvent(&.{ fields.kv("status", 503), fields.kv("tenant", "prod") })));
    const result = Predicate.parseDiagnostic("status >=");
    try std.testing.expect(result == .diagnostic);
    try std.testing.expectEqual(error.InvalidSyntax, result.diagnostic.err);
    try std.testing.expectEqual(@as(usize, 9), result.diagnostic.offset);
    try std.testing.expectError(error.InvalidSyntax, Predicate.parse("a==1 || b==2"));
    try std.testing.expectError(error.InvalidType, Predicate.parse("a ^= 10"));
    try std.testing.expect(try (try Predicate.parse(" ")).matches(testEvent(&.{})));
}

test "predicate exact integer float comparisons preserve 128-bit boundaries" {
    const cases = [_]struct { left: Value, right: Value, order: std.math.Order }{
        .{ .left = .{ .signed = std.math.minInt(i128) }, .right = .{ .unsigned = 0 }, .order = .lt },
        .{ .left = .{ .unsigned = std.math.maxInt(u128) }, .right = .{ .signed = std.math.maxInt(i128) }, .order = .gt },
        .{ .left = .{ .unsigned = 9007199254740993 }, .right = .{ .float = 9007199254740992.0 }, .order = .gt },
        .{ .left = .{ .signed = -9007199254740993 }, .right = .{ .float = -9007199254740992.0 }, .order = .lt },
        .{ .left = .{ .unsigned = 1 }, .right = .{ .float = 1.5 }, .order = .lt },
        .{ .left = .{ .signed = -1 }, .right = .{ .float = -1.5 }, .order = .gt },
        .{ .left = .{ .unsigned = 0 }, .right = .{ .float = -0.0 }, .order = .eq },
        .{ .left = .{ .unsigned = std.math.maxInt(u128) }, .right = .{ .float = 0x1p128 }, .order = .lt },
        .{ .left = .{ .signed = std.math.minInt(i128) }, .right = .{ .float = -0x1p127 }, .order = .eq },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.order, numericOrder(case.left, case.right).?);
        try std.testing.expectEqual(case.order.invert(), numericOrder(case.right, case.left).?);
    }
    for ([_]Operator{ .eq, .ne, .lt, .le, .gt, .ge }) |operator| {
        const predicate = try Predicate.init(&.{.{ .key = "number", .operator = operator, .value = .{ .float = std.math.nan(f64) } }});
        try std.testing.expect(!try predicate.matches(testEvent(&.{fields.kv("number", 1)})));
    }
    try std.testing.expectError(error.InvalidSyntax, Predicate.parse("n == 340282366920938463463374607431768211456"));
}

test "predicate explicit group paths and literal dotted keys have distinct behavior" {
    const grouped: Value = .{ .group = &.{fields.kv("status", 503)} };
    const value = testEvent(&.{ fields.kv("http", grouped), fields.kv("http.status", 200), fields.kv("array", fields.Value{ .array = &.{.null_value} }) });
    const literal = try Predicate.init(&.{.{ .key = "http.status", .operator = .eq, .value = .{ .unsigned = 200 } }});
    const explicit = try Predicate.init(&.{.{ .path = &.{ "http", "status" }, .operator = .ge, .value = .{ .unsigned = 500 } }});
    try std.testing.expect(try literal.matches(value));
    try std.testing.expect(try explicit.matches(value));
    const wrong = try Predicate.init(&.{.{ .path = &.{ "http.status", "value" }, .operator = .exists }});
    try std.testing.expect(!try wrong.matches(value));
    const aggregate = try Predicate.init(&.{.{ .key = "array", .operator = .eq, .value = .null_value }});
    try std.testing.expect(!try aggregate.matches(value));
}

test "predicate absent null primitive types and deferred messages have explicit semantics" {
    const null_predicate = try Predicate.parse("value == null");
    try std.testing.expect(try null_predicate.matches(testEvent(&.{fields.kv("value", null)})));
    try std.testing.expect(!try null_predicate.matches(testEvent(&.{})));
    const missing_ne = try Predicate.parse("missing != 1");
    try std.testing.expect(!try missing_ne.matches(testEvent(&.{})));
    const units = try Predicate.parse("duration >= duration_ns:12 && timestamp == timestamp_ns:20");
    try std.testing.expect(try units.matches(testEvent(&.{ fields.kv("duration", fields.durationNs(12)), fields.kv("timestamp", fields.timestampNs(20)) })));
    const rendered = try Predicate.parse("@rendered_message *= \"failed\"");
    var deferred = testEvent(&.{});
    deferred.message = "request {s}";
    deferred.message_template = true;
    deferred.format_args = &.{fields.kv("", "failed")};
    try std.testing.expect(!try rendered.matches(deferred));
    const template = try Predicate.parse("@message *= \"{s}\"");
    try std.testing.expect(try template.matches(deferred));
    deferred.message_template = false;
    deferred.message = "request failed";
    try std.testing.expect(try rendered.matches(deferred));
}

test "Thompson regex supports alternation groups classes anchors and quantifiers" {
    const cases = [_]struct { pattern: []const u8, input: []const u8, expected: bool }{
        .{ .pattern = "^(warn|error): [a-z]+[0-9]?$", .input = "error: failed7", .expected = true },
        .{ .pattern = "^(warn|error): [a-z]+[0-9]?$", .input = "info: failed7", .expected = false },
        .{ .pattern = "ab*c", .input = "xxabbbcxx", .expected = true },
        .{ .pattern = "ab+c", .input = "ac", .expected = false },
        .{ .pattern = "ab?c", .input = "ac", .expected = true },
        .{ .pattern = "a.c", .input = "a\nc", .expected = false },
        .{ .pattern = "a[^x-z]c", .input = "abc", .expected = true },
        .{ .pattern = "^$", .input = "", .expected = true },
        .{ .pattern = "^a$", .input = "ba", .expected = false },
        .{ .pattern = "a|", .input = "", .expected = true },
        .{ .pattern = "\\[a\\]", .input = "[a]", .expected = true },
    };
    for (cases) |case| {
        const pattern = try Pattern.init(case.pattern);
        try std.testing.expectEqual(case.expected, try pattern.matches(case.input));
    }
    const predicate = try Predicate.parse("@message =~ \"(failed|timeout)$\"");
    try std.testing.expect(try predicate.matches(testEvent(&.{})));
    try std.testing.expectError(error.UnsupportedRegex, Pattern.init("(a)\\1"));
    try std.testing.expectError(error.UnsupportedRegex, Pattern.init("a{2}"));
    try std.testing.expectError(error.InvalidRegex, Pattern.init("a**"));
    try std.testing.expectError(error.InvalidRegex, Pattern.init("[z-a]"));
    try std.testing.expectError(error.InvalidRegex, Pattern.init("(abc"));
}

test "regex worst-case nested quantifiers use fixed states and bounded input" {
    const pattern = try Pattern.init("^(a+)+b$");
    const long = [_]u8{'a'} ** max_regex_input_bytes;
    try std.testing.expect(!try pattern.matches(&long));
    const alternation = try Pattern.init("^(a|aa)*b$");
    try std.testing.expect(!try alternation.matches(&long));
    const excessive = [_]u8{'a'} ** (max_regex_input_bytes + 1);
    try std.testing.expectError(error.InputTooLong, alternation.matches(&excessive));
    const too_many = [_]u8{'a'} ** max_regex_states;
    try std.testing.expectError(error.TooManyRegexStates, Pattern.init(&too_many));
    const nesting = "(" ** 33 ++ "a" ++ ")" ** 33;
    try std.testing.expectError(error.RegexNestingTooDeep, Pattern.init(nesting));
}

test "predicate owns configuration and all matches use fixed storage" {
    var key = "tenant".*;
    var value = "prod".*;
    var pattern_bytes = "^prod$".*;
    const predicate = try Predicate.init(&.{ .{ .key = &key, .operator = .eq, .value = .{ .string = &value } }, .{ .key = &key, .operator = .pattern, .value = .{ .string = &pattern_bytes } } });
    @memset(&key, 'x');
    @memset(&value, 'x');
    @memset(&pattern_bytes, 'x');
    const copied = predicate;
    for (0..1000) |_| try std.testing.expect(try copied.matches(testEvent(&.{fields.kv("tenant", "prod")})));
    const too_many = [_]Rule{.{ .key = "x", .operator = .exists }} ** (max_rules + 1);
    try std.testing.expectError(error.TooManyRules, Predicate.init(&too_many));
    const long = [_]u8{'x'} ** max_storage_bytes;
    try std.testing.expectError(error.StorageExhausted, Predicate.init(&.{.{ .key = "key", .operator = .eq, .value = .{ .string = &long } }}));
}

test "predicate compatibility equality avoids undefined tails and distinguishes policies" {
    const first = try Predicate.parse("tenant == \"prod\" && @message =~ \"^request.*$\"");
    const same = try Predicate.parse("tenant == \"prod\" && @message =~ \"^request.*$\"");
    const changed = try Predicate.parse("tenant == \"test\" && @message =~ \"^request.*$\"");
    try std.testing.expect(first.eql(&same));
    try std.testing.expect(!first.eql(&changed));
    const empty_a = try Predicate.init(&.{});
    const empty_b = try Predicate.init(&.{});
    try std.testing.expect(empty_a.eql(&empty_b));
    const nested_a = try Predicate.init(&.{.{ .path = &.{ "a", "b" }, .operator = .exists }});
    const nested_b = try Predicate.init(&.{.{ .path = &.{ "a", "c" }, .operator = .exists }});
    try std.testing.expect(!nested_a.eql(&nested_b));
    const nan_a = try Predicate.init(&.{.{ .key = "n", .operator = .eq, .value = .{ .float = std.math.nan(f64) } }});
    const nan_b = try Predicate.init(&.{.{ .key = "n", .operator = .eq, .value = .{ .float = std.math.nan(f64) } }});
    try std.testing.expect(nan_a.eql(&nan_b));
}

test "regex states remain bounded for nullable loops and multiple compiled rules" {
    const nullable = try Pattern.init("^((a?)*)*b$");
    try std.testing.expect(try nullable.matches("aaab"));
    try std.testing.expect(!try nullable.matches("aaaa"));
    const predicate = try Predicate.parse("@scope =~ \"^http\\\\.\" && @message =~ \"failed$\"");
    try std.testing.expect(try predicate.matches(testEvent(&.{})));
    var changed = testEvent(&.{});
    changed.message = "success";
    try std.testing.expect(!try predicate.matches(changed));
    var path_key = "group".*;
    var leaf_key = "leaf".*;
    const nested = try Predicate.init(&.{.{ .path = &.{ &path_key, &leaf_key }, .operator = .exists }});
    @memset(&path_key, 'x');
    @memset(&leaf_key, 'x');
    try std.testing.expect(try nested.matches(testEvent(&.{fields.kv("group", Value{ .group = &.{fields.kv("leaf", null)} })})));
}

test "parsed numeric string and pattern literals preserve their types" {
    const numbers = try Predicate.parse("min == -170141183460469231731687303715884105728 && max == 340282366920938463463374607431768211455 && ratio < 3.5 && hex == 0xfee");
    try std.testing.expect(try numbers.matches(testEvent(&.{ fields.kv("min", std.math.minInt(i128)), fields.kv("max", std.math.maxInt(u128)), fields.kv("ratio", @as(f64, 3.25)), fields.kv("hex", 0xfee) })));
    const strings = try Predicate.parse("text == \"quoted\\\"\\n雪\"");
    try std.testing.expect(try strings.matches(testEvent(&.{fields.kv("text", "quoted\"\n雪")})));
    const wrong = try Predicate.parse("number != 1");
    try std.testing.expect(!try wrong.matches(testEvent(&.{fields.kv("number", "1")})));
    const infinity = try Predicate.init(&.{.{ .key = "number", .operator = .lt, .value = .{ .float = std.math.inf(f64) } }});
    try std.testing.expect(try infinity.matches(testEvent(&.{fields.kv("number", std.math.maxInt(u128))})));
    const tiny = try Predicate.init(&.{.{ .key = "number", .operator = .lt, .value = .{ .float = @bitCast(@as(u64, 1)) } }});
    try std.testing.expect(try tiny.matches(testEvent(&.{fields.kv("number", 0)})));
}
