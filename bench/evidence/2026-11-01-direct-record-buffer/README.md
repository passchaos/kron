# Direct complete-record rendering into FileSink staging

Baseline `c2f8792`. The original consumer renders into runtime scratch and
copies each completed record into FileSink's staging buffer. The candidate
offers a synchronous optional sink transaction: a renderer receives exactly
the existing runtime record budget from the unused staging suffix. Success
publishes only its complete prefix. A callback/error never flushes earlier
accepted bytes or advances the accepted length. Failed/closed sinks, sinks
without the capability, or insufficient suffix space decline without invoking
the callback; the ordinary render-and-write path retains its error order.

The runtime tries this only for one selected route, preserving shared encoding
for multi-route fanout. Materialized text/JSON/logfmt/binary and eligible fused
inline/schema records use the same owning encoders and validation. Callback
errors remain encoding errors even for best-effort routes; sink transaction
errors still follow required/best-effort write policy. The caller's scratch
limit, route timestamp options and output bytes do not change. No I/O occurs
before successful rendering and no buffer address escapes the synchronous call.
The existing io_uring backend still copies completed batches into its stable
pool; this candidate removes only runtime-scratch-to-file-staging record copies.

FileSink rejects render reentrancy, write/flush/shutdown during a callback and
deinit during rendering. Callback storage is borrowed; the callback must not
retain it, mutate other sink state or reenter the destination. A rejected tail
may contain scratch bytes but is not accepted and cannot be flushed. Append
offset overflow and invalid returned length retain the earlier accepted prefix.
Each callback result is checked before the staging length advances.

## Semantic evidence

Tests compare direct and ordinary byte output for three text formats plus
binary, deferred messages, nested/secret/source/trace fields and readable time.
Untouched runtime scratch proves the supported direct path was used; a nearly
full suffix forces and verifies the ordinary fallback. Wire/schema malformed
boolean and duplicate-key errors produce no accepted record even on best-effort
routes; error classification and encoding-before-sink-failure remain unchanged.

File transaction tests use a failing allocator after init, assert the callback
points at the actual unused staging suffix, inject callback failures and bad
lengths, check overflow and recursive calls, and verify only the complete prefix
is written. An initial test erroneously read through the write-only sink file
and failed `NotOpenForReading`; the final test reopens a read handle and passes.
Actual portable short-write/zero-progress/disk-error tests confirm byte progress,
accepted ownership, latched errors and later callback rejection.

Final related ReleaseSafe scope passes33/33 tests (`related-safe.log`), including
existing coalesced checked/failure/reclaim and schema mutation/runtime fault
checks. The production baseline remains frozen in before-source.tar.gz and
before-provenance.json; candidate sources and binary have separate identities.
Earlier subset logs did not discover delivery tests until their owning module
was explicitly imported from the runtime test block; final coverage includes
the actual tests. No earlier subset is described as that full coverage.

## Performance qualification

`measure.py --pmu` runs five paired complete-file user-counter comparisons for
inline SPSC Memory P4, inline shared Memory P1, schema SPSC Memory/Mmap P4.
`measure.py` compares Memory/Mmap shared/SPSC P1/P4 schema, with inline P4
control paths, batch and sampled phases. All cases use complete JSON and system
wall time,256 queue slots/512-byte payloads,64KiB file buffer, four consumer
quanta, fixed CPU0/2/4/6/8/10 affinity and actual portable backend. Throughput
ends after written flush, shutdown and cleanup; initialization/preparation and
tails are recorded separately. No durable media flush is requested.

The owning independent file oracle validates every physical record and hash.
Source/binary guards execute before and after each trial. Full positive/negative
observations, CV/spread/bootstrap intervals and failed/incomplete captures are
retained. A local CPU reduction does not establish stable end-to-end improvement
or new Foundation/spdlog/io_uring ranking. Final gate and performance decisions
are recorded only after capture and verification finish.

## Decision: rejected, production restored

All280 trials complete and independently verify **36,280,000 physical JSON
records**. The40-trial PMU comparison finds repeatable instruction increases:
inline SPSC Memory P4 +0.598%, inline shared Memory P1 +0.640%, schema SPSC
Mmap P4 +0.496%, schema SPSC Memory P4 +0.479%. The interval pairs do not
overlap. Each group has a negative throughput median in that PMU capture,
with overlapping intervals; cycles provide no unambiguous qualified gain.

The independent240-trial whole-file capture has overlapping throughput median
intervals in every group. Inline P4 shared Memory −0.685%, shared Mmap −1.331%,
SPSC Memory −0.755%; schema shared Memory P4 −1.144%. Positive medians exist
for some P1/schema groups, but none establishes an overall qualified throughput
gain. Shared schema Mmap P1 has a negative11.051% median with large variance,
retained as inconclusive. Tails are mixed; inline SPSC Memory P4 p99.9 rises
343893→353480ns within the local repeatability budget, with interval overlap.
Every slower sample and per-metric interval remains in the comparison files.

The extra interface, callback dispatch and staging-state checks therefore do
not meet the evidence threshold for promotion. The entire candidate and its
tests are retained in `after-source.tar.gz`; production src is restored exactly
to `c2f8792`. No public `renderRecord` capability or borrowed staging buffers
are shipped. Narrow candidate Debug/Fast checks each pass17 tests, Safe related
scope33 tests; broad platform/fault gates are not rerun on a rejected candidate.
The restored exact baseline retains its545/545 ReleaseSafe and nine-platform
object evidence from the owning prior commit. This rejection narrows future
work: removing a fast copy must outweigh its required ownership/dispatch costs.
