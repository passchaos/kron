const std = @import("std");
const builtin = @import("builtin");

const backend = switch (builtin.os.tag) {
    .linux => @import("../platform/mapping/linux.zig"),
    .windows => @import("../platform/mapping/windows.zig"),
    .macos, .ios => @import("../platform/mapping/darwin.zig"),
    else => @import("../platform/mapping/unsupported.zig"),
};
pub const supported = backend.directory_durable_supported;
pub const TestingHooks = if (builtin.is_test) struct {
    pub threadlocal var strict_file: ?*const fn (std.Io, std.Io.File) anyerror!void = null;
    pub threadlocal var strict_directory: ?*const fn (std.Io, std.Io.Dir) anyerror!void = null;
} else struct {};

pub fn sync(io: std.Io, dir: std.Io.Dir) !void {
    if (!supported) return error.UnsupportedDurability;
    if (builtin.is_test) if (TestingHooks.strict_directory) |hook| return hook(io, dir);
    try backend.syncDirectory(io, dir);
}

pub fn syncFile(io: std.Io, file: std.Io.File) !void {
    if (builtin.is_test) if (TestingHooks.strict_file) |hook| return hook(io, file);
    try backend.syncFile(io, file);
}
