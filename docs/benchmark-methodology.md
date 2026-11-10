# Benchmark method and reproducibility

The application-impact benchmark additionally compares identical deterministic
request work with no logger and shared/SPSC Memory/Mmap logging. It verifies
application digests and complete JSON against an independent integer model,
and reports whole-process user PMU and actual completion boundaries. Input,
affinity, sampling, sparse-source and synthetic-workload limits are described in
[application-benchmark.md](application-benchmark.md). It complements log-only
measurements and does not substitute for production-service or durable evidence.

`bench/main.zig` measures the implemented kron Runtime, encoders, memory queues and mmap journals,
and sinks on Zig 0.16. It runs synchronous delivery, shared MPSC journal delivery,
and the real SPSC runtime with one attached channel per producer. File trials
select a concrete portable or Linux io_uring backend. Memory trials use the
bounded MemorySink. It does not infer performance from SQE submission speed.

Build a ReleaseFast executable with the repository's `bench` step, or use the
compiler directly when working on the benchmark in isolation:

```sh
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/main.zig \
  -O ReleaseFast -Mkron=src/root.zig -femit-bin=/tmp/kron-bench
/tmp/kron-bench --help
python3 bench/validate.py --binary /tmp/kron-bench
```

The build step imports the public `kron` module into `bench/main.zig` and forwards
arguments after `--`, for example `zig build bench -Doptimize=ReleaseFast --
--mode=async --sink=file --backend=portable`. Avoid comparing Debug measurements
with ReleaseFast measurements. Reports include the optimize mode and Zig version.

## Explicit queue storage

`--storage=mmap|memory` selects the asynchronous capture storage, independently
of `--sink=memory|file`. Both shared async and SPSC support memory schema
prewarming and durable file output. Sync reports queue_storage=none and rejects
an explicit memory storage selection. These choices have different process-crash
contracts and must remain separately labeled in performance comparisons.

## Trials and timing boundaries

One invocation writes two JSON Lines rows, or a CSV header and two data rows.
The `sampled` and `batch` rows use independent runtimes, sinks, and fresh journal
files. Each trial has `--events` total attempts across all producers; the default
is **10,000 total**, rather than 10,000 per producer. Initialization and final
quantile sorting/report serialization are outside the completion interval.

The producer threads first attach their SPSC channels when applicable, perform
the excluded warmup, and wait at a start barrier. The main thread waits for all
producers, flushes warmup to written, snapshots counters, and releases the
barrier. Timing ends after every producer has joined, `flush(.written)` has
returned, the requested optional durable flush has returned, and
`shutdown(.drain)` has completed. Start barrier wakeup, producer completion/join,
final flush, and shutdown overhead are included in `total_ns`.

| Report field | Meaning |
| --- | --- |
| `runtime_init_ns` | Sink and Runtime initialization, including journal/channel allocation, mapping, and preallocation. |
| `preparation_ns` | Thread creation, SPSC attachment, sample storage preparation, excluded warmup, and its flush. |
| `producer_wall_ns` | Start barrier release through the producer joins, including contention and overload blocking. |
| `flush_written_ns` | Final `flush(.written)` after producers finish. This may be small when the worker already caught up. |
| `durable_flush_ns` | Optional final `flush(.durable)`; null when not requested. |
| `shutdown_ns` | Final shutdown and worker join. |
| `total_ns` | Complete measured trial through final drain, including optional durable flush. |
| `written_records_per_sec` | Confirmed complete sink records divided by `total_ns`. |
| `written_bytes_per_sec` | Confirmed complete sink bytes divided by `total_ns`. |
| `producer_ns_per_attempt` | `producer_wall_ns / attempted`; in the batch trial there are no per-call awake-clock measurements. |

`--durable` gives a separately labeled scenario. Its rate denominator includes
the durable flush, so it must not be mixed into a written-only comparison. The
trial journal's reclaim boundary remains written: requesting a final durable
flush measures that flush and does not prove a crash-safe durable checkpoint
protocol. Filesystem/hardware fault qualification is a separate gate.

