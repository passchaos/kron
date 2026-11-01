const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const single_threaded = b.option(bool, "single-threaded", "Build a synchronous single-threaded consumer") orelse false;
    const system_local_time = b.option(bool, "system-local-time", "Enable system local-time conversion through the dependency") orelse false;
    const dependency = b.dependency("kron", .{ .target = target, .optimize = optimize, .@"single-threaded" = single_threaded, .@"system-local-time" = system_local_time });
    const module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize, .single_threaded = single_threaded });
    module.addImport("kron", dependency.module("kron"));
    const executable = b.addExecutable(.{ .name = "kron-package-consumer", .root_module = module });
    b.installArtifact(executable);
    const run = b.addRunArtifact(executable);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the independent Zig application").dependOn(&run.step);

    const tests_module = b.createModule(.{ .root_source_file = b.path("tests.zig"), .target = target, .optimize = optimize, .single_threaded = single_threaded });
    tests_module.addImport("kron", dependency.module("kron"));
    tests_module.addImport("consumer", module);
    const tests = b.addTest(.{ .root_module = tests_module });
    b.step("check", "Compile the public package from an independent consumer").dependOn(&tests.step);
    b.step("test", "Run independent package argument and API tests").dependOn(&b.addRunArtifact(tests).step);
}
