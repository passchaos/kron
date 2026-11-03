#!/usr/bin/env python3
"""SIGKILL a real kron Journal owner, then inspect it in a fresh kroncat process.

Every child and readiness handshake has a deadline. The writer deliberately
does not sync commits; this exercises process-crash recovery on the same OS.
"""

import argparse
import hashlib
import json
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time


RAW_SECRET = b"kron-crash-raw-secret-9e891aa7"
PHASES = {
    "reserved": [],
    "committed": [1, 2, 3],
    "gap": [1, 3, 4],
    "schema-committed": [1, 2, 3],
    "schema-gap": [2, 3, 4],
    "hot-routes": [2, 3, 4],
}


def await_ready(child, timeout):
    deadline = time.monotonic() + timeout
    with selectors.DefaultSelector() as selector:
        selector.register(child.stdout, selectors.EVENT_READ)
        data = bytearray()
        while b"\n" not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise AssertionError("crash writer did not announce ready before deadline")
            chunk = child.stdout.read1(4096)
            if not chunk:
                _, stderr_bytes = child.communicate(timeout=timeout)
                stderr = stderr_bytes.decode(errors="replace")
                raise AssertionError(f"crash writer exited before ready: {stderr}")
            data.extend(chunk)
            if len(data) > 4096:
                raise AssertionError("unexpected crash writer readiness output")
        if bytes(data) != b"ready\n":
            raise AssertionError(f"unexpected readiness output: {data!r}")


