# Random-time process-crash evidence

The workload runs two producers through public kron APIs while its worker writes
JSON to a real file. After a written warm prefix, the parent sends SIGKILL at a
seeded delay without parking capture or delivery at a fault hook. Shared MPSC
and per-thread SPSC each cover inline and prepared-schema payloads.

| Report | Optimization of application and library | Cases | Complete ACKs | Recovered records | Written/recovery overlap | Incomplete reservations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| release-safe.json | ReleaseSafe | 32 | 96,932 | 51 | 2 | 10 |
| high-u64-safe.json | ReleaseSafe | 8 | 12,487 | 18 | 2 | 1 |
| release-fast.json | ReleaseFast | 12 | 57,242 | 40 | 5 | 2 |

All complete ACKs were covered by complete written output or independently
recovered events. Two inspections produced identical output and left journal
and output hashes unchanged. CRC checks use Python zlib separately from the Zig
reader. Nested fields, strings, bytes and sensitive values are checked against
an independent event oracle. Six negative tests reject deliberately broken
evidence, including lost events, duplicate identities and corrupted snapshots.

`safe-build.json` and `fast-build.json` retain verbose project build commands,
including the optimization flag on both modules. The reports' binary SHA256
values were checked against those build-owned artifacts. `qualification.json`
records report hashes, source hashes and the formal gates. Both formal gates
passed 5/5 steps, 12 scenarios and 6 negative oracle tests.

```sh
zig build test-runtime-crash -Doptimize=ReleaseSafe -j1
zig build test-runtime-crash -Doptimize=ReleaseFast -j1
zig build test-runtime-crash-oracle -j1
```

These are Linux process-crash checks, with no physical power-loss, system-crash
or non-Linux runtime claim. ACK follows emit and can lag a complete accepted
event by one call per producer. A seed fixes payloads and requested delay, while
OS scheduling and the actual kill location can change. No partial output tails
were observed in the recorded runs; explicit file short-write tests provide
that separate evidence. This workload includes a confirmation pipe and pacing
and is not a performance benchmark.
