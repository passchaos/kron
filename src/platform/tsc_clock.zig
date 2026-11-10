//! Optional x86_64 Linux TSC clock. Qualification is deliberately conservative:
//! any unsupported capability, unstable calibration, migration, stale mapping,
//! or detected drift falls back to NativeClock instead of inventing wall time.
const std = @import("std");
const builtin = @import("builtin");
const Clock = @import("clock.zig").Clock;
const NativeClock = @import("static_clock.zig").NativeClock;
const tsc_math = @import("tsc_math.zig");
const max_samples = tsc_math.max_samples;
const CounterSample = tsc_math.CounterSample;
const qualifyCounterSamples = tsc_math.qualifyCounterSamples;
const estimateTicks = tsc_math.estimateTicks;
const multiplierQ32 = tsc_math.multiplierQ32;
const ticksToNs = tsc_math.ticksToNs;
const driftExceeded = tsc_math.driftExceeded;
const addSignedSaturating = tsc_math.addSignedSaturating;
const clampMonotonic = tsc_math.clampMonotonic;

pub const supported = builtin.os.tag == .linux and builtin.cpu.arch == .x86_64;

pub const Options = struct {
    calibration_samples: u8 = 7,
    interval_ns: u64 = std.time.ns_per_ms,
    max_error_ppm: u32 = 2_000,
    refresh_ns: u64 = 5 * std.time.ns_per_s,
    require_invariant: bool = true,
    allow_hypervisor: bool = false,
};

pub const Status = enum(u8) {
    probing,
    qualified,
    unsupported_platform,
    tsc_unavailable,
    rdtscp_unavailable,
    invariant_required,
    hypervisor_disallowed,
    frequency_unavailable,
    invalid_options,
    calibration_canceled,
    calibration_unstable,
    cross_core_unsynchronized,
    migration_detected,
    stale,
    drift_exceeded,
};

pub const FrequencySource = enum(u8) {
    none,
    cpuid_leaf_15,
    cpuid_leaf_16,
};

pub const Capability = struct {
    platform_supported: bool = supported,
    has_tsc: bool = false,
    has_rdtscp: bool = false,
    invariant_tsc: bool = false,
    hypervisor: bool = false,
    frequency_source: FrequencySource = .none,
    frequency_hz: u64 = 0,
};

pub const Stats = struct {
    status: Status,
    capability: Capability,
    instance_cookie: u64,
    calibrated_hz: u64,
    calibration_error_ppm: u32,
    expected_aux: u32,
    generation: u64,
    refreshes: u64,
    tsc_reads: u64,
    fallbacks: u64,
    migrations: u64,
    stale_reads: u64,
};

const TscReading = struct {
    ticks: u64,
    aux: u32,
};

const Calibration = struct {
    real_anchor_ticks: u64,
    real_anchor_ns: i64,
    monotonic_anchor_ticks: u64,
    monotonic_anchor_ns: u64,
    deadline_ticks: u64,
    multiplier_q32: u64,
    frequency_hz: u64,
    expected_aux: u32,
    error_ppm: u32,
};

const CalibrationSnapshot = struct {
    generation: u64,
    calibration: Calibration,
};

const CachedCalibration = struct {
    instance_cookie: u64 = 0,
    generation: u64 = 0,
    calibration: Calibration = undefined,
};

const ThreadCache = struct {
    threadlocal var calibration: CachedCalibration = .{};
};

const InstanceCookies = struct {
    var next: std.atomic.Value(u64) = .init(1);
};

const TimeSource = struct {
    context: ?*anyopaque = null,
    real_now: *const fn (?*anyopaque, std.Io) i64 = nativeReal,
    monotonic_now: *const fn (?*anyopaque, std.Io) u64 = nativeMonotonic,

    fn real(self: TimeSource, io: std.Io) i64 {
        return self.real_now(self.context, io);
    }

    fn monotonic(self: TimeSource, io: std.Io) u64 {
        return self.monotonic_now(self.context, io);
    }

    fn nativeReal(_: ?*anyopaque, io: std.Io) i64 {
        return NativeClock.realNow(io);
    }

    fn nativeMonotonic(_: ?*anyopaque, io: std.Io) u64 {
        return NativeClock.monotonicNow(io);
    }
};

