#!/usr/bin/env python3
"""Seeded process recovery at exact READY boundaries across ring wraps/epochs.

This workload randomizes counts and epoch boundaries; it does not sample
arbitrary crash points. A real writer is SIGKILLed only after its READY proof.
The campaign establishes process-crash behavior on the same OS, not power loss.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import selectors
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zlib


RAW_PASSWORD = b"kron-campaign-real-password-f41a7009"
SOURCE = {"module": "campaign.owner", "file": "recovery_campaign_writer.zig",
          "function": "emitBorrowed", "line": 73, "column": 5}


def scenario(seed, use_schema):
    rng = random.Random(seed)
    written = rng.randrange(64, 128)
    pending = rng.randrange(1, 8)
    first_replace = rng.randrange(2, written // 8) * 8
    old_pending = rng.randrange(1, pending + 1)
    return {"seed": seed, "schema": use_schema, "written": written, "pending": pending,
            "first_replace": first_replace, "old_pending": old_pending,
            "second_replace": written + old_pending}


def await_ready(child, timeout):
    deadline = time.monotonic() + timeout
    data = bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(child.stdout, selectors.EVENT_READ)
        while b"\n" not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise AssertionError("campaign writer did not announce READY before deadline")
            chunk = os.read(child.stdout.fileno(), 4096)
            if not chunk:
                _, error = child.communicate(timeout=max(0.1, remaining))
                raise AssertionError(f"campaign writer exited before READY: {error.decode(errors='replace')}")
            data.extend(chunk)
            assert len(data) <= 4096, "unbounded READY output"
    lines = bytes(data).splitlines()
    assert len(lines) == 1 and lines[0].startswith(b"READY "), data
    return json.loads(lines[0][6:])


def verify_ready(ready, expected):
    for key in ("seed", "schema", "written", "pending", "first_replace", "second_replace", "old_pending"):
        assert ready[key] == expected[key], (key, ready, expected)
    assert ready["accepted"] == expected["written"] + expected["pending"]
    assert ready["queue_pending"] == expected["pending"] + 1
    assert ready["first_pending_sequence"] == expected["written"] + 2
    assert ready["old_pending_retained"] is True
    assert len(ready["route_fingerprints"]) == 3


def generation_for(identifier, scenario):
    if identifier < scenario["first_replace"]:
        return 1
    if identifier < scenario["second_replace"]:
        return 2
    return 3


def parse_records(data):
    assert RAW_PASSWORD not in data, "raw password leaked into output"
    return [json.loads(line) for line in data.splitlines() if line.strip()]


def unsigned(value, name):
    # JSON encoders preserve full-width integers as decimal strings once they
    # exceed the exact JSON-number range. Accept those two precise encodings;
    # floats, booleans, signs, whitespace and out-of-range values remain errors.
    assert ((isinstance(value, int) and not isinstance(value, bool)) or
            (isinstance(value, str) and value.isascii() and value.isdecimal())), (name, value)
    result = int(value)
    assert 0 <= result < 2**64, (name, value)
    return result


def verify_records(records, identifiers, ready):
    assert [unsigned(record["attributes"]["id"], "id") for record in records] == list(identifiers)
    for record, identifier in zip(records, identifiers):
        generation = generation_for(identifier, ready)
        assert record["scope"] == "recovery.campaign"
        assert record["severity"] == "info"
        assert record["message"] == f"campaign {identifier}: payload-{ready['seed']}-{identifier}"
        assert unsigned(record["session"], "session") == unsigned(ready["session"], "ready session")
        assert unsigned(record["sequence"], "sequence") == identifier + (1 if identifier < ready["written"] else 2)
        assert record["channel"] == 0 and unsigned(record["route_mask"], "route_mask") == 1
        assert unsigned(record["config_generation"], "config_generation") == generation
        assert record["source"] == SOURCE
        blob = bytes([identifier & 255, ready["seed"] & 255, (identifier ^ ready["seed"]) & 255, 255])
        actual_attributes = dict(record["attributes"])
        actual_attributes["id"] = unsigned(actual_attributes["id"], "attribute id")
        actual_attributes["seed"] = unsigned(actual_attributes["seed"], "attribute seed")
        actual_attributes["route_generation"] = unsigned(actual_attributes["route_generation"], "attribute route generation")
        actual_attributes["route_fingerprint"] = unsigned(actual_attributes["route_fingerprint"], "attribute fingerprint")
        assert actual_attributes == {
            "id": identifier,
            "seed": ready["seed"],
            "password": "[REDACTED]",
            "payload": f"payload-{ready['seed']}-{identifier}",
            "nested": {"label": f"child-{ready['seed']}-{identifier}",
                       "values": [identifier, identifier % 2 == 0, "hex:" + blob.hex(), None],
                       "secret": "[REDACTED]"},
            "route_generation": generation,
            "route_fingerprint": unsigned(ready["route_fingerprints"][generation - 1], "ready fingerprint"),
        }, record


def verify_journal(data, ready):
    def number(offset, width):
        assert 0 <= offset <= len(data) - width, "truncated journal structure"
        return int.from_bytes(data[offset:offset + width], "little")

    assert data[:8] == b"KRONJNL1"
    assert number(8, 4) == (2 if ready["schema"] else 1)
    assert number(16, 8) == 16 and number(24, 8) == 4096
    assert zlib.crc32(data[:60]) == number(60, 4)
    stride = number(32, 8)
    assert stride == 4160
    data_end = 4096 + 16 * stride
    table = None
    if ready["schema"]:
        assert data[256:264] == b"KRONSCH1"
        assert number(264, 2) == 1 and number(268, 4) == 4
        assert number(276, 4) == 4096
        assert zlib.crc32(data[256:316]) == number(316, 4)
        base, schema_stride, capacity = number(280, 8), number(272, 4), number(268, 4)
        assert base >= data_end and base % 4096 == 0
        assert base + number(288, 8) == len(data)
        table = (base, schema_stride, capacity)
    else:
        assert len(data) == data_end
    pending_sequences = set(range(ready["first_pending_sequence"], ready["first_pending_sequence"] + ready["pending"]))
    observed = set()
    reserved = set()
    for index in range(16):
        slot = 4096 + index * stride
        marker = number(slot, 8)
        if marker == 0:
            continue
        sequence, state = marker >> 2, marker & 3
        assert (sequence - 1) % 16 == index
        if state == 1:
            reserved.add(sequence)
            continue
        assert state == 2 and sequence in pending_sequences, (sequence, state)
        assert number(slot + 8, 8) == sequence
        generation = number(slot + 16, 8)
        assert generation == (sequence - 1) // 16 + 1
        length = number(slot + 24, 4)
        assert 84 <= length <= 4096
        payload = data[slot + 64:slot + 64 + length]
        reference = data[slot + 32:slot + 56]
        crc_data = struct.pack("<QQI", sequence, generation, length)
        if ready["schema"]:
            crc_data += reference
        assert zlib.crc32(crc_data + payload) == number(slot + 28, 4)
        assert payload[:4] == b"KRNE" and int.from_bytes(payload[4:6], "little") == (5 if ready["schema"] else 4)
        identifier = sequence - 2
        expected_generation = generation_for(identifier, ready)
        assert int.from_bytes(payload[76:84], "little") == expected_generation
        assert int.from_bytes(payload[68:76], "little") == ready["route_fingerprints"][expected_generation - 1]
        if ready["schema"]:
            schema_id, schema_version = number(slot + 32, 4), number(slot + 36, 2)
            assert schema_version == 2 and 1 <= schema_id <= table[2]
            entry = table[0] + (schema_id - 1) * table[1]
            assert number(entry, 8) == schema_id * 4 + 2
            assert number(entry + 8, 4) == schema_id and number(entry + 12, 2) == 2
            definition_length = number(entry + 16, 4)
            assert 20 <= definition_length <= 4096
            definition = data[entry + 64:entry + 64 + definition_length]
            assert zlib.crc32(data[entry + 8:entry + 20] + data[entry + 24:entry + 64] + definition) == number(entry + 20, 4)
            assert data[entry + 24:entry + 40] == data[slot + 40:slot + 56]
        else:
            assert reference == bytes(24)
        observed.add(sequence)
    assert observed == pending_sequences
    assert reserved == {ready["written"] + 1}
    assert RAW_PASSWORD not in data, "raw password leaked into retained journal records"


def inspect(reader, journal, timeout):
    result = subprocess.run([str(reader), "--recover", "--json", str(journal)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return parse_records(result.stdout)


def run_case(writer, reader, directory, expected, timeout):
    journal = directory / f"seed-{expected['seed']}-schema-{int(expected['schema'])}.journal"
    output = journal.with_suffix(".jsonl")
    arguments = [str(writer), "--journal", str(journal), "--output", str(output),
                 f"--seed={expected['seed']}", f"--schema={str(expected['schema']).lower()}",
                 f"--written={expected['written']}", f"--pending={expected['pending']}",
                 f"--first-replace={expected['first_replace']}", f"--old-pending={expected['old_pending']}"]
    child = subprocess.Popen(arguments, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        ready = await_ready(child, timeout)
        verify_ready(ready, expected)
        assert child.poll() is None
        child.send_signal(signal.SIGKILL)
        child.wait(timeout=timeout)
        assert child.returncode == -signal.SIGKILL
    finally:
        try:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=timeout)
        finally:
            for stream in (child.stdin, child.stdout, child.stderr):
                if stream and not stream.closed:
                    stream.close()
    assert output.is_file() and journal.is_file()
    output_bytes = output.read_bytes()
    verify_records(parse_records(output_bytes), range(ready["written"]), ready)
    journal_bytes = journal.read_bytes()
    verify_journal(journal_bytes, ready)
    journal_hash = hashlib.sha256(journal_bytes).digest()
    output_hash = hashlib.sha256(output_bytes).digest()
    for _ in range(2):
        records = inspect(reader, journal, timeout)
        verify_records(records, range(ready["written"], ready["accepted"]), ready)
        assert hashlib.sha256(journal.read_bytes()).digest() == journal_hash, "inspection changed journal"
        assert hashlib.sha256(output.read_bytes()).digest() == output_hash, "inspection changed written output"
    print(f"seed={ready['seed']} schema={ready['schema']}: written={ready['written']} pending={ready['pending']} "
          f"wraps={ready['written']//16} epoch thresholds={ready['first_replace']},{ready['second_replace']}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--writer", type=Path, default=Path("zig-out/bin/kron-recovery-campaign-writer"))
    parser.add_argument("--reader", type=Path, default=Path("zig-out/bin/kroncat"))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cases", type=int, default=10)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()
    if sys.platform != "linux":
        print("SKIP: seeded SIGKILL/mmap campaign requires Linux")
        return
    if not 8 <= args.cases <= 12 or not 0 < args.timeout <= 30 or not 0 <= args.seed <= 2**64 - args.cases:
        parser.error("require 8..12 cases, timeout in (0,30], and a bounded u64 seed")
    writer, reader = args.writer.resolve(strict=True), args.reader.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="kron-recovery-campaign-") as temporary:
        directory = Path(temporary)
        for index in range(args.cases):
            run_case(writer, reader, directory, scenario(args.seed + index, bool(index % 2)), args.timeout)
    print("Seeded exact-boundary process recovery campaign passed; no arbitrary-crash-point or power-loss claim", flush=True)


if __name__ == "__main__":
    main()
