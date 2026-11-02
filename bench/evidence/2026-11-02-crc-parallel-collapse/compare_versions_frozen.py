#!/usr/bin/env python3
"""Compare frozen kron binaries with full file verification and paired rounds."""
import argparse
import itertools
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

import run as workflow
from qualification import paired_metric


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--affinity", default="auto")
    parser.add_argument("--events", type=int, default=100000)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--modes", default="async")
    parser.add_argument("--schema", choices=("off", "on", "both"), default="off")
    parser.add_argument("--perf", choices=("cpu_core", "cpu_atom"))
    args = parser.parse_args()
    modes = args.modes.split(",")
    if not 1000 <= args.events <= 1000000 or not 5 <= args.repeats <= 10 or not set(modes) <= {"async", "spsc"} or len(modes) != len(set(modes)):
        parser.error("bounded events, 5..10 rounds and unique async/spsc modes required")
    cpus = workflow.affinity(args.affinity)
    binaries = {label: getattr(args, label).resolve(strict=True) for label in ("before", "after")}
    identities = {label: workflow.sha256(path) for label, path in binaries.items()}
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    manifest = {"configuration": vars(args) | {key: str(value) for key, value in vars(args).items() if isinstance(value, Path)},
                "binary_sha256": identities, "affinity": cpus, "loadavg_before": os.getloadavg(),
                "host": platform.uname()._asdict(), "driver_sha256": workflow.sha256(__file__),
                "oracle_sha256": workflow.sha256(workflow.__file__),
                "qualification_sha256": workflow.sha256(Path(__file__).with_name("qualification.py")),
                "scope": "Frozen versions, public managed Logging, 256 slots/512B, system time, portable file, written flush/close; no durable. PMU, if selected, includes complete child process setup."}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    schemas = (False, True) if args.schema == "both" else (args.schema == "on",)
    cases = list(itertools.product(modes, ("memory", "mmap"), (1, 4), ("batch", "sampled"), schemas))
    rows = []
    with (output / "results.jsonl").open("x") as evidence:
        for repetition in range(args.repeats):
            ordered = cases if repetition % 2 == 0 else list(reversed(cases))
            for mode, storage, producers, phase, schema in ordered:
                for label in (("before", "after") if repetition % 2 == 0 else ("after", "before")):
                    if any(workflow.sha256(path) != identities[key] for key, path in binaries.items()):
                        raise ValueError("binary changed during capture")
                    temporary = Path(tempfile.mkdtemp(prefix="kron-version-"))
                    artifact = temporary / "events.jsonl"
                    name = f"{mode}-{storage}-P{producers}-{phase}-{'schema' if schema else 'inline'}-{repetition}-{label}"
                    command = ["taskset", "-c", ",".join(map(str, cpus)), str(binaries[label]),
                               "--frontend=managed", "--backend=portable", f"--output={artifact}", f"--events={args.events}",
                               "--warmup=1000", f"--producers={producers}", f"--phase={phase}", "--queue-slots=256",
                               f"--mode={mode}", f"--storage={storage}", f"--schema={str(schema).lower()}"]
                    if args.perf:
                        counter_file = output / f"{name}.csv"
                        command = ["perf", "stat", "-e", f"{args.perf}/instructions/u,{args.perf}/cycles/u", "-x,", "-o", str(counter_file), "--"] + command
                    try:
                        process = subprocess.run(command, capture_output=True, text=True, timeout=120)
                        (temporary / "stdout.log").write_text(process.stdout)
                        (temporary / "stderr.log").write_text(process.stderr)
                        process.check_returncode()
                        row = json.loads(process.stdout)
                        workflow.verify(row, artifact, args.events, 1000)
                        if (row["frontend"], row["mode"], row["storage"], row["producers"], row["phase"], row["prepared_schema"], row["backend_selected"], row["queue_slots"], row["max_record_bytes"]) != ("managed", mode, storage, producers, phase, schema, "portable", 256, 512):
                            raise ValueError("changed workload or budget")
                        row.update(label=label, repetition=repetition, command=command, binary_sha256=identities[label])
                        row["written_flush_records_per_sec"] = args.events * 1e9 / (row["producer_wall_ns"] + row["flush_ns"])
                        if args.perf:
                            for line in counter_file.read_text().splitlines():
                                parts = line.split(",")
                                if len(parts) >= 3 and parts[0].isdigit():
                                    for metric in ("instructions", "cycles"):
                                        if metric in parts[2]:
                                            row[metric] = int(parts[0])
                            if not all(key in row for key in ("instructions", "cycles")):
                                raise ValueError("missing hardware counters")
                    except (Exception, KeyboardInterrupt) as error:
                        def captured(value):
                            return value.decode(errors="replace") if isinstance(value, bytes) else value
                        (output / "failure.json").write_text(json.dumps({"command": command, "error": str(error), "retained_directory": str(temporary), "retry_started": False,
                            "stdout_before_timeout": captured(getattr(error, "stdout", None)), "stderr_before_timeout": captured(getattr(error, "stderr", None))}, indent=2) + "\n")
                        raise
                    evidence.write(json.dumps(row) + "\n")
                    evidence.flush()
                    rows.append(row)
                    shutil.rmtree(temporary)
                print(f"{len(rows)}/{len(cases) * args.repeats * 2}: {mode}/{storage} P{producers} {phase} schema={schema}, complete JSON verified", flush=True)
    groups = []
    for mode, storage, producers, phase, schema in cases:
        selected = {label: [row for row in rows if (row["label"], row["mode"], row["storage"], row["producers"], row["phase"], row["prepared_schema"]) == (label, mode, storage, producers, phase, schema)] for label in binaries}
        metrics = {metric: paired_metric(selected["after"], selected["before"], metric) for metric in ("written_records_per_sec", "written_flush_records_per_sec", "lifecycle_records_per_sec")}
        lower_metrics = ("init_ns", "shutdown_ns") + (("p50_ns", "p99_ns", "p999_ns") if phase == "sampled" else ()) + (("instructions", "cycles") if args.perf else ())
        metrics.update({metric: paired_metric(selected["after"], selected["before"], metric, False) for metric in lower_metrics})
        groups.append(dict(mode=mode, storage=storage, producers=producers, phase=phase, schema=schema, metrics=metrics))
    report = {"trials": len(rows), "physical_records_verified": sum(row["file_records_verified"] for row in rows),
              "groups": groups, "ending_load": os.getloadavg(), "ratio_direction": "above one favors after; kron_leads/peer_leads mean after/before in this version comparison"}
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
