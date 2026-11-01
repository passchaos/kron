#!/usr/bin/env python3
"""Capture and compare bounded benchmark trials with child CPU affinity."""
import argparse
import hashlib
import json
import math
import os
import pathlib
import platform
import random
import statistics
import subprocess
import tempfile
import time

SCHEMA_VERSION = 1
METRICS = {"throughput": "higher", "p50_ns": "lower", "p99_ns": "lower"}


def parse_cases(value, benchmark):
    cases = []
    for item in value.split(","):
        try:
            phase, number = item.split(":")
            producers = int(number)
        except (ValueError, TypeError) as error:
            raise ValueError("cases must be PHASE:PRODUCERS comma-separated") from error
        phases = ("admission", "full") if benchmark == "snapshot" else ("sampled", "batch")
        if phase not in phases or producers not in (1, 4, 16):
            raise ValueError("unsupported phase or producer count")
        case = {"phase": phase, "producers": producers}
        if case in cases:
            raise ValueError("duplicate case")
        cases.append(case)
    if not cases:
        raise ValueError("at least one case required")
    return cases


def affinity(value, allowed=None):
    allowed = set(os.sched_getaffinity(0) if allowed is None else allowed)
    selected = sorted(allowed)[:min(8, len(allowed))] if value == "auto" else sorted({int(cpu) for cpu in value.split(",")})
    if not selected or not set(selected) <= allowed:
        raise ValueError("affinity must select currently allowed CPUs")
    return selected


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("invalid numeric metric")
    return value


def storage_configuration(config):
    """Legacy captures without storage fields describe the historical mmap path."""
    storage = config.get("queue_storage", "mmap")
    if storage not in ("mmap", "memory"):
        raise ValueError("unsupported queue storage")
    persistent = storage == "mmap"
    if config.get("process_crash_recovery", persistent) is not persistent:
        raise ValueError("queue storage/recovery contract mismatch")
    result = dict(config)
    result.update({"queue_storage": storage, "process_crash_recovery": persistent})
    return result


