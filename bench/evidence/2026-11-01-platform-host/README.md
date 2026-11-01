# Native Zig platform host qualification

The independent Zig consumer now provides `qualify DIRECTORY`. Its test logic
runs entirely in Zig with the host's allocator and `std.Io`. Mobile Zig hosts
can call `tests/package_consumer/platform.zig`'s `run` function inside their
sandbox. Python is only the local build/run/report wrapper.

The suite checks real Unicode file names, sync/memory/mmap/shared/SPSC logging,
filter reload, capture ownership, sensitive-value masking, ordinary and timed
flush capabilities, shutdown, and no runtime allocator calls after setup.
It opens inline and schema journals, verifies exclusive ownership, retains a
reservation gap plus a complete record across close/reopen, inspects twice
without changing the journal, then reclaims the recovered record. Rolling-file
retention and explicit synchronization are checked separately.

| Evidence | Scope |
| --- | --- |
| linux-safe.json | Five native runtime modes and the complete journal/rolling suite, ReleaseSafe |
| linux-single-safe.json | Native synchronous runtime plus journal/rolling suite, single-threaded ReleaseSafe |
| linux-fast.json | Five native runtime modes and the complete journal/rolling suite, ReleaseFast |
| distribution-safe.json | The same suite through a fetched, unpacked source distribution |
| windows-link.json | Actual Windows PE executable with the suite linked; no runtime test |
| package-test-safe.log | Two independent Zig package tests, including refusal to overwrite an existing qualification |
| host-gate-safe.log | The root `test-platform-host` build/run gate |

```sh
zig build test-platform-host -Doptimize=ReleaseSafe -j1
cd tests/package_consumer
zig build run -Doptimize=ReleaseSafe -- qualify /tmp/kron-native-host
```

The suite creates `DIRECTORY/native-check` and refuses to reuse an existing
folder. Artifacts remain for inspection when called directly. `confirmed` means
the explicit synchronization protocol succeeded on that host/storage;
`unsupported` records an explicit platform/filesystem capability rejection.
Other I/O failures fail the suite. Windows must report unsupported strict
directory durability while retaining ordinary logging functionality.

Closing/reopening in one process is not forced process termination, a system
crash, physical power loss or app suspension. Those require separate evidence.
No Windows/Apple/Android runtime environment is available on this host; Linux
runtime and Windows link results do not qualify those four device platforms.
The JSON reports identify actual host, Zig version, source hashes and binary
hashes. `qualification.json` collects the final source and evidence identities.
