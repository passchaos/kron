//! Streaming escaping and injective key spelling shared by record encoders.
const std = @import("std");
pub const Escaping = enum { json, text };

/// JSON replaces each malformed byte with U+FFFD. Text makes malformed bytes
/// visible as \xHH. Both escape line breaks, so an input cannot inject records.
pub fn quoted(writer: *std.Io.Writer, input: []const u8, escaping: Escaping) std.Io.Writer.Error!void {
    const plain = asciiRun(input);
    if (plain == input.len) return quotedAscii(writer, input);
    var output = try QuotedWriter.init(writer, escaping);
    try writer.writeAll(input[0..plain]);
    try output.consume(input[plain..]);
    try output.finish();
}

fn quotedAscii(writer: *std.Io.Writer, input: []const u8) std.Io.Writer.Error!void {
    try writer.writeByte('"');
    try writer.writeAll(input);
    try writer.writeByte('"');
}

/// Return the first byte requiring escaping/UTF-8 handling. Word loads stay
/// inside the slice and use explicit little endian so the least mask byte is
/// always the first input byte. Byte-borrow masks may flag later adjacent
/// bytes too, but never a byte before the first real match; only the first
/// match is consumed. Short tails use the exact original scalar predicate.
fn asciiRun(input: []const u8) usize {
    if (input.len == 0) return 0;
    // UTF-8/control-heavy input must enter the scalar state machine without
    // paying for a whole-word mask at every codepoint or escaped byte.
    const first = input[0];
    if (first < 0x20 or first >= 0x7f or first == '"' or first == '\\') return 0;
    const high = 0x8080808080808080;
    const ones = 0x0101010101010101;
    var index: usize = 1;
    while (input.len - index >= 8) : (index += 8) {
        const word = std.mem.readInt(u64, input[index..][0..8], .little);
        const quotes = word ^ 0x2222222222222222;
        const slashes = word ^ 0x5c5c5c5c5c5c5c5c;
        const delete = word ^ 0x7f7f7f7f7f7f7f7f;
        const mask = (word & high) |
            ((word -% 0x2020202020202020) & ~word & high) |
            ((quotes -% ones) & ~quotes & high) |
            ((slashes -% ones) & ~slashes & high) |
            ((delete -% ones) & ~delete & high);
        if (mask != 0) return index + @as(usize, @intCast(@ctz(mask) / 8));
    }
    while (index < input.len and input[index] >= 0x20 and input[index] < 0x7f and input[index] != '"' and input[index] != '\\') : (index += 1) {}
    return index;
}

fn validSequence(sequence: []const u8) bool {
    _ = std.unicode.utf8Decode(sequence) catch return false;
    return true;
}

