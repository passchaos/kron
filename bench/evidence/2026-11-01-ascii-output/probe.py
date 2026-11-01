#!/usr/bin/env python3
"""Five serial PMU pairs with exact output identity across six message shapes."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--prefix", required=True)
    args = parser.parse_args()
    assert args.prefix.replace("-", "").isalnum()
    spec = importlib.util.spec_from_file_location("stats", ROOT / "bench/regression.py")
    stats = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stats)
    watched = {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT / "src").rglob("*.zig"))}
    binaries = {"before": Path("/tmp/kron-ascii-probe-before"), "after": Path(args.candidate)}
    identities = {label: sha(binary) for label, binary in binaries.items()}
    assert not (HERE / f"{args.prefix}-results.json").exists()
    rows = []
    for pair in range(5):
        for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
            assert all(sha(ROOT / name) == value for name, value in watched.items())
            assert all(sha(binaries[name]) == value for name, value in identities.items())
            log = HERE / f"{args.prefix}-perf-{label}-{pair}.csv"
            assert not log.exists()
            command = ["perf", "stat", "-x,", "-e", "cpu_core/instructions/u,cpu_core/cycles/u",
                       "-o", str(log), "--", "taskset", "-c", "0", str(binaries[label])]
            process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
            (HERE / f"{args.prefix}-output-{label}-{pair}.jsonl").write_text(process.stdout)
            (HERE / f"{args.prefix}-stderr-{label}-{pair}.log").write_text(process.stderr)
            assert process.returncode == 0, process.stderr
            output = [json.loads(line) for line in process.stdout.splitlines()]
            assert len(output) == 6 and all(row["iterations"] == 100000 for row in output)
            metrics = {}
            for line in log.read_text().splitlines():
                if not line.strip() or line.startswith("#"):
                    continue
                parts = line.split(",")
                assert parts[0].isdigit() and float(parts[4]) >= 95, line
                metrics[parts[2]] = int(parts[0])
            rows.append(dict(label=label, pair=pair, command=command, binary_sha256=identities[label],
                             output=output, metrics=metrics))
            print(args.prefix, pair, label, "all six output cases consumed", flush=True)
    summary = {}
    cases = ("scalar5", "nested20", "wide5", "ascii-long", "unicode-message", "escaped-message")
    for case in cases:
        selected = [entry for row in rows for entry in row["output"] if entry["case"] == case]
        assert len({(entry["checksum"], entry["output_bytes"]) for entry in selected}) == 1
        values = {label: stats.summary([entry["ns_per_record"] for row in rows if row["label"] == label
                  for entry in row["output"] if entry["case"] == case]) for label in binaries}
        summary[case] = summarize(values)
    for metric in rows[0]["metrics"]:
        values = {label: stats.summary([row["metrics"][metric] for row in rows if row["label"] == label])
                  for label in binaries}
        summary[metric] = summarize(values)
    assert all(sha(ROOT / name) == value for name, value in watched.items())
    result = dict(scope="Encoder-only scalar/nested/wide/long ASCII/Unicode/dense escaped shapes; "
                  "input updates and complete hashes included; whole-process PMU includes all cases.",
                  trials=10, records_hashed=6000000, source_sha256=watched,
                  driver_sha256=sha(HERE / "encoder_probe.zig"), rows=rows, summary=summary)
    (HERE / f"{args.prefix}-results.json").write_text(json.dumps(result, indent=2) + "\n")
    for name, value in summary.items():
        print(name, round(value["before"]["median"], 2), "->", round(value["after"]["median"], 2),
              "change_pct", round((value["after_over_before"] - 1) * 100, 2), value["status"])


def summarize(values):
    return {**values, "after_over_before": values["after"]["median"] / values["before"]["median"],
            "status": "stable_local_measurement" if all(value["cv"] < .1 and value["relative_spread"] < .1
                      for value in values.values()) else "inconclusive"}


if __name__ == "__main__":
    main()
