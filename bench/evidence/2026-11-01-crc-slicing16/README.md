# Portable slicing-by-16 CRC evaluation

The actual full file-workflow profile locates the largest sampled hotspot in
journal CRC. The before profile has 23.87% self overhead in slotChecksum; the
after build shows 19.68% in Crc32.update after different inlining. Each trace
contains roughly 1K core-PMU samples. Profiles include startup, so percentages
locate work and are not a paired end-to-end speedup claim. Kernel symbols were
unavailable; userspace symbols and call chains were recorded.

The production CRC processes 16 rather than eight bytes per slicing iteration,
then retains eight-byte and byte tails. IEEE polynomial, seed, reflection,
final XOR and every commit/peek/reclaim checksum remain unchanged. The immutable
lookup table grows from 8KiB to 16KiB. No CPU dispatch or dependency is introduced.

Five standalone process pairs on CPU0 record userspace `cpu_core` instructions
and cycles. The process includes setup/oracle checks, reporting and the mixed
CRC batches up to 16KiB. Median instructions increase 4.31%; median cycles
decrease 24.41%. Counter values are highly repeatable. This supports a local
primitive cycle improvement and does not claim fewer instructions or whole
logging throughput improvement. Wall-clock microbench comparisons remain
inconclusive under the 10% noise limit.

| Complete workflow case | Before median records/s | After median records/s | Status |
| --- | ---: | ---: | --- |
| shared memory P1 | 1,025,764 | 1,042,006 | Inconclusive |
| shared memory P4 | 1,029,520 | 1,089,016 | Inconclusive |
| shared mmap P4 | 1,028,947 | 1,025,446 | Inconclusive |
| SPSC memory P1 | 1,058,806 | 971,337 | Inconclusive |
| SPSC memory P4 | 1,128,794 | 1,167,662 | Inconclusive |
| SPSC mmap P4 | 1,069,188 | 1,083,124 | Inconclusive |

The 120 trials use 100K measured records plus 1K warmup, five alternating
before/after pairs, complete JSON, system clock, the same queue/file budgets,
and final written flush/shutdown/object cleanup. Every physical output record
is independently parsed and validated; 12,120,000 complete records passed.
Memory and mmap are compared separately. Producer sampled tails remain in
`workflow-comparison.json`, including every outlier.

The apparent P1 short-batch decline was audited with ten million-record trials.
Those pass 10,010,000 complete records; medians are 1,229,827 -> 1,308,962
records/s, still inconclusive. The candidate has a slow run at 264,372 records/s
that remains in the report. Longer trials do not eliminate shared-host noise.

Three CRC tests include standard vectors, prior oracle checks and 1,152 new
unaligned length cases with 11,520 partition checks through 64KiB. Vort's actual
local code verifies 416 interoperability cases. Six real file-delivery faults,
12 live random-SIGKILL scenarios and six negative recovery oracle tests passed.
Final ReleaseFast `verify-local` passes 76/76 steps and 469/469 Zig tests,
including the full configuration/decoder/lifecycle gates and eight examples.
The final ReleaseSafe gate emits all nine target objects and passes six file
fault tests. `qualification.json` records source and evidence identities.

`before-source.tar.gz` keeps the original production source and full-workflow
benchmark. Raw process reports, perf CSV, original traces, source/binary hashes
and exact flags remain in this folder. Both application and kron were built
ReleaseFast with frame pointers in these comparisons. This differs from the
earlier C++ comparison build; the two result sets are not mixed.

```sh
zig build bench-crc -Doptimize=ReleaseFast -j1
zig build check-local-reuse -Dvort-path=/path/to/vort -Doptimize=ReleaseSafe -j1
```

Mechanisms learned from Quill, Foundation, fmtlog, NanoLog, Reckless and BqLog,
including the normal-runtime checksum difference, are documented in
[industry-performance-lessons.md](../../../docs/industry-performance-lessons.md).

The two profiled million-event output files were independently validated as
well; `profile-output-validation.json` retains their complete byte counts and
file hashes. Temporary copies were removed after validation. Profile sample
percentages remain qualitative hotspot evidence, not a stable speedup claim.
