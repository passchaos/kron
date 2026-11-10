# Regex matching work and qualification boundaries

Log filtering uses a fixed-budget Thompson NFA with 128 states, 32 compile
nesting levels, and an 8192-byte input limit. Configuration compile time computes
reachable states under four beginning/end assertion conditions, and matching
traverses only active states that consume characters; two 64-bit bitmaps merge
paths without allocating memory. Empty branches, nullable loops, states crossing
64-bit boundaries, arbitrary bytes, and strict end anchors preserve their
original semantics.

`State.closure` stores the two EOL conditions when BOL is false, and
`Regex.initial` stores the two EOL conditions for the input's first position.
State after each consumed character is already expanded with the next position's
end condition; only the first position can use BOL. Compile-time fixed points are
computed within the patched graph of this regex and do not read other regex states
in the same Predicate. Runtime no longer expands jump/split/assertion per byte or
scans the complete state array.

This choice moves work into configuration initialization and increases fixed
memory. On native x86_64, `Pattern` grows from 4,624 to 9,264 bytes and
`Predicate` from 17,952 to 25,632 bytes, including fixed metadata capacity for 64
rules; the 8 KiB configuration-string budget is unchanged. In a 1,000-compile
batch probe, the API path rose from about 0.88 to 2.04 µs/call, and the 127-literal
state path from about 1.15 to 3.22 µs/call. The probe has no first-initialization
quantile qualification.

## Business benchmark

```sh
zig build bench-regex -Doptimize=ReleaseFast -- --iterations=10000 --repetitions=5
python3 bench/regex_compare.py --before /path/to/frozen-before \
  --after /path/to/frozen-after --output /path/to/new-report
```

Eight input classes cover API paths, severity messages, long literal searches,
nullable loops, overlapping alternation, the 128-state limit, dense character
classes, and NUL/high bytes. Each group has four inputs, two expected to match
and two to reject; long inputs use fewer iterations while retaining four inputs.
Pattern, single-field Predicate, and two complete synchronous JSON paths are
reported separately. The synchronous path includes capture, field validation,
predicate, JSON encoding, complete byte hash/copy, and written flush; it checks
accepted/written/filtered, zero allocation after initialization, final JSON
fields, and all before/after output hashes. It does not cover asynchronous queues,
file I/O, durability, or single-call producer quantiles.

The comparison driver fixes CPU, alternates five child-process pairs with five
repetitions per process, and reverses case order; it checks matching line counts,
input volume, match counts, written, output volume, hashes, and measurement
environment. Missing/duplicate lines, wrong counts, output changes, and
measurement-time allocation must fail. All slow samples are retained, and any side
with CV or relative spread above 10% is reported inconclusive.

All final groups in the current comparison are inconclusive. Medians show API
Pattern about 350→76 ns, severity Pattern 486→79 ns, long literal search
48.5→9.5 µs, overlapping alternation 142→54 µs, and 128-state input 370→14 µs;
two complete synchronous JSON batches were about 557→282 ns and 681→283 ns. These
describe only this round's data and are not a stable end-to-end performance
promise or cross-library ranking.

Another five full benchmark child-process user-PMU pairs covered eight
Pattern/Predicate classes, two complete synchronous JSON paths, configuration
compile/initialization, and report output. All input counts, written, and JSON
hashes matched; instructions fell 81.34% by median with both-side relative spread
below 0.00005%; cycles still exceeded the noise threshold. Long-input matching
dominates this probe, so the instruction ratio cannot be generalized to async or
file-log workflows.

## Semantics and fuzz

```sh
zig build test-regex-equivalence test-regex-differential test-regex-fuzz \
  test-predicates test-regex-bench -Doptimize=ReleaseSafe -j1
zig build test-regex-equivalence -Doptimize=ReleaseSafe --fuzz=1M -j1
```

An independent dense fixed-point interpreter checks the production matcher across
8,192 mutations, and also checks nonzero starting offsets for multiple regexes
sharing a Predicate array. It provides only a graph-execution comparison; parsing
and final matching semantics are still checked by an independent Python bytes
`re.search` oracle. Module tests cover every byte, 128 states, 32 nesting levels,
and anchor loops.

`test-regex-equivalence` includes a native Zig coverage-guided fuzz entry:
arbitrary regex compile input, valid complex graphs with arbitrary match input,
arbitrary predicate configuration, and diagnostic offsets. `--fuzz=1M` is a
bounded run; `--fuzz` can run continuously in a dedicated test environment.
ReleaseSafe keeps Zig boundary/integer checks, and the Zig fuzzer owns coverage
instrumentation. This does not represent AddressSanitizer, ThreadSanitizer, or
cross-platform device sanitizer qualification, and a bounded campaign cannot
replace sustained fuzz.
