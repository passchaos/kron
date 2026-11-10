# Controlled performance capture and comparison

`bench/regression.py` captures public benchmark executables and compares complete
captures. It fixes inputs and child-process CPU affinity, validates delivery,
retains every report row, and distinguishes a noisy measurement from a confirmed
regression. It does not rebuild kron, change host-wide settings, or rewrite the
historical pilot evidence.

Run a baseline and candidate with an externally built snapshot executable:

```sh
python3 bench/regression.py capture \
  --binary /tmp/kron-snapshot-byref --output /tmp/snapshot-baseline.json \
  --benchmark snapshot --mode attached --cases admission:1,full:4 \
  --events 10000 --repeats 5 --affinity auto \
  --source-label 'revision and build command for this artifact'
python3 bench/regression.py capture \
  --binary /tmp/kron-snapshot-candidate --output /tmp/snapshot-candidate.json \
  --benchmark snapshot --mode attached --cases admission:1,full:4 \
  --events 10000 --repeats 5 --affinity auto \
  --source-label 'candidate revision and build command'
python3 bench/regression.py compare \
  --baseline /tmp/snapshot-baseline.json --candidate /tmp/snapshot-candidate.json \
  --output /tmp/snapshot-comparison.json --threshold 0.10
```

For the full main logger benchmark, select `--benchmark logger`, `--mode async`
or `spsc`, `--cases sampled:1,batch:4`, and `--sink memory` or `file`. The input is
fixed to five numeric fields, JSON, dynamic timestamp clock, warmup 1,000 total
events, blocking overflow, sleeping worker, 256 journal/channel slots, 16 KiB
records, 64 KiB file batches, portable file backend, no prepared schema, and no
durable flush. For snapshot it fixes ZeroClock, complete JSON discard sink,
1 KiB records, 256 journal/channel slots, sleeping worker and no replacements.
Shared and attached captures are separate configurations; they cannot be compared
as a same-configuration code regression.

## Scope and prerequisites

Every case uses 1/4/16 producers, at most 10,000 total events, exactly 1,000
excluded warmup events, and **five through nine** independent repetitions. The
default cases are P1 admission and P4 full for snapshot, or P1 sampled and P4
batch for the logger. Repetition order alternates between forward and reversed
cases. Fewer than five repetitions are rejected, rather than promoted into a
baseline. `--timeout` defaults to 45 seconds per invocation and is limited to
120 seconds; a failure leaves an incomplete capture with its command/reason and
stops without retrying.

On Linux, `--affinity auto` takes up to the first eight CPUs currently allowed
by `os.sched_getaffinity(0)`. `--affinity 2,4,6,8` can choose an explicit subset
of that allowed set. `subprocess` applies `os.sched_setaffinity` to the child
before executing the benchmark; all its threads inherit that mask. The driver
and host-wide policy are unchanged. This pins a process to a set, not one thread
per core, and can still include hybrid or SMT siblings. Affinity does not reserve
CPUs or suppress frequency changes and background workload.

Each trial receives a fresh temporary work directory for its journal and any
file output. Initialization and warmup remain excluded according to the public
executable's reported timing contract. No system cache flush is performed;
this is the same warmed logging workload with fresh resources, not a disk cold
start or durable-storage benchmark. Snapshot full uses a counting discard sink
that validates record boundaries; the logger's own report distinguishes memory
and file sinks. Complete written flush and final drain are included in the
reported throughput boundary.

Capture metadata includes binary SHA-256, driver SHA-256, the Zig source-tree
hash, supplied source/build label, CPU model, selected CPU governors, kernel,
architecture, reported optimize/toolchain settings, affinity, fixed input flags,
all commands, and every output row. The final tool also records the temporary
storage directory/device in its machine fingerprint. A working-tree hash is a
capture-time source record, not proof that an already built external binary
matches that source. Supply the actual revision/build provenance in
`--source-label`; the immutable binary hash identifies the measured artifact.

Snapshot capture also supports `--storage=memory|mmap` (default mmap). The
driver forwards the option and verifies `queue_storage` plus
`process_crash_recovery` in every report. Memory must explicitly report false
for crash recovery. Captures with different storage cannot be compared as an
equal-semantics code optimization: compare rejects them. Each capture's summary
remains useful for a deliberate storage-policy study. Legacy captures missing
storage metadata are treated as mmap only; a new memory row cannot masquerade
as a legacy mmap row. The main logger driver also supports explicit memory storage, preserving the same strict separation of recovery contracts.

