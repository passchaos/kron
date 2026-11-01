//! Linux and Android share file-backed MAP_SHARED and fallocate semantics.
const std = @import("std");
const linux = std.os.linux;
pub const directory_durable_supported = true;

pub fn validateFile(file: std.Io.File) !void {
    var fs_info: [256]u8 align(8) = undefined;
    while (true) switch (linux.errno(linux.syscall2(.fstatfs, @intCast(file.handle), @intFromPtr(&fs_info)))) {
        .SUCCESS => break,
        .INTR => continue,
        else => return error.FilesystemInfoFailed,
    };
    const fs_type = std.mem.readInt(u32, fs_info[0..4], .little);
    if (fs_type == 0x01021994 or fs_type == 0x858458f6) return error.VolatileFilesystem;
}

pub fn preallocate(file: std.Io.File, length: usize) !void {
    while (true) switch (linux.errno(linux.fallocate(file.handle, 0, 0, @intCast(length)))) {
        .SUCCESS => return,
        .INTR => continue,
        .NOSPC => return error.NoSpaceLeft,
        .DQUOT => return error.DiskQuota,
        .OPNOTSUPP, .NOSYS => return error.PreallocationUnsupported,
        else => return error.PreallocationFailed,
    };
}

pub fn map(file: std.Io.File, length: usize) ![]align(4096) u8 {
    const address = linux.mmap(null, length, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED, .POPULATE = true }, file.handle, 0);
    if (linux.errno(address) != .SUCCESS) return error.MappingFailed;
    return @as([*]align(4096) u8, @ptrFromInt(address))[0..length];
}

pub fn sync(bytes: []align(4096) u8) !void {
    while (true) switch (linux.errno(linux.msync(bytes.ptr, bytes.len, linux.MSF.SYNC))) {
        .SUCCESS => return,
        .INTR => continue,
        else => return error.MappingSyncFailed,
    };
}

pub fn unmap(bytes: []align(4096) u8) void {
    _ = linux.munmap(bytes.ptr, bytes.len);
}

pub fn syncFile(io: std.Io, file: std.Io.File) !void {
    try file.sync(io);
}

pub fn syncDirectory(io: std.Io, dir: std.Io.Dir) !void {
    const file: std.Io.File = .{ .handle = dir.handle, .flags = .{ .nonblocking = false } };
    try file.sync(io);
}

pub const publishFile = syncFile;
pub const publishDirectory = syncDirectory;
