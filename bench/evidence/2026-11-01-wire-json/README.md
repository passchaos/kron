# Fused wire-to-record consumer path

The checked consumer previously decoded a v4 payload into an `Event`/`Field`
tree and then traversed that tree again to render JSON. This round adds a
fused path for the common single-route JSON shape:

- The payload is the current self-contained v4 codec.
- Exactly one route is selected, its format is JSON, text or logfmt.
- The message is not deferred (no template and no format arguments).
- Attribute values, including nested arrays/groups, are validated by the
  checked wire parser; nested descriptors use the caller scratch arena.

The fused renderer parses the header, scope/message/trace/span/source and
attributes once, writing the same JSON/text/logfmt record into the caller-owned scratch
buffer. Every value tag is validated by the checked wire parser and top-level
keys are checked for duplicates before the record reaches a sink. A corrupt
payload returns its decoder error; an unsupported shape returns
`error.Fallback`, and the normal decode-and-encode path remains authoritative.
No journal format, public encoder, validation boundary or route behavior
changed.

## Correctness

- `encoder/wire_json.zig` compares the fused bytes against
  `codec.decode` + `encoder.encodeWithTime(.json)` for a flat event covering
  unsigned/signed/string/bool/float/duration/timestamp/null, trace, span and
  source. Bytes are identical.
- A nested group/array event is also compared byte-for-byte; nested values use
  the scratch arena and the same duplicate-key/depth/node validation.
- Text and logfmt records are compared byte-for-byte against the decoded
  encoders for a nested event with source, trace and array values.
- Deferred messages return `error.Fallback`; the normal path handles them.
- 10,000-record SPSC-memory text and logfmt file workflows both reported
  status ok, 10,000 written, pending=0 and 11,000 physical lines each.
- Full `verify-local` passed 81/81 steps and 510/510 tests, including the
  nested and text/logfmt fused tests
  (`verify-local-releasefast-specialized.log`).
- A 10,000-record SPSC memory workflow passed the independent oracle with all
  11,000 physical records (including warmup) verified.
- 100 alternating full-file trials validated 10,100,000 physical JSON records;
  every trial had accepted=written=100,000 and pending/drop=0
  (`workflow-results.jsonl`, `comparison.json`).

## Whole-process PMU

Five alternating pairs, complete ReleaseFast JSON file workflow, fixed CPUs,
100,000 records plus 1,000 warmup.

| Case | Instructions before → after | Change | Status |
| --- | ---: | ---: | --- |
| SPSC memory P4 batch | 1,154,112,566 → 1,085,502,232 | −5.94% | stable |
| Async memory P1 batch | 1,040,240,533 → 975,795,731 | −6.20% | stable |

Instruction relative spread is 0.8%–1.2% on both sides. Cycles and throughput
remain inconclusive because the host load average was about 100. The fused
path removes the intermediate `Event`/`Field` materialization and one tree
traversal; it is not a cross-library ranking.

## Complete file workflow

100 alternating trials validated 10,100,000 physical JSON records. Every
completed trial had accepted=written=100,000, pending/drop=0 and the original
queue/file budgets. The host load average was about 100, so every throughput
group exceeded the 10% CV/spread gate and all bootstrap intervals overlap:

| Batch case | Before median records/s | After median records/s | Change | Status |
| --- | ---: | ---: | ---: | --- |
| async memory P1 | 1,774,592 | 1,201,778 | −32.3% | inconclusive |
| async memory P4 | 1,554,678 | 1,487,933 | −4.3% | inconclusive |
| SPSC memory P4 | 1,583,934 | 1,361,254 | −14.1% | inconclusive |
| SPSC mmap P4 | 1,391,135 | 1,875,912 | +34.8% | inconclusive |
| SPSC mmap P4 prepared | 1,558,402 | 1,396,801 | −10.4% | inconclusive |

The negative medians and the large positive mmap median are retained as noise;
none is used to claim a throughput speedup. The stable PMU instruction
reduction (measured on the JSON route) and the 10.1M-record output verification
are the evidence for this round. The prepared-schema case uses schema payloads
and therefore exercises the fallback path, not the fused path. Text/logfmt
runtime workflows are output-verified but were not separately PMU-qualified.

## Boundaries

This path is intentionally narrow: single JSON/text/logfmt route, current v4
inline payload, non-deferred message; nested attributes are supported through
the scratch arena. Legacy payloads, schema references, templates/format
arguments, multiple routes and binary routes continue through the existing
path. The public encoder still validates independently, and the fused
path writes only into a scratch buffer until the whole record has been
validated.

`before-source.tar.gz`, `implementation.patch`, `provenance.json`, the
before/after binaries and all raw rows preserve the exact implementation.
