# Conditional progress wake experiment: not promoted

Baseline `c4b7f34`. The explored runtime registered blocked producers and
flush waiters, advanced a seq_cst progress epoch, and issued futexWake only
when registered waiters existed. It was removed from production after the
complete-workflow comparison failed to qualify an improvement. Final runtime
production source is restored to the baseline. Only an actual Memory/Mmap
worker-failure wake regression is retained.

`progress-candidate.zig`, `after-source.tar.gz` and
`rejected-implementation.patch` retain the tested protocol and exact rejected
source. Its three tests cover notification before registration, publication
between epoch check and actual futex entry, spurious returns, epoch wrap and
all four registered waiters over32 repeated contexts. Debug/Safe/Fast pass.
A public idle-batch test proves the baseline issues an unconditional wake
without waiting callers (idle-before-test.log); that candidate-specific test
is retained as evidence, not as a passing current-production requirement.

160 complete-file before/after trials cover shared/SPSC, Memory/Mmap,
P1/P4, batch and sampled, five alternating pairs,100k records plus1k warmup.
Independent output oracle checks **16,160,000 physical JSON records**, all
measured accepted=written, drop/pending0. Same system wall clock,256 slots
and512-byte payloads,64KiB file buffer, consumer quantum4 and CPU0/2/4/6/8/10.
Throughput includes producer, checked consumer/file output, final written
flush, shutdown and cleanup; startup and sampled percentiles remain separate.
All output hashes/metadata/IDs/bytes and source/executable guards are retained
in workflow-results.jsonl and comparison.json.

Batch through-close median changes: shared Memory P1 -7.56%, P4 -4.24%;
shared Mmap P1 -8.60%, P4 -5.08%; SPSC Memory P1 -1.74%, P4 +0.29%;
SPSC Mmap P1 -4.24%, P4 -0.97%. All bootstrap median intervals overlap,
and most groups exceed10% CV/spread. Several low-variance negative medians
remain. No overall throughput or tail improvement is qualified, so the
registered-counter/stronger-atomic runtime variant is not retained.

Two traced SPSC Memory P4 runs independently verify202000 physical records.
The baseline uses11668 futex calls and1582 pwritev; the candidate uses12074
futex calls and1582 pwritev. This saturated workload keeps real waiters,
so skipping wakes with no waiters does not eliminate most wakes. Tracing
changes the schedule; these are observations, not a causal regression proof.
The registration RMWs and revised synchronization are additional costs.

The retained public regression blocks a real sink write, fills an SPSC
channel, observes its producer waiting on the actual progress futex, then
fails the sink. For Memory and Mmap, worker failure wakes the producer,
propagates the write error, and keeps both accepted records unreclaimed
(written0,pending2). The existing shutdown and deadline tests keep passing.
`final-integration-safe.log` runs the restored production implementation and
passes13/13 public runtime tests. Candidate integration-safe.log predates
this additional retained failure regression.

Final current file-backend measurements use the restored implementation and
are recorded separately in ../2026-11-01-uring-current/. Those portable versus
io_uring results are not mixed with these rejected synchronization candidates.
