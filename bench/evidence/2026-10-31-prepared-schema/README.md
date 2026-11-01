# Prepared schema pilot

This evidence compares the same logical inputs and normal JSON output through
self-contained versus prepared-metadata capture. There are 64 rows: two
repetitions, async/SPSC, memory/file, one/four producers, journal v1/v2, and
sampled/batch timing. Every row verified 10,000 accepted and written events,
with zero final pending. Registration and persistence are outside producer
timing and explicitly included in preparation time.

Raw commands, executable identity and validation details are in
[manifest.json](manifest.json); [results.jsonl](results.jsonl) contains all
measurements and [summary.json](summary.json) preserves median/min/max values.
Large output files remain in the manifest's external artifact directory.

Four-producer file batch medians were about 582K → 649K records/s for shared
journals and 604K → 681K for SPSC. This two-repetition development-host pilot
does not establish a stable universal speedup. Single-producer SPSC file ranges
overlap; initialization, preparation, queue policy and full drain remain
separate costs. The comparison does not change output metadata or compare
binary archive throughput against readable JSON.

This evidence is tied to the executable/source identities in the manifest.
Historical C++ and file-backend pilots are preserved separately; later changes
need their own verification rather than inheriting these results.
