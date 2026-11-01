# Transfer the checked shared admission View

Baseline Git `bcf7da6` has the same production sources as `c2f8792`. The prior
direct FileSink buffer callback experiment was rejected and restored. Its
full negative/positive evidence remains in the owning evidence directory.

## Change and invariants

Shared Runtime.begin already acquires a checked configuration View. Previously
it retained a pending pin, released that View before returning the admission,
then released the pin at Runtime.end. The candidate transfers the same checked
reader to the admitted call and releases it at end. This avoids two pending
refcount updates without creating a cache or extending lifetime past that call.
The registry already prevents collection/reuse while either readers or pending
pins exist. The admission count/cut and snapshot selection protocol are unchanged.

Accepted journal records still retain their own pending pin before commit and
release it only after the original required written/durable and checked reclaim
boundary. A worker may complete that record before its producer calls end;
the admission reader still keeps the snapshot and resource lease alive. SPSC
continues using its separately owned channel cache; sync/deadline/control
retains use their original pending-pin callbacks. Public output, queue/wire,
filter/sampling semantics and resource budgets do not change.

Filtered/sampled branches release their local View through the same defer.
Ready branches transfer ownership exactly once. TLS unwinding releases the
reader on capture/submission errors, synchronous failure and normal completion.
No borrowed View can be retained by a user or persisted into the journal.

## Semantic tests

New owning tests use real Memory/Mmap shared runtimes behind a reservation gap
and verify that ready admission has a reader but no pending pin. Submission
retains precisely one independent record pin; ending the admission releases
the reader but leaves that record pending until written acknowledgement.
The testing audit counts the exact pending RMW delta, rather than inferring
it from implementation text.

A concurrent replacement/retirement test verifies the old lease is protected
before reserve, then waits for worker acknowledgement and batch View release
while admission remains open. Record pending is zero but collection cannot
free the old lease until end releases the admission reader. The worker's
written publication can precede its temporary batch-View cleanup; an initial
test asserted the reader count too early, and its failure is retained. The
corrected test waits for the actual lifetime boundary.

Other tests cover filtered and exhausted sampling, capture DuplicateKey,
sync write failure, exact reader/count unwinding and zero accepted output.
Existing old-snapshot/filter-overlay and warmed SPSC guard tests remain in
the final15-test Safe scope (`ownership-complete-safe.log`). Initial compile
setup mistakes are retained separately. Broader configuration/admission
scope37 tests passed before new test additions; final source must receive
its own related and composite checks before qualification.

## Full workflow measurement

The frozen public fullJSON harness reports producer/consumer/written flush,
shutdown and cleanup, with initialization/preparation separate. Memory/Mmap,
shared/SPSC, inline/schema, P1/P4 keep full system wall time and fields,256
slots/512-byte payloads,64KiB file buffer and four consumer service quanta.
CPU affinity0/2/4/6/8/10 and actual portable backend are checked. The independent
owning file oracle verifies every physical record; before/after source/binary
guards protect each trial. Five pairs include both batch and sampled calls.

`measure.py --pmu` captures40 complete300k-record trials for inline shared
Memory P1/P4, shared Mmap P4 and SPSC Memory P4 as the unchanged-path control.
User counters include process setup and exclude kernel work. `measure.py`
captures320 full file trials (16 configurations × batch/sampled ×5 pairs).
No strict durable flush is requested for performance measurement. All raw
negative/positive observations, CV/spread/bootstrap and per-file hashes remain;
local atomics savings do not imply a new Foundation/spdlog ranking.

The completed40-trial PMU capture verifies12,040,000 physical records. Shared
Memory P1/P4 and Mmap P4 instruction median differences are within0.13%, with
overlapping intervals; the unchanged SPSC control is within0.01%. Shared
Memory P4 throughput median is3.356% lower with both CV/spread passing and
non-overlapping intervals in this capture. Other throughput medians are also
negative but limited by intervals or repeatability. This does not establish
the mechanism of the loss. Emitted begin contains two fewer static lock-prefixed
instructions, while full-process instruction totals are nearly unchanged;
raw assembly/counters are retained without equating counts to speed.

