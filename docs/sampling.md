# Global sampling semantics and performance

Each route in `Logging.outputs` has an independent sampler, and even identical
sampling configurations do not share quotas; all producers share the quota of
their route. Lazy fields are not constructed when every output rejects by
filtering/sampling. The global/override description below applies to multiple
routes inside one advanced Runtime pipeline.

Sampling belongs to an immutable configuration generation. Default Runtime
sampling state is shared by all routes inheriting the default and all producers;
a route with explicit sampling gets independent state, but its quota is still
shared by all producers rather than one copy per thread. Shared async and SPSC
use the same semantics.

| Configuration | Decision |
| --- | --- |
| `.none` | Accept everything |
| `.count=N` | Accept the first N sampling calls globally; saturates at zero budget |
| `.every=N` | Accept calls 1, N+1, 2N+1, ... in global atomic order; N must be nonzero |
| `.token_bucket` | Fixed capacity, continuously refill one token per interval, using an explicit monotonic time |

Runtime performs scope/level filtering first, then sampling. The default
`sample_bypass = .warn` bypasses sampling at warn and above; predicates, field
capture, and I/O happen afterward, so a call that passes sampling may still fail
to write because of a predicate or capture error. The sampling budget counts calls
entering this stage and does not guarantee an equal number of written records.

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .submission = .asynchronous,
    .memory_queue = .{ .capacity = 256, .max_record_bytes = 8192 },
    .sampling = .{ .every = 2 },
    .sample_bypass = .warn,
    .routes = routes,
});
```

route_mask is determined from each route's sampling before capture, and fields
are constructed only if at least one route passes; output and recovery do not
re-sample. An explicit route `.sampling = .none` can keep accepting after the
default sampling budget is exhausted, and sample_bypass follows that route's
setting.

Filter-only `reloadFilter` and `setLevelChecked` preserve sampling state; a
complete configuration replacement creates a new sampler starting from its
initial budget/phase. Old admissions and accepted records continue under the old
configuration. count/token bucket use CAS to prevent duplicate consumption
instead of an approximate `fetchSub` that could underflow.

## Dedicated every=1/2 path

`every=1` returns true directly with state 0 and no RMW. `every=2` uses atomic
XOR and reads the old value's lowest bit, so state is always 0 or 1; modification
order is the global alternation order. Other N values still use the original
bounded modulo-N CAS, and phase is not converted into a wrapping ticket. Sampler
size/alignment and configuration budget are unchanged.

In the current x86_64 ReleaseFast object, `every=2` generates `lock btcq` and
returns the old bit without a CAS retry loop. Using only `fetchXor(...) == 0` can
still generate a CAS loop, so the actual disassembly was archived; compilers on
other platforms may choose different instructions, and source inspection cannot
infer cost on every platform.

Ordering tests verify every1 state 0 and every2 phase at each step; concurrency
tests check exact global counts and final state for count, every1/2/3/8, and
bucket. Runtime tests also verify that filter updates preserve every2 phase and
that complete replacement resets it. They do not infer atomic order from thread
completion order.

## Repeated measurement

`zig build bench-sampling -Doptimize=ReleaseFast -- --producers=4 --attempts=10000 --repetitions=5`
uses a fixed fake time and covers none, every1/2/3/8, count, and bucket. After
each warmup, the sampler is reset while all workers stop at the start gate;
measurement includes wakeup and join and has no per-call clock read. The benchmark
reports sampler cost only, not complete log throughput or p99.

Before/final each ran 105 trials (1/4/16 producers × 7 policies × 5 repetitions),
and all exact acceptance budgets passed; an intermediate candidate with another
105 trials was retained. Raw data, binary SHA-256, source hashes, and disassembly
are no longer tracked.

Median every1 batch time was P1 118,540 → 38,391 ns, P4 377,381 → 73,461 ns, and
P16 485,637 → 268,572 ns. Each policy runs 10,000 calls, and these values include
thread-scheduling overhead. every2 did not show a stable win at P4/P16; some
control policies also varied with the environment and were reported inconclusive
under the 10% noise threshold. The current result confirms reduced per-call atomic
work and preserved semantics, not faster performance for every sampling workload.
