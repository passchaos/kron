//! System local-time conversion. Configuration reads the timezone identity;
//! rendering calls the platform converter only on a formatter's second miss.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

pub const supported = switch (builtin.os.tag) {
    .windows => true,
    .linux, .macos, .ios => builtin.link_libc,
    else => false,
};
pub const Error = types.Error || error{ LocalTimeUnavailable, LocalTimeConversionFailed, NonMinuteLocalOffset };
pub const Identity = [16]u8;

pub const TestingAudit = if (builtin.is_test) struct {
    pub var conversions: std.atomic.Value(usize) = .init(0);
    pub var thread_id: std.atomic.Value(std.Thread.Id) = .init(0);
} else struct {};

/// Capture rules provenance during configuration, never while submitting logs.
/// The process timezone environment must remain stable while routes use it.
pub fn identity(io: std.Io) !Identity {
    if (comptime !supported) return error.LocalTimeUnavailable;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("kron-system-local-v1");
    if (comptime builtin.os.tag == .windows) {
        const zone = try windowsZone();
        hash.update(std.mem.asBytes(&zone));
    } else {
        const environment = if (std.c.getenv("TZ")) |value| std.mem.span(value) else null;
        if (environment) |value| {
            if (value.len > 4096) return error.LocalTimeIdentityTooLarge;
            hash.update("TZ:");
            hash.update(value);
            if (value.len == 0) return finishIdentity(&hash);
            const name = if (value[0] == ':') value[1..] else value;
            if (name.len == 0) return error.InvalidLocalTimeZone;
            if (std.fs.path.isAbsolute(name)) {
                try hashZoneFile(io, name, &hash);
            } else if (std.mem.indexOfScalar(u8, name, '/') != null or std.mem.indexOfAny(u8, name, "0123456789,+-") == null) {
                // Named zone: include file bytes so tzdata upgrades cannot
                // silently change the presentation of recovered records.
                if (comptime builtin.abi == .android) {
                    try hashAndroidRules(io, &hash);
                } else {
                    var path_bytes: [8192]u8 = undefined;
                    const directory = if (std.c.getenv("TZDIR")) |tzdir| std.mem.span(tzdir) else "/usr/share/zoneinfo";
                    if (directory.len > 4096) return error.LocalTimeIdentityTooLarge;
                    const path = try std.fmt.bufPrint(&path_bytes, "{s}/{s}", .{ directory, name });
                    try hashZoneFile(io, path, &hash);
                }
            }
            // POSIX TZ expressions include their full rule string above.
        } else {
            hash.update("system:");
            if (comptime builtin.abi == .android) {
                var property: [128]u8 = @splat(0);
                const length = __system_property_get("persist.sys.timezone", &property);
                if (length <= 0 or length >= property.len) return error.InvalidLocalTimeZone;
                hash.update(property[0..@intCast(length)]);
                try hashAndroidRules(io, &hash);
            } else try hashZoneFile(io, "/etc/localtime", &hash);
        }
    }
    return finishIdentity(&hash);
}

fn hashZoneFile(io: std.Io, path: []const u8, hash: *std.crypto.hash.sha2.Sha256) !void {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &.{});
    var total: usize = 0;
    while (true) {
        const size = reader.interface.readSliceShort(&buffer) catch return reader.err.?;
        total += size;
        if (total > 4 * 1024 * 1024) return error.LocalTimeIdentityTooLarge;
        hash.update(buffer[0..size]);
        if (size < buffer.len) return;
    }
}

extern "c" fn __system_property_get([*:0]const u8, [*]u8) c_int;

fn hashAndroidRules(io: std.Io, hash: *std.crypto.hash.sha2.Sha256) !void {
    hashZoneFile(io, "/apex/com.android.tzdata/etc/tz/tzdata", hash) catch |err| switch (err) {
        error.FileNotFound => try hashZoneFile(io, "/system/usr/share/zoneinfo/tzdata", hash),
        else => return err,
    };
}

fn finishIdentity(hash: *std.crypto.hash.sha2.Sha256) Identity {
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return digest[0..16].*;
}

/// Convert the event's instant, including the operating system's DST rules.
/// Sub-minute historic offsets cannot be represented by RFC3339; reject them.
pub fn offsetAt(seconds: i64) Error!types.UtcOffset {
    return (try convert(seconds)).offset;
}

pub const Converted = struct { date_time: types.civil.DateTime, offset: types.UtcOffset };

