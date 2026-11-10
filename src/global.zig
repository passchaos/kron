//! Optional process-wide logging owner for applications and libraries that
//! cannot thread a logger through every API.
//!
//! The application installs one `Logging` owner with `setLogging` before
//! starting workers and calls `clearLogging` after all users stop. Callers
//! then derive a zero-allocation frontend with their own scope:
//!
//!     kron.global.info("mylib", "connected", .{ .host = host });
//!
//! The scope is chosen at the call site, so independent libraries do not
//! compete for one fixed process-wide scope. This is a convenience facade,
//! not a replacement for the explicit `Logging`/`Runtime` lifecycle. The slot
//! is atomic, so lookups do not race with install/clear; the caller must still
//! keep the installed `Logging` alive until every user has stopped and must
//! call `clearLogging` before destroying it.

const std = @import("std");
const Logging = @import("logging/root.zig").Logging;
const Level = @import("core/level.zig").Level;

pub const Logger = Logging.Logger;

var global_logging: std.atomic.Value(?*Logging) = .init(null);

/// Install the process-wide owner. Call before starting workers.
pub fn setLogging(logging: ?*Logging) void {
    global_logging.store(logging, .release);
}

/// Remove the global owner before destroying the underlying `Logging`.
pub fn clearLogging() void {
    global_logging.store(null, .release);
}

/// Returns the installed owner, or null when no owner is configured.
pub fn getLogging() ?*Logging {
    return global_logging.load(.acquire);
}

/// Derive a zero-allocation frontend for `scope`, or null when unset.
/// The scope string must outlive the returned logger; use a literal or a
/// module-level constant.
pub fn scoped(scope: []const u8) ?Logger {
    const logging = getLogging() orelse return null;
    return logging.scoped(scope);
}

/// Check whether `level` would be admitted for `scope` without capturing
/// fields. Returns false when no owner is installed.
pub fn enabled(level: Level, scope: []const u8) bool {
    const logger = scoped(scope) orelse return false;
    return logger.enabled(level);
}

pub fn log(level: Level, scope: []const u8, message: []const u8, fields: anytype) void {
    if (scoped(scope)) |logger| logger.log(level, message, fields);
}

pub fn logf(level: Level, scope: []const u8, comptime fmt: []const u8, args: anytype, fields: anytype) void {
    if (scoped(scope)) |logger| logger.logf(level, fmt, args, fields);
}

/// Explicit source location for plain messages.
pub fn logAt(source: std.builtin.SourceLocation, level: Level, scope: []const u8, message: []const u8, fields: anytype) void {
    if (scoped(scope)) |logger| logger.logAt(source, level, message, fields);
}

/// Explicit source location for formatted messages.
pub fn logfAt(source: std.builtin.SourceLocation, level: Level, scope: []const u8, comptime fmt: []const u8, args: anytype, fields: anytype) void {
    const logger = scoped(scope) orelse return;
    switch (level) {
        .trace => logger.traceAt(source, fmt, args, fields),
        .debug => logger.debugAt(source, fmt, args, fields),
        .info => logger.infoAt(source, fmt, args, fields),
        .warn => logger.warnAt(source, fmt, args, fields),
        .err => logger.errAt(source, fmt, args, fields),
        .fatal => logger.fatalAt(source, fmt, args, fields),
        .off => {},
    }
}

pub fn err(scope: []const u8, message: []const u8, fields: anytype) void {
    log(.err, scope, message, fields);
}

pub fn errAt(source: std.builtin.SourceLocation, scope: []const u8, message: []const u8, fields: anytype) void {
    logAt(source, .err, scope, message, fields);
}

pub fn warn(scope: []const u8, message: []const u8, fields: anytype) void {
    log(.warn, scope, message, fields);
}

pub fn warnAt(source: std.builtin.SourceLocation, scope: []const u8, message: []const u8, fields: anytype) void {
    logAt(source, .warn, scope, message, fields);
}

pub fn info(scope: []const u8, message: []const u8, fields: anytype) void {
    log(.info, scope, message, fields);
}

pub fn infoAt(source: std.builtin.SourceLocation, scope: []const u8, message: []const u8, fields: anytype) void {
    logAt(source, .info, scope, message, fields);
}

pub fn debug(scope: []const u8, message: []const u8, fields: anytype) void {
    log(.debug, scope, message, fields);
}

pub fn debugAt(source: std.builtin.SourceLocation, scope: []const u8, message: []const u8, fields: anytype) void {
    logAt(source, .debug, scope, message, fields);
}

pub fn trace(scope: []const u8, message: []const u8, fields: anytype) void {
    log(.trace, scope, message, fields);
}

pub fn traceAt(source: std.builtin.SourceLocation, scope: []const u8, message: []const u8, fields: anytype) void {
    logAt(source, .trace, scope, message, fields);
}

test "global owner is optional and no-op when unset" {
    clearLogging();
    try std.testing.expect(getLogging() == null);
    try std.testing.expect(scoped("ignored") == null);
    try std.testing.expect(!enabled(.info, "ignored"));
    info("ignored", "dropped", .{});
    err("ignored", "dropped", .{});
}

test "global owner derives per-call scopes without allocation" {
    clearLogging();
    var bytes: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    const logging = try Logging.create(std.testing.allocator, std.testing.io, .{
        .outputs = &.{.{ .target = .{ .writer = &writer }, .format = .json }},
    });
    var live = true;
    defer if (live) logging.destroy();
    setLogging(logging);
    defer clearLogging();

    try std.testing.expect(getLogging().? == logging);
    try std.testing.expect(enabled(.info, "mylib.http"));
    try std.testing.expect(!enabled(.debug, "mylib.http"));
    info("mylib.http", "request done", .{ .status = @as(u16, 200) });
    warn("mylib.db", "pool exhausted", .{ .size = @as(u8, 10) });
    try logging.flush();
    try logging.shutdown();
    logging.destroy();
    live = false;
    clearLogging();

    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"scope\":\"mylib.http\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"scope\":\"mylib.db\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"status\":200") != null);
}

test "global At variants forward explicit source locations" {
    clearLogging();
    var bytes: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    const logging = try Logging.create(std.testing.allocator, std.testing.io, .{
        .outputs = &.{.{ .target = .{ .writer = &writer }, .format = .json }},
    });
    var live = true;
    defer if (live) logging.destroy();
    setLogging(logging);
    defer clearLogging();

    infoAt(@src(), "mylib", "plain", .{ .kind = "plain" });
    logfAt(@src(), .info, "mylib", "formatted {d}", .{@as(u32, 7)}, .{ .kind = "formatted" });
    logAt(@src(), .warn, "mylib", "leveled", .{ .kind = "leveled" });
    try logging.flush();
    try logging.shutdown();
    logging.destroy();
    live = false;
    clearLogging();

    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"message\":\"plain\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "formatted 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"message\":\"leveled\"") != null);
}
