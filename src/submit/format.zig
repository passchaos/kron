//! Deferred formatting: producer-side capture stores typed values; only the
//! consumer renders them. This deliberately does not invoke custom formatters.
//! Supports {}, {any}, d/x/X/b/o/s/t/e/E, escaped braces, positional/named
//! arguments, and literal/named width and precision. Defaults and {any} print
//! the captured scalar representation, with enum/error names stored as strings.
//! Explicit arrays/groups use streamed JSON for {} and {any}; formatting
//! options for containers require a preencoded string.
//! Width is bounded at 4096 and precision at 1000. String precision follows
//! std.Io.Writer (it does not truncate); hex bytes disallow format options.
const std = @import("std");
const fields = @import("../core/field.zig");
const common = @import("../encoder/common.zig");
pub const Field = fields.Field;
pub const Value = fields.Value;

pub const max_args: usize = 64;
pub const max_width: usize = 4096;
pub const max_precision: usize = 1000;
pub const CaptureError = error{TooManyFormatArgs};
pub const ValidationError = error{
    InvalidFormat,
    UnsupportedSpecifier,
    CustomFormatterRequiresPreencoded,
    TooManyArguments,
    TooFewArguments,
    UnusedArgument,
    UnknownArgument,
    UnsupportedArgumentType,
    ArgumentTypeMismatch,
    InvalidWidth,
    InvalidPrecision,
};

pub const ArgKind = enum {
    null_value,
    boolean,
    signed,
    unsigned,
    integer,
    float,
    string,
    bytes,
    duration_ns,
    timestamp_ns,
    array,
    group,
    dynamic,
};

/// The captured representation, rather than an arbitrary object's formatter,
/// defines the schema. Optional values preserve their payload kind.
pub fn argumentKind(comptime T: type) ValidationError!ArgKind {
    if (T == Value) return .dynamic;
    if (T == fields.Bytes) return .bytes;
    if (T == fields.Duration) return .duration_ns;
    if (T == fields.Timestamp) return .timestamp_ns;
    if (T == fields.Secret) return .string;
    if (T == fields.Array) return .array;
    if (T == fields.Group) return .group;
    return switch (@typeInfo(T)) {
        .null => .null_value,
        .bool => .boolean,
        .int => |info| if (info.bits > 128) error.UnsupportedArgumentType else if (info.signedness == .signed) .signed else .unsigned,
        .comptime_int => .integer,
        .float => |info| if (info.bits > 64) error.UnsupportedArgumentType else .float,
        .comptime_float => .float,
        .@"enum", .error_set => .string,
        .optional => |info| argumentKind(info.child),
        .pointer => |info| blk: {
            if (info.size == .slice and info.child == u8) break :blk .string;
            if (info.size == .one) switch (@typeInfo(info.child)) {
                .array => |array| if (array.child == u8) break :blk .string,
                else => {},
            };
            break :blk error.UnsupportedArgumentType;
        },
        // A value array would borrow storage in capture's argument copy. Use
        // an explicit slice/pointer whose backing bytes survive submission.
        else => error.UnsupportedArgumentType,
    };
}

const Selector = union(enum) { none, number: usize, named: []const u8 };
const Spec = enum { default, decimal, hex, hex_upper, binary, octal, string, tag, any, scientific, scientific_upper };
const Placeholder = struct {
    argument: Selector = .none,
    width: Selector = .none,
    precision: Selector = .none,
    spec: Spec = .default,
    fill: u8 = ' ',
    alignment: std.fmt.Alignment = .right,
};

