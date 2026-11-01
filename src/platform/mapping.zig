//! File-backed shared mapping with the same journal protocol on each platform.
//! Locks coordinate cooperating owners; active files must never be truncated.
const std = @import("std");
const builtin = @import("builtin");
const backend = switch (builtin.os.tag) {
    .linux => @import("mapping/linux.zig"),
    .windows => @import("mapping/windows.zig"),
    .macos, .ios => @import("mapping/darwin.zig"),
    else => @import("mapping/unsupported.zig"),
};

pub const supported = switch (builtin.os.tag) {
    .linux, .windows, .macos, .ios => builtin.cpu.arch.endian() == .little and @sizeOf(usize) == 8,
    else => false,
};
pub const durable_supported = supported and backend.directory_durable_supported;

pub const Mapping = struct {
    file: std.Io.File,
    directory: std.Io.Dir,
    io: std.Io,
    bytes: []align(4096) u8,
    fresh: bool,

    pub fn open(io: std.Io, path: []const u8, length: usize) !Mapping {
        if (comptime !supported) return error.UnsupportedPlatform;
        if (length == 0 or length > std.math.maxInt(i64)) return error.InvalidSize;
        const directory = try std.Io.Dir.cwd().openDir(io, std.fs.path.dirname(path) orelse ".", .{ .iterate = true });
        errdefer directory.close(io);
        const file = directory.createFile(io, std.fs.path.basename(path), .{ .read = true, .truncate = false, .lock = .exclusive, .lock_nonblocking = true }) catch |err| switch (err) {
            error.WouldBlock => return error.JournalLocked,
            else => return err,
        };
        errdefer file.close(io);
        const stat = try file.stat(io);
        if (stat.kind != .file) return error.NotRegularFile;
        try backend.validateFile(file);
        const fresh = stat.size == 0;
        if (!fresh and stat.size != length) return error.LayoutMismatch;
        if (fresh) try file.setLength(io, length);
        try backend.preallocate(file, length);
        const bytes = try backend.map(file, length);
        // Cover both 4 KiB and 16 KiB system pages; volatile stores prefault
        // writable pages without depending on Linux-only MAP_POPULATE.
        var offset: usize = 0;
        while (offset < bytes.len) : (offset += 4096) {
            const page: *volatile u8 = &bytes[offset];
            page.* = page.*;
        }
        return .{ .file = file, .directory = directory, .io = io, .bytes = bytes, .fresh = fresh };
    }

    /// Publish complete file contents and length. This is used for schema-ready
    /// publication; directory durability is a separate explicit capability.
    pub fn syncFile(self: *Mapping) !void {
        try backend.sync(self.bytes);
        try backend.syncFile(self.io, self.file);
    }

    /// Ready publication always flushes the file. Platforms with a directory
    /// protocol also include the entry; strict durable remains separately gated.
    pub fn publish(self: *Mapping) !void {
        try backend.sync(self.bytes);
        try backend.publishFile(self.io, self.file);
        if (comptime durable_supported) try backend.publishDirectory(self.io, self.directory);
    }

    /// Strict durable boundary also covers creation of the containing entry.
    pub fn sync(self: *Mapping) !void {
        if (comptime !durable_supported) return error.UnsupportedDurability;
        try self.syncFile();
        try backend.syncDirectory(self.io, self.directory);
    }

    pub fn deinit(self: *Mapping) void {
        backend.unmap(self.bytes);
        self.file.close(self.io);
        self.directory.close(self.io);
        self.* = undefined;
    }
};
