# Rejected batched configuration-pin release candidates

Baseline: Git commit `8a351c0`. Two consumer-only pin-release candidates
were explored, each retaining per-record CRC, schema readiness, journal
reclaim and output barriers. Both have been **removed from production**.
The baseline production paths remain; only an expanded old-version
late-corruption regression test is kept.

`before-source.tar.gz` freezes the baseline. `after-source.tar.gz` freezes
the second rejected candidate; `rejected-unified.patch` is its exact patch.
`first-source.tar.gz` was reconstructed from the frozen candidate and
`delivery-batch-first.zig`; every Zig file hash was checked against
`first-provenance.json`. It retains the first candidate's exact source.
`rejected-implementation.patch` is another copy of the unified candidate
patch captured before restoring production. The original
after-provenance/source-manifest describe a
rejected candidate, not the restored final source. No passing current-library
performance claim is based on those files.

## Attempt and result

The first candidate groups already-reclaimed records by config/channel and
releases their record pins in one seq_cst fetchSub per run. Existing
WrittenCounts separately publishes the successful written prefix. The
second combines both into one count to avoid duplicate per-record state
updates. Batch Views outlive all temporary acknowledgements. Deterministic
31-record shared/SPSC tests verify one pin RMW, old leases remain protected,
and channel 0/1/64 concurrently retaining/releasing pins preserves the exact
remaining cache pin. Both candidates pass semantic module tests.

Each candidate completes 100 paired full-file trials, five configurations
(shared Memory P1/P4, SPSC Memory P4, SPSC Mmap P4 and prepared SPSC Mmap
P4) with sampled/batch in separate processes. Every trial independently
checks 100000 measured + 1000 warmup physical JSON records: **10,100,000
records per candidate**. Each additionally completes 20 whole-file PMU
trials (300000+1000) checking **6,020,000 records**. Total exploration
evidence: **240 trials, 32,240,000 physical records**, all accepted=written,
drop/pending=0, exact ID/field/output-byte validation. All slow values remain.

| Candidate | Shared Memory P1 | Shared Memory P4 | SPSC Memory P4 | SPSC Mmap P4 | Prepared SPSC Mmap P4 |
| --- | ---: | ---: | ---: | ---: | ---: |
| separate counters | -6.09% | -10.61% | -13.14% | -0.10% | -3.20% |
| unified counter | -12.47% | -27.49% | -0.92% | -0.04% | -7.71% |

These are batch full-through-close median changes. First-round Mmap
meets the local noise budget with overlapping bootstrap intervals; its
other groups and every unified group are inconclusive. Host variance
is high and these observations alone do not prove an intrinsic regression,
but neither candidate has a verified benefit or meets the promotion
requirements. Keeping baseline is warranted; fewer atomic operations do
not substitute for complete workflow evidence.

`first-results.jsonl`, `first-comparison.json`, `first-pmu/` preserve the first
version; `workflow-results.jsonl`, `comparison.json`, `full-pmu/` preserve
the unified version. System wall clocks, complete JSON, 256-slot/512-byte
queues, 64KiB file buffers and CPU0/2/4/6/8/10 affinity remain fixed.
Throughput includes producer, background output, final written flush,
shutdown and object/file cleanup. Init/preparation and sampled tails are
reported separately; there is no durable media flush.

First-candidate whole-process user PMU instructions are effectively flat
(+0.06% SPSC P4 / +0.09% shared P1), with cycles/throughput negative
medians and noise. Unified instructions are also flat (+0.01%/+0.04%);
cycles median falls 2.32%/3.31% and throughput rises 1.97%/12.22%, but
all these cycle/throughput groups remain inconclusive. No ranking or
speedup is claimed from those conflicting observations.

## Retained regression

`src/core/runtime_delivery_tests.zig` now retires the configuration before
allowing the batch to deliver, covers both shared and SPSC memory storage,
and corrupts the second payload after all three outputs have been flushed.
The first record reclaims; the next reclaim returns CorruptRecord. Written
is exactly 1, journal pending is 2, target covers only the successful prefix,
and the old configuration retains exactly two pins even after SPSC cache
detach. The inspection View is then dropped before collection, which still
cannot release the old version; its ownership callback remains uncalled.
Runtime destruction after failure releases that callback exactly once.
This remains useful
fault evidence on the baseline implementation.

`retained-final-{debug,safe,fast}.log` records final restored-production
batch gates (18 tests, including import fixtures), with the lease callback
and collection checks. Earlier `retained-batch-*` logs predate those lease
checks; candidate `module-*` logs are exploratory evidence.
`retired-lease-safe.log` records an intermediate test failure: its deferred
detach ran after explicit Runtime destruction. The final test conditions
deferred cleanup on the live owner and passes all three optimize modes.

Only the regression test and experiment documentation/evidence are retained
in the final commit. All production `.zig` modules are byte identical to
`8a351c0`, except `src/core/runtime_delivery_tests.zig`; the final evidence
audit hashes those modules. This rejection is a concrete performance
qualification outcome, not a claim that the unfinished library goal is met.