const Parser = struct {
    bytes: []const u8,
    index: usize = 0,

    fn selector(self: *Parser) ValidationError!Selector {
        if (self.index == self.bytes.len) return .none;
        if (self.bytes[self.index] == '[') {
            self.index += 1;
            const start = self.index;
            while (self.index < self.bytes.len and self.bytes[self.index] != ']') : (self.index += 1) {
                if (self.bytes[self.index] == '[' or self.bytes[self.index] == '{' or self.bytes[self.index] == '}') return error.InvalidFormat;
            }
            if (self.index == self.bytes.len or self.index == start) return error.InvalidFormat;
            const name = self.bytes[start..self.index];
            self.index += 1;
            return .{ .named = name };
        }
        const start = self.index;
        var number: usize = 0;
        while (self.index < self.bytes.len) : (self.index += 1) {
            const byte = self.bytes[self.index];
            if (byte < '0' or byte > '9') break;
            number = std.math.mul(usize, number, 10) catch return error.InvalidFormat;
            number = std.math.add(usize, number, byte - '0') catch return error.InvalidFormat;
        }
        return if (start == self.index) .none else .{ .number = number };
    }
};

fn parsePlaceholder(bytes: []const u8) ValidationError!Placeholder {
    var parser: Parser = .{ .bytes = bytes };
    var result: Placeholder = .{};
    result.argument = try parser.selector();
    const spec_start = parser.index;
    while (parser.index < bytes.len and bytes[parser.index] != ':') : (parser.index += 1) {}
    const spec = bytes[spec_start..parser.index];
    result.spec = if (spec.len == 0) .default else if (std.mem.eql(u8, spec, "d")) .decimal else if (std.mem.eql(u8, spec, "x")) .hex else if (std.mem.eql(u8, spec, "X")) .hex_upper else if (std.mem.eql(u8, spec, "b")) .binary else if (std.mem.eql(u8, spec, "o")) .octal else if (std.mem.eql(u8, spec, "s")) .string else if (std.mem.eql(u8, spec, "t")) .tag else if (std.mem.eql(u8, spec, "any")) .any else if (std.mem.eql(u8, spec, "e")) .scientific else if (std.mem.eql(u8, spec, "E")) .scientific_upper else if (std.mem.eql(u8, spec, "f")) return error.CustomFormatterRequiresPreencoded else return error.UnsupportedSpecifier;
    if (parser.index == bytes.len) return result;
    parser.index += 1; // colon
    if (parser.index + 1 < bytes.len and alignment(bytes[parser.index + 1]) != null) {
        result.fill = bytes[parser.index];
        if (result.fill == '{' or result.fill == '}') return error.InvalidFormat;
        parser.index += 1;
    }
    if (parser.index < bytes.len) {
        if (alignment(bytes[parser.index])) |value| {
            result.alignment = value;
            parser.index += 1;
        } else if (bytes[parser.index] == '0') result.fill = '0';
    }
    result.width = try parser.selector();
    if (parser.index < bytes.len) {
        if (bytes[parser.index] != '.') return error.InvalidFormat;
        parser.index += 1;
        result.precision = try parser.selector();
        if (result.precision == .none) return error.InvalidPrecision;
    }
    if (parser.index != bytes.len) return error.InvalidFormat;
    if (result.width == .number and result.width.number > max_width) return error.InvalidWidth;
    if (result.precision == .number and result.precision.number > max_precision) return error.InvalidPrecision;
    return result;
}

fn alignment(byte: u8) ?std.fmt.Alignment {
    return switch (byte) {
        '<' => .left,
        '^' => .center,
        '>' => .right,
        else => null,
    };
}

const Cursor = struct {
    index: usize = 0,
    next_argument: usize = 0,
    used_arguments: u64 = 0,

    fn mark(self: *Cursor, index: usize, count: usize) ValidationError!usize {
        if (index >= count) return error.TooFewArguments;
        self.used_arguments |= @as(u64, 1) << @as(u6, @intCast(index));
        return index;
    }

    fn finish(self: Cursor, count: usize) ValidationError!void {
        if (@popCount(self.used_arguments) != count) return error.UnusedArgument;
    }
};

