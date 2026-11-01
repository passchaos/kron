//! Native Darwin MAP_SHARED file storage. Requires linkage with libSystem.
//! ABI declarations are taken from Zig 0.16's bundled any-darwin-any headers:
//! sys/mount.h (__DARWIN_STRUCT_STATFS64) and sys/fcntl.h (fstore_t).
//! Cross compilation does not qualify APFS/iOS power-failure durability.
const std = @import("std");
const builtin = @import("builtin");

const supported = builtin.os.tag == .macos or builtin.os.tag == .ios;
/// The platform exposes the operations used below. A concrete directory or
/// storage device may reject strict synchronization; such errors propagate.
pub const directory_durable_supported = supported;

const StatFs = extern struct {
    f_bsize: u32,
    f_iosize: i32,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_owner: u32,
    f_type: u32,
    f_flags: u32,
    f_fssubtype: u32,
    f_fstypename: [16]u8,
    f_mntonname: [1024]u8,
    f_mntfromname: [1024]u8,
    f_flags_ext: u32,
    f_reserved: [7]u32,
};

const FStore = extern struct {
    fst_flags: c_uint,
    fst_posmode: c_int,
    fst_offset: i64,
    fst_length: i64,
    fst_bytesalloc: i64,
};

const allocate_contiguous: c_uint = 0x00000002;
const allocate_all: c_uint = 0x00000004;
const physical_eof_position: c_int = 3;

extern "c" fn fstatfs(fd: c_int, out: *StatFs) c_int;
extern "c" fn @"fstatfs$INODE64"(fd: c_int, out: *StatFs) c_int;

comptime {
    std.debug.assert(@sizeOf(StatFs) == 2168);
    std.debug.assert(@offsetOf(StatFs, "f_fstypename") == 72);
    std.debug.assert(@offsetOf(StatFs, "f_mntfromname") == 1112);
    std.debug.assert(@sizeOf(FStore) == 32);
    std.debug.assert(@offsetOf(FStore, "fst_offset") == 8);
}

pub fn validateFile(file: std.Io.File) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    var info: StatFs = undefined;
    while (true) {
        const rc = if (builtin.cpu.arch == .x86_64) @"fstatfs$INODE64"(file.handle, &info) else fstatfs(file.handle, &info);
        switch (std.c.errno(rc)) {
            .SUCCESS => break,
            .INTR => continue,
            .BADF => return error.InvalidFileDescriptor,
            .IO => return error.InputOutput,
            else => return error.FilesystemInfoFailed,
        }
    }
    const name = std.mem.sliceTo(&info.f_fstypename, 0);
    // Known memory/pseudo filesystems cannot provide a durable disk journal.
    // A RAM-backed disk formatted as APFS/HFS is not identifiable by this ABI;
    // callers must choose an appropriate persistent storage device.
    inline for (.{ "tmpfs", "mfs", "ramfs", "devfs", "fdesc", "volfs" }) |volatile_name| {
        if (std.mem.eql(u8, name, volatile_name)) return error.VolatileFilesystem;
    }
}

