# Impact of logging on application work

`bench/application.zig` uses the public kron API to run identical application
computation with no logger, shared Memory, SPSC Memory, shared Mmap, and SPSC
Mmap. Complete timing includes producer tasks, final written flush, shutdown, and
Runtime/FileSink cleanup; logging initialization and application data preparation
are reported separately. The application working set and sample storage are part
of the benchmark; final report/sorting and benchmark storage release are outside
the complete-log completion interval.

This is two explicit synthetic request models: `compute` processes 2 KiB per
thread and performs 64 dependent integer mix/state updates; `cache` processes
1 MiB per thread and performs 32 data-dependent position updates. Request results
update the working set, and all results are combined into per-thread sum/xor
checksums so the no-logger path cannot be optimized away. An independent Python
model computes expected results from the same request IDs and state transitions
and verifies every actual logged result. These models simulate computation and
cache access; they do not represent a real business service or cold-cache
qualification.

| Option | Scope |
| --- | --- |
| `--mode=none/shared/spsc` | No logging, ordinary shared async, per-thread SPSC |
| `--storage=memory/mmap` | Queue storage for enabled logging; no-logger reports none |
| `--work=compute/cache` | Small working-set computation or 1 MiB per-thread data-dependent updates |
| `--operations=N` | Total requests across all threads, 1..1000000, at least the producer count |
| `--producers=1/4/16` | Application thread count; reported separately from CPU mask size |
| `--every=N` | Emit one log every N global request IDs, 1..1024 |
| `--sampled=true/false` | Per-operation (computation + optional logging) quantiles or batch timing |
| `--warmup=N` | Total 0..10000 warmup requests; application state resets before timing |
| `--output=PATH` | Real complete JSON file; no-logger mode does not create it |

Each log contains the complete system time and correlation metadata plus
request_id/result/producer/rounds/warmup fields. Memory does not recover pending
records, while Mmap has the original process recovery protocol; the two are always
reported separately. No-logger mode does not call the logger or acquire event
time but keeps all application-state computation. This baseline measures the cost
of disabling logging; no-logger timing is not presented as logger producer
latency.

Formal runs fix 256 slots, 512-byte records, a 64 KiB file buffer, a sleeping
worker, block overload policy, and the default four service quanta; all
logger/sink objects use a failing allocator after initialization to prove no new
Runtime allocation during the run. Application working-set/sample storage and
`std.Io`/thread hosts are independent benchmark resources, so whole-process zero
allocation is not claimed. Each measurement uses a new path and verifies warmup
and normal events, results, duplicate/missing records, per-channel sequence, and
actual SPSC attachment identity before deleting artifacts.

Log frequency uses global request_id modulo N, with request IDs interleaved across
producers. Sparse `every=16` with P4/P16 concentrates requests on producer 0;
this represents a sparse, concentrated log source, not uniform per-thread
logging. `every=1` covers every producer's logs. The default driver selects CPU
mask 0/2/4/6/8/10 across six physical cores, and P16 oversubscribes; affinity does
not reserve CPUs or mask host load.

```sh
zig build bench-application -Doptimize=ReleaseFast -- --output=.zig-cache/application.log --mode=shared --storage=memory --work=cache --producers=4 --every=16
zig build test-application-bench -Doptimize=ReleaseSafe -j1
python3 bench/application_compare.py --binary /path/to/kron-application-bench --output /path/to/fresh-capture --pmu
```

The driver defaults to two models, P1/P4/P16, every1/16, and five repetitions of
five modes, for 300 batch trials. `--smoke` runs 15 small real scenarios,
including sampled and P16, with correctness conclusions only. PMU measures
whole-child-process user instructions/cycles/cache-misses and context-switches/
task-clock, including initialization, preparation, and report output while
excluding kernel hardware events; its scope differs from complete timing. Each
count retains coverage, unsupported/uncounted cache events are explicitly
unavailable, and counts below 90% coverage do not qualify as stable differences.

Application throughput, stage time, CPU, and similar metrics are reported as
median/CV/spread/bootstrap intervals across five child-process results, with all
slow values retained. Common computation checksums for no-logger and logging
groups must match. Noise above 10% or overlapping intervals makes a comparison
inconclusive. A single local difference does not replace an "industry best"
conclusion across all workloads.

The first formal 300 trials completed, verifying 3.6 million requests and 1.65756
million logs; all application throughput comparisons remained inconclusive.
Hardware-count coverage was at least 91%, and some instructions/task-clock
differences had local qualification. Current real services still need to
establish their own baselines from their workloads and logging policies.
