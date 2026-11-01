# Safe complete-record validation reuse

Public text/JSON/logfmt encoders validate the complete attributes/format-argument
tree once, using the existing shared node/depth/key rules. Rendering then stays
inside private functions in the same module. Standalone common.value still
validates its input, including nested deferred formatting arguments. There is
no exported unchecked writer or retained validation token. Borrowed event
storage must remain unchanged throughout the call, including writer callbacks.

Streaming escaping/key/hex primitives now live in escaping.zig. Complete safe
record rendering stays in common.zig; format-specific public wrappers and
golden tests remain at their original paths. Compile-time layout selection
does not introduce another runtime format switch. Writer operation order,
number formatting, output bytes, journal protocol and output confirmation
boundaries remain the same.

Two new tests verify the actual public format entry points and standalone value
safety. The all-tag event has 14 nodes (including its unused format argument),
each visited once. The independently copied old implementation fails the same
count check with `expected 14, found 27`. This test copy contains added tests
and forced discovery only; the measured frozen source remains unchanged.

`differential.zig` imports the complete frozen and candidate modules separately,
calls only their public encoder APIs, and compares 12 complete outputs and
16,486 short-buffer errors/prefixes. Inputs cover every value tag, scalar extrema,
nonfinite/subnormal floats, nested arrays/groups, malformed UTF-8/keys, source,
trace, erased secrets and deferred UTF-8 fragments. Its ReleaseSafe run passes.

The initial direct encoder/root test command used too narrow a Zig module root
and could not resolve imports; the authoritative scoped checks use src/root.zig.
The initial old-test filter selected only import fixtures; the corrected
independent test copy forces common.zig discovery and demonstrates rejection.
Those preliminary logs are retained and are not passing-gate evidence.

`measure.py` records five alternating before/after pairs for five separate
memory/mmap, shared/SPSC, P1/P4, inline/prepared cases, with batch and sampled
phases in independent processes. Each writes 100K measured plus 1K warmup records,
with full JSON/system clocks, 256 queue slots, 512-byte payload and 64KiB file
buffer. Existing cpp_reference/run.py verifies every physical record and exact
file bytes after written flush, shutdown and cleanup. Initialization/preparation
are reported separately; lifecycle metrics include them. regression.py supplies
the existing across-trial summaries and 10% CV/spread noise threshold.

The before binary is the previous batch-accounting candidate, reused only after
matching every source and driver hash. Both modules and applications are
ReleaseFast with frame pointers. before/after-provenance.json identify the exact
source trees and binaries; measurement guards both at every trial. All slow
trials remain in workflow-results.jsonl. No CPU governor, kernel policy or host
processes are altered.

All 100 workflow trials complete and validate 10,100,000 physical records.
Every throughput case is inconclusive. Several candidate medians are lower,
with large slow values retained; the candidate SPSC-memory P4 results are
0.884/1.233/1.224/0.903/0.924M records/s. Complete summaries remain in
comparison.json and the Chinese results table is in docs/encoder-validation.md.

To investigate those slow values, encoder_probe.zig runs 300K scalar-five and
300K nested-twenty JSON records per process, updates numeric input and hashes
every output byte. Ten paired CPU0 PMU processes have identical checksums/bytes.
Whole-process user-space instructions fall 14.27% and cycles 17.90%; per-case
wall time remains inconclusive. This includes encoding/input mutation/hash
consumption only and cannot establish file-workflow throughput.

Ten additional full P4 SPSC-memory file workflows validate 3,010,000 records.
Whole-process user-space instructions fall 2.55%, while median cycles rise 2.62%
and task-clock rises 2.15%, with larger baseline variation. Median complete
throughput changes 1.200M to 1.265M records/s (+5.39%) but remains inconclusive.
full-pmu-results.json retains all software/hardware counters and report phases.
These results support reduced work but do not establish stable speedup or fully
rule out a workload-specific regression. No slow measurements are discarded.

Final comparison and qualification record observed performance and verification
scope. This experiment has a written boundary, not a durable/fsync boundary;
cross-compilation is not non-Linux device-runtime qualification. The older
cross-library ranking retains its archived source identity and requires a new
common run before drawing a current Quill/Foundation ranking.

Final Debug and ReleaseSafe scoped encoder checks pass 23/23 each. Full
ReleaseFast verify-local passes 76/76 build steps and 480/480 Zig tests, including
all existing configuration/decoder/query/package/host/process-crash gates.
Final ReleaseSafe check-platforms/test-file-delivery/test-configurations passes
16/16 build steps: nine target objects and 18/18 real file/configuration tests.
The complete frozen before tree and helpers are in before-source.tar.gz;
implementation.patch and before-node-count-oracle.patch identify exact changes.