The synchronous Runtime currently flushes each successful record before
returning from `tryEmit`. Its file trial therefore measures this synchronous
contract, even though FileSink can buffer records for a different caller. The
asynchronous Runtime batches the actual journal consumer output. A small journal
or slow sink can make producer admission include backpressure.

## Latency samples and the clock baseline

The sampled trial records `std.Io.Clock.awake` immediately before and after the
normal `Logger.tryEmit` call, including benchmark payload construction and
dispatch. The total sample budget is split across producers and samples are
spread deterministically through each producer's event sequence. Every attempted
outcome is eligible, including filtered, dropped, and failed calls. Quantiles
use nearest ranks of the observed samples; the report includes sample count and
maximum alongside p50, p99, and p99.9.

Each invocation also measures an identically bracketed compiler-barrier noop and
reports `clock_pair_p50_ns`, p99, p99.9, mean, and clock resolution. The separate
`noop_batch_ns_per_call` uses a loop with no per-call clock reads. These quantify
instrumentation cost; clock resolution alone does not describe clock-read cost.
No clock quantile is subtracted from a producer quantile. With fewer than 1,000
samples, p99.9 is often just the observed maximum. Neither small samples nor an
average over a batch establish a stable single-call tail latency.

The batch trial still constructs the same records, checks emit outcomes, and
uses the same record counter sink wrapper. It only removes per-call awake-clock
sampling. `producer_ns_per_attempt` is elapsed wall time divided by all attempts,
including concurrency; it is a throughput-derived average, not an average of
individual producer call durations. The wrapper adds two counters when a child
accepts a record and updates acknowledged counters after a successful child
flush. This common instrumentation is included for every backend.

## Inputs, warmup, and budgets

Arguments accept both `--key=value` and `--key value`. All sizes are decimal
bytes. `bench/args.zig` defines and validates the argument schema. Unknown options,
unsupported producer/field counts, incompatible sink/backend combinations, and
out-of-budget configurations produce a nonzero exit. Runtime errors are emitted
as rows with `status=failed` or `status=unsupported`, observed counters, and an
error name; the executable exits 2 after reporting both trials.

The main dimensions are:

| Argument | Choices/default | Input and contract |
| --- | --- | --- |
| `--mode` | `sync`, `async`, `spsc`; default `sync` | SPSC attaches and detaches on each producer's own thread. |
| `--sink` | `memory`, `file`; default `memory` | Memory has a fixed byte budget; file outputs remain as artifacts. |
| `--backend` | `portable`, `linux_uring`, `auto`; default `portable` | File only. `backend_selected` records the actual initialized backend. Explicit io_uring failure does not fall back. |
| `--producers` | `1`, `4`, `16`; default `1` | Total events and sample budgets are divided exactly among producers. |
| `--fields` | `0`, `5`, `10`; default `5` | Named typed attributes `field0` through `field9`, rather than an extra hidden event ID field. |
| `--payload` | `numeric`, `short`, `long`; default `numeric` | Numeric attributes are unsigned values varying by event/producer/field. Short attributes are 23 ASCII bytes. Long message and attributes repeat ASCII plus newline, quote, and backslash characters to exercise escaping. |
| `--string-bytes` | Default `256` | Long message and each long attribute length. Increase record and sink budgets when increasing this. |
| `--filtered` | Off by default | Emit info while the runtime filter is off; ordinary `tryEmit` argument evaluation still occurs. |
| `--temperature` | `warm`, `cold`; default `warm` | Warm performs `--warmup-events` total excluded attempts on the same producer threads. Cold omits emit warmup. |
| `--format` | `json`, `text`, `logfmt`; default `json` | Keep constant when comparing backends. |
| `--overflow` | `block`, `drop_newest`; default `block` | An overloaded drop trial reports accepted, dropped, and pending counts separately. |
| `--idle` | `auto`, `sleep`, `spin`; default `auto` | Auto uses runtime defaults: shared async sleeps; SPSC spins. Keep this constant in backend comparisons. |
| `--clock` | `dynamic`, `std_io`, `native`, `none`; default `dynamic` | Producer timestamp call path. Static modes use `loggerWithClock` or `attachThreadWithClock`; report field `event_clock` identifies the choice. |
| `--schema` | Disabled by default | Prepared metadata with journal v2. Requires async/SPSC and `--clock=dynamic`; incompatible combinations return `InvalidConfiguration`. |

