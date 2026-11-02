#!/usr/bin/env python3
"""Frozen public encoder comparison with complete-output hashing controls."""
import argparse, hashlib, json, pathlib, subprocess, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "cpp_reference"))
from qualification import paired_metric

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True, type=pathlib.Path)
    parser.add_argument("--after", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--cpu", default="30")
    parser.add_argument("--perf", choices=("cpu_core", "cpu_atom"), default="cpu_atom")
    args = parser.parse_args()
    binaries = {label: getattr(args, label).resolve(strict=True) for label in ("before", "after")}
    identities = {label: sha(path) for label, path in binaries.items()}
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = {"binary_sha256": identities, "cpu": args.cpu, "pmu": args.perf, "driver_sha256": sha(pathlib.Path(__file__)), "scope": "Public encoder + mutation + Wyhash of full output, scalar/nested keys1/3/4/6/8/9/16/32/64; not file workflow or fused wire. PMU includes child setup."}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rows = []
    with (args.output / "results.jsonl").open("x") as evidence:
        for repetition in range(5):
            for format_ in ("json", "text", "logfmt"):
                pair = []
                for label in (("before", "after") if repetition % 2 == 0 else ("after", "before")):
                    if any(sha(path) != identities[key] for key, path in binaries.items()): raise ValueError("binary changed")
                    name = f"{repetition}-{format_}-{label}"
                    counter_file = args.output / (name + ".csv")
                    command = ["perf", "stat", "-e", f"{args.perf}/instructions/u,{args.perf}/cycles/u", "-x,", "-o", str(counter_file), "--", "taskset", "-c", args.cpu, str(binaries[label]), format_]
                    run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                    (args.output / (name + ".log")).write_text(run.stdout + run.stderr)
                    run.check_returncode()
                    cases = [json.loads(line) for line in run.stdout.splitlines()]
                    if [r["case"] for r in cases] != [f"keys{length}-{shape}" for length in (1,3,4,6,8,9,16,32,64) for shape in ("scalar","nested")] or any(r["iterations"] != 100000 for r in cases): raise ValueError("changed workload")
                    counters = {}
                    for line in counter_file.read_text().splitlines():
                        parts = line.split(",")
                        if len(parts) >= 3 and parts[0].isdigit():
                            for metric in ("instructions", "cycles"):
                                if metric in parts[2]: counters[metric] = int(parts[0])
                    if set(counters) != {"instructions", "cycles"}: raise ValueError("missing counters")
                    row = {"label": label, "repetition": repetition, "format": format_, "cases": cases, **counters, "command": command}
                    for case in cases: row[case["case"]] = case["ns_per_record"]
                    pair.append(row); rows.append(row); evidence.write(json.dumps(row) + "\n"); evidence.flush()
                if any(a["checksum"] != b["checksum"] or a["output_bytes"] != b["output_bytes"] for a, b in zip(pair[0]["cases"], pair[1]["cases"])): raise ValueError("output changed")
                print(format_, repetition, "all18 full-output checksums match", flush=True)
    groups = []
    for format_ in ("json", "text", "logfmt"):
        selected = {label: [r for r in rows if (r["format"], r["label"]) == (format_, label)] for label in binaries}
        metrics = {key: paired_metric(selected["after"], selected["before"], key, False) for key in ("instructions", "cycles", *[f"keys{length}-{shape}" for length in (1,3,4,6,8,9,16,32,64) for shape in ("scalar","nested")])}
        groups.append({"format": format_, "metrics": metrics})
    report = {"trials": len(rows), "complete_encoder_calls": sum(c["iterations"] for r in rows for c in r["cases"]), "groups": groups, "ratio_direction": "above one favors after; local encoder only"}
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
if __name__ == "__main__": main()
