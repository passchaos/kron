# Decimal record output and direct complete-string escaping

The unpadded integer path now uses a bounded stack decimal renderer, writing
the resulting digits with one writeAll. Native magnitudes use digit pairs;
i128/u128 magnitudes above u64 use 10^19 chunks, including padded zero tails.
Signed minima use unsigned magnitude. Record metadata and scalar values use
this path; deferred width/precision/base formatting and floats retain the
general formatter. JSON integer string boundaries are unchanged.

Complete strings call the existing QuotedWriter.consume directly, removing an
unbuffered writer drain dispatch. Deferred formatting still streams through the
same UTF-8 state machine. No scratch-sized complete message, length prepass,
writer capacity relaxation, journal protocol or resource-budget change is made.

Three new decimal tests compare all 65,536 u16 values, native extrema, wide
decimal/binary boundaries, zero chunks and 2,048 randomized u128/i128 pairs with
the standard formatter. The public encoder differential independently imports
frozen/candidate modules: 12 complete records and 16,486 fixed-buffer prefixes
are byte identical. A generic writer accepting only 1/3/7 bytes and failing at
every budget has 49,494 identical success/failure prefixes, without another
callback after an error. Final Debug/ReleaseSafe scoped checks pass 26/26 each.

The 100 full-file workflow trials validate every physical JSON record: 10.1M
records, 100K measured+1K warmup each, five alternating before/after pairs for
five memory/mmap, shared/SPSC, P1/P4, inline/prepared cases. System timestamps,
256-slot/512-byte payload budget and 64KiB file buffer remain the same. Throughput
includes written flush, shutdown and object cleanup; lifecycle reports also
include initialization/preparation. All five batch median changes are positive
(+24.52%, +6.79%, +3.16%, +0.21%, +8.03%), but every throughput qualification is
inconclusive with overlapping trial-bootstrap intervals. All slow values remain.

The first scalar5/nested20/wide5 probe overlapped compilation of the full-workflow
candidate binary and is not isolated-time evidence. Its raw data is retained.
A second serial CPU0 probe capture has no local build/gate overlap: 10 processes,
300K records per case, full-output hashes/bytes identical. Whole-process user
instructions fall 18.50% and cycles 27.14%, both within the 10% CV/spread threshold;
all per-case wall-time qualifications remain inconclusive. It includes input
mutation and hashing, and cannot predict file throughput.

Ten additional P4 SPSC-memory full file workflows validate 3.01M records, 300K
measured+1K warmup each. Whole-process user instructions fall 6.22% with approximately
0.02% spread on both sides; cycles/task-clock median changes are −3.37%/−3.79%
but remain inconclusive. Complete throughput median rises 1.115M→1.285M (+15.31%),
also inconclusive. Software counters and all slow trials remain in the report.

research-sources.json records Foundation DefaultFormatter and Zig Writer source
hashes. The initial profile covers the former scalar/nested probe and is about
1K user-core-PMU samples, including startup and output consumption. Its original
binary identity is separate from the later wide-value probe; symbol percentages
do not establish whole-file gain.

before-source.tar.gz preserves the exact old sources and unchanged workflow
driver. implementation.patch identifies the two modified modules and added
decimal.zig. before/after-provenance.json and per-row hashes identify binaries.
The guarded implementation/driver sources are unchanged through capture.

measure-executed.py preserves the script used for the full workflow. It inherited
the prior experiment's descriptive scope string; comparison.json corrects that
description with an explicit scope_note, and measure.py corrects it for replay.
Trial rows, numerical metrics and hashes are unchanged by that correction.

Final verification and source identities are recorded in qualification.json.
The experiment is written/file completion, not fsync/power-loss qualification.
Cross-platform object compilation is separate from non-Linux native execution.
The older Foundation/Quill table retains its archived source snapshot.