pub fn convert(seconds: i64) Error!Converted {
    if (comptime !supported) return error.LocalTimeUnavailable;
    if (builtin.is_test) {
        _ = TestingAudit.conversions.fetchAdd(1, .monotonic);
        TestingAudit.thread_id.store(std.Thread.getCurrentId(), .release);
    }
    return if (comptime builtin.os.tag == .windows) windowsConvert(seconds) else posixConvert(seconds);
}

fn checkedOffset(seconds: i64) Error!types.UtcOffset {
    if (@mod(seconds, 60) != 0) return error.NonMinuteLocalOffset;
    const minutes = std.math.cast(i16, @divTrunc(seconds, 60)) orelse return error.InvalidOffset;
    return types.UtcOffset.init(minutes);
}

const PosixTm = extern struct {
    second: c_int,
    minute: c_int,
    hour: c_int,
    day: c_int,
    month: c_int,
    year: c_int,
    weekday: c_int,
    yearday: c_int,
    is_dst: c_int,
    offset_seconds: c_long,
    zone: ?[*:0]const u8,
};
extern "c" fn localtime_r(*const std.c.time_t, *PosixTm) ?*PosixTm;

fn posixConvert(seconds: i64) Error!Converted {
    const instant = std.math.cast(std.c.time_t, seconds) orelse return error.LocalTimeConversionFailed;
    var result: PosixTm = undefined;
    _ = localtime_r(&instant, &result) orelse return error.LocalTimeConversionFailed;
    const year = std.math.cast(u16, @as(i64, result.year) + 1900) orelse return error.OutOfRange;
    const month = std.math.cast(u8, @as(i64, result.month) + 1) orelse return error.InvalidDate;
    const date_time: types.civil.DateTime = .{
        .date = try types.civil.Date.init(year, month, std.math.cast(u8, result.day) orelse return error.InvalidDate),
        .hour = std.math.cast(u8, result.hour) orelse return error.InvalidTime,
        .minute = std.math.cast(u8, result.minute) orelse return error.InvalidTime,
        .second = std.math.cast(u8, result.second) orelse return error.InvalidTime,
    };
    try date_time.validate();
    return .{ .date_time = date_time, .offset = try checkedOffset(result.offset_seconds) };
}

const SystemTime = extern struct {
    year: u16 = 0,
    month: u16 = 0,
    weekday: u16 = 0,
    day: u16 = 0,
    hour: u16 = 0,
    minute: u16 = 0,
    second: u16 = 0,
    milliseconds: u16 = 0,
};
const DynamicZone = extern struct {
    bias: i32 = 0,
    standard_name: [32]u16 = @splat(0),
    standard_date: SystemTime = .{},
    standard_bias: i32 = 0,
    daylight_name: [32]u16 = @splat(0),
    daylight_date: SystemTime = .{},
    daylight_bias: i32 = 0,
    key_name: [128]u16 = @splat(0),
    dynamic_daylight_disabled: u8 = 0,
    padding: [3]u8 = @splat(0),
};
extern "kernel32" fn GetDynamicTimeZoneInformation(*DynamicZone) callconv(.winapi) u32;
extern "kernel32" fn SystemTimeToTzSpecificLocalTimeEx(*const DynamicZone, *const SystemTime, *SystemTime) callconv(.winapi) std.os.windows.BOOL;

fn windowsZone() Error!DynamicZone {
    var zone: DynamicZone = .{};
    if (GetDynamicTimeZoneInformation(&zone) == std.math.maxInt(u32)) return error.LocalTimeConversionFailed;
    return zone;
}

fn windowsConvert(seconds: i64) Error!Converted {
    const date = try types.civil.Date.fromEpochDays(@divFloor(seconds, 86400));
    const daytime = @mod(seconds, 86400);
    const input: SystemTime = .{ .year = date.year, .month = date.month, .day = date.day, .hour = @intCast(@divTrunc(daytime, 3600)), .minute = @intCast(@divTrunc(@mod(daytime, 3600), 60)), .second = @intCast(@mod(daytime, 60)) };
    const zone = try windowsZone();
    var output: SystemTime = undefined;
    if (!SystemTimeToTzSpecificLocalTimeEx(&zone, &input, &output).toBool()) return error.LocalTimeConversionFailed;
    const date_time: types.civil.DateTime = .{ .date = try types.civil.Date.init(output.year, @intCast(output.month), @intCast(output.day)), .hour = @intCast(output.hour), .minute = @intCast(output.minute), .second = @intCast(output.second) };
    try date_time.validate();
    const shifted = try date_time.date.epochDays() * 86400 + @as(i64, date_time.hour) * 3600 + @as(i64, date_time.minute) * 60 + date_time.second;
    return .{ .date_time = date_time, .offset = try checkedOffset(shifted - seconds) };
}