const AtomicCalibration = struct {
    sequence: std.atomic.Value(u64) = .init(0),
    real_anchor_ticks: std.atomic.Value(u64) = .init(0),
    real_anchor_ns: std.atomic.Value(i64) = .init(0),
    monotonic_anchor_ticks: std.atomic.Value(u64) = .init(0),
    monotonic_anchor_ns: std.atomic.Value(u64) = .init(0),
    deadline_ticks: std.atomic.Value(u64) = .init(0),
    multiplier_q32: std.atomic.Value(u64) = .init(0),
    frequency_hz: std.atomic.Value(u64) = .init(0),
    expected_aux: std.atomic.Value(u32) = .init(0),
    error_ppm: std.atomic.Value(u32) = .init(0),

    fn store(self: *AtomicCalibration, value: Calibration) void {
        const previous = self.sequence.load(.seq_cst);
        std.debug.assert(previous & 1 == 0);
        self.sequence.store(previous +% 1, .seq_cst);
        self.real_anchor_ticks.store(value.real_anchor_ticks, .seq_cst);
        self.real_anchor_ns.store(value.real_anchor_ns, .seq_cst);
        self.monotonic_anchor_ticks.store(value.monotonic_anchor_ticks, .seq_cst);
        self.monotonic_anchor_ns.store(value.monotonic_anchor_ns, .seq_cst);
        self.deadline_ticks.store(value.deadline_ticks, .seq_cst);
        self.multiplier_q32.store(value.multiplier_q32, .seq_cst);
        self.frequency_hz.store(value.frequency_hz, .seq_cst);
        self.expected_aux.store(value.expected_aux, .seq_cst);
        self.error_ppm.store(value.error_ppm, .seq_cst);
        self.sequence.store(previous +% 2, .seq_cst);
    }

    fn load(self: *const AtomicCalibration) ?Calibration {
        const before = self.sequence.load(.seq_cst);
        if (before & 1 != 0) return null;
        const value: Calibration = .{
            .real_anchor_ticks = self.real_anchor_ticks.load(.seq_cst),
            .real_anchor_ns = self.real_anchor_ns.load(.seq_cst),
            .monotonic_anchor_ticks = self.monotonic_anchor_ticks.load(.seq_cst),
            .monotonic_anchor_ns = self.monotonic_anchor_ns.load(.seq_cst),
            .deadline_ticks = self.deadline_ticks.load(.seq_cst),
            .multiplier_q32 = self.multiplier_q32.load(.seq_cst),
            .frequency_hz = self.frequency_hz.load(.seq_cst),
            .expected_aux = self.expected_aux.load(.seq_cst),
            .error_ppm = self.error_ppm.load(.seq_cst),
        };
        return if (self.sequence.load(.seq_cst) == before) value else null;
    }
};

