//! Read-only export/query tool for journals and framed binary archives.
const std = @import("std");
const kron = @import("kron");

pub const usage =
    \\Usage: kroncat [--json|--text] [--level LEVEL] [--where 'KEY == VALUE']
    \\               [--follow] [--recover] FILE
    \\Reads a journal, binary archive or compressed archive without modifying it.
    \\  --json          Emit JSON Lines (default: text).
    \\  --level LEVEL   Include this severity and higher.
    \\  --where EXPR    Equality on primitive fields or metadata; repeat for AND.
    \\                  Quote strings to distinguish "42" from 42. Bytes: bytes:00ff.
    \\  --follow, -f    Poll for new complete records every 200 ms.
    \\  --recover       Export journal commits beyond the durable checkpoint.
    \\  --help, -h      Show this help.
    \\
;

pub const ArgumentError = error{ MissingPath, MultiplePaths, UnknownOption, MissingOptionValue, TooManyPredicates, InvalidWhere, InvalidLevel };
const StringLiteral = struct { text: []const u8, escaped: bool = false };
pub const Expected = union(enum) {
    null_value,
    boolean: bool,
    signed: i128,
    unsigned: u128,
    float: f64,
    string: StringLiteral,
    bytes: []const u8,
    duration_ns: i64,
    timestamp_ns: i64,
};

pub const Query = struct {
    key: []const u8,
    expected: Expected,

    pub fn parse(expression: []const u8) error{InvalidWhere}!Query {
        const equal = std.mem.find(u8, expression, "==") orelse return error.InvalidWhere;
        const key = trim(expression[0..equal]);
        const literal = trim(expression[equal + 2 ..]);
        if (key.len == 0 or literal.len == 0) return error.InvalidWhere;
        for (key) |byte| if (std.ascii.isWhitespace(byte) or byte == '=' or byte == '\'' or byte == '"') return error.InvalidWhere;
        if (literal[0] == '=') return error.InvalidWhere;
        return .{ .key = key, .expected = try parseExpected(literal) };
    }

    pub fn matches(self: Query, event: kron.Event) bool {
        for (event.fields) |field| {
            if (std.mem.eql(u8, field.key, self.key)) return self.matchesValue(field.value);
        }
        const value: kron.Value = if (std.mem.eql(u8, self.key, "scope")) .{ .string = event.scope } else if (std.mem.eql(u8, self.key, "message")) .{ .string = event.message } else if (std.mem.eql(u8, self.key, "level")) .{ .string = @tagName(event.level) } else if (std.mem.eql(u8, self.key, "timestamp_ns")) .{ .timestamp_ns = event.timestamp_ns } else if (std.mem.eql(u8, self.key, "session")) .{ .unsigned = event.session } else if (std.mem.eql(u8, self.key, "sequence")) .{ .unsigned = event.sequence } else if (std.mem.eql(u8, self.key, "channel")) .{ .unsigned = event.channel } else return false;
        return self.matchesValue(value);
    }

    pub fn matchesValue(self: Query, value: kron.Value) bool {
        // Compound values are emitted structurally; this small query grammar
        // deliberately restricts equality to primitive literals.
        if (value == .array or value == .group) return false;
        return switch (self.expected) {
            .null_value => value == .null_value,
            .boolean => |expected| value == .boolean and value.boolean == expected,
            .signed => |expected| switch (value) {
                .signed => |actual| actual == expected,
                .unsigned => |actual| expected >= 0 and actual == @as(u128, @intCast(expected)),
                .duration_ns, .timestamp_ns => |actual| actual == expected,
                else => false,
            },
            .unsigned => |expected| switch (value) {
                .unsigned => |actual| actual == expected,
                .signed => |actual| actual >= 0 and @as(u128, @intCast(actual)) == expected,
                .duration_ns, .timestamp_ns => |actual| actual >= 0 and @as(u128, @intCast(actual)) == expected,
                else => false,
            },
            .float => |expected| value == .float and value.float == expected,
            .string => |expected| value == .string and stringEquals(value.string, expected),
            .bytes => |expected| value == .bytes and hexEquals(value.bytes, expected),
            .duration_ns => |expected| value == .duration_ns and value.duration_ns == expected,
            .timestamp_ns => |expected| value == .timestamp_ns and value.timestamp_ns == expected,
        };
    }
};

pub const Options = struct {
    path: []const u8 = "",
    format: kron.Format = .text,
    level: kron.Level = .trace,
    follow: bool = false,
    recover: bool = false,
    help: bool = false,
    queries: [16]Query = undefined,
    query_count: usize = 0,

    pub fn matches(self: *const Options, event: kron.Event) bool {
        if (!self.level.allows(event.level)) return false;
        for (self.queries[0..self.query_count]) |query| if (!query.matches(event)) return false;
        return true;
    }
};

