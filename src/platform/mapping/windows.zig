//! Windows file-backed shared mapping backend.
//!
//! View flush and file flush are deliberately separate. Windows does not
//! document a directory-handle operation equivalent to durable POSIX fsync,
//! so directory durability is reported as unsupported rather than guessed.
const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

pub const supported = builtin.os.tag == .windows;
pub const directory_durable_supported = false;
pub const publishFile = syncFile;
pub const publishDirectory = syncDirectory;

const page_readwrite: windows.DWORD = 0x04;
const file_map_write: windows.DWORD = 0x0002;
const file_type_unknown: windows.DWORD = 0;
const file_type_disk: windows.DWORD = 1;
const file_type_remote: windows.DWORD = 0x8000;

const drive_unknown: windows.DWORD = 0;
const drive_no_root_dir: windows.DWORD = 1;
const drive_removable: windows.DWORD = 2;
const drive_fixed: windows.DWORD = 3;
const drive_remote: windows.DWORD = 4;
const drive_cdrom: windows.DWORD = 5;
const drive_ramdisk: windows.DWORD = 6;

const FileAllocationInformation = extern struct {
    AllocationSize: windows.LARGE_INTEGER,
};

const kernel32 = struct {
    extern "kernel32" fn GetFileType(
        hFile: windows.HANDLE,
    ) callconv(.winapi) windows.DWORD;

    extern "kernel32" fn GetFinalPathNameByHandleW(
        hFile: windows.HANDLE,
        lpszFilePath: [*]u16,
        cchFilePath: windows.DWORD,
        dwFlags: windows.DWORD,
    ) callconv(.winapi) windows.DWORD;

    extern "kernel32" fn GetVolumePathNameW(
        lpszFileName: windows.LPCWSTR,
        lpszVolumePathName: [*]u16,
        cchBufferLength: windows.DWORD,
    ) callconv(.winapi) windows.BOOL;

    extern "kernel32" fn GetDriveTypeW(
        lpRootPathName: windows.LPCWSTR,
    ) callconv(.winapi) windows.DWORD;

    extern "kernel32" fn CreateFileMappingW(
        hFile: windows.HANDLE,
        lpFileMappingAttributes: ?*windows.SECURITY_ATTRIBUTES,
        flProtect: windows.DWORD,
        dwMaximumSizeHigh: windows.DWORD,
        dwMaximumSizeLow: windows.DWORD,
        lpName: ?windows.LPCWSTR,
    ) callconv(.winapi) ?windows.HANDLE;

    extern "kernel32" fn MapViewOfFile(
        hFileMappingObject: windows.HANDLE,
        dwDesiredAccess: windows.DWORD,
        dwFileOffsetHigh: windows.DWORD,
        dwFileOffsetLow: windows.DWORD,
        dwNumberOfBytesToMap: windows.SIZE_T,
    ) callconv(.winapi) ?windows.LPVOID;

    extern "kernel32" fn FlushViewOfFile(
        lpBaseAddress: windows.LPCVOID,
        dwNumberOfBytesToFlush: windows.SIZE_T,
    ) callconv(.winapi) windows.BOOL;

    extern "kernel32" fn UnmapViewOfFile(
        lpBaseAddress: windows.LPCVOID,
    ) callconv(.winapi) windows.BOOL;
};

