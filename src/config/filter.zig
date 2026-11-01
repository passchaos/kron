const std = @import("std");
const Level = @import("../core/level.zig").Level;

pub const max_rules = 64;
pub const max_scope_bytes = 4096;

pub const ParseError = error{
    EmptyDirective,
    InvalidLevel,
    InvalidScope,
    TooManyRules,
    ScopeBudgetExceeded,
};

/// Byte offset into the original specification, including its whitespace.
pub const ParseDiagnostic = struct {
    kind: ParseError,
    offset: usize,
};

const Rule = struct {
    offset: u16,
    len: u16,
    level: Level,
};

/// A bounded, owning filter. Offsets make value copies independent of the
/// original specification and of the address of this value.
pub const Filter = struct {
    default_level: Level = .info,
    rule_count: usize = 0,
    scope_bytes_used: usize = 0,
    rules: [max_rules]Rule = undefined,
    scope_bytes: [max_scope_bytes]u8 = undefined,

    pub fn parse(spec: []const u8) ParseError!Filter {
        var diagnostic: ?ParseDiagnostic = null;
        return parseDetailed(spec, &diagnostic);
    }

    pub fn parseDetailed(spec: []const u8, diagnostic: *?ParseDiagnostic) ParseError!Filter {
        diagnostic.* = null;
        var filter: Filter = .{};
        // An absent/empty application specification selects library defaults.
        if (std.mem.trim(u8, spec, " \t\r\n").len == 0) return filter;

        var start: usize = 0;
        while (true) {
            const end = if (std.mem.indexOfScalarPos(u8, spec, start, ',')) |i| i else spec.len;
            var first = start;
            while (first < end and isWhitespace(spec[first])) : (first += 1) {}
            var last = end;
            while (last > first and isWhitespace(spec[last - 1])) : (last -= 1) {}
            if (first == last) return fail(diagnostic, error.EmptyDirective, first);

            const directive = spec[first..last];
            if (std.mem.indexOfScalar(u8, directive, '=')) |equals| {
                var scope_end = equals;
                while (scope_end > 0 and isWhitespace(directive[scope_end - 1])) : (scope_end -= 1) {}
                const scope = directive[0..scope_end];
                if (invalidScopeOffset(scope)) |offset|
                    return fail(diagnostic, error.InvalidScope, first + offset);
                var level_start = equals + 1;
                while (level_start < directive.len and isWhitespace(directive[level_start])) : (level_start += 1) {}
                const level = parseLevel(directive[level_start..]) orelse
                    return fail(diagnostic, error.InvalidLevel, first + level_start);
                try filter.put(scope, level, first, diagnostic);
            } else {
                filter.default_level = parseLevel(directive) orelse
                    return fail(diagnostic, error.InvalidLevel, first);
            }
            if (end == spec.len) break;
            start = end + 1;
        }
        return filter;
    }

    pub fn threshold(self: *const Filter, scope: []const u8) Level {
        var level = self.default_level;
        var longest: usize = 0;
        for (self.rules[0..self.rule_count]) |rule| {
            const prefix = self.scope_bytes[rule.offset..][0..rule.len];
            if (prefix.len > longest and scopeMatches(prefix, scope)) {
                longest = prefix.len;
                level = rule.level;
            }
        }
        return level;
    }

    pub fn enabled(self: *const Filter, level: Level, scope: []const u8) bool {
        return levelEnabled(level, self.threshold(scope));
    }

    fn put(self: *Filter, scope: []const u8, level: Level, offset: usize, diagnostic: *?ParseDiagnostic) ParseError!void {
        for (self.rules[0..self.rule_count]) |*rule| {
            const previous = self.scope_bytes[rule.offset..][0..rule.len];
            if (std.mem.eql(u8, previous, scope)) {
                rule.level = level;
                return;
            }
        }
        if (self.rule_count == max_rules) return fail(diagnostic, error.TooManyRules, offset);
        if (scope.len > max_scope_bytes - self.scope_bytes_used)
            return fail(diagnostic, error.ScopeBudgetExceeded, offset);
        self.rules[self.rule_count] = .{
            .offset = @intCast(self.scope_bytes_used),
            .len = @intCast(scope.len),
            .level = level,
        };
        @memcpy(self.scope_bytes[self.scope_bytes_used..][0..scope.len], scope);
        self.scope_bytes_used += scope.len;
        self.rule_count += 1;
    }
};

pub fn levelEnabled(level: Level, threshold: Level) bool {
    return level != .off and threshold != .off and @intFromEnum(level) >= @intFromEnum(threshold);
}