/// Checks syntax, count and all statically known argument types without
/// formatting or evaluating argument values. Named structs and tuples work.
pub fn validate(comptime fmt: []const u8, comptime Args: type) void {
    comptime {
        check(fmt, Args) catch |err| {
            if (err == error.CustomFormatterRequiresPreencoded) @compileError("kron deferred {f} requires an explicit preencoded string; custom formatters cannot run during capture");
            if (err == error.UnsupportedArgumentType) @compileError("kron deferred format arguments must be supported scalars or borrowed strings; use an explicit slice for byte arrays and a preencoded string for custom objects (" ++ @typeName(Args) ++ ")");
            @compileError("kron deferred format: " ++ @errorName(err) ++ " in '" ++ fmt ++ "' for " ++ @typeName(Args));
        };
    }
}

/// Exposed as a fallible comptime check so tests and adapters can inspect
/// rejection reasons without making a compilation intentionally fail.
pub fn check(comptime fmt: []const u8, comptime Args: type) ValidationError!void {
    @setEvalBranchQuota(10000 + fmt.len * 1000);
    const info = switch (@typeInfo(Args)) {
        .@"struct" => |info| info,
        else => return error.UnsupportedArgumentType,
    };
    if (info.fields.len > max_args) return error.TooManyArguments;
    var cursor: Cursor = .{};
    while (cursor.index < fmt.len) {
        const byte = fmt[cursor.index];
        if (byte != '{' and byte != '}') {
            cursor.index += 1;
            continue;
        }
        if (cursor.index + 1 < fmt.len and fmt[cursor.index + 1] == byte) {
            cursor.index += 2;
            continue;
        }
        if (byte == '}') return error.InvalidFormat;
        const placeholder = try nextPlaceholder(fmt, &cursor);
        try checkDimension(placeholder.width, Args, &cursor, false);
        try checkDimension(placeholder.precision, Args, &cursor, true);
        const index = try resolveStatic(placeholder.argument, Args, &cursor);
        inline for (info.fields, 0..) |field, field_index| {
            if (index == field_index) {
                const kind = try argumentKind(field.type);
                if (!compatible(kind, placeholder.spec)) return error.ArgumentTypeMismatch;
                if ((kind == .string or kind == .bytes) and (placeholder.spec == .hex or placeholder.spec == .hex_upper) and (placeholder.width != .none or placeholder.precision != .none or placeholder.fill != ' ' or placeholder.alignment != .right)) return error.ArgumentTypeMismatch;
                if ((kind == .array or kind == .group) and (placeholder.width != .none or placeholder.precision != .none or placeholder.fill != ' ' or placeholder.alignment != .right)) return error.ArgumentTypeMismatch;
            }
        }
    }
    try cursor.finish(info.fields.len);
}

fn nextPlaceholder(fmt: []const u8, cursor: *Cursor) ValidationError!Placeholder {
    cursor.index += 1;
    const start = cursor.index;
    while (cursor.index < fmt.len and fmt[cursor.index] != '}') : (cursor.index += 1) {
        if (fmt[cursor.index] == '{') return error.InvalidFormat;
    }
    if (cursor.index == fmt.len) return error.InvalidFormat;
    const placeholder = try parsePlaceholder(fmt[start..cursor.index]);
    cursor.index += 1;
    return placeholder;
}

fn resolveStatic(selector: Selector, comptime Args: type, cursor: *Cursor) ValidationError!usize {
    const info = @typeInfo(Args).@"struct";
    const index = switch (selector) {
        .none => blk: {
            const next = cursor.next_argument;
            cursor.next_argument += 1;
            break :blk next;
        },
        .number => |number| number,
        .named => |name| blk: {
            inline for (info.fields, 0..) |field, i| if (std.mem.eql(u8, field.name, name)) break :blk i;
            return error.UnknownArgument;
        },
    };
    return cursor.mark(index, info.fields.len);
}

