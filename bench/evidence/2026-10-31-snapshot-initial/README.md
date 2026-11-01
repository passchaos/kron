# Initial snapshot pilot and profile

The 32 rows in [results.jsonl](results.jsonl) cover shared/attached admission and
full JSON output, producer counts, repetitions and explicitly labeled cold
configuration replacement. Counters verified all calls, zero drops and zero
final pending. Steady-state rows rejected Runtime allocations after preparation.

This pilot used a spinning collector and discovered that the attached path was
slower than expected. The [profile report](profile-report.txt) contains a limited
57-sample hybrid-CPU profile with memcpyFast in the routeMaskIn call chain.
Investigation then found an approximately22KiB Route value copy, which was
removed in a separate source change.

Commands, binary identity and scope are in [manifest.json](manifest.json).
This is retained historical evidence, not a current performance claim. The
subsequent [by-reference check](../2026-10-31-snapshot-by-reference/README.md)
has a different explicit idle policy and therefore must not be interpreted as
a controlled before/after timing ratio.