/// Verifies that `file` is a disk-backed file on storage for which this
/// backend can state a durability capability. Known RAM disks and remote
/// shares are rejected. This cannot detect every third-party volatile block
/// device; it is a conservative capability check, not media certification.
pub fn validateFile(file: std.Io.File) !void {
    if (comptime !supported) return error.UnsupportedPlatform;

    const file_type = kernel32.GetFileType(file.handle);
    if (file_type == file_type_unknown) {
        return switch (windows.GetLastError()) {
            .SUCCESS => error.NotFileBacked,
            .ACCESS_DENIED => error.AccessDenied,
            .INVALID_HANDLE => error.InvalidHandle,
            else => error.StorageCapabilityUnknown,
        };
    }
    if (file_type & ~file_type_remote != file_type_disk) return error.NotFileBacked;
    if (file_type & file_type_remote != 0) return error.RemoteDurabilityUnsupported;

    // FILE_NAME_NORMALIZED | VOLUME_NAME_DOS are both zero. The buffers are
    // intentionally bounded at Windows' documented maximum wide path length.
    var final_path: [windows.PATH_MAX_WIDE + 1]u16 = undefined;
    const final_length = kernel32.GetFinalPathNameByHandleW(
        file.handle,
        &final_path,
        final_path.len,
        0,
    );
    if (final_length == 0) return pathCapabilityError(windows.GetLastError());
    if (final_length >= final_path.len) return error.NameTooLong;
    final_path[final_length] = 0;

    var volume_path: [windows.PATH_MAX_WIDE + 1]u16 = undefined;
    if (!kernel32.GetVolumePathNameW(
        @ptrCast(&final_path),
        &volume_path,
        volume_path.len,
    ).toBool()) return pathCapabilityError(windows.GetLastError());

    return switch (kernel32.GetDriveTypeW(@ptrCast(&volume_path))) {
        drive_fixed, drive_removable => {},
        drive_ramdisk => error.VolatileFilesystem,
        drive_remote => error.RemoteDurabilityUnsupported,
        drive_cdrom => error.ReadOnlyStorage,
        drive_unknown, drive_no_root_dir => error.StorageCapabilityUnknown,
        else => error.StorageCapabilityUnknown,
    };
}

/// Reserves filesystem allocation without changing logical file contents.
/// The facade has already established EOF with `setLength`; writing zeroes here
/// would corrupt an existing journal and is intentionally not used.
pub fn preallocate(file: std.Io.File, length: usize) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    if (length == 0 or length > std.math.maxInt(i64)) return error.InvalidSize;

    var allocation: FileAllocationInformation = .{ .AllocationSize = @intCast(length) };
    var io_status: windows.IO_STATUS_BLOCK = undefined;
    return switch (windows.ntdll.NtSetInformationFile(
        file.handle,
        &io_status,
        @ptrCast(&allocation),
        @sizeOf(FileAllocationInformation),
        .Allocation,
    )) {
        .SUCCESS => {},
        .DISK_FULL, .QUOTA_EXCEEDED => error.NoSpaceLeft,
        .ACCESS_DENIED => error.AccessDenied,
        .INVALID_HANDLE => error.InvalidHandle,
        .FILE_TOO_LARGE, .SECTION_TOO_BIG => error.InvalidSize,
        .NOT_SUPPORTED, .INVALID_PARAMETER => error.PreallocationUnsupported,
        else => |status| windows.unexpectedStatus(status),
    };
}

/// Creates a writable file mapping and maps exactly `length` bytes. The
/// mapping-object handle is closed immediately after MapViewOfFile succeeds;
/// the mapped view remains valid until `unmap`.
pub fn map(file: std.Io.File, length: usize) ![]align(4096) u8 {
    if (comptime !supported) return error.UnsupportedPlatform;
    if (length == 0) return error.InvalidSize;

    const length_u64: u64 = length;
    const mapping = kernel32.CreateFileMappingW(
        file.handle,
        null,
        page_readwrite,
        @truncate(length_u64 >> 32),
        @truncate(length_u64),
        null,
    ) orelse return mappingCreateError(windows.GetLastError());
    defer windows.CloseHandle(mapping);

    const view = kernel32.MapViewOfFile(
        mapping,
        file_map_write,
        0,
        0,
        length,
    ) orelse return mappingViewError(windows.GetLastError());
    const address = @intFromPtr(view);
    if (address & 4095 != 0) {
        _ = kernel32.UnmapViewOfFile(view);
        return error.MappingAlignment;
    }
    const pointer: [*]align(4096) u8 = @ptrFromInt(address);
    return pointer[0..length];
}

