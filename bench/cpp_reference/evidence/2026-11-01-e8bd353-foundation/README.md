# Current kron vs Foundation Logging + spdlog

Measured kron commit **e8bd353**; Foundation owning repository HEAD
`0d1f5b0c5689a3fdc502b1c4c7ed8496eb1d5a94`. Foundation is the real public
`Logger.Native()` spdlog C++ frontend, compiled with its `cpp/src/logger.cc`
and Rust release core; spdlog1.17.0 include source is pinned by archive hash.
The owning Foundation sources are copied before building and never edited.
This is the combined Foundation pipeline, not standalone spdlog async.

The frozen measured sources, harness/oracle/analyzers and dependencies are
recorded in measured-source.tar.gz, foundation-source.tar.gz, manifest.json
and capture.json. Actual binaries have independent hashes. Runtime production
identity matches the549/549 ReleaseSafe and nine-platform qualification of
the measured commit. No source edits or test/build overlap from this task occur
during the completed performance capture.

## Complete capture and result

**200/200 trials verify20,200,000 physical JSON records**, each100k measured
plus1k warmup, five independent repetitions for every batch/sampled case.
Memory/Mmap, P1/P4 and shared/SPSC are separate, inline and prepared schema
are separate. The whole file is checked after written flush, shutdown and
cleanup; every accepted/written/drop/pending, event ID, complete field, byte
and file hash check passes. Records are discarded only after successful oracle
verification. All slow trials remain in results.jsonl; no outlier is excluded.

Linux x86_64, i9-13900K, NVMe/ext4, Zig0.16 ReleaseFast and Rust/C++ release
(-O3), fixed CPU0/2/4/6/8/10 affinity. One real file, full JSON/system wall clock,
five numeric attributes, block overflow,256 slots and64KiB output buffer.
Kron actually selects portable for all trials. No rotating trigger, compression,
predicate/sampling, nested business payload or durable media flush is requested.
Host load samples are preserved in capture.json; this is a loaded host window.

The plain inline throughput median is higher for kron SPSC in all four groups.
Memory P1/P4 are+8.67%/+3.21%; Mmap P1/P4 are+23.09%/+12.58%. Shared Memory
P4 remains4.41% below Foundation, while shared Mmap P1/P4 are+18.05%/+6.81%.
Every complete-through-close cross-library throughput qualification remains
**inconclusive** because relative spreads exceed10%; only one interval pair
does not overlap, and that pair also fails the repeatability budget.

Prepared schema is slower than inline in this workload and is below Foundation
in most configurations. It has separate registration/preparation and fixed
schema storage; schema cannot be presented as a universally faster default.
The complete median/percentile/stage/ratio and CV/spread/interval reports are
[detailed-comparison.md](detailed-comparison.md) and detailed-analysis.json;
the existing owning analyzer also produces comparison.md/analysis.json.

## Call tails and lifecycle

Ordinary SPSC P4 p99 medians are605ns Memory and663ns Mmap, compared with
Foundation28689ns/7982ns. However its p99.9 medians are345167ns/347492ns,
compared with Foundation36936ns/12750ns. Those per-call percentile comparisons
fail the repeatability budget. They show why a low p99 cannot be used to claim
uniform tail superiority. Calls include backpressure waiting; this experiment
does not measure each record's admission-to-file visibility latency.

Mmap initialization materially affects short program lifecycles. Foundation
P4 init median22.728ms, kron shared inline18.702ms and SPSC inline1248.936ms.
For100k measured+1k warmup records the full lifecycle medians are70.924ms,
71.246ms and1290.771ms respectively. Schema Mmap preparation also has very
slow observations: pre-registration precedes measured producer start and is
reported explicitly. All initialization/preparation tails remain. Stage medians
cannot be added to reconstruct the full-lifecycle median.

Foundation Memory has two very slow through-close samples: P1 shutdown806.442ms
and P4 shutdown233.880ms. They produce close throughput0.117M/0.341M records/s
in those rows and are not removed. The independently reported written-flush
medians are2.205M/2.320M, and through-close medians2.155M/2.317M. Thus the
result preserves both write completion and cleanup boundaries. Mmap P1 also
has a9.388ms shutdown sample. These observations do not establish a cause.

## Resource and semantic comparison

| Queue configuration | P1 configured queue bytes | P4 configured queue bytes |
| --- | ---: | ---: |
| Foundation Memory |131072|131072|
| Foundation Mmap |151552|151552|
| kron shared inline Memory/Mmap |151552|151552|
| kron SPSC inline Memory/Mmap |303104|757760|
| kron shared schema Memory/Mmap |159872|159872|
| kron SPSC schema Memory/Mmap |319744|799360|

Foundation Memory's131072-byte queue limit is not its total allocated memory:
pending/consumer RecordBatch storage and backend/C++ scratch exist too. Mmap
is a single shared256-slot576-byte spool with4096-byte header. Kron reports
queue backing (mapped bytes for Mmap) separately from other runtime metadata,
turn arrays and tracking structures. SPSC includes a main queue and one queue
per producer, so P1/P4 have2/5 queues. These are explicit storage reservations,
not a claim of equal total heap/RSS. Every library uses64KiB file buffering.

Foundation stores producer-formatted complete records; kron captures typed
values and formats in the consumer. Memory pending is lost on process crash
for both libraries; Mmap supports process recovery. Kron keeps checked CRC at
commit, peek and reclaim plus configuration/sink identity and pins; protocols
are not identical. This comparison preserves each library's actual semantics
and does not reduce kron validation to change rankings. No strict power-loss
qualification or fsync throughput is implied by ordinary written completion.

## Reproduce

```sh
python3 bench/cpp_reference/run.py --output-dir /path/to/fresh-capture --libraries foundation,kron --events 100000 --warmup 1000 --repeats 5 --producers 1,4 --metadata full --kron-schema both --kron-modes async,spsc --kron-storages memory,mmap --affinity 0,2,4,6,8,10 --timeout-seconds 120 --discard-artifacts
python3 bench/cpp_reference/analyze.py /path/to/fresh-capture
```

`detail.py` is the archived additional analysis for this200-trial layout.
Final source/archive/binary and row/distribution checks are in qualification.json.
The broader goal remains unproven: stable all-metric dominance, business
payload diversity and non-Linux device runs require independent evidence.
