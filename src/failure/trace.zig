//! Stack capture shared by fatal reports and signal reports.
//!
//! Capture stores raw return addresses in caller storage. Raw addresses are
//! always written; symbolization appends directly to a bounded report writer
//! because Zig's debug-info reader may allocate and take internal locks.
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

/// Appends a symbolized trace to `writer`. Returns false when the writer is
/// full or debug information is unavailable; the caller marks the report
/// truncated. No separate symbolization buffer is allocated.
pub fn appendSymbolized(writer: *std.Io.Writer, captured: *const std.debug.StackTrace) bool {
    const terminal: std.Io.Terminal = .{ .writer = writer, .mode = .no_color };
    std.debug.writeStackTrace(captured, terminal) catch return false;
    return true;
}
