#!/usr/bin/env python3
"""Compare complete application work with no logging, Memory and Mmap."""
import argparse
import collections
import functools
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MASK = (1 << 64) - 1
SEED = 0x6B726F6E61707031
AFFINITY = [0, 2, 4, 6, 8, 10]
MODES = [("none", "none"), ("shared", "memory"), ("spsc", "memory"), ("shared", "mmap"), ("spsc", "mmap")]


def mix(value):
    value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & MASK
    value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & MASK
    return value ^ (value >> 31)


@functools.lru_cache(maxsize=64)
def reference(work, operations, producers, warmup):
    """Independent integer model; no Zig code or output is used as an oracle."""
    words, rounds = (256, 64) if work == "compute" else (131072, 32)
    workers, values, warm_values = [], {}, {}
    for producer in range(producers):
        initial = [mix((SEED + producer * 0x9E3779B97F4A7C15 + i) & MASK) for i in range(words)]
        for is_warmup, total in [(True, warmup), (False, operations)]:
            table = initial.copy()
            checksum_sum = checksum_xor = 0
            count = total // producers + (producer < total % producers)
            for index in range(count):
                request_id = index * producers + producer + (operations if is_warmup else 0)
                value = mix(SEED ^ request_id)
                for step in range(rounds):
                    location = value & (words - 1)
                    value = mix(value ^ table[location] ^ step)
                    table[location] = (value + request_id) & MASK
                (warm_values if is_warmup else values)[request_id] = value
                checksum_sum = (checksum_sum + value) & MASK
                checksum_xor ^= value
            if not is_warmup:
                workers.append(dict(producer=producer, operations=count, sum=checksum_sum, xor=checksum_xor))
    return workers, values, warm_values


