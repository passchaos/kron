# Test organization

Tests are divided into production-module unit tests, public-API integration,
real-process/child-VM faults, independent Zig consumption, and evidence oracles.
Run build steps from the repository root; see
[development and verification](../docs/development.md) for targeted selection.

## Scope and entry points

| Type | Location/fixture | Verification |
| --- | --- | --- |
| Module and internal regressions | In-`src/` tests, [core/tests](../src/core/tests/runtime.zig), [logging/tests](../src/logging/tests.zig) | Fields/codec, token/gate, configuration caches, batches, errors/allocator; included by the root module |
| Public logging pipelines | runtime/capture/adapter/redaction/async_storage integration | Real sync/shared/SPSC, typed snapshots, context, zero allocation, and errors |
| Concurrent shared-producer delivery | [async_storage.zig](async_storage.zig), `test-async-storage` | 4 threads × 250 records × 2 rounds, Memory block queue, accepted=written=1000, pending=0; mid-flight `shutdown(.drain)` gives accepted=written, rejected_closing, state=closed; clean reopen after concurrent mmap submission, pending=0; Safe/Debug/Fast, multiple seeds, 1000-run soak |
| Field keys and error ordering | [field_key_validation.zig](field_key_validation.zig), `test-field-keys` | Independent `eql` byte oracle, exact pair/node counts, duplicate vs cycle/depth/budget precedence, real guard pages at both Linux ends |
| Exact queue peak | [journal_peak.zig](journal_peak.zig), `test-journal-peak` | Memory/Mmap ordinary/schema concurrent occupancy and high-water marks, Full/oversize/abort/CRC failures, recovery rebuild, complete sequence/data |
| Written progress and publication | [journal_progress.zig](journal_progress.zig), `test-journal-progress` | Live offset without sync, leading tombstones, CRC failure prefix, recovery old-tail/new-gap, acquire-observation and pre-join marker assertions |
| Journal/archive randomized fuzz | [journal_fuzz.zig](journal_fuzz.zig), `test-journal-fuzz` | 20,000 random commit/peek/release, mmap reopen/recovery, random archive record-count/message round-trip; seeds printed; Debug/Safe/Fast; extended 1000-seed ReleaseSafe scan passed 1000/1000 |
| v1/v2 journal upgrade compatibility | [journal/schema_journal_tests.zig](../src/journal/schema_journal_tests.zig), root tests/`test-logging` | Real v1/v2 headers/extensions, CRC, commit/peek, reopen/recovery read/write under V3 sources; unreleased-record recovery |
| Old-binary journal fixtures | [fixtures/journal](fixtures/journal/README.md), root tests/`test-logging` | v1/v2 journals written by actual `5b1fd7c` binaries (x86_64 and aarch64 QEMU); pending records read under V3 sources with `recover=true`, old scope/message parsed |
| Nested/rolling/schema combined recovery | [logging/tests.zig](../src/logging/tests.zig), root tests/`test-logging` | Prepared nested group/array through rolling output and mmap schema journal; after flushDurable/shutdown, same-journal reopen, pending=0, replay append |
| Clock and Io call boundaries | [clock_dispatch.zig](clock_dispatch.zig), `test-clock-dispatch` | Exact clamp, callback inside/outside switching, Io identity/argument snapshots, zero/monotonic, public function pointers and capture/full boundaries |
| TLS admission lifetime | [admission_lifecycle.zig](../src/core/tests/admission_lifecycle.zig), `test-admission-lifecycle` | Owned/bare/borrowed reuse, outer ownership in callbacks, 64-level stack and overflow, OS-thread isolation, all Levels and full generation/channel boundaries |
| Native CRC math and target selection | [crc32_pclmul.zig](../src/platform/crc32_pclmul.zig), [crc32.zig](../src/platform/crc32.zig); root filter `partial CRC stripes` | Independent bitwise/GF2 message and seed basis, arbitrary seed/alignment, frozen zlib, prefix/partition; helper imported only for x86_64+PCLMUL+SSE2 test targets |
| CRC segmentation and read boundaries | [crc32_segment_tests.zig](../src/platform/crc32_segment_tests.zig), `test-crc-segments` | Arbitrary u32 seeds and 0..512/32 alignment, original 20/24 segments and incremental splits, Linux PROT_NONE boundaries at both ends and empty slices |
| ASCII short tails and public escaping | [escaping.zig](../src/encoder/escaping.zig), `test-escaping-tails` | Independent scalar first-match, all bytes/adjacent pairs/tail crossings; five public operations' success bytes and failure prefixes per buffer capacity |
| Fused scratch lifetime | [wire_scratch_tests.zig](../src/encoder/wire_scratch_tests.zig), `test-wire-scratch` | Complete decode reuse after JSON/text/logfmt errors and Fallback, exact comparison counts, 64 top-level keys/exact nested budget and suffix guards |
| Shared/SPSC coordinates and evidence | [journal/tests.zig](../src/journal/tests.zig), `test-journal-coordinates` | Eight-capacity independent incrementing slot/generation oracle, non-power-of-two wrap, crossing 2^32 and max_sequence, reserved header/commit payload/abort/release and written; independently recomputed valid CRC with wrong generation still rejected and slot preserved |
| Configuration and deadline | configuration_integration/transactions, route_policy, route_filter, predicate, deadline | Old route generation/lease, admission, sampling phase, timeout resources and reentrancy |
| Concurrent configuration replacement | [configuration_integration.zig](configuration_integration.zig), `test-configurations` | Shared async 4 producers × 500, 20 route/redaction replacements and cuts; also 4 producers × 500 + 20 filter reloads; accepted=written, health/sink agreement; 200-run soak |
| Time and source | time_integration, local_time_integration/oracle, independent package tests | Exact nanoseconds, fixed/local cache, DST/recovery identity, repository-relative source paths |
| Files/archives/decoding | file_delivery_failures, compressed_archive, decoder_matrix/fuzz, tool_query | Partial/zero/CQE errors, versions/corruption, read-only Reader/query/follow |
| Multiple filesystem behavior | [multifs volatile](../docs/async-storage.md) | tmpfs mmap journal rejects `VolatileFilesystem` by design; ext4 five modes pass; not crash/power-loss qualification |
| Shared filesystem behavior | [shared_fs/vm_9p.py](shared_fs/vm_9p.py) | QEMU virtio-9p: sync/memory/SPSC-memory pass; mmap journal rejects `PreallocationUnsupported` by design; not NFS/crash qualification |
| Real ENOSPC faults | [faults/vm_enospc.py](faults/vm_enospc.py) | After filling a child-VM 1 MiB tmpfs, direct FileSink, Runtime Memory+FileSink durable flush, and RollingFileSink flush all return and latch `NoSpaceLeft`; no false success |
| Read-only filesystem initialization | [faults/vm_readonly.py](faults/vm_readonly.py) | On a read-only child-VM ext4, FileSink and Journal both return `ReadOnlyFileSystem`; no false success |
| Journal ENOSPC preallocation | [faults/vm_journal_enospc.py](faults/vm_journal_enospc.py) | After filling a 64 MiB ext4, `Journal.create` returns `NoSpaceLeft`; no false success |
| Regex | regex_differential/fuzz/equivalence | Python differential, bounded mutation, coverage-guided entry; fuzz corpus driven by runner seed and a completed 1000-seed scan |
| Decoder mutation fuzz | [decoder_fuzz.zig](decoder_fuzz.zig), `test-fuzz` | Runner-seed-driven mutation; 1000-seed scan 1000/1000, Safe/Debug/Fast 7/7 |
| Negative compilation | [compile_fail/](compile_fail/), [run_compile_fail.py](run_compile_fail.py) | Unsupported inputs/formats, field-selection boundaries, prohibition on directly modifying opaque configuration |
| Process recovery | crash_writer/recovery, async_storage_crash, recovery_campaign, runtime_crash_campaign | Real SIGKILL, complete commits/reservation gaps/hot routes, random ACK coverage |
| Failure capture | [failure_handler_writer.zig](failure_handler_writer.zig), [failure_handler.py](failure_handler.py), `test-failure-handler` | Real SIGSEGV/SIGABRT/SIGTERM and fatal-event children; symbolized signal reports by default with a raw opt-out, symbolized `record`/`fatal`, crash-file naming/content, symlink, stderr mirror, and a `chdir` case through the pre-opened crash directory |
| Child-VM shutdown | [power_loss/](power_loss/README.md) | QEMU shutdown and journal/output confirmation; ext4/XFS/Btrfs/F2FS 16-run schema campaigns and single non-schema ACK1 pass; specific filesystem/device, not general physical power-loss qualification |
| aarch64 QEMU user mode | [aarch64 QEMU notes](../docs/platforms.md) | aarch64-linux-musl static root suite 455 pass/7 skip/0 fail; journal/archive fuzz 20 seeds; independent package consumer five modes and qualification pass; not a real device |
| Independent package and device host | [package_consumer/](package_consumer/build.zig), [package_consumer.py](package_consumer.py) | `b.dependency`, five modes, single-thread, local options, source distribution and target-native self-check |
| Benchmark tool oracles | `test_*.py`, time/local oracles | Reject incomplete output, backend fallback, wrong comparisons/regression results; independent application models |

