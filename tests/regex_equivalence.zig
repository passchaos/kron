//! Compare the production matcher with an intentionally dense fixed-point
//! interpreter over the compiled graph. Python owns the parser/match oracle.
const std = @import("std");
const kron = @import("kron");
const limit = 128;

fn denseMatches(pattern: *const kron.Pattern, input: []const u8) bool {
    var active: [limit]bool = @splat(false);
    for (0..input.len + 1) |position| {
        active[pattern.regex.start] = true;
        var changed = true;
        while (changed) {
            changed = false;
            for (pattern.states[0..pattern.state_count], 0..) |state, index| {
                if (!active[index]) continue;
                const follows = switch (state.op) {
                    .split, .jump => true,
                    .bol => position == 0,
                    .eol => position == input.len,
                    else => false,
                };
                if (!follows) continue;
                if (!active[state.out]) {
                    active[state.out] = true;
                    changed = true;
                }
                if (state.op == .split and !active[state.out2]) {
                    active[state.out2] = true;
                    changed = true;
                }
            }
        }
        var next: [limit]bool = @splat(false);
        for (pattern.states[0..pattern.state_count], 0..) |state, index| {
            if (!active[index]) continue;
            if (state.op == .accept) return true;
            if (position == input.len) continue;
            const consumes = switch (state.op) {
                .byte => state.byte == input[position],
                .any => input[position] != '\n',
                .class => state.set[input[position] / 8] & (@as(u8, 1) << @as(u3, @truncate(input[position]))) != 0,
                else => false,
            };
            if (consumes) next[state.out] = true;
        }
        active = next;
    }
    return false;
}

fn check(pattern_bytes: []const u8, input: []const u8) !void {
    const pattern = kron.Pattern.init(pattern_bytes) catch return;
    const expected = denseMatches(&pattern, input);
    try std.testing.expectEqual(expected, try pattern.matches(input));
    // Each regex starts at a different offset in Predicate's shared array.
    const predicate = kron.Predicate.init(&.{
        .{ .key = "marker", .operator = .pattern, .value = .{ .string = "^ok$" } },
        .{ .key = "input", .operator = .pattern, .value = .{ .bytes = pattern_bytes } },
    }) catch |err| {
        try std.testing.expectEqual(error.TooManyRegexStates, err);
        return;
    };
    try std.testing.expectEqual(expected, try predicate.matches(.{
        .level = .info,
        .scope = "fuzz",
        .message = "",
        .timestamp_ns = 0,
        .fields = &.{ kron.kv("input", kron.bytes(input)), kron.kv("marker", "ok") },
    }));
}

const seeds = [_][]const u8{
    "",      "^$",     "a|",             "^(a|aa)*b$", "^((a?)*)*b$", "(^)*a",                        "($)+",
    "[]a]+", "[^]a]+", "[\\x00-\\xff]*", "(ab|a)b",    "(()|a)*",     "^/api/(users|orders)/[0-9]+$", "(warn|error): [a-z]+",
};

test "dense graph interpreter agrees across mutation nullable loops and shared offsets" {
    var random = std.Random.DefaultPrng.init(0x7370617273656e66);
    const rng = random.random();
    var pattern: [160]u8 = undefined;
    var input: [64]u8 = undefined;
    for (0..8192) |iteration| {
        const seed = seeds[iteration % seeds.len];
        @memcpy(pattern[0..seed.len], seed);
        var length = seed.len;
        if (iteration % 3 == 0) {
            rng.bytes(&pattern);
            length = rng.uintLessThan(usize, pattern.len + 1);
        } else if (iteration % 3 == 1 and length != 0) {
            pattern[rng.uintLessThan(usize, length)] = rng.int(u8);
        }
        if (iteration % 2 == 0) {
            for (&input) |*byte| byte.* = "ab01\x00\xff\n"[rng.uintLessThan(usize, 7)];
        } else rng.bytes(&input);
        try check(pattern[0..length], input[0..rng.uintLessThan(usize, input.len + 1)]);
    }
    const budget = "a" ** 127;
    try check(budget, budget);
    try check(budget, "a" ** 126);
}

test "shared graphs cross both closure words at exact budget with independent anchors" {
    const predicate = try kron.Predicate.init(&.{
        .{ .key = "marker", .operator = .pattern, .value = .{ .string = "x" ** 63 } },
        .{ .key = "input", .operator = .pattern, .value = .{ .string = "a" ** 63 } },
    });
    try std.testing.expectEqual(limit, predicate.state_count);
    for ([_][]const u8{ "a" ** 63, "a" ** 62, "b" ++ "a" ** 63 }) |input| {
        try std.testing.expectEqual(input.len >= 63, try predicate.matches(.{
            .level = .info,
            .scope = "fuzz",
            .message = "",
            .timestamp_ns = 0,
            .fields = &.{ kron.kv("marker", "x" ** 63), kron.kv("input", input) },
        }));
    }
    for (seeds) |bytes| {
        const pattern = try kron.Pattern.init(bytes);
        const shared = try kron.Predicate.init(&.{
            .{ .key = "marker", .operator = .pattern, .value = .{ .string = "x" ** 63 } },
            .{ .key = "input", .operator = .pattern, .value = .{ .string = bytes } },
        });
        for ([_][]const u8{ "", "a", "b", "aaab", "\n", "\x00\xff\n", "/api/orders/7" }) |input| {
            try std.testing.expectEqual(denseMatches(&pattern, input), try shared.matches(.{
                .level = .info,
                .scope = "fuzz",
                .message = "",
                .timestamp_ns = 0,
                .fields = &.{ kron.kv("marker", "x" ** 63), kron.kv("input", kron.bytes(input)) },
            }));
        }
    }
}

fn fuzzOne(_: void, smith: *std.testing.Smith) !void {
    var pattern: [160]u8 = undefined;
    var input: [128]u8 = undefined;
    // Mix arbitrary compile input with known valid graphs, so discovery does
    // not have to find nested syntax before reaching the matching engine.
    const selected = smith.valueRangeAtMost(u8, 0, seeds.len);
    const bytes = if (selected == seeds.len) pattern[0..smith.slice(&pattern)] else seeds[selected];
    try check(bytes, input[0..smith.slice(&input)]);
    var spec: [512]u8 = undefined;
    const spec_bytes = spec[0..smith.slice(&spec)];
    switch (kron.Predicate.parseDiagnostic(spec_bytes)) {
        .diagnostic => |diagnostic| try std.testing.expect(diagnostic.offset <= spec_bytes.len),
        .predicate => |predicate| {
            const event: kron.Event = .{ .level = .info, .scope = "fuzz", .message = "ab01", .timestamp_ns = 0, .fields = &.{kron.kv("input", "ab01")} };
            _ = try predicate.matches(event);
        },
    }
}

test "coverage guided regex graph and predicate parser" {
    try std.testing.fuzz({}, fuzzOne, .{});
}
