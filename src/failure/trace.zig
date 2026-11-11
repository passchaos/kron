//! Stack capture shared by fatal reports and signal reports.
//!
//! Capture stores raw return addresses in caller storage. Raw addresses are
//! always written; symbolization is a separate best-effort step because Zig's
//! debug-info reader may allocate and take internal locks.
const std = @import("std");

pub const max_frames = 128;

pub fn capture(buffer: []usize, options: std.debug.StackUnwindOptions) std.debug.StackTrace {
    return std.debug.captureCurrentStackTrace(options, buffer);
}

/// Captures from the interrupted context provided by a POSIX signal handler.
/// Targets without a native context fall back to the current stack.
pub fn captureFromSignal(context: ?*anyopaque, buffer: []usize) std.debug.StackTrace {
    if (comptime std.debug.cpu_context.Native == noreturn) {
        return capture(buffer, .{});
    } else {
        if (std.debug.cpu_context.fromPosixSignalContext(context)) |native| {
            var value = native;
            return capture(buffer, .{ .context = &value });
        }
        return capture(buffer, .{});
    }
}

/// Writes a symbolized trace into `buffer` using a fixed writer. Returns the
/// written bytes; truncation keeps the prefix instead of failing the report.
pub fn symbolize(buffer: []u8, trace: *const std.debug.StackTrace) []const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    const terminal: std.Io.Terminal = .{ .writer = &writer, .mode = .no_color };
    std.debug.writeStackTrace(trace, terminal) catch {};
    return writer.buffered();
}
