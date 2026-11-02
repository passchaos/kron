#!/usr/bin/env python3
"""Frozen original journal CRC benchmark; three roots, 15 interleaved processes."""
import hashlib
import json
import math
import resource
import statistics
import subprocess
import time
from pathlib import Path

BASE = Path(__file__).resolve().parent
REPO = BASE.parent.parent
OUT = BASE / "primitive"
VARIANTS = ("serial", "direct", "tree")
LENGTHS = (0, 19, 20, 21, 43, 44, 45, 63, 64, 65, 76, 79, 80, 81,
           127, 128, 129, 255, 256, 257, 511, 512, 513, 2048, 16384)
ORDERS = (("serial", "direct", "tree"), ("direct", "tree", "serial"),
          ("tree", "serial", "direct"), ("serial", "tree", "direct"),
          ("direct", "serial", "tree"))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def freeze():
    OUT.mkdir(exist_ok=True)
    provenance = json.loads((BASE / "native-result.json").read_text())
    front = (REPO / "src/platform/crc32.zig").read_bytes()
    fold = (REPO / "src/platform/crc32_pclmul.zig").read_bytes()
    assert sha(front) == provenance["source_sha256"]["src/platform/crc32.zig"]
    assert sha(fold) == provenance["source_sha256"]["src/platform/crc32_pclmul.zig"]
    bench = (REPO / "bench/crc.zig").read_bytes()
    (OUT / "bench.zig").write_bytes(bench)
    src = fold.decode()
    begin = src.index("    var x5 = clmul(x1, k3k4, 0x00);")
    end = src.index("    while (len >= 16) {", begin)
    for variant in VARIANTS:
        root = OUT / variant
        root.mkdir(exist_ok=True)
        (root / "crc32.zig").write_bytes(front)
        if variant == "serial":
            candidate = src
        else:
            if variant == "direct":
                constants = ("const k256: V2 = .{ 0x00f1da05aa, 0x015a546366 };\n"
                             "const k384: V2 = .{ 0x003db1ecdc, 0x0174359406 };\n")
                collapse = """    const a = clmul(x1, k384, 0x00) ^ clmul(x1, k384, 0x11);
    const b = clmul(x2, k256, 0x00) ^ clmul(x2, k256, 0x11);
    const c = clmul(x3, k3k4, 0x00) ^ clmul(x3, k3k4, 0x11);
    x1 = a ^ b ^ c ^ x4;
    var x5: V2 = undefined;
"""
            else:
                constants = "const k256: V2 = .{ 0x00f1da05aa, 0x015a546366 };\n"
                collapse = """    const a = clmul(x1, k3k4, 0x00) ^ clmul(x1, k3k4, 0x11) ^ x2;
    const b = clmul(x3, k3k4, 0x00) ^ clmul(x3, k3k4, 0x11) ^ x4;
    x1 = clmul(a, k256, 0x00) ^ clmul(a, k256, 0x11) ^ b;
    var x5: V2 = undefined;
"""
            candidate = src[:begin] + collapse + src[end:]
            candidate = candidate.replace("const k5k0:", constants + "const k5k0:")
        (root / "crc32_pclmul.zig").write_text(candidate)
    return {"bench/crc.zig": sha(bench), "src/platform/crc32.zig": sha(front),
            "src/platform/crc32_pclmul.zig": sha(fold)}


def build():
    artifacts = {}
    for variant in VARIANTS:
        root = OUT / variant
        binary = root / "crc-bench"
        command = ["zig", "build-exe", "-O", "ReleaseFast", "-mcpu=native",
                   "--dep", "crc", f"-Mroot={OUT / 'bench.zig'}",
                   "-O", "ReleaseFast", "-mcpu=native", f"-Mcrc={root / 'crc32.zig'}",
                   f"-femit-bin={binary}"]
        start = time.monotonic()
        result = subprocess.run(command, cwd=REPO, capture_output=True, text=True)
        (root / "build.log").write_text(result.stdout + result.stderr)
        result.check_returncode()
        artifacts[variant] = {"command": command, "binary": str(binary),
                              "binary_sha256": sha(binary.read_bytes()),
                              "crc32_sha256": sha((root / "crc32.zig").read_bytes()),
                              "pclmul_sha256": sha((root / "crc32_pclmul.zig").read_bytes()),
                              "build_wall_seconds": time.monotonic() - start}
        print(f"built {variant} {artifacts[variant]['binary_sha256']}", flush=True)
    return artifacts


