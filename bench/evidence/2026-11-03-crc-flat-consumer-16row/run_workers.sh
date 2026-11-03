#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/passchaos/project-z/kron
OUT=$ROOT/bench/evidence/2026-11-03-crc-flat-consumer-16row
SRC=$ROOT/.zig-cache/crc-flat-consumer-16row/candidate/src/root.zig
cd "$ROOT"

FORMAT_FILTERS=(--test-filter 'consumer CRC roles:' --test-filter 'slot CRC')
JOURNAL_FILTERS=(--test-filter 'checked consumer rejects checksum valid generation corruption without releasing a captured record' --test-filter 'recoveryRecordAt retains corrupt records and returns the existing checksum error' --test-filter 'v2 CRC covers schema ref and recovery refuses unknown references without reclaim' --test-filter 'batch borrows records until ordered acknowledgement and stops at gaps' --test-filter 'parallel producers wrap without duplicates or payload damage' --test-filter 'mmap reopen replays committed payload and session without msync' --test-filter 'SPSC reopens committed data across reservation gap using same file protocol' --test-filter 'SPSC producer and consumer concurrently wrap cached cursors' --test-filter 'schema SPSC reserve stays exclusive and warm reserve commit has no allocations')
PROGRESS_FILTERS=(--test-filter 'memory journal progress: all peek paths publish leading tombstones and free producer space' --test-filter 'mmap journal progress: all peek paths publish leading tombstones and free producer space' --test-filter 'memory journal progress: late CRC and release failures retain the failed record until repair' --test-filter 'mmap journal progress: late CRC and release failures retain the failed record until repair')
READER_FILTERS=(--test-filter 'reader returned event is independent of journal slot reuse' --test-filter 'journal damage is reported without reclaiming or repairing evidence' --test-filter 'journal reader bounds memory and validates codec payloads' --test-filter 'v2 schema reader retains missing corrupt unknown and mismatched references for retry' --test-filter 'v2 schema extension corruption and journal version changes are diagnosed')
COMBINED=("${FORMAT_FILTERS[@]}" "${JOURNAL_FILTERS[@]}")

zig test "$SRC" -O Debug -mcpu=native "${FORMAT_FILTERS[@]}" > "$OUT/worker-format-native-debug.log" 2>&1
zig test "$SRC" -O Debug -mcpu=native "${JOURNAL_FILTERS[@]}" > "$OUT/worker-journal-native-debug.log" 2>&1
zig test --dep kron -Mroot=tests/journal_progress.zig -O Debug -mcpu=native -Mkron="$SRC" -O Debug -mcpu=native "${PROGRESS_FILTERS[@]}" > "$OUT/worker-progress-native-debug.log" 2>&1
zig test --dep kron --dep kroncat -Mroot=tests/tool_query.zig -O Debug -mcpu=native -Mkroncat=tools/kroncat.zig -O Debug -mcpu=native -Mkron="$SRC" -O Debug -mcpu=native "${READER_FILTERS[@]}" > "$OUT/worker-reader-native-debug.log" 2>&1

for OPT in ReleaseSafe ReleaseFast; do
  zig test "$SRC" -O "$OPT" -mcpu=native "${COMBINED[@]}" > "$OUT/worker-core-native-$( [ "$OPT" = ReleaseSafe ] && echo safe || echo fast ).log" 2>&1
  zig test --dep kron -Mroot=tests/journal_progress.zig -O "$OPT" -mcpu=native -Mkron="$SRC" -O "$OPT" -mcpu=native "${PROGRESS_FILTERS[@]}" > "$OUT/worker-progress-native-$( [ "$OPT" = ReleaseSafe ] && echo safe || echo fast ).log" 2>&1
  zig test --dep kron --dep kroncat -Mroot=tests/tool_query.zig -O "$OPT" -mcpu=native -Mkroncat=tools/kroncat.zig -O "$OPT" -mcpu=native -Mkron="$SRC" -O "$OPT" -mcpu=native "${READER_FILTERS[@]}" > "$OUT/worker-reader-native-$( [ "$OPT" = ReleaseSafe ] && echo safe || echo fast ).log" 2>&1
done

zig test "$SRC" -O ReleaseSafe -target x86_64-linux-gnu -mcpu=baseline "${COMBINED[@]}" > "$OUT/worker-core-generic-safe.log" 2>&1
zig test --dep kron -Mroot=tests/journal_progress.zig -O ReleaseSafe -target x86_64-linux-gnu -mcpu=baseline -Mkron="$SRC" -O ReleaseSafe -target x86_64-linux-gnu -mcpu=baseline "${PROGRESS_FILTERS[@]}" > "$OUT/worker-progress-generic-safe.log" 2>&1
zig test --dep kron --dep kroncat -Mroot=tests/tool_query.zig -O ReleaseSafe -target x86_64-linux-gnu -mcpu=baseline -Mkroncat=tools/kroncat.zig -O ReleaseSafe -target x86_64-linux-gnu -mcpu=baseline -Mkron="$SRC" -O ReleaseSafe -target x86_64-linux-gnu -mcpu=baseline "${READER_FILTERS[@]}" > "$OUT/worker-reader-generic-safe.log" 2>&1

for f in "$OUT"/worker-*.log; do echo "=== $(basename "$f") ==="; tail -1 "$f"; done
