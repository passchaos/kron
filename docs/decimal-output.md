# Decimal record output and complete-string escaping

Complete text/JSON/logfmt output does not need base, width, precision, or
alignment options for numbers. This path uses a dedicated decimal writer: small
integers keep the native digit-pair loop, large u64 values split into at most two
10^8 tails, and each tail generates eight fixed digits from a u32; smaller
i128/u128 values reuse the native path, while wide values split by 10^19 and
generate decimal digits separately. Non-leading blocks are zero-padded to 19
digits, including all-zero blocks; at most two wide splits avoid per-two-digit
wide division. The sign is handled through a safe unsigned absolute value,
including the i128 minimum.

For values within 64 bits, when the current Writer has at least 21 bytes left,
the exact digit count is computed and written directly into the existing buffer;
only the actual length is published, without calling drain/rebase. Small
buffers, unbuffered streaming Writers, and wide values above u64 continue to
generate into a stack buffer of at most 40 bytes and perform one `writeAll`,
without generic alignment. A separate native large-number helper and cold
buffered function keep extra registers/temporary frames on the paths that need
them, so ordinary small numbers do not carry that frame; the fixed powers table
is 160 bytes. JSON integers outside ±(2^53−1) are still written as decimal
strings; float, NaN/Inf policy, and base/width/precision in deferred formats keep
the original generic formatter. This optimization does not change capture
representation, journal CRC, schema, accepted/written/durable boundaries, or
file-buffer budgets.

A fully available string calls the same module's `QuotedWriter.consume`
directly, avoiding the unbuffered Writer drain vtable first. Deferred messages
still use the streaming QuotedWriter for UTF-8 fragments spanning arguments;
complete and streaming strings share the same consume/byte state machine,
preserving reversible representation of malformed UTF-8, control characters,
newlines, and JSON keys.

Foundation DefaultFormatter's sequential number generation and direct copying
were the reference direction. This round kept the original streaming Writer
interface and per-output byte-prefix behavior, without whole-event two-pass length
accounting, complete-message scratch, or copied upstream code. Number generation
is centralized in `decimal.zig`, escaping remains in `escaping.zig`, and record
layout plus safe tree validation remain in `common.zig`.

The latest eight-digit chunking/cold-buffered optimization verified 140 real-file
trials and 42.14 million JSON records. Complete user instructions for shared
Memory/Mmap P1/P4 fell by about 3.43%–3.47%, with four groups having
non-overlapping median intervals; five native primitive instruction classes fell
by about 9%–10%, and field-combination/full-u64/signed/wide cycles also had local
qualification. Formal batch throughput medians were positive, but all speed-ratio
intervals overlapped, and a first-round sampled Mmap P1 −6% did not reproduce in
an independent 20-trial recheck; no general throughput/tail win is claimed.
Current Safe passed 151 steps and 639 tests with one capability skip, and
integer/short-write plus native/generic/aarch64 compile boundaries were retained.
Historical numbers below are bound to their own source revisions.

## Correctness verification

- Three new tests compare all 65,536 u16 values byte-for-byte with the standard
  formatter; native integer extremes, 39 decimal boundaries, 128 binary
  boundaries, all-zero blocks, and 2,048 random u128/i128 pairs match.
- All short fixed-Writer prefixes for the minimum signed integer and maximum
  unsigned integer are compared with the standard formatter. A bounded Writer
  failure is never treated as a complete-record success.
- A frozen complete old module and the current module each call the public
  encoder; 12 complete text/JSON/logfmt outputs and 16,486 fixed-buffer capacity
  prefixes match byte-for-byte.
- An independent generic Writer accepts only 1/3/7 bytes at a time and triggers
  failure at every byte budget; 49,494 complete/failure output prefixes match the
  old implementation, and neither side calls the Writer again after an error.
- UTF-8 fragment joining, nested values, all value tags, integer JSON boundaries,
  source, trace, secret, float, and zero output for invalid trees remain covered
  by the original tests.

The measurement boundary for this round is written file flush, shutdown, and
cleanup. Local number-generation gains do not represent durable/fsync throughput
or a cross-library ranking.

## Complete-workflow measurement

