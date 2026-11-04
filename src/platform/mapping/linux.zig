//! Linux and Android share file-backed MAP_SHARED and fallocate semantics.
const std = @import("std");
const linux = std.os.linux;
pub const directory_durable_supported = true;
// Linux msync(MS_SYNC) calls vfs_fsync_range(file, range, datasync=1).
// fsync calls that same filesystem operation for [0, LLONG_MAX], datasync=0,
// covering dirty MAP_SHARED pages as well as file length/metadata. Cold
// publication needs only that whole-file barrier, followed by directory fsync.
pub const publish_file_flushes_mapping = true;
/// Linux `map` uses MAP_POPULATE, so the generic volatile page walk is
/// redundant and would dirty every page of a fresh mapping.
pub const prefault_needed = false;

fn fileSystemType(file: std.Io.File) !u32 {
    var fs_info: [256]u8 align(8) = undefined;
    while (true) switch (linux.errno(linux.syscall2(.fstatfs, @intCast(file.handle), @intFromPtr(&fs_info)))) {
        .SUCCESS => break,
        .INTR => continue,
        else => return error.FilesystemInfoFailed,
    };
    return std.mem.readInt(u32, fs_info[0..4], .little);
}

pub fn validateFile(file: std.Io.File) !void {
    const fs_type = try fileSystemType(file);
    if (fs_type == 0x01021994 or fs_type == 0x858458f6) return error.VolatileFilesystem;
}

/// A freshly extended file on these Linux filesystems is backed by unwritten
/// extents, whose reads are zero. Unknown filesystems keep the full clear so
/// a reused or unusual backend cannot expose stale slot bytes as valid data.
pub fn freshZeroed(file: std.Io.File) !bool {
    const fs_type = try fileSystemType(file);
    return fs_type == 0xef53 or fs_type == 0x58465342 or fs_type == 0x9123683e or fs_type == 0xf2f52010;
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

/// Schedule writeback without waiting for it. This is sufficient for a
/// non-durable `written` boundary; readers still observe the dirty pages.
pub fn syncAsync(bytes: []align(4096) u8) !void {
    while (true) switch (linux.errno(linux.msync(bytes.ptr, bytes.len, linux.MSF.ASYNC))) {
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
