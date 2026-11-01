# Protected configuration views per delivery batch

The consumer now acquires one configuration View for each distinct snapshot
inside a bounded, 64-record batch and retains it through output barriers and
record acknowledgment. Matching nonzero generation/fingerprint reuses that
view; legacy generation zero still runs the manager's complete lookup and
ambiguity validation each time. The view prevents retirement while callbacks
and reclaim still borrow the snapshot. Error cleanup releases only views;
pending record pins and sink leases remain unchanged.

The change is limited to consumer configuration ownership. Journal checksums,
wire formats, admission cuts and per-record written/durable reclaim remain the
same. It follows the batch reuse principle seen in Quill and Foundation without
introducing a second volatile queue or an unchecked recovery credential.

Five new tests cover:

- One actual Manager.find for 64 same-version selections, with retirement
  blocked until the batch's View is released.
- Legacy lookups revalidated each time, retaining one reader per snapshot and
  requiring no new allocations.
- All 64 configuration versions, including equal fingerprints but distinct
  generations, retaining separate ownership correctly.
- Actual shared/SPSC worker batches of 31 records, with no additional manager
  lookup between the first and last sink callback.
- Mixed versions and sink failure: the written prefix remains, all six records
  stay pending, temporary readers are released and record pins/leases remain.

Existing configuration/deadline tests pass 31/31 in ReleaseSafe. The scoped root
test run passes 12/12, including these five substantive tests and the root import
fixtures. Final broader gates and source identities are recorded separately in
`qualification.json`.

Final ReleaseFast `verify-local` passes 76/76 build steps and 474/474 Zig tests,
with the existing Python, compile-fail, differential, host/package and real
process-crash gates. The final ReleaseSafe platform gate emits all nine target
objects and passes 12 configuration integration tests. `verify-fast.log`,
`platforms-safe.log` and `qualification.json` identify the exact sources.

`before-lookup-negative.log` shows the new worker call-count regression rejecting
the old consumer with 31 lookups. Only test audit instrumentation was added to
that separate baseline test copy; the frozen measurement baseline is unchanged.

| Full batch file workflow | Before median records/s | After median records/s | Qualification |
| --- | ---: | ---: | --- |
| shared Memory P1 | 1,156,635 | 1,259,012 | Local +8.9%; before/after spread 9.34%/2.76% |
| shared Memory P4 | 1,112,450 | 1,138,738 | Inconclusive |
| SPSC Memory P4 | 1,098,274 | 1,205,207 | Inconclusive |
| SPSC Mmap P4 | 1,143,207 | 1,165,445 | Inconclusive |
| SPSC Mmap P4 prepared | 1,194,094 | 1,159,759 | Inconclusive |

The 100 processes use 100K measured records plus 1K warmup, sampled/batch
separately and five alternating before/after pairs on CPUs 0/2/4/6/8/10. Every
physical JSON record is independently validated: 10,100,000 complete records,
accepted=written, pending/drop=0. Reported throughput includes final flush,
shutdown and object cleanup. It retains full JSON, system timestamps, queue and
file budgets; memory/mmap and inline/prepared cases remain separate.

This local P1 result does not establish broad speedup or industry leadership.
Per-case min/max, noisy p99/p99.9 and all slow trials remain in `comparison.json`.
Prepared mmap did not show a measured benefit in this run. The earlier cross-
library table has a different source snapshot; it must be rerun after cumulative
changes to claim a new C++ ranking.

`before-source.tar.gz` preserves the complete original source and benchmark.
`provenance.json` records both source and binary hashes. Both application and
library used ReleaseFast with frame pointers, and the comparator source stayed
unchanged through measurement. No CPU governor or host policy was modified.