def collect(artifacts):
    expected_keys = {(length, schema, repetition) for length in LENGTHS
                     for schema in (False, True) for repetition in range(5)}
    reference = None
    records = {v: [] for v in VARIANTS}
    invocations = []
    for invocation, order in enumerate(ORDERS):
        for ordinal, variant in enumerate(order):
            usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
            start = time.monotonic()
            result = subprocess.run([artifacts[variant]["binary"]], capture_output=True, text=True)
            elapsed = time.monotonic() - start
            usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
            raw_path = OUT / f"{variant}-{invocation}.jsonl"
            raw_path.write_text(result.stdout)
            (OUT / f"{variant}-{invocation}.stderr").write_text(result.stderr)
            result.check_returncode()
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            assert len(rows) == 250, (variant, invocation, len(rows))
            keyed = {(r["payload_bytes"], r["schema"], r["repetition"]): r for r in rows}
            assert len(keyed) == 250 and set(keyed) == expected_keys
            checksums = {key: (r["checksum"], r["iterations"]) for key, r in keyed.items()}
            if reference is None:
                reference = checksums
            assert checksums == reference, (variant, invocation, "checksum mismatch")
            assert all(r["benchmark"] == "journal-crc" and r["iterations"] == 10000 and
                       r["elapsed_ns"] > 0 and r["optimize"] == "ReleaseFast" for r in rows)
            records[variant].append(keyed)
            meta = {"invocation": invocation, "ordinal": ordinal, "variant": variant,
                    "raw_file": str(raw_path), "raw_sha256": sha(result.stdout.encode()),
                    "rows": len(rows), "wall_seconds": elapsed,
                    "user_cpu_seconds": usage_after.ru_utime - usage_before.ru_utime,
                    "system_cpu_seconds": usage_after.ru_stime - usage_before.ru_stime}
            invocations.append(meta)
            print(f"ran {variant} #{invocation} 250 checksum-matched rows {elapsed:.3f}s", flush=True)
    return records, invocations


def summarize(records):
    groups = []
    for length in LENGTHS:
        for schema in (False, True):
            medians = {variant: [statistics.median(run[(length, schema, r)]["ns_per_record"] for r in range(5))
                                 for run in records[variant]] for variant in VARIANTS}
            paired = {variant: [a / b for a, b in zip(medians["serial"], medians[variant])]
                      for variant in ("direct", "tree")}
            group = {"payload_bytes": length, "schema": schema,
                     "invocation_median_ns": medians,
                     "median_ns": {v: statistics.median(vals) for v, vals in medians.items()},
                     "paired_speedups": paired,
                     "median_paired_speedup": {v: statistics.median(vals) for v, vals in paired.items()},
                     "paired_range": {v: [min(vals), max(vals)] for v, vals in paired.items()},
                     "within_variant_invocation_max_over_min": {v: max(vals) / min(vals) for v, vals in medians.items()}}
            groups.append(group)
    affected = [g for g in groups if g["payload_bytes"] >= 64]
    aggregate = {}
    for variant in ("direct", "tree"):
        ratios = [g["median_paired_speedup"][variant] for g in affected]
        aggregate[variant] = {
            "affected_groups": len(ratios),
            "geomean_median_paired_speedup": math.exp(statistics.mean(map(math.log, ratios))),
            "median_paired_speedup": statistics.median(ratios),
            "groups_over_1_02": sum(r > 1.02 for r in ratios),
            "groups_under_0_98": sum(r < .98 for r in ratios),
        }
    return groups, aggregate


def main():
    source = freeze()
    artifacts = build()
    records, invocations = collect(artifacts)
    groups, aggregate = summarize(records)
    result = {"cpu": 30, "cpu_affinity": "inherited taskset -c 30", "source_sha256": source,
              "benchmark": "unchanged bench/crc.zig; header20 + optional reference24 + payload updates",
              "payload_lengths": LENGTHS, "internal_repetitions": 5, "invocations_per_variant": 5,
              "iterations_per_row": 10000, "rows": 3750, "checksum_comparison": "all matched",
              "artifacts": artifacts, "orders": ORDERS, "invocations": invocations,
              "primitive_cpu_seconds": sum(i["user_cpu_seconds"] + i["system_cpu_seconds"] for i in invocations),
              "affected_length_aggregate": aggregate, "groups": groups,
              "qualification": "bounded primitive diagnostic; no complete logging performance claim"}
    (OUT / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"rows": result["rows"], "checksums": result["checksum_comparison"],
                      "primitive_cpu_seconds": result["primitive_cpu_seconds"],
                      "aggregate": aggregate}, indent=2), flush=True)


if __name__ == "__main__":
    main()