def recover(reader, journal, timeout):
    completed = subprocess.run(
        [str(reader), "--recover", "--json", str(journal)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    assert completed.returncode == 0, (
        f"kroncat recovery failed ({completed.returncode}): "
        f"{completed.stderr.decode(errors='replace')}"
    )
    assert RAW_SECRET not in completed.stdout, "raw secret reached recovered output"
    return [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]


def verify_records(records, expected_sequences, phase):
    assert [int(record["sequence"]) for record in records] == expected_sequences
    for identifier, record in enumerate(records):
        assert record["scope"] == "crash.snapshot"
        assert record["message"] == f"event {identifier}: borrowed original"
        assert int(record["timestamp_ns"]) == 123456789
        if phase != "hot-routes":
            assert int(record["session"]) == 4242
        else:
            assert int(record["session"]) == int(records[0]["session"])
        assert record["channel"] == (0 if phase == "hot-routes" else 7)
        assert int(record["route_mask"]) == 1
        assert int(record["config_generation"]) == ((1 if identifier == 0 else 2) if phase == "hot-routes" else 3)
        assert record["severity"] == "info"
        assert record["trace_id"] == "aa" * 16
        assert record["span_id"] == "bb" * 8
        assert record["trace_flags"] == 1
        assert record["attributes"] == {
            "id": identifier,
            "snapshot": "borrowed original",
            "secret": "[REDACTED]",
            "bytes": "hex:00ff",
        }
        assert record["source"] == {
            "module": "crash.owner",
            "file": "crash_writer.zig",
            "function": "encodeEvent",
            "line": 41,
            "column": 9,
        }
    assert all(record["attributes"]["id"] != 999 for record in records)


def verify_journal_layout(data, phase, expected_sequences):
    def number(offset, size):
        assert offset + size <= len(data), "truncated journal layout"
        return int.from_bytes(data[offset : offset + size], "little")

    assert data.startswith(b"KRONJNL1"), "unexpected journal header"
    schema = phase.startswith("schema-")
    # Protocol migration adds route_generation: self-contained v4 and schema
    # references v5 use 84 bytes. Legacy v1/v3 and references v2 remain readable.
    expected_payload_version = 5 if schema else 4
    assert number(8, 4) == (3 if schema else 1), "wrong journal protocol version"
    capacity = number(16, 8)
    maximum = number(24, 8)
    stride = number(32, 8)
    header_size = number(56, 4)
    assert capacity == 8 and maximum == 2048
    assert stride >= 64 + maximum and stride % 64 == 0
    data_end = header_size + capacity * stride
    if schema:
        assert data[256:264] == b"KRONSCH1", "missing schema extension"
        assert number(264, 2) == 1, "wrong schema definition version"
        assert number(268, 4) == 4, "wrong schema capacity"
        assert number(276, 4) == 4096, "wrong schema definition capacity"
        schema_offset = number(280, 8)
        schema_bytes = number(288, 8)
        assert schema_offset >= data_end
        assert schema_offset + schema_bytes == len(data), "wrong v2 file layout"
    else:
        assert data_end == len(data), "wrong v1 file layout"
    route_fingerprints = []
    for identifier, sequence in enumerate(expected_sequences):
        slot = header_size + (sequence - 1) % capacity * stride
        assert number(slot, 8) == sequence * 4 + 2, "expected committed slot"
        assert number(slot + 8, 8) == sequence
        length = number(slot + 24, 4)
        assert 84 <= length <= maximum
        assert data[slot + 64 : slot + 68] == b"KRNE"
        actual_payload_version = number(slot + 68, 2)
        assert actual_payload_version == expected_payload_version, (
            f"{phase} sequence {sequence}: expected payload version "
            f"{expected_payload_version}, got {actual_payload_version}"
        )
        route_generation = number(slot + 64 + 76, 8)
        if phase == "hot-routes":
            assert route_generation == (1 if identifier == 0 else 2), "wrong hot route generation"
            route_fingerprints.append(number(slot + 64 + 68, 8))
        else:
            assert route_generation == 0, "direct codec event has an unexpected route generation"
        if schema:
            assert number(slot + 32, 4) != 0, "event has no schema reference"
            assert number(slot + 36, 2) == 1
            assert any(data[slot + 40 : slot + 56]), "event has no schema hash"
    if phase == "hot-routes":
        assert route_fingerprints[0] != route_fingerprints[1], "old and new targets must have distinct bindings"
        assert route_fingerprints[1] == route_fingerprints[2], "new route binding changed between records"


def run_phase(writer, reader, directory, phase, expected_sequences, timeout):
    journal = directory / f"{phase}.journal"
    child = subprocess.Popen(
        [str(writer), "--journal", str(journal), "--phase", phase],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        await_ready(child, timeout)
        assert child.poll() is None, "writer must still own the journal at SIGKILL"
        child.send_signal(signal.SIGKILL)
        child.wait(timeout=timeout)
        assert child.returncode == -signal.SIGKILL, child.returncode
    finally:
        try:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=timeout)
        finally:
            child.stdin.close()
            child.stdout.close()
            child.stderr.close()
    assert journal.is_file(), "writer did not create a real journal"
    before = journal.read_bytes()
    verify_journal_layout(before, phase, expected_sequences)
    assert RAW_SECRET not in before, "raw secret reached persisted codec payload"
    before_hash = hashlib.sha256(before).digest()
    records = recover(reader, journal, timeout)
    verify_records(records, expected_sequences, phase)
    assert hashlib.sha256(journal.read_bytes()).digest() == before_hash, "inspection changed the journal"
    # The recovery CLI is an inspector. A second new process must see the same
    # committed records; inspection must not acknowledge/consume the journal.
    verify_records(recover(reader, journal, timeout), expected_sequences, phase)
    assert hashlib.sha256(journal.read_bytes()).digest() == before_hash, "repeat inspection changed the journal"
    payload_version = 5 if phase.startswith("schema-") else 4
    print(f"SIGKILL {phase}: recovered {len(records)} committed events (expected payload v{payload_version})", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--writer", type=Path, default=Path("zig-out/bin/kron-crash-writer"))
    parser.add_argument("--reader", type=Path, default=Path("zig-out/bin/kroncat"))
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()
    if sys.platform != "linux":
        print("SKIP: mmap journal SIGKILL recovery requires Linux")
        return
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    writer = args.writer.resolve(strict=True)
    reader = args.reader.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="kron-crash-recovery-") as temporary:
        directory = Path(temporary)
        for phase, expected_sequences in PHASES.items():
            run_phase(writer, reader, directory, phase, expected_sequences, args.timeout)


if __name__ == "__main__":
    main()
