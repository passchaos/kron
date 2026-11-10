# Configuration reuse in background batches

After the background takes a bounded checked-delivery window from a journal, it
holds one protected View for each configuration generation in that window. The
current window can merge records already ready within the remaining 64-record
service quanta, up to 256 by default; later records with the same generation and
fingerprint reuse the View instead of scanning the configuration table and
incrementing/decrementing reader counts per record. A configuration group still
has at most 64 entries, matching the configuration table limit. This borrows the
direction of Quill and Foundation coalescing repeated consumer operations into a
batch; journal commit, CRC, ordering, and per-record reclamation checks are
unchanged. See [coalesced delivery](coalesced-delivery.md) for the new window's
write/acknowledgement trade-off.

The temporary batch object lives on the consumer stack with fixed capacity for 64
groups and allocates no heap memory. After decoding, records still verify their
complete configuration identity and route_mask and are delivered by original
route, format, and sink; each group accumulates its route mask and executes the
same written/durable barrier. Old Views are released only after the entire batch
is delivered, barriers complete, and records are reclaimed. Error paths release
batch Views through `defer` without dropping pending pins for unacknowledged
records or triggering early resource-lease release.

Records captured by the current Runtime have a definite nonzero route generation.
Historical generation=0 records re-run the complete `Manager.find` fingerprint/
ambiguity check every time, then reuse the same resolved snapshot; the first hit
never replaces historical recovery-identity validation. Filter-only reload and
full replacement publish as before, and the cache exists only for the current
batch without retaining raw pointers across batches.

Each record is still acknowledged independently, and all original CRC checks
continue. This round of configuration View reuse did not introduce a batched
reclamation API or change accepted/written/durable protocols. Durable-route
bitmap precomputation and contiguous-channel written accounting were added
separately; see [batch acknowledgement and accounting](batch-accounting.md).
Journal cursors and reclaim remain per-record, and snapshot reuse is not the same
as completing all batch processing.

## Verification

Module tests directly check real `Manager.find` call counts: 64 selections of the
same generation perform one lookup; 64 different generations each perform one
lookup, even when target fingerprints match, and keep independent Views. The old
generation cannot be collected while a View is held; after the batch ends it can
be reclaimed and the lease is released exactly once. Wrong fingerprints/unknown
generations still return errors; historical generation=0 re-looks up every time
and reuse does not allocate.

A real background test uses a reservation gap to prebuild 31 complete events,
then opens the consumer and verifies that shared and SPSC queues perform no extra
`find` calls across 31 sink callbacks. Another mixed-generation test verifies that
when a new sink fails, the old output prefix is preserved, all six journal records
remain, written is zero, neither generation leaks a temporary reader, and record
pins and leases remain. Existing configuration transaction, hot resource
replacement, deadline, and cross-process recovery tests continue to run.

The complete-workflow before/after comparison uses the same JSON layout, system
wall clock, 512-byte journal payload budget, 256-slot queue, 64 KiB file buffer,
written flush, and shutdown/cleanup. It includes shared/SPSC, Memory/Mmap, and
prepared schema, with fixed CPU affinity and alternating trial order. A local
reduction in lookup count does not convert directly into end-to-end log
throughput.

## Complete-workflow measurement

Five configurations, sampled/batch in separate processes, five before/after pairs
each, for 100 trials. Each trial used 100,000 measured records and 1,000 warmup
records, parsing and verifying 10.1 million complete logs. Application and
library were built with ReleaseFast and frame pointers, fixed to CPU
0/2/4/6/8/10. Producer time, final written flush, shutdown, object cleanup, and
call quantiles were recorded; no timestamps, fields, or error checks were omitted.

| Batch mode | Before median records/s | After median records/s | Qualification |
| --- | ---: | ---: | --- |
| shared Memory P1 | 1,156,635 | 1,259,012 | about 8.9% local gain; cross-round spread below 10% |
| shared Memory P4 | 1,112,450 | 1,138,738 | inconclusive |
| SPSC Memory P4 | 1,098,274 | 1,205,207 | inconclusive |
| SPSC Mmap P4 | 1,143,207 | 1,165,445 | inconclusive |
| SPSC Mmap P4 prepared | 1,194,094 | 1,159,759 | inconclusive |

These are same-condition results on this development host and do not represent
every workload or platform. The prepared scenario showed no gain, and higher
producer speed also changes backpressure and background batch size; stage medians
cannot be subtracted to explain per-record cost. All min/max, quantiles, and slow
values were retained. Existing cross-library comparisons used different build
snapshots and would need a same-round rerun after cumulative optimizations.
