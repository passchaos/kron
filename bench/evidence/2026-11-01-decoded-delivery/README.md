# Decoded delivery validation proof

The checked consumer path decoded a journal payload (which validates the wire
tree, node budget, depth, duplicate keys and lengths) and then the output
encoder validated the same decoded tree again. This round removes that second
full-tree pass only for events that a checked decoder proved.

- `Event.tree_validated` is an internal provenance hint, false by default.
- `codec.decode` and `schema_codec.resolve` set it only after completing their
  complete wire-tree validation.
- `encoder.common.encodeDecoded` is an internal delivery entry point. It takes
  the normal validating path when the hint is false, and the already-private
  renderer when true.
- Public `encoder.encode` / `encodeWithTime` ignore the hint and always
  validate. The new public test constructs an invalid event with
  `tree_validated = true` and confirms the public encoder still fails before
  writing a byte.
- `runtime.submit` never trusts a caller-supplied hint: admission validation
  (`codec.measure` or the redaction/binding validator) runs first, and
  `submitSafeDestination` overwrites the flag from the trusted submission
  context.
- Binary routes still use the public validating encoder.

Redaction rewrites borrowed storage and prepared schema bindings use a
different wire shape; both keep their independent validation. No unchecked
writer or reusable public credential is exported.

## Correctness

- New codec/encoder tests compare `encodeDecoded` and `encodeWithTime` bytes
  for text/JSON/logfmt on a decoded event with nested values, a template
  message, source, trace and a redacted secret.
- A forged `tree_validated = true` on an invalid cyclic tree still fails
  public `encoder.encode` with zero output.
- `runtime.submit` with a forged hint and duplicate keys still returns
  `DuplicateKey`; admission validation is not bypassed.
- `zig build test -Doptimize=ReleaseFast` passed 35/35 steps and 481/481 tests
  (`test-releasefast-final.log`). The earlier interrupted log is retained
  because the source changed during that build.
- Full `verify-local -Doptimize=ReleaseFast` passed 81/81 steps and 505/505
  tests (`verify-local-releasefast.log`).
- Targeted ReleaseSafe runs passed: proof tests 10/10
  (`release-safe-proof.log`) and the forged-hint predicate integration test
  1/1 (`release-safe-predicates.log`).

## Whole-process PMU

Five alternating pairs, complete ReleaseFast JSON file workflow, fixed CPUs,
100,000 records plus 1,000 warmup. User/core counters exclude kernel I/O.

| Case | Instructions before → after | Change | Status |
| --- | ---: | ---: | --- |
| SPSC memory P4 batch | 1,192,405,654 → 1,147,913,047 | −3.73% | stable |
| Async memory P1 batch | 1,088,324,949 → 1,039,471,174 | −4.49% | stable |

Instruction relative spread is 0.5%–1.6% on both sides. Cycles and task-clock
spread is 19%–45%, so they remain inconclusive. Throughput medians in this
window are also inconclusive; the host load average was about 100.

## Complete file workflow

The paired workflow uses the independent output oracle and validates every
physical JSON record. It completed 52 of 100 trials (5,252,000 records) before
an mmap trial exceeded the 120-second subprocess limit under host load. Every
completed trial had accepted=written=100,000, pending/drop=0 and the original
queue/file budgets. The partial capture is retained as
`workflow-results.jsonl`; it is **not** a throughput qualification and no
medians from it are used to claim a speedup. The PMU instruction reduction and
the output oracle are the evidence for this round.

## Boundaries

The gain is consumer CPU work, not a cross-library ranking. The host was
oversubscribed during capture; the full workflow still needs a quiet-window
rerun. The internal proof is not part of the public API, and public encoders
remain independently validating.

`before-source.tar.gz`, `implementation.patch`, `provenance.json` and the
before/after binaries preserve the exact sources and identities.
