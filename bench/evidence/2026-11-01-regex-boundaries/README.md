# Byte regex boundaries and parser mutation

Baseline: local Git commit `38c413c`, recorded in `baseline-commit.txt`.
`before.log` runs the expanded independent corpus against the original
production parser and fails on the first 20 mismatches. `before-probe.log`
also records unsupported `\D`/`\A` being accepted as literals, a leading
`]` class being rejected, missing `\f`/`\xFF` escapes, and a quantified
anchor being accepted.

The owning regex compiler/search now lives in `src/pipeline/regex.zig`;
Predicate retains field/configuration parsing and the existing public
Pattern/Regex aliases. Thompson state representation, release semantics,
128-state shared budget, 32-level nesting and 8192-byte input limit remain.
Unsupported categories/assertions/backreferences/unknown alphabetic escapes
are rejected explicitly. The parser supports two-digit hex and control
escapes, first-element `]` in classes, and rejects malformed ranges/hex and
directly quantified anchors. Matching remains byte oriented with strict
whole-input anchors; dot excludes LF. Invalid runtime replacement leaves
the configuration generation and journal reservation target unchanged.

Each of eight seeded differential campaigns runs **20,234 outcomes**:
20,188 independently computed byte matches, 45 exact compile errors and
one input-limit error. Total: **161,872 outcomes**, including **161,504
match comparisons**. Each seed also passes eight negative driver checks.
Inputs cover all 256 bytes, NUL/high bytes, CR/LF, escaped punctuation,
literal brackets/hyphens, classes, groups, nullable loops and strict anchors.
Original ASCII cases are retained. CPython bytes `re.search` is the matching
oracle; only unescaped class-external `$` is translated to absolute-end
`\Z` to implement the existing kron contract for a final LF. Random byte
inputs are at most six bytes, keeping the backtracking oracle bounded.

`seed-*/corpus.json.gz` retains the exact JSON corpus, gzip mtime zero.
Each `summary.json` hashes the uncompressed JSON and records outcomes and
driver rejection checks. `campaign.log` is the actual campaign output and
`campaign-driver.txt` identifies its Debug executable.

Five standalone module tests cover exact 128-state/32-group limits, all
65,536 literal byte/input pairs and 65,536 class byte/input pairs, full
byte ranges, escapes, anchors and explicit unsupported syntax. Public fuzz
tests execute 8192 seeded regex mutation/arbitrary-input cases and 4096
predicate parser mutations. Successful patterns are copied and compared
after overwriting their configuration storage; multiple predicates exercise
the shared state budget. Diagnostics must stay inside the original spec.

`module-debug.log`, `module-safe.log`, `module-fast.log` retain module gates.
`debug.log`, `safe.log`, `fast.log` retain differential/fuzz/public-runtime
gates. The earlier `safe-first.log` and `safe-intermediate.log` are failed
development checks: the fuzz initially treated a legitimate shared-state
budget rejection as failure, then a `try`/`catch` compile error was fixed.
They are retained as failures and do not count as qualifications.

The completed ReleaseFast `verify-local` run in `verify-fast.log` passes
83/83 build steps and 515/515 tests, including actual random-time SIGKILL,
package consumers, single-threaded execution and independent oracles.

Reproduce:

```sh
zig test src/pipeline/regex.zig -O ReleaseSafe
zig build test-regex-differential test-regex-fuzz test-predicates \
  -Doptimize=ReleaseSafe -j1 --summary all
zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all
```

These are reproducible bounded campaigns, not a continuous sanitizer fuzz
qualification, a regular-expression throughput benchmark or a cross-library
performance ranking. Platform device runs and larger system/power-loss
campaigns remain in the full implementation acceptance list.
