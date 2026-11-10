# Log inspection tools

`zig build` installs `kroncat` and `kron-bench`. The kroncat implementation is
[kroncat.zig](kroncat.zig); it supports read-only export, query, and follow for
local self-contained archives and journals.

```sh
zig-out/bin/kroncat --json --recover app.journal
zig-out/bin/kroncat --follow --level warn app.kron
zig-out/bin/kroncat --json --where 'request_id == "abc"' app.kron
```

Schema definitions and event payloads are validated independently and do not
depend on the binary of an exited process. Read-only recovery/inspection does not
modify the original journal and does not replace Runtime's stable output-identity
validation and recovery delivery. See [encoding](../docs/encoding.md),
[schema](../docs/schema.md), and
[compressed archives](../docs/compressed-archive.md) for encoding, bad tails,
historical versions, and compression.

## Repository checks

`python3 tools/check_repo_hygiene.py` checks that tracked files do not match
`.gitignore`, do not include caches/generated artifacts, and are not oversized
(single-file limit 8 MiB); `zig build hygiene` is the build entry for the same
check.

`python3 tools/check_links.py` checks relative links in tracked Markdown, skipping
HTTP/mailto/anchor links and fenced code blocks; `zig build links` is the build
entry for the same check.

`zig build test-query -Doptimize=ReleaseSafe -j1` verifies Reader/query/follow.
Real child-process force-kill and read-only export are covered by `test-crash`,
`test-async-crash`, and `test-runtime-crash`; see [tests/](../tests/README.md).