fn checkDimension(selector: Selector, comptime Args: type, cursor: *Cursor, precision: bool) ValidationError!void {
    if (selector != .named) return;
    const index = try resolveStatic(selector, Args, cursor);
    inline for (@typeInfo(Args).@"struct".fields, 0..) |field, i| {
        if (index == i) {
            const kind = try argumentKind(field.type);
            if (kind != .signed and kind != .unsigned and kind != .integer and kind != .dynamic) return if (precision) error.InvalidPrecision else error.InvalidWidth;
        }
    }
}

fn compatible(kind: ArgKind, spec: Spec) bool {
    if (kind == .dynamic or kind == .null_value) return true;
    const integer = kind == .signed or kind == .unsigned or kind == .integer or kind == .duration_ns or kind == .timestamp_ns;
    return switch (spec) {
        .default, .any => true,
        .decimal => integer or kind == .float,
        .hex, .hex_upper => integer or kind == .float or kind == .string or kind == .bytes,
        .binary, .octal => integer,
        .scientific, .scientific_upper => kind == .float,
        .string => kind == .string or kind == .bytes,
        .tag => kind == .string,
    };
}

/// Captures each scalar into the caller's fixed storage. Borrowed strings are
/// copied by the event codec before acceptance; no formatter runs here.
pub fn capture(comptime fmt: []const u8, args: anytype, destination: []Field) CaptureError![]const Field {
    const Args = @TypeOf(args);
    validate(fmt, Args);
    const info = @typeInfo(Args).@"struct";
    if (destination.len < info.fields.len) return error.TooManyFormatArgs;
    inline for (info.fields, 0..) |field, index| {
        destination[index] = .{ .key = field.name, .value = fields.fromAny(@field(args, field.name)) };
    }
    return destination[0..info.fields.len];
}

fn resolveRuntime(selector: Selector, args: []const Field, cursor: *Cursor) ValidationError!usize {
    const index = switch (selector) {
        .none => blk: {
            const next = cursor.next_argument;
            cursor.next_argument += 1;
            break :blk next;
        },
        .number => |number| number,
        .named => |name| blk: {
            for (args, 0..) |field, i| if (std.mem.eql(u8, field.key, name)) break :blk i;
            return error.UnknownArgument;
        },
    };
    return cursor.mark(index, args.len);
}

fn dimensionRuntime(selector: Selector, args: []const Field, cursor: *Cursor, precision: bool) ValidationError!?usize {
    const value = switch (selector) {
        .none => return null,
        .number => |number| number,
        .named => blk: {
            const index = try resolveRuntime(selector, args, cursor);
            const result: ?usize = switch (args[index].value) {
                .signed => |number| std.math.cast(usize, number),
                .unsigned => |number| std.math.cast(usize, number),
                else => null,
            };
            break :blk result orelse return if (precision) error.InvalidPrecision else error.InvalidWidth;
        },
    };
    if (value > (if (precision) max_precision else max_width)) return if (precision) error.InvalidPrecision else error.InvalidWidth;
    return value;
}

/// Renders a recovered runtime template without panicking on malformed
/// records. Syntax/type errors map to the Writer's normal error contract.
pub fn render(fmt: []const u8, args: []const Field, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (args.len > max_args) return error.WriteFailed;
    var validator: fields.ValueValidator = .{};
    validator.arguments(args) catch return error.WriteFailed;
    var cursor: Cursor = .{};
    while (cursor.index < fmt.len) {
        const start = cursor.index;
        while (cursor.index < fmt.len and fmt[cursor.index] != '{' and fmt[cursor.index] != '}') : (cursor.index += 1) {}
        try writer.writeAll(fmt[start..cursor.index]);
        if (cursor.index == fmt.len) break;
        const byte = fmt[cursor.index];
        if (cursor.index + 1 < fmt.len and fmt[cursor.index + 1] == byte) {
            try writer.writeByte(byte);
            cursor.index += 2;
            continue;
        }
        if (byte == '}') return error.WriteFailed;
        const placeholder = nextPlaceholder(fmt, &cursor) catch return error.WriteFailed;
        const width = dimensionRuntime(placeholder.width, args, &cursor, false) catch return error.WriteFailed;
        const precision = dimensionRuntime(placeholder.precision, args, &cursor, true) catch return error.WriteFailed;
        const index = resolveRuntime(placeholder.argument, args, &cursor) catch return error.WriteFailed;
        const options: std.fmt.Options = .{ .fill = placeholder.fill, .alignment = placeholder.alignment, .width = width, .precision = precision };
        try renderValue(args[index].value, placeholder.spec, options, writer);
    }
    cursor.finish(args.len) catch return error.WriteFailed;
}

