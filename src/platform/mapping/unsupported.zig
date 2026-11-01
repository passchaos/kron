const std = @import("std");
pub const directory_durable_supported = false;
pub fn validateFile(_: std.Io.File) !void {
    return error.UnsupportedPlatform;
}
pub fn preallocate(_: std.Io.File, _: usize) !void {
    return error.UnsupportedPlatform;
}
pub fn map(_: std.Io.File, _: usize) ![]align(4096) u8 {
    return error.UnsupportedPlatform;
}
pub fn sync(_: []align(4096) u8) !void {
    return error.UnsupportedPlatform;
}
pub fn unmap(_: []align(4096) u8) void {}
pub fn syncFile(_: std.Io, _: std.Io.File) !void {
    return error.UnsupportedPlatform;
}
pub fn syncDirectory(_: std.Io, _: std.Io.Dir) !void {
    return error.UnsupportedDurability;
}

pub const publishFile = syncFile;
pub const publishDirectory = syncDirectory;