/// Arguments exclude argv[0]. All query/path strings borrow this argument list.
pub fn parseArguments(args: []const []const u8) ArgumentError!Options {
    var options: Options = .{};
    var index: usize = 0;
    var positional_only = false;
    while (index < args.len) : (index += 1) {
        const argument = args[index];
        if (!positional_only and std.mem.eql(u8, argument, "--")) {
            positional_only = true;
        } else if (!positional_only and (std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h"))) {
            options.help = true;
        } else if (!positional_only and std.mem.eql(u8, argument, "--json")) {
            options.format = .json;
        } else if (!positional_only and std.mem.eql(u8, argument, "--text")) {
            options.format = .text;
        } else if (!positional_only and (std.mem.eql(u8, argument, "--follow") or std.mem.eql(u8, argument, "-f"))) {
            options.follow = true;
        } else if (!positional_only and std.mem.eql(u8, argument, "--recover")) {
            options.recover = true;
        } else if (!positional_only and (std.mem.eql(u8, argument, "--level") or std.mem.startsWith(u8, argument, "--level="))) {
            const value = try optionValue(argument, "--level", args, &index);
            options.level = kron.Level.parse(value) catch return error.InvalidLevel;
        } else if (!positional_only and (std.mem.eql(u8, argument, "--where") or std.mem.startsWith(u8, argument, "--where="))) {
            const value = try optionValue(argument, "--where", args, &index);
            if (options.query_count == options.queries.len) return error.TooManyPredicates;
            options.queries[options.query_count] = try Query.parse(value);
            options.query_count += 1;
        } else if (!positional_only and std.mem.startsWith(u8, argument, "-")) {
            return error.UnknownOption;
        } else {
            if (options.path.len != 0) return error.MultiplePaths;
            if (argument.len == 0) return error.MissingPath;
            options.path = argument;
        }
    }
    if (!options.help and options.path.len == 0) return error.MissingPath;
    return options;
}

fn optionValue(argument: []const u8, name: []const u8, args: []const []const u8, index: *usize) error{MissingOptionValue}![]const u8 {
    const value = if (argument.len > name.len) argument[name.len + 1 ..] else blk: {
        index.* += 1;
        if (index.* == args.len) return error.MissingOptionValue;
        break :blk args[index.*];
    };
    if (value.len == 0) return error.MissingOptionValue;
    return value;
}

fn trim(bytes: []const u8) []const u8 {
    return std.mem.trim(u8, bytes, " \t\r\n");
}

fn parseExpected(literal: []const u8) error{InvalidWhere}!Expected {
    if (literal[0] == '"' or literal[0] == '\'') {
        const quote = literal[0];
        if (literal.len < 2 or literal[literal.len - 1] != quote) return error.InvalidWhere;
        const inner = literal[1 .. literal.len - 1];
        var index: usize = 0;
        while (index < inner.len) {
            if (inner[index] == quote) return error.InvalidWhere;
            _ = try literalByte(inner, &index);
        }
        return .{ .string = .{ .text = inner, .escaped = true } };
    }
    if (std.mem.eql(u8, literal, "null")) return .null_value;
    if (std.mem.eql(u8, literal, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, literal, "false")) return .{ .boolean = false };
    if (std.mem.startsWith(u8, literal, "bytes:")) {
        const hex = literal[6..];
        if (hex.len % 2 != 0) return error.InvalidWhere;
        for (hex) |byte| _ = std.fmt.charToDigit(byte, 16) catch return error.InvalidWhere;
        return .{ .bytes = hex };
    }
    if (std.mem.startsWith(u8, literal, "signed:")) return .{ .signed = std.fmt.parseInt(i128, literal[7..], 0) catch return error.InvalidWhere };
    if (std.mem.startsWith(u8, literal, "unsigned:")) return .{ .unsigned = std.fmt.parseInt(u128, literal[9..], 0) catch return error.InvalidWhere };
    if (std.mem.startsWith(u8, literal, "float:")) return .{ .float = std.fmt.parseFloat(f64, literal[6..]) catch return error.InvalidWhere };
    if (std.mem.startsWith(u8, literal, "duration_ns:")) return .{ .duration_ns = std.fmt.parseInt(i64, literal[12..], 0) catch return error.InvalidWhere };
    if (std.mem.startsWith(u8, literal, "timestamp_ns:")) return .{ .timestamp_ns = std.fmt.parseInt(i64, literal[13..], 0) catch return error.InvalidWhere };
    if (std.mem.startsWith(u8, literal, "string:")) return .{ .string = .{ .text = literal[7..] } };
    if (std.ascii.isDigit(literal[0]) or literal[0] == '-' or literal[0] == '+') {
        const number = if (literal[0] == '-' or literal[0] == '+') literal[1..] else literal;
        const based = std.mem.startsWith(u8, number, "0x") or std.mem.startsWith(u8, number, "0o") or std.mem.startsWith(u8, number, "0b");
        if (!based and std.mem.findAny(u8, literal, ".eE") != null) return .{ .float = std.fmt.parseFloat(f64, literal) catch return error.InvalidWhere };
        if (literal[0] == '-') return .{ .signed = std.fmt.parseInt(i128, literal, 0) catch return error.InvalidWhere };
        return .{ .unsigned = std.fmt.parseInt(u128, literal, 0) catch return error.InvalidWhere };
    }
    return .{ .string = .{ .text = literal } };
}

fn literalByte(bytes: []const u8, index: *usize) error{InvalidWhere}!u8 {
    const byte = bytes[index.*];
    index.* += 1;
    if (byte != '\\') return byte;
    if (index.* == bytes.len) return error.InvalidWhere;
    const escaped = bytes[index.*];
    index.* += 1;
    return switch (escaped) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        '0' => 0,
        '\\' => '\\',
        '"' => '"',
        '\'' => '\'',
        'x' => blk: {
            if (bytes.len - index.* < 2) return error.InvalidWhere;
            const high = std.fmt.charToDigit(bytes[index.*], 16) catch return error.InvalidWhere;
            const low = std.fmt.charToDigit(bytes[index.* + 1], 16) catch return error.InvalidWhere;
            index.* += 2;
            break :blk high * 16 + low;
        },
        else => error.InvalidWhere,
    };
}

