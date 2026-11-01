# Schema shape checks in the validating size visitor

Baseline `cd00f1f`. `encodedReferenceSize` used to traverse the complete tree
for validation and wire size, then traverse top-level fields/arguments again
for schema key/type checks. The candidate observes those keys/types from the
existing ValueValidator Field visitor, storing the first shape error without
ending the validation traversal. Nested keys continue to count in wire size;
top-level keys are still encoded only in schema metadata. Metadata shape is
checked before the stored descriptor error, then level, then wire overflow.
No output buffer is touched before all those checks pass.

This keeps complete-tree errors (cycle/duplicate/depth/node budget) before
schema/level/overflow errors, including an earlier wrong key and a later invalid
argument. The field and argument schema iterators remain independent. Errors
from malformed borrowed schema descriptors retain their original precedence:
metadata mismatch precedes descriptor error, and a later tree error precedes
both. Public encoders, runtime admission/redaction, canonical ready-schema
lookup, reserve/commit/reclaim reference checks, CRC, pins and delivery are
otherwise unchanged. No external unchecked credential, cached mutable value,
allocation or protocol/layout change is added.

## Semantic evidence

Two new module tests exercise wrong scope/message/count/key/type, malformed
schema descriptors, later cycle/duplicate, unused arguments, invalid level and
synthetic unrepresentable lengths. Rejected payload buffers stay untouched.
Existing reference size shared node/depth/duplicate and validation-first
overflow tests remain. Directed Debug/Fast reference scopes each pass29 tests;
the larger Safe schema/reference scope is separately recorded.

`differential.zig` compiles the frozen baseline and candidate as independent
modules. Across4096 generated cases,342 successes have exact payload bytes
and3754 rejections have matching errors and untouched destination buffers.
Cases include nested/all-scalar shapes, argument/schema mismatch, cyclic and
duplicate descriptors, output capacities, metadata error order and level.
This supplements the owning current/historical decoder/schema matrices;
it does not replace broad runtime correctness or performance qualification.

## Complete-file measurements

The public fullJSON harness keeps system time, five numeric attributes,
256 queue slots/512-byte payloads,64KiB file buffer, default4 consumer quanta,
fixed CPU0/2/4/6/8/10 and actual portable backend. Every file is checked by
the independent owning oracle; producer/consumer/final written flush/shutdown/
cleanup throughput is separate from initialization/preparation and sampled
call tails. No strict media durability is requested for performance trials.

`measure.py --pmu` takes40 complete300k-record trials for schema SPSC Memory/
Mmap P4, schema shared Memory P1, and inline SPSC Memory P4 as a control.
`measure.py` uses320 complete100k-record trials across Memory/Mmap, shared/
SPSC, P1/P4, inline/schema and batch/sampled, five pairs. Frozen source/binary
guards preserve the completed candidate; all positive/negative observations,
CV/spread/bootstrap and failures remain. User PMU includes setup and excludes
kernel work. Source-level traversal savings alone cannot establish faster
complete logging or a new Foundation/spdlog ranking.

## Initial PMU capture limitation

The first40-trial PMU capture verifies12,040,000 physical records but its
first pair may overlap the end of the related Safe test. It is retained as
limited initial evidence. A fresh complete40-trial PMU capture is recorded
as pmu-clean, after all local gates have ended. The initial schema instruction
medians increase about0.44%–0.47%; inline control is unchanged. These initial
results are not used as clean promotion evidence.

The clean40-trial PMU capture verifies another12,040,000 physical records.
Schema SPSC Memory/Mmap user instructions increase0.463% in both groups with
passing CV/spread and non-overlapping intervals; shared Memory P1 is+0.543%,
with overlapping intervals. Inline control is within0.01%. Cycles and all
throughput comparisons in that capture are inconclusive. A separate complete
file capture tests whether a remaining runtime benefit outweighs this cost.

## Decision: rejected

All400 completed file/PMU trials independently verify **56,400,000 physical
JSON records**. The initial40-trial PMU has the possible local-gate overlap
noted above and is excluded from clean performance qualification. Clean
formal capture is360 trials and44,360,000 verified records, including the
independent40 PMU and320 full-file trials. No sources, builds or tests from
this task change/overlap those clean captures. Source/archive/binary identities
and every saved row/distribution are audited in measurement-audit.json.

The complete320-trial file capture has inconclusive throughput comparisons in
every group. Schema shared Memory P1/P4 median changes+3.11%/−1.81%, shared
Mmap P1/P4−3.73%/−6.66%, SPSC Memory P1/P4−1.10%/−2.21%, and SPSC Mmap
P1/P4+3.50%/−1.18%. These are noisy medians, not proof of either improvement
or regression. The unchanged inline Mmap control also has large spread and
median movements; those cannot be causally assigned to this schema-only change.
No local output-format, metadata or resource budget was altered to change rank.

Most schema call tails are inconclusive. SPSC Mmap P4 p99.9 median falls
333609→327964ns within the local repeatability budget, but intervals overlap;
Memory P4 is338320→341363ns and inconclusive. All slower/positive observations,
percentile distributions and bootstrap limits remain in the raw reports.

The candidate reduces an apparent extra loop but adds iterator/error state to
the validating visitor; clean PMU shows repeatable SPSC schema instructions
increase0.463%, with no complete-workflow gain qualified. That evidence does
not justify production promotion. `src` is restored exactly to `cd00f1f`,
keeping its original schema measurement/validation and552-test/nine-platform
qualification. The whole candidate and its two substantive priority tests remain
in after-source.tar.gz. Broad runtime/platform gates are not rerun for a rejected
candidate. Future schema work should attack separately proven duplication or
expensive canonical checks while retaining complete-tree-first error order.