Cold means first use of this freshly initialized runtime and producer threads
without an emit warmup. It does **not** drop operating-system caches or undo
journal pre-touching. The noop clock baseline runs before both trials. Report
`runtime_init_ns` separately when cold-start initialization matters.

Budget defaults are 64 MiB for the memory sink, 256 slots for the shared journal,
256 slots per SPSC channel, 16 KiB maximum encoded/captured record bytes,
64 KiB file batches, and io_uring depth 4. SPSC preallocates the selected number of
producer channels. `--journal-bytes` defaults to 256 MiB and includes the shared
journal **plus every SPSC channel**. The report gives both the configured bound
and `queue_allocation_bytes`, using the current 4 KiB header and fixed 64-byte
aligned slot layout; Runtime independently enforces its allocation budget.
`journal_allocation_bytes` and `journal_mapped_bytes` report only file mappings,
so they are zero for memory storage. `queue_storage` reports none/memory/mmap;
`process_crash_recovery` is true only for mmap. Memory trials have no journal
artifact path. CSV appends these storage fields after the legacy columns.

`journal_high_water` is Runtime's lifetime high-water metric for this trial,
including warmup. Memory warmup output is cleared after its successful flush so
that it does not consume the measured output budget. File artifacts keep warmup
records; `warmup_written` distinguishes them from measured records. Budget
exhaustion is an observable failed/dropped trial, rather than automatic growth.

## Counters and artifact checks

Producer return values populate `attempted`, `accepted`, `filtered`, `sampled`,
`dropped_full`, `dropped_oversize`, `rejected_closing`, and `emit_errors`. Runtime
health supplies independent accepted/written/error/pending counters. A counted
wrapper confirms complete records only after the concrete sink's flush succeeds.

A successful trial checks all of these conditions before printing `status=ok`:

- All requested attempts occurred.
- Producer accepted equals Runtime accepted.
- Runtime written equals the counted sink's written records and accepted events.
- Final journal pending is zero.
- Actual memory length or file size equals the acknowledged byte count, with
  excluded file warmup bytes accounted for.

`bench/validate.py` also reads file artifacts, counts physical JSON Lines, parses
each line, and verifies CSV parsing, filtered/dropped cases, SPSC concurrency,
both file backends, final durable flush, and a deliberate bounded-memory failure.
If io_uring is unavailable because of kernel or policy restrictions, its case is
reported as unsupported; this is not a passing io_uring execution result.

## Reproduce a backend comparison

A complete JSON file workflow has compared portable and Linux io_uring with the
same ReleaseFast executable, repeating Memory/Mmap, shared/SPSC, and P1/P4 five
times each for batch and sampled, for 160 trials and 16.16 million physically
verified records. On that workload, io_uring's through-shutdown throughput median
was about 17%–19% lower; six of eight batch groups met the two-side 10% CV/spread
threshold and two remained inconclusive. Each checked batch currently reclaims
slots only after the required flush, so the I/O-overlap window is limited; the
result cannot be generalized to every storage device or larger batch.

The generic backend comparison entry is `bench/compare_backends.py` below. It
fixes consumer budget 4, 256 queue slots, 512-byte payloads, and a 64 KiB file
buffer, verifies real files record by record, reports `backend_requested` and
`backend_selected`, and never treats an unavailable or failed explicit io_uring
request as portable success.

