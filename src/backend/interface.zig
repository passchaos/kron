const std = @import("std");
const Portable = @import("portable.zig").Portable;
pub const LinuxUring = @import("linux_uring.zig").LinuxUring;

pub const Kind = enum { auto, portable, linux_uring };

pub const Backend = union(enum) {
    portable: Portable,
    linux_uring: LinuxUring,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, file: std.Io.File, start_offset: u64, batch_bytes: usize, depth: u16, requested_kind: Kind) !Backend {
        return switch (requested_kind) {
            .portable => .{ .portable = Portable.init(io, file, start_offset) },
            .linux_uring => .{ .linux_uring = try LinuxUring.init(allocator, file, start_offset, batch_bytes, depth) },
            .auto => .{ .linux_uring = LinuxUring.init(allocator, file, start_offset, batch_bytes, depth) catch |err| switch (err) {
                error.Unsupported => return .{ .portable = Portable.init(io, file, start_offset) },
                else => return err,
            } },
        };
    }

    pub fn kind(self: *const Backend) Kind {
        return switch (self.*) {
            .portable => .portable,
            .linux_uring => .linux_uring,
        };
    }

    pub fn writeBatch(self: *Backend, bytes: []const u8) !void {
        switch (self.*) {
            inline else => |*backend| try backend.writeBatch(bytes),
        }
    }

    pub fn flush(self: *Backend) !void {
        switch (self.*) {
            inline else => |*backend| try backend.flush(),
        }
    }

    pub fn sync(self: *Backend) !void {
        switch (self.*) {
            inline else => |*backend| try backend.sync(),
        }
    }

    pub fn offset(self: *const Backend) u64 {
        return switch (self.*) {
            .portable => |backend| backend.offset,
            .linux_uring => |*backend| backend.offset(),
        };
    }

    pub fn writtenOffset(self: *const Backend) u64 {
        return switch (self.*) {
            .portable => |backend| backend.offset,
            .linux_uring => |*backend| backend.writtenOffset(),
        };
    }

    pub fn shutdown(self: *Backend) !void {
        switch (self.*) {
            .portable => {},
            .linux_uring => |*backend| try backend.shutdown(),
        }
    }

    pub fn deinit(self: *Backend) void {
        switch (self.*) {
            inline else => |*backend| backend.deinit(),
        }
    }
};
