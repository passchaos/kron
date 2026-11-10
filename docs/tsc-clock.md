# Qualified TSC clock

`src/platform/tsc_clock.zig` is an optional x86_64 Linux clock provider. Pure
calibration math and counter-sample qualification live in
`src/platform/tsc_math.zig`; the clock state, cross-core probe and fallback
machine stay in `tsc_clock.zig`. The clock is not selected automatically and is
not part of the default runtime clock path.
An application creates and qualifies an instance before attaching the logger,
keeps it alive while callbacks can run, and arranges explicit background
refreshes.

```zig
var tsc = try TscClock.create(allocator, io, .{});
defer tsc.destroy();

const clock = tsc.clock();
// Pass `clock` through the existing explicit clock injection point.
```

For multiple producer threads, use a separate instance per producer and
`runtime.attachThreadWithInstanceClock(tsc.clock(), .{ .scope = "worker" })`.
Each instance must remain alive until its attached logger is detached. A
runtime-wide instance is suitable only when its calibrated AUX/owner contract
matches the actual producer; sharing it does not qualify multiple CPUs.

The public surface is:

```zig
pub fn TscClock.create(allocator, io, Options) !*TscClock;
pub fn TscClock.destroy(*TscClock) void;
pub fn TscClock.clock(*TscClock) Clock;
pub fn TscClock.realNow(*TscClock, io) i64;
pub fn TscClock.monotonicNow(*TscClock, io) u64;
pub fn TscClock.refresh(*TscClock) !void;
pub fn TscClock.status(*const TscClock) Status;
pub fn TscClock.stats(*const TscClock) Stats;
pub fn probeCapabilities(Options) Capability;
```

Default options use seven one-millisecond samples, a 2,000 ppm error limit,
and a five-second mapping lifetime. The sample count must be odd and between 3
and 31. `refresh_ns` must be greater than `interval_ns`.

## Qualification

Qualification rejects rather than guesses. All of the following must hold:

- target is x86_64 Linux;
- CPUID reports TSC and RDTSCP;
- CPUID `0x80000007` reports invariant TSC when `require_invariant` is true;
- a hypervisor is absent unless `allow_hypervisor` is explicitly enabled;
- CPUID leaf `0x15`, or leaf `0x16` as a nominal fallback, supplies a frequency;
- the median measured frequency is stable within `max_error_ppm`;
- an exact leaf `0x15` frequency agrees with measured frequency within the same
  limit;
- RDTSCP AUX is unchanged across each sample;
- when at least two CPUs are allowed, a short-lived thread is pinned to a
  second CPU while the creating thread is temporarily pinned to the first.
  Sixteen request/response brackets must establish compatible counters and
  stable, distinct AUX values. The original affinity mask is restored before
  qualification returns.

CPUID results are process-cached. CPUID and the pinned cross-core handshake are
qualification-only operations and are not part of the producer hot path.

Leaf `0x16` is a nominal processor frequency, so it is recorded as capability
evidence but is not treated as an exact reference. The measured median remains
the conversion frequency. Leaf `0x15`, when complete, is treated as the exact
crystal/numerator/denominator reference.

Failure to qualify still returns an allocated clock instance. `status()` and
`stats()` explain the rejection, while reads delegate to `NativeClock`. The
clock never substitutes zero, fabricated wall time, or raw TSC ticks for UTC
nanoseconds.

## Hot path and refresh

Qualified reads execute fenced `RDTSCP` (`lfence; rdtscp; lfence`) with a
compiler memory clobber, validate TSC_AUX and the tick deadline, then apply a
Q32 fixed-point ticks-to-nanoseconds conversion. They do not perform a system
call. A changed AUX, expired deadline, negative tick delta, conversion overflow,
or invalid snapshot changes status and immediately uses `NativeClock`.

Calibration records separate real-time and awake-clock anchors. Event values
remain converted UTC nanoseconds, so the existing wire format does not need to
store raw ticks.

The two clock domains deliberately have different jump policies:

- `monotonicNow` is atomically clamped against its previous result and cannot
  move backward when switching between TSC and native providers;
