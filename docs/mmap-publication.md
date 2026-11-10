# Linux Mmap initialization and schema publication

Linux/Android cold publication uses a whole-file `fsync`, then synchronizes the
parent directory. The Linux kernel's `msync(MS_SYNC)` calls
`vfs_fsync_range`; `fsync` calls the same filesystem operation over the whole
file and includes file metadata. A cold publication that calls `msync` and then
`fsync` therefore waits twice for the same mapping data to be written back.

`platform.Mapping.publish` omits the preceding `msync` on Linux/Android while
keeping whole-file `fsync` and parent-directory `fsync`. Other platforms keep the
original mapping-flush and file-publication order. Explicit
`Mapping.syncFile/sync`, journal durable checkpoints, and durable reclaim still
follow the original mapping/file/directory synchronization protocol.
Initialization still performs file preallocation and writable-page touching; file
format and resource budgets are unchanged.

This is a Linux file-synchronization contract and cannot be generalized into
mapping-flush equivalence on every platform. The source basis comes from Linux
v6.8 `mm/msync.c`, `fs/sync.c`, and `fs/ext4/fsync.c`, including range writeback,
filesystem journal commit, device flush, and writeback error handling.

An initialization file or directory `fsync` failure returns an error to the caller
and releases the mapping and exclusive file lock. During schema publication, even
if file sync succeeds, a directory sync failure leaves the descriptor unready;
producers cannot reserve records that reference that schema, and ready is
published only after a successful retry. Existing failed-sync/reopen qualification
continues to run.

The static ReleaseSafe writer has been verified by force-killing a Linux
6.8/ext4 child QEMU: after schema ACK 17/31 and ordinary inline ACK 3, every
acknowledged JSON record and checkpoint was retained, and snapshot verification
did not change the original image. This is evidence for the specified virtual
machine, filesystem, and acknowledgement points; other platforms and devices
remain on the main acceptance list.

A real four-producer SPSC initialization changed its call counts from five
`msync` plus ten file/directory `fsync` to zero `msync` plus ten `fsync`; the five
preallocations are unchanged. One hundred sixty complete Memory/Mmap, shared/
SPSC, P1/P4 file trials verified 16.16 million JSON records. Startup and
throughput were all marked `inconclusive` because of variance; shared Mmap
initialization had a slower median, SPSC Mmap initialization median fell, and all
slow values were retained. The change reduces duplicate sync calls but has not
qualified a stable cold-start or throughput gain.

A later cross-library performance judgment would still require a same-round
re-measurement with current sources; this local change cannot be added to an older
ranking.
