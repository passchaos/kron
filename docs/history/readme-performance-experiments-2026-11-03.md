# README performance experiment snapshot (2026-11-03)

This snapshot preserves the experiment narrative, numbers, and evidence pointers
from the top of the README before reorganization. Each result is bound to its
source revision and measurement window; see
[current acceptance status](../implementation-status.md) for current capabilities
and unfinished goals. Measurement directories and cross-library harnesses have
since been removed, so links are omitted.

The journal three-entry specialization candidate was withdrawn at the static
threshold: forcing tail calls was limited by backend, error-set type, and
aggregate-return ABI; the inline variant preserving the public interface passed
default Debug/Safe/Fast/generic regressions but added return temporary copies,
increased the SPSC stack frame, and added 832 bytes to the drain stack frame. The
experiment had no performance trial; production Journal stayed unchanged, and the
next fixed-capacity exact arithmetic still required independent verification.

Fixed-capacity reciprocal arithmetic passed an independent proof over the full
u64 range and 200,000 random/boundary tests, using two multiplications and one
correction in practice, but eight-capacity queue controls had 13/16 stable
regressions and the Journal object grew 64 bytes; the candidate was withdrawn
without entering complete-log comparison. Eight dual-topology complete-workflow
profiles of the current production baseline then verified 8.008 million JSON
records; this sampling only located hotspots and did not provide a new speed
ranking.

Two four-byte ASCII tail-scanning candidates (global and JSON attribute prefix)
were withdrawn: six-byte keys had a local gain, but short strings, longer keys, or
UTF-8 control cases had stable regressions. Production kept the original eight-byte
scan and Writer output order; `test-escaping-tails` was added to cover short-tail
first matches, adjacent bytes, and failure prefixes of five public operations.

Both TLS inactive-slot cleanup and compact Frame candidates were withdrawn because
of complete-workflow regressions; production kept the original optional decision
and full slot cleanup. 880 comparisons verified 88.88 million complete JSON
records; the compact representation saved 1 KiB of TLS array but still had six
E-core throughput regressions and did not qualify. Five new lifecycle regressions
covered reuse, callback nesting, 64-level stack, thread isolation, and complete
generation/channel boundaries.

Three CRC 16-byte remainder continuation candidates (unconditional dispatch,
zero-remainder guard, and block-end loop) were withdrawn. Dual-topology 54 lengths
and two header shapes produced 32,400 timed batches with identical checksums, but
each version had E-core control regressions; fewer loop instructions or a 241-byte
local gain did not qualify. Independent bitwise/GF2 message and seed basis
vectors, arbitrary seed/alignment cases, and 45 zlib fixed vectors were added.

A direct weighted-folding CRC remainder candidate passed independent math and
target verification, but zero-remainder cases actually increased dispatch and
constant-read cost, failed the preset static threshold, and was withdrawn without a
performance trial. A shared reservation quotient/remainder reuse reduced two DIVs
to one on the success path, but after 530 complete comparisons verified 134.53
million JSON records, long workflows did not obtain a stable gain and SPSC p50
control had negatives; the production candidate was withdrawn. Coordinate-boundary
regressions and all results were retained.

Later power-of-two reservation, creation-time caching, and complete Journal
coordinate candidates were also withdrawn: the first two had local instruction/
latency gains but complete workflows still had throughput or schema control
negatives; complete coordinates removed five DIVs from the default consumer but
regressed arbitrary capacities, and retaining the original CRC call boundary still
did not qualify. Production kept the original Journal math, and
`test-journal-coordinates` was added to verify shared/SPSC eight-capacity wrap,
crossing 2^32/sequence limits, and rejection/preservation of CRC-valid but
wrong-generation records.

Two default clock callback and internal inline candidates were withdrawn because
of complete-workflow negatives; production kept the original `std.Io` injection
path. 960 comparisons verified 96.96 million complete JSON records; fewer calls
and Io copies did not prove an overall gain. Callback switching, Io argument
snapshots, nanosecond boundaries, and call-time regressions were retained.

The shared written cursor now publishes progress with a release RMW, paired with an
acquire read in `writtenTarget()` for clear write visibility; the original maximum
algorithm, CRC, recovery, and queue budget were preserved. Two ordinary store
performance candidates were withdrawn because of complete-workflow regressions;
880 comparisons verified 88.88 million JSON records, and the cross-library ranking
was not updated. New public tests covered the live cursor, failure prefixes, and
pre-join publication observation.

The shared queue updated `high_water` only on peak growth; the direct CAS loop
retained the exact maximum, default CRC, and live written. Complete Safe/
distribution/recovery/nine-target gates passed 155 steps; a one-million-record
recheck confirmed no regression but did not obtain a general throughput gain. The
latest dual-topology Foundation comparison verified 32.32 million JSON records:
P-core led spdlog in 7 groups and tracing in 4, while E-core still had a clear gap;
the target was not met.

Four short-field-name comparison candidates were withdrawn: default complete
workflows had local gains, but 1–3-byte and long-key inputs had stable regressions.
Production kept the original comparison and added a public byte oracle, real guard
pages, and error-order regressions.

The current CRC uses three-operand PCLMUL on AVX targets, removing nine register
copies from the actual update function and reducing complete PMU instructions by
about 0.7%; default CRC, three checkpoints, and recovery were preserved. Complete
Safe/distribution/SIGKILL/nine-target gates passed 151 steps. The latest
dual-topology Foundation comparison verified 32.32 million JSON records: P-core led
spdlog in 5 groups and tracing in 5, but E-core still lagged and one P-core group
lagged tracing; the target was not met. A typed-capture candidate was withdrawn
because of complete throughput regressions; boundary regressions and evidence were
retained.

Earlier Runtime internal submission reduced Binding/Event copies while preserving
the public snapshot and validation; the complete gate passed 151 steps. Default
PMU four-group instructions fell about 0.7%; the same-source dual-topology
Foundation comparison verified 32.32 million JSON records, with P-core leading
spdlog in 4 groups and tracing in 2, while E-core still did not meet the target.

Earlier source retained direct JSON attribute-prefix output and predicate route
bitmaps; the complete gate passed 149 steps. Final file PMU four-group instructions
fell about 3.0%, cycles and complete throughput were mixed; 400 application trials
verified 4.8 million requests and 2.21 million complete logs. The dual-topology
320-trial Foundation comparison still did not fully overtake either combination.

The current implementation retains IEEE CRC four-lane parallel merging; complete
ReleaseSafe/distribution/SIGKILL/nine-target gates passed. The dual-topology
same-round Foundation comparison verified 32.32 million JSON records, with P-core
leading tracing in 6 groups and spdlog in 3, the rest inconclusive, and E-core
still clearly behind.
