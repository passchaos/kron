# Reverted codec header prefix reuse experiment

This directory preserves a measured but rejected candidate. `decode` and
`schema_codec.resolve` already consumed the four-byte magic and two-byte
version, then `readHeader` parsed those six bytes again. The candidate split
out `readHeaderBody` and reused the already-consumed prefix.

Correctness:

- Codec-filtered tests passed 40/40.
- Schema-filtered tests passed 50/50.

Fixed-CPU PMU on the complete JSON file workflow:

| Case | Before median instructions | After median instructions | Change |
| --- | ---: | ---: | ---: |
| SPSC memory P4 | 1,150,254,433 | 1,154,826,587 | +0.40% |
| Async memory P1 | 1,038,503,266 | 1,037,774,585 | −0.07% |

Both instruction spreads were stable (0.6%–1.2%), but the change is neutral
within noise and adds a public header-body entry point. Cycles and throughput
were inconclusive under host load. The source was reverted byte-for-byte to
the decoded-delivery state that passed the full 81/81-step, 505/505-test gate;
no library change from this experiment is retained.

Files: `pmu.py`, `pmu-results.jsonl`, `pmu-summary.json`,
`kron-ref-before-header`, `kron-ref-after-header`, and the partial candidate
test logs.
