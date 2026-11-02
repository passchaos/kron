//! Public escaping controls. Setup is outside timing; complete output is hashed.
const std = @import("std");
const escaping = @import("escaping");
const Operation = enum { quoted_json, quoted_text, json_key, json_member };

pub fn main(init: std.process.Init) !void {
    var long_ascii: [256]u8 = @splat('a');
    const unicode = "雪🙂雪🙂雪🙂雪🙂雪🙂雪🙂雪🙂雪🙂";
    const inputs = [_][]const u8{
        "", "a", "ab", "abc", "abcd", "abcde", "field0", "abcdefg", "abcdefgh", "abcdefghi",
        "twelve_chars", "reference.app", "sixteen-char-key", "twenty-four-character-ke", &long_ascii,
        unicode, "a\"b\\c\t", "\x00\x01\x7f\xff\n", "$bytes:reserved", "abc\xffdef",
    };
    var buffer: [4096]u8 = undefined;
    var report_buffer: [4096]u8 = undefined;
    var report = std.Io.File.stdout().writerStreaming(init.io, &report_buffer);
    for (inputs, 0..) |input, case| for (std.enums.values(Operation)) |operation| {
        for (0..5) |repetition| {
            var checksum: u64 = 0;
            var bytes: u64 = 0;
            const iterations = 10000;
            const start = std.Io.Clock.awake.now(init.io);
            for (0..iterations) |iteration| {
                // Keep the long ASCII fixture dynamic without changing its
                // character class; both frozen binaries receive identical data.
                long_ascii[255] = 'a' + @as(u8, @intCast(iteration % 26));
                var writer = std.Io.Writer.fixed(&buffer);
                switch (operation) {
                    .quoted_json => try escaping.quoted(&writer, input, .json),
                    .quoted_text => try escaping.quoted(&writer, input, .text),
                    .json_key => try escaping.jsonKey(&writer, input),
                    .json_member => try escaping.jsonMember(&writer, input, true),
                }
                checksum +%= std.hash.Wyhash.hash(iteration, writer.buffered());
                bytes += writer.end;
                std.mem.doNotOptimizeAway(writer.buffered());
            }
            const elapsed = start.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds();
            try std.json.Stringify.value(.{
                .benchmark = "public-escaping", .case = case, .operation = @tagName(operation),
                .input_bytes = input.len, .repetition = repetition, .iterations = iterations,
                .elapsed_ns = elapsed, .ns_per_record = @as(f64, @floatFromInt(elapsed)) / iterations,
                .checksum = checksum, .output_bytes = bytes,
                .scope = "Escaping only, full output hash included; not logging throughput",
            }, .{}, &report.interface);
            try report.interface.writeByte('\n');
        }
    };
    try report.interface.flush();
}
