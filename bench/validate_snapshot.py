#!/usr/bin/env python3
"""Bounded public snapshot/admission benchmark validation and pilot capture."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import statistics
import subprocess
import time


def verify(row, events, phase, mode, producers, replace_every):
    assert row["status"] == "ok" and row["benchmark"] == "snapshot", row
    assert row["mode"] == mode and row["phase"] == phase and row["producers"] == producers, row
    assert row["events"] == row["completed"] == row["sample_count"] == events, row
    assert row["filtered"] == row["drop"] == row["final_pending"] == 0, row
    assert row["total_ns"] >= row["producer_wall_ns"] + row["flush_ns"] + row["shutdown_ns"], row
    assert row["p50_ns"] <= row["p99_ns"] <= row["p999_ns"], row
    assert row["event_clock"] == "ZeroClock" and row["global_snapshot_pin_metric"] is None, row
    if phase == "full":
        assert row["accepted"] == row["written"] == events and row["written_bytes"] > 0 and row["field_count"] == 5, row
    else:
        assert row["accepted"] == row["written"] == row["written_bytes"] == row["field_count"] == 0, row
    if replace_every == 0:
        assert row["no_allocations_in_measurement"] and row["runtime_allocations_in_measurement"] == 0, row
        assert row["steady_state"] and row["replacements"] == 0, row
    else:
        calls = events // producers + int(events % producers != 0)
        assert row["replacements"] == calls // replace_every and not row["steady_state"], row
        assert row["replace_every_thread0_calls"] == replace_every, row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--output-dir", default="/tmp/kron-snapshot-pilot")
    parser.add_argument("--events", type=int, default=10000)
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--timeout-seconds", type=int, default=45)
    parser.add_argument("--replacement-check", action="store_true")
    parser.add_argument("--admission-p1-only", action="store_true")
    parser.add_argument("--idle", choices=("sleep", "spin"), default="sleep")
    options = parser.parse_args()
    if not 1 <= options.events <= 1000000 or not 1 <= options.repeats <= 5 or not 1 <= options.timeout_seconds <= 120:
        parser.error("invalid bounded pilot options")
    binary = str(pathlib.Path(options.binary).resolve())
    output = pathlib.Path(options.output_dir).resolve()
    output.mkdir(parents=True, exist_ok=True)
    artifact_dir = output / "journals"
    artifact_dir.mkdir(exist_ok=True)
    cases = [(mode, phase, producers, 0) for mode in ("shared", "attached")
             for phase in ("admission", "full") for producers in (1, 4, 16)]
    if options.admission_p1_only:
        cases = [(mode, "admission", 1, 0) for mode in ("shared", "attached")]
    if options.replacement_check:
        cases.extend((mode, phase, 4, max(1, options.events // 8)) for mode in ("shared", "attached") for phase in ("admission", "full"))
    manifest = {"captured_unix_seconds": time.time(), "binary": binary,
                "binary_sha256": hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest(),
                "host": dict(platform.uname()._asdict()), "logical_cpus": os.cpu_count(),
                "cpu_affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
                "repetitions": options.repeats,
                "notes": ["Admission uses public begin/end with no capture/queue emission.",
                          "Full shared MPSC vs attached SPSC also changes queue/scheduling; do not attribute all throughput to pin reduction.",
                          "No private snapshot handle is inspected; global pin metric deliberately null."]}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rows = []
    with (output / "results.jsonl").open("w") as evidence:
        for repetition in range(options.repeats):
            order = cases if repetition % 2 == 0 else list(reversed(cases))
            for mode, phase, producers, replace_every in order:
                command = [binary, f"--mode={mode}", f"--phase={phase}", f"--producers={producers}",
                           f"--events={options.events}", "--warmup=1000", f"--work-dir={artifact_dir}"]
                command.append(f"--idle={options.idle}")
                if replace_every:
                    command.append(f"--replace-every={replace_every}")
                try:
                    result = subprocess.run(command, capture_output=True, text=True, timeout=options.timeout_seconds)
                    if result.returncode != 0:
                        raise RuntimeError((command, result.returncode, result.stdout, result.stderr))
                    row = json.loads(result.stdout)
                    verify(row, options.events, phase, mode, producers, replace_every)
                    row.update({"repetition": repetition, "command": command})
                    evidence.write(json.dumps(row) + "\n")
                    evidence.flush()
                    rows.append(row)
                    print(f"r{repetition+1} {mode}/{phase}/p{producers} replacement={replace_every}: {row['completed']} completed, written={row['written']}", flush=True)
                except subprocess.TimeoutExpired as error:
                    evidence.write(json.dumps({"status": "incomplete_timeout", "command": command, "timeout_seconds": options.timeout_seconds,
                                               "stdout_before_timeout": error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout,
                                               "retry_started": False}) + "\n")
                    evidence.flush()
                    raise
    summary = {}
    for mode, phase, producers, replacement in cases:
        selected = [r for r in rows if r["mode"] == mode and r["phase"] == phase and r["producers"] == producers
                    and r["replace_every_thread0_calls"] == replacement]
        rates = [r["completed_per_sec"] for r in selected]
        summary[f"{mode}/{phase}/p{producers}/replacement-{replacement}"] = {
            "trials": len(selected), "completed_per_sec_median": statistics.median(rates),
            "completed_per_sec_min": min(rates), "completed_per_sec_max": max(rates),
            "p50_ns_median": statistics.median(r["p50_ns"] for r in selected),
            "p99_ns_median": statistics.median(r["p99_ns"] for r in selected),
            "runtime_allocations": [r["runtime_allocations_in_measurement"] for r in selected]}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    invalid = subprocess.run([binary, "--producers=3"], capture_output=True, text=True, timeout=10)
    assert invalid.returncode != 0


if __name__ == "__main__":
    main()
