const std = @import("std");
pub const max_regex_states = 128;
pub const max_regex_input_bytes = 8192;
pub const CompileError = error{ InvalidRegex, UnsupportedRegex, TooManyRegexStates, RegexNestingTooDeep };
pub const MatchError = error{InputTooLong};
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


pub fn main() !void {
    const cases = [_]struct { pattern: []const u8, input: []const u8 }{
        .{ .pattern = "\\D+", .input = "abc" },
        .{ .pattern = "\\Aabc", .input = "abc" },
        .{ .pattern = "[]a]+", .input = "]a" },
        .{ .pattern = "\\f", .input = "\x0c" },
        .{ .pattern = "\\xFF", .input = "\xff" },
        .{ .pattern = "^*a", .input = "a" },
    };
    for (cases) |case| {
        const pattern = Pattern.init(case.pattern) catch |err| {
            std.debug.print("pattern={s} error={s}\n", .{ case.pattern, @errorName(err) });
            continue;
        };
        std.debug.print("pattern={s} matched={any}\n", .{ case.pattern, try pattern.matches(case.input) });
    }
}
