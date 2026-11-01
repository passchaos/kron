const std = @import("std");
const tsc = @import("tsc");

test "actual capability probe is internally coherent" {
    const capability = tsc.probeCapabilities(.{});
    if (!tsc.supported) {
        try std.testing.expect(!capability.platform_supported);
        return;
    }
    try std.testing.expect(capability.platform_supported);
    if (capability.frequency_hz == 0) {
        try std.testing.expectEqual(tsc.FrequencySource.none, capability.frequency_source);
    } else {
        try std.testing.expect(capability.frequency_source != .none);
    }
}

test "qualified clock or conservative native fallback remains real time" {
    var clock = try tsc.TscClock.create(std.testing.allocator, std.testing.io, .{
        .calibration_samples = 3,
        .interval_ns = std.time.ns_per_ms,
        .max_error_ppm = 20_000,
        .refresh_ns = 200 * std.time.ns_per_ms,
    });
    defer clock.destroy();

    const selected = clock.clock();
    const wall_before = std.Io.Clock.real.now(std.testing.io).toNanoseconds();
    const wall = selected.realNow(std.testing.io);
    const wall_after = std.Io.Clock.real.now(std.testing.io).toNanoseconds();
    try std.testing.expect(wall >= wall_before - std.time.ns_per_s);
    try std.testing.expect(wall <= wall_after + std.time.ns_per_s);

    const monotonic_a = selected.monotonicNow(std.testing.io);
    const monotonic_b = selected.monotonicNow(std.testing.io);
    try std.testing.expect(monotonic_b >= monotonic_a);

    const stats = clock.stats();
    try std.testing.expect(stats.status != .probing);
    if (stats.status == .qualified) {
        try std.testing.expect(stats.calibrated_hz != 0);
        try std.testing.expect(stats.generation != 0);
        try std.testing.expect(stats.expected_aux != 0 or stats.capability.has_rdtscp);
    } else {
        std.debug.print("TSC qualification used native fallback: status={t}\n", .{stats.status});
        try std.testing.expect(stats.fallbacks >= 2);
    }
}

test "expired mapping falls back until explicit refresh" {
    var clock = try tsc.TscClock.create(std.testing.allocator, std.testing.io, .{
        .calibration_samples = 3,
        .interval_ns = std.time.ns_per_ms,
        .max_error_ppm = 50_000,
        .refresh_ns = 20 * std.time.ns_per_ms,
    });
    defer clock.destroy();
    if (clock.status() != .qualified) return;

    const monotonic_before = clock.monotonicNow(std.testing.io);
    try std.Io.sleep(std.testing.io, .fromMilliseconds(30), .awake);
    const wall_before = std.Io.Clock.real.now(std.testing.io).toNanoseconds();
    const after = clock.realNow(std.testing.io);
    const wall_after = std.Io.Clock.real.now(std.testing.io).toNanoseconds();
    try std.testing.expect(after >= wall_before - std.time.ns_per_s and after <= wall_after + std.time.ns_per_s);
    try std.testing.expect(clock.monotonicNow(std.testing.io) >= monotonic_before);
    const invalid_status = clock.status();
    try std.testing.expect(invalid_status == .stale or invalid_status == .migration_detected);
    const invalid_stats = clock.stats();
    try std.testing.expect(invalid_stats.fallbacks != 0);
    if (invalid_status == .migration_detected)
        try std.testing.expect(invalid_stats.migrations != 0);

    const generation = invalid_stats.generation;
    clock.refresh() catch |err| {
        // Actual calibration can conservatively reject a noisy host. Preserve
        // its safety contract: reject qualification and use real native time.
        switch (err) {
            error.CalibrationUnstable => try std.testing.expectEqual(tsc.Status.calibration_unstable, clock.status()),
            error.CrossCoreUnsynchronized => try std.testing.expectEqual(tsc.Status.cross_core_unsynchronized, clock.status()),
            else => return err,
        }
        const fallbacks = clock.stats().fallbacks;
        const native_before = std.Io.Clock.real.now(std.testing.io).toNanoseconds();
        const fallback = clock.realNow(std.testing.io);
        const native_after = std.Io.Clock.real.now(std.testing.io).toNanoseconds();
        try std.testing.expect(fallback >= native_before - std.time.ns_per_s and fallback <= native_after + std.time.ns_per_s);
        try std.testing.expectEqual(fallbacks + 1, clock.stats().fallbacks);
        std.debug.print("TSC refresh conservatively rejected noisy calibration: {s}\n", .{@errorName(err)});
        return;
    };
    try std.testing.expectEqual(tsc.Status.qualified, clock.status());
    try std.testing.expect(clock.stats().generation > generation);
    try std.testing.expect(clock.monotonicNow(std.testing.io) >= monotonic_before);
}