pub const TscClock = struct {
    allocator: std.mem.Allocator,
    instance_cookie: u64,
    io: std.Io,
    source: TimeSource,
    options: Options,
    capability: Capability,
    slots: [2]AtomicCalibration = .{ .{}, .{} },
    generation: std.atomic.Value(u64) = .init(0),
    status_value: std.atomic.Value(Status) = .init(.probing),
    refreshing: std.atomic.Value(bool) = .init(false),
    last_monotonic_ns: std.atomic.Value(u64),
    refresh_count: std.atomic.Value(u64) = .init(0),
    tsc_read_count: std.atomic.Value(u64) = .init(0),
    fallback_count: std.atomic.Value(u64) = .init(0),
    migration_count: std.atomic.Value(u64) = .init(0),
    stale_count: std.atomic.Value(u64) = .init(0),

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*TscClock {
        return createWithSource(allocator, io, options, .{});
    }

    fn createWithSource(
        allocator: std.mem.Allocator,
        io: std.Io,
        options: Options,
        source: TimeSource,
    ) !*TscClock {
        const instance_cookie = try allocateInstanceCookie(&InstanceCookies.next);
        const self = try allocator.create(TscClock);
        self.* = .{
            .allocator = allocator,
            .instance_cookie = instance_cookie,
            .io = io,
            .source = source,
            .options = options,
            .capability = probeCapabilities(options),
            .last_monotonic_ns = .init(source.monotonic(io)),
        };
        self.refresh() catch {};
        return self;
    }

    pub fn destroy(self: *TscClock) void {
        const allocator = self.allocator;
        self.* = undefined;
        allocator.destroy(self);
    }

    pub fn clock(self: *TscClock) Clock {
        return .{
            .context = self,
            .real_now = realCallback,
            .monotonic_now = monotonicCallback,
        };
    }

    pub fn realNow(self: *TscClock, io: std.Io) i64 {
        const calibration = self.hotCalibration() orelse return self.fallbackReal(io);
        const reading = readTsc() orelse return self.fallbackReal(io);
        _ = self.tsc_read_count.fetchAdd(1, .monotonic);
        if (!self.validateReading(reading, calibration)) return self.fallbackReal(io);
        if (reading.ticks < calibration.real_anchor_ticks) return self.invalidate(.cross_core_unsynchronized, io, true);
        const delta_ns = ticksToNs(reading.ticks - calibration.real_anchor_ticks, calibration.multiplier_q32) orelse
            return self.invalidate(.stale, io, true);
        const candidate = addSignedSaturating(calibration.real_anchor_ns, delta_ns);
        return candidate;
    }

    pub fn monotonicNow(self: *TscClock, io: std.Io) u64 {
        const calibration = self.hotCalibration() orelse return self.fallbackMonotonic(io);
        const reading = readTsc() orelse return self.fallbackMonotonic(io);
        _ = self.tsc_read_count.fetchAdd(1, .monotonic);
        if (!self.validateReading(reading, calibration)) return self.fallbackMonotonic(io);
        if (reading.ticks < calibration.monotonic_anchor_ticks) return self.invalidateMonotonic(.cross_core_unsynchronized, io);
        const delta_ns = ticksToNs(reading.ticks - calibration.monotonic_anchor_ticks, calibration.multiplier_q32) orelse
            return self.invalidateMonotonic(.stale, io);
        const candidate = calibration.monotonic_anchor_ns +| delta_ns;
        return clampMonotonic(&self.last_monotonic_ns, candidate);
    }

    pub fn refresh(self: *TscClock) !void {
        if (self.refreshing.cmpxchgStrong(false, true, .acquire, .monotonic) != null)
            return error.RefreshInProgress;
        defer self.refreshing.store(false, .release);

        const rejection = capabilityRejection(self.capability, self.options);
        if (rejection) |reason| {
            self.status_value.store(reason, .release);
            return error.NotQualified;
        }
        if (!validOptions(self.options)) {
            self.status_value.store(.invalid_options, .release);
            return error.InvalidOptions;
        }

        const previous = self.loadCalibration();
        const calibration = self.calibrate() catch |err| {
            self.status_value.store(switch (err) {
                error.CalibrationCanceled => .calibration_canceled,
                error.CalibrationUnstable => .calibration_unstable,
                error.CrossCoreUnsynchronized => .cross_core_unsynchronized,
            }, .release);
            return err;
        };

        if (previous) |old| {
            const elapsed = calibration.monotonic_anchor_ns -| old.monotonic_anchor_ns;
            if (elapsed != 0 and calibration.monotonic_anchor_ticks >= old.monotonic_anchor_ticks) {
                const predicted_delta = ticksToNs(
                    calibration.monotonic_anchor_ticks - old.monotonic_anchor_ticks,
                    old.multiplier_q32,
                ) orelse std.math.maxInt(u64);
                const actual_delta = elapsed;
                if (driftExceeded(predicted_delta, actual_delta, self.options.max_error_ppm)) {
                    self.status_value.store(.drift_exceeded, .release);
                    return error.DriftExceeded;
                }
            }
        }

        self.publish(calibration);
        self.status_value.store(.qualified, .release);
        _ = self.refresh_count.fetchAdd(1, .monotonic);
    }

    pub fn status(self: *const TscClock) Status {
        return self.status_value.load(.acquire);
    }

    pub fn stats(self: *const TscClock) Stats {
        const snapshot = self.loadCalibrationWithGeneration();
        return .{
            .status = self.status(),
            .capability = self.capability,
            .instance_cookie = self.instance_cookie,
            .calibrated_hz = if (snapshot) |value| value.calibration.frequency_hz else 0,
            .calibration_error_ppm = if (snapshot) |value| value.calibration.error_ppm else 0,
            .expected_aux = if (snapshot) |value| value.calibration.expected_aux else 0,
            .generation = if (snapshot) |value| value.generation else 0,
            .refreshes = self.refresh_count.load(.monotonic),
            .tsc_reads = self.tsc_read_count.load(.monotonic),
            .fallbacks = self.fallback_count.load(.monotonic),
            .migrations = self.migration_count.load(.monotonic),
            .stale_reads = self.stale_count.load(.monotonic),
        };
    }

    fn realCallback(context: ?*anyopaque, io: std.Io) i64 {
        const self: *TscClock = @ptrCast(@alignCast(context.?));
        return self.realNow(io);
    }

    fn monotonicCallback(context: ?*anyopaque, io: std.Io) u64 {
        const self: *TscClock = @ptrCast(@alignCast(context.?));
        return self.monotonicNow(io);
    }

    fn hotCalibration(self: *const TscClock) ?Calibration {
        if (self.status_value.load(.acquire) != .qualified) return null;
        const generation = self.generation.load(.seq_cst);
        if (generation == 0) return null;
        const cached = &ThreadCache.calibration;
        if (cached.instance_cookie == self.instance_cookie and cached.generation == generation)
            return cached.calibration;
        const snapshot = self.loadCalibrationWithGeneration() orelse return null;
        cached.* = .{
            .instance_cookie = self.instance_cookie,
            .generation = snapshot.generation,
            .calibration = snapshot.calibration,
        };
        return snapshot.calibration;
    }

    fn loadCalibration(self: *const TscClock) ?Calibration {
        const snapshot = self.loadCalibrationWithGeneration() orelse return null;
        return snapshot.calibration;
    }

    fn loadCalibrationWithGeneration(self: *const TscClock) ?CalibrationSnapshot {
        var attempts: usize = 0;
        while (attempts < 3) : (attempts += 1) {
            const before = self.generation.load(.seq_cst);
            if (before == 0) return null;
            const value = self.slots[before & 1].load() orelse continue;
            const after = self.generation.load(.seq_cst);
            if (before == after) return .{ .generation = before, .calibration = value };
        }
        return null;
    }

    fn publish(self: *TscClock, calibration: Calibration) void {
        const next = self.generation.load(.monotonic) +% 1;
        self.slots[next & 1].store(calibration);
        self.generation.store(next, .seq_cst);
    }

    fn validateReading(self: *TscClock, reading: TscReading, calibration: Calibration) bool {
        const rejection = readingRejection(reading, calibration) orelse return true;
        switch (rejection) {
            .migration_detected => _ = self.migration_count.fetchAdd(1, .monotonic),
            .stale => _ = self.stale_count.fetchAdd(1, .monotonic),
            else => unreachable,
        }
        self.status_value.store(rejection, .release);
        return false;
    }

    fn fallbackReal(self: *TscClock, io: std.Io) i64 {
        _ = self.fallback_count.fetchAdd(1, .monotonic);
        return self.source.real(io);
    }

    fn fallbackMonotonic(self: *TscClock, io: std.Io) u64 {
        _ = self.fallback_count.fetchAdd(1, .monotonic);
        return clampMonotonic(&self.last_monotonic_ns, self.source.monotonic(io));
    }

    fn invalidate(self: *TscClock, reason: Status, io: std.Io, stale: bool) i64 {
        if (stale) _ = self.stale_count.fetchAdd(1, .monotonic);
        self.status_value.store(reason, .release);
        return self.fallbackReal(io);
    }

    fn invalidateMonotonic(self: *TscClock, reason: Status, io: std.Io) u64 {
        self.status_value.store(reason, .release);
        return self.fallbackMonotonic(io);
    }

    fn calibrate(self: *TscClock) !Calibration {
        var samples: [max_samples]CounterSample = undefined;
        var aux: ?u32 = null;
        for (samples[0..self.options.calibration_samples]) |*sample| {
            const start = captureMonotonic(self.source, self.io) orelse return error.CalibrationUnstable;
            if (aux) |expected| {
                if (start.aux != expected) return error.CalibrationUnstable;
            } else aux = start.aux;
            std.Io.sleep(
                self.io,
                .fromNanoseconds(@intCast(self.options.interval_ns)),
                .awake,
            ) catch return error.CalibrationCanceled;
            const finish = captureMonotonic(self.source, self.io) orelse return error.CalibrationUnstable;
            if (finish.aux != aux.? or finish.ticks <= start.ticks or finish.ns <= start.ns)
                return error.CalibrationUnstable;
            sample.* = .{
                .start_ticks = start.ticks,
                .finish_ticks = finish.ticks,
                .start_ns = start.ns,
                .finish_ns = finish.ns,
            };
        }
        const exact_reference = if (self.capability.frequency_source == .cpuid_leaf_15)
            self.capability.frequency_hz
        else
            null;
        const estimate = qualifyCounterSamples(
            samples[0..self.options.calibration_samples],
            exact_reference,
            self.options.max_error_ppm,
        ) catch return error.CalibrationUnstable;
        const frequency = estimate.hz;
        const maximum_error = estimate.maximum_error_ppm;

        try validateCrossCore(frequency, self.options.max_error_ppm, self.io);

        const monotonic = captureMonotonic(self.source, self.io) orelse return error.CalibrationUnstable;
        const real = captureReal(self.source, self.io) orelse return error.CalibrationUnstable;
        if (monotonic.aux != real.aux) return error.CalibrationUnstable;
        const multiplier = multiplierQ32(frequency) orelse return error.CalibrationUnstable;
        const validity_ticks = estimateTicks(frequency, self.options.refresh_ns) orelse
            return error.CalibrationUnstable;
        return .{
            .real_anchor_ticks = real.ticks,
            .real_anchor_ns = real.ns,
            .monotonic_anchor_ticks = monotonic.ticks,
            .monotonic_anchor_ns = monotonic.ns,
            .deadline_ticks = @max(real.ticks, monotonic.ticks) +| validity_ticks,
            .multiplier_q32 = multiplier,
            .frequency_hz = frequency,
            .expected_aux = real.aux,
            .error_ppm = maximum_error,
        };
    }
};

