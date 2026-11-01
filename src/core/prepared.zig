//! A prepared binding borrows immutable schema bytes from its owning runtime.
//! Registration/persistence is a cold operation; emission uses the same
//! filtering, capture and lifecycle protocol as ordinary logger handles.
const std = @import("std");
const logger = @import("logger.zig");
const journal = @import("../journal/journal.zig");
const schema = @import("../journal/schema.zig");

pub const Binding = struct {
    owner: *anyopaque,
    journal: *journal.Journal,
    reference: schema.Ref,
    definition: schema.Definition,
};

pub fn Owner(comptime R: type) type {
    return struct {
        const Self = @This();
        pub const value_owner = true;
        runtime: *R,
        binding: Binding,

        pub fn enabled(self: Self, level: logger.Level, scope: []const u8) bool {
            return self.runtime.enabled(level, scope);
        }

        pub fn begin(self: Self, level: logger.Level, scope: []const u8) logger.BeginResult {
            return self.runtime.begin(level, scope);
        }

        pub fn end(self: Self) void {
            self.runtime.end();
        }

        pub fn nowNs(self: Self) i64 {
            return self.runtime.nowNs();
        }

        pub fn submit(self: Self, admission: logger.Admission, event: logger.Event) anyerror!logger.EmitResult {
            return self.runtime.submitWithSchema(admission, event, self.binding);
        }

        pub fn captureFailed(self: Self, err: anyerror) void {
            self.runtime.captureFailed(err);
        }

        pub fn reportError(self: Self, err: anyerror) void {
            self.runtime.reportError(err);
        }
    };
}

pub fn ThreadOwner(comptime Base: type) type {
    return struct {
        const Self = @This();
        pub const value_owner = true;
        base: Base,
        binding: Binding,

        pub fn enabled(self: Self, level: logger.Level, scope: []const u8) bool {
            return self.base.enabled(level, scope);
        }

        pub fn begin(self: Self, level: logger.Level, scope: []const u8) logger.BeginResult {
            return self.base.begin(level, scope);
        }

        pub fn end(self: Self) void {
            self.base.end();
        }

        pub fn nowNs(self: Self) i64 {
            return self.base.nowNs();
        }

        pub fn submit(self: Self, admission: logger.Admission, event: logger.Event) anyerror!logger.EmitResult {
            return self.base.submitWithSchema(admission, event, self.binding);
        }

        pub fn captureFailed(self: Self, err: anyerror) void {
            self.base.captureFailed(err);
        }

        pub fn reportError(self: Self, err: anyerror) void {
            self.base.reportError(err);
        }

        pub fn copyScope(self: Self, destination: []u8) anyerror![]const u8 {
            return self.base.copyScope(destination);
        }

        pub fn detach(self: Self) anyerror!void {
            return self.base.detach();
        }
    };
}