fn stringEquals(actual: []const u8, expected: StringLiteral) bool {
    if (!expected.escaped) return std.mem.eql(u8, actual, expected.text);
    var index: usize = 0;
    var count: usize = 0;
    while (index < expected.text.len) : (count += 1) {
        const byte = literalByte(expected.text, &index) catch return false;
        if (count == actual.len or actual[count] != byte) return false;
    }
    return count == actual.len;
}

fn hexEquals(actual: []const u8, hex: []const u8) bool {
    if (actual.len != hex.len / 2) return false;
    for (actual, 0..) |byte, index| {
        const high = std.fmt.charToDigit(hex[index * 2], 16) catch return false;
        const low = std.fmt.charToDigit(hex[index * 2 + 1], 16) catch return false;
        if (byte != high * 16 + low) return false;
    }
    return true;
}

/// Emits every currently available matching event. Follow callers may wait
/// and retry after a partial final archive frame without consuming its offset.
pub fn emitAvailable(reader: *kron.archive.Reader, options: *const Options, writer: *std.Io.Writer) !usize {
    var count: usize = 0;
    while (true) {
        const event = (reader.next() catch |err| {
            if (options.follow and err == error.IncompleteFrame) return count;
            return err;
        }) orelse return count;
        if (!options.matches(event)) continue;
        try kron.encoder.encode(options.format, event, writer);
        count += 1;
    }
}

pub fn main(init: std.process.Init) void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    run(init, &stderr.interface) catch |err| {
        if (err != error.ReportedFailure) stderr.interface.print("kroncat: {s}\n", .{@errorName(err)}) catch {};
        stderr.interface.flush() catch {};
        std.process.exit(1);
    };
}

fn run(init: std.process.Init, stderr: *std.Io.Writer) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = parseArguments(args[1..]) catch |err| {
        try stderr.print("kroncat: {s}\n{s}", .{ @errorName(err), usage });
        return error.ReportedFailure;
    };
    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    if (options.help) {
        try stdout.interface.writeAll(usage);
        try stdout.interface.flush();
        return;
    }
    const reader = kron.archive.Reader.openOptions(init.gpa, init.io, options.path, .{ .recover_only = options.recover }) catch |err| {
        try stderr.print("kroncat: {s}: {s}\n", .{ options.path, @errorName(err) });
        return error.ReportedFailure;
    };
    defer reader.deinit();
    while (true) {
        _ = emitAvailable(reader, &options, &stdout.interface) catch |err| {
            stdout.interface.flush() catch {};
            try stderr.print("kroncat: {s}: {s} at offset={d} sequence={d}\n", .{ options.path, @errorName(err), reader.last_offset, reader.last_sequence });
            return error.ReportedFailure;
        };
        try stdout.interface.flush();
        if (!options.follow) break;
        try std.Io.sleep(init.io, .fromMilliseconds(200), .awake);
    }
}
