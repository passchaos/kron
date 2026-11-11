//! Crash-report naming, fixed-buffer formatting, and UTC timestamp helpers.
//!
//! The helpers are pure so naming and UTC conversion can be verified without
//! writing files or installing signal handlers. `Writer` bounds the complete
//! report in caller storage and marks truncation instead of failing the crash
//! path.
const std = @import("std");
const signal = @import("signal.zig");

pub const max_component = 64;
pub const max_path = std.Io.Dir.max_path_bytes;
pub const max_name = 3 * max_component + 64;
pub const max_report_bytes = 32 * 1024;

/// Replaces characters that are unsafe in a single path component. Empty
/// inputs become `unknown`, so a report always has a name.
pub fn sanitize(destination: []u8, input: []const u8) []const u8 {
    if (destination.len == 0) return destination[0..0];
    var written: usize = 0;
    for (input) |byte| {
        if (written == destination.len) break;
        const safe = switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9', '.', '_', '-' => byte,
            else => '_',
        };
        destination[written] = safe;
        written += 1;
    }
    if (written == 0) {
        const fallback = "unknown";
        const length = @min(fallback.len, destination.len);
        @memcpy(destination[0..length], fallback[0..length]);
        return destination[0..length];
    }
    return destination[0..written];
}

/// Formats `unix_seconds` as `YYYYMMDD-HHMMSS` in UTC.
pub fn formatTimestamp(buffer: []u8, unix_seconds: i64) ![]const u8 {
    const seconds: u64 = if (unix_seconds < 0) 0 else @intCast(unix_seconds);
    const epoch = std.time.epoch.EpochSeconds{ .secs = seconds };
    const day = epoch.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    return std.fmt.bufPrint(buffer, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        @as(u8, month_day.day_index) + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

/// Formats `unix_seconds` as an RFC3339-like UTC timestamp.
pub fn formatIsoTimestamp(buffer: []u8, unix_seconds: i64) ![]const u8 {
    const seconds: u64 = if (unix_seconds < 0) 0 else @intCast(unix_seconds);
    const epoch = std.time.epoch.EpochSeconds{ .secs = seconds };
    const day = epoch.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        @as(u8, month_day.day_index) + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

fn directoryPrefix(directory: []const u8) []const u8 {
    if (directory.len == 0) return ".";
    if (std.mem.eql(u8, directory, "/")) return "";
    return if (directory[directory.len - 1] == '/') directory[0 .. directory.len - 1] else directory;
}

/// Builds `<program>.<host>.<user>.log.FATAL.<timestamp>.<pid>` without a
/// directory. This is the crash name used with a pre-opened directory handle.
pub fn crashNameZ(
    buffer: []u8,
    program: []const u8,
    host: []const u8,
    user: []const u8,
    unix_seconds: i64,
    pid: i32,
    attempt: u32,
) ![:0]const u8 {
    var timestamp_buffer: [32]u8 = undefined;
    const timestamp = try formatTimestamp(&timestamp_buffer, unix_seconds);
    if (attempt == 0) {
        return std.fmt.bufPrintZ(buffer, "{s}.{s}.{s}.log.FATAL.{s}.{d}", .{
            program, host, user, timestamp, pid,
        });
    }
    return std.fmt.bufPrintZ(buffer, "{s}.{s}.{s}.log.FATAL.{s}.{d}-{d}", .{
        program, host, user, timestamp, pid, attempt,
    });
}

pub fn crashName(
    buffer: []u8,
    program: []const u8,
    host: []const u8,
    user: []const u8,
    unix_seconds: i64,
    pid: i32,
    attempt: u32,
) ![]const u8 {
    return crashNameZ(buffer, program, host, user, unix_seconds, pid, attempt);
}

/// Builds `<directory>/<program>.<host>.<user>.log.FATAL.<timestamp>.<pid>`.
/// A non-zero `attempt` adds a collision suffix before the final `.log`.
pub fn fileNameZ(
    buffer: []u8,
    directory: []const u8,
    program: []const u8,
    host: []const u8,
    user: []const u8,
    unix_seconds: i64,
    pid: i32,
    attempt: u32,
) ![:0]const u8 {
    var timestamp_buffer: [32]u8 = undefined;
    const timestamp = try formatTimestamp(&timestamp_buffer, unix_seconds);
    const prefix = directoryPrefix(directory);
    if (attempt == 0) {
        return std.fmt.bufPrintZ(buffer, "{s}/{s}.{s}.{s}.log.FATAL.{s}.{d}", .{
            prefix, program, host, user, timestamp, pid,
        });
    }
    return std.fmt.bufPrintZ(buffer, "{s}/{s}.{s}.{s}.log.FATAL.{s}.{d}-{d}", .{
        prefix, program, host, user, timestamp, pid, attempt,
    });
}

pub fn fileName(
    buffer: []u8,
    directory: []const u8,
    program: []const u8,
    host: []const u8,
    user: []const u8,
    unix_seconds: i64,
    pid: i32,
    attempt: u32,
) ![]const u8 {
    return fileNameZ(buffer, directory, program, host, user, unix_seconds, pid, attempt);
}

/// Builds the stable `<program>.FATAL` link name without a directory.
pub fn latestName(buffer: []u8, program: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{s}.FATAL", .{program});
}

/// Builds the stable `<directory>/<program>.FATAL` symlink path.
pub fn latestLink(buffer: []u8, directory: []const u8, program: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{s}/{s}.FATAL", .{ directoryPrefix(directory), program });
}

pub fn signalLabel(value: signal.Signal) []const u8 {
    return signal.label(value);
}

/// Fixed-buffer report writer. Formatting stops at the buffer limit and
/// `finish` appends a truncation marker when the report did not fit.
pub const Writer = struct {
    const marker = "\n[report truncated]\n";

    inner: std.Io.Writer,
    storage: []u8,
    truncated: bool = false,

    pub fn init(buffer: []u8) Writer {
        const usable = if (buffer.len > marker.len) buffer[0 .. buffer.len - marker.len] else buffer[0..0];
        return .{ .inner = std.Io.Writer.fixed(usable), .storage = buffer };
    }

    pub fn print(self: *Writer, comptime fmt: []const u8, args: anytype) void {
        self.inner.print(fmt, args) catch {
            self.truncated = true;
        };
    }

    pub fn write(self: *Writer, bytes: []const u8) void {
        self.inner.writeAll(bytes) catch {
            self.truncated = true;
        };
    }

    pub fn finish(self: *Writer) []const u8 {
        if (self.truncated and self.inner.end + marker.len <= self.storage.len) {
            const end = self.inner.end;
            @memcpy(self.storage[end .. end + marker.len], marker);
            self.inner.end = end + marker.len;
        }
        return self.storage[0..self.inner.end];
    }
};

test "component sanitization keeps safe bytes and replaces separators" {
    var buffer: [max_component]u8 = undefined;
    try std.testing.expectEqualStrings("app_1.2-3", sanitize(&buffer, "app/1.2-3"));
    try std.testing.expectEqualStrings("a_b_c", sanitize(&buffer, "a b\nc"));
    try std.testing.expectEqualStrings("unknown", sanitize(&buffer, ""));
    try std.testing.expectEqualStrings("___", sanitize(&buffer, "///"));
}

test "component sanitization truncates at the component budget" {
    var buffer: [4]u8 = undefined;
    try std.testing.expectEqualStrings("abcd", sanitize(&buffer, "abcdefgh"));
}

test "UTC timestamp formatting handles epoch and leap day" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("19700101-000000", try formatTimestamp(&buffer, 0));
    try std.testing.expectEqualStrings("20240229-235959", try formatTimestamp(&buffer, 1709251199));
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", try formatIsoTimestamp(&buffer, 0));
}

test "crash file names follow the glog-style pattern" {
    var buffer: [max_path]u8 = undefined;
    try std.testing.expectEqualStrings(
        "app.host.user.log.FATAL.20240229-235959.1234",
        try crashName(&buffer, "app", "host", "user", 1709251199, 1234, 0),
    );
    try std.testing.expectEqualStrings(
        "/var/crash/app.host.user.log.FATAL.20240229-235959.1234",
        try fileName(&buffer, "/var/crash", "app", "host", "user", 1709251199, 1234, 0),
    );
    try std.testing.expectEqualStrings(
        "crash/app.host.user.log.FATAL.20240229-235959.1234-2",
        try fileName(&buffer, "crash/", "app", "host", "user", 1709251199, 1234, 2),
    );
    try std.testing.expectEqualStrings("app.FATAL", try latestName(&buffer, "app"));
    try std.testing.expectEqualStrings("/var/crash/app.FATAL", try latestLink(&buffer, "/var/crash", "app"));
}

test "fixed report writer marks truncation instead of failing" {
    var buffer: [64]u8 = undefined;
    var writer = Writer.init(&buffer);
    writer.write("header\n");
    writer.write("x" ** 128);
    const text = writer.finish();
    try std.testing.expect(std.mem.startsWith(u8, text, "header\n"));
    try std.testing.expect(std.mem.endsWith(u8, text, "[report truncated]\n"));
}
