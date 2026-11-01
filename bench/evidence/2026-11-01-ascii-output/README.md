# Bounded ASCII scanning and direct quoted output

The current full-file P4 SPSC-memory profile independently validates 1,001,000
physical JSON records. Roughly 8K user-core-PMU samples locate CRC at 26.33%
and quoted/consume around 5.8%. Percentages include initialization and all
threads, so they identify work rather than quantify a speedup.

Only escaping.zig changes. Printable ASCII strings and JSON keys bypass the
general quoted-writer/UTF-8-validation path. Bounded little-endian 8-byte loads
locate the first special byte; the original UTF-8/escape byte state machine
handles the suffix. DEL, malformed bytes, record separators, U+2028/U+2029 and
injective $bytes: key spelling retain their original rules. No unvalidated value
entry point, memory allocation, SIMD/CPU-feature requirement, journal format or
checksum-site change is introduced.

Two new tests compare 1,835,008 adjacent-byte/position/alignment combinations
against an independent scalar predicate and 2,048 arbitrary-byte inputs against
the original byte-at-a-time renderer. Short/tail slices and stream fragments
remain correct. Public old/new module comparisons have 12 identical complete
records, 16,486 fixed-writer prefixes and 49,494 generic short-write/failure
prefixes, without another writer callback after an error.

The initial candidate made Unicode-message medians 5.7% slower and increased
combined user instructions. escaping-initial.zig, its binary identity and all
probe-results.json rows are retained. The final scanner checks the first byte
before loading a word, immediately handling UTF-8/control-dense input. Both
implementation.patch and initial-to-final.patch preserve the exact changes.

Final six-case encoder probe trials hash 6M complete outputs with exact bytes
and checksums. Whole-process user instructions fall 10.68%, cycles 8.06%.
Nested digits are locally about 16.6% faster, long ASCII 38%; Unicode's roughly
2% median reduction still has overlapping trial intervals. Per-case slow values
remain. The probe includes scalar updates and output hashing, not file/queue
throughput, and whole-process counters include all six shapes.

| Complete batch file workflow | Before median records/s | After median records/s | Status |
| --- | ---: | ---: | --- |
| shared memory P1 | 1,337,151 | 1,415,928 | Inconclusive |
| shared memory P4 | 1,338,047 | 1,410,953 | Inconclusive |
| SPSC memory P4 | 1,360,909 | 1,330,091 | Inconclusive |
| SPSC mmap P4 | 1,327,848 | 1,400,393 | Inconclusive |
| SPSC mmap P4 prepared | 1,321,728 | 1,442,009 | Inconclusive |

100 paired processes validate every physical output record: 10,100,000 records.
All accepted=written, drop/pending=0, complete system-clock JSON, original queue
and file budgets. Producer+written flush+shutdown+cleanup define throughput;
initialization/preparation remain reported separately in lifecycle metrics.
All throughput trial-bootstrap intervals overlap, and at least one side fails
the 10% CV/spread noise threshold. The SPSC-memory decline and other slow trials
are retained rather than replaced by positive medians.

Ten additional P4 SPSC-memory PMU file workflows validate 3,010,000 records.
User instructions fall 5.65%; cycles/task-clock changes (about −5.4%) remain
inconclusive, as does full throughput (+6.3% median). User counters exclude
kernel I/O work. This extra design is separately recorded and not merged with
the 100K-record workflow medians.

Go encoding/json and serde_json safe-string fragment paths were read as design
references; research-sources.json records exact hashes. No upstream source is
copied and no production dependency is added. before-source.tar.gz preserves
the full pre-change sources, identical workflow driver and independent output/
statistics helpers. Per-row and provenance hashes retain the final identities.

Final qualification records full regression/platform scope. The file boundary
is written, not durable/fsync or power-loss. Existing cross-library data has an
older source snapshot; neither probe nor these local gains establish a new
Foundation/Quill ranking or native non-Linux device qualification.