const CapabilityCache = struct {
    var state: std.atomic.Value(u8) = .init(0); // 0 empty, 1 probing, 2 ready
    var value: Capability = .{};
};

fn allocateInstanceCookie(counter: *std.atomic.Value(u64)) error{InstanceCookieExhausted}!u64 {
    var candidate = counter.load(.monotonic);
    while (true) {
        if (candidate == 0 or candidate == std.math.maxInt(u64))
            return error.InstanceCookieExhausted;
        candidate = counter.cmpxchgWeak(
            candidate,
            candidate + 1,
            .monotonic,
            .monotonic,
        ) orelse return candidate;
    }
}

pub const QualifiedTscClock = TscClock;

pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*TscClock {
    return TscClock.create(allocator, io, options);
}

pub fn probeCapabilities(options: Options) Capability {
    _ = options;
    if (CapabilityCache.state.load(.acquire) == 2) return CapabilityCache.value;
    if (CapabilityCache.state.cmpxchgStrong(0, 1, .acquire, .monotonic) == null) {
        CapabilityCache.value = probeCapabilitiesUncached();
        CapabilityCache.state.store(2, .release);
        return CapabilityCache.value;
    }
    while (CapabilityCache.state.load(.acquire) != 2) std.atomic.spinLoopHint();
    return CapabilityCache.value;
}