Use a file sink, one format, identical records and policy, the same final
completion boundary, and equal batch/depth/journal budgets. Keep the executable,
machine, and CPU affinity constant. This helper alternates backend order across
repetitions, verifies counters and actual backend selection, and preserves raw
JSON Lines, command arguments, binary SHA-256, and machine metadata:

```sh
python3 bench/compare_backends.py --binary /tmp/kron-bench \
  --output-dir /tmp/kron-bench-file-comparison --repeats 5 \
  --events 10000 --mode async --producers 4 --fields 5 --payload numeric
```

It creates fresh output and journal files under the evidence directory rather
than replaying old journal records. The default timeout is 60 seconds per
invocation. A timeout is an incomplete trial; its submission count must not be
used as written throughput. Preserve incomplete journals when diagnosing it.
The median/min/max summary describes observed trial variation; it does not
establish a universal default-backend decision.

A three-repetition pilot on this development host used an Intel Core i9-13900K,
32 logical CPUs, Linux 6.8.0-147-generic, and the `powersave` governor. Portable
observed a median 598,961 written records/s in its batch trial; io_uring observed
568,293. Each completed 10,000 records with zero final pending. The unreserved
host, small trial count, bounded-journal backpressure, and ongoing source changes
limit this pilot; it is not the controlled regression baseline described below.

For an explicit single scenario, including contention or saturation:

```sh
/tmp/kron-bench --mode=spsc --sink=file --backend=portable \
  --producers=16 --fields=10 --payload=long --events=10000 --idle=spin
/tmp/kron-bench --mode=async --sink=memory --producers=16 \
  --journal-slots=2 --overflow=drop_newest --events=10000
/tmp/kron-bench --mode=async --sink=file --backend=portable \
  --durable --events=10000 --output=csv
```

Record machine model, physical/logical CPU topology, affinity, frequency/governor,
kernel, filesystem and mount options, storage device, background workload, and
the exact build revision. On Linux useful read-only capture commands are:

```sh
uname -a
lscpu
findmnt -T /tmp/kron-bench-file-comparison -o SOURCE,FSTYPE,OPTIONS
lsblk -o NAME,MODEL,ROTA,SIZE
```

Reports include logical CPU count, architecture/OS, kernel release, Zig version,
and optimize mode. CPU process/thread clocks are included when available. Linux
also reports user/system CPU time, minor/major page faults, context-switch deltas,
and process lifetime maximum RSS in KiB. Maximum RSS is a process high-water
value rather than per-trial allocation. Main-thread noop measurements and thread
clock sums do not imply affinity pinning or an idle machine.

## Attribute clock dispatch separately

`bench/dispatch.zig` isolates wall-clock acquisition from logging admission,
capture, formatting, queues, and sinks. It uses the same real-time nanoseconds
and i64 clamp for its `dynamic` and `std_io` cases. The dynamic case calls
`Clock.realNow` through a callback selected by a `noinline` runtime factory. Both
runtime choices delegate to std.Io with identical semantics. A memory escape
keeps the callback target opaque to whole-program optimization. Before publishing
a dispatch-cost claim, inspect the measured binary: the dynamic batch must still
have an indirect callback call, while StandardClock retains the std.Io `now`
vtable call.

| Microbenchmark mode | What changes |
| --- | --- |
| `dynamic` | Runtime-selected kron.Clock callback followed by the supplied std.Io clock provider. |
| `std_io` | Comptime StandardClock entry point followed by the same std.Io clock provider. It still makes a std.Io vtable call. |
| `native` | Explicit Linux NativeClock provider using vDSO-aware `clock_gettime`; this changes the provider as well as dispatch. It is not a measurement of removing only one virtual call. |
| `none` | Comptime ZeroClock disables the wall timestamp. The loop/checksum control remains, but there are no wall-clock reads. |

