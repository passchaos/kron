//! Fixed-budget byte regular expressions. Compiled states own all literals;
//! Thompson search merges paths without allocation or backtracking.
const std = @import("std");
pub const max_regex_states = 128;
pub const max_regex_input_bytes = 8192;
pub const CompileError = error{ InvalidRegex, UnsupportedRegex, TooManyRegexStates, RegexNestingTooDeep };
pub const MatchError = error{InputTooLong};

const no_state: u8 = 255;
const no_patch: u16 = 65535;
pub const State = struct {
    op: enum { byte, any, class, split, jump, bol, eol, accept },
    out: u8 = no_state,
    out2: u8 = no_state,
    byte: u8 = 0,
    set: [32]u8 = @splat(0),
    // Configuration-time closure through SPLIT/JUMP to consuming/assertion states.
    closure: [2]u64 = @splat(0),
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
        var active: [2]u64 = @splat(0);
        for (0..input.len + 1) |position| {
            // Start at each byte position; anchors retain absolute-input meaning.
            merge(&active, states[self.start].closure);
            var visited: [2]u64 = @splat(0);
            var next: [2]u64 = @splat(0);
            while (active[0] != 0 or active[1] != 0) {
                const word: usize = if (active[0] != 0) 0 else 1;
                const bit: u6 = @intCast(@ctz(active[word]));
                const mask = @as(u64, 1) << bit;
                active[word] &= ~mask;
                visited[word] |= mask;
                const state = states[word * 64 + bit];
                switch (state.op) {
                    .accept => return true,
                    .bol, .eol => {
                        if ((state.op == .bol and position == 0) or (state.op == .eol and position == input.len)) {
                            const closure = states[state.out].closure;
                            // Assertion cycles must also visit each state once.
                            merge(&active, .{ closure[0] & ~visited[0], closure[1] & ~visited[1] });
                        }
                    },
                    .byte, .any, .class => {
                        if (position == input.len) continue;
                        const byte = input[position];
                        const consumes = switch (state.op) {
                            .byte => state.byte == byte,
                            .any => byte != '\n',
                            .class => state.set[byte >> 3] & (@as(u8, 1) << @as(u3, @truncate(byte))) != 0,
                            else => unreachable,
                        };
                        if (consumes) merge(&next, states[state.out].closure);
                    },
                    // All unconditional epsilon transitions are expanded at
                    // compile time. No jump/split enters a runtime state set.
                    .jump, .split => unreachable,
                }
            }
            active = next;
        }
        return false;
    }

    fn merge(destination: *[2]u64, source: [2]u64) void {
        destination[0] |= source[0];
        destination[1] |= source[1];
    }
};

