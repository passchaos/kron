# Decoder and persistent format matrix

The independent `test-decoder-matrix` gate also runs inside `test-fuzz`. It covers
eight fixtures and separates event payload versions, schema definition versions
and disk container versions.

| Fixture | Prefix truncations | Mutations | Valid mutated reencodes |
| --- | ---: | ---: | ---: |
| inline v1, scalar | 353 | 2,048 | 1,120 |
| inline v3, scalar | 361 | 2,048 | 1,157 |
| inline v4, scalar | 369 | 2,048 | 1,152 |
| inline v4, nested | 340 | 2,048 | 1,112 |
| reference v2, scalar definition v1 | 205 | 2,048 | 1,272 |
| reference v5, scalar definition v1 | 213 | 2,048 | 1,250 |
| reference v5, nested definition v2 | 265 | 2,048 | 1,139 |
| reference v5, nested template/arguments | 276 | 2,048 | 1,117 |

Successful decodes must keep every borrowed key, string, byte slice and source
sentinel inside the input or schema. Aggregate descriptors must fit caller
scratch. Each fixture also checks scratch capacities 0..15 with untouched
canaries and unused storage, including failed decode paths. Full validation,
canonical reencoding and independent JSON parsing follow successful decode.
Legacy missing header fields must default to zero. Invalid deferred templates
can return the documented writer error; they cannot bypass codec bounds.

The separate schema test changes each of 147 body bytes, then refreshes the
domain-prefixed SHA256 identity and entry CRC. It observes 54 structural
rejections and 93 valid definitions whose canonical hashes are checked again.
The disk test stores eight real files, with plain archive frames or schema
journals, and runs two independent public Reader exports for each. Event bytes
match and original files stay unchanged.

```sh
zig build test-decoder-matrix -Doptimize=Debug -j1
zig build test-fuzz test-query -Doptimize=ReleaseSafe -j1
zig build test-decoder-matrix -Doptimize=ReleaseFast -j1
```

Debug and ReleaseFast each pass the three matrix tests. ReleaseSafe passes all
seven fuzz tests and 23 query tests, including the existing independent legacy
golden and mixed plain/compressed archive test. All three matrix runs produce
the same coverage counts. `qualification.json` records source, log and generated
test binary hashes.

These are bounded deterministic regression corpora, not persistent or complete
coverage-guided fuzz qualification. Historical payloads in the matrix are built
by explicit header conversion; independent historical golden bytes remain in
the older codec/query tests. Disk fixtures are local temporary files, rather
than samples from old production applications. Production codec behavior was
not changed in this work.
