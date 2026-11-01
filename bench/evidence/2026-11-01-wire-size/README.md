# Bounded native-width wire-size accumulator probe

Baseline: e5f189e. Before the static-scalar capture change, wire-size total
was changed from u128 to u64. Each added term is capped at u32_max+1:
valid wire sums remain exact, and any single oversized usize still ensures
TooLarge after complete tree validation. At most 256 nodes/keys and five
metadata/source strings keep this bounded native sum below 2^42.

The scalar module tests compare the result with exact u128 sums over 8192
mixed boundary/random sequences, including maxInt(usize); the size-only
codec test rejects logical huge strings without dereferencing them and
retains cyclic/duplicate-tree errors before wire overflow. Existing schema
size/shape/level error priority remains tested by its owning source.

`probe/` uses the unchanged public bench/encoding.zig: 3 shapes x 6 size,
inline encode, binary archive and schema-reference operations x 5 repetitions.
Five alternating paired CPU0 processes agree on all 900 report rows,
sizes and encoded-byte hashes. Whole-probe instructions decrease 2.89%,
cycles increase 2.45% with both sides near the 10% spread budget; every
per-case wall time is inconclusive. This diagnostic probe includes validation,
fixture mutation, output hashing, schema setup and reporting. It cannot
establish asynchronous/file throughput gain.

`wire-size-candidate.zig` and `codec-candidate.zig` preserve this isolated
candidate. Later combined/static-only full-file probes and qualifications
are in ../2026-11-01-static-scalar/. They explicitly distinguish those
inputs and snapshots instead of adding independent percentage gains.
