//! Platform-neutral fatal signal identifiers used by the public options and
//! crash-report text. The POSIX values live in `os.zig` so this file stays
//! compilable on targets without signal support.

pub const Signal = enum {
    segv,
    ill,
    fpe,
    abrt,
    bus,
    term,
};

pub const default_signals = [_]Signal{ .segv, .ill, .fpe, .abrt, .bus, .term };

pub fn label(signal: Signal) []const u8 {
    return switch (signal) {
        .segv => "SIGSEGV",
        .ill => "SIGILL",
        .fpe => "SIGFPE",
        .abrt => "SIGABRT",
        .bus => "SIGBUS",
        .term => "SIGTERM",
    };
}

test "signal labels cover the default set" {
    const std = @import("std");
    for (default_signals) |signal| try std.testing.expect(label(signal).len != 0);
    try std.testing.expectEqualStrings("SIGSEGV", label(.segv));
    try std.testing.expectEqualStrings("SIGTERM", label(.term));
}
