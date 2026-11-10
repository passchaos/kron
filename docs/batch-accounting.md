# Intra-batch durability decisions and written accounting

When the background processes a batch, the configuration group is already held
immutable by a protected View. Each group now precomputes a bitmap of routes that
are required and have `reclaim_after = durable`; records use their route_mask
with this bitmap to determine the acknowledgement boundary. The result is used
only for the current batch and does not change configuration publication, file
format, or individual sync calls.

If any required route demands durability, the event's complete route_mask is
still included in the original durable barrier, confirming all required targets
selected by that event. A best_effort route does not independently change the
journal acknowledgement boundary; its write/flush/sync behavior remains handled
by the delivery pipeline. The record's acknowledgement boundary is stored in a
fixed array instead of rescanning routes during reclamation; the current
coalescing window is at most 256 records, and a configuration group still has at
most 64 entries. See [coalesced delivery](coalesced-delivery.md).

Completion counts are aggregated per contiguous channel: a record is added to a
temporary count only after both `journal.releaseAfter` and configuration record
pin release succeed. A channel switch commits the previous segment; the remaining
count is committed before batch completion and progress publication; error exits
commit the already-acknowledged prefix through `defer`. The final atomic update
still uses `fetchAdd`, so concurrent sync/fallback increments to the same counter
do not lose counts. Thirty-one complete records on the same channel reduce 31
written RMWs to one.

## Acknowledgement and observation boundaries

A follow-up attempted to aggregate configuration record-pin release: after each
journal record was completely reclaimed, one `fetchSub` per snapshot/channel
combined the independent pin/written counts and the unified acknowledgement
count. Two versions each ran 100 complete-file trials and 20 long-workflow PMU
trials, verifying 32.24 million JSON records with correct semantics. Neither
version qualified for a complete-throughput improvement, and several Memory
negative medians plus high spread were retained; production withdrew the
candidates and still releases record pins individually. Atomic-count reductions
cannot replace complete-workflow performance evidence.

The retained fault regression was extended to shared/SPSC: retire the old
configuration before delivery, flush three outputs, then corrupt the second
record and confirm written=1, pending=2, and that the watermark advances only
across the successful prefix. After SPSC detach, the old configuration still has
two record pins; collecting after releasing the check View still fails, the old
lease is not released, and only Runtime destruction releases it once. This test
covers real background/resource lifetime without changing the production
protocol.

The journal still performs complete per-record CRC checks, ordering checks, and
written/durable reclaim. Each slot's release, watermark, schema reference, and
recovery protocol keep the original implementation; no batched journal
reclamation interface was introduced. A batch only aggregates counts and cannot
include later-failing records in the successful prefix.

Concurrent health reads individual atomics for observation, not as a
transactional snapshot. The written count may briefly lag the journal watermark
within a batch and is updated before the batch ends; error returns also retain the
actual acknowledged count. Explicit flush/shutdown remain the confirmation
interfaces: they acquire the original delivery lock and observe completed batch
counts before returning. "The health queue is empty" is not a substitute for the
barrier.

This change adds a count object on the consumer stack, allocates no heap memory,
and adds no producer counting step. Each batch configuration group gains one
derived u64 bitmap, and the original record route_mask array is replaced by a
smaller acknowledgement-boundary array. All resources remain owned by the
original Runtime; temporary statistics must not escape the batch.

## Verification

- 1,024 route masks cover required/best_effort, written/durable, the 64th route
  bit, and mixed targets, compared item by item with the original scan method
  and checked against the complete barrier mask.
- Contiguous channel changes, empty flush, repeated flush, and updates inserted
  by another owner are counted exactly; a real concurrency test confirms batch
  accounting composes with synchronous counters across 41,000 updates.
- Thirty-one actual shared/SPSC records in one batch publish written accounting
  once; the old implementation is rejected by a counting regression that expects
  31 RMWs.
- After all three outputs complete, the second record awaiting reclamation is
  deliberately corrupted to verify written=1, pending=2, a journal watermark that
  crosses only the successful prefix, and remaining record pins that are not
  released.
- Existing mixed-configuration sink failures, View release, lease retention,
  deadline, and cross-process recovery tests continue to run.

Current-source Debug and ReleaseSafe targeted tests pass 13/13, including an
import fixture and six substantive tests. Complete ReleaseFast `verify-local`
passes 76/76 build steps and 478/478 Zig tests, including real SIGKILL,
configuration transactions, independent package consumption, and native Linux
host self-checks. The final ReleaseSafe gate passes 22/22 build steps: nine
targets actually generate public-path objects, and configuration, transactions,
deadline, and real file faults pass 37/37. Reducing atomic operations and route
scans does not automatically make every workload faster.

## Complete-workflow measurement

Five configurations each ran batch and sampled modes in separate processes, five
before/after pairs, for 100 trials total. Each trial used 100,000 measured records
and 1,000 warmup records, verifying 10.1 million complete JSON logs including
fields, messages, timestamps, scope, event identity, and counts; output file
SHA-256 and physical byte counts were also stored. Application and kron module
were ReleaseFast with frame pointers, fixed to CPU 0/2/4/6/8/10, alternating
before/after order. Before was the frozen source after configuration View reuse
but before this round's accounting aggregation and durable mask.

| Batch mode | Before median records/s | After median records/s | Median change | This round |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 | 1,272,767 | 1,252,057 | −1.63% | inconclusive; after cross-round spread about 31.2% |
| shared Memory P4 | 1,221,402 | 1,226,962 | +0.46% | inconclusive; before cross-round spread about 19.4% |
| SPSC Memory P4 | 1,192,114 | 1,173,534 | −1.56% | inconclusive; after cross-round spread about 14.6% |
| SPSC Mmap P4 | 1,220,463 | 1,205,500 | −1.23% | passes this host's noise threshold; intervals still overlap |
| SPSC Mmap P4 prepared | 1,230,803 | 1,273,351 | +3.46% | passes this host's noise threshold; intervals still overlap |

`stable_local_measurement` only means that before/after CV and relative spread
are both below 10%; it is not statistical significance or a cross-platform gain.
The last two groups' trial-bootstrap 95% median intervals still overlap, so no
stable end-to-end speedup is claimed; the ordinary Mmap decrease and all slow
values are retained. Most sampled producer quantiles remain inconclusive;
prepared p50 median was 493 → 501 ns and p99 16,591 → 16,538 ns, which does not
establish a tail improvement.

The completion boundary for these trials is written file flush, shutdown, and
object cleanup. Durable-route precomputation is separately verified by 1,024 masks
against the original scan oracle; this written throughput is not fsync
performance. Earlier Quill/Foundation numbers came from older sources; any
cumulative cross-library ranking would require a same-round re-measurement.