/// Retains at most one UTF-8 sequence across writer calls. Formatting arguments
/// may split a codepoint, so per-chunk UTF-8 validation would corrupt valid text.
pub const QuotedWriter = struct {
    interface: std.Io.Writer,
    target: *std.Io.Writer,
    escaping: Escaping,
    pending: [4]u8 = undefined,
    pending_len: usize = 0,
    expected_len: usize = 0,

    pub fn init(target: *std.Io.Writer, escaping: Escaping) std.Io.Writer.Error!QuotedWriter {
        try target.writeByte('"');
        return .{ .interface = .{ .buffer = &.{}, .vtable = &.{ .drain = drain } }, .target = target, .escaping = escaping };
    }

    pub fn finish(self: *QuotedWriter) std.Io.Writer.Error!void {
        try self.flushInvalid();
        try self.target.writeByte('"');
    }

    fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *QuotedWriter = @fieldParentPtr("interface", writer);
        std.debug.assert(writer.end == 0);
        var consumed: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try self.consume(bytes);
            consumed = std.math.add(usize, consumed, bytes.len) catch return error.WriteFailed;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| {
            try self.consume(last);
            consumed = std.math.add(usize, consumed, last.len) catch return error.WriteFailed;
        }
        return consumed;
    }

    fn consume(self: *QuotedWriter, input: []const u8) std.Io.Writer.Error!void {
        var index: usize = 0;
        while (index < input.len) {
            // Most messages consist of long printable ASCII runs.
            if (self.pending_len == 0) {
                const start = index;
                index += asciiRun(input[index..]);
                try self.target.writeAll(input[start..index]);
                if (index == input.len) break;
            }
            try self.byte(input[index]);
            index += 1;
        }
    }

    fn byte(self: *QuotedWriter, current: u8) std.Io.Writer.Error!void {
        if (self.pending_len != 0) {
            if (current & 0xc0 != 0x80) {
                try self.flushInvalid();
                return self.byte(current);
            }
            self.pending[self.pending_len] = current;
            self.pending_len += 1;
            if (self.pending_len == self.expected_len) {
                const sequence = self.pending[0..self.pending_len];
                if (validSequence(sequence)) {
                    if (sequence.len == 3 and sequence[0] == 0xe2 and sequence[1] == 0x80 and (sequence[2] == 0xa8 or sequence[2] == 0xa9)) {
                        try self.target.writeAll(if (sequence[2] == 0xa8) "\\u2028" else "\\u2029");
                    } else try self.target.writeAll(sequence);
                    self.pending_len = 0;
                } else try self.flushInvalid();
            }
            return;
        }
        switch (current) {
            '"' => try self.target.writeAll("\\\""),
            '\\' => try self.target.writeAll("\\\\"),
            '\n' => try self.target.writeAll("\\n"),
            '\r' => try self.target.writeAll("\\r"),
            '\t' => try self.target.writeAll("\\t"),
            0x08 => try self.target.writeAll("\\b"),
            0x0c => try self.target.writeAll("\\f"),
            else => {
                if (current < 0x20 or current == 0x7f) {
                    try self.target.writeAll(if (self.escaping == .json) "\\u00" else "\\x");
                    try hexByte(self.target, current);
                } else if (current < 0x80) {
                    try self.target.writeByte(current);
                } else {
                    const length = std.unicode.utf8ByteSequenceLength(current) catch 0;
                    if (length == 0) return self.invalidByte(current);
                    self.pending[0] = current;
                    self.pending_len = 1;
                    self.expected_len = length;
                }
            },
        }
    }

    fn invalidByte(self: *QuotedWriter, current: u8) std.Io.Writer.Error!void {
        if (self.escaping == .json) {
            try self.target.writeAll("\xef\xbf\xbd");
        } else {
            try self.target.writeAll("\\x");
            try hexByte(self.target, current);
        }
    }

    fn flushInvalid(self: *QuotedWriter) std.Io.Writer.Error!void {
        for (self.pending[0..self.pending_len]) |current| try self.invalidByte(current);
        self.pending_len = 0;
    }
};

pub fn hexByte(writer: *std.Io.Writer, byte: u8) std.Io.Writer.Error!void {
    const alphabet = "0123456789abcdef";
    try writer.writeByte(alphabet[byte >> 4]);
    try writer.writeByte(alphabet[byte & 15]);
}

pub fn hex(writer: *std.Io.Writer, input: []const u8) std.Io.Writer.Error!void {
    for (input) |byte| try hexByte(writer, byte);
}

/// Invalid UTF-8 keys use a reversible hex spelling. Reserve and encode the
/// same prefix for valid keys too, so distinct byte keys never collapse into
/// duplicate JSON properties after replacement-character normalization.
pub fn jsonKey(writer: *std.Io.Writer, input: []const u8) std.Io.Writer.Error!void {
    const prefix = "$bytes:";
    if (!std.mem.startsWith(u8, input, prefix)) {
        if (asciiRun(input) == input.len) return quotedAscii(writer, input);
        if (std.unicode.utf8ValidateSlice(input)) return quoted(writer, input, .json);
    }
    try writer.writeByte('"');
    try writer.writeAll(prefix);
    try hex(writer, input);
    try writer.writeByte('"');
}

/// Keys use an injective percent encoding for bytes outside this small safe
/// alphabet. Percent itself is escaped, preserving distinct original keys.
pub fn logfmtKey(writer: *std.Io.Writer, input: []const u8) std.Io.Writer.Error!void {
    for (input) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.' or byte == '-') {
            try writer.writeByte(byte);
        } else {
            try writer.writeByte('%');
            try hexByte(writer, byte);
        }
    }
}

