//! A typed frontend owner binds the producer timestamp provider at comptime.
//! It shares admission, journal ownership, configuration and delivery with the
//! same runtime; the backend does not become a second logging implementation.
const std = @import("std");
const logger = @import("logger.zig");

pub fn StaticClockOwner(comptime Base: type, comptime ClockProvider: type) type {
    return struct {
        const Self = @This();
        pub const value_owner = true;
        base: logger.Logger(Base, .trace).OwnerStorage,
        scope: []const u8 = "default",

        pub fn enabled(self: Self, level: logger.Level, scope: []const u8) bool {
            return self.base.enabled(level, scope);
        }

        pub fn begin(self: Self, level: logger.Level, scope: []const u8) logger.BeginResult {
            return self.base.begin(level, scope);
        }

        pub fn end(self: Self) void {
            self.base.end();
        }

        pub fn submit(self: Self, admission: logger.Admission, event: logger.Event) anyerror!logger.EmitResult {
            return self.base.submit(admission, event);
        }

        pub inline fn nowNs(self: Self) i64 {
            const io = if (comptime @hasField(Base, "io")) self.base.io else self.base.registry.io;
            return ClockProvider.realNow(io);
        }

        pub fn captureFailed(self: Self, failure: anyerror) void {
            self.base.captureFailed(failure);
        }

        pub fn reportError(self: Self, failure: anyerror) void {
            self.base.reportError(failure);
        }

        pub fn detach(self: Self) anyerror!void {
            if (comptime !@hasDecl(Base, "detach")) @compileError("only attached thread loggers can detach");
            return self.base.detach();
        }

        pub fn copyScope(self: Self, destination: []u8) anyerror![]const u8 {
            if (comptime @hasDecl(Base, "copyScope")) return self.base.copyScope(destination);
            if (destination.len < self.scope.len) return error.BufferTooSmall;
            @memcpy(destination[0..self.scope.len], self.scope);
            return destination[0..self.scope.len];
        }
    };
}

/// A per-logger instance clock, useful for one qualified TSC instance per
/// producer. The caller keeps its callback context alive until all derived
/// logger users stop. This does not replace runtime clocks used for deadlines.
pub fn InstanceClockOwner(comptime Base: type) type {
    return struct {
        const Self = @This();
        pub const value_owner = true;
        base: logger.Logger(Base, .trace).OwnerStorage,
        clock: @import("../platform/clock.zig").Clock,
        scope: []const u8 = "default",

        pub fn enabled(self: Self, level: logger.Level, scope: []const u8) bool {
            return self.base.enabled(level, scope);
        }

        pub fn begin(self: Self, level: logger.Level, scope: []const u8) logger.BeginResult {
            return self.base.begin(level, scope);
        }

        pub fn end(self: Self) void {
            self.base.end();
        }

        pub fn submit(self: Self, admission: logger.Admission, event: logger.Event) anyerror!logger.EmitResult {
            return self.base.submit(admission, event);
        }

        pub fn nowNs(self: Self) i64 {
            const io = if (comptime @hasField(Base, "io")) self.base.io else self.base.registry.io;
            return self.clock.realNow(io);
        }

        pub fn captureFailed(self: Self, err: anyerror) void {
            self.base.captureFailed(err);
        }

        pub fn reportError(self: Self, err: anyerror) void {
            self.base.reportError(err);
        }

        pub fn detach(self: Self) anyerror!void {
            if (comptime !@hasDecl(Base, "detach")) @compileError("only attached loggers detach");
            return self.base.detach();
        }

        pub fn copyScope(self: Self, destination: []u8) anyerror![]const u8 {
            if (comptime @hasDecl(Base, "copyScope")) return self.base.copyScope(destination);
            if (destination.len < self.scope.len) return error.BufferTooSmall;
            @memcpy(destination[0..self.scope.len], self.scope);
            return destination[0..self.scope.len];
        }
    };
}
