#!/usr/bin/env python3
"""Bounded executable checks for counters, report parsing and completion timing."""
import argparse
import csv
import io
import json
import pathlib
import subprocess
import tempfile
import statistics
import time
import hashlib
import platform


def verify(rows, events, filtered=False):
    assert [r["phase"] for r in rows] == ["sampled", "batch"]
    for row in rows:
        assert row["status"] == "ok", row
        storage = row.get("queue_storage", "none" if row["mode"] == "sync" else "mmap")
        assert storage in ("none", "memory", "mmap"), row
        assert storage == "none" if row["mode"] == "sync" else storage != "none", row
        assert row.get("process_crash_recovery", storage == "mmap") is (storage == "mmap"), row
        allocated = row.get("queue_allocation_bytes", row["journal_allocation_bytes"])
        mapped = row.get("journal_mapped_bytes", row["journal_allocation_bytes"])
        if storage == "none":
            assert allocated == mapped == 0 and row.get("journal_path") is None, row
        elif storage == "memory":
            assert allocated > 0 and mapped == row["journal_allocation_bytes"] == 0, row
            assert row.get("journal_path") is None, row
        else:
            assert allocated == mapped == row["journal_allocation_bytes"] and allocated > 0, row
            assert row.get("journal_path") is not None, row
        assert row["attempted"] == events, row
        outcomes = sum(row[k] for k in (
            "accepted", "filtered", "sampled", "dropped_full", "dropped_oversize", "rejected_closing", "emit_errors"))
        assert outcomes == events, row
        assert row["accepted"] == row["runtime_accepted"] == row["runtime_written"] == row["sink_written_records"], row
        assert row["final_pending"] == 0 and row["runtime_write_errors"] == 0, row
        assert row["total_ns"] >= row["producer_wall_ns"] + row["flush_written_ns"], row
        if filtered:
            assert row["filtered"] == events and row["sink_written_records"] == 0, row
        if row["phase"] == "sampled":
            assert 0 < row["latency_samples"] <= min(row["samples_max"], events), row
            assert row["producer_p50_ns"] <= row["producer_p99_ns"] <= row["producer_p999_ns"] <= row["producer_max_ns"], row
        else:
            assert row["latency_samples"] == 0 and row["producer_p50_ns"] is None, row
        if row["sink"] == "file":
            assert row["backend_selected"] in ("portable", "linux_uring"), row
            path = pathlib.Path(row["file_path"])
            contents = path.read_bytes()
            assert len(contents) == row["artifact_bytes"], row
            assert contents.count(b"\n") == row["warmup_written"] + row["sink_written_records"], row
            # JSON escaping keeps even long messages to one physical line.
            if row["format"] == "json":
                for line in contents.splitlines():
                    event = json.loads(line)
                    timestamp = int(event["timestamp_ns"])
                    assert timestamp == 0 if row["event_clock"] == "none" else timestamp > 0, row
                    assert event["scope"] == "benchmark", row
                    attrs = event["attributes"]
                    assert set(attrs) == {f"field{index}" for index in range(row["fields"])}, row
                    pattern = '0123456789abcdef\n"\\'
                    long_string = (pattern * ((row["long_string_bytes"] + len(pattern) - 1) // len(pattern)))[:row["long_string_bytes"]]
                    expected_message = {"numeric": "benchmark event", "short": "request completed", "long": long_string}[row["payload"]]
                    assert event["message"] == expected_message, row
                    if row["payload"] == "numeric" and attrs:
                        first = int(attrs["field0"])
                        assert all(int(attrs[f"field{index}"]) == first + index for index in range(row["fields"])), row
                    elif row["payload"] != "numeric":
                        expected_value = "short-string-0123456789" if row["payload"] == "short" else long_string
                        assert all(value == expected_value for value in attrs.values()), row
        if row.get("journal_path"):
            paths = [pathlib.Path(row["journal_path"])]
            if row["mode"] == "spsc":
                paths.extend(pathlib.Path(f"{row['journal_path']}.thread-{index}.journal") for index in range(row["producers"]))
            assert sum(path.stat().st_size for path in paths) == row["journal_allocation_bytes"], row
            for path in paths:
                with path.open("rb") as journal:
                    header = journal.read(4096)
                assert int.from_bytes(header[8:12], "little") == (2 if row.get("schema_enabled") else 1), row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--case", action="append", help="Run only this named scenario; repeat to select several.")
    parser.add_argument("--timeout-seconds", type=int, default=45)
    parser.add_argument("--schema-pilot", help="Run two repeated v1/v2 async/SPSC P1/P4 memory/file comparisons and save reports here.")
    arguments = parser.parse_args()
    binary = str(pathlib.Path(arguments.binary).resolve())
    if arguments.schema_pilot:
        return schema_pilot(binary, pathlib.Path(arguments.schema_pilot).resolve(), arguments.timeout_seconds)
    cases = [
        ("sync-zero", ["--fields=0"], False),
        ("sync-short-cold", ["--producers=4", "--payload=short", "--temperature=cold"], False),
        ("sync-long", ["--producers=16", "--payload=long", "--fields=10"], False),
        ("text", ["--format=text", "--payload=long", "--fields=10"], False),
        ("logfmt", ["--format=logfmt", "--payload=short", "--fields=5"], False),
        ("filtered", ["--filtered", "--producers=16"], True),
        ("async", ["--mode=async", "--producers=4"], False),
        ("async-overload", ["--mode=async", "--producers=16", "--overflow=drop_newest", "--journal-slots=2"], False),
        ("spsc", ["--mode=spsc", "--fields=0"], False),
        ("spsc-long", ["--mode=spsc", "--payload=long", "--producers=4", "--fields=10"], False),
        ("spsc-sleep", ["--mode=spsc", "--producers=16", "--idle=sleep"], False),
        ("file-portable", ["--mode=async", "--sink=file", "--backend=portable", "--producers=4"], False),
        ("file-uring", ["--mode=async", "--sink=file", "--backend=linux_uring", "--producers=4"], False),
        ("file-spsc-auto", ["--mode=spsc", "--sink=file", "--backend=auto", "--fields=10", "--payload=long", "--producers=16"], False),
        ("file-durable", ["--mode=async", "--sink=file", "--backend=portable", "--durable"], False),
        ("std-io-clock", ["--clock=std_io", "--fields=0"], False),
        ("native-clock", ["--clock=native", "--mode=async"], False),
        ("none-clock", ["--clock=none", "--mode=async"], False),
        ("std-io-spsc-clock", ["--clock=std_io", "--mode=spsc", "--producers=4"], False),
        ("native-spsc-clock", ["--clock=native", "--mode=spsc", "--producers=4"], False),
        ("none-spsc-clock", ["--clock=none", "--mode=spsc", "--producers=16"], False),
        ("none-file-clock", ["--clock=none", "--mode=spsc", "--sink=file", "--producers=4"], False),
        ("static-file-clock", ["--clock=std_io", "--mode=async", "--sink=file", "--producers=4"], False),
        ("schema-zero", ["--schema", "--mode=async", "--fields=0"], False),
        ("schema-long", ["--schema", "--mode=async", "--fields=10", "--payload=long", "--producers=4"], False),
        ("schema-spsc-short", ["--schema", "--mode=spsc", "--fields=5", "--payload=short", "--producers=4"], False),
        ("schema-spsc-file", ["--schema", "--mode=spsc", "--sink=file", "--fields=10", "--payload=long", "--producers=4"], False),
        ("memory-async", ["--mode=async", "--storage=memory", "--producers=4"], False),
        ("memory-spsc", ["--mode=spsc", "--storage=memory", "--producers=4"], False),
        ("memory-file-durable", ["--mode=async", "--storage=memory", "--sink=file", "--durable"], False),
        ("memory-filtered-schema", ["--mode=async", "--storage=memory", "--schema", "--filtered", "--producers=4"], True),
        ("memory-spsc-file-schema", ["--mode=spsc", "--storage=memory", "--schema", "--sink=file", "--fields=10", "--payload=long", "--producers=4"], False),
    ]
    if arguments.case:
        known = {name for name, _, _ in cases}
        unknown = set(arguments.case) - known
        if unknown:
            parser.error(f"unknown cases: {sorted(unknown)}")
        cases = [case for case in cases if case[0] in arguments.case]
    with tempfile.TemporaryDirectory(prefix="kron-bench-validation-") as directory:
        for name, options, filtered in cases:
            command = [binary, "--events=127", "--samples=31", "--warmup-events=17", f"--work-dir={directory}", *options]
            completed = subprocess.run(command, capture_output=True, text=True, timeout=arguments.timeout_seconds)
            rows = [json.loads(line) for line in completed.stdout.splitlines()]
            if "--storage=memory" in options:
                assert all(row.get("queue_storage") == "memory" and row.get("process_crash_recovery") is False for row in rows), rows
            if name in ("file-uring", "native-clock", "native-spsc-clock") and rows and all(r["status"] == "unsupported" for r in rows):
                assert completed.returncode == 2, completed
                print(f"{name}: UNSUPPORTED ({rows[0]['error_name']})")
                continue
            assert completed.returncode == 0, (name, completed.stdout, completed.stderr)
            verify(rows, 127, filtered)
            print(f"{name}: verified ({rows[0]['backend_selected']})")
        completed = subprocess.run([binary, "--events=31", "--warmup-events=7", "--output=csv", f"--work-dir={directory}"], capture_output=True, text=True, timeout=45, check=True)
        rows = list(csv.DictReader(io.StringIO(completed.stdout)))
        assert len(rows) == 2 and all(row["sink_written_records"] == "31" for row in rows)
        assert rows[1]["producer_p50_ns"] == "" and rows[0]["clock_pair_p50_ns"] != ""
        print("csv: verified")
        failed = subprocess.run([binary, "--events=31", "--temperature=cold", "--memory-bytes=1024", f"--work-dir={directory}"], capture_output=True, text=True, timeout=45)
        rows = [json.loads(line) for line in failed.stdout.splitlines()]
        assert failed.returncode == 2 and len(rows) == 2
        assert all(row["status"] == "failed" and row["error_name"] == "BufferFull" for row in rows), rows
        assert all(row["attempted"] < 31 and row["emit_errors"] == 1 for row in rows), rows
        assert all(0 < row["sink_written_records"] < 31 for row in rows), rows
        print("failure-report: verified")


def schema_pilot(binary, output, timeout):
    output.mkdir(parents=True, exist_ok=True)
    artifacts = output / "artifacts"
    artifacts.mkdir(exist_ok=True)
    rows = []
    cases = [(mode, sink, producers, schema) for mode in ("async", "spsc")
             for sink in ("memory", "file") for producers in (1, 4) for schema in (False, True)]
    manifest = {"binary": binary, "captured_unix_seconds": time.time(), "repetitions": 2,
                "binary_sha256": hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest(),
                "machine": dict(platform.uname()._asdict()),
                "note": "Bounded pilot; output format and actual inputs unchanged; registration excluded in preparation_ns."}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    with (output / "results.jsonl").open("w") as evidence:
        for repetition in range(2):
            order = cases if repetition == 0 else list(reversed(cases))
            for mode, sink, producers, schema in order:
                command = [binary, "--events=10000", "--samples=10000", "--warmup-events=1000",
                           f"--mode={mode}", f"--sink={sink}", f"--producers={producers}",
                           "--fields=5", "--payload=numeric", "--clock=dynamic", "--format=json",
                           "--backend=portable", "--idle=sleep", f"--work-dir={artifacts}"]
                if schema:
                    command.append("--schema")
                try:
                    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
                    if result.returncode != 0:
                        raise RuntimeError((command, result.returncode, result.stdout, result.stderr))
                    current = [json.loads(line) for line in result.stdout.splitlines()]
                    verify(current, 10000)
                    for row in current:
                        assert row["schema_enabled"] == schema, row
                        row["repetition"] = repetition
                        row["command"] = command
                        evidence.write(json.dumps(row) + "\n")
                        rows.append(row)
                    evidence.flush()
                    print(f"schema pilot r{repetition+1}: {mode}/{sink}/p{producers}/v{2 if schema else 1} verified", flush=True)
                except subprocess.TimeoutExpired as error:
                    evidence.write(json.dumps({"status": "incomplete_timeout", "command": command, "timeout_seconds": timeout,
                                               "stdout": error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout,
                                               "retry_started": False}) + "\n")
                    evidence.flush()
                    raise
    summary = {}
    for mode, sink, producers, schema in cases:
        selected = [row for row in rows if row["mode"] == mode and row["sink"] == sink
                    and row["producers"] == producers and row["schema_enabled"] == schema and row["phase"] == "batch"]
        rates = [row["written_records_per_sec"] for row in selected]
        summary[f"{mode}/{sink}/p{producers}/v{2 if schema else 1}"] = {
            "trials": len(selected), "written_records_per_sec_median": statistics.median(rates),
            "written_records_per_sec_min": min(rates), "written_records_per_sec_max": max(rates),
            "journal_allocation_bytes": selected[0]["journal_allocation_bytes"],
            "prepared_metadata": schema}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
