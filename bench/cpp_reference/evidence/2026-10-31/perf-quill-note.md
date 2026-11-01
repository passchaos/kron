# Quill focused perf stat observation

An isolated profiling invocation used Quill v9.0.0, deferred formatting, four
producers, 10,000 measured events, 1,000 excluded warmup events, a blocking queue,
and final flush/Backend::stop. File validation confirmed 10,000 measured complete
records and 1,044,490 measured output bytes with zero drop and final pending.

```sh
perf stat -e cycles,instructions,cache-misses,context-switches,page-faults -- \
  /tmp/kron-cpp-comparison-20261031-final/reference-quill \
  --output=/tmp/kron-quill-profile.jsonl --events=10000 --warmup=1000 \
  --producers=4 --phase=batch --strategy=deferred_format --queue-slots=256
```

Observed counters:

- cpu_atom cycles: 44,133,465.
- cpu_atom instructions: 102,312,910.
- cpu_atom cache misses: 107,150.
- Context switches: 185.
- Page faults: 533.
- Process invocation elapsed: 10.448122 ms; user 8.127 ms, system 4.644 ms.
- Harness measured completion interval: 3.331963 ms, including final drain.

The i9-13900K is a hybrid CPU. Corresponding `cpu_core` counters were **not
counted** in this invocation; these hardware counters therefore do not describe
all instructions/cycles on every core. perf's process elapsed time includes
initialization, warmup, post-trial file verification and noop measurement, which
are outside the harness's measured interval. This single unpinned observation
does not support cross-library IPC/cache attribution or a general optimization
conclusion. It establishes that local counters are available and records their
scope limitations.
