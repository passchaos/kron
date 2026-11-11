# Development and verification

Use Zig 0.16 and run commands from the repository root. Start with the smallest
verification that matches the change, reusing `.zig-cache` and existing
sessions; run the corresponding combined gates when public dependencies,
concurrency/lifetime, persistent formats, build, or release paths are affected.

## Common entry points

| Change scope | Preferred command |
| --- | --- |
| Logging configuration/output/ownership (including per-route queues) | `zig build test-logging test-outputs -Doptimize=ReleaseSafe -j1` |
| codec/fields/thread registration modules | `zig test src/root.zig -O ReleaseSafe --test-filter 'codec'`; select subsets by actual test name |
| Source paths/text locations | `zig test src/root.zig -O ReleaseSafe --test-filter 'source'`; run `run-mmap` and `run-source-location` |
| Fields/context/object adapters | `test-field-keys`, `test-capture`, `test-adapter`, `test-redaction-paths`, `test-compile-fail` |
| Internal submission arguments and caller snapshots | `test-submission-snapshot`, `test-capture`, `test-redaction-paths`, plus prepared/binding regressions |
| Memory/Mmap and backpressure | `test-journal-progress`, `test-journal-peak`, `test-async-storage`, `test-integration`, and related Runtime queue regressions |
| Concurrent shared-producer delivery | `test-async-storage`; 4 threads × 250 records × 2 rounds, Memory block queue, accepted=written, pending=0; mid-flight `shutdown(.drain)` produces rejected_closing and state=closed; clean reopen after concurrent mmap; 1000-run soak |
| Journal/archive randomized fuzz | `test-journal-fuzz`; 20,000 random commit/peek/release, mmap reopen/recovery, random archive record/message round-trip; seeds printed; Debug/Safe/Fast; extended 1000-seed ReleaseSafe scan |
| Journal slot/generation coordinates | `test-journal-coordinates`; shared/SPSC across eight capacities, full sequence/wrap, and valid-CRC wrong-generation evidence |
| v1/v2 journal upgrade compatibility | Root tests/`test-logging`; real v1/v2 headers/extensions, CRC, commit/peek, reopen/recovery read/write under V3 sources |
| Old-binary journal fixtures | [fixtures/journal](../tests/fixtures/journal/README.md), root tests/`test-logging`; v1/v2 journals written by real `5b1fd7c` x86_64 and aarch64 binaries read with V3 sources and `recover=true` |
| Nested/rolling/schema combination recovery | Root tests/`test-logging`; prepared nested group/array through rolling output + mmap schema journal, durable reopen of the same journal, pending=0, and replay append |
| Configuration and old-generation lifetime | `test-route-policies`, `test-configurations`, `test-transactions`, `test-route-filters`, `test-predicates` |
| Concurrent configuration replacement | `test-configurations`; shared async 4 producers × 500, 20 route/redaction replacements and cuts, plus 4 producers × 500 + 20 filter reloads; 200-run soak including replacement/filter |
| TLS admission ownership and reuse | `test-admission-lifecycle`; related shared admission View, configuration, and deadline regressions |
| CRC native math and dispatch | `zig test src/platform/crc32.zig -O ReleaseSafe`; root filter `partial CRC stripes` with actual cases; verify native/no-AVX PCLMUL/generic separately |
| CRC segmentation/seeds/read boundaries | `test-crc-segments`; lengths 0..512 with 32-byte alignment, 20/24-byte segments, arbitrary seeds, real guard pages on both sides |
| ASCII scanning and escape failure prefixes | `test-escaping-tails`; short-tail single/adjacent bytes, quoted JSON/text, JSON key/member, every short-buffer prefix |
| Clock and time conversion/recovery | `test-clock-dispatch`, `test-time` (fixed offsets and Python oracle), `test-local-time` (consumer and independent zoneinfo) |
| flush/deadline/shutdown | `test-deadline`, `test-single-threaded`, `test-integration` |
| Real files/rotation | `test-file-delivery`, `test-platform-host`, and corresponding sink module tests |
| Failure capture | `test-failure-handler`; real SIGSEGV/SIGABRT/SIGTERM and fatal-event children, symbolized signal reports by default with a raw opt-out and bounded frames, symbolized `record`/`fatal`, crash-file contents, symlink, stderr mirror, `chdir` independence, stack-overflow alt-stack capture, and worker-thread SIGSEGV |
| Multiple filesystem behavior | tmpfs vs ext4 package consumer; tmpfs mmap journal rejects `VolatileFilesystem` by design |
| Shared filesystem behavior | `tests/shared_fs/vm_9p.py`; under QEMU virtio-9p sync/memory pass, while mmap journal rejects `PreallocationUnsupported` by design |
| Real ENOSPC faults | `tests/faults/vm_enospc.py`; after filling a child-VM tmpfs, direct FileSink, Runtime Memory+FileSink durable flush, and RollingFileSink flush all return and latch `NoSpaceLeft` |
| Read-only filesystem initialization | `tests/faults/vm_readonly.py`; FileSink and Journal return `ReadOnlyFileSystem` on a read-only child-VM ext4 |
| Journal ENOSPC preallocation | `tests/faults/vm_journal_enospc.py`; after filling a 64 MiB ext4, `Journal.create` returns `NoSpaceLeft` |
| Child-VM shutdown | [power_loss](../tests/power_loss/README.md); ext4/XFS/Btrfs/F2FS 16-run child-VM SIGKILL campaigns; not physical power loss |
| wire/Reader/compression | `test-decoder-matrix`, `test-fuzz` (runner-seed-driven, 1000-seed scan), `test-query`, `test-compression` |
| Fused scratch lifetime/budget | `test-wire-scratch`; three-format failures and complete decoder reuse after Fallback, 64 top-level keys, and exact nested arena budgets |
| Regular expressions | `test-regex-differential`, `test-regex-fuzz`, `test-regex-equivalence`; fuzz corpus driven by runner seed, 1000-seed scan |
| build/dependency/distribution | `test-package`, `test-package-single-threaded`, `test-package-distribution`, `check-platforms` |
| aarch64 QEMU user mode | `zig test src/root.zig -target aarch64-linux-musl -O ReleaseSafe`, journal fuzz, and `tests/package_consumer` cross-build |