## Complete first workflow and long follow-up

The320-trial independent file capture verifies32,320,000 physical records.
Shared schema Mmap P1 median throughput increases9.550%, with both CV/spread
passing and non-overlapping bootstrap intervals. Other throughput differences
mostly have overlapping intervals: shared inline Memory P4 −0.869%, shared
inline Mmap P4 −0.153%, shared schema Memory P4 +0.392%, Mmap P4 +0.245%.
The SPSC controls also move by up to about2.7%, although their hot path is
unchanged; this limits causal claims outside the affected shared path.

Call tails remain mixed: shared schema Memory P4 p99 increases24538→30593ns
while p99.9 decreases53732→37628ns, both inconclusive. Shared schema Mmap P4
p99 increases24819→31573ns and p99.9 increases35009→38859ns, inconclusive.
All medians, slow rows and per-metric distributions remain.

A10-trial1M-record shared schema Mmap P1 follow-up verifies10,010,000 records
and has a +4.032% median with non-overlapping intervals and passing local
repeatability. Its first pair started near the final directed ReleaseFast test
exit, so this overlap is retained as a limitation and a fresh clean capture is
required before promoting the candidate. The initial long capture is not used
as clean performance qualification.

## Clean qualification and scope

The independent clean10-trial1M-record capture verifies10,010,000 physical
records. Shared schema Mmap P1 median throughput is1.746M→1.829M records/s
(+4.793%), both CV/spread pass and bootstrap intervals do not overlap. No
build or test from this task overlaps that capture. This is the qualified
workload-specific improvement, not a general shared/P4 speedup.

The complete320-trial file capture,40-trial PMU and clean10-trial long check
total370 trials and54,370,000 verified physical records. The earlier10-trial
long run with test-exit overlap is retained separately and not included in
this clean qualification total. PMU shared Memory P4 has a repeatable negative
median with non-overlapping intervals; the independent full workflow P4
difference overlaps. Both results remain, and no uniform P4 gain is claimed.

The candidate is retained for its cleaner ownership transfer and repeated
shared schema Mmap P1 gain, subject to composite lifecycle/recovery and platform
checks. It creates no heap/queue/file/cached-view budget, and SPSC remains on
its original channel-owned cache. A new cross-library comparison is still
required before changing the Foundation/spdlog ranking.

## Final semantic gate

`zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all` passes
93/93 steps and549/549 Zig tests, including the three new admission lifetime
tests, configuration/deadline/error gates, independent five-mode/single-threaded/
source-distribution packages, Linux host qualification, supported wire/schema
mutation matrices and12 random-time real process-crash cases. Every ACK is
covered by complete output or recovery. The owning TSC check uses native
fallback on calibration_unstable, not new TSC acceleration evidence.

Reproduction builds the candidate with:

```sh
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/cpp_reference/kron_reference.zig -Mkron=src/root.zig -femit-bin=bench/evidence/2026-11-01-admission-view/kron-ref-after-final
zig test src/root.zig -O ReleaseSafe --test-filter 'shared admission' --test-filter 'admission paused' --test-filter 'warmed SPSC'
zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all
zig build check-platforms -Doptimize=ReleaseSafe -j2 --summary all
```

Keep frozen before/after roots and binary hashes during captures. Per-trial
logs are grouped in `trials/<capture>/`, with immediate raw saved rows and
complete/incomplete comparisons retained separately. Final source, archive,
binary, gate and measurement identities are bound in qualification.json after
all checks finish. Cross-platform objects cannot replace device execution.

Nine ReleaseSafe platform objects pass10/10 build steps (`platforms.log`).
These checks and the completed549-test composite are bound to the final source
and capture identities. This is compilation evidence for non-Linux targets,
not device execution or new physical power-loss qualification.
