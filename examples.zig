//! Repository-root entry keeps @src().file relative to the project root.
const std = @import("std");
const selection = @import("kron_example");
const Kind = enum { quick_start, file_logging, structured, threaded, rolling, basic, readable_time, async_memory, std_log, prepared, hot_configuration, configuration_sources, predicates, tsc_clock, local_time, file_stdout_local_time, mmap, source_location, route_policies, failure_handler };
const kind = std.meta.stringToEnum(Kind, selection.name) orelse @compileError("unknown kron example");
const example = switch (kind) {
    .quick_start => @import("examples/quick_start.zig"),
    .file_logging => @import("examples/file_logging.zig"),
    .structured => @import("examples/structured.zig"),
    .threaded => @import("examples/threaded.zig"),
    .rolling => @import("examples/rolling.zig"),
    .basic => @import("examples/basic.zig"),
    .readable_time => @import("examples/readable_time.zig"),
    .async_memory => @import("examples/async_memory.zig"),
    .std_log => @import("examples/std_log.zig"),
    .prepared => @import("examples/prepared.zig"),
    .hot_configuration => @import("examples/hot_configuration.zig"),
    .configuration_sources => @import("examples/configuration_sources.zig"),
    .predicates => @import("examples/predicates.zig"),
    .tsc_clock => @import("examples/tsc_clock.zig"),
    .local_time => @import("examples/local_time.zig"),
    .file_stdout_local_time => @import("examples/file_stdout_local_time.zig"),
    .mmap => @import("examples/mmap.zig"),
    .source_location => @import("examples/source_location.zig"),
    .route_policies => @import("examples/route_policies.zig"),
    .failure_handler => @import("examples/failure_handler.zig"),
};

pub const std_options: std.Options = if (@hasDecl(example, "std_options")) example.std_options else .{};
pub const main = example.main;
