#!/usr/bin/env python3
"""SIGKILL two live producers at seeded times, then inspect every mmap channel.

No worker/producer is parked at a fault hook after READY. ACKs follow public
emit success; written output and independently recovered events must cover
every ACK. Output may end in an unacknowledged partial record, and an output
record may overlap recovery before journal reclaim. This is process-crash
evidence on the same Linux kernel, not system-crash or physical power loss.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import selectors
import signal
import subprocess
import sys
import tempfile
import time

from runtime_crash_oracle import complete_records, committed_sequences, unsigned, verify_coverage


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def run_case(writer, reader, folder, seed, mode, schema, delay, timeout):
    journal = folder / "events.journal"
    output = folder / "events.jsonl"
    command = [str(writer), str(journal), str(output), mode, str(schema).lower(), str(seed)]
    child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ready, ready_at = None, None
    acknowledgements = [[], []]
    transcript = bytearray()
    pending = bytearray()

    def consume(data):
        nonlocal ready, ready_at
        transcript.extend(data)
        assert len(transcript) <= 2 * 1024 * 1024, "unbounded child announcements"
        pending.extend(data)
        while b"\n" in pending:
            line, _, rest = pending.partition(b"\n")
            pending[:] = rest
            if line.startswith(b"READY "):
                assert ready is None, "duplicate READY"
                ready = json.loads(line[6:])
                ready["seed"], ready["session"] = unsigned(ready["seed"]), unsigned(ready["session"])
                assert ready == {"seed": seed, "mode": mode, "schema": schema, "session": ready["session"], "producers": 2, "warm_records": 64}, ready
                assert all(ids == list(range(64)) for ids in acknowledgements), "READY preceded warm ACKs"
                ready_at = time.monotonic()
            else:
                parts = line.split(b" ")
                assert len(parts) == 3 and parts[0] == b"ACK" and all(value.isdigit() for value in parts[1:]), line
                producer, identifier = map(int, parts[1:])
                assert 0 <= producer < 2 and identifier == len(acknowledgements[producer]) and identifier < 20000, line
                acknowledgements[producer].append(identifier)

    killed_at = None
    try:
        deadline = time.monotonic() + timeout
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            while True:
                now = time.monotonic()
                if ready_at is not None and now >= ready_at + delay:
                    assert child.poll() is None, "workload exited before SIGKILL"
                    killed_at = time.monotonic()
                    child.send_signal(signal.SIGKILL)
                    break
                end = ready_at + delay if ready_at is not None else deadline
                assert now < deadline, "workload did not establish READY before deadline"
                events = selector.select(max(0, min(end, deadline) - now))
                if not events:
                    continue
                data = os.read(child.stdout.fileno(), 65536)
                if not data:
                    _, stderr = child.communicate(timeout=timeout)
                    raise AssertionError(f"workload exited before SIGKILL: {stderr.decode(errors='replace')}")
                consume(data)
        tail, stderr = child.communicate(timeout=timeout)
        consume(tail)
        assert child.returncode == -signal.SIGKILL, (child.returncode, stderr)
        assert stderr == b"", stderr.decode(errors="replace")
        # A killed atomic pipe write can leave only an incomplete final ACK;
        # ignore that unconfirmed fragment, but reject any other announcement.
        assert not pending or b"ACK ".startswith(pending) or pending.startswith(b"ACK "), pending
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=timeout)
        for stream in (child.stdin, child.stdout, child.stderr):
            if stream and not stream.closed:
                stream.close()

    assert ready is not None and killed_at is not None
    output_bytes = output.read_bytes()
    assert len(output_bytes) <= 16 * 1024 * 1024, "unbounded output"
    written, partial = complete_records(output_bytes)
    journals = sorted(folder.glob("*.journal"))
    assert len(journals) == (3 if mode == "spsc" else 1), journals
    recovered, recovered_lines, stores = [], [], []
    for path in journals:
        image = path.read_bytes()
        committed, reserved = committed_sequences(image, schema)
        digest = sha256(image)
        first = subprocess.run([str(reader), "--recover", "--json", str(path)], capture_output=True, timeout=timeout)
        assert first.returncode == 0, first.stderr.decode(errors="replace")
        records, remainder = complete_records(first.stdout)
        assert not remainder, "reader emitted partial output"
        assert {unsigned(event["sequence"]) for event in records} == committed, "reader omitted or invented commits"
        assert len(records) == len(committed)
        recovered.extend(records)
        recovered_lines.extend(first.stdout.splitlines(keepends=True))
        second = subprocess.run([str(reader), "--recover", "--json", str(path)], capture_output=True, timeout=timeout)
        assert second.returncode == 0 and second.stdout == first.stdout, "repeat inspection changed result"
        assert sha256(path.read_bytes()) == digest, "inspection changed journal"
        stores.append({"file": path.name, "sha256": digest, "bytes": len(image), "committed": len(committed),
                       "reserved": reserved, "recovery_sha256": sha256(first.stdout)})
    assert not partial or any(line.startswith(partial) for line in recovered_lines), "partial file tail has no complete journal record"
    assert output.read_bytes() == output_bytes, "inspection changed output"
    counts = verify_coverage(written, recovered, acknowledgements, ready)
    case = {"seed": seed, "mode": mode, "schema": schema, "ready": ready, "requested_delay_ms": delay * 1000,
            "observed_delay_ms": (killed_at - ready_at) * 1000, "acknowledgements_per_producer": list(map(len, acknowledgements)),
            "counts": counts, "partial_output_bytes": len(partial), "output_sha256": sha256(output_bytes),
            "announcements_sha256": sha256(transcript), "journals": stores}
    print(f"random SIGKILL seed={seed} {mode} schema={schema}: ACK={counts['acknowledged']} written={counts['written']} "
          f"recovered={counts['recovered']} overlap={counts['overlap']} partial={len(partial)}", flush=True)
    return case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--writer", type=Path, required=True)
    parser.add_argument("--reader", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=20261031)
    parser.add_argument("--cases", type=int, default=12)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if sys.platform != "linux":
        print("SKIP: random-time mmap SIGKILL campaign requires Linux")
        return
    if not 4 <= args.cases <= 32 or args.cases % 4 or not 0 <= args.seed <= 2**64 - args.cases or not 0 < args.timeout <= 30:
        parser.error("require 4..32 cases divisible by 4, a bounded u64 seed, and timeout in (0,30]")
    writer, reader = args.writer.resolve(strict=True), args.reader.resolve(strict=True)
    cases = []
    with tempfile.TemporaryDirectory(prefix="kron-random-sigkill-") as temporary:
        for index in range(args.cases):
            folder = Path(temporary) / str(index)
            folder.mkdir()
            seed = args.seed + index
            cases.append(run_case(writer, reader, folder, seed, "shared" if index % 4 < 2 else "spsc",
                                  bool(index % 2), random.Random(seed).uniform(0.008, 0.075), args.timeout))
    root = Path(__file__).resolve().parents[1]
    sources = ("tests/runtime_crash_writer.zig", "tests/runtime_crash_campaign.py", "tests/runtime_crash_oracle.py",
               "src/core/runtime.zig", "src/journal/journal.zig", "src/archive/reader.zig")
    report = {"status": "passed", "host": {"system": platform.system(), "machine": platform.machine(), "release": platform.release()},
              "writer_sha256": sha256(writer.read_bytes()), "reader_sha256": sha256(reader.read_bytes()),
              "source_sha256": {relative: sha256((root / relative).read_bytes()) for relative in sources},
              "scope": "Random-time SIGKILL during two live producers and file delivery; process crash only, no power-loss claim.",
              "cases": cases}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Random-time process-crash campaign passed: {len(cases)} cases, all ACKs covered by complete output or recovery", flush=True)


if __name__ == "__main__":
    main()
