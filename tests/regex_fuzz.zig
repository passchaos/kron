//! Reproducible public regex/parser mutation campaigns, with bounded inputs.
//! Independent matching outcomes are covered by regex_differential.py; these
//! corpora exercise arbitrary compile inputs and configuration ownership.
const std = @import("std");
const kron = @import("kron");

test "byte regex mutation and arbitrary input preserve owned fixed-budget state" {
    var random = std.Random.DefaultPrng.init(0x6b726f6e72656766);
    const rng = random.random();
    const seeds = [_][]const u8{
        "",         "^((a?)*)*b$",          "[\\x00-\\xff]+", "[]a]",  "[^]a]",
        "\\n$",     "(warn|error): [a-z]+", "[a\\-c]",        "\\\\",  "(a|ab)*c",
        "^\\x00.$", "\\q",                  "[z-a]",          "(?=x)",
    };
    var pattern_bytes: [160]u8 = undefined;
    var input: [64]u8 = undefined;
    var compiled: usize = 0;
    var rejected: usize = 0;
    for (0..8192) |iteration| {
        var length: usize = undefined;
        if (iteration % 2 == 0) {
            const seed = seeds[iteration / 2 % seeds.len];
            @memcpy(pattern_bytes[0..seed.len], seed);
            length = seed.len;
            if (iteration % 8 != 0) {
                for (0..1 + iteration % 4) |_| {
                    if (length != 0) pattern_bytes[rng.uintLessThan(usize, length)] = rng.int(u8);
                }
                if (iteration % 3 == 0) length = rng.uintLessThan(usize, length + 1);
            }
        } else {
            rng.bytes(&pattern_bytes);
            length = rng.uintLessThan(usize, pattern_bytes.len + 1);
        }
        const pattern = kron.Pattern.init(pattern_bytes[0..length]) catch {
            rejected += 1;
            continue;
        };
        compiled += 1;
        const copied = pattern;
        rng.bytes(&input);
        const bytes = input[0..rng.uintLessThan(usize, input.len + 1)];
        const expected = try pattern.matches(bytes);
        try std.testing.expectEqual(expected, try copied.matches(bytes));
        // Pattern and Predicate must own their state rather than retain the
        // mutable configuration buffer, including byte patterns with NUL.
        const predicate = kron.Predicate.init(&.{
            .{ .key = "input", .operator = .pattern, .value = .{ .bytes = pattern_bytes[0..length] } },
            .{ .key = "marker", .operator = .pattern, .value = .{ .string = "^ok$" } },
        }) catch |err| {
            try std.testing.expectEqual(error.TooManyRegexStates, err);
            try std.testing.expect(pattern.state_count + 5 > 128);
            continue;
        };
        @memset(&pattern_bytes, 0xdd);
        try std.testing.expectEqual(expected, try pattern.matches(bytes));
        try std.testing.expectEqual(expected, try copied.matches(bytes));
        const fields = [_]kron.Field{ kron.kv("input", kron.bytes(bytes)), kron.kv("marker", "ok") };
        try std.testing.expectEqual(expected, try predicate.matches(.{
            .level = .info,
            .scope = "fuzz.regex",
            .message = "",
            .timestamp_ns = 0,
            .fields = &fields,
        }));
    }
    // A campaign that accidentally rejects or accepts every generated input
    // does not exercise both parser outcomes.
    try std.testing.expect(compiled > 1000);
    try std.testing.expect(rejected > 1000);
}

test "predicate parser mutation diagnostics and successful values stay owned" {
    var random = std.Random.DefaultPrng.init(0x7072656469636174);
    const rng = random.random();
    const seeds = [_][]const u8{
        "@message =~ \"^[]a]+$\"",     "exists(input) && @scope =~ \"^fuzz\\\\.\"",
        "input == 42",                 "input =~ \"\\\\x00\"",
        "@message =~ \"\\\\D\"",       "input == \"a\\n\"",
        "input > 3 && exists(marker)", "",
        "@message =~ \"[\"",
    };
    var spec: [256]u8 = undefined;
    for (0..4096) |iteration| {
        var length: usize = undefined;
        if (iteration % 2 == 0) {
            const seed = seeds[iteration / 2 % seeds.len];
            @memcpy(spec[0..seed.len], seed);
            length = seed.len;
            if (length != 0 and iteration % 8 != 0) spec[rng.uintLessThan(usize, length)] = rng.int(u8);
        } else {
            rng.bytes(&spec);
            length = rng.uintLessThan(usize, spec.len + 1);
        }
        switch (kron.Predicate.parseDiagnostic(spec[0..length])) {
            .diagnostic => |diagnostic| try std.testing.expect(diagnostic.offset <= length),
            .predicate => |predicate| {
                @memset(&spec, 0xdd);
                const copy = predicate;
                const event: kron.Event = .{
                    .level = .info,
                    .scope = "fuzz.regex",
                    .message = "]a",
                    .timestamp_ns = 0,
                    .fields = &.{ kron.kv("input", 42), kron.kv("marker", "ok") },
                };
                try std.testing.expectEqual(try predicate.matches(event), try copy.matches(event));
                try std.testing.expect(predicate.eql(&copy));
            },
        }
    }
}
