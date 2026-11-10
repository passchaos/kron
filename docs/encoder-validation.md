# Validation reuse for complete-record encoding

The public text, JSON, and logfmt `encode` entries keep the same signatures and
output layout. Each call first validates attributes and format_args completely,
sharing the 256-value-node budget, 8-level container depth, and duplicate-key
rules; only after success does it enter the module-private recursive output.
Field values are no longer validated one by one, and fixed-type metadata uses the
same private output method.

The complete encoding entry does not return a validation credential, does not
export a value writer that bypasses validation, and does not allow a validation
result to be retained for another call. Standalone `common.value` still fully
validates its input, and nested arguments in deferred formatting still render
through this safe entry. All descriptors, keys, and borrowed bytes must remain
valid and unchanged for the entire encoding call, and Writer callbacks must obey
the same borrowing condition.

The checked wire parser's `valueWith(receiver)` reuses the same tag, length, node,
depth, nested, duplicate-key, and arena checks, then calls back with a comptime
tag and typed payload; public `value()` still constructs the original `Value`,
and arrays/groups are fully parsed before callbacks. The fused renderer therefore
skips intermediate `Value` and generic second dispatch without relaxing
validation or error precedence; see
[wire scalar notes](performance-hotspots.md) for differential and full-gate
details.

Structurally, UTF-8 streaming escaping, hex, and reversible key representation
are split into `escaping.zig`; `common.zig` owns complete-record validation, the
three layouts, and private value output, while json/text/logfmt modules keep
public entries and their golden tests. Independent format entries select layout at
comptime and add no runtime format dispatch. There is no production dependency,
heap allocation, complete-message scratch, or new wire format.

This corresponds to Foundation formatter's direction of reducing duplicate work
and centralizing processing. The current code keeps the original
`std.Io.Writer` write order and output fragments, without two-pass output-length
computation or cached format templates; Foundation's calendar-date cache does not
apply to JSON output that preserves full `timestamp_ns`.

## Correctness evidence

- Actual public text/JSON/logfmt entries cover all 11 value tags, nested
  containers, and unused format arguments; a record with 14 nodes validates
  exactly 14 times. The same test rejects the old implementation at 27
  traversals; the test uses a separately copied old source and does not modify the
  measurement baseline.
- Standalone `common.value` still validates valid complete trees and produces
  zero output when duplicate keys fail. Original cycle, depth, duplicate-key, and
  shared attributes/arguments budget tests continue to cover every encoder format.
- An independent module comparison between frozen old source and current source
  matches 12 complete text/JSON/logfmt outputs byte-for-byte; 16,486 short-buffer
  capacity cases match errors and written prefixes. Inputs include integer
  extremes, NaN/Inf/subnormal, malformed UTF-8, reversible keys, source/trace,
  secret, nested values, and cross-argument UTF-8 joining.
- Original JSON parsing/goldens, logfmt nesting, streaming escaping, long messages,
  and capture deep-copy tests continue to verify behavior. Format errors and
  underlying Writer failures still return the original errors; "zero output for
  invalid trees" does not mean zero output for arbitrary I/O failures.

A local reduction in traversal count cannot replace end-to-end throughput
evidence or a cross-library ranking.

Current Debug/ReleaseSafe encoding-targeted tests pass 23/23 each; complete
ReleaseFast `verify-local` passes 76/76 build steps and 480/480 Zig tests,
including current/historical format decode matrices, independent package five-mode
and Linux host self-checks, configuration replacement, fixed/random SIGKILL, and
query tools. Final ReleaseSafe passes 16/16 build steps: nine targets actually
generate public-path objects, and real file delivery plus configuration
integration pass 18/18. Non-Linux device execution is still not qualified.

## Complete workflow and slow-value investigation

One hundred complete-file comparisons verified 10.1 million logs one by one,
including final written flush, shutdown, and object cleanup, while retaining all
fields and system timestamps. Sampled/batch ran five before/after pairs per
configuration with CPU 0/2/4/6/8/10 fixed.

| Batch mode | Before median records/s | After median records/s | Median change | Qualification |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 | 1,088,241 | 924,220 | −15.07% | inconclusive |
| shared Memory P4 | 1,188,972 | 1,226,172 | +3.13% | inconclusive |
| SPSC Memory P4 | 1,199,412 | 923,631 | −22.99% | inconclusive |
| SPSC Mmap P4 | 1,190,182 | 1,121,010 | −5.81% | inconclusive |
| SPSC Mmap P4 prepared | 1,222,309 | 968,104 | −20.80% | inconclusive |

Every throughput group had at least one side's CV or spread above 10%, and all
trial-bootstrap median intervals overlapped. The candidate's clear slow values
cannot be removed, and a lower node count alone does not establish an end-to-end
improvement; SPSC Memory after runs were 0.884/1.233/1.224/0.903/0.924M records/s.

To investigate the slow values, five additional encoding probes fixed to CPU 0
each encoded 300,000 records with five scalars and 300,000 with 20 nested scalars
as JSON per process, varying values per record and including complete output in
Wyhash; before/after checksums and byte counts matched. Whole-process user-space
core PMU instructions fell 14.27% and cycles 17.90% by median; both wall-clock
measurements still failed the noise threshold. This covers encoding, value
updates, and output consumption, not journal, file I/O, or background delivery.

Five additional 300,000-record trials of the most clearly negative P4 SPSC Memory
complete file workflow verified another 3.01 million logs. Whole-process user
instructions fell 2.55% by median, while cycles rose 2.62% and task-clock 2.15%;
before cycles/task-clock cross-round spread was about 17.6%/19.7%. Complete
throughput median rose from 1.200M to 1.265M (+5.39%) and remained inconclusive.
Software context-switch/migration counts also varied widely, so the original slow
values cannot be attributed to a single cause.

These results support a real reduction in encoding work but do not confirm stable
complete-log speedups or rule out regressions on specific workloads. The
implementation and all negative results/CPU counts were retained for verification
in a more stable environment; standalone probe cycle changes are not converted
into complete-file throughput. The measurement boundary is written, not
fsync/durable. Any cumulative cross-library comparison would require a same-round
re-measurement.
