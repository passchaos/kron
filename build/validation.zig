//! Compile-time gates for production targets and runnable examples.
const std = @import("std");

pub fn addPlatforms(b: *std.Build) void {
    const platform_step = b.step("check-platforms", "Compile real public file/runtime/journal paths for five OS families");
    const platform_queries = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .android },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .android },
        .{ .cpu_arch = .aarch64, .os_tag = .ios },
        .{ .cpu_arch = .aarch64, .os_tag = .ios, .abi = .simulator },
    };
    for (platform_queries) |query| {
        const platform_target = b.resolveTargetQuery(query);
        const platform_module = b.createModule(.{ .root_source_file = b.path("src/platform_check.zig"), .target = platform_target, .optimize = .ReleaseSafe, .link_libc = switch (query.os_tag.?) {
            .macos, .ios => true,
            .linux => true,
            else => null,
        } });
        const object = b.addObject(.{ .name = b.fmt("kron-{s}-{s}-{s}", .{ @tagName(query.cpu_arch.?), @tagName(query.os_tag.?), @tagName(query.abi orelse .none) }), .root_module = platform_module });
        _ = object.getEmittedBin();
        platform_step.dependOn(&object.step);
    }
}

const Example = struct {
    name: []const u8,
    path: []const u8,
    system_local_time: bool = false,
};

const examples = [_]Example{
    .{ .name = "quick-start", .path = "examples/quick_start.zig" },
    .{ .name = "file-logging", .path = "examples/file_logging.zig" },
    .{ .name = "structured", .path = "examples/structured.zig" },
    .{ .name = "threaded", .path = "examples/threaded.zig" },
    .{ .name = "rolling", .path = "examples/rolling.zig" },
    .{ .name = "basic", .path = "examples/basic.zig" },
    .{ .name = "readable-time", .path = "examples/readable_time.zig" },
    .{ .name = "async-memory", .path = "examples/async_memory.zig" },
    .{ .name = "std-log", .path = "examples/std_log.zig" },
    .{ .name = "prepared", .path = "examples/prepared.zig" },
    .{ .name = "hot-configuration", .path = "examples/hot_configuration.zig" },
    .{ .name = "configuration-sources", .path = "examples/configuration_sources.zig" },
    .{ .name = "predicates", .path = "examples/predicates.zig" },
    .{ .name = "tsc-clock", .path = "examples/tsc_clock.zig" },
    .{ .name = "local-time", .path = "examples/local_time.zig", .system_local_time = true },
    .{ .name = "file-stdout-local-time", .path = "examples/file_stdout_local_time.zig", .system_local_time = true },
    .{ .name = "mmap", .path = "examples/mmap.zig", .system_local_time = true },
    .{ .name = "source-location", .path = "examples/source_location.zig", .system_local_time = true },
};

pub fn addExamples(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, module: *std.Build.Module, verify: *std.Build.Step) void {
    for (examples) |example| {
        const libc: ?bool = if (example.system_local_time) target.result.os.tag != .windows else null;
        const example_module = createExampleModule(b, target, optimize, module, example.path, libc);
        const name = if (example.system_local_time) b.fmt("kron-{s}-example", .{example.name}) else b.fmt("kron-{s}", .{example.name});
        const executable = b.addExecutable(.{ .name = name, .root_module = example_module });
        const run = b.addRunArtifact(executable);
        b.step(b.fmt("run-{s}", .{example.name}), b.fmt("Run the {s} example", .{example.name})).dependOn(&run.step);
        verify.dependOn(&executable.step);
    }
}

fn createExampleModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kron: *std.Build.Module, path: []const u8, link_libc: ?bool) *std.Build.Module {
    const selection = b.addOptions();
    selection.addOption([]const u8, "name", std.fs.path.stem(path));
    const example = b.createModule(.{ .root_source_file = b.path("examples.zig"), .target = target, .optimize = optimize, .link_libc = link_libc });
    example.addImport("kron", kron);
    example.addOptions("kron_example", selection);
    return example;
}