Five configurations in separate sampled/batch processes ran five before/after
pairs each, for 100 real-file trials of 100,000 measured records plus 1,000
warmup records, verifying 10.1 million complete JSON records. The system clock,
256 slots/512-byte payloads, 64 KiB file buffer, CPU 0/2/4/6/8/10, final written
flush, shutdown, and cleanup were held constant; initialization and warmup are
reported separately in lifecycle metrics.

| Batch mode | Before median records/s | After median records/s | Median change | This round |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 | 1,092,183 | 1,359,992 | +24.52% | inconclusive |
| shared Memory P4 | 1,217,630 | 1,300,304 | +6.79% | inconclusive |
| SPSC Memory P4 | 1,189,422 | 1,227,039 | +3.16% | inconclusive |
| SPSC Mmap P4 | 1,231,334 | 1,233,869 | +0.21% | inconclusive |
| SPSC Mmap P4 prepared | 1,149,036 | 1,241,312 | +8.03% | inconclusive |

Every throughput group had at least one side's CV or spread above 10%, and
trial-bootstrap median intervals still overlapped. Positive medians cannot be
declared stable speedups; for example, SPSC Memory after spread was about 63.8%,
and all slow values were retained. Before/after runs with identical format,
resource budget, and reliability are compared only within their own
configuration; Memory and Mmap cannot be combined into one gain.

Encoding probes covered five native values, 20 nested values, and five wide
values near the u128 limit, with 300,000 records per class per process and
complete output included in Wyhash. The first probe group overlapped this round's
full-workflow binary compilation, so its instruction/cycle and wall-clock results
are retained but not used as isolated timing qualification. The following five
serial probe pairs had no build/gate overlap, matched output checksums and byte
counts, reduced whole-process user instructions by 18.50% and cycles by 27.14%,
with both PMU counts below 10% CV/spread; wall-clock times remained inconclusive.
These numbers include input updates, encoding, hashing, and startup/reporting and
cannot be converted into file-log gains.

Five additional complete P4 SPSC Memory file-workflow pairs of 300,000 records
verified another 3.01 million logs; all-thread user instructions fell 6.22% with
about 0.02% spread, cycles fell 3.37%, and task-clock fell 3.79%, but the latter
two failed the cross-round threshold. Complete throughput median rose from 1.115M
to 1.285M (+15.31%) and remained inconclusive; related software counts and slow
trials were retained. This supports a real reduction in complete-pipeline CPU
work but does not establish stable latency/throughput gains or a cross-library
ranking.

Final Debug/ReleaseSafe targeted tests passed 26/26 each, complete ReleaseFast
passed 76/76 build steps and 483/483 Zig tests, and nine-target ReleaseSafe
objects plus file/configuration checks passed 18/18. Later time-handling work has
its own implementation and evidence and is not mixed into this round's source
identity.

## Current direct-buffer path

After the current baseline `20d49be` complete-file profile confirmed a small
memcpy hotspot, native direct number output was implemented. New tests cover all
decimal/binary native boundaries, 4,096 random native pairs, existing-prefix and
unused-buffer sentinels, 1/20/21/64-byte internal buffers, downstream 1/3/7-byte
short writes, and every physical failure prefix. The final public encoder and
frozen source still match on 12 complete records, 16,486 fixed prefixes, and
49,494 generic prefixes.

Initial inline and digit-count-table variants had about a 3% negative median in
the nested20 probe, and the raw results were retained; the final separate helper
removed that negative median. One hundred formal file trials verified 10.1
million logs; shared Memory P1/P4, SPSC Memory P4, SPSC Mmap P4, and prepared
improved by about 3.86%/3.40%/4.04%/3.00%/3.31%, with both-side CV/spread below
10%; only SPSC Memory P4 had non-overlapping trial-bootstrap median intervals,
while the others still overlapped.

Another 20 complete-file user-PMU trials verified 6.02 million logs: SPSC Memory
P4 cycles fell 4.99% and instructions rose 1.00%; shared P1 instructions rose
1.04% and cycles remained inconclusive. The SPSC long workflow retained a
candidate slow value, keeping throughput inconclusive. This is a change in the
instruction mix and copy cost, not an instruction reduction on every path; local
gains cannot be accumulated into a cross-library lead.