def verify(row, artifact, expected=None):
    assert row["schema_version"] == 1 and row["status"] == "ok"
    if expected:
        assert all(row[key] == value for key, value in expected.items())
    assert row["work"] in ("compute", "cache") and row["mode"] in ("none", "shared", "spsc")
    assert row["completed"] == row["operations"] and row["drop"] == row["pending"] == 0
    assert row["runtime_allocations_after_init"] == 0 and row["metadata"] == "full" and row["fields_per_event"] == 5
    assert row["total_ns"] == sum(row[k] for k in ("producer_ns", "flush_ns", "shutdown_ns", "cleanup_ns"))
    assert row["lifecycle_ns"] == row["runtime_init_ns"] + row["preparation_ns"] + row["total_ns"]
    assert row["total_ns"] > 0 and math.isclose(row["application_operations_per_sec"], row["operations"] * 1e9 / row["total_ns"], rel_tol=1e-12)
    workers, values, warm_values = reference(row["work"], row["operations"], row["producers"], row["warmup_operations"])
    assert row["worker_checksums"] == workers
    assert row["checksum_sum"] == sum(x["sum"] for x in workers) & MASK
    checksum_xor = functools.reduce(lambda a, b: a ^ b, (x["xor"] for x in workers), 0)
    assert row["checksum_xor"] == checksum_xor
    table_words = 256 if row["work"] == "compute" else 131072
    assert row["work_table_bytes"] == row["producers"] * table_words * 8
    assert row["work_rounds"] == (64 if row["work"] == "compute" else 32)
    assert row["sample_bytes"] == (row["operations"] * 8 if row["sampled"] else 0)
    if row["sampled"]:
        assert 0 <= row["p50_operation_ns"] <= row["p99_operation_ns"] <= row["p999_operation_ns"]
    else:
        assert all(row[k] is None for k in ("p50_operation_ns", "p99_operation_ns", "p999_operation_ns"))
    if row["mode"] == "none":
        assert row["storage"] == row["backend_selected"] == "none" and not row["system_event_clock"]
        assert row["accepted"] == row["written"] == row["log_attempts"] == row["warmup_logs"] == 0
        assert row["queue_backing_bytes"] == row["journal_backing_bytes"] == row["file_buffer_bytes"] == 0
        assert not artifact.exists(), "no-log baseline must not create a logger file"
        row["file_records_verified"] = 0
        return
    assert row["system_event_clock"] and row["backend_selected"] == "portable"
    assert row["storage"] in ("memory", "mmap")
    assert row["has_process_crash_recovery"] == (row["storage"] == "mmap")
    assert row["queue_slots"] == 256 and row["max_record_bytes"] == 512 and row["file_buffer_bytes"] == 65536 and row["consumer_quanta"] == 4
    queues = row["producers"] + 1 if row["mode"] == "spsc" else 1
    assert row["queue_backing_bytes"] == queues * 151552
    assert row["journal_backing_bytes"] == (row["queue_backing_bytes"] if row["storage"] == "mmap" else 0)
    selected = {key: (value, False) for key, value in values.items() if key % row["log_every"] == 0}
    selected.update({key: (value, True) for key, value in warm_values.items() if key % row["log_every"] == 0})
    assert row["accepted"] == row["written"] == row["log_attempts"] == sum(not warm for _, warm in selected.values())
    assert row["warmup_logs"] == sum(warm for _, warm in selected.values())
    contents = artifact.read_bytes()
    assert (contents.endswith(b"\n") if selected else contents == b"") and contents.count(b"\n") == len(selected)
    identities, seen, last_sequence, producer_channels = set(), set(), {}, {}
    for line in contents.splitlines():
        event = json.loads(line)
        assert set(event) == {"timestamp_ns", "severity", "scope", "message", "session", "channel", "sequence", "route_mask", "config_generation", "trace_flags", "attributes"}
        assert event["scope"] == "application" and event["message"] == "request complete" and event["severity"] == "info"
        assert str(event["session"]) == str(MASK) and event["route_mask"] == event["config_generation"] == 1 and event["trace_flags"] == 0
        assert isinstance(event["timestamp_ns"], str) and event["timestamp_ns"].isascii() and event["timestamp_ns"].isdigit() and len(event["timestamp_ns"]) == 19
        attrs = event["attributes"]
        assert set(attrs) == {"request_id", "result", "producer", "rounds", "warmup"}
        request_id = int(attrs["request_id"])
        assert request_id in selected and request_id not in seen
        result, warmup = selected[request_id]
        assert int(attrs["result"]) == result and attrs["warmup"] is warmup and attrs["rounds"] == row["work_rounds"]
        assert attrs["producer"] == (request_id - (row["operations"] if warmup else 0)) % row["producers"]
        channel = int(event["channel"])
        sequence = int(event["sequence"])
        if row["mode"] == "spsc":
            assert 1 <= channel <= row["producers"]
            producer = attrs["producer"]
            if producer not in producer_channels:
                assert channel not in producer_channels.values()
                producer_channels[producer] = channel
            assert producer_channels[producer] == channel
        else:
            assert channel == 0
        assert sequence > last_sequence.get(channel, 0) and (channel, sequence) not in identities
        last_sequence[channel] = sequence
        identities.add((channel, sequence))
        seen.add(request_id)
    assert seen == set(selected)
    row["file_records_verified"] = len(seen)
    row["file_bytes_verified"] = len(contents)
    row["file_sha256"] = hashlib.sha256(contents).hexdigest()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def capture(binary, folder, smoke=False, pmu=False):
    folder.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location("regression", ROOT / "bench/regression.py")
    regression = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(regression)
    sources = {str(x.relative_to(ROOT)): sha(x) for x in sorted((ROOT / "src").rglob("*.zig"))}
    sources.update({str(x.relative_to(ROOT)): sha(x) for x in [ROOT / "bench/application.zig", ROOT / "bench/application/workload.zig", Path(__file__), ROOT / "bench/regression.py"]})
    binary_hash = sha(binary)
    machine = {"platform": platform.platform(), "affinity": AFFINITY, "load_start": list(os.getloadavg()), "binary_sha256": binary_hash,
               "source_sha256": sources, "pmu": pmu, "command": [str(binary)], "scope": "same synthetic application request work; none vs public fullJSON Memory/Mmap; producer+flush/shutdown/cleanup; not cross-library or device durability"}
    (folder / "manifest.json").write_text(json.dumps(machine, indent=2) + "\n")
    cases = [(work, producers, every, sampled) for work in ("compute", "cache") for producers in (1, 4, 16) for every in (1, 16) for sampled in (False,)]
    if smoke:
        cases = [(work, 4, 3, True) for work in ("compute", "cache")] + [("compute", 16, 3, False)]
    repetitions = 1 if smoke else 5
    rows = []
    with (folder / "results.jsonl").open("x") as output:
        for pair in range(repetitions):
            for work, producers, every, sampled in cases:
                # The unlogged model is cached per work/P/input only and must
                # remain identical for every mode/logging frequency.
                reference(work, 103 if smoke else 12000, producers, 17 if smoke else 1000)
                for mode, storage in MODES if pair % 2 == 0 else reversed(MODES):
                    stem = f"{pair}-{work}-P{producers}-every{every}-{mode}-{storage}"
                    directory = folder / "artifacts" / stem
                    directory.mkdir(parents=True)
                    artifact = directory / "output.jsonl"
                    command = ["taskset", "-c", ",".join(map(str, AFFINITY)), str(binary), f"--output={artifact}", f"--mode={mode}",
                               f"--storage={storage if mode != 'none' else 'memory'}", f"--work={work}", f"--producers={producers}", f"--every={every}",
                               f"--operations={103 if smoke else 12000}", f"--warmup={17 if smoke else 1000}", f"--sampled={str(sampled).lower()}"]
                    if pmu:
                        command = ["perf", "stat", "-x,", "-o", str(folder / f"{stem}.csv"), "-e",
                                   "cpu_core/instructions/u,cpu_core/cycles/u,cpu_core/cache-misses/u,context-switches,task-clock", "--"] + command
                    assert all(sha(ROOT / key) == value for key, value in sources.items()) and sha(binary) == binary_hash
                    process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
                    (folder / f"{stem}.log").write_text(process.stdout + process.stderr)
                    if process.returncode:
                        raise RuntimeError(f"failed application capture preserved: {stem} ({process.returncode})")
                    row = json.loads(process.stdout)
                    verify(row, artifact, dict(work=work, mode=mode, producers=producers, log_every=every, sampled=sampled))
                    if pmu:
                        counters = {}
                        for line in (folder / f"{stem}.csv").read_text().splitlines():
                            parts = line.split(",")
                            if len(parts) < 3 or not parts[0].strip() or line.startswith("#"):
                                continue
                            name = parts[2]
                            value = parts[0].strip()
                            counters[name] = {"value": float(value) if value.replace(".", "", 1).isdigit() else None,
                                              "raw_value": value, "coverage_percent": float(parts[4]) if len(parts) > 4 and parts[4] else None}
                        row["pmu_counters"] = counters
                        assert all(any(name in key and counter["value"] is not None for key, counter in counters.items()) for name in ["instructions", "cycles", "context-switches", "task-clock"]), counters
                    assert all(sha(ROOT / key) == value for key, value in sources.items()) and sha(binary) == binary_hash
                    row.update(pair=pair, command=command, binary_sha256=binary_hash, load_average=list(os.getloadavg()))
                    output.write(json.dumps(row) + "\n")
                    output.flush()
                    rows.append(row)
                    shutil.rmtree(directory)
                print(f"application {pair} {work} P{producers} every{every}: {len(rows)}/{len(cases)*len(MODES)*repetitions} verified trials", flush=True)
    grouped = collections.defaultdict(list)
    for row in rows:
        grouped[row["work"], row["producers"], row["log_every"], row["sampled"], row["mode"], row["storage"]].append(row)
    groups = []
    for key, selected in grouped.items():
        metrics = {name: (dict(trials=1, observed=selected[0][name], qualification="smoke_no_performance_qualification") if smoke else regression.summary([r[name] for r in selected])) for name in ["application_operations_per_sec", "producer_ns", "total_ns", "lifecycle_ns", "runtime_init_ns", "preparation_ns"]}
        pmu_metrics = {}
        if pmu and not smoke:
            for name in selected[0]["pmu_counters"]:
                observed = [r["pmu_counters"][name] for r in selected]
                valid = all(x["value"] is not None for x in observed)
                pmu_metrics[name] = dict(available=valid, coverage_percent_min=min(x["coverage_percent"] or 0 for x in observed),
                                         distribution=regression.summary([x["value"] for x in observed]) if valid else None)
        groups.append(dict(work=key[0], producers=key[1], every=key[2], sampled=key[3], mode=key[4], storage=key[5], metrics=metrics, pmu=pmu_metrics))
    comparisons = []
    for group in groups:
        if group["mode"] == "none" or smoke:
            continue
        baseline = next(x for x in groups if x["mode"] == "none" and all(x[k] == group[k] for k in ["work", "producers", "every", "sampled"]))
        metrics = {}
        all_metrics = {**{k: (baseline["metrics"][k], group["metrics"][k], True) for k in group["metrics"]},
                       **{k: (baseline["pmu"][k]["distribution"], group["pmu"][k]["distribution"],
                               baseline["pmu"][k]["coverage_percent_min"] >= 90 and group["pmu"][k]["coverage_percent_min"] >= 90)
                          for k in group["pmu"] if group["pmu"][k]["available"] and baseline["pmu"][k]["available"]}}
        for key, (before, after, coverage) in all_metrics.items():
            ratio = after["median"] / before["median"] if before["median"] else None
            left, right = before["median_bootstrap_ci95"], after["median_bootstrap_ci95"]
            overlap = max(left[0], right[0]) <= min(left[1], right[1])
            repeatable = all(x["cv"] < .1 and x["relative_spread"] < .1 for x in [before, after])
            metrics[key] = dict(logged_over_no_logger=ratio, change_percent=(ratio-1)*100 if ratio is not None else None,
                                both_repeatable=repeatable, bootstrap_intervals_overlap=overlap, counter_coverage_sufficient=coverage,
                                qualification="local_difference_supported" if repeatable and coverage and not overlap and ratio is not None else "inconclusive")
        comparisons.append(dict(work=group["work"], producers=group["producers"], every=group["every"], sampled=group["sampled"], mode=group["mode"], storage=group["storage"], metrics=metrics))
    report = dict(trials=len(rows), operations_verified=sum(r["completed"] for r in rows), physical_log_records_verified=sum(r["file_records_verified"] for r in rows),
                  status="smoke_verified" if smoke else "complete_application_work_verified", groups=groups, comparisons=comparisons, **machine)
    (folder / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--pmu", action="store_true")
    args = parser.parse_args()
    result = capture(args.binary.resolve(), args.output.resolve(), args.smoke, args.pmu)
    print(f"Application comparison verified: {result['trials']} trials, {result['operations_verified']} requests, {result['physical_log_records_verified']} complete logs")


if __name__ == "__main__":
    main()