const Fragment = struct { start: u8, head: u16, tail: u16 };
pub const Compiler = struct {
    input: []const u8,
    index: usize = 0,
    states: *[max_regex_states]State,
    count: *usize,
    depth: usize = 0,
    links: [max_regex_states * 2]u16 = @splat(no_patch),

    fn add(self: *Compiler, state: State) CompileError!u8 {
        if (self.count.* == max_regex_states) return error.TooManyRegexStates;
        const index: u8 = @intCast(self.count.*);
        self.states[index] = state;
        self.count.* += 1;
        return index;
    }

    fn dangling(self: *Compiler, start: u8, second: bool) Fragment {
        const patch_index: u16 = @as(u16, start) * 2 + @intFromBool(second);
        self.links[patch_index] = no_patch;
        return .{ .start = start, .head = patch_index, .tail = patch_index };
    }

    fn join(self: *Compiler, first: Fragment, second: Fragment, start: u8) Fragment {
        self.links[first.tail] = second.head;
        return .{ .start = start, .head = first.head, .tail = second.tail };
    }

    fn patch(self: *Compiler, fragment: Fragment, target: u8) void {
        var current = fragment.head;
        while (current != no_patch) {
            if (current & 1 == 0) self.states[current / 2].out = target else self.states[current / 2].out2 = target;
            current = self.links[current];
        }
    }

    pub fn compile(self: *Compiler) CompileError!Regex {
        const minimum = self.count.*;
        const fragment = try self.alternate();
        if (self.index != self.input.len) return error.InvalidRegex;
        const accept = try self.add(.{ .op = .accept });
        self.patch(fragment, accept);
        self.prepareClosures(minimum);
        return .{ .start = fragment.start, .minimum_state = @intCast(minimum), .state_count = @intCast(self.count.* - minimum) };
    }

    /// Reach a fixed point over this regex's fully patched graph. Assertions
    /// remain terminals: their truth depends on the current input position.
    /// At most 128 states and 128 monotone rounds, with no allocation.
    fn prepareClosures(self: *Compiler, minimum: usize) void {
        const states = self.states[minimum..self.count.*];
        for (states, minimum..) |*state, index| {
            state.closure = @splat(0);
            if (state.op != .jump and state.op != .split) state.closure[index >> 6] = @as(u64, 1) << @as(u6, @truncate(index));
        }
        var changed = true;
        while (changed) {
            changed = false;
            for (states) |*state| {
                if (state.op != .jump and state.op != .split) continue;
                var closure = self.states[state.out].closure;
                if (state.op == .split) {
                    const second = self.states[state.out2].closure;
                    closure[0] |= second[0];
                    closure[1] |= second[1];
                }
                if (closure[0] != state.closure[0] or closure[1] != state.closure[1]) {
                    state.closure = closure;
                    changed = true;
                }
            }
        }
    }

    fn alternate(self: *Compiler) CompileError!Fragment {
        var fragment = try self.concatenate();
        while (self.index < self.input.len and self.input[self.index] == '|') {
            self.index += 1;
            const other = try self.concatenate();
            const split = try self.add(.{ .op = .split, .out = fragment.start, .out2 = other.start });
            fragment = self.join(fragment, other, split);
        }
        return fragment;
    }

    fn concatenate(self: *Compiler) CompileError!Fragment {
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

    fn quantified(self: *Compiler) CompileError!Fragment {
        const atom_start = self.index;
        var fragment = try self.atom();
        if (self.index < self.input.len) {
            const quantifier = self.input[self.index];
            if (quantifier == '*' or quantifier == '+' or quantifier == '?') {
                // Anchors are assertions rather than repeatable atoms. A
                // parenthesized assertion remains a valid (nullable) group.
                if (self.input[atom_start] == '^' or self.input[atom_start] == '$') return error.InvalidRegex;
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

    fn atom(self: *Compiler) CompileError!Fragment {
        if (self.index == self.input.len) return error.InvalidRegex;
        const byte = self.input[self.index];
        self.index += 1;
        if (byte == '(') {
            if (self.index < self.input.len and self.input[self.index] == '?') return error.UnsupportedRegex;
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

    fn escapeByte(self: *Compiler) CompileError!u8 {
        if (self.index == self.input.len) return error.InvalidRegex;
        const byte = self.input[self.index];
        self.index += 1;
        return switch (byte) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'f' => 12,
            'v' => 11,
            'a' => 7,
            'x' => blk: {
                if (self.input.len - self.index < 2) return error.InvalidRegex;
                const high = std.fmt.charToDigit(self.input[self.index], 16) catch return error.InvalidRegex;
                const low = std.fmt.charToDigit(self.input[self.index + 1], 16) catch return error.InvalidRegex;
                self.index += 2;
                break :blk high * 16 + low;
            },
            // Never silently turn an unsupported character category,
            // assertion, backreference or unknown letter escape into a byte.
            else => if (std.ascii.isAlphanumeric(byte)) error.UnsupportedRegex else byte,
        };
    }

    fn characterClass(self: *Compiler) CompileError!State {
        var result: State = .{ .op = .class };
        const negate = self.index < self.input.len and self.input[self.index] == '^';
        if (negate) self.index += 1;
        var count: usize = 0;
        // A closing bracket in the first element (also after ^) is literal.
        // It still needs a later closing bracket, so [] and [^] are invalid.
        while (self.index < self.input.len and (self.input[self.index] != ']' or count == 0)) {
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

    fn classByte(self: *Compiler) CompileError!u8 {
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
        var compiler: Compiler = .{ .input = pattern, .states = &result.states, .count = &result.state_count };
        result.regex = try compiler.compile();
        return result;
    }

    pub fn matches(self: *const Pattern, input: []const u8) MatchError!bool {
        return self.regex.matches(self.states[0..self.state_count], input);
    }
};

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

test "regex escapes and character classes cover every byte including NUL" {
    var literal: [4]u8 = undefined;
    var class: [6]u8 = undefined;
    for (0..256) |byte| {
        const value: u8 = @intCast(byte);
        const escaped = try std.fmt.bufPrint(&literal, "\\x{x:0>2}", .{value});
        const member = try std.fmt.bufPrint(&class, "[{s}]", .{escaped});
        const pattern = try Pattern.init(escaped);
        const grouped = try Pattern.init(member);
        for (0..256) |input_byte| {
            const input = [_]u8{@intCast(input_byte)};
            try std.testing.expectEqual(byte == input_byte, try pattern.matches(&input));
            try std.testing.expectEqual(byte == input_byte, try grouped.matches(&input));
        }
    }
    const range = try Pattern.init("^[\\x00-\\xff]+$");
    var all_bytes: [256]u8 = undefined;
    for (&all_bytes, 0..) |*byte, index| byte.* = @intCast(index);
    try std.testing.expect(try range.matches(&all_bytes));
    const escapes = [_]struct { pattern: []const u8, byte: u8 }{
        .{ .pattern = "\\n", .byte = 10 }, .{ .pattern = "\\r", .byte = 13 },
        .{ .pattern = "\\t", .byte = 9 },  .{ .pattern = "\\f", .byte = 12 },
        .{ .pattern = "\\v", .byte = 11 }, .{ .pattern = "\\a", .byte = 7 },
    };
    for (escapes) |case| {
        const pattern = try Pattern.init(case.pattern);
        try std.testing.expect(try pattern.matches(&.{case.byte}));
        try std.testing.expect(!try pattern.matches(case.pattern[1..]));
    }
}

test "regex bracket placement and strict anchors retain byte search semantics" {
    const cases = [_]struct { pattern: []const u8, input: []const u8, expected: bool }{
        .{ .pattern = "^[]a]+$", .input = "]a]", .expected = true },
        .{ .pattern = "^[]a]+$", .input = "]a]\n", .expected = false },
        .{ .pattern = "^[^]a]+$", .input = "bc\n", .expected = true },
        .{ .pattern = "^[^]a]+$", .input = "b]c", .expected = false },
        .{ .pattern = "[-a]+", .input = "-", .expected = true },
        .{ .pattern = "[a-]+", .input = "-", .expected = true },
        .{ .pattern = "[\\]-a]", .input = "^", .expected = true },
        .{ .pattern = "[a\\-c]", .input = "b", .expected = false },
        .{ .pattern = "[\\xFF]", .input = "\xff", .expected = true },
        .{ .pattern = "[\\^$]", .input = "^", .expected = true },
        .{ .pattern = "^$", .input = "\n", .expected = false },
        .{ .pattern = "^.*$", .input = "a\r", .expected = true },
        .{ .pattern = "^.*$", .input = "a\n", .expected = false },
        .{ .pattern = "(^)*a", .input = "a", .expected = true },
        .{ .pattern = "($)+", .input = "a\n", .expected = true },
        .{ .pattern = "^..$", .input = "\xc3\xa9", .expected = true },
        .{ .pattern = "^.$", .input = "\xc3\xa9", .expected = false },
    };
    for (cases) |case| {
        const pattern = try Pattern.init(case.pattern);
        try std.testing.expectEqual(case.expected, try pattern.matches(case.input));
    }
}

test "regex rejects unsupported syntax instead of silently matching literals" {
    for ([_][]const u8{
        "\\D",   "\\d",     "\\S",       "\\W", "\\b", "\\B",   "\\A",   "\\Z",
        "\\z",   "\\u1234", "\\N{name}", "\\q", "\\0", "[\\D]", "(?=a)", "(?:a)",
        "(?i)a", "a{2}",
    }) |pattern| try std.testing.expectError(error.UnsupportedRegex, Pattern.init(pattern));
    for ([_][]const u8{
        "[]",    "[^]", "[a-", "\\x", "\\x0", "\\xgg", "\\x+1", "\\x_1",
        "\\x1_", "^*",  "$+",  "a$?", "a**",
    }) |pattern| try std.testing.expectError(error.InvalidRegex, Pattern.init(pattern));
    // 127 byte states plus ACCEPT exactly exhaust the fixed budget.
    const limit = [_]u8{'a'} ** (max_regex_states - 1);
    const pattern = try Pattern.init(&limit);
    try std.testing.expectEqual(max_regex_states, pattern.state_count);
    try std.testing.expect(try pattern.matches(&limit));
    const nesting = "(" ** 32 ++ "a" ++ ")" ** 32;
    try std.testing.expect(try (try Pattern.init(nesting)).matches("a"));
}

test "closure words span full state budget and nullable assertion cycles" {
    const empty_branches = try Pattern.init("|" ** 63);
    try std.testing.expectEqual(max_regex_states, empty_branches.state_count);
    try std.testing.expect(try empty_branches.matches(""));
    try std.testing.expect(try empty_branches.matches("\x00\xff\n"));
    const chain = try Pattern.init("a" ** 127);
    try std.testing.expect(try chain.matches("a" ** 127));
    try std.testing.expect(!try chain.matches("a" ** 126));
    for ([_][]const u8{ "(^)*a", "($)+", "((^|$)*)*", "^((a?)*)*b$" }) |bytes| {
        const pattern = try Pattern.init(bytes);
        for (pattern.states[0..pattern.state_count]) |state| {
            for (0..max_regex_states) |index| {
                if (state.closure[index >> 6] & (@as(u64, 1) << @as(u6, @truncate(index))) == 0) continue;
                try std.testing.expect(index < pattern.state_count);
                try std.testing.expect(pattern.states[index].op != .jump and pattern.states[index].op != .split);
            }
        }
    }
}