/// F_PREALLOCATE reserves physical storage independently of logical length,
/// which the facade has already set. Darwin PEOFPOS adds the requested bytes to
/// physical EOF, so request only the deficit reported by fstat's 512-byte block
/// count. Reopening a sufficiently allocated journal performs no allocation.
/// The journal owner must exclude concurrent truncate/punch-hole mutations.
pub fn preallocate(file: std.Io.File, length: usize) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    if (length == 0 or length > std.math.maxInt(i64)) return error.InvalidSize;
    const missing = try allocationDeficit(file, length);
    if (missing == 0) return;
    var store: FStore = .{
        .fst_flags = allocate_contiguous | allocate_all,
        .fst_posmode = physical_eof_position,
        .fst_offset = 0,
        .fst_length = @intCast(missing),
        .fst_bytesalloc = 0,
    };
    while (true) {
        switch (std.c.errno(std.c.fcntl(file.handle, std.c.F.PREALLOCATE, &store))) {
            .SUCCESS => {
                if (try allocationDeficit(file, length) != 0) return error.PreallocationIncomplete;
                return;
            },
            .INTR => continue,
            .NOSPC => break,
            .DQUOT => return error.DiskQuota,
            .INVAL, .OPNOTSUPP, .NOSYS => return error.PreallocationUnsupported,
            .BADF => return error.InvalidFileDescriptor,
            .IO => return error.InputOutput,
            .ACCES, .PERM => return error.AccessDenied,
            else => return error.PreallocationFailed,
        }
    }
    // Some filesystem implementations can leave partial progress even when
    // an allocation request fails. Re-read actual blocks before fallback so
    // those bytes cannot be reserved again beyond the fixed journal budget.
    const remaining = try allocationDeficit(file, length);
    if (remaining == 0) return;
    store.fst_flags = allocate_all;
    store.fst_length = @intCast(remaining);
    store.fst_bytesalloc = 0;
    while (true) {
        switch (std.c.errno(std.c.fcntl(file.handle, std.c.F.PREALLOCATE, &store))) {
            .SUCCESS => {
                if (try allocationDeficit(file, length) != 0) return error.PreallocationIncomplete;
                return;
            },
            .INTR => continue,
            .NOSPC => return error.NoSpaceLeft,
            .DQUOT => return error.DiskQuota,
            .INVAL, .OPNOTSUPP, .NOSYS => return error.PreallocationUnsupported,
            .BADF => return error.InvalidFileDescriptor,
            .IO => return error.InputOutput,
            .ACCES, .PERM => return error.AccessDenied,
            else => return error.PreallocationFailed,
        }
    }
}

fn allocationDeficit(file: std.Io.File, length: usize) !usize {
    var stat: std.c.Stat = undefined;
    while (true) {
        switch (std.c.errno(std.c.fstat(file.handle, &stat))) {
            .SUCCESS => break,
            .INTR => continue,
            .BADF => return error.InvalidFileDescriptor,
            .IO => return error.InputOutput,
            else => return error.FileInfoFailed,
        }
    }
    if (!std.c.S.ISREG(stat.mode)) return error.NotRegularFile;
    if (stat.size < 0 or stat.blocks < 0) return error.InvalidFileSize;
    if (@as(u64, @intCast(stat.size)) < length) return error.InvalidSize;
    const allocated = @as(u128, @intCast(stat.blocks)) * 512;
    return if (allocated >= length) 0 else @intCast(length - allocated);
}

pub fn map(file: std.Io.File, length: usize) ![]align(4096) u8 {
    if (comptime !supported) return error.UnsupportedPlatform;
    if (length == 0 or length > std.math.maxInt(i64)) return error.InvalidSize;
    // No ANON/PRIVATE flags. Native pages can be 16 KiB; their start addresses
    // also satisfy the facade's weaker 4 KiB alignment contract.
    const address = std.c.mmap(null, length, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, file.handle, 0);
    if (address == std.c.MAP_FAILED) {
        const err: std.c.E = @enumFromInt(std.c._errno().*);
        return switch (err) {
            .ACCES, .PERM => error.AccessDenied,
            .NOMEM => error.OutOfMemory,
            .BADF => error.InvalidFileDescriptor,
            .NODEV, .OPNOTSUPP => error.MappingUnsupported,
            .INVAL => error.InvalidMapping,
            else => error.MappingFailed,
        };
    }
    return @as([*]align(4096) u8, @ptrCast(@alignCast(address)))[0..length];
}