fn probeCapabilitiesUncached() Capability {
    if (comptime !supported) return .{};
    const basic = cpuid(0, 0);
    const leaf1 = cpuid(1, 0);
    const extended = cpuid(0x80000000, 0);
    var result: Capability = .{
        .has_tsc = leaf1.edx & (@as(u32, 1) << 4) != 0,
        .hypervisor = leaf1.ecx & (@as(u32, 1) << 31) != 0,
    };
    if (extended.eax >= 0x80000001) {
        result.has_rdtscp = cpuid(0x80000001, 0).edx & (@as(u32, 1) << 27) != 0;
    }
    if (extended.eax >= 0x80000007) {
        result.invariant_tsc = cpuid(0x80000007, 0).edx & (@as(u32, 1) << 8) != 0;
    }
    if (basic.eax >= 0x15) {
        const frequency = cpuid(0x15, 0);
        if (frequency.eax != 0 and frequency.ebx != 0 and frequency.ecx != 0) {
            const hz = (@as(u128, frequency.ecx) * frequency.ebx) / frequency.eax;
            if (hz <= std.math.maxInt(u64)) {
                result.frequency_source = .cpuid_leaf_15;
                result.frequency_hz = @intCast(hz);
            }
        }
    }
    if (result.frequency_hz == 0 and basic.eax >= 0x16) {
        const frequency = cpuid(0x16, 0);
        if (frequency.eax != 0) {
            result.frequency_source = .cpuid_leaf_16;
            result.frequency_hz = @as(u64, frequency.eax) * std.time.ns_per_ms;
        }
    }
    return result;
}

fn capabilityRejection(capability: Capability, options: Options) ?Status {
    if (!capability.platform_supported) return .unsupported_platform;
    if (!capability.has_tsc) return .tsc_unavailable;
    if (!capability.has_rdtscp) return .rdtscp_unavailable;
    if (options.require_invariant and !capability.invariant_tsc) return .invariant_required;
    if (!options.allow_hypervisor and capability.hypervisor) return .hypervisor_disallowed;
    if (capability.frequency_hz == 0) return .frequency_unavailable;
    return null;
}

fn validOptions(options: Options) bool {
    return options.calibration_samples >= 3 and
        options.calibration_samples <= max_samples and
        options.calibration_samples & 1 == 1 and
        options.interval_ns != 0 and
        options.refresh_ns > options.interval_ns and
        options.max_error_ppm != 0;
}

const Cpuid = struct { eax: u32, ebx: u32, ecx: u32, edx: u32 };

fn cpuid(leaf: u32, subleaf: u32) Cpuid {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
        : .{ .memory = true });
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

fn readTsc() ?TscReading {
    if (comptime !supported) return null;
    var low: u32 = undefined;
    var high: u32 = undefined;
    var aux: u32 = undefined;
    asm volatile (
        \\lfence
        \\rdtscp
        \\lfence
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
          [aux] "={ecx}" (aux),
        :
        : .{ .memory = true });
    return .{ .ticks = (@as(u64, high) << 32) | low, .aux = aux };
}

const MonotonicCapture = struct { ticks: u64, ns: u64, aux: u32 };
const RealCapture = struct { ticks: u64, ns: i64, aux: u32 };

fn captureMonotonic(source: TimeSource, io: std.Io) ?MonotonicCapture {
    const before = readTsc() orelse return null;
    const ns = source.monotonic(io);
    const after = readTsc() orelse return null;
    if (before.aux != after.aux or after.ticks < before.ticks) return null;
    return .{ .ticks = before.ticks + (after.ticks - before.ticks) / 2, .ns = ns, .aux = before.aux };
}

fn captureReal(source: TimeSource, io: std.Io) ?RealCapture {
    const before = readTsc() orelse return null;
    const ns = source.real(io);
    const after = readTsc() orelse return null;
    if (before.aux != after.aux or after.ticks < before.ticks) return null;
    return .{ .ticks = before.ticks + (after.ticks - before.ticks) / 2, .ns = ns, .aux = before.aux };
}

fn readingRejection(reading: TscReading, calibration: Calibration) ?Status {
    if (reading.aux != calibration.expected_aux) return .migration_detected;
    if (reading.ticks > calibration.deadline_ticks) return .stale;
    return null;
}

