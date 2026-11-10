# By-reference route iteration check

The owning route loops now use pointers to immutable routes rather than copying
their fixed predicate storage. The old routeMaskIn assembly reserved0x5868 stack
bytes and called memcpy for0x5840 bytes; the new binary reserves0x38 bytes and
has no such memcpy call. Exact executable identity and facts are preserved in
[manifest.json](manifest.json).

[results.jsonl](results.jsonl) contains four matched sleeping-collector admission
checks: one/four producers, shared/attached,10000 calls with1000 excluded warmup.
P1 p50 was78/77ns and P4 p50 was484/157ns(shared/attached). No Runtime allocation,
drop or pending work remained. The original full-P4 end-to-end rows (about587K
records/s shared and617K attached) were not retained in this evidence directory;
manifest.json records the binary identity for that run.

These are single development-host checks, not a stable latency guarantee.
Admission-only and end-to-end output are different metrics; original spinning
collector measurements are preserved separately. The benchmark never reads the
opaque configuration internals or invents numeric pin counts.