## Validation and statistics

Snapshot admission rows must report all completed begin/end pairs and zero
accepted/written events. Snapshot full and logger rows must confirm all requested
events accepted and written, zero filtering/drop/errors/pending, and the fixed
clock, queue, sink and formatting configuration. Snapshot additionally proves
zero Runtime allocations during measurement using its failing allocator. If
another executable reports allocation counters they are checked; absent counters
are not invented as a zero-allocation claim. All rows returned by a logger
invocation are validated even when only its requested sampled or batch row is
selected for summary. Missing repetitions or duplicate repetition IDs are errors.

Each case reports throughput plus sampled p50/p99 when available. The statistics
retain median, mean, min/max, inclusive Q1/Q3, relative IQR, sample coefficient
of variation, and relative range `(max-min)/median`. A deterministic bootstrap
over the five-to-nine **trial summary values** gives a 95% median interval.
This describes between-trial uncertainty; it is not a confidence interval for
the underlying individual-call p99. Benchmark noop clock measurements remain
in the raw reports and are not subtracted from latency percentiles.

The default threshold is 10%:

| Condition for a metric | Result |
| --- | --- |
| Either capture's CV or relative range exceeds the threshold | `inconclusive`; no pass/fail claim for that metric. |
| Stable median throughput falls more than 10%, or stable median latency rises more than 10% | `regression`. |
| Stable metric remains inside the threshold | `within_threshold`. |
| A zero baseline latency prevents a meaningful relative comparison | `inconclusive`. |

All configured metrics matter. A reliable regression in any metric yields an
overall regression. Otherwise a noisy metric makes the overall result
inconclusive; only fully stable results within the limit return
`within_threshold`. The comparison prints each metric's statistics and change
so an aggregate status cannot hide the reason.

Compare requires identical benchmark configuration, affinity, kernel/CPU/
governor/storage fingerprint and reported compiler environment. Binary and source
hashes may differ and remain recorded; a budget, clock, format, sink, queue storage or machine
change is rejected instead of mislabeled a code performance change. Serialized
summaries are recomputed from validated rows before comparison. Different input
or reliability contracts require a separate comparison study.

Exit codes are 0 for complete capture or `within_threshold`, 1 for regression,
2 for inconclusive, and 3 for validation/configuration/runtime failure. An
inconclusive result needs a more stable environment or appropriate further
sampling; it is not silently accepted as a successful performance gate.

## Tool verification and observed selfbaseline

Run the focused tests:

```sh
python3 -m unittest discover -s tests -p test_regression.py -v
```

Ten pure tests cover case/affinity parsing, minimum repetitions, quartiles and
bootstrap intervals, stable throughput/latency regressions, noisy regressions,
changed budgets/clocks/machines, missing completions, duplicate repetitions,
allocation failure and zero baseline resolution.

The implementation was exercised by two real captures of the **same** existing
snapshot binary: five repetitions each of attached P1 admission and P4 full,
10,000 events, the same CPU mask, and a sleeping worker. All 20 invocations
completed their expected calls, full invocations wrote 10,000 records, final
pending was zero, and Runtime allocation counts were zero. The candidate and
baseline binary hashes matched.

The same-binary comparison returned **inconclusive**. P4 full throughput medians
were 523,544 and 532,598 records/s, with relative ranges about 3.3% and 5.2%, and
that metric remained within threshold. Admission latency/rate and P4 full p50
had larger between-trial variation, so they were not promoted to a passing or
failing result. This verifies the noise branch with actual reports; it proves
neither an optimization nor a regression of kron.

Those new reports are preserved under
`/tmp/kron-controlled-regression-baseline.json`,
`/tmp/kron-controlled-regression-candidate.json`, and
`/tmp/kron-controlled-regression-comparison.json`. Temporary evidence can be
cleaned by the environment. The earlier file, clock, prepared-schema, and
snapshot pilot reports were not overwritten. Establish a production regression
baseline from a controlled build and machine with understood noise before using
the default threshold as a release gate.