const CrossCoreProbe = struct {
    cpu: usize,
    ready: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),
    request: std.atomic.Value(u32) = .init(0),
    response: std.atomic.Value(u32) = .init(0),
    ticks: std.atomic.Value(u64) = .init(0),
    aux: std.atomic.Value(u32) = .init(0),
    stop: std.atomic.Value(bool) = .init(false),

    fn run(self: *CrossCoreProbe) void {
        var affinity: std.os.linux.cpu_set_t = @splat(0);
        setCpu(&affinity, self.cpu);
        std.os.linux.sched_setaffinity(0, &affinity) catch {
            self.failed.store(true, .release);
            self.ready.store(true, .release);
            return;
        };
        self.ready.store(true, .release);
        var previous: u32 = 0;
        while (!self.stop.load(.acquire)) {
            const request = self.request.load(.acquire);
            if (request == previous) {
                std.atomic.spinLoopHint();
                continue;
            }
            previous = request;
            const reading = readTsc() orelse {
                self.failed.store(true, .release);
                return;
            };
            self.ticks.store(reading.ticks, .monotonic);
            self.aux.store(reading.aux, .monotonic);
            self.response.store(request, .release);
        }
    }
};

fn validateCrossCore(frequency_hz: u64, max_error_ppm: u32, io: std.Io) !void {
    // A single allowed CPU needs no cross-core proof. With two or more, pin
    // only this thread and a short-lived probe thread, then restore this
    // thread's exact prior affinity mask before returning.
    if (comptime !supported) return error.CrossCoreUnsynchronized;
    const original = std.posix.sched_getaffinity(0) catch return error.CrossCoreUnsynchronized;
    const cpus = firstTwoCpus(original) orelse return;
    if (comptime builtin.single_threaded) return error.CrossCoreUnsynchronized;
    var local_affinity: std.os.linux.cpu_set_t = @splat(0);
    setCpu(&local_affinity, cpus[0]);
    std.os.linux.sched_setaffinity(0, &local_affinity) catch return error.CrossCoreUnsynchronized;
    var restored = false;
    defer if (!restored) std.os.linux.sched_setaffinity(0, &original) catch {};

    var probe: CrossCoreProbe = .{ .cpu = cpus[1] };
    const thread = std.Thread.spawn(.{}, CrossCoreProbe.run, .{&probe}) catch
        return error.CrossCoreUnsynchronized;
    defer {
        probe.stop.store(true, .release);
        thread.join();
    }

    const ready_deadline = NativeClock.monotonicNow(io) +| 100 * std.time.ns_per_ms;
    while (!probe.ready.load(.acquire)) {
        if (NativeClock.monotonicNow(io) >= ready_deadline) return error.CrossCoreUnsynchronized;
        std.atomic.spinLoopHint();
    }
    if (probe.failed.load(.acquire)) return error.CrossCoreUnsynchronized;

    var best_round_trip: u64 = std.math.maxInt(u64);
    var best_outside: u64 = std.math.maxInt(u64);
    var expected_local_aux: ?u32 = null;
    var expected_remote_aux: ?u32 = null;
    for (1..17) |sequence| {
        const before = readTsc() orelse return error.CrossCoreUnsynchronized;
        if (expected_local_aux) |aux| {
            if (before.aux != aux) return error.CrossCoreUnsynchronized;
        } else expected_local_aux = before.aux;
        probe.request.store(@intCast(sequence), .release);
        const response_deadline = NativeClock.monotonicNow(io) +| 100 * std.time.ns_per_ms;
        while (probe.response.load(.acquire) != sequence) {
            if (probe.failed.load(.acquire) or NativeClock.monotonicNow(io) >= response_deadline)
                return error.CrossCoreUnsynchronized;
            std.atomic.spinLoopHint();
        }
        const after = readTsc() orelse return error.CrossCoreUnsynchronized;
        if (after.aux != expected_local_aux.? or after.ticks < before.ticks)
            return error.CrossCoreUnsynchronized;
        const remote_aux = probe.aux.load(.monotonic);
        if (expected_remote_aux) |aux| {
            if (remote_aux != aux) return error.CrossCoreUnsynchronized;
        } else expected_remote_aux = remote_aux;
        const remote = probe.ticks.load(.monotonic);
        const outside = if (remote < before.ticks)
            before.ticks - remote
        else if (remote > after.ticks)
            remote - after.ticks
        else
            0;
        const round_trip = after.ticks - before.ticks;
        if (round_trip < best_round_trip) {
            best_round_trip = round_trip;
            best_outside = outside;
        }
    }

    // Permit only the calibration's ppm error budget outside the tightest
    // request/response bracket. This detects grossly offset per-core counters
    // without pretending the handshake has zero scheduling uncertainty.
    const tolerance = @as(u64, @intCast((@as(u128, best_round_trip) * max_error_ppm) / 1_000_000));
    if (best_outside > tolerance or expected_local_aux == expected_remote_aux)
        return error.CrossCoreUnsynchronized;

    // Also reject nonsensical handshakes whose best round-trip exceeds the
    // configured one millisecond calibration scale by a wide margin.
    const maximum_round_trip = estimateTicks(frequency_hz, 100 * std.time.ns_per_ms) orelse
        return error.CrossCoreUnsynchronized;
    if (best_round_trip > maximum_round_trip) return error.CrossCoreUnsynchronized;

    std.os.linux.sched_setaffinity(0, &original) catch return error.CrossCoreUnsynchronized;
    restored = true;
}

