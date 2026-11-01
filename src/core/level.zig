const std = @import("std");

pub const Level = enum(u8) {
    trace,
    debug,
    info,
    warn,
    err,
    fatal,
    off,

    pub fn allows(threshold: Level, level: Level) bool {
        return threshold != .off and level != .off and @intFromEnum(level) >= @intFromEnum(threshold);
    }

    pub fn parse(text: []const u8) error{InvalidLevel}!Level {
        inline for (std.meta.fields(Level)) |field| {
            if (std.ascii.eqlIgnoreCase(text, field.name)) return @enumFromInt(field.value);
        }
        if (std.ascii.eqlIgnoreCase(text, "error")) return .err;
        if (std.ascii.eqlIgnoreCase(text, "warning")) return .warn;
        return error.InvalidLevel;
    }

    pub fn label(self: Level) []const u8 {
        return switch (self) {
            .err => "error",
            else => @tagName(self),
        };
    }

    pub fn severityNumber(self: Level) u8 {
        return switch (self) {
            .trace => 1,
            .debug => 5,
            .info => 9,
            .warn => 13,
            .err => 17,
            .fatal => 21,
            .off => 0,
        };
    }

    pub fn fromStd(level: std.log.Level) Level {
        return switch (level) {
            .debug => .debug,
            .info => .info,
            .warn => .warn,
            .err => .err,
        };
    }
};

test "severity ordering and disabled levels" {
    try std.testing.expect(Level.info.allows(.err));
    try std.testing.expect(!Level.info.allows(.debug));
    try std.testing.expect(!Level.off.allows(.fatal));
    try std.testing.expect(!Level.trace.allows(.off));
    try std.testing.expectEqual(Level.err, try Level.parse("ERROR"));
    try std.testing.expectError(error.InvalidLevel, Level.parse("verbose"));
    try std.testing.expectEqual(@as(u8, 17), Level.err.severityNumber());
}
