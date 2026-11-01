# Admission measurement reuse

The default inline submission path previously validated the complete
attribute/argument tree in `submitDestination`, then `codec.encode` validated
it again while computing the exact wire size. The route predicate sits between
those two passes. This round keeps the complete pre-predicate validation but
fuses it with the length calculation:

- `codec.measure` validates the borrowed tree and returns the exact wire size
  without rejecting the event level.
- `SubmissionContext.encoded_size` carries that size for the default inline
  path.
- `codec.encodeSized` re-checks the level and destination capacity, then writes
  the same bytes without another full-tree length traversal.
- Redaction rewrites borrowed storage and prepared schema bindings use a
  different wire shape, so both keep their independent validation/measurement.
- Public `codec.encode` still validates independently; no unchecked writer or
  reusable validation token is exported.

Error ordering is unchanged: tree errors still occur before route predicates,
and level/capacity errors still occur only at the accepted write boundary. A
filtered invalid-level event remains filtered; an invalid tree still fails
before filtering.

## Correctness evidence

- `zig build test` passes; the new codec test compares `measure`, `encodedSize`
  and `encodeSized` bytes with public `encode`, checks `BufferTooSmall`, and
  confirms `.off` is measured but rejected only by level-checked writes.
- `zig build test-predicates` passes the new public integration test: duplicate
  keys fail before the predicate with no journal reservation; a filtered `.off`
  event returns `filtered`; an accepted nested event keeps every value in the
  delivered JSON.
- The full ReleaseFast verification gate passed 81/81 steps and 502/502 tests
  (`verify-local-releasefast.log`).
- Targeted ReleaseSafe runs passed:
  `release-safe-codec.log` (9/9, including the admission measurement test) and
  `release-safe-predicates.log` (1/1). A full ReleaseSafe `zig build test`
  attempt was stopped after more than 18 minutes blocked in `D` state on
  `jbd2_log_wait_commit` with host load around 110 and the root filesystem at
  98% capacity. That attempt is not recorded as a pass; it was a host I/O
  starvation, not a reported code failure. The full ReleaseSafe suite remains
  to be rerun in a quieter window.

## Whole-process PMU

`perf stat` on fixed CPUs 0/2/4/6/8/10, five alternating pairs, complete
ReleaseFast JSON file workflow (producer + background formatting/file output +
written flush + shutdown + cleanup). Each trial emits 100,000 records plus 1,000
warmup records. User/core counters exclude kernel I/O work.

| Case | Before median instructions | After median instructions | Change | Status |
| --- | ---: | ---: | ---: | --- |
| SPSC memory P4 batch | 1,452,632,717 | 1,409,229,503 | −2.99% | stable local measurement |
| Async memory P1 batch | 1,320,597,982 | 1,275,834,972 | −3.39% | stable local measurement |

Instruction relative spread is 0.5%–1.2% on both sides. Cycles and task-clock
spread is 12%–28%; the host load average was about 95 during capture, so cycles
and throughput remain inconclusive. No speedup is claimed from these counters
alone.

Raw rows, binary identities and the exact commands are in `pmu-results.jsonl`
and `pmu-summary.json`.

## Complete file workflow

The paired workflow uses the same driver and independent output oracle as the
cross-library comparison. It validates every physical JSON record, counters,
file budgets and written flush/shutdown/cleanup. 100 alternating trials
validated 10,100,000 records; every trial had accepted=written=100,000,
pending/drop=0 and the original queue/file budgets. Results are in
`workflow-results.jsonl` and `comparison.json`.

| Batch case | Before median records/s | After median records/s | Change | Status |
| --- | ---: | ---: | ---: | --- |
| async memory P1 | 1,441,005 | 1,348,054 | −6.46% | inconclusive |
| async memory P4 | 1,411,129 | 1,409,612 | −0.11% | inconclusive |
| SPSC memory P4 | 1,404,875 | 1,411,592 | +0.48% | inconclusive |
| SPSC mmap P4 | 1,386,829 | 1,378,897 | −0.57% | inconclusive |
| SPSC mmap P4 prepared | 1,421,397 | 1,427,105 | +0.40% | inconclusive |

Every throughput group has at least one side with CV or relative spread above
10%, and all trial-bootstrap median intervals overlap. The host load average
was about 88–92 during capture. The async-P1 decline and the other slow values
are retained; positive medians are not promoted to a stable speedup.

## Boundaries

This is a local whole-process CPU-work reduction, not a cross-library ranking.
The archived cross-library numbers use an older source snapshot; a new
Foundation/Quill comparison must be run on the same source and host window.
The file boundary is written, not durable/fsync or power loss. Mobile device
qualification remains outstanding.

`before-source.tar.gz`, `codec.patch`, `runtime.patch`, `tests.patch` and
`provenance.json` preserve the exact before/after sources, patches and binary
hashes.