fn renderValue(value: Value, spec: Spec, options: std.fmt.Options, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    // Null is permitted for optional arguments with any supported specifier.
    if (value == .null_value) return writer.alignBufferOptions("null", options);
    const kind: ArgKind = switch (value) {
        .null_value => .null_value,
        .boolean => .boolean,
        .signed => .signed,
        .unsigned => .unsigned,
        .float => .float,
        .string => .string,
        .bytes => .bytes,
        .duration_ns => .duration_ns,
        .timestamp_ns => .timestamp_ns,
        .array => .array,
        .group => .group,
    };
    if (!compatible(kind, spec)) return error.WriteFailed;
    switch (value) {
        .null_value => unreachable,
        .boolean => |boolean| try writer.alignBufferOptions(if (boolean) "true" else "false", options),
        .signed => |number| try renderInteger(number, spec, options, writer),
        .unsigned => |number| try renderInteger(number, spec, options, writer),
        .duration_ns, .timestamp_ns => |number| try renderInteger(number, spec, options, writer),
        .float => |number| switch (spec) {
            .hex, .hex_upper => try renderFloatHex(number, spec, options, writer),
            else => try renderFloat(number, spec, options, writer),
        },
        .string, .bytes => |bytes| {
            if (spec == .hex or spec == .hex_upper) {
                // Hex bytes do not use the number formatter's width/precision.
                if (options.width != null or options.precision != null or options.fill != ' ' or options.alignment != .right) return error.WriteFailed;
                try writer.printHex(bytes, if (spec == .hex_upper) .upper else .lower);
            } else try writer.alignBufferOptions(bytes, options);
        },
        .array, .group => {
            if (options.width != null or options.precision != null or options.fill != ' ' or options.alignment != .right) return error.WriteFailed;
            try common.value(writer, value, .json);
        },
    }
}

fn renderFloat(value: f64, spec: Spec, options: std.fmt.Options, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    // The std writer's fixed 347-byte float buffer cannot hold all accepted
    // precision values. Size this consumer-only scratch space for the bound.
    var buffer: [max_precision + std.fmt.float.bufferSize(.decimal, f64) + 8]u8 = undefined;
    const mode: std.fmt.float.Mode = switch (spec) {
        .default, .any, .scientific, .scientific_upper => .scientific,
        else => .decimal,
    };
    const rendered = std.fmt.float.render(&buffer, value, .{ .mode = mode, .precision = options.precision }) catch return error.WriteFailed;
    try writer.alignBufferOptions(rendered, options);
}

fn renderFloatHex(value: f64, spec: Spec, options: std.fmt.Options, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    // printFloatHexOptions assumes a 50-byte buffer and panics on excessive
    // precision. The lower-level formatter returns errors with our full bound.
    var buffer: [max_precision + 50]u8 = undefined;
    var scratch = std.Io.Writer.fixed(&buffer);
    try scratch.printFloatHex(value, if (spec == .hex_upper) .upper else .lower, options.precision);
    try writer.alignBufferOptions(scratch.buffered(), options);
}

fn renderInteger(value: anytype, spec: Spec, options: std.fmt.Options, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const base: u8 = switch (spec) {
        .hex, .hex_upper => 16,
        .binary => 2,
        .octal => 8,
        else => 10,
    };
    try writer.printInt(value, base, if (spec == .hex_upper) .upper else .lower, options);
}

