# Linux whole-file publication without duplicate mapping sync

Baseline commit `3e1dcc9`. Before/after full sources, exact implementation
patch and executable hashes are retained in source archives and provenance
files. Only the Linux/Android cold mapping publication path removes its
msync(MS_SYNC) before whole-file fsync. File fsync and directory fsync remain;
strict durable Mapping.sync/syncFile, journal checkpoints/reclaim, schema
readiness, preallocation and writable prefault remain unchanged. Other OS
backends still perform their original mapping flush before file publication.
Memory queues have no mapped-file publication and keep the same behavior.

## Owning-source contract

Linux6.8 mm/msync.c executes vfs_fsync_range(file, start, end, datasync=1).
fsync in fs/sync.c executes the same per-filesystem operation over
[0, LLONG_MAX], datasync=0, including all file data and metadata. On ext4,
ext4_sync_file calls file_write_and_wait_range, journal commit, required device
flush and file_check_and_advance_wb_err. The syscall facade's std.Io.File.sync
actually invokes fsync. The whole-file fsync covers dirty MAP_SHARED page
cache pages, so a previous range sync is redundant for cold publication.
The directory barrier is still separate. Exact URLs, file hashes and source
excerpts are in linux-sync-source.json and ext4-sync-source.json; Linux man
pages describe the corresponding whole-file and directory guarantees.

This is a Linux-specific property; it is not generalized to Darwin or
Windows FlushViewOfFile/FlushFileBuffers. The explicit strict durable API
still has its original mapping/file/directory sequence. No kernel parameter,
filesystem mount, device-cache policy or dependency is changed.

## Fault and restart proof

Creation fault tests fail file-sync or directory-sync independently. Both
propagate InputOutput and release the exclusive journal lock/mapping so a
new owner can retry. Schema directory failure after successful file sync
retains the descriptor but does not set ready; reserve fails SchemaNotReady
and does not advance the reservation target. Successful retry executes both
remaining barriers, keeps schema identity and accepts the event. Existing
failed-file-sync and reopen-ready tests continue passing.

Fresh static ReleaseSafe writer tests inside isolated QEMU guests pass
schema ACK17 and ACK31 (crossing16-slot reuse) and inline ACK3. QEMU is
actually SIGKILLed after completed acknowledgements. Snapshot verifier boots
confirm every acknowledged JSON record and checkpoint, and the harness
checks the raw crash image is unchanged by verification. Exact transcripts,
writer/kernel/BusyBox/config hashes and image hashes are retained in vm-*.log,
vm-*/ and vm-results.json. Raw128MiB scratch images remain in .zig-cache
paths recorded there. This proves those child-VM/ext4 trials, not physical
host power loss or arbitrary filesystem/device qualification.

## Syscall and complete-workflow measurement

strace captures real P4 SPSC Mmap initialization plus1000 file records.
Both outputs pass the independent file oracle. Original:5 msync,10 fsync,
5 fallocate calls. Candidate:0 msync,10 fsync,5 fallocate. The traced cold
init is1.718s before and1.842s after; after spends about1.746s in one fsync.
These individual observations show the kernel waits remain and do not prove
speedup. Original logs and durations are retained in trace-summary.json.

160 complete-file paired trials cover shared/SPSC, Memory/Mmap, P1/P4,
sampled/batch and five before/after pairs. Independent oracle verifies all
**16,160,000 physical JSON records**, every measured accepted=written100000,
all pending/drop0. System clocks,256 slots/512-byte payload,64KiB file buffer,
CPU0/2/4/6/8/10 affinity and per-record confirmation remain identical.
Init/preparation and shutdown/cleanup are independently timed; full-written
throughput includes final file flush and close. No device-durable flush is
requested in this workflow, but cold journal file publication remains.

| Batch config | before init ms | after init ms | before close M/s | after close M/s |
| --- | ---: | ---: | ---: | ---: |
| shared Memory P1 |0.578|0.611|2.034|2.033|
| shared Memory P4 |0.575|0.575|1.977|2.052|
| shared Mmap P1 |18.594|406.486|1.885|1.721|
| shared Mmap P4 |18.441|98.394|2.049|1.847|
| SPSC Memory P1 |0.663|0.672|2.160|2.158|
| SPSC Memory P4 |0.990|0.918|1.914|2.087|
| SPSC Mmap P1 |36.007|18.736|2.042|1.907|
| SPSC Mmap P4 |1081.455|839.219|1.628|2.002|

Every group is **inconclusive**, with overlapping bootstrap median intervals.
Shared Mmap has negative init medians; SPSC Mmap init medians are positive
in this window. All slow observations are retained, including init spread
above60x in one baseline group. The valid conclusion is removal of redundant
synchronous filesystem operations, not a stable cold-start or full-workflow
throughput win. `comparison.json` records all counters, timings, p50/p99/p99.9,
CV/spread and bootstrap intervals; `workflow-results.jsonl` retains every
file's hashes/counts and source/executable guards. There is no new
Foundation comparison in this experiment. Earlier cross-library results
cannot be updated by adding this local percentage.

## Reproduce

```sh
zig test src/root.zig -O ReleaseSafe --test-filter 'publication'
zig test src/root.zig -O ReleaseSafe --test-filter 'directory sync failure'
zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all
zig build check-platforms -j1 --summary all
```

Performance capture rebuilds the frozen executables and uses the guarded
measure.py script with a fresh output folder; do not overwrite completed
evidence. Final composite/platform counts and current source identities
are recorded in qualification.json once the gates finish.

Final ReleaseSafe `verify-safe.log` passes **89/89 build steps and 532/532
tests**, including publication/file/directory/schema faults, actual SIGKILL,
Memory/Mmap ownership, no-allocation paths and independent package consumers.
Directed Debug publication failure and ReleaseFast sync gates also pass;
their exact scopes are preserved in the corresponding logs.
`platforms.log` generates all nine actual ReleaseSafe target objects,
10/10 steps passing. `qualification.json` binds gates, frozen source identities,
VM confirmation points and syscall counts to the remaining performance limits.