/// Pushes dirty mapped pages to the file. FlushViewOfFile alone does not
/// guarantee storage-media durability; callers requiring that boundary must
/// subsequently call `syncFile`.
pub fn sync(bytes: []align(4096) u8) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    if (bytes.len == 0) return error.InvalidSize;
    if (!kernel32.FlushViewOfFile(bytes.ptr, bytes.len).toBool()) {
        return switch (windows.GetLastError()) {
            .ACCESS_DENIED => error.AccessDenied,
            .INVALID_HANDLE, .INVALID_ADDRESS => error.InvalidMapping,
            .LOCK_VIOLATION => error.MappingBusy,
            else => error.MappingSyncFailed,
        };
    }
}

/// Releases a view created by `map`. With a valid live view, failure indicates
/// a programming error or unrecoverable process state; the public contract is
/// intentionally non-fallible to match the cross-platform facade.
pub fn unmap(bytes: []align(4096) u8) void {
    if (comptime !supported) return;
    if (bytes.len == 0) return;
    if (!kernel32.UnmapViewOfFile(bytes.ptr).toBool()) {
        const err = windows.GetLastError();
        std.debug.panic("UnmapViewOfFile failed: {t}", .{err});
    }
}

/// Flushes file data and file metadata through std.Io's normal Windows path
/// (`NtFlushBuffersFile`, equivalent to the FlushFileBuffers boundary).
pub fn syncFile(io: std.Io, file: std.Io.File) !void {
    if (comptime !supported) return error.UnsupportedPlatform;
    try file.sync(io);
}

/// Windows has no documented, reliable directory-handle flush contract that
/// is equivalent to POSIX directory fsync. Never report a guessed success.
pub fn syncDirectory(io: std.Io, dir: std.Io.Dir) !void {
    _ = io;
    _ = dir;
    return error.UnsupportedDurability;
}

fn pathCapabilityError(err: windows.Win32Error) anyerror {
    return switch (err) {
        .ACCESS_DENIED => error.AccessDenied,
        .INVALID_HANDLE => error.InvalidHandle,
        .FILENAME_EXCED_RANGE, .BUFFER_OVERFLOW, .INSUFFICIENT_BUFFER => error.NameTooLong,
        else => error.StorageCapabilityUnknown,
    };
}

fn mappingCreateError(err: windows.Win32Error) anyerror {
    return switch (err) {
        .ACCESS_DENIED => error.AccessDenied,
        .INVALID_HANDLE => error.InvalidHandle,
        .DISK_FULL, .HANDLE_DISK_FULL => error.NoSpaceLeft,
        .NOT_ENOUGH_MEMORY, .OUTOFMEMORY, .COMMITMENT_LIMIT => error.SystemResources,
        .FILE_INVALID => error.NotFileBacked,
        else => error.MappingFailed,
    };
}

fn mappingViewError(err: windows.Win32Error) anyerror {
    return switch (err) {
        .ACCESS_DENIED => error.AccessDenied,
        .INVALID_HANDLE => error.InvalidHandle,
        .NOT_ENOUGH_MEMORY, .OUTOFMEMORY, .COMMITMENT_LIMIT => error.SystemResources,
        .MAPPED_ALIGNMENT => error.MappingAlignment,
        else => error.MappingFailed,
    };
}

test "all public backend functions are semantically analyzed" {
    if (comptime !supported) return error.SkipZigTest;
    var execute = false;
    _ = &execute;
    if (execute) {
        const file: std.Io.File = undefined;
        const dir: std.Io.Dir = undefined;
        try validateFile(file);
        try preallocate(file, 4096);
        const bytes = try map(file, 4096);
        try sync(bytes);
        unmap(bytes);
        try syncFile(std.testing.io, file);
        try syncDirectory(std.testing.io, dir);
    }
    try std.testing.expect(!directory_durable_supported);
}
