# Application work with no logger and Memory/Mmap

Production source baseline6e774b0. This change adds an application benchmark,
independent result oracle and build gates; production runtime is unchanged.
The public API request/compute path is used, with a same-work no-logger baseline.
See docs/application-benchmark.md for input/scope details and reproduction.

Two deterministic workloads use per-worker mutable tables:compute2KiB/64 mix
rounds and cache1MiB/32 data-dependent updates. Every request contributes to
consumed worker sum/xor digests. A separate Python integer model checks every
worker digest and each logged request/result. Fields and system-time/fullJSON
are not reduced for performance. Same application state is used for every mode.

The15-trial smoke validates1545 requests and480 complete logs, including P4,
P16 and per-operation sampling. The first smoke checked all files successfully
but attempted single-row performance summary; the regression tool rejected it.
Final smoke emits explicit non-performance summaries. Independent oracle tests
reject wrong results, completion/digests, missing/duplicate/partial records,
changed queue/work budgets, invalid channels and no-logger file creation.

The initial PMU capture used an oracle that incorrectly equated SPSC attachment
channel with producer number. Channel allocation depends on actual attach order;
its legitimate permuted channels were rejected. The stopped capture's logs,
raw rows, source snapshot and failed workload remain in
initial-channel-oracle-failure/. The corrected oracle requires a stable bijection
for actual producers with logged events, bounded pool indices and per-channel
sequence ordering. No production change was needed. A fresh complete capture
uses that corrected frozen oracle; incomplete earlier data never qualifies it.

Formal capture is300 trials, P1/P4/P16, every1/16 global request logging, both
workloads and five modes, five repetitions. Application total is producer joins
through final written flush/shutdown/Runtime+FileSink cleanup; init/preparation
remain separate. No-logger creates no output file. Queue/source/digests and
full log contents/hashes are checked per row; successful files alone are removed.
Application working-set/sample allocations are outside runtime's zero-allocation
claim. The failing runtime/sink allocator is disabled immediately after init.

PMU includes whole process init/preparation/reporting, excludes kernel hardware
work, and preserves time coverage. Six-core CPU affinity does not reserve the
host, and P16 is oversubscribed. every16/P4/P16 selects a concentrated producer,
not an evenly distributed sparse logging workload. No strict durable flush,
business-service claim, cold-cache or new cross-library rank is inferred.

Source archives/provenance bind the binary, model and verifier. Final repeated
no-logger comparisons, phase/CPU/coverage/spread/bootstrap and negative data
remain in capture/summary.json and capture/results.jsonl. Final gate/audit
identities are recorded after completion in qualification.json.

## Completed result and gates

All300 trials verify3,600,000 application requests and1,657,560 full logs.
Every worker digest and file result matches the independent state model.
All application throughput comparisons remain inconclusive: this loaded-host
short request workload cannot establish stable service-impact percentages.
Every median/slow value is preserved in comparison.md and capture/summary.json.
User PMU coverage is at least91%; some instructions/task-clock differences are
locally supported and remain separately labelled. Counters include process
initialization and reporting and have a different boundary from application rate.

The15 final smoke scenarios pass; all default per-operation and P16 paths are
exercised. Application module gates pass3 Zig tests and5 Python negative/oracle
tests in Debug/ReleaseSafe/ReleaseFast. Full ReleaseSafe verify-local passes
97/97 steps and559/559 Zig tests, including the new application gate and owning
library/package/recovery tests. Production src is byte-identical to6e774b0.

After capture completed, unavailable-counter summary handling was hardened:
absent coverage remains0/unqualified rather than raising during summary. The
measured archive and capture-time script hash remain unchanged; the current
reporting-only script identity is recorded separately. This branch did not occur
in the captured supported events and does not change any saved distributions.

The default-readiness recommendation is project-specific: fixed Zig0.16/Linux,
bounded Memory+portable file path and explicit error/lifecycle handling. The
benchmark does not establish cross-platform device or stable fastest status.
