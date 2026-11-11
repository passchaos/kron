//! Optional glog-style failure capture for applications.
//!
//! `FailureHandler` installs fatal-signal handlers, writes crash reports with
//! raw stack return addresses, mirrors them to stderr, and can bind to
//! `Logging` so `.fatal` events terminate after delivery. See
//! [failure-handler.md](../../docs/failure-handler.md).
pub const FailureHandler = @import("handler.zig").FailureHandler;
pub const Signal = @import("signal.zig").Signal;
pub const default_signals = @import("signal.zig").default_signals;
pub const max_stack_frames = @import("trace.zig").max_frames;

test {
    _ = @import("handler.zig");
    _ = @import("os.zig");
    _ = @import("report.zig");
    _ = @import("signal.zig");
    _ = @import("trace.zig");
}