The microbenchmark reports all four modes with rotating order across repetitions.
Provider warmup occurs before each measured batch. A returned timestamp feeds a
wrapping checksum and a per-call compiler barrier so calls cannot disappear; the
barrier also keeps ZeroClock's control loop intact. Timing uses just two
`std.Io.Clock.awake` reads around the batch. Reported `ns_per_call` is batch elapsed
time divided by calls, not a single-call p99. The separately reported bracketed
noop distribution and batch noop average describe instrumentation; neither is
subtracted from the result.

NativeClock's supported flag describes the Linux implementation. The provider
can fall back to std.Io on a clock-read failure; the microbenchmark explicitly
reports `native_provider_may_fallback_to_std_io`. Native on an unsupported target
is reported unsupported and is not relabeled std.Io. No-clock changes timestamp
semantics: in the complete logging benchmark timestamps become zero while
monotonic runtime progress remains enabled. Its smaller encoded timestamp also
changes output bytes, so a full-pipeline improvement is not solely clock-read
cost.

Build and validate independently:

```sh
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/dispatch.zig \
  -O ReleaseFast -Mkron=src/root.zig -femit-bin=/tmp/kron-dispatch
python3 bench/validate_dispatch.py --binary /tmp/kron-dispatch
/tmp/kron-dispatch --iterations=100000 --warmup=10000 --repetitions=7
python3 bench/validate.py --binary /tmp/kron-bench \
  --case std-io-clock --case native-clock --case none-clock \
  --case std-io-spsc-clock --case native-spsc-clock --case none-spsc-clock
```

The bounded defaults are 10,000 measured reads, 1,000 excluded warmup reads, and
five repetitions. `--mode=dynamic|std_io|native|none` selects one mode for focused
profiling. The validation verifies exact batch counts, checksum consumption,
rotating order, unsupported labels, and invalid-budget handling, with no timing
advantage assertion.

For full pipelines, keep mode, inputs, sink, format, capacity, overload, idle,
and clock provider constant when comparing dispatch choices:

```sh
/tmp/kron-bench --mode=spsc --sink=memory --events=10000 --clock=dynamic
/tmp/kron-bench --mode=spsc --sink=memory --events=10000 --clock=std_io
/tmp/kron-bench --mode=spsc --sink=memory --events=10000 --clock=native
/tmp/kron-bench --mode=spsc --sink=memory --events=10000 --clock=none
```

The producer factories select the requested static provider on each actual
producer thread, including SPSC attachment. Clock selection does not replace the
runtime admission, routing, encoding, sink flush, or final drain checks. Dynamic
and StandardClock isolate the optional kron callback layer while preserving the
std.Io provider. Native and disabled timestamps are separate scenarios. A small
time difference amid overlapping repeated-run ranges does not establish a stable
nanosecond saving, and a clock-only result cannot be attributed wholesale to
end-to-end log latency.

A bounded clock-only pilot preserved seven rotating-order batches. Dynamic and StandardClock ranges overlap;
the results do not establish a stable subnanosecond dispatch saving. The evidence
also records an incomplete SPSC sleep trial seen with a pre-fix runtime binary,
separately from completed clock-only measurements.

The earlier file-backend pilot evidence is retained unchanged. It predates this
explicit clock selector; absence of `event_clock` in those archived rows means
the then-default Runtime dynamic std.Io clock path.

## Prepared metadata comparison

`--schema` is an explicit prepared-metadata benchmark. Defaults continue to use
self-contained records in journal file v1 with no schema table. The prepared trial enables two
fixed schema slots with 4,096 bytes per definition in every shared/channel
journal. `queue_allocation_bytes` includes the schema extension and aligned
table computed by `kron.schema.layout` for the main journal and **each** SPSC
channel; Runtime independently enforces `--journal-bytes`.

