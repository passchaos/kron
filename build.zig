const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const single_threaded = b.option(bool, "single-threaded", "Build the imported kron module for a single-threaded application");
    const module = b.addModule("kron", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single_threaded,
        .link_libc = switch (target.result.os.tag) {
            .macos, .ios => true,
            else => if (target.result.abi == .android) true else null,
        },
    });

    const tests = b.addTest(.{ .root_module = module });
    const run_tests = b.addRunArtifact(tests);
    if (b.args) |args| run_tests.addArgs(args);
    const test_step = b.step("test", "Run kron unit and integration tests");
    test_step.dependOn(&run_tests.step);

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
            else => if (query.abi == .android) true else null,
        } });
        const object = b.addObject(.{ .name = b.fmt("kron-{s}-{s}-{s}", .{ @tagName(query.cpu_arch.?), @tagName(query.os_tag.?), @tagName(query.abi orelse .none) }), .root_module = platform_module });
        _ = object.getEmittedBin();
        platform_step.dependOn(&object.step);
    }

    const adapter_module = b.createModule(.{ .root_source_file = b.path("tests/adapter_integration.zig"), .target = target, .optimize = optimize });
    adapter_module.addImport("kron", module);
    const adapter_tests = b.addTest(.{ .name = "kron-adapter", .root_module = adapter_module });
    const run_adapter = b.addRunArtifact(adapter_tests);
    b.step("test-adapter", "Verify explicitly selected object fields and captured ownership").dependOn(&run_adapter.step);
    test_step.dependOn(&run_adapter.step);

    const redaction_module = b.createModule(.{ .root_source_file = b.path("tests/redaction_paths.zig"), .target = target, .optimize = optimize });
    redaction_module.addImport("kron", module);
    const redaction_tests = b.addTest(.{ .name = "kron-redaction-paths", .root_module = redaction_module });
    const run_redaction = b.addRunArtifact(redaction_tests);
    b.step("test-redaction-paths", "Verify empty and configured redaction capture paths").dependOn(&run_redaction.step);
    test_step.dependOn(&run_redaction.step);

    const async_storage_module = b.createModule(.{ .root_source_file = b.path("tests/async_storage.zig"), .target = target, .optimize = optimize });
    async_storage_module.addImport("kron", module);
    const async_storage_tests = b.addTest(.{ .name = "kron-async-storage", .root_module = async_storage_module });
    const run_async_storage = b.addRunArtifact(async_storage_tests);
    b.step("test-async-storage", "Verify ordinary memory and mmap asynchronous storage").dependOn(&run_async_storage.step);
    test_step.dependOn(&run_async_storage.step);

    const file_failure_module = b.createModule(.{ .root_source_file = b.path("tests/file_delivery_failures.zig"), .target = target, .optimize = optimize });
    file_failure_module.addImport("kron", module);
    const file_failure_tests = b.addTest(.{ .name = "kron-file-delivery-failures", .root_module = file_failure_module });
    const run_file_failures = b.addRunArtifact(file_failure_tests);
    b.step("test-file-delivery", "Verify real file short-write errors and journal ownership").dependOn(&run_file_failures.step);
    test_step.dependOn(&run_file_failures.step);

    const capture_module = b.createModule(.{ .root_source_file = b.path("tests/capture_integration.zig"), .target = target, .optimize = optimize });
    capture_module.addImport("kron", module);
    const capture_tests = b.addTest(.{ .name = "kron-capture-integration", .root_module = capture_module });
    const run_capture_tests = b.addRunArtifact(capture_tests);
    b.step("test-capture", "Verify static capture and dynamic field/context boundaries").dependOn(&run_capture_tests.step);
    test_step.dependOn(&run_capture_tests.step);

    const single_kron = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize, .single_threaded = true, .link_libc = switch (target.result.os.tag) {
        .macos, .ios => true,
        else => if (target.result.abi == .android) true else null,
    } });
    const single_module = b.createModule(.{ .root_source_file = b.path("tests/single_threaded.zig"), .target = target, .optimize = optimize, .single_threaded = true });
    single_module.addImport("kron", single_kron);
    const single_exe = b.addExecutable(.{ .name = "kron-single-threaded", .root_module = single_module });
    const run_single = b.addRunArtifact(single_exe);
    b.step("test-single-threaded", "Run synchronous file logging in a single-threaded executable").dependOn(&run_single.step);

    const tool_module = b.createModule(.{
        .root_source_file = b.path("tools/kroncat.zig"),
        .target = target,
        .optimize = optimize,
    });
    tool_module.addImport("kron", module);
    const tool = b.addExecutable(.{ .name = "kroncat", .root_module = tool_module });
    b.installArtifact(tool);
    const run_tool = b.addRunArtifact(tool);
    if (b.args) |args| run_tool.addArgs(args);
    b.step("kroncat", "Read and query a journal or binary archive").dependOn(&run_tool.step);

    const integration_module = b.createModule(.{
        .root_source_file = b.path("tests/runtime_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_module.addImport("kron", module);
    const integration = b.addTest(.{ .name = "kron-integration", .root_module = integration_module });
    const run_integration = b.addRunArtifact(integration);
    test_step.dependOn(&run_integration.step);
    b.step("test-integration", "Run concurrent runtime and fault tests").dependOn(&run_integration.step);

    const time_tests_module = b.createModule(.{ .root_source_file = b.path("tests/time_integration.zig"), .target = target, .optimize = optimize });
    time_tests_module.addImport("kron", module);
    const time_tests = b.addTest(.{ .name = "kron-time", .root_module = time_tests_module });
    const run_time_tests = b.addRunArtifact(time_tests);
    test_step.dependOn(&run_time_tests.step);
    const time_oracle_module = b.createModule(.{ .root_source_file = b.path("tests/time_oracle.zig"), .target = target, .optimize = optimize });
    time_oracle_module.addImport("kron", module);
    const time_oracle = b.addExecutable(.{ .name = "kron-time-oracle", .root_module = time_oracle_module });
    const check_time = b.addSystemCommand(&.{ "python3", "tests/time_oracle.py", "--writer" });
    check_time.addArtifactArg(time_oracle);
    const time_step = b.step("test-time", "Verify fixed-offset time, hot routes and independent datetime oracle");
    time_step.dependOn(&run_time_tests.step);
    time_step.dependOn(&check_time.step);
    test_step.dependOn(&check_time.step);
    const time_bench_module = b.createModule(.{ .root_source_file = b.path("bench/time.zig"), .target = target, .optimize = optimize });
    time_bench_module.addImport("kron", module);
    const time_bench = b.addExecutable(.{ .name = "kron-time-bench", .root_module = time_bench_module });
    b.step("bench-time", "Measure fixed-offset calendar cache with exact output consumption").dependOn(&b.addRunArtifact(time_bench).step);

    const configuration_module = b.createModule(.{ .root_source_file = b.path("tests/configuration_integration.zig"), .target = target, .optimize = optimize });
    configuration_module.addImport("kron", module);
    const configuration_tests = b.addTest(.{ .name = "kron-configurations", .root_module = configuration_module });
    const run_configurations = b.addRunArtifact(configuration_tests);
    test_step.dependOn(&run_configurations.step);
    b.step("test-configurations", "Verify old and new delivery generations during replacement").dependOn(&run_configurations.step);

    const transactions_module = b.createModule(.{ .root_source_file = b.path("tests/configuration_transactions.zig"), .target = target, .optimize = optimize });
    transactions_module.addImport("kron", module);
    const transactions = b.addTest(.{ .name = "kron-transactions", .root_module = transactions_module });
    const run_transactions = b.addRunArtifact(transactions);
    test_step.dependOn(&run_transactions.step);
    b.step("test-transactions", "Verify configuration sources and generation-bound filter reload").dependOn(&run_transactions.step);

    const route_filter_module = b.createModule(.{ .root_source_file = b.path("tests/route_filter_integration.zig"), .target = target, .optimize = optimize });
    route_filter_module.addImport("kron", module);
    const route_filter_tests = b.addTest(.{ .name = "kron-route-filters", .root_module = route_filter_module });
    const run_route_filters = b.addRunArtifact(route_filter_tests);
    b.step("test-route-filters", "Verify 64-route level masks and live filter replacements through public APIs").dependOn(&run_route_filters.step);
    test_step.dependOn(&run_route_filters.step);

    const predicate_module = b.createModule(.{ .root_source_file = b.path("tests/predicate_integration.zig"), .target = target, .optimize = optimize });
    predicate_module.addImport("kron", module);
    const predicate_tests = b.addTest(.{ .name = "kron-predicates", .root_module = predicate_module });
    const run_predicates = b.addRunArtifact(predicate_tests);
    test_step.dependOn(&run_predicates.step);
    b.step("test-predicates", "Verify pre-acceptance predicates and channel cache lifetimes").dependOn(&run_predicates.step);

    const tsc_module = b.createModule(.{ .root_source_file = b.path("src/platform/tsc_clock.zig"), .target = target, .optimize = optimize });
    const tsc_test_module = b.createModule(.{ .root_source_file = b.path("tests/tsc_qualification.zig"), .target = target, .optimize = optimize });
    tsc_test_module.addImport("tsc", tsc_module);
    const tsc_tests = b.addTest(.{ .name = "kron-tsc-qualification", .root_module = tsc_test_module });
    const run_tsc_tests = b.addRunArtifact(tsc_tests);
    b.step("test-tsc", "Verify real TSC qualification, explicit fallback and refresh").dependOn(&run_tsc_tests.step);
    test_step.dependOn(&run_tsc_tests.step);

    const compression_module = b.createModule(.{ .root_source_file = b.path("tests/compressed_archive.zig"), .target = target, .optimize = optimize });
    compression_module.addImport("kron", module);
    const compression_tests = b.addTest(.{ .name = "kron-compression", .root_module = compression_module });
    const run_compression = b.addRunArtifact(compression_tests);
    test_step.dependOn(&run_compression.step);
    b.step("test-compression", "Verify compressed archive framing and bounded resources").dependOn(&run_compression.step);

    const deadline_module = b.createModule(.{
        .root_source_file = b.path("tests/deadline_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    deadline_module.addImport("kron", module);
    const deadline_tests = b.addTest(.{ .name = "kron-deadline", .root_module = deadline_module });
    const run_deadline = b.addRunArtifact(deadline_tests);
    test_step.dependOn(&run_deadline.step);
    b.step("test-deadline", "Verify timed control operations retain in-flight resources").dependOn(&run_deadline.step);

    const fuzz_module = b.createModule(.{ .root_source_file = b.path("tests/decoder_fuzz.zig"), .target = target, .optimize = optimize });
    fuzz_module.addImport("kron", module);
    const fuzz_tests = b.addTest(.{ .name = "kron-fuzz-smoke", .root_module = fuzz_module });
    const run_fuzz = b.addRunArtifact(fuzz_tests);
    b.step("test-fuzz", "Run reproducible decoder/version/schema and format mutation corpora").dependOn(&run_fuzz.step);
    const decoder_matrix_module = b.createModule(.{ .root_source_file = b.path("tests/decoder_matrix.zig"), .target = target, .optimize = optimize });
    decoder_matrix_module.addImport("kron", module);
    const decoder_matrix_tests = b.addTest(.{ .name = "kron-decoder-matrix", .root_module = decoder_matrix_module });
    b.step("test-decoder-matrix", "Verify legacy/current payloads, schema integrity and persistent Reader compatibility").dependOn(&b.addRunArtifact(decoder_matrix_tests).step);

    const query_module = b.createModule(.{
        .root_source_file = b.path("tests/tool_query.zig"),
        .target = target,
        .optimize = optimize,
    });
    query_module.addImport("kron", module);
    query_module.addImport("kroncat", tool_module);
    const query = b.addTest(.{ .name = "kron-query", .root_module = query_module });
    const run_query = b.addRunArtifact(query);
    test_step.dependOn(&run_query.step);
    b.step("test-query", "Run archive reader and query tests").dependOn(&run_query.step);

    const crash_module = b.createModule(.{
        .root_source_file = b.path("tests/crash_writer.zig"),
        .target = target,
        .optimize = optimize,
    });
    crash_module.addImport("kron", module);
    const crash_writer = b.addExecutable(.{ .name = "kron-crash-writer", .root_module = crash_module });
    const crash_check = b.addSystemCommand(&.{ "python3", "tests/crash_recovery.py", "--writer" });
    crash_check.addArtifactArg(crash_writer);
    crash_check.addArg("--reader");
    crash_check.addArtifactArg(tool);
    b.step("test-crash", "Kill real writers and recover through kroncat").dependOn(&crash_check.step);

    const async_crash_module = b.createModule(.{ .root_source_file = b.path("tests/async_crash_writer.zig"), .target = target, .optimize = optimize });
    async_crash_module.addImport("kron", module);
    const async_crash_writer = b.addExecutable(.{ .name = "kron-async-crash-writer", .root_module = async_crash_module });
    const async_crash_check = b.addSystemCommand(&.{ "python3", "tests/async_storage_crash.py", "--writer" });
    async_crash_check.addArtifactArg(async_crash_writer);
    async_crash_check.addArg("--reader");
    async_crash_check.addArtifactArg(tool);
    b.step("test-async-crash", "Verify actual crash loss for memory versus mmap recovery").dependOn(&async_crash_check.step);

    const campaign_module = b.createModule(.{ .root_source_file = b.path("tests/recovery_campaign_writer.zig"), .target = target, .optimize = optimize });
    campaign_module.addImport("kron", module);
    const campaign_writer = b.addExecutable(.{ .name = "kron-recovery-campaign-writer", .root_module = campaign_module });
    const campaign_check = b.addSystemCommand(&.{ "python3", "tests/recovery_campaign.py", "--writer" });
    campaign_check.addArtifactArg(campaign_writer);
    campaign_check.addArg("--reader");
    campaign_check.addArtifactArg(tool);
    b.step("test-recovery-campaign", "Verify seeded process crashes across ring wraps and route epochs").dependOn(&campaign_check.step);

    const random_crash_module = b.createModule(.{ .root_source_file = b.path("tests/runtime_crash_writer.zig"), .target = target, .optimize = optimize });
    random_crash_module.addImport("kron", module);
    const random_crash_writer = b.addExecutable(.{ .name = "kron-runtime-crash-writer", .root_module = random_crash_module });
    const random_crash_check = b.addSystemCommand(&.{ "python3", "tests/runtime_crash_campaign.py", "--writer" });
    random_crash_check.addArtifactArg(random_crash_writer);
    random_crash_check.addArg("--reader");
    random_crash_check.addArtifactArg(tool);
    const random_crash_oracle = b.addSystemCommand(&.{ "python3", "tests/test_runtime_crash_oracle.py" });
    const random_crash_step = b.step("test-runtime-crash", "Kill running shared/SPSC producers at random times and verify every ACK");
    random_crash_step.dependOn(&random_crash_check.step);
    random_crash_step.dependOn(&random_crash_oracle.step);
    b.step("test-runtime-crash-oracle", "Reject missing, duplicate, corrupt and conflicting recovery evidence").dependOn(&random_crash_oracle.step);

    const power_module = b.createModule(.{ .root_source_file = b.path("tests/power_loss/testwriter.zig"), .target = target, .optimize = optimize });
    power_module.addImport("kron", module);
    const power_writer = b.addExecutable(.{ .name = "kron-powerloss-writer", .root_module = power_module });
    const power_install = b.addInstallArtifact(power_writer, .{});
    b.step("powerloss-writer", "Build the static child-VM durability writer/verifier").dependOn(&power_install.step);

    const compile_fail = b.addSystemCommand(&.{ "python3", "tests/run_compile_fail.py", "--zig" });
    compile_fail.addArg(b.graph.zig_exe);
    b.step("test-compile-fail", "Verify invalid fields and formats are rejected").dependOn(&compile_fail.step);

    const verify = b.step("verify", "Run unit, integration, query, crash and compile-fail gates");
    verify.dependOn(test_step);
    verify.dependOn(&crash_check.step);
    verify.dependOn(&async_crash_check.step);
    verify.dependOn(&campaign_check.step);
    verify.dependOn(random_crash_step);
    const package_check = b.addSystemCommand(&.{ "python3", "tests/package_consumer.py", "--zig" });
    package_check.addArg(b.graph.zig_exe);
    package_check.addArgs(&.{ "--optimize", @tagName(optimize) });
    b.step("test-package", "Build and run an independent Zig package consumer").dependOn(&package_check.step);
    verify.dependOn(&package_check.step);
    const package_single = b.addSystemCommand(&.{ "python3", "tests/package_consumer.py", "--zig" });
    package_single.addArg(b.graph.zig_exe);
    package_single.addArgs(&.{ "--optimize", @tagName(optimize), "--single-threaded" });
    b.step("test-package-single-threaded", "Verify a single-threaded application imports kron through its dependency").dependOn(&package_single.step);
    verify.dependOn(&package_single.step);
    const package_distribution = b.addSystemCommand(&.{ "python3", "tests/package_consumer.py", "--zig" });
    package_distribution.addArg(b.graph.zig_exe);
    package_distribution.addArgs(&.{ "--optimize", @tagName(optimize), "--packaged" });
    b.step("test-package-distribution", "Fetch the source distribution locally and run a fresh Zig consumer").dependOn(&package_distribution.step);
    const platform_host = b.addSystemCommand(&.{ "python3", "tests/package_consumer.py", "--zig" });
    platform_host.addArg(b.graph.zig_exe);
    platform_host.addArgs(&.{ "--optimize", @tagName(optimize), "--platform-only" });
    b.step("test-platform-host", "Run native Zig host qualification of files, queues, journal reopen and durability").dependOn(&platform_host.step);
    verify.dependOn(&platform_host.step);
    verify.dependOn(&compile_fail.step);
    verify.dependOn(&run_fuzz.step);
    verify.dependOn(&run_single.step);
    b.step("verify-local", "Verify standalone logging").dependOn(verify);

    const regression_tests = b.addSystemCommand(&.{ "python3", "tests/test_regression.py" });
    b.step("test-regression", "Verify controlled performance regression accounting").dependOn(&regression_tests.step);
    verify.dependOn(&regression_tests.step);
    const cpp_reference_report_tests = b.addSystemCommand(&.{ "python3", "tests/test_cpp_reference.py" });
    b.step("test-cpp-reference-report", "Reject partial output, metadata mismatches and incomplete workflow benchmark reports").dependOn(&cpp_reference_report_tests.step);
    verify.dependOn(&cpp_reference_report_tests.step);

    const local_reuse = b.step("check-local-reuse", "Check Vort checksum interoperability with persistent kron formats");
    if (b.option([]const u8, "vort-path", "Path to a local Vort checkout for optional interoperability checks")) |vort_path| {
        const checksum_module = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ vort_path, "src/checksum.zig" }) }, .target = target, .optimize = optimize });
        const reuse_module = b.createModule(.{ .root_source_file = b.path("src/local_checksum_check.zig"), .target = target, .optimize = optimize, .single_threaded = true });
        reuse_module.addImport("vort_checksum", checksum_module);
        const reuse_exe = b.addExecutable(.{ .name = "kron-local-checksum-check", .root_module = reuse_module });
        local_reuse.dependOn(&b.addRunArtifact(reuse_exe).step);
    } else {
        local_reuse.dependOn(&b.addFail("check-local-reuse requires -Dvort-path=/path/to/vort").step);
    }
    const local_faults = b.step("check-local-faults", "Check persistent checkpoint prefixes with the local ZKV fault device");
    if (b.option([]const u8, "zkv-path", "Path to a local ZKV checkout for optional fault-model checks")) |zkv_path| {
        const fault_module = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ zkv_path, "src/storage/faultable_device.zig" }) }, .target = target, .optimize = optimize });
        const check_module = b.createModule(.{ .root_source_file = b.path("src/local_fault_check.zig"), .target = target, .optimize = optimize, .single_threaded = true });
        check_module.addImport("zkv_fault", fault_module);
        const check_exe = b.addExecutable(.{ .name = "kron-local-fault-check", .root_module = check_module });
        local_faults.dependOn(&b.addRunArtifact(check_exe).step);
    } else {
        local_faults.dependOn(&b.addFail("check-local-faults requires -Dzkv-path=/path/to/zkv").step);
    }

    const regex_module = b.createModule(.{ .root_source_file = b.path("tests/regex_differential.zig"), .target = target, .optimize = optimize });
    regex_module.addImport("kron", module);
    const regex_driver = b.addExecutable(.{ .name = "kron-regex-differential", .root_module = regex_module });
    const regex_check = b.addSystemCommand(&.{ "python3", "tests/regex_differential.py", "--driver" });
    regex_check.addArtifactArg(regex_driver);
    b.step("test-regex-differential", "Compare supported byte regexes with a seeded Python corpus").dependOn(&regex_check.step);
    verify.dependOn(&regex_check.step);

    const regex_fuzz_module = b.createModule(.{ .root_source_file = b.path("tests/regex_fuzz.zig"), .target = target, .optimize = optimize });
    regex_fuzz_module.addImport("kron", module);
    const regex_fuzz = b.addTest(.{ .name = "kron-regex-fuzz", .root_module = regex_fuzz_module });
    const run_regex_fuzz = b.addRunArtifact(regex_fuzz);
    b.step("test-regex-fuzz", "Run byte regex and predicate parser mutation corpora").dependOn(&run_regex_fuzz.step);
    verify.dependOn(&run_regex_fuzz.step);

    const regex_equivalence_module = b.createModule(.{ .root_source_file = b.path("tests/regex_equivalence.zig"), .target = target, .optimize = optimize });
    regex_equivalence_module.addImport("kron", module);
    const regex_equivalence = b.addTest(.{ .name = "kron-regex-equivalence", .root_module = regex_equivalence_module });
    const run_regex_equivalence = b.addRunArtifact(regex_equivalence);
    b.step("test-regex-equivalence", "Compare graph execution and expose coverage guided regex/parser fuzzing").dependOn(&run_regex_equivalence.step);
    verify.dependOn(&run_regex_equivalence.step);

    const regex_bench_module = b.createModule(.{ .root_source_file = b.path("bench/regex.zig"), .target = target, .optimize = optimize });
    regex_bench_module.addImport("kron", module);
    const regex_bench = b.addExecutable(.{ .name = "kron-regex-bench", .root_module = regex_bench_module });
    const run_regex_bench = b.addRunArtifact(regex_bench);
    if (b.args) |args| run_regex_bench.addArgs(args);
    b.step("bench-regex", "Measure bounded business regexes and complete synchronous JSON output").dependOn(&run_regex_bench.step);
    const regex_bench_tests = b.addTest(.{ .name = "kron-regex-bench-tests", .root_module = regex_bench_module });
    const run_regex_bench_tests = b.addRunArtifact(regex_bench_tests);
    const regex_compare_tests = b.addSystemCommand(&.{ "python3", "bench/regex_compare.py", "--self-test" });
    const regex_bench_step = b.step("test-regex-bench", "Verify regex workload decisions and reject invalid comparison evidence");
    regex_bench_step.dependOn(&run_regex_bench_tests.step);
    regex_bench_step.dependOn(&regex_compare_tests.step);
    verify.dependOn(regex_bench_step);

    const bench_module = b.createModule(.{ .root_source_file = b.path("bench/main.zig"), .target = target, .optimize = optimize });
    bench_module.addImport("kron", module);
    const bench = b.addExecutable(.{ .name = "kron-bench", .root_module = bench_module });
    b.installArtifact(bench);
    const run_bench = b.addRunArtifact(bench);
    if (b.args) |args| run_bench.addArgs(args);
    b.step("bench", "Measure producer latency and completed output throughput").dependOn(&run_bench.step);
    const bench_tests = b.addTest(.{ .name = "kron-bench-tests", .root_module = bench_module });
    const run_bench_tests = b.addRunArtifact(bench_tests);
    b.step("test-bench", "Verify benchmark argument and accounting helpers").dependOn(&run_bench_tests.step);
    verify.dependOn(&run_bench_tests.step);
    const dispatch_module = b.createModule(.{ .root_source_file = b.path("bench/dispatch.zig"), .target = target, .optimize = optimize });
    dispatch_module.addImport("kron", module);
    const dispatch = b.addExecutable(.{ .name = "kron-dispatch-bench", .root_module = dispatch_module });
    const run_dispatch = b.addRunArtifact(dispatch);
    if (b.args) |args| run_dispatch.addArgs(args);
    b.step("bench-dispatch", "Measure clock dispatch independently of queues and I/O").dependOn(&run_dispatch.step);
    const dispatch_tests = b.addTest(.{ .name = "kron-dispatch-tests", .root_module = dispatch_module });
    const run_dispatch_tests = b.addRunArtifact(dispatch_tests);
    b.step("test-dispatch", "Verify isolated clock benchmark accounting").dependOn(&run_dispatch_tests.step);
    verify.dependOn(&run_dispatch_tests.step);

    const snapshot_module = b.createModule(.{ .root_source_file = b.path("bench/snapshot.zig"), .target = target, .optimize = optimize });
    snapshot_module.addImport("kron", module);
    const snapshot_bench = b.addExecutable(.{ .name = "kron-snapshot-bench", .root_module = snapshot_module });
    const run_snapshot = b.addRunArtifact(snapshot_bench);
    if (b.args) |args| run_snapshot.addArgs(args);
    b.step("bench-snapshot", "Measure shared and channel-cached admission separately from full output").dependOn(&run_snapshot.step);
    const snapshot_tests = b.addTest(.{ .name = "kron-snapshot-tests", .root_module = snapshot_module });
    const run_snapshot_tests = b.addRunArtifact(snapshot_tests);
    b.step("test-snapshot", "Verify bounded snapshot benchmark options").dependOn(&run_snapshot_tests.step);
    verify.dependOn(&run_snapshot_tests.step);

    const routes_bench_module = b.createModule(.{ .root_source_file = b.path("bench/routes.zig"), .target = target, .optimize = optimize });
    routes_bench_module.addImport("kron", module);
    const routes_bench = b.addExecutable(.{ .name = "kron-route-enabled", .root_module = routes_bench_module });
    b.step("bench-routes", "Measure public enabled decisions with inherited and independent route filters").dependOn(&b.addRunArtifact(routes_bench).step);

    const crc_bench_module = b.createModule(.{ .root_source_file = b.path("bench/crc.zig"), .target = target, .optimize = optimize });
    const crc_module = b.createModule(.{ .root_source_file = b.path("src/platform/crc32.zig"), .target = target, .optimize = optimize });
    crc_bench_module.addImport("crc", crc_module);
    const crc_bench = b.addExecutable(.{ .name = "kron-crc-bench", .root_module = crc_bench_module });
    b.step("bench-crc", "Measure portable IEEE CRC with journal headers and schema references").dependOn(&b.addRunArtifact(crc_bench).step);

    const tsc_bench_module = b.createModule(.{ .root_source_file = b.path("bench/tsc.zig"), .target = target, .optimize = optimize });
    tsc_bench_module.addImport("kron", module);
    const tsc_bench = b.addExecutable(.{ .name = "kron-tsc-bench", .root_module = tsc_bench_module });
    b.step("bench-tsc", "Compare qualified TSC and native wall clocks with fallback counts").dependOn(&b.addRunArtifact(tsc_bench).step);

    const sampling_module = b.createModule(.{ .root_source_file = b.path("bench/sampling.zig"), .target = target, .optimize = optimize });
    sampling_module.addImport("kron", module);
    const sampling_bench = b.addExecutable(.{ .name = "kron-sampling-bench", .root_module = sampling_module });
    const run_sampling = b.addRunArtifact(sampling_bench);
    if (b.args) |args| run_sampling.addArgs(args);
    b.step("bench-sampling", "Measure exact global sampling separately from output queues").dependOn(&run_sampling.step);
    const sampling_tests = b.addTest(.{ .name = "kron-sampling-bench-tests", .root_module = sampling_module });
    const run_sampling_tests = b.addRunArtifact(sampling_tests);
    b.step("test-sampling-bench", "Verify bounded repeated sampling benchmark inputs").dependOn(&run_sampling_tests.step);
    verify.dependOn(&run_sampling_tests.step);

    const encoding_module = b.createModule(.{ .root_source_file = b.path("bench/encoding.zig"), .target = target, .optimize = optimize });
    encoding_module.addImport("kron", module);
    const encoding_bench = b.addExecutable(.{ .name = "kron-encoding-bench", .root_module = encoding_module });
    const run_encoding = b.addRunArtifact(encoding_bench);
    if (b.args) |args| run_encoding.addArgs(args);
    b.step("bench-encoding", "Measure validated binary encoding and archive framing").dependOn(&run_encoding.step);
    const encoding_tests = b.addTest(.{ .name = "kron-encoding-bench-tests", .root_module = encoding_module });
    const run_encoding_tests = b.addRunArtifact(encoding_tests);
    b.step("test-encoding-bench", "Verify encoding benchmark budgets and input shapes").dependOn(&run_encoding_tests.step);
    verify.dependOn(&run_encoding_tests.step);

    const capture_bench_module = b.createModule(.{ .root_source_file = b.path("bench/capture.zig"), .target = target, .optimize = optimize });
    capture_bench_module.addImport("kron", module);
    const capture_bench = b.addExecutable(.{ .name = "kron-capture-bench", .root_module = capture_bench_module });
    const run_capture_bench = b.addRunArtifact(capture_bench);
    if (b.args) |args| run_capture_bench.addArgs(args);
    b.step("bench-capture", "Measure typed field capture and full synchronous output").dependOn(&run_capture_bench.step);
    const capture_bench_tests = b.addTest(.{ .name = "kron-capture-bench-tests", .root_module = capture_bench_module });
    const run_capture_bench_tests = b.addRunArtifact(capture_bench_tests);
    b.step("test-capture-bench", "Verify capture benchmark shapes and bounded inputs").dependOn(&run_capture_bench_tests.step);
    verify.dependOn(&run_capture_bench_tests.step);

    inline for (.{ .{ "basic", "examples/basic.zig" }, .{ "readable-time", "examples/readable_time.zig" }, .{ "async-memory", "examples/async_memory.zig" }, .{ "std-log", "examples/std_log.zig" }, .{ "prepared", "examples/prepared.zig" }, .{ "hot-configuration", "examples/hot_configuration.zig" }, .{ "configuration-sources", "examples/configuration_sources.zig" }, .{ "predicates", "examples/predicates.zig" }, .{ "tsc-clock", "examples/tsc_clock.zig" } }) |example| {
        const example_module = b.createModule(.{ .root_source_file = b.path(example[1]), .target = target, .optimize = optimize });
        example_module.addImport("kron", module);
        const exe = b.addExecutable(.{ .name = "kron-" ++ example[0], .root_module = example_module });
        const run = b.addRunArtifact(exe);
        b.step("run-" ++ example[0], "Run the " ++ example[0] ++ " example").dependOn(&run.step);
        verify.dependOn(&exe.step);
    }

    const check_tests = b.addTest(.{ .root_module = module });
    b.step("check", "Compile the public module and tests").dependOn(&check_tests.step);
}