test "quoted strings preserve UTF-8 and escape malformed bytes and record separators" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try quoted(&writer, "雪\n\"\x00\xff\xc0\xaf\xe2\x80\xa8", .json);
    try std.testing.expectEqualStrings("\"雪\\n\\\"\\u0000\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd\\u2028\"", writer.buffered());
    writer.end = 0;
    try quoted(&writer, "x\r\n\x1b\xff", .text);
    try std.testing.expectEqualStrings("\"x\\r\\n\\x1b\\xff\"", writer.buffered());
}

test "streaming escaping preserves UTF-8 for every write boundary" {
    const input = "雪🙂\n\"\xff\xed\xa0\x80\xe2\x80\xa8\xe2";
    for (std.enums.values(Escaping)) |escaping| {
        var expected_buffer: [512]u8 = undefined;
        var expected = std.Io.Writer.fixed(&expected_buffer);
        try quoted(&expected, input, escaping);
        for (0..input.len + 1) |split| {
            var actual_buffer: [512]u8 = undefined;
            var actual = std.Io.Writer.fixed(&actual_buffer);
            var output = try QuotedWriter.init(&actual, escaping);
            try output.interface.writeAll(input[0..split]);
            try output.interface.writeAll(input[split..]);
            try output.finish();
            try std.testing.expectEqualStrings(expected.buffered(), actual.buffered());
        }
        var actual_buffer: [512]u8 = undefined;
        var actual = std.Io.Writer.fixed(&actual_buffer);
        var output = try QuotedWriter.init(&actual, escaping);
        for (input) |byte| try output.interface.writeByte(byte);
        try output.finish();
        try std.testing.expectEqualStrings(expected.buffered(), actual.buffered());
    }
}

fn scalarRun(input: []const u8) usize {
    for (input, 0..) |byte, index| if (byte < 0x20 or byte >= 0x7f or byte == '"' or byte == '\\') return index;
    return input.len;
}

test "ASCII word scan matches scalar predicate for every byte pair lane and alignment" {
    var storage: [64]u8 = undefined;
    // All adjacent values detect cross-lane borrow interactions. Positions
    // cover short scalar tails, complete words, word boundaries and alignment.
    for ([_]usize{ 0, 1, 3, 7 }) |offset| {
        for ([_]usize{ 0, 6, 7, 14, 15, 22, 23 }) |position| {
            for (0..65536) |pair| {
                @memset(&storage, 'a');
                const input = storage[offset..][0..32];
                input[position] = @truncate(pair);
                input[position + 1] = @truncate(pair >> 8);
                try std.testing.expectEqual(scalarRun(input), asciiRun(input));
            }
        }
    }
    for (0..8) |offset| for (0..33) |length| {
        @memset(&storage, ' ');
        const input = storage[offset..][0..length];
        try std.testing.expectEqual(length, asciiRun(input));
        for (0..length) |index| {
            input[index] = 0;
            try std.testing.expectEqual(index, asciiRun(input));
            input[index] = ' ';
        }
    };
}

test "ASCII word scan retains exact escaping and streaming output across random chunk boundaries" {
    var random = std.Random.DefaultPrng.init(0x61736369692d7275);
    var input_bytes: [128]u8 = undefined;
    for (0..2048) |_| {
        const length = random.random().uintLessThan(usize, input_bytes.len + 1);
        const input = input_bytes[0..length];
        random.random().bytes(input);
        try std.testing.expectEqual(scalarRun(input), asciiRun(input));
        for (std.enums.values(Escaping)) |mode| {
            var expected_bytes: [1024]u8 = undefined;
            var expected = std.Io.Writer.fixed(&expected_bytes);
            var reference = try QuotedWriter.init(&expected, mode);
            // Bypass both the optimized complete string and ASCII run scan.
            for (input) |byte| try reference.byte(byte);
            try reference.finish();
            var actual_bytes: [1024]u8 = undefined;
            var actual = std.Io.Writer.fixed(&actual_bytes);
            try quoted(&actual, input, mode);
            try std.testing.expectEqualStrings(expected.buffered(), actual.buffered());
            actual.end = 0;
            var stream = try QuotedWriter.init(&actual, mode);
            const split = random.random().uintLessThan(usize, length + 1);
            try stream.interface.writeAll(input[0..split]);
            try stream.interface.writeAll(input[split..]);
            try stream.finish();
            try std.testing.expectEqualStrings(expected.buffered(), actual.buffered());
        }
    }
}