Every producer registers the actual benchmark shape before emitting warmup or
joining the start barrier: scope `benchmark`, a dynamic message, 0/5/10 field
keys, and unsigned or string kind masks for the selected payload. Metadata stores
types and keys without example values. Shared producers deduplicate through
`prewarmMetadata` and use `loggerWithSchema`; an attached SPSC producer registers
its own channel via `prewarmThreadMetadata` and uses `threadLoggerWithSchema`.
Registration, metadata persistence and cold deduplication are included in
`preparation_ns`, and excluded from producer timing even in the no-emit-warmup
scenario. A schema "cold" trial therefore means no emit warmup after preparation,
not an unregistered first emit.

The same message and attribute values are encoded into the same JSON shape and
flushed through the same sink completion boundary. `schema_enabled` identifies
the wire path; the report does not invent captured-payload-byte counters that
Runtime does not supply. Normal output byte counts, accepted/written counters,
drop accounting and final pending checks remain active. File verification also
checks scope, field count, parseable JSON Lines, and the v2 journal header.
It also checks exact message/attribute values for numeric and string payloads,
and matches the combined on-disk main/channel journal sizes against the reported
allocation for either wire version.
Dynamic-clock-only support keeps this comparison away from a second, unmatched
prepared/static-clock wrapper.

Run the bounded shape checks and two repeated comparisons:

```sh
python3 bench/validate.py --binary /tmp/kron-bench-schema \
  --case schema-zero --case schema-long --case schema-spsc-short \
  --case schema-spsc-file
python3 bench/validate.py --binary /tmp/kron-bench-schema \
  --schema-pilot /tmp/kron-schema-pilot --timeout-seconds 45
```

The pilot uses 10,000 total attempts per trial, 1,000 excluded warmup attempts,
1/4 producers, both memory/file sinks, async/SPSC, five numeric attributes, and
the same JSON/dynamic-clock/sleeping-idle settings. The second repetition reverses
case order. It preserves a fresh binary hash, raw rows, commands, and median/
min/max completion rates in the requested output directory. A timeout stops the
pilot with an incomplete row and no retry. Previous C++ and file-backend baseline
evidence remains unchanged. Compare repeated ranges and preparation cost before
attributing a stable performance improvement to prepared metadata.

A two-repetition development-host pilot completed all 64 sampled/batch rows,
with 10,000 accepted and written events in each row and no final pending. The
five-numeric-field batch medians were:

| Mode/sink | P1 v1 records/s | P1 prepared v2 records/s | P4 v1 records/s | P4 prepared v2 records/s |
| --- | ---: | ---: | ---: | ---: |
| Async/memory | 617,661 | 678,188 | 611,159 | 664,570 |
| Async/file | 590,670 | 655,947 | 581,670 | 648,655 |
| SPSC/memory | 623,252 | 682,356 | 622,636 | 675,869 |
| SPSC/file | 547,827 | 621,771 | 603,838 | 681,340 |

Actual schema table storage adds 8,320 bytes to each journal at these settings.
For P4 SPSC, the reported total rises from 21,073,920 to 21,115,520 bytes because
the main journal and four channels each contain a table. All their actual file
sizes and v1/v2 headers were checked. Registration remains in preparation time.
These are two trials on an unreserved host, rather than an established baseline:
SPSC/file P1 ranges overlapped (v1 460,999–634,654; v2 577,060–666,483 records/s).
Raw rows, commands, binary/validator hashes and summary were preserved under
`/tmp/kron-schema-pilot-20261031`; these temporary artifacts may be cleaned up.
The earlier checked-in baseline evidence was not rewritten.

## Snapshot admission versus complete output

`bench/snapshot.zig` isolates the current public admission paths. `--mode=shared`
uses a ZeroClock logger backed by the shared Runtime owner; `--mode=attached`
attaches a ZeroClock SPSC logger on each producer thread. It neither casts the
opaque configuration handle nor reads a mutable Snapshot. The report's
`global_snapshot_pin_metric` is null: pin/RMW counts are not measured by this
benchmark and no production introspection API is invented for that purpose.

