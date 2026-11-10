# Field conditions and bounded regex filtering

Level/scope is still decided before field construction; `predicate` is decided
after capture and recursive redaction but before journal reserve/acceptance. An
expression can be set on Runtime, configuration Policy, or an individual route:

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .predicate = "tenant == \"prod\"",
    .routes = &.{.{
        .name = "errors", .sink = file.sink(),
        .predicate = "status >= 500 && path =~ \"^/api/(users|orders)$\"",
    }},
});
```

Supported operations are AND, exists, equality/inequality/ordering, prefix,
contains, and regex. Syntax includes `exists(key)`, `== != < <= > >=`, `^=`
(prefix), `*=` (contains), and `=~` (regex). Strings use quotes, and numeric
comparison preserves i128/u128 precision. NaN comparisons return false, missing
fields do not match, and containers do not participate in scalar comparison.

Metadata targets use `@scope`, `@level`, `@message`, and `@rendered_message`.
`message` means the template for deferred events; `rendered_message` accepts only
explicitly pre-encoded or ordinary string events and never performs expensive
formatting implicitly in the producer. Dotted field names match literally; the
lower-level `Predicate.init` Rule.path can explicitly traverse groups to avoid
dotted-key ambiguity.

Regexes compile to a fixed-budget Thompson NFA supporting `.`, `*`, `+`, `?`,
`[]`, `^`, `$`, `|`, and `()`; there is no backtracking, and unsupported
expressions such as backreferences fail explicitly. Each Predicate has at most 64
rules, 8 KiB of configuration, and 128 regex states; regex input is at most 8 KiB,
and compile nesting is at most 32 levels. Matching does not allocate, and
oversized regex input returns `InputTooLong` without consuming a journal slot.

Regex matching is byte-oriented, so a UTF-8 character may span multiple bytes;
`.` matches one byte other than LF (`0x0a`). `^` matches only the beginning of the
whole input, `$` only the end of the whole input, and a trailing newline is part
of the input. The default search may start at any byte position, and empty
groups/branches and nullable repetition still use the same bounded NFA.

Escapes `\n \r \t \f \v \a` and exactly two-hex-digit `\xNN` are supported,
including NUL and `0xff`; escaped punctuation matches literally. The first `]` in
a character class (including its position in `[^]...]`) is a literal, a leading or
trailing `-` or `\-` is literal, and other `a-z` forms an inclusive byte range.
Reversed ranges and unclosed character classes return `InvalidRegex`. Zig
strings, predicate strings, and JSON configuration each still require their own
normal escaping layer.

`\d/\D/\w/\W/\s/\S`, `\b/\B/\A/\Z`, numeric escapes/backreferences, Unicode named
escapes, `(?...)` extension groups, and unknown letter escapes explicitly return
`UnsupportedRegex` and are never treated as literal letters. Quantifiers directly
on `^/$`, repeated quantifiers, and incomplete/invalid `\xNN` return
`InvalidRegex`; nullable assertions inside parentheses may still repeat. Invalid
configuration transactions preserve the original generation and journal
reservation watermark.

Expressions are parsed and deep-copied before configuration publication; an
invalid transaction keeps the original configuration. Accepted events store the
route mask and configuration generation at acceptance, and the background never
drops them again using the latest predicate. Per-route filtering may retain only
some targets, while a global predicate failure returns filtered directly.

External `test-predicates` verifies pre-acceptance filtering, regex budgets,
redaction ordering, old/new configuration delivery, and that the SPSC cache
generation remains valid when a Runtime callback is nested. Runnable example:
`zig build run-predicates`.

`test-regex-differential` uses independent Python bytes `re.search` to generate a
reproducible corpus, passing arbitrary bytes as hex and covering the original
short-ASCII corpus, all 256 byte values, newline/CR/control characters, escapes,
character classes, empty branches, and nullable quantifiers. Python's `$` also
matches before a trailing LF, so the oracle rewrites only unescaped `$` outside
character classes to Python's absolute-end `\Z`; all other parsing and matching is
done by Python. Random oracle inputs are at most 6 bytes and the original ASCII
corpus at most 12 bytes to avoid oracle backtracking load; 8 KiB long inputs and
over-limit behavior are verified in separate resource tests. The driver also
checks explicit compile errors and input over-limit, and runs negative self-checks
(wrong expect/invalid hex/no expect/empty corpus) each round to prove it can reject
false passes.

`test-regex-fuzz` adds 8,192 regex mutations/arbitrary-byte compilation and 4,096
predicate-parser mutations; successful compilation covers Pattern copies, input
configuration overrides, and shared state budgets across multiple regexes;
diagnostic offsets must stay within the original spec. It and the differential
test are part of `verify-local` and form a bounded reproducible campaign, not a
replacement for sustained sanitizer fuzz or performance qualification of every
business regex. The implementation is split into compilation/matching in
`pipeline/regex.zig` and field rules/configuration syntax in
`pipeline/predicate.zig`.

The matching hot path uses two 64-bit active-state bitmaps. At compile time,
epsilon and assertion loops are expanded for four BOL/EOL conditions, and the
input's first position uses a separate initial state; each subsequent position
checks only active states that consume the actual byte, preserving input and
state budgets. Fixed compile storage and configuration-initialization cost
increase; see [regex matching work](regex-performance.md) for resources, eight
business workloads, complete synchronous JSON comparison, and the
`test-regex-equivalence --fuzz=1M` entry.
