# Coalesced delivery window for ready records

The background accounts queue budget in 64-record service quanta, and
`consumer_batches_per_queue=1..4` sets a per-round upper bound of 64–256 records.
One checked peek can now take contiguous, fully committed records within the
current remaining budget and let them share a configuration View, output flush,
and consumer-progress notification. It never waits for later producers to fill the
window and never skips an incomplete reservation.

Assume four quanta remain and the queue already has 255 contiguous records: the
old path flushed at most every 64 records, while the new path can write all 255
and execute one window barrier, then reclaim per record. If only one record is
present, it is delivered immediately and charges one quantum; the remaining three
quanta can serve at most another 192 records. Producers submitting during
delivery therefore cannot extend this round's service volume indefinitely.

The default per-queue service upper bound remains 256 records; an explicit budget
of 1 remains 64. Placing 160 backlogged logs after the first record already being
delivered still serves the peer at positions 1/65/129/161 for budgets 1/2/3/4.
This guarantees a record-count budget, not an OS wall-clock scheduling bound. A
larger acknowledgement window may reduce writes and wakeups but can change
full-queue call quantiles, so it must be verified on the actual workload.

## Write and reclaim order

All records in the window first pass checked peek, validating committed state,
length, generation, CRC, and schema readiness. Corruption found later in the
window fails the whole peek and no record reaches the sink. Configurations are
looked up by the generation/fingerprint captured with the event; each distinct
generation holds an independent View, and one window contains at most the 64
generations allowed by the current configuration table.

Each event is output through its original route, then the written/durable barriers
required by each configuration group in the window execute. After all required
barriers complete, the journal still runs the original `releaseAfter` check and
reclamation per record, and configuration record pins are released per record;
accepted records are not released early, the second CRC is not skipped, and the
checkpoint protocol is unchanged.

If output or flush/sync fails, every record in the window is retained. If output
completed but later corruption occurs during reclamation, only the actually
reclaimed prefix is acknowledged, and written counts and configuration pins follow
that prefix. Views are released during error unwinding, and unreclaimed records
continue to protect the old configuration and resource lease. Earlier records may
already be written while still retained; crash recovery continues to use
at-least-once semantics with identifiable duplicates.

## Resources and verification

Records, channels, snapshots, and boundary scratch are reserved as fixed 256-item
storage on the consumer stack; the configuration-group array remains 64 items.
No producer work or heap allocation is added, and journal, sink, and in-flight I/O
budgets do not grow. Consumer stack space increases; current-target sizes are
recorded in measurement evidence.

Real Runtime regressions cover Memory/Mmap, shared/SPSC, and ordinary/schema
(eight combinations); 255 ready records all output on the first flush, and the
failing allocator installed after initialization receives no new calls. They also
verify zero output for initial corruption later in the window, retention of all
records and both-side pins on old/new configuration flush or durable failure, and
that corruption at reclamation of the 191st record acknowledges only the first
190 while the remaining 65 continue to protect the old configuration. Existing
full-queue shutdown wakeups, deadlines, and real file-fault tests continue to run.

This optimization coalesces already-ready records; it does not use timed
fill-batching or low-frequency log buffering. Performance evidence compares
Memory/Mmap and portable/io_uring separately while preserving complete JSON,
system wall clock, final written flush, shutdown, and file verification. Local
improvements cannot be generalized to untested workloads or a cross-library
ranking.
