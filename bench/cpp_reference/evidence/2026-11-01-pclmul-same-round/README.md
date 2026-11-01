# Same-round Foundation/kron comparison (loaded host)

This directory now contains an actual same-round comparison, not only the
guarded scheduler. The guarded wait never reached its quiet threshold (three
five-minute samples below load 24) because the host stayed around load 88–110.
The comparison was therefore launched directly against the final verified
source: PCLMUL CRC, decoded-delivery validation reuse, and the fused
wire-to-record path for JSON/text/logfmt.

## Scope

- Foundation Logging and current kron, same 299-byte full JSON event layout
- 100,000 records + 1,000 warmup per trial
- 5 repetitions, 1 and 4 producers
- Foundation memory/mmap; kron async/spsc memory/mmap, schema off
- Complete written-flush/shutdown/cleanup lifecycle
- Every physical output record verified by the independent oracle

120 trials completed, 12,120,000 records verified. Every trial reported
status ok, accepted=written=100,000, pending/drop=0. The runner exited 0;
`summary.json` is the authoritative capture. The host was oversubscribed
throughout, so every group is marked `inconclusive`; this is a same-round
direction measurement, not a stable ranking.

## Batch written+flush medians (5 trials)

| Configuration | Foundation M records/s | kron M records/s | Direction |
| --- | ---: | ---: | --- |
| Memory P1 | 1.521 | async memory 1.906 / SPSC memory 2.039 | kron ahead |
| Memory P4 | 2.224 | async memory 1.938 / SPSC memory 2.043 | Foundation ahead |
| Mmap P1 | 1.820 | async mmap 1.730 / SPSC mmap 2.167 | SPSC ahead; async behind |
| Mmap P4 | 2.204 | async mmap 1.988 / SPSC mmap 2.061 | Foundation ahead |

## Producer p50/p99 (sampled phase, ns)

| Configuration | Foundation | kron |
| --- | ---: | ---: |
| Memory P1 | 349 / 713 | async 348 / 1781; SPSC 473 / 877 |
| Memory P4 | 638 / 30,332 | async 786 / 13,747; SPSC 291 / 9,472 |
| Mmap P1 | 513 / 926 | async 417 / 814; SPSC 480 / 861 |
| Mmap P4 | 690 / 11,196 | async 807 / 14,530; SPSC 290 / 9,074 |

The P1 call latency is comparable to Foundation; SPSC P4 p50 is lower but
throughput is slightly behind. All throughput relative spreads were
0.11–1.00, so no stable speedup is claimed.

## Interpretation

- In this loaded-host same-round run, kron leads Foundation in the P1
  memory/mmap batch medians and is close or slightly behind in P4.
- The previous archived comparison (kron roughly 0.46–0.60× Foundation) is an
  older source snapshot; the PCLMUL CRC, decoded-delivery, and fused
  wire-to-record changes narrowed the gap substantially.
- The host load prevents a qualified ranking. A quiet-window rerun with the
  same five-repetition protocol is still required before claiming that kron
  has surpassed Foundation.

Files: `manifest.json`, `results.jsonl`, `summary.json`, `run.log`,
`wait.log`, `wait_and_run.py`, and the Foundation snapshot/build metadata.