- `realNow` preserves wall-clock semantics. Native fallback returns the real
  native value, and a refreshed anchor reflects NTP or administrative wall
  adjustments, including backward adjustments. Wall time is not silently
  converted into a monotonic clock.

`refresh()` is explicit and should run in application-owned background/control
work before the current `refresh_ns` expires. It obtains new real and monotonic
anchors, repeats frequency and cross-core qualification, and rejects excessive
monotonic drift. Wall-clock adjustments such as NTP are incorporated only at a
refresh boundary; no per-record wall-clock syscall is hidden in the qualified
path.

Calibration publication uses two slots with a per-slot sequence and SeqCst
atomic fields. A writer marks the reused slot odd, stores a complete
calibration, marks it even, then publishes its generation. Readers verify both
the slot sequence and the global generation. A stress test repeatedly reuses
both slots while another thread reads and rejects every mixed-generation
snapshot. This remains data-race-free when an explicitly shared `Clock`
callback overlaps refresh.

Each OS thread also has a one-entry calibration cache. Every clock instance is
assigned a process-unique, nonzero 64-bit cookie at creation; cookie allocation
fails before wraparound. A cache hit requires both that cookie and the currently
published generation. It can therefore use a plain thread-local copy of the
immutable calibration rather than reload ten SeqCst fields on every timestamp.
A miss loads `{ generation, calibration }` as one validated snapshot before
filling the cache. Pairing those values is required: separately loading a new
calibration and an old generation during publication would make a stale cache
entry appear valid. The cookie also prevents an allocator reusing an instance
address from inheriting the destroyed instance's TLS entry.

The cache is per-thread metadata only. It does not share qualification across
threads, bypass TSC_AUX checks, extend the tick deadline, or weaken any CPUID,
cross-core, drift, or fallback rule.

The intended producer configuration is nevertheless single-owner: create the
instance on the producer thread before attaching the logger, and use that
instance from that thread. Calling it from a thread or migrated CPU with a
different AUX invalidates qualification and uses native fallback until an
explicit refresh binds a new anchor. A shared callback is memory-safe, not a
promise that one calibrated AUX can serve arbitrary producer threads.

Destroying an instance while any callback can still execute is invalid. The
owner must stop or detach all loggers first.

## Verification and limits

Run the self-contained tests without changing the package root or build graph:

```sh
zig test src/platform/tsc_clock.zig
zig test --dep tsc \
  -Mroot=tests/tsc_qualification.zig \
  -Mtsc=src/platform/tsc_clock.zig
```

On the 2026-10-31 development host, the actual probe reported invariant TSC,
no hypervisor, a leaf `0x15` frequency of approximately 2.9952 GHz, a measured
frequency of approximately 2.995 GHz, and 43–288 ppm maximum sample deviation
across the recorded qualification runs.
The qualification, cross-core handshake, stale fallback, and explicit refresh
tests passed in Debug, ReleaseSafe, and ReleaseFast configurations.

Those figures are qualification evidence, not a latency benchmark. This module
makes no “few nanoseconds” promise. In addition to RDTSCP and conversion, the
cache-hit hot path performs atomic status and generation loads, a statistics
`fetchAdd`, and a monotonic CAS for monotonic reads. Producer cost, cache
effects, CPU topology, and the callback layer must be measured by the separate
clock-selection benchmark on each deployment target. Virtual machines remain
unqualified by default because invariant and synchronized virtual TSC behavior
is a hypervisor contract, not something CPUID presence alone proves.

`zig build bench-tsc -Doptimize=ReleaseFast` performs a separate clock-only
comparison and reports how many reads were qualified versus fallback. A recorded
host observation qualified all 100000 TSC reads but measured about 34.52 ns/call
versus 18.35 ns NativeClock before the TLS metadata cache. Three bounded qualified runs after
the cache measured 22.02–23.45 ns/call for TSC and 15.30–16.24 ns/call for
NativeClock, with zero fallback reads. The repeated metadata load was reduced,
but TSC still did not win this host comparison; its purpose is an explicit,
checked clock choice, not automatic performance promotion.
