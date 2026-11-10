# <experiment name>

One paragraph: what changed, which source commit/binary was measured, and whether
the candidate was retained or withdrawn.

## 问题

What gap or hypothesis this experiment tests. State the completion boundary and
the workload or oracle used.

## 变更

Source/configuration changes and the exact commands or scripts needed to
reproduce them. Keep generated binaries and raw workload files out of Git.

## 实际执行

- Host/topology, load window, Zig/C++ toolchain and optimization mode.
- Trial counts, events, warmup, repeats and output validation.
- The exact test/build gates that passed or were intentionally skipped.

## 结果

Lead/negative/inconclusive counts, medians and intervals. Keep failed and slow
runs; do not replace them with a single best number. Link `results.jsonl` and
`manifest.json` instead of pasting large tables.

## 边界

What this evidence does not prove (cross-host ranking, power loss, other
filesystems, non-Linux runtime, etc.). Historical evidence is never rewritten
when directories are reorganized.

## 原始数据

- `manifest.json`: host, source/binary SHA256, commands and configuration.
- `results.jsonl`: raw measurement rows, or a compressed `.jsonl.xz` copy.
- Keep only curated logs; raw stdout/stderr and profiling data belong in an
  external artifact store.