`--phase=admission` calls the owner's normal `begin(.info, "snapshot")` and
balances every ready admission with `end()`. It captures no fields and submits
no queue or sink records. `completed` counts successful begin/end pairs while
accepted/written remain zero. This microbenchmark can expose admission overhead,
including filter/snapshot lookup, gates, owner-thread validation, and contention;
it does not isolate a single atomic instruction in the machine code.

`--phase=full` emits the same message and five numeric fields through the normal
typed frontend and JSON encoder. A counting discard sink checks complete JSON
record boundaries, the message, and zero timestamp, and confirms records only
after its flush. This removes filesystem output and memory retention from the
comparison. The shared/attached comparison still changes MPSC versus SPSC queue
reservation/consumer scheduling, so full-pipeline differences cannot be entirely
attributed to snapshot pinning.

Both phases create/prewarm the actual owner on the producer threads, flush warmup,
and start behind a barrier. Each emit or admission is measured with two awake
clock reads; a separately reported bracketed noop baseline quantifies timing
cost without subtracting its quantile. `producer_wall_ns` includes all joins,
and `total_ns` additionally includes final written flush and shutdown/drain.
Runtime allocations are rejected after preparation in the steady variant: the
Runtime allocator is a failing allocator with its failure point advanced to the
last initialization allocation. A successful steady row must report zero new
Runtime allocator calls, all requested completed calls, no dropped/filtered
outcomes, and zero final pending. This does not count allocations internal to
the supplied std.Io provider.

`--idle=sleep|spin` keeps the worker policy explicit and identical in shared and
attached modes. The current default is sleep, particularly for admission-only
tests whose consumer has no records. The initial pilot below used an explicitly
spinning worker; it is retained as an observation rather than rewritten after
policy/source changes. `--admission-p1-only` in the validation runner selects the
small P1 shared/attached subset for two-repeat matched-policy checks.

`--replace-every=N` is a separately labeled variant: producer zero installs the
same logical route after each N of its own measured calls. Replacement work
falls outside individual call samples but inside producer wall time. The variant
allows and reports cold configuration allocations, retains versions through
delivery, and is limited to 32 replacements. It does not mix replacement work
into the steady-state result or turn replacement into a warmup operation.

Build and run the bounded two-repetition pilot:

```sh
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/snapshot.zig \
  -O ReleaseFast -Mkron=src/root.zig -femit-bin=/tmp/kron-snapshot
python3 bench/validate_snapshot.py --binary /tmp/kron-snapshot \
  --output-dir /tmp/kron-snapshot-pilot --events 10000 --repeats 2 \
  --replacement-check --idle=sleep
```

The pilot completed 32 rows: shared/attached × admission/full × 1/4/16 producers
for two repetitions, plus four P4 replacement scenarios per repetition. Every
row completed 10,000 calls; full rows wrote 10,000 complete records and admission
rows wrote none. All steady rows reported zero Runtime allocations. The explicit
replacement variant installed two versions and reported six allocations in
each row.

Observed admission sample medians of repeated p50 values were shared/attached
532.5/1,560 ns for P1, 886/1,798 ns for P4, and 1,985/2,307.5 ns for P16. The
attached path did not demonstrate an admission speedup in this development-host
sample. P4 complete-output medians were 579,086 shared and 540,679 attached
records/s; P16 were 563,423 and 572,167, with close ranges. These include sampling
and the selected spinning worker, and remain two unreserved-host trials rather
than a controlled baseline. Raw results and binary hash are preserved under
`/tmp/kron-snapshot-pilot`; earlier file/C++/clock evidence is unchanged.

A separate bounded `perf record` on attached admission P4 with 100,000 calls
observed 57 `cpu_atom/cycles/P` samples and zero lost samples. About 72.7% landed
in `memcpyFast`, with `routeMaskIn` in its call chain; about 6.8% landed in the
spinning collector's `drainJournal`, and 4.4% in `threadSnapshot`. This limited
hybrid-CPU sample suggests investigating filter/route copying alongside snapshot
lookup before attributing the result to refcounts. Restricted kernel symbols and
unpinned scheduling limit interpretation. It is an engineering profile lead,
not proof that all memcpy samples represent one source-level copy or a prediction
of an optimization's benefit.

