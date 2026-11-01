//! Stable owned sink storage for the application logging facade.
const std = @import("std");
const FileSink = @import("../sink/file.zig").FileSink;
const RollingFileSink = @import("../sink/rolling_file.zig").RollingFileSink;
const WriterSink = @import("../sink/writer.zig").WriterSink;
const Sink = @import("../sink/interface.zig").Sink;

pub const Target = union(enum) {
    stderr,
    stdout,
    file: FileSink.Options,
    rolling_file: RollingFileSink.Options,
    /// Borrowed writer and resources must outlive Logging.destroy().
    writer: *std.Io.Writer,
};

/// Two separately owned writers must not maintain independent offsets for
/// one file. Resolved identities are checked again after opening for aliases.
pub fn sameFileTarget(left: Target, right: Target) bool {
    const Identity = struct { path: []const u8, dir: ?std.Io.Dir };
    const a: Identity = switch (left) {
        .file => |file| .{ .path = file.path, .dir = file.dir },
        .rolling_file => |file| .{ .path = file.path, .dir = file.dir },
        else => return false,
    };
    const b: Identity = switch (right) {
        .file => |file| .{ .path = file.path, .dir = file.dir },
        .rolling_file => |file| .{ .path = file.path, .dir = file.dir },
        else => return false,
    };
    return std.meta.eql(a.dir orelse std.Io.Dir.cwd(), b.dir orelse std.Io.Dir.cwd()) and std.mem.eql(u8, a.path, b.path);
}

pub const Resource = struct {
    destination: union(enum) { file: *FileSink, rolling_file: *RollingFileSink, writer: WriterSink },
    stream: std.Io.File.Writer = undefined,
    stream_buffer: [4096]u8 = undefined,

    /// Resource lives in a stable owner allocation before its writer is bound.
    pub fn init(self: *Resource, allocator: std.mem.Allocator, io: std.Io, target: Target) !void {
        switch (target) {
            .file => |file| self.destination = .{ .file = try FileSink.create(allocator, io, file) },
            .rolling_file => |file| self.destination = .{ .rolling_file = try RollingFileSink.create(allocator, io, file) },
            .writer => |writer| self.destination = .{ .writer = WriterSink.init(writer) },
            .stderr, .stdout => {
                const file = if (target == .stderr) std.Io.File.stderr() else std.Io.File.stdout();
                self.stream = file.writerStreaming(io, &self.stream_buffer);
                self.destination = .{ .writer = WriterSink.init(&self.stream.interface) };
            },
        }
    }

    pub fn sink(self: *Resource) Sink {
        return switch (self.destination) {
            .file => |file| file.sink(),
            .rolling_file => |file| file.sink(),
            .writer => |*writer| writer.sink(),
        };
    }

    pub fn deinit(self: *Resource) void {
        switch (self.destination) {
            .file => |file| file.deinit(),
            .rolling_file => |file| file.deinit(),
            .writer => {},
        }
    }
};