test "capture preserves typed scalar arguments and erases secrets" {
    var storage: [4]Field = undefined;
    const args = try capture("{d} {s} {any} {d}", .{ @as(i64, -123), fields.secret("original"), true, @as(f64, 3.25) }, &storage);
    try std.testing.expectEqual(@as(i128, -123), args[0].value.signed);
    try std.testing.expectEqualStrings(fields.redacted, args[1].value.string);
    try std.testing.expect(args[2].value.boolean);
    try std.testing.expectEqual(@as(f64, 3.25), args[3].value.float);
    try std.testing.expectError(error.TooManyFormatArgs, capture("{d}", .{1}, &.{}));
}

test "comptime syntax count and type rejection are inspectable" {
    try comptime check("{{ {1x} {0d} }} {1x}", @TypeOf(.{ @as(i32, 1), @as(u32, 2) }));
    try std.testing.expectError(error.InvalidFormat, comptime check("{", @TypeOf(.{})));
    try std.testing.expectError(error.InvalidFormat, comptime check("}", @TypeOf(.{})));
    try std.testing.expectError(error.UnsupportedSpecifier, comptime check("{q}", @TypeOf(.{1})));
    try std.testing.expectError(error.CustomFormatterRequiresPreencoded, comptime check("{f}", @TypeOf(.{1})));
    try std.testing.expectError(error.CustomFormatterRequiresPreencoded, comptime check("{f}", @TypeOf(.{.{ .custom = 1 }})));
    try std.testing.expectError(error.TooFewArguments, comptime check("{} {}", @TypeOf(.{1})));
    try std.testing.expectError(error.UnusedArgument, comptime check("{}", @TypeOf(.{ 1, 2 })));
    try std.testing.expectError(error.ArgumentTypeMismatch, comptime check("{d}", @TypeOf(.{"text"})));
    try std.testing.expectError(error.ArgumentTypeMismatch, comptime check("{s}", @TypeOf(.{1})));
    try std.testing.expectError(error.UnsupportedArgumentType, comptime check("{any}", @TypeOf(.{.{ .nested = 1 }})));
    try std.testing.expectError(error.UnsupportedArgumentType, comptime check("{s}", @TypeOf(.{[_]u8{'x'}})));
}

test "runtime rendering supports float escaped braces indices bases and widths" {
    var storage: [5]Field = undefined;
    const fmt = "{{{1s:_^7}}} {0d:04} {2d:.2} {3b} {4o} {0x}";
    const args = try capture(fmt, .{ @as(u32, 15), "hi", @as(f64, 3.25), @as(u8, 5), @as(u8, 9) }, &storage);
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render(fmt, args, &writer);
    try std.testing.expectEqualStrings("{__hi___} 0015 3.25 101 11 f", writer.buffered());
}

test "named width precision tag and optional rendering" {
    const Ready = enum { ready };
    const value: ?u32 = null;
    var storage: [5]Field = undefined;
    const fmt = "{[state]t} {[value]d} {[number]d:[width].[precision]}";
    const args = try capture(fmt, .{ .state = Ready.ready, .value = value, .number = @as(f64, 2.5), .width = @as(u8, 7), .precision = @as(u8, 2) }, &storage);
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render(fmt, args, &writer);
    try std.testing.expectEqualStrings("ready null    2.50", writer.buffered());
}

test "invalid runtime templates and argument types return writer errors" {
    const args = [_]Field{fields.kv("0", "text")};
    inline for (.{ "{", "}", "{f}", "{q}", "{d}", "{1s}", "{s:999999}", "{s:.}", "{s} {}", "{[missing]s}" }) |fmt| {
        var buffer: [64]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try std.testing.expectError(error.WriteFailed, render(fmt, &args, &writer));
    }
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.WriteFailed, render("plain", &args, &writer));
}