pub fn scopeMatches(prefix: []const u8, scope: []const u8) bool {
    return std.mem.startsWith(u8, scope, prefix) and
        (scope.len == prefix.len or scope[prefix.len] == '.');
}

pub fn parseLevel(text: []const u8) ?Level {
    return Level.parse(text) catch null;
}

fn invalidScopeOffset(scope: []const u8) ?usize {
    if (scope.len == 0) return 0;
    var component_start = true;
    for (scope, 0..) |byte, i| {
        if (byte == '.') {
            if (component_start) return i;
            component_start = true;
        } else {
            if (byte <= ' ' or byte == 0x7f or byte == '=' or byte == ',') return i;
            component_start = false;
        }
    }
    if (component_start) return scope.len - 1;
    return null;
}

fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}

fn fail(diagnostic: *?ParseDiagnostic, kind: ParseError, offset: usize) ParseError {
    diagnostic.* = .{ .kind = kind, .offset = offset };
    return kind;
}

test "longest component match, off, and duplicate last wins" {
    const filter = try Filter.parse("info,http=debug,db.query=trace,noisy=off,http.server=warn,http=trace");
    try std.testing.expectEqual(Level.trace, filter.threshold("http.client"));
    try std.testing.expectEqual(Level.warn, filter.threshold("http.server.request"));
    try std.testing.expectEqual(Level.info, filter.threshold("httpx"));
    try std.testing.expectEqual(Level.info, filter.threshold("db.queryx"));
    try std.testing.expectEqual(Level.trace, filter.threshold("db.query.execute"));
    try std.testing.expect(!filter.enabled(.fatal, "noisy.worker"));
    try std.testing.expect(!filter.enabled(.off, "http"));
    try std.testing.expect(filter.enabled(.debug, "http"));
    try std.testing.expect(!filter.enabled(.info, "http.server"));
    try std.testing.expectEqual(@as(usize, 4), filter.rule_count);
}

test "parse diagnostics preserve original byte positions" {
    var diagnostic: ?ParseDiagnostic = null;
    try std.testing.expectError(error.InvalidLevel, Filter.parseDetailed(" info, http = verbose", &diagnostic));
    try std.testing.expectEqual(@as(usize, 14), diagnostic.?.offset);
    try std.testing.expectError(error.InvalidScope, Filter.parseDetailed("info,db..query=trace", &diagnostic));
    try std.testing.expectEqual(@as(usize, 8), diagnostic.?.offset);
    try std.testing.expectError(error.EmptyDirective, Filter.parseDetailed("info,", &diagnostic));
    try std.testing.expectEqual(@as(usize, 5), diagnostic.?.offset);
    try std.testing.expectError(error.InvalidScope, Filter.parse("info,=trace"));
    try std.testing.expectError(error.InvalidLevel, Filter.parse("http=debug=info"));
    _ = try Filter.parseDetailed(" warn , http = trace ", &diagnostic);
    try std.testing.expect(diagnostic == null);
}

test "filter owns scope bytes and copies preserve ownership" {
    var spec = "info,http=trace".*;
    const filter = try Filter.parse(&spec);
    @memset(&spec, 'x');
    const copied = filter;
    try std.testing.expectEqual(Level.trace, copied.threshold("http.child"));
}

test "fixed budgets reject excess without penalizing duplicates" {
    var bytes: [max_scope_bytes + 6]u8 = undefined;
    @memset(bytes[0..max_scope_bytes], 's');
    @memcpy(bytes[max_scope_bytes..], "=trace");
    const filter = try Filter.parse(&bytes);
    try std.testing.expectEqual(@as(usize, max_scope_bytes), filter.scope_bytes_used);
    var oversized: [max_scope_bytes + 7]u8 = undefined;
    @memset(oversized[0 .. max_scope_bytes + 1], 's');
    @memcpy(oversized[max_scope_bytes + 1 ..], "=trace");
    try std.testing.expectError(error.ScopeBudgetExceeded, Filter.parse(&oversized));

    var spec_buffer: [2048]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&spec_buffer);
    for (0..max_rules) |i| try writer.print("s{d}=info,", .{i});
    try writer.writeAll("s0=trace");
    const duplicate = try Filter.parse(writer.buffered());
    try std.testing.expectEqual(@as(usize, max_rules), duplicate.rule_count);
    try std.testing.expectEqual(Level.trace, duplicate.threshold("s0"));
    try writer.writeAll(",extra=info");
    try std.testing.expectError(error.TooManyRules, Filter.parse(writer.buffered()));
}
