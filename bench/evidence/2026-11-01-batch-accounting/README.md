# Batch durable decisions and acknowledged written counts

The consumer derives a required-durable route bitmap from each protected
configuration View. Each event selects its reclaim boundary once and retains
the existing full route mask for the durable barrier. Journal CRC, ordering,
slot release, schema ownership and checkpoint protocols still run per record.

WrittenCounts aggregates consecutive acknowledged records for the same channel.
It uses atomic fetchAdd when the channel changes, before successful progress
notification, and on error cleanup. Only successful releaseAfter and record-pin
release add a record. Concurrent synchronous/fallback increments remain intact.
An actual shared/SPSC batch of 31 records now requires one written update.

Four new substantive tests cover the durable-mask oracle, consecutive-channel
counting, concurrent sync/fallback increments and a late reclaim failure. The
existing real batch test also checks the written update count. A separate test
copy of the old implementation fails as expected with `expected 1, found 31`;
its audit/test delta is preserved in `before-written-update-oracle.patch` and
does not modify the frozen measurement baseline.

The late-corruption case writes three complete outputs, then damages a later
record during sink flush. Only one record reclaims successfully: written=1,
pending=2, with both remaining configuration record pins retained. The normal
mixed-generation sink failure, temporary View ownership, lease and deadline
tests remain part of verification.

| Full batch file workflow | Before median records/s | After median records/s | Assessment |
| --- | ---: | ---: | --- |
| shared Memory P1 | 1,272,767 | 1,252,057 | Inconclusive |
| shared Memory P4 | 1,221,402 | 1,226,962 | Inconclusive |
| SPSC Memory P4 | 1,192,114 | 1,173,534 | Inconclusive |
| SPSC Mmap P4 | 1,220,463 | 1,205,500 | −1.23%; noise threshold passed, overlapping CIs |
| SPSC Mmap P4 prepared | 1,230,803 | 1,273,351 | +3.46%; noise threshold passed, overlapping CIs |

There are 100 independent processes: five cases, sampled/batch phases, before/
after labels and five alternating pairs. Each process writes 100K measured and
1K warmup records on CPUs 0/2/4/6/8/10. Every physical JSON record is validated
by the existing independent run.py oracle: 10,100,000 records, with exact field
values, complete event identities, output bytes, accepted=written, pending/drop=0.
Full JSON, system clocks, queue capacity and payload/file-buffer budgets remain
the same. Memory/mmap, shared/SPSC and prepared/inline retain separate results.

Written throughput includes producer work, final written flush, shutdown and
object cleanup. Initialization/preparation are reported separately and included
in lifecycle metrics. This is not a durable/fsync throughput experiment; the
durable decision is independently checked against the previous scanning oracle.

`stable_local_measurement` means both trial CV and relative spread are below
10%. It does not establish statistical significance. Both qualifying mmap
throughput cases still have overlapping trial-bootstrap 95% median intervals;
all slow trials and noisy tail metrics are retained. This change reduces
operation counts but does not establish stable end-to-end improvement or a new
Quill/Foundation ranking.

`before-source.tar.gz` preserves the original src tree, identical Zig driver,
source manifest and independent output/statistical helpers. `implementation.patch`
shows the three modified implementation/test files. `provenance.json` identifies
both binaries, all before/after source hashes and the passed measurement source
guard. Application and library are both ReleaseFast with frame pointers.

To rebuild the frozen before binary, extract the archive into an empty
directory and run the build argv in provenance.json with the recorded Zig
toolchain. Build the candidate from the working tree with the same module
optimization flags. Each row in workflow-results.jsonl preserves its exact argv;
replace only the binary and temporary output paths when replaying. Pass the
report and produced output to run.py's verify function before computing trial
summaries using regression.py's summary function.

The current Debug and ReleaseSafe scoped root test runs both pass 13/13 tests,
including import fixtures and six substantive tests. Full ReleaseFast
verify-local passes 76/76 build steps and 478/478 Zig tests, with the existing
Python, negative compilation, differential, package/host and process-crash gates.
The final ReleaseSafe gate passes 22/22 steps: all nine target objects are emitted,
and configuration/transaction/deadline/real-file-failure tests pass 37/37.

Final verification logs and qualification.json record the exact tested sources
and the scope of the platform gate. Cross-compilation does not establish actual
Windows/macOS/Android/iOS device runtime or physical power-loss qualification.
