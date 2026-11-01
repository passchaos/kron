#!/usr/bin/env python3
"""Reproduce the eight byte-regex differential seeds against a supplied driver."""
import argparse
import gzip
import hashlib
import json
import subprocess
from pathlib import Path

SEEDS = [0x6B726F6E72656778, 0, 1, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000,
         0x7265676578, 0x1020304050607080, 0xAAAAAAAA55555555]
ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--driver", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    driver = args.driver.resolve()
    (args.output / "campaign-driver.txt").write_text(str(driver) + "\n")
    reports = []
    with (args.output / "campaign.log").open("w") as log:
        for seed in SEEDS:
            directory = args.output / f"seed-{seed:016x}"
            subprocess.run(["python3", str(ROOT / "tests/regex_differential.py"),
                            "--driver", str(driver), "--seed", str(seed),
                            "--output", str(directory)], stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=60)
            report = json.loads((directory / "summary.json").read_text())
            data = gzip.decompress((directory / "corpus.json.gz").read_bytes())
            assert hashlib.sha256(data).hexdigest() == report["corpus_sha256"]
            assert len(json.loads(data)) == report["cases"]
            assert report["driver_returncode"] == 0 and len(report["negative_checks"]) == 8
            reports.append(report)
            print(f"seed={seed:#x} passed", flush=True)
    summary = {key: sum(report[key] for report in reports)
               for key in ("cases", "comparisons", "compile_errors", "match_errors")}
    summary["seeds"] = SEEDS
    summary["negative_checks"] = sum(len(report["negative_checks"]) for report in reports)
    summary["driver_sha256"] = hashlib.sha256(driver.read_bytes()).hexdigest()
    (args.output / "campaign-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{summary['cases']} exact outcomes; {summary['negative_checks']} negative checks passed")


if __name__ == "__main__":
    main()
