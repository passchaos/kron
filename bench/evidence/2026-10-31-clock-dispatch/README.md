# Clock-only pilot, 2026-10-31

`results.jsonl` contains seven rotating-order repetitions, 100,000 measured reads
per mode, and 10,000 excluded warmup reads per batch. `capture.json` records the
exact command, binary SHA-256, host identity, and generated-code observations.
The dynamic measured loop retained an indirect kron.Clock callback; StandardClock
retained the application's std.Io vtable call. No logger or sink is measured.

| Mode | Median ns/call | Min | Max |
| --- | ---: | ---: | ---: |
| Dynamic std.Io callback | 17.005 | 16.900 | 21.328 |
| Static StandardClock | 16.573 | 16.506 | 21.279 |
| NativeClock | 15.414 | 14.917 | 19.050 |
| ZeroClock loop control | 0.257 | 0.251 | 0.258 |

The dynamic and StandardClock repeated-run ranges overlap substantially. These
measurements do not establish a stable subnanosecond dispatch saving. NativeClock
changes the provider to Linux's vDSO-aware native read and may fall back on a
clock-read failure; its result is not the effect of only removing a callback.
ZeroClock changes timestamp semantics and reports the retained control loop's
cost rather than an event timestamp read. All batches include checksum and
per-call compiler-barrier work.

The host was an unreserved development machine. The measured awake-clock pair
noop p50 was 22 ns; it is reported independently and not subtracted from these
batch averages. This evidence is a bounded attribution pilot, not a controlled
performance baseline or a claim of universal nanosecond improvement.

The separate [SPSC sleep timeout](spsc-sleep-timeout.md) records an incomplete
full-pipeline trial observed during verification with a pre-fix runtime binary.
It is retained as failed liveness evidence and is not counted as a timing result.