fn firstTwoCpus(affinity: std.os.linux.cpu_set_t) ?[2]usize {
    var result: [2]usize = undefined;
    var count: usize = 0;
    for (0..@sizeOf(std.os.linux.cpu_set_t) * 8) |cpu| {
        if (!hasCpu(affinity, cpu)) continue;
        if (count < result.len) result[count] = cpu;
        count += 1;
        if (count == result.len) return result;
    }
    return null;
}

fn hasCpu(affinity: std.os.linux.cpu_set_t, cpu: usize) bool {
    const bits = @bitSizeOf(usize);
    return affinity[cpu / bits] & (@as(usize, 1) << @intCast(cpu % bits)) != 0;
}

fn setCpu(affinity: *std.os.linux.cpu_set_t, cpu: usize) void {
    const bits = @bitSizeOf(usize);
    affinity[cpu / bits] |= @as(usize, 1) << @intCast(cpu % bits);
}

test "migration stale and drift predicates reject unsafe mappings" {
    const calibration: Calibration = .{
        .real_anchor_ticks = 100,
        .real_anchor_ns = 1_000,
        .monotonic_anchor_ticks = 100,
        .monotonic_anchor_ns = 1_000,
        .deadline_ticks = 200,
        .multiplier_q32 = 1,
        .frequency_hz = 1,
        .expected_aux = 7,
        .error_ppm = 0,
    };
    try std.testing.expectEqual(Status.migration_detected, readingRejection(.{ .ticks = 150, .aux = 8 }, calibration).?);
    try std.testing.expectEqual(Status.stale, readingRejection(.{ .ticks = 201, .aux = 7 }, calibration).?);
    try std.testing.expect(readingRejection(.{ .ticks = 200, .aux = 7 }, calibration) == null);
    try std.testing.expect(!driftExceeded(1_000_000, 1_000_500, 1_000));
    try std.testing.expect(driftExceeded(1_000_000, 1_010_000, 1_000));
}

test "invalid options and rejected capabilities remain explicit" {
    try std.testing.expect(!validOptions(.{ .calibration_samples = 2 }));
    try std.testing.expectEqual(Status.unsupported_platform, capabilityRejection(.{ .platform_supported = false }, .{}).?);
    try std.testing.expectEqual(Status.rdtscp_unavailable, capabilityRejection(.{ .platform_supported = true, .has_tsc = true }, .{}).?);
    try std.testing.expectEqual(Status.hypervisor_disallowed, capabilityRejection(.{
        .platform_supported = true,
        .has_tsc = true,
        .has_rdtscp = true,
        .invariant_tsc = true,
        .hypervisor = true,
        .frequency_source = .cpuid_leaf_16,
        .frequency_hz = 1,
    }, .{}).?);
}

test "native wall fallback preserves backward wall-clock adjustments" {
    const Fake = struct {
        wall: [2]i64 = .{ 100, 50 },
        wall_index: usize = 0,

        fn real(context: ?*anyopaque, _: std.Io) i64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            defer self.wall_index += 1;
            return self.wall[@min(self.wall_index, self.wall.len - 1)];
        }

        fn monotonic(_: ?*anyopaque, _: std.Io) u64 {
            return 1;
        }
    };
    var fake: Fake = .{};
    var clock = try TscClock.createWithSource(std.testing.allocator, std.testing.io, .{
        .calibration_samples = 2,
    }, .{
        .context = &fake,
        .real_now = Fake.real,
        .monotonic_now = Fake.monotonic,
    });
    defer clock.destroy();
    try std.testing.expectEqual(@as(i64, 100), clock.realNow(std.testing.io));
    try std.testing.expectEqual(@as(i64, 50), clock.realNow(std.testing.io));
}

test "instance cookies are unique nonzero and fail before wrap" {
    var counter: std.atomic.Value(u64) = .init(1);
    try std.testing.expectEqual(@as(u64, 1), try allocateInstanceCookie(&counter));
    try std.testing.expectEqual(@as(u64, 2), try allocateInstanceCookie(&counter));
    counter.store(std.math.maxInt(u64), .monotonic);
    try std.testing.expectError(error.InstanceCookieExhausted, allocateInstanceCookie(&counter));
    counter.store(0, .monotonic);
    try std.testing.expectError(error.InstanceCookieExhausted, allocateInstanceCookie(&counter));
}