test "consumer handles maximum precision without standard writer buffer panic" {
    var storage: [1]Field = undefined;
    const args = try capture("{d:.1000}", .{@as(f64, 1.25)}, &storage);
    var buffer: [1400]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render("{d:.1000}", args, &writer);
    try std.testing.expectEqual(@as(usize, 1002), writer.buffered().len);
    try std.testing.expect(std.mem.startsWith(u8, writer.buffered(), "1.25"));
    writer.end = 0;
    try render("{x:.1000}", args, &writer);
    try std.testing.expectEqual(@as(usize, 1006), writer.buffered().len);
    try std.testing.expect(std.mem.startsWith(u8, writer.buffered(), "0x1.4"));
    try std.testing.expect(std.mem.endsWith(u8, writer.buffered(), "p0"));
    try std.testing.expectError(error.InvalidPrecision, comptime check("{d:.1001}", @TypeOf(.{@as(f64, 1.0)})));
}

test "integer extremes and fixed writer failure are safe" {
    var storage: [2]Field = undefined;
    const args = try capture("{d} {x}", .{ std.math.minInt(i128), std.math.maxInt(u128) }, &storage);
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render("{d} {x}", args, &writer);
    try std.testing.expectEqualStrings("-170141183460469231731687303715884105728 ffffffffffffffffffffffffffffffff", writer.buffered());
    var small: [1]u8 = undefined;
    var failed = std.Io.Writer.fixed(&small);
    try std.testing.expectError(error.WriteFailed, render("{d} {x}", args, &failed));
    const too_many = [_]Field{fields.kv("", 1)} ** (max_args + 1);
    writer.end = 0;
    try std.testing.expectError(error.WriteFailed, render("", &too_many, &writer));
}

test "dynamic invalid width and hex string options are rejected" {
    const args = [_]Field{ fields.kv("value", 1.0), fields.kv("width", @as(i8, -1)) };
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.WriteFailed, render("{[value]d:[width]}", &args, &writer));
    try std.testing.expectError(error.ArgumentTypeMismatch, comptime check("{x:5}", @TypeOf(.{"text"})));
    try std.testing.expectError(error.InvalidWidth, comptime check("{[value]d:[width]}", @TypeOf(.{ .value = 1, .width = "bad" })));
    const bytes = [_]Field{fields.kv("0", fields.bytes("\x00\xff"))};
    writer.end = 0;
    try render("{X}", &bytes, &writer);
    try std.testing.expectEqualStrings("00FF", writer.buffered());
}

test "nested deferred defaults stream JSON while scalar specifiers reject containers" {
    const items = [_]Value{ fields.fromAny("line\n\""), fields.fromAny(fields.secret("nested-format-secret")), .{ .group = &.{fields.kv("ok", true)} } };
    const nested = fields.array(&items);
    try comptime check("{} {any}", @TypeOf(.{ nested, fields.group(&.{fields.kv("key", 1)}) }));
    try std.testing.expectError(error.ArgumentTypeMismatch, comptime check("{s}", @TypeOf(.{nested})));
    try std.testing.expectError(error.ArgumentTypeMismatch, comptime check("{d}", @TypeOf(.{nested})));
    try std.testing.expectError(error.ArgumentTypeMismatch, comptime check("{any:8}", @TypeOf(.{nested})));
    var storage: [1]Field = undefined;
    const args = try capture("{any}", .{nested}, &storage);
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render("{any}", args, &writer);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, writer.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("line\n\"", parsed.value.array.items[0].string);
    try std.testing.expectEqualStrings(fields.redacted, parsed.value.array.items[1].string);
    try std.testing.expect(parsed.value.array.items[2].object.get("ok").?.bool);
    inline for (.{ "{s}", "{d}", "{t}", "{any:8}" }) |fmt| {
        writer = std.Io.Writer.fixed(&buffer);
        try std.testing.expectError(error.WriteFailed, render(fmt, &.{fields.kv("", fields.fromAny(nested))}, &writer));
    }
    var small: [12]u8 = undefined;
    writer = std.Io.Writer.fixed(&small);
    try std.testing.expectError(error.WriteFailed, render("{any}", args, &writer));
}
