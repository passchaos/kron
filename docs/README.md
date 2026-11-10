# Documentation navigation

Start with the [usage guide](usage.md) to integrate the library, use
[current acceptance status](implementation-status.md) to judge capabilities and
qualification, and use [development and verification](development.md) when
changing the repository. The public application entry point is `kron.Logging`;
lower-level APIs and design notes are covered in the topic documents.

## Usage and capabilities

| Topic | Document |
| --- | --- |
| Initialization, loggers, fields, threads, outputs, errors | [Usage guide](usage.md) |
| Zig dependency, build, source distribution, single-threaded consumers | [Package integration](package.md) |
| Choosing project-default logging | [Default integration advice](default-logging.md) |
| Borrowed/owned values and field capture | [Capture](capture.md) |
| Arrays/groups and explicit object adapters | [Structured values](structured-values.md) |
| Dynamic filters, source transactions, old configuration resources | [Configuration](configuration.md) |
| Conditions and bounded regular expressions | [Predicates](predicates.md) |
| Global sampling, phases, and bypass | [Sampling](sampling.md) |
| UTC, fixed offsets, system local time, RFC3339, dates, durations | [Time](time.md) |
| Choosing Memory or Mmap | [Asynchronous storage](async-storage.md) |
| Mode/storage/format/recovery/durable combinations | [Capability matrix](capability-matrix.md) |
| flush, durable, deadline, shutdown | [Lifecycle](lifecycle.md) |
| File short writes, rotation, synchronization, error latching | [File reliability](file-reliability.md) |
| Four encodings and protocol versions | [Encoding](encoding.md) |
| Standard zlib compressed archives | [Compressed archive](compressed-archive.md) |
| Pre-registered metadata/schema | [Schema](schema.md) |
| Platform implementations, compilation, device qualification | [Platform support](platforms.md) |

## Architecture and development

| Topic | Document |
| --- | --- |
| Unified owner and tracing design mapping | [API architecture](api-design.md) |
| Directory responsibilities, dependencies, test placement, extension boundaries | [Code structure](code-structure.md) |
| Common gates, targeted verification, evidence maintenance | [Development and verification](development.md) |
| Overall product goals, protocols, acceptance requirements | [Overall design](design.md) |
| Journal slots, CRC, recovery, ownership protocol | [Journal protocol](journal-protocol.md) |
| Existing capabilities, recent gates, remaining priorities | [Current acceptance status](implementation-status.md) |
| Local project research and reuse boundaries | [Local reuse](local-reuse.md) |
| Examples, integration/fault tests, benchmarks, tools | [examples](../examples/README.md), [tests](../tests/README.md), [bench](../bench/README.md), [tools](../tools/README.md) |
| Contribution process, security reporting, license | [CONTRIBUTING](../CONTRIBUTING.md), [SECURITY](../SECURITY.md), [LICENSE](../LICENSE) |
| Versions and recent changes | [Changelog](../CHANGELOG.md) |

## Performance mechanisms and measurement

Each document preserves the source and workload identity used at measurement
time. Local before/after results do not establish a current cross-library
ranking; inconclusive, failed, and negative results remain part of the record.

| Scope | Document |
| --- | --- |
| Timing boundaries, inputs, reproduction | [Benchmark methodology](benchmark-methodology.md) |
| Evidence retention, external storage, new-experiment workflow | [Evidence retention policy](benchmark-evidence-policy.md) |
| Complete business computation and no-logger baseline | [Application impact](application-benchmark.md) |
| Regression statistics and noise | [Performance regression](performance-regression.md) |
| Mechanism research and optimization priorities | [Industry reference](industry-performance-lessons.md), [Hotspots](performance-hotspots.md) |
| Consumer fairness and queue notification | [Scheduling](consumer-scheduling.md) |
| Configuration reuse, acknowledgements, batching | [Configuration reuse](batch-configuration.md), [Accounting](batch-accounting.md), [Batch coalescing](coalesced-delivery.md) |
| Route masks and filtering work | [Route filtering](route-filter-performance.md), [Regular expressions](regex-performance.md) |
| Mmap publication and clock selection | [Cold publication](mmap-publication.md), [TSC](tsc-clock.md) |
| Encoder validation, numbers, escaping | [Validation reuse](encoder-validation.md), [Decimal](decimal-output.md), [ASCII](ascii-output.md) |

## History and evidence

[history/](history/README.md) preserves older design drafts, previous README
performance narratives, and the detailed acceptance chronology. Benchmark
evidence and frozen reference sources are no longer tracked in the repository;
the remaining history documents summarize their conclusions. Historical
snapshots do not describe the current public API.
