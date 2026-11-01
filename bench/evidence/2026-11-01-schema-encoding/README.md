# Schema reference encoding

The reference payload codec now counts wire lengths during its bounded tree
validation and writes through the same internal value wire implementation as
the inline codec. Each reference size/encode call validates each node once;
previous reference encoding validated the tree during shape checking, again
during value sizing, and again through the public standalone value writer.
Public standalone writing continues to validate independently.

The benchmark covers five flat numeric fields, an eight-node nested value and
the maximum 256-node value. Schema setup and complete roundtrip checks happen
outside timing. Encoder batches consume all output with Wyhash. Each process
uses one fixed allowed CPU; application and kron modules both use ReleaseFast.
Five process pairs alternate before/after order, each with five batch repeats.

| Reference operation | Shape | Before median ns/call | After median ns/call | Local assessment |
| --- | --- | ---: | ---: | --- |
| size | flat5 | 66.04 | 51.13 | 23% lower |
| size | nested8 | 83.74 | 52.20 | 38% lower |
| size | max256 | 1,106.85 | 614.56 | 44% lower |
| encode | flat5 | 194.30 | 139.68 | Inconclusive: cross-process spread >10% |
| encode | nested8 | 307.21 | 217.58 | 29% lower |
| encode | max256 | 4,381.74 | 3,291.67 | Inconclusive: cross-process spread >10% |

All 450 paired rows have identical checksums, output byte counts, inline/archive
and reference wire lengths, input shape, iteration count and resource budgets.
`comparison.json` contains every operation, five process medians, dispersion and
the 10% noise limit. These batch measurements include fixture updates and output
hashing and do not establish producer latency, file throughput or industry rank.

`before-source.tar.gz` retains the complete original source and the expanded
benchmark, excluding generated caches. `baseline-archive.json` identifies the
archive and its build command. Extract into an empty folder to rebuild before:

```sh
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/encoding.zig \
  -O ReleaseFast -Mkron=src/root.zig -femit-bin=before
```

Build the current benchmark with the same options, then run each process on the
same allowed CPU with `--iterations=10000 --repetitions=5`. The pair files and
comparison include source and binary hashes. `qualification.json` records the
final correctness and platform gates separately from timing evidence.
