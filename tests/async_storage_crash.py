#!/usr/bin/env python3
"""Compare real SIGKILL loss in a memory queue with mmap journal recovery.

READY proves accepted=3, written=0 and pending=4 (a reservation gap plus three
events). Only that child's PID is killed. This establishes process-crash
behavior on the same OS, not a power-loss guarantee. Previously written output
is checked separately and remains intact when memory-only pending events die.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time


RAW_PASSWORD = b"kron-async-real-password-5b73a998"
STORAGES = ("memory", "mmap")


def writer_command(writer, storage, phase, journal, output):
    return [str(writer), f"--storage={storage}", f"--phase={phase}",
            "--journal", str(journal), "--output", str(output)]


def parse_announcement(data, prefix):
    lines = data.splitlines()
    assert len(lines) == 1 and lines[0].startswith(prefix + b" "), data
    return json.loads(lines[0][len(prefix) + 1:])


def await_ready(child, timeout):
    deadline = time.monotonic() + timeout
    data = bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(child.stdout, selectors.EVENT_READ)
        while b"\n" not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise AssertionError("writer did not announce READY before deadline")
            chunk = os.read(child.stdout.fileno(), 4096)
            if not chunk:
                _, error = child.communicate(timeout=max(0.1, remaining))
                raise AssertionError(f"writer exited before READY: {error.decode(errors='replace')}")
            data.extend(chunk)
            assert len(data) <= 4096, "unbounded writer readiness output"
    return parse_announcement(bytes(data), b"READY")


def verify_health(health, storage, phase):
    assert health["storage"] == storage and health["queue_storage"] == storage, health
    assert health["phase"] == phase and health["accepted"] == 3, health
    assert health["written"] == (0 if phase == "crash" else 3), health
    assert health["pending"] == (4 if phase == "crash" else 0), health
    assert health["worker_alive"] is (phase == "crash"), health


def records_from_bytes(data):
    assert RAW_PASSWORD not in data, "raw password leaked into JSON output"
    return [json.loads(line) for line in data.splitlines() if line.strip()]


def verify_records(records, storage, phase, first_sequence):
    assert len(records) == 3, records
    assert [record["sequence"] for record in records] == list(range(first_sequence, first_sequence + 3)), records
    assert len({record["session"] for record in records}) == 1
    for identifier, record in enumerate(records):
        assert record["scope"] == "async.storage"
        assert record["message"] == "asynchronous storage event"
        assert record["severity"] == "info"
        assert record["attributes"] == {
            "id": identifier,
            "storage": storage,
            "phase": phase,
            "password": "[REDACTED]",
        }, record


def read_output(path):
    return path.read_bytes() if path.exists() else b""


def recover(reader, journal, timeout):
    result = subprocess.run([str(reader), "--recover", "--json", str(journal)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=timeout, check=False)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return records_from_bytes(result.stdout)


def run_crash(writer, reader, storage, journal, output, timeout):
    previous_output = read_output(output)
    child = subprocess.Popen(writer_command(writer, storage, "crash", journal, output),
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        health = await_ready(child, timeout)
        verify_health(health, storage, "crash")
        assert child.poll() is None, "READY child exited before its SIGKILL"
        child.send_signal(signal.SIGKILL)
        child.wait(timeout=timeout)
        assert child.returncode == -signal.SIGKILL, child.returncode
    finally:
        try:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=timeout)
        finally:
            for stream in (child.stdin, child.stdout, child.stderr):
                if stream and not stream.closed:
                    stream.close()
    assert read_output(output) == previous_output, "unwritten events changed previously written output"
    if storage == "memory":
        # There is no file to recover. Do not disguise the missing journal with
        # an empty input or a synthetic kroncat invocation.
        assert not journal.exists(), "memory queue created a journal file"
        print(f"SIGKILL memory: accepted=3 written=0; pending events lost, {len(records_from_bytes(previous_output))} prior outputs preserved", flush=True)
        return
    assert journal.is_file(), "mmap queue did not create its journal"
    before = journal.read_bytes()
    assert RAW_PASSWORD not in before, "raw password leaked into captured journal bytes"
    digest = hashlib.sha256(before).digest()
    verify_records(recover(reader, journal, timeout), storage, "crash", health["first_sequence"])
    assert hashlib.sha256(journal.read_bytes()).digest() == digest, "recovery inspection modified journal"
    verify_records(recover(reader, journal, timeout), storage, "crash", health["first_sequence"])
    assert hashlib.sha256(journal.read_bytes()).digest() == digest, "repeat recovery consumed records"
    print(f"SIGKILL mmap: recovered 3 accepted/unwritten events; {len(records_from_bytes(previous_output))} prior outputs preserved", flush=True)


def run_drain(writer, reader, storage, journal, output, timeout):
    result = subprocess.run(writer_command(writer, storage, "drain", journal, output),
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout, check=False)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    health = parse_announcement(result.stdout, b"DRAINED")
    verify_health(health, storage, "drain")
    output_bytes = read_output(output)
    verify_records(records_from_bytes(output_bytes), storage, "drain", health["first_sequence"])
    if storage == "memory":
        assert not journal.exists(), "draining memory queue created a journal file"
    else:
        assert journal.is_file()
        assert RAW_PASSWORD not in journal.read_bytes()
        assert recover(reader, journal, timeout) == [], "successful drain left committed output pending"
    print(f"drain {storage}: accepted=written=3, pending=0, configured password masking verified", flush=True)
    return output_bytes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--writer", type=Path, default=Path("zig-out/bin/kron-async-crash-writer"))
    parser.add_argument("--reader", type=Path, default=Path("zig-out/bin/kroncat"))
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()
    if sys.platform != "linux":
        print("SKIP: SIGKILL/mmap asynchronous storage comparison requires Linux")
        return
    if not 0 < args.timeout <= 30:
        parser.error("--timeout must be positive and at most 30 seconds")
    writer = args.writer.resolve(strict=True)
    reader = args.reader.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="kron-async-storage-") as temporary:
        directory = Path(temporary)
        for storage in STORAGES:
            run_crash(writer, reader, storage, directory / f"{storage}-pending.journal",
                      directory / f"{storage}-pending.jsonl", args.timeout)
            journal = directory / f"{storage}-drained.journal"
            output = directory / f"{storage}-drained.jsonl"
            written = run_drain(writer, reader, storage, journal, output, args.timeout)
            run_crash(writer, reader, storage, journal, output, args.timeout)
            assert read_output(output) == written, "pending-memory crash damaged written output"
    print("Asynchronous storage SIGKILL/drain comparison passed (process crash; no power-loss claim)", flush=True)


if __name__ == "__main__":
    main()
