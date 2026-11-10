# Local repository reuse assessment

On 2026-10-31, 46 major repositories under `~/project-z` were surveyed, excluding
temporary worktrees, vendor directories, and `zig-pkg`. READMEs, actual APIs, Zig
versions, dependencies, and storage semantics were checked before deciding reuse
scope. No other repository was modified, and target descriptions were not treated
as verified performance results.

| Repository/actual component | Use for kron | Current decision |
| --- | --- | --- |
| Vort `src/checksum.zig` `crc32Best`, `crc32UpdateBest`, `crc32Combine` | Verify IEEE CRC32 one-shot, incremental, segmented, and hardware-implementation compatibility | Optional oracle; journal slots use kron's own IEEE implementation with optional PCLMUL on native x86_64 and portable slice-by-16 elsewhere; no Vort production dependency |
| ZKV `src/storage/faultable_device.zig` `FaultableDevice(capacity,max_writes)` | Fixed arrays, volatile/durable separation, write-prefix persistence, failed sync and crash, dual-checkpoint update protocol | Added as an optional persistence-model check, using the actual model and kron protocol without copying |
| ZKV `src/storage/read_window.zig` `Cache(slot_count)` | Fixed window, borrow pin, positional/mmap and growing-tail refresh | Reserved for future `kroncat` indexed random queries; the current sequential consumer has no direct gain |
| Netz `src/mqtt/persistence/{commit_log,durability}.zig` | Reference distinction between complete-commit corruption and short tails, plus file sync→replace→directory sync | Semantic reference only; kron already has an implementation, and the whole package depends on vail/pbz/zio, so it was not introduced |
| Zigraft `Impl/DynRef/DynMut` | Two-pointer borrowed dynamic views and compile-time interface contracts | The existing sink vtable already covers the need; introducing it has insufficient benefit |
| MCAP chunks, CRC, positional index/reference replay | Tool and archive-index design reference | The existing log format already has recovery and compatibility protocols; the journal is not changed to MCAP and the whole package is not introduced |

These candidates all declare Zig 0.16. Zigraft and Netz provide top-level MIT
licenses; no top-level license file was found for Vort, ZKV, MCAP, Hetu, Pangu,
Alea, or Zev. The current checks use explicit local paths, and the default build
and release package do not copy these sources; pin versions and release
authorization before adopting a production dependency. The current package
`.dependencies` remains empty.

No independent local implementation better suited than kron's existing io_uring
backend was found, and no smaller public component than the standard-library arena
and the existing streaming JSON encoder was found. Hetu's read-only whole-file
mapping cannot replace the exclusive lock, space preallocation, shared writable
mapping, and recovery protocol required by logging; Zev's generic SIMD wrapper
cannot directly replace CRC polynomial folding. Alea's reproducible-corpus idea is
useful, but the standard-library PRNG already satisfies test requirements.

## Actual verification

```sh
zig build check-local-reuse -Dvort-path=/home/passchaos/project-z/vort -Doptimize=ReleaseSafe -j1
zig build check-local-faults -Dzkv-path=/home/passchaos/project-z/zkv -Doptimize=ReleaseSafe -j1
```

The Vort check passes **416 groups** of different length/alignment inputs,
verifying one-shot CRC, incremental update, combine, complete journal v1/v2
coverage, and compressed archive headers. The current x86_64 build selects
`hardware`. This proves compatibility with the tested implementation and
persistent format, not complete logging performance.

After kron's own CRC moved to 16-byte slicing on 2026-11-01, the 416-group Vort
interoperability check passed again under ReleaseSafe. Native x86_64 then gained
compile-time PCLMUL folding, with the portable table retained for generic/non-x86/
short inputs; the 416-group check passed again and reported `backend=hardware`.
This proves persistent-format compatibility and primitive acceleration; complete
logging throughput still requires same-round measurement, and interoperability
alone does not establish an overall lead.

The ZKV model check passes **3,120 persistent-prefix scenarios** and **8 invalid
boundary scenarios**. It covers dual slots, empty/old valid targets, 0–64-byte
persistent prefixes, direct crash/failed-sync-then-crash, and sequence/epoch
carry and upper bounds. A new checkpoint's valid fields are only the first 20
bytes, with the following 44 bytes unchanged zero padding, so a complete target
entry from prefix 20 onward is identical and can legitimately choose the new
boundary; prefixes 0–19 keep the old boundary. The test uses the actual
`journal/format.zig` encoding/decoding and CRC and cannot represent real
mmap/fsync/physical power loss or guarantee that CRC32 detects every possible
collision.

See [performance-regression.md](performance-regression.md) for the controlled
performance regression tool. Twenty same-binary self-baseline trials completed
delivery, but noise exceeded the threshold and the result was `inconclusive`.
