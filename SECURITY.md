# Security policy

## Reporting

Please do not open a public issue for a suspected vulnerability. Use GitHub's
private vulnerability reporting / security advisory flow for this repository so
the report can be triaged before disclosure.

Include the affected commit or version, the platform and Zig version, the
configuration and a minimal reproduction. For durability or recovery issues,
state whether the report involves a process crash, a filesystem fault or
physical power loss; these are separate qualification boundaries.

## Scope

The library owns bounded queues, file mappings, recovery, redaction and output
resource lifetime. Reports about data disclosure through redaction/filter
configuration, journal recovery crossing an ownership boundary, or a sink
writing outside its declared path are in scope. Benchmark-only helpers under
`bench/` and generated evidence are not production APIs, but reports about
evidence accidentally containing secrets are still welcome.