Add `-Doptimize=ReleaseSafe -j1` to build steps in the table; platform object
checks fix ReleaseSafe internally. `--test-filter` only selects tests to run and
must not be described as full-library coverage.

Root tests cover relative import boundaries of modules. Running a file under
`src/core/tests/` directly as an independent root may escape module paths;
prefer filtering from `src/root.zig`. Short pure modules can be verified
independently, for example `zig test src/submit/source.zig`; system-time tests
that need libc use `zig test src/time/root.zig -lc`.

## Full gates

```sh
zig build verify-fast -Doptimize=ReleaseSafe -j1 --summary all
zig build verify-local test-package-distribution -Doptimize=ReleaseSafe -j1 --summary all
zig build check-platforms -j1 --summary all
zig build fmt hygiene links -j1
zig build docs -j1
```

For routine changes, start with `zig build test-unit` (root unit tests without
fuzz/crash). For a broader fast gate, run `verify-fast` (root/public tests,
compile-fail, fuzz, single-threaded). Before committing, run `verify-local` or
the platform/distribution gate according to impact. `fmt` checks Zig
formatting, `hygiene` checks tracked-file hygiene and single-file size, `links`
checks relative Markdown links, and `docs` generates Zig API documentation under
`zig-out/docs`. `verify-local` includes root/public integration,
deadline/configuration/files, tools, compile-fail, version/corruption matrices,
real SIGKILL, random ACK recovery, independent package/single-threaded builds,
and example compilation. Source distribution is selected separately in this
command. The platform step produces real objects for nine targets: two Linux
architectures, Windows, two macOS architectures, two Android architectures, and
iOS device/simulator; these objects do not represent device execution.

Add relevant tests for Debug/ReleaseFast according to impact. After a complete
ReleaseSafe success, do not repeat every fault campaign for documentation or log
recording changes. Single-threaded builds provide sync and ordinary
flush/shutdown; timed/async interfaces return explicit capability errors. The
system-local specialization explicitly links platform libc; default Linux root
tests may skip local-cache tests by capability, so separately confirm that the
specialized oracle actually ran.

## Output and runtime checks

Examples usually append files in the current working directory. Match the
session in the current stdout and avoid mixing tails from other sessions or
repeated runs into this result. Source paths resolve from the repository root;
verify line/column and call sites. Text has no outer quotes, while JSON keeps a
valid source string. Format/date/redaction/sequence can be compared across
multiple outputs for the same event.

Running examples is a reversible integration check, not a replacement for
crash/overload/durability tests; a normal journal reopen is not equivalent to a
forced kill or power loss. Read-only tool export should verify that the original
file is unchanged.

## Performance and evidence

Follow [benchmark-methodology.md](benchmark-methodology.md) and record the source
commit/hash, binary, toolchain/optimization level, inputs/budgets/actual backend,
clock, repetition count, complete-record/result oracle, and every completion
stage. Keep local date microbenchmarks, CRC/sampling costs, and complete
log/application workflows separate.

Do not combine percentages from different baselines into a current
cross-library ranking. Results above the noise limit stay inconclusive; original
failures/slow values/negatives, incomplete trials, and hardware/filesystem scope
are retained. The main performance entry points are under [bench/](../bench/README.md).

`docs/implementation-status.md` maintains only current capabilities, recent
identified gates, and remaining priorities; detailed chronology belongs under
`docs/history/`. Frozen sources and raw evidence are not rewritten during
directory reorganization. New output/format behavior is documented in the guide,
and package distribution roots/support modules are checked together. Measurement
results are not tracked in this repository; there is no generated evidence index
to refresh.

## Change boundaries

Read the source that owns the state before changing it, and preserve borrowed
storage, stable writer addresses, thread tokens, configuration pins/leases, and
reservation/record ownership. Exposing private implementation only to simplify
tests expands API responsibility; choose a module boundary or internal test
import first.

Commit after completing a verified functional change. When a remote exists,
pull first, resolve conflicts, and push only for remotes the user has authorized.
The complete "industry best" goal is considered done only after performance,
platform, fault, and behavior scopes each have corresponding evidence.