## Verification principles

Run the smallest test that proves the behavior, then escalate to the relevant
combination or final gate. Tests do not change assertions when relocated, fake
modules, or expand the private surface; shared fixtures are reused only when
responsibility and oracle independence are preserved.

Import-aggregated tests in one test binary count toward totals; cross-binary
counts are not a unique test count. A local skip in a no-libc root test is a
specific capability check, and `test-local-time` must actually run conversion/
consumer and the oracle.

Real fault records retain ACK, physical JSON, completeness/FIFO, and replay
identity. Memory losing undelivered records is a contract, and Mmap at-least-once
duplication is an allowed boundary; normal shutdown or read-only reopen is not
presented as SIGKILL/system power loss. Platform objects/linking are not
presented as target-device execution.

Temporary files and caches use `.zig-cache` or fixture-owned temporary
directories; when preserving a failure scene, record its identity. Frozen
historical results under `power_loss/evidence` are not changed by current test
path organization.

`independent_outputs.zig` (`zig build test-outputs`) verifies `Logging.outputs`
independent mode/queue/overflow, per-route sampling and pre-queue redaction,
partial success, 64 outputs, thread/prepared rollback, and deadline shutdown.
`test_managed_outputs_compare.py` verifies the complete-workflow benchmark JSON
oracle and rejects missing, duplicate, truncated, or changed-workload output.

`submission_snapshot.zig` (`zig build test-submission-snapshot`) verifies public
submit immutability of caller Event/borrowed backing layers, queue snapshots
before acceptance, public Binding canonical lookup and invalid-reference
rejection, and redaction scratch lifetime across nested sink callbacks in
sync/full fallback. The step is part of `test` and `verify-local`; it does not
validate through a public private-measurement proof.
