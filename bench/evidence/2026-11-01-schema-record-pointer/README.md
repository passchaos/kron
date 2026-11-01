# Reverted schema Record pointer experiment

This directory preserves a measured but rejected candidate. The idea was to
store a borrowed `*const Definition` in `Journal.Record` so the consumer
`decodeRecord` could skip a second ready lookup for prepared-schema records.

The full test step passed (35/35 steps, 481/481 tests), but the fixed-CPU PMU
showed no instruction reduction:

| Schema case | Before median instructions | After median instructions | Change |
| --- | ---: | ---: | ---: |
| SPSC memory P4 | 1,365,471,209 | 1,374,798,339 | +0.68% |
| Async memory P1 | 1,265,569,099 | 1,283,064,007 | +1.38% |

The copy of the small `Definition` value was already cheap; the pointer added
an indirection without removing work. Throughput was inconclusive. The source
was reverted byte-for-byte to the decoded-delivery state that passed the full
81/81-step, 505/505-test gate. No library change from this experiment is
retained.

Files are kept as negative evidence:

- `implementation.patch` was not generated; the candidate is reconstructed by
  the before/after binaries and `pmu-results.jsonl`/`pmu-summary.json`.
- `before-source.tar.gz`, `kron-ref-before-schema-ptr`,
  `kron-ref-after-schema-ptr` and `pmu.py` preserve the exact experiment.
- `test-releasefast.log` records the candidate's full test-step pass.
