# Native PCLMUL IEEE CRC32

The complete JSON workflow profile repeatedly placed journal CRC at roughly a
quarter of user-core samples: producer commit, checked consumer peek and
release each hash the same record. This round replaces only the CRC block loop
when the compile target is x86_64 and advertises PCLMUL + SSE2. Generic
x86_64, non-x86 targets, short inputs and sub-16-byte tails keep the portable
sixteen-byte slicing table.

The persisted polynomial (0xEDB88320), input reflection, final XOR, commit/
peek/release check sites, schema-reference coverage, journal framing and
recovery protocol are unchanged. The native path folds four 128-bit lanes over
64-byte blocks, then reduces 128→64→32 bits and applies the Barrett step. It
performs unaligned 16-byte loads, never reads outside the supplied slice, does
no allocation or runtime CPU probing, and adds no external dependency.

## Correctness

- `src/platform/crc32.zig` keeps the portable oracle and adds a native-path
  differential test: 32 alignments × 22 lengths (64 B–69,999 B) × 14
  incremental splits, compared with `std.hash.Crc32`.
- Existing module tests cover standard vectors, 64 alignments × 36 lengths,
  short tails, block boundaries and journal header partitions.
- Portable fallback re-tested on this host with `-mcpu=baseline`: 3 passed,
  the native-only test skipped. `aarch64-linux` compiles with the same source.
- Journal golden v1/v2 checksum tests pass unchanged.
- Vort real-source interoperability passes 416 cases, reporting
  `backend=hardware` for the native build.
- Full ReleaseFast `verify-local`: 81/81 steps and 503/503 tests passed
  (`verify-local-releasefast-rerun.log`). The first run hit a 10-second crash
  writer readiness timeout under host load; `test-crash` passed standalone
  afterwards (`test-crash.log`), and the clean rerun passed the whole gate.

## CRC primitive

Journal-shaped batches: 20-byte header, optional 24-byte schema reference,
payload, output checksum consumed. Three invocations per side, five internal
repetitions each, fixed CPUs 0/2/4/6/8/10.

| Payload | Before median ns/record | After median ns/record | Change |
| --- | ---: | ---: | ---: |
| 64 B | 24.56 | 13.83 | −43.7% |
| 256 B | 95.23 | 18.98 | −80.1% |
| 512 B | 199.96 | 26.34 | −86.8% |
| 2 KiB | 785.42 | 79.56 | −89.9% |
| 16 KiB | 6312.29 | 535.23 | −91.5% |

With the schema reference the same cases are 32.12→21.40, 103.55→26.58,
206.41→33.80, 799.14→87.65 and 6493.42→546.36 ns. Every case produced the
same checksum before and after.

## Whole-process PMU

Five alternating pairs, complete ReleaseFast JSON file workflow, fixed CPUs,
100,000 records plus 1,000 warmup each. User/core counters exclude kernel I/O.

| Case | Instructions before → after | Change | Status |
| --- | ---: | ---: | --- |
| SPSC memory P4 batch | 1,419,594,438 → 1,202,017,414 | −15.33% | stable |
| Async memory P1 batch | 1,279,222,652 → 1,090,074,869 | −14.78% | stable |

SPSC memory P4 median throughput moved 1,393,077 → 1,815,741 records/s
(+30.3%) and met the local CV/spread gate. Async memory P1 moved
1,483,168 → 1,912,574 (+28.9%) but its intervals still overlap. Cycles and
task-clock remain inconclusive because the host load was about 100.

## Complete file workflow

100 alternating trials validated 10,100,000 physical JSON records; every trial
had accepted=written=100,000, pending/drop=0 and the original queue/file
budgets.

| Batch case | Before median records/s | After median records/s | Change | Status |
| --- | ---: | ---: | ---: | --- |
| async memory P1 | 926,000 | 1,707,137 | +84.4% | inconclusive |
| async memory P4 | 1,417,895 | 1,633,455 | +15.2% | inconclusive |
| SPSC memory P4 | 1,318,197 | 1,592,112 | +20.8% | inconclusive |
| SPSC mmap P4 | 1,234,154 | 1,427,963 | +15.7% | inconclusive |
| SPSC mmap P4 prepared | 1,117,234 | 1,332,204 | +19.2% | inconclusive |

The host load average was about 110 during this capture, so at least one side
of every workflow group exceeded the 10% CV/spread gate and all bootstrap
intervals overlap. The positive medians are retained as evidence of direction,
not as a stable throughput guarantee. The async-P1 before median is unusually
low and is not used to claim an 84% speedup.

## Boundaries

This is a native x86_64 optimization. Generic builds and non-x86 targets use
the portable table and remain correct; they do not receive the speedup. The
archived Foundation/Quill comparison uses an older source snapshot and a
different host window. No same-round cross-library rerun is included, so this
evidence does not establish a new cross-library ranking. A same-round harness
smoke was attempted at host load about 109; Foundation reported an 8.7-second
initialization and a 6.6-second shutdown, so that capture is archived as
`bench/cpp_reference/evidence/2026-11-01-pclmul-same-round-smoke/` and
explicitly is not a ranking. The file boundary is written, not durable/fsync or
power loss.

`before-source.tar.gz`, `crc32.patch`, `provenance.json`, the before/after
binaries and all raw rows preserve the exact implementation and identities.
