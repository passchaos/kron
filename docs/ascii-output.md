# Printable ASCII scanning and output

In the current complete-JSON file-workflow user profile, CRC is about 26% and
quoted/consume about 6%. This round keeps every CRC checkpoint and only reduces
scanning and intermediate Writer work for common scope, message, and field keys.
Go `encoding/json` and Rust `serde_json` also copy safe-byte runs in batches; this
library keeps its existing DEL, malformed-UTF-8, cross-argument fragment, and
reversible-key policies without copying upstream code.

A complete string first searches for the first byte that needs escaping or UTF-8
handling. If it is entirely printable ASCII without quotes/backslashes, the
implementation writes the opening quote, original bytes, and closing quote
directly; ordinary JSON keys are also proven UTF-8-valid by the same test and do
not run a separate generic UTF-8 validation. Keys beginning with `$bytes:` still
use the reserved reversible-hex rule and cannot take the ordinary-key fast path.

The scanner checks the first byte. UTF-8-heavy or control-character input enters
the original byte state machine immediately; other contiguous runs use a bounded
8-byte load and byte mask, returning to the original implementation at the first
special byte. The 8-byte read never crosses the caller slice and is explicitly
little-endian to preserve first-byte order; short tails keep the original scalar
rule. A cross-byte borrow mask can mark a position adjacent to the first match, so
only the first match is used and the mask is never treated as an exact
per-byte classification bitmap.

The initial implementation did not check the first byte first and showed about a
+5.7% median for Unicode messages in a six-input probe. That candidate and data
were retained, and an early return fixed it. In the final identical probe, Unicode
median was about −2% with overlapping intervals; this small change is not claimed
as a stable gain. Escape-heavy messages were about −5.8%, long ASCII about −38%,
and nested numbers about −16.6%. These probe results are for reviewing the
encoding path, include input changes and complete-output hashing, and do not
represent file-log throughput.

## Correctness and cost comparison

- 1,835,008 adjacent byte/position/alignment combinations match the independent
  scalar rule; short/empty slices, spaces and control characters, word
  boundaries, and 2,048 random inputs are also covered.
- Random inputs generate a reference byte-by-byte with the original state
  machine; complete strings and chunked streaming output are compared
  byte-for-byte; original UTF-8/JSON/logfmt and source/nested tests remain.
- Frozen old and current modules each call the public encoder; 12 complete
  records and 16,486 fixed Writer prefixes match. A generic Writer accepting only
  1/3/7 bytes at a time keeps the same prefixes across 49,494 complete/failure
  budgets, with no extra callbacks after an error.
- Initial and final six-input probes were retained separately; the final ten
  processes verified 6 million output hashes/bytes. Whole-process user
  instructions fell 10.68% by median and cycles 8.06%, covering numeric/nested/
  wide, long ASCII, Unicode, and escape-heavy messages; aggregate CPU counts
  across inputs do not replace per-workload cost or complete file workflows.

The complete workflow keeps JSON fields, system timestamps, Memory/Mmap,
shared/SPSC, prepared shapes, queue/file buffer budgets, and written flush,
shutdown, and cleanup endpoints.

## Complete-file results

One hundred same-condition before/after trials, each with 100,000 measured
records and 1,000 warmup records, verified 10.1 million complete JSON records.
Batch and sampled ran in separate processes, with five alternating before/after
pairs per configuration. CPU was fixed to 0/2/4/6/8/10, and all output hashes,
physical bytes, accepted/written/pending/drop, and stage times were retained.

| Batch mode | Before median records/s | After median records/s | Median change | Qualification |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 | 1,337,151 | 1,415,928 | +5.89% | inconclusive |
| shared Memory P4 | 1,338,047 | 1,410,953 | +5.45% | inconclusive |
| SPSC Memory P4 | 1,360,909 | 1,330,091 | −2.26% | inconclusive |
| SPSC Mmap P4 | 1,327,848 | 1,400,393 | +5.46% | inconclusive |
| SPSC Mmap P4 prepared | 1,321,728 | 1,442,009 | +9.10% | inconclusive |

Every throughput group had at least one side's CV or spread above 10%, and
trial-bootstrap median intervals still overlapped. Positive medians cannot claim a
stable gain, and the SPSC Memory decrease or other slow trials cannot be removed.

Five additional complete P4 SPSC Memory PMU trials of 300,000 records verified
another 3.01 million logs. Whole-process user instructions fell 5.65% by median
with stable both-side counts; cycles fell 5.38% and task-clock 5.45%, but the
variance threshold still failed. Throughput median rose from 1.308M to 1.391M
(+6.30%) and remained inconclusive. This group has a different design from the
100,000-record trials, so medians cannot be merged or subtracted as independent
stage costs.

This supports a real reduction in complete-pipeline CPU work but does not
establish stable end-to-end speedup, rule out regressions on every workload, or
change an existing cross-library ranking. User-space PMU does not count kernel I/O
work, standalone encoding probes include hashing/input updates, and file
measurement confirms written, not durable/fsync.