pub fn sync(bytes: []align(4096) u8) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    if (bytes.len == 0) return error.InvalidSize;
    // The slice must be the original native-page-aligned mapping, not an
    // arbitrary 4 KiB-aligned subrange of a mapping on a 16 KiB-page system.
    const ptr: *align(std.heap.page_size_min) anyopaque = @ptrCast(@alignCast(bytes.ptr));
    while (true) {
        switch (std.c.errno(std.c.msync(ptr, bytes.len, std.c.MSF.SYNC))) {
            .SUCCESS => return,
            .INTR => continue,
            .INVAL => return error.InvalidMapping,
            .NOMEM => return error.UnmappedMemory,
            .IO => return error.InputOutput,
            .ACCES, .PERM => return error.AccessDenied,
            else => return error.MappingSyncFailed,
        }
    }
}

pub fn unmap(bytes: []align(4096) u8) void {
    if (comptime !supported) return;
    const ptr: *align(std.heap.page_size_min) const anyopaque = @ptrCast(@alignCast(bytes.ptr));
    // A failed unmap indicates an invalid ownership/range contract. It must not
    // be represented as a successful resource release by a void destructor.
    if (std.c.munmap(ptr, bytes.len) != 0) @panic("Darwin journal munmap failed");
}

fn fullSync(fd: std.c.fd_t) !void {
    while (true) {
        switch (std.c.errno(std.c.fcntl(fd, std.c.F.FULLFSYNC))) {
            .SUCCESS => return,
            .INTR => continue,
            .INVAL, .OPNOTSUPP, .NOTTY, .NOSYS => return error.UnsupportedDurability,
            .BADF => return error.InvalidFileDescriptor,
            .IO => return error.InputOutput,
            .NOSPC => return error.NoSpaceLeft,
            .DQUOT => return error.DiskQuota,
            .ACCES, .PERM => return error.AccessDenied,
            else => return error.FullSyncFailed,
        }
    }
}

fn fsyncLoop(fd: std.c.fd_t) !void {
    while (true) {
        switch (std.c.errno(std.c.fsync(fd))) {
            .SUCCESS => return,
            .INTR => continue,
            .INVAL, .OPNOTSUPP, .NOTTY, .NOSYS => return error.FileSyncUnsupported,
            .BADF => return error.InvalidFileDescriptor,
            .IO => return error.InputOutput,
            .NOSPC => return error.NoSpaceLeft,
            .DQUOT => return error.DiskQuota,
            .ACCES, .PERM => return error.AccessDenied,
            else => return error.FileSyncFailed,
        }
    }
}

pub fn syncFile(io: std.Io, file: std.Io.File) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    publishFile(io, file) catch |err| switch (err) {
        error.FileSyncUnsupported => return error.UnsupportedDurability,
        else => return err,
    };
    // fsync alone can leave the device's volatile write cache populated.
    // Both macOS and iOS headers expose FULLFSYNC; errors cannot be downgraded.
    try fullSync(file.handle);
}

pub fn syncDirectory(io: std.Io, dir: std.Io.Dir) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    publishDirectory(io, dir) catch |err| switch (err) {
        error.FileSyncUnsupported => return error.UnsupportedDurability,
        else => return err,
    };
    // Strictly ask for a media flush after directory metadata synchronization.
    // Some directory/filesystem combinations may reject this request; the
    // facade must report UnsupportedDurability rather than claim durable success.
    try fullSync(dir.handle);
}

/// Publish the initial file/header/schema state through the filesystem. This
/// does not request device-cache flushing and is not the strict durable API.
/// I/O failures are still propagated; initialization must not ignore them.
pub fn publishFile(io: std.Io, file: std.Io.File) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    _ = io;
    try fsyncLoop(file.handle);
}

/// Publish directory entries without requiring F_FULLFSYNC support on this
/// directory. A failed ordinary fsync remains an explicit initialization error.
pub fn publishDirectory(io: std.Io, dir: std.Io.Dir) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    _ = io;
    // std.Io's POSIX implementation classifies EINVAL as a programmer bug;
    // native fsync preserves it as an explicit unsupported storage capability.
    try fsyncLoop(dir.handle);
}