The profile led to a separately verified implementation fix: route iteration in
`routeMaskIn` copied each approximately 22 KiB Route, which contained fixed
predicate state. The parent changed the owning loops to iterate by reference.
Generated-code inspection on the old binary showed a `0x5840`-byte memcpy call
and `0x5868` bytes of stack reservation in this function. The new binary had
`0x38` bytes of stack reservation and no memcpy call there. These are concrete
compiled call-path facts; they do not imply every earlier timing difference
was caused solely by that copy. The old attached begin assembly also showed its
gettid syscall behind a TLS cache-valid check, so no per-call thread-ID syscall
cost is attributed to the warmed attached path.

After the fix, a single bounded matched-policy check used sleeping workers,
10,000 total calls, and 1,000 excluded warmup calls. Admission p50 was
78/77 ns shared/attached for P1 and 484/157 ns for P4. Both modes completed every
call with zero Runtime allocations. The same rebuilt binary's two P4 full rows
confirmed 10,000 accepted and written records with zero pending: shared
587,125 records/s and attached 616,930 records/s, including final drain. A separate
two-repeat P1 sleep check observed shared p50 81.5 ns and attached 68 ns, but its
binary was compiled during the source change and is not presented as a pre-fix
baseline. These small development-host observations do not establish a stable
RMW-only saving or a universal pipeline multiplier.

The original 32-row spin pilot/profile remains under `/tmp/kron-snapshot-pilot`;
the two-repeat P1 sleep check is under `/tmp/kron-snapshot-p1-sleep-pilot`; the
explicit rebuilt four-admission/two-full rows and binary hash are under
`/tmp/kron-snapshot-byref-pilot`. Old/new targeted assembly is preserved beside
that last pilot. The full matrix was not rerun to manufacture a new baseline.

Comparison against spdlog, Quill, fmtlog, or another logger requires an explicitly
provided local dependency path and version. Align actual input, encoding,
ordering, memory/queue budgets, overflow behavior, final drain, and durability
before interpreting rates. Binary/deferred outputs and text/JSON outputs belong
in separate comparisons. This benchmark does not install dependencies or label
an implementation strongest based on unrelated published figures.

## Feature contracts and raw throughput

A raw record rate is not a feature-normalized ranking. The kron Memory journal
performs slot reserve/commit/abort, generation and sequence validation, CRC
generation and consumer revalidation, and deferred structured capture before
consumer formatting. Other logging libraries may not carry the same journal/CRC/
recovery contract, and their mmap queues can differ in schema, pin, reclaim, and
durable boundaries. The same JSON bytes and written flush can therefore still
represent different reliability work.

CPU topology is part of the measurement identity. On the current host the
`auto` window uses SMT P-cores, while CPUs 16..31 are single-thread physical
cores that usually map to E-cores. The E-core profile shows CRC, journal
reserve/validate and consumer formatting as larger shares, and competitors can
lead on raw throughput there. P-core windows previously showed kron ahead in some
groups. Neither window is a universal ranking.

The same-source `fd4e941 -> current` A/B on E-cores shows current faster by
7.2%–14.6%, so recent optimizations did not cause the E-core gap. Any claim that
one logger is strongest must state the matched feature contract, output bytes,
storage/recovery mode, CPU topology, and whether the comparison is raw or
feature-normalized.

These tools establish a reproducible starting point. A performance baseline and
regression threshold should follow repeated runs on a controlled machine,
including producer distributions, written completion, saturation, CPU/resource
cost, and business-workload impact. The current measurements are observations
of this build and environment, not promised absolute latency or throughput.

The prepared pilot's 64 rows each confirmed accepted/written equality and zero pending. Two repetitions are a starting point, not a stable regression threshold.