def validate_row(row, config, case):
    config = storage_configuration(config)
    # Absence is compatible with old mmap output only. An explicit memory row
    # can never masquerade as an old mmap row/configuration.
    row_storage = row.get("queue_storage", "mmap")
    if row_storage == "memory" and "process_crash_recovery" not in row:
        raise ValueError("memory queue report requires explicit recovery contract")
    row_recovery = row.get("process_crash_recovery", row_storage == "mmap")
    if row_storage != config["queue_storage"] or row_recovery is not config["process_crash_recovery"]:
        raise ValueError("reported queue storage/recovery contract mismatch")
    events = config["events"]
    if row.get("status") != "ok" or row.get("producers") != case["producers"]:
        raise ValueError("failed trial or mismatched producers")
    if row.get("phase") != case["phase"]:
        raise ValueError("mismatched phase")
    if config["benchmark"] == "snapshot":
        expected = {"benchmark": "snapshot", "mode": config["mode"], "events": events,
                    "warmup": config["warmup"], "event_clock": "ZeroClock", "idle": config["idle"],
                    "queue_slots": 256, "channel_slots": 256, "max_record_bytes": 1024,
                    "sink": "counted_complete_json_discard", "steady_state": True,
                    "replace_every_thread0_calls": 0}
        if row.get("completed") != events:
            raise ValueError("missing completed admissions/events")
        required_written = events if case["phase"] == "full" else 0
        if row.get("accepted") != required_written or row.get("written") != required_written:
            raise ValueError("accepted/written completion mismatch")
        if row.get("field_count") != (5 if case["phase"] == "full" else 0):
            raise ValueError("field input shape changed")
        if (case["phase"] == "full" and row.get("written_bytes", 0) <= 0) or (case["phase"] == "admission" and row.get("written_bytes") != 0):
            raise ValueError("output byte completion mismatch")
        if any(row.get(key) != 0 for key in ("drop", "filtered", "final_pending")):
            raise ValueError("drop, filtering or pending records")
        if row.get("runtime_allocations_in_measurement") != 0 or not row.get("no_allocations_in_measurement"):
            raise ValueError("steady trial allocated")
        elapsed_parts = ("producer_wall_ns", "flush_ns", "shutdown_ns")
        throughput = row.get("completed_per_sec")
        p50, p99 = row.get("p50_ns"), row.get("p99_ns")
    else:
        expected = {"mode": config["mode"], "events_requested": events, "warmup_attempted": config["warmup"],
                    "event_clock": config["clock"], "idle_selected": config["idle"], "sink": config["sink"],
                    "format": "json", "fields": 5, "payload": "numeric", "filtered_case": False,
                    "overflow": "block", "journal_slots": 256, "channel_slots": 256,
                    "max_record_bytes": 16384, "file_buffer_bytes": 65536, "queue_depth": 4,
                    "schema_enabled": False, "durable_requested": False}
        if not all(row.get(key) == events for key in ("attempted", "accepted", "runtime_accepted", "runtime_written", "sink_written_records")):
            raise ValueError("accepted/written completion mismatch")
        if any(row.get(key) != 0 for key in ("filtered", "sampled", "dropped_full", "dropped_oversize", "emit_errors", "runtime_write_errors", "rejected_closing", "final_pending")):
            raise ValueError("drop, errors or pending records")
        if "runtime_allocations_in_measurement" in row and row["runtime_allocations_in_measurement"] != 0:
            raise ValueError("steady trial allocated")
        if config["sink"] == "file" and row.get("backend_selected") != "portable":
            raise ValueError("file backend changed")
        queue_bytes = (4096 + 256 * ((16384 + 64 + 63) // 64 * 64)) * (1 + case["producers"] if config["mode"] == "spsc" else 1)
        if "queue_allocation_bytes" in row and row["queue_allocation_bytes"] != queue_bytes:
            raise ValueError("fixed queue allocation budget changed")
        if config["queue_storage"] == "memory":
            if row.get("journal_path") is not None or row.get("journal_mapped_bytes") != 0 or row.get("journal_allocation_bytes") != 0 or row.get("queue_allocation_bytes", 0) <= 0:
                raise ValueError("memory queue report contains mapped storage or lacks queue budget")
        elif "journal_mapped_bytes" in row:
            if row.get("journal_path") is None or row["journal_mapped_bytes"] != queue_bytes or row.get("journal_allocation_bytes") != queue_bytes or row.get("queue_allocation_bytes") != row["journal_mapped_bytes"]:
                raise ValueError("mmap queue budget/path mismatch")
        elapsed_parts = ("producer_wall_ns", "flush_written_ns", "shutdown_ns")
        throughput = row.get("written_records_per_sec")
        p50, p99 = row.get("producer_p50_ns"), row.get("producer_p99_ns")
    for key, value in expected.items():
        if row.get(key) != value:
            raise ValueError(f"reported configuration mismatch: {key}")
    if row.get("total_ns", 0) < sum(number(row.get(key)) for key in elapsed_parts):
        raise ValueError("timing excludes final completion")
    metrics = {"throughput": number(throughput)}
    if metrics["throughput"] <= 0:
        raise ValueError("nonpositive throughput")
    if p50 is not None:
        metrics["p50_ns"], metrics["p99_ns"] = number(p50), number(p99)
        if p50 < 0 or p99 < p50:
            raise ValueError("invalid latency distribution")
    elif config["benchmark"] == "snapshot" or case["phase"] == "sampled":
        raise ValueError("missing sampled latency")
    return metrics


def summary(values):
    values = [number(value) for value in values]
    if not 5 <= len(values) <= 9 or any(value < 0 for value in values):
        raise ValueError("summary requires 5..9 nonnegative trials")
    median = statistics.median(values)
    mean = statistics.mean(values)
    q1, _, q3 = statistics.quantiles(values, n=4, method="inclusive")
    rng = random.Random(0x6B726F6E)
    medians = sorted(statistics.median(rng.choices(values, k=len(values))) for _ in range(2000))
    return {"trials": len(values), "median": median, "mean": mean, "q1": q1, "q3": q3,
            "min": min(values), "max": max(values),
            "cv": statistics.stdev(values) / mean if mean else 0.0,
            "relative_spread": (max(values) - min(values)) / median if median else 0.0,
            "relative_iqr": (q3 - q1) / median if median else 0.0,
            "median_bootstrap_ci95": [medians[49], medians[1949]],
            "ci_note": "Bootstrap across trial summaries; not a per-call tail-confidence interval."}


def aggregate(rows, config):
    grouped = {}
    for case in config["cases"]:
        selected = [entry for entry in rows if entry["case"] == case]
        if len(selected) != config["repeats"] or sorted(entry["repetition"] for entry in selected) != list(range(config["repeats"])):
            raise ValueError("missing completed repetitions")
        metrics = [validate_row(entry["row"], config, case) for entry in selected]
        key = f"{case['phase']}/p{case['producers']}"
        grouped[key] = {name: summary([trial[name] for trial in metrics]) for name in metrics[0]}
    return grouped


def compare(baseline, candidate, threshold=0.10):
    if not 0 < threshold <= 0.50:
        raise ValueError("threshold must be >0 and <=0.50")
    if baseline.get("status") != "complete" or candidate.get("status") != "complete":
        raise ValueError("comparison requires complete captures")
    if baseline.get("schema_version", SCHEMA_VERSION) != SCHEMA_VERSION or candidate.get("schema_version", SCHEMA_VERSION) != SCHEMA_VERSION:
        raise ValueError("unsupported capture schema")
    baseline_configuration = storage_configuration(baseline["configuration"])
    candidate_configuration = storage_configuration(candidate["configuration"])
    if baseline_configuration != candidate_configuration:
        raise ValueError("benchmark configuration/affinity changed")
    for key in ("host_fingerprint", "compiler_environment"):
        if baseline["metadata"].get(key) != candidate["metadata"].get(key):
            raise ValueError(f"machine/build environment changed: {key}")
    base = aggregate(baseline["rows"], baseline["configuration"])
    current = aggregate(candidate["rows"], candidate["configuration"])
    assessments = {}
    for case, metrics in base.items():
        assessments[case] = {}
        for name, old in metrics.items():
            new = current[case][name]
            scale = old["median"]
            change = (new["median"] - scale) / scale if scale else (0.0 if new["median"] == 0 else None)
            degradation = None if change is None else (-change if METRICS[name] == "higher" else change)
            noisy = max(old["cv"], new["cv"], old["relative_spread"], new["relative_spread"]) > threshold
            status = "inconclusive" if noisy or degradation is None else ("regression" if degradation > threshold else "within_threshold")
            assessments[case][name] = {"status": status, "relative_change": change, "relative_degradation": degradation,
                                      "baseline": old, "candidate": new, "noise_limit": threshold}
    statuses = {result["status"] for metrics in assessments.values() for result in metrics.values()}
    status = "regression" if "regression" in statuses else ("inconclusive" if "inconclusive" in statuses else "within_threshold")
    return {"schema_version": SCHEMA_VERSION, "status": status, "threshold": threshold, "metrics": assessments,
            "same_binary": baseline["metadata"]["binary_sha256"] == candidate["metadata"]["binary_sha256"],
            "baseline_binary_sha256": baseline["metadata"]["binary_sha256"], "candidate_binary_sha256": candidate["metadata"]["binary_sha256"],
            "queue_storage": baseline_configuration["queue_storage"], "process_crash_recovery": baseline_configuration["process_crash_recovery"],
            "note": "Same-binary comparison validates tooling/repeatability, not an optimization."}


def read_text(path):
    try:
        return pathlib.Path(path).read_text().strip()
    except OSError:
        return None


def source_hash(root):
    digest = hashlib.sha256()
    for file in sorted(pathlib.Path(root).rglob("*.zig")):
        if any(part in (".zig-cache", "zig-out") for part in file.parts):
            continue
        digest.update(str(file.relative_to(root)).encode() + b"\0")
        digest.update(file.read_bytes())
    return digest.hexdigest()


def configuration(options):
    if not 5 <= options.repeats <= 9 or not 1 <= options.events <= 10000 or not 1 <= options.timeout <= 120:
        raise ValueError("requires 5..9 repeats, 1..10000 events and 1..120 second timeout")
    mode = options.mode or ("attached" if options.benchmark == "snapshot" else "async")
    if mode not in (("shared", "attached") if options.benchmark == "snapshot" else ("async", "spsc")):
        raise ValueError("mode incompatible with benchmark")
    cases = parse_cases(options.cases or ("admission:1,full:4" if options.benchmark == "snapshot" else "sampled:1,batch:4"), options.benchmark)
    return {"benchmark": options.benchmark, "mode": mode, "events": options.events, "warmup": 1000,
            "queue_storage": options.storage, "process_crash_recovery": options.storage == "mmap",
            "repeats": options.repeats, "cases": cases, "affinity": affinity(options.affinity),
            "idle": "sleep", "clock": "ZeroClock" if options.benchmark == "snapshot" else "dynamic",
            "sink": "counted_complete_json_discard" if options.benchmark == "snapshot" else options.sink,
            "format": "json", "fields": 5, "payload": "numeric", "overflow": "block", "queue_slots": 256,
            "max_record_bytes": 1024 if options.benchmark == "snapshot" else 16384,
            "file_backend": None if options.benchmark == "snapshot" else "portable", "schema": False, "durable": False}


def command(binary, config, case, work_dir):
    args = [binary, f"--mode={config['mode']}", f"--events={config['events']}", f"--producers={case['producers']}", f"--work-dir={work_dir}", "--idle=sleep"]
    if config["benchmark"] == "snapshot":
        return args + [f"--phase={case['phase']}", "--warmup=1000", f"--storage={storage_configuration(config)['queue_storage']}"]
    storage = storage_configuration(config)["queue_storage"]
    return args + [f"--storage={storage}", f"--sink={config['sink']}", "--backend=portable", "--format=json", "--fields=5", "--payload=numeric",
                   "--clock=dynamic", "--warmup-events=1000", "--samples=10000", "--overflow=block", "--journal-slots=256",
                   "--channel-slots=256", "--max-record-bytes=16384", "--buffer-bytes=65536", "--queue-depth=4", "--output=json"]


def capture(options):
    config = configuration(options)
    binary = str(pathlib.Path(options.binary).resolve())
    binary_digest = hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest()
    output = pathlib.Path(options.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    host = {"machine": platform.machine(), "kernel": platform.release(), "system": platform.system(),
            "cpu_model": next((line.split(":", 1)[1].strip() for line in (read_text("/proc/cpuinfo") or "").splitlines() if line.startswith("model name")), None),
            "governors": {str(cpu): read_text(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_governor") for cpu in config["affinity"]},
            "temporary_directory": tempfile.gettempdir(), "temporary_device": os.stat(tempfile.gettempdir()).st_dev}
    data = {"schema_version": SCHEMA_VERSION, "status": "running", "configuration": config,
            "metadata": {"captured_unix_seconds": time.time(), "binary": binary, "binary_sha256": binary_digest,
                         "host_fingerprint": host, "compiler_environment": None,
                         "source_tree_sha256": source_hash(pathlib.Path(options.source_root).resolve()),
                         "source_label": options.source_label,
                         "source_note": "Working-tree hash at capture; binary/source matching requires externally supplied build provenance.",
                         "queue_storage": config["queue_storage"], "process_crash_recovery": config["process_crash_recovery"],
                         "driver_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()}, "rows": []}
    def save():
        output.write_text(json.dumps(data, indent=2, allow_nan=False) + "\n")
    save()
    if hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest() != binary_digest:
        raise ValueError("benchmark binary changed before capture")
    with tempfile.TemporaryDirectory(prefix="kron-regression-") as fresh:
        for repetition in range(config["repeats"]):
            cases = config["cases"] if repetition % 2 == 0 else list(reversed(config["cases"]))
            for case in cases:
                work = pathlib.Path(fresh) / f"r{repetition}-{case['phase']}-p{case['producers']}"
                work.mkdir()
                invocation = command(binary, config, case, work)
                try:
                    process = subprocess.run(invocation, capture_output=True, text=True, timeout=options.timeout,
                                             preexec_fn=lambda: os.sched_setaffinity(0, config["affinity"]))
                    if process.returncode != 0:
                        raise ValueError(f"benchmark exited {process.returncode}: {process.stderr}")
                    reported = [json.loads(line) for line in process.stdout.splitlines()]
                    for reported_row in reported:
                        validate_row(reported_row, config, {"phase": reported_row.get("phase"), "producers": case["producers"]})
                    selected = [row for row in reported if row.get("phase") == case["phase"]]
                    if len(selected) != 1:
                        raise ValueError("missing or duplicate requested phase")
                    row = selected[0]
                    validate_row(row, config, case)
                    environment = {"optimize": row.get("optimize"), "zig_version": row.get("zig_version"),
                                   "target": row.get("target", row.get("target_os")), "target_arch": row.get("target_arch", platform.machine())}
                    if data["metadata"]["compiler_environment"] is None:
                        data["metadata"]["compiler_environment"] = environment
                    elif data["metadata"]["compiler_environment"] != environment:
                        raise ValueError("build environment drift within capture")
                    data["rows"].append({"repetition": repetition, "case": case, "command": invocation, "row": row,
                                         "all_reported_rows": reported, "child_affinity_requested": config["affinity"]})
                    save()
                    print(f"r{repetition+1} {case['phase']}/p{case['producers']}: verified", flush=True)
                except (subprocess.TimeoutExpired, ValueError, json.JSONDecodeError, OSError) as error:
                    data["status"] = "incomplete"
                    data["failure"] = {"command": invocation, "error": str(error), "retry_started": False}
                    save()
                    raise
    if hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest() != binary_digest:
        data["status"] = "incomplete"
        data["failure"] = {"error": "benchmark binary changed during capture"}
        save()
        raise ValueError("benchmark binary changed during capture")
    data["summary"] = aggregate(data["rows"], config)
    data["status"] = "complete"
    save()
    return data


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="action", required=True)
    cap = commands.add_parser("capture")
    cap.add_argument("--binary", required=True)
    cap.add_argument("--output", required=True)
    cap.add_argument("--benchmark", choices=("snapshot", "logger"), default="snapshot")
    cap.add_argument("--mode")
    cap.add_argument("--cases")
    cap.add_argument("--sink", choices=("memory", "file"), default="memory")
    cap.add_argument("--storage", choices=("memory", "mmap"), default="mmap",
                     help="Queue storage for snapshot or logger; cross-storage compare is rejected.")
    cap.add_argument("--events", type=int, default=10000)
    cap.add_argument("--repeats", type=int, default=5)
    cap.add_argument("--affinity", default="auto")
    cap.add_argument("--timeout", type=int, default=45)
    cap.add_argument("--source-root", default=str(pathlib.Path(__file__).resolve().parents[1]))
    cap.add_argument("--source-label", default="unspecified build provenance")
    cmp = commands.add_parser("compare")
    cmp.add_argument("--baseline", required=True)
    cmp.add_argument("--candidate", required=True)
    cmp.add_argument("--output", required=True)
    cmp.add_argument("--threshold", type=float, default=0.10)
    return result


def main(argv=None):
    options = parser().parse_args(argv)
    try:
        if options.action == "capture":
            data = capture(options)
            print(json.dumps({"status": data["status"], "output": options.output, "summary": data["summary"]}, indent=2))
            return 0
        baseline = json.loads(pathlib.Path(options.baseline).read_text())
        candidate = json.loads(pathlib.Path(options.candidate).read_text())
        result = compare(baseline, candidate, options.threshold)
        pathlib.Path(options.output).write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
        print(json.dumps({"status": result["status"], "same_binary": result["same_binary"], "output": options.output}))
        return {"within_threshold": 0, "regression": 1, "inconclusive": 2}[result["status"]]
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"regression tool: {error}", file=__import__("sys").stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
