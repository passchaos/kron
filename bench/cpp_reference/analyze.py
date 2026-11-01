#!/usr/bin/env python3
"""Summarize verified complete-workflow trials without hiding shutdown costs."""
import argparse
import collections
import json
import math
from pathlib import Path
import statistics


def distribution(values):
    assert values and all(math.isfinite(value) and value >= 0 for value in values)
    median = statistics.median(values)
    spread = (max(values) - min(values)) / median if median else 0
    return {"trials": len(values), "median": median, "min": min(values), "max": max(values),
            "relative_spread": spread,
            "qualification": "inconclusive" if len(values) < 5 or spread > .10 else "local_repeatability_within_10_percent"}


def analyze(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    rows = [json.loads(line) for line in (folder / "results.jsonl").read_text().splitlines()]
    assert rows and all(row["status"] == "ok" for row in rows), "incomplete or failed cases cannot produce a passing comparison"
    options = manifest["configuration"]
    expected = len(options["producers"].split(",")) * 2 * options["repeats"]
    count = 0
    for library in options["libraries"].split(","):
        configurations = 2 if library == "quill" else len(options["kron_storages"].split(",")) if library == "foundation" else 1
        if library == "kron":
            configurations = len(options["kron_modes"].split(",")) * len(options["kron_storages"].split(",")) * (2 if options["kron_schema"] == "both" else 1)
        count += configurations * expected
    assert len(rows) == count, (len(rows), count)
    grouped = collections.defaultdict(list)
    for row in rows:
        assert row["file_records_verified"] == row["events"] + row["warmup_events"]
        assert row["accepted"] == row["written"] == row["events"]
        assert row["drop"] == row["final_pending"] == 0 and row["metadata"] == "full"
        assert row["lifecycle_ns"] == row["init_ns"] + row["preparation_ns"] + row["total_ns"]
        assert row["total_ns"] == sum(row[key] for key in ("producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns"))
        grouped[(row["library"], row["case"], row["producers"], row["phase"])].append(row)
    groups = []
    for key, selected in sorted(grouped.items()):
        assert len(selected) == options["repeats"], key
        metrics = {metric: distribution([row[metric] for row in selected]) for metric in
                   ("init_ns", "preparation_ns", "producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns", "total_ns", "lifecycle_ns", "written_bytes", "written_records_per_sec", "lifecycle_records_per_sec")}
        metrics["written_flush_records_per_sec"] = distribution([row["events"] * 1e9 / (row["producer_wall_ns"] + row["flush_ns"]) for row in selected])
        metrics["written_flush_ns"] = distribution([row["producer_wall_ns"] + row["flush_ns"] for row in selected])
        metrics["written_close_records_per_sec"] = metrics["written_records_per_sec"]
        metrics["written_mib_per_sec"] = distribution([row["written_bytes"] * 1e9 / (row["producer_wall_ns"] + row["flush_ns"]) / 1048576 for row in selected])
        metrics["bytes_per_event"] = distribution([row["written_bytes"] / row["events"] for row in selected])
        if key[-1] == "sampled":
            metrics.update({metric: distribution([row[metric] for row in selected]) for metric in
                            ("p50_ns", "p99_ns", "p999_ns", "noop_clock_pair_p50_ns", "noop_clock_pair_p99_ns")})
        groups.append({"library": key[0], "configuration": key[1], "producers": key[2], "phase": key[3],
                       "process_crash_recovery": selected[0]["has_process_crash_recovery"], "metrics": metrics})
    report = {"status": "complete_verified_comparison", "trials": len(rows),
              "measured_records_verified": sum(row["written"] for row in rows),
              "all_records_verified": sum(row["file_records_verified"] for row in rows),
              "configuration": options, "affinity": manifest["child_affinity"], "groups": groups,
              "scope": "Full JSON fields and system-clock capture, with all file records independently verified. Written flush, final close and initialization are separate metrics; no durable media synchronization.",
              "noise_limit": .10}
    return report


def markdown(report):
    def name(group):
        return group["library"] + " " + group["configuration"]
    batch = {(name(group), group["producers"]): group for group in report["groups"] if group["phase"] == "batch"}
    sampled = {(name(group), group["producers"]): group for group in report["groups"] if group["phase"] == "sampled"}
    lines = ["# 完整日志流程实测", "", f"共 {report['trials']} 个试验，逐条核对 {report['all_records_verified']:,} 条完整日志。固定 CPU affinity：{report['affinity']}。", "",
             "下表均为五次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。", "",
             "| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |",
             "| --- | ---: | ---: | ---: | ---: | --- |"]
    names = sorted({item[0] for item in batch})
    for label in names:
        one, four = batch[(label, 1)], batch[(label, 4)]
        values = [group["metrics"][metric]["median"] / 1e6 for metric in ("written_flush_records_per_sec", "written_close_records_per_sec") for group in (one, four)]
        lines.append(f"| {label} | {values[0]:.3f} | {values[1]:.3f} | {values[2]:.3f} | {values[3]:.3f} | {'有' if one['process_crash_recovery'] else '无'} |")
    lines += ["", "| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for label in names:
        one, four = sampled[(label, 1)], sampled[(label, 4)]
        quantiles = [f"{group['metrics']['p50_ns']['median']:,.0f} / {group['metrics']['p99_ns']['median']:,.0f}" for group in (one, four)]
        init = [batch[(label, p)]["metrics"]["init_ns"]["median"] / 1e6 for p in (1, 4)]
        lines.append(f"| {label} | {quantiles[0]} | {quantiles[1]} | {init[0]:.3f} | {init[1]:.3f} |")
    lines += ["", "| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for label in names:
        values = [batch[(label, p)]["metrics"][metric]["median"] / 1e6 for metric in ("lifecycle_ns", "shutdown_ns") for p in (1, 4)]
        size = batch[(label, 4)]["metrics"]["bytes_per_event"]["median"]
        lines.append(f"| {label} | {values[0]:.3f} | {values[1]:.3f} | {values[2]:.3f} | {values[3]:.3f} | {size:.2f} |")
    lines += ["", "各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    report = analyze(args.directory)
    (args.directory / "analysis.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.directory / "comparison.md").write_text(markdown(report))
    print(f"Verified workflow comparison: {report['trials']} trials, {report['all_records_verified']:,} complete records")


if __name__ == "__main__":
    main()
