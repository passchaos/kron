# Memory/Mmap bounded consumer service budget

Baseline `fd7e3f6`; this experiment focuses on Memory and Mmap storage,
shared async/SPSC separately, P1/P4. Complete-file output, written flush,
shutdown/cleanup, initialization and sampled p50/p99/p99.9 are retained.
Only journal service budget changes; no per-record validation, CRC, schema,
configuration, output barrier or recovery contract is weakened.

## Deterministic service and lifecycle proof

The original fixed four-batch collector serves a busy channel again before
its queued peer. A callback blocks the first one-record batch, then 160
additional busy records and one peer are queued. Before regression expects
peer at position1 but sees161 (`before-fairness.log`). Default4's bound
is retained, and explicit quanta1/2/3/4 give positions1/65/129/161. Tests
cover Memory/Mmap, shared-peer/SPSC-peer, exact per-channel sequence,
162 written records, zero pending and no post-initialization allocation.
This is a record-count service bound, not an OS wall-clock guarantee.

The public `consumer_batches_per_queue` initialization option accepts1..4,
default4. Values0/>4 fail before allocation/file creation. It is a single
owned usize and creates no runtime allocation or publication cache.
Shared and SPSC queues use the same checked-batch loop. Sync validates
the range but has no collector. The option is fixed at creation.

A public test observes the real futex wait of an SPSC producer behind two
uncommitted reservations, then shutdown must wake it. The owner aborts its
reservations, returns rejected_closing and leaves no accepted records, output
or pending slots. Both Memory/Mmap run the same shutdown scenario.

## Initial fixed-one-batch candidate

The first candidate conditionally gave channel registries a one-batch
quantum and was not promoted as default. `before-source.tar.gz` and
`after-source.tar.gz`, `implementation.patch` and provenance files freeze
those before/after sources and executable hashes. 160 trials cover all
8 shared/SPSC x Memory/Mmap x P1/P4 configurations, sampled/batch and five
paired repetitions. Every100k measured +1k warmup file is independently
verified: **16,160,000 physical JSON records**; accepted=written, drop/pending0.
All slow values remain in workflow-results.jsonl/comparison.json.

Every throughput group remains inconclusive. SPSC P4 Memory p99 median
rises9538->79460ns while p99.9 falls369885->107534ns; Mmap p99
rises10531->80957ns while p99.9 falls426859->119463ns. Shorter peer
service gaps shift the wait distribution instead of proving all percentiles
improve. No fixed-one-batch default performance claim is made.

## Same-binary explicit tuning

The final public option retains default4 and supports explicit1.
`configurable-source.tar.gz`/configurable.patch/source-manifest.json freeze
the actual measured implementation; its exact binary hash is recorded.
The 40-trial tuned capture uses **the same executable for both labels**
with --consumer-batches=4 or1. Only SPSC P4 Memory/Mmap, sampled/batch,
five paired repetitions, 100k measured+1k warmup; all **4,040,000 physical
JSON records** independently verified. The reports record the chosen
consumer budget. Final all-quantum regression tests extend the deterministic
proof to2 and3; those tests were added after this performance snapshot,
without changing the production scheduling code.

| Storage | budget4 p99 ns | budget1 p99 ns | budget4 p99.9 ns | budget1 p99.9 ns |
| --- | ---: | ---: | ---: | ---: |
| Memory |10901|82827|377748|114702|
| Mmap |9132|84536|391030|110680|

All these percentiles and throughput are inconclusive under the10%
CV/spread budget; the repeated directions are material tradeoffs and
remain visible. Budget1 batch medians are2.039M/s Memory and2.133M/s
Mmap, versus budget4's2.116M/s and1.990M/s; these medians cannot be
used as stable speedup claims. Default4 stays unchanged.

Both captures retain full system wall clocks, complete JSON, 256slots with
512-byte payloads,64KiB file buffer, CPU0/2/4/6/8/10 affinity and no durable
media synchronization. SPSC has per-producer channels, so total reserved
queue bytes differ from the shared mode and remain in every report.

## Gates

The final configurable Runtime passes ReleaseSafe verify-local **89/89
steps and530/530 tests**, including new SPSC full-wait shutdown, old-version
late corruption/leases, deadline, actual SIGKILL, no allocations and
independent package consumers. Module logs identify the earlier2-value
quantum proof and final all4-value proof separately. Platform object
checks are recorded independently; they do not prove devices ran the code.

Final Foundation/kron comparisons use default4 and separately report
Memory/Mmap; their source snapshot and raw file trials are not inferred
from the local tuning medians.