test "TLS cache keys generation together with instance cookie" {
    const patterned = struct {
        fn calibration(value: u64, wall: i64) Calibration {
            return .{
                .real_anchor_ticks = value,
                .real_anchor_ns = wall,
                .monotonic_anchor_ticks = value,
                .monotonic_anchor_ns = value,
                .deadline_ticks = value,
                .multiplier_q32 = value,
                .frequency_hz = value,
                .expected_aux = @intCast(value),
                .error_ppm = @intCast(value),
            };
        }
    }.calibration;

    var clock: TscClock = .{
        .allocator = std.testing.allocator,
        .instance_cookie = 10_001,
        .io = std.testing.io,
        .source = .{},
        .options = .{},
        .capability = .{},
        .last_monotonic_ns = .init(0),
    };
    clock.status_value.store(.qualified, .release);
    ThreadCache.calibration = .{};

    clock.publish(patterned(1, 100));
    const first = clock.hotCalibration().?;
    try std.testing.expectEqual(@as(u64, 1), first.frequency_hz);
    try std.testing.expectEqual(@as(i64, 100), first.real_anchor_ns);
    try std.testing.expectEqual(clock.instance_cookie, ThreadCache.calibration.instance_cookie);
    try std.testing.expectEqual(@as(u64, 1), ThreadCache.calibration.generation);

    // Model allocator address reuse: the new instance has the same storage and
    // generation number, but a different cookie and calibration.
    clock.instance_cookie = 10_002;
    clock.slots = .{ .{}, .{} };
    clock.generation.store(0, .seq_cst);
    clock.publish(patterned(2, -50));
    const reused = clock.hotCalibration().?;
    try std.testing.expectEqual(@as(u64, 2), reused.frequency_hz);
    try std.testing.expectEqual(@as(i64, -50), reused.real_anchor_ns);
    try std.testing.expectEqual(clock.instance_cookie, ThreadCache.calibration.instance_cookie);
    try std.testing.expectEqual(@as(u64, 1), ThreadCache.calibration.generation);

    clock.publish(patterned(3, -75));
    const refreshed = clock.hotCalibration().?;
    try std.testing.expectEqual(@as(u64, 3), refreshed.frequency_hz);
    try std.testing.expectEqual(@as(i64, -75), refreshed.real_anchor_ns);
    try std.testing.expectEqual(@as(u64, 2), ThreadCache.calibration.generation);
}

test "reused calibration slots never expose mixed generations" {
    const Context = struct {
        clock: *TscClock,
        done: std.atomic.Value(bool) = .init(false),

        fn writer(self: *@This()) void {
            for (1..100_001) |index| {
                const value: u64 = @intCast(index);
                self.clock.publish(.{
                    .real_anchor_ticks = value,
                    .real_anchor_ns = @intCast(value),
                    .monotonic_anchor_ticks = value,
                    .monotonic_anchor_ns = value,
                    .deadline_ticks = value,
                    .multiplier_q32 = value,
                    .frequency_hz = value,
                    .expected_aux = @intCast(value),
                    .error_ppm = @intCast(value),
                });
                if (index % 1_000 == 0) std.Thread.yield() catch {};
            }
            self.done.store(true, .release);
        }

        fn expectConsistent(value: Calibration) !void {
            const expected = value.real_anchor_ticks;
            try std.testing.expectEqual(@as(i64, @intCast(expected)), value.real_anchor_ns);
            try std.testing.expectEqual(expected, value.monotonic_anchor_ticks);
            try std.testing.expectEqual(expected, value.monotonic_anchor_ns);
            try std.testing.expectEqual(expected, value.deadline_ticks);
            try std.testing.expectEqual(expected, value.multiplier_q32);
            try std.testing.expectEqual(expected, value.frequency_hz);
            try std.testing.expectEqual(@as(u32, @intCast(expected)), value.expected_aux);
            try std.testing.expectEqual(@as(u32, @intCast(expected)), value.error_ppm);
        }
    };
    var clock: TscClock = .{
        .allocator = std.testing.allocator,
        .instance_cookie = 20_001,
        .io = std.testing.io,
        .source = .{},
        .options = .{},
        .capability = .{},
        .last_monotonic_ns = .init(0),
    };
    clock.status_value.store(.qualified, .release);
    ThreadCache.calibration = .{};
    var context: Context = .{ .clock = &clock };
    const thread = try std.Thread.spawn(.{}, Context.writer, .{&context});
    defer thread.join();
    var observations: usize = 0;
    while (!context.done.load(.acquire)) {
        const value = clock.loadCalibration() orelse continue;
        try Context.expectConsistent(value);
        const cached = clock.hotCalibration() orelse continue;
        try Context.expectConsistent(cached);
        try std.testing.expectEqual(clock.instance_cookie, ThreadCache.calibration.instance_cookie);
        try std.testing.expectEqual(
            ThreadCache.calibration.generation,
            ThreadCache.calibration.calibration.real_anchor_ticks,
        );
        observations += 1;
    }
    try Context.expectConsistent(clock.loadCalibration().?);
    try std.testing.expect(observations != 0);
}
