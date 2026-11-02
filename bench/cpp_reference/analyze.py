#!/usr/bin/env python3
"""Summarize verified complete-workflow trials without hiding shutdown costs."""
import argparse
import collections
import json
import math
from pathlib import Path
import statistics
from qualification import foundation_comparisons


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
        configurations = 2 if library == "quill" else len(options["kron_storages"].split(",")) if library in {"foundation", "foundation_tracing"} else 1
        if library == "kron":
            configurations = len(options["kron_modes"].split(",")) * len(options["kron_storages"].split(",")) * (2 if options["kron_schema"] == "both" else 1)
        count += configurations * expected
    assert len(rows) == count, (len(rows), count)
    grouped = collections.defaultdict(list)
    for row in rows:
        assert row["file_records_verified"] == row["events"] + row["warmup_events"]
        assert row["accepted"] == row["written"] == row["events"]
        assert row["drop"] == row["final_pending"] == 0 and row["metadata"] == options["metadata"]
        assert row["lifecycle_ns"] == row["init_ns"] + row["preparation_ns"] + row["total_ns"]
        assert row["total_ns"] == sum(row[key] for key in ("producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns"))
        row["written_flush_records_per_sec"] = row["events"] * 1e9 / (row["producer_wall_ns"] + row["flush_ns"])
        grouped[(row["library"], row["case"], row["producers"], row["phase"])].append(row)
    expected_keys = set()
    for library in options["libraries"].split(","):
        cases = ["producer_format"]
        if library in {"foundation", "foundation_tracing"}:
            cases = options["kron_storages"].split(",")
        elif library == "quill":
            cases = ["producer_format", "deferred_format"]
        elif library == "kron":
            schemas = (False, True) if options["kron_schema"] == "both" else (options["kron_schema"] == "on",)
            cases = [f"{mode}-{storage}-{'schema' if schema else 'inline'}" for mode in options["kron_modes"].split(",") for storage in options["kron_storages"].split(",") for schema in schemas]
        expected_keys.update((library, case, int(producers), phase) for case in cases for producers in options["producers"].split(",") for phase in ("batch", "sampled"))
    assert set(grouped) == expected_keys, "missing or unexpected comparison group"
    groups = []
    for key, selected in sorted(grouped.items()):
        assert len(selected) == options["repeats"], key
        assert {row["repetition"] for row in selected} == set(range(options["repeats"])), "missing or duplicated repetition"
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
              "scope": ("Native build_tracing text, five numeric event fields, UTC time/file/line/thread metadata. This is a separate control, not the common JSON comparison." if options["metadata"] == "native_tracing" else "Full JSON fields and system-clock capture, with all file records independently verified.") + " Written flush, final close and initialization are separate metrics; no durable media synchronization.",
              "noise_limit": .10}
    if options["metadata"] == "full":
        report["foundation_qualification"] = foundation_comparisons(grouped)
    return report


def markdown(report):
    def name(group):
        return group["library"] + " " + group["configuration"]
    batch = {(name(group), group["producers"]): group for group in report["groups"] if group["phase"] == "batch"}
    sampled = {(name(group), group["producers"]): group for group in report["groups"] if group["phase"] == "sampled"}
    lines = ["# 完整日志流程实测", "", f"共 {report['trials']} 个试验，逐条核对 {report['all_records_verified']:,} 条完整日志。固定 CPU affinity：{report['affinity']}。", "",
             f"下表均为{report['configuration']['repeats']}次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。", "",
             "| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |",
             "| --- | ---: | ---: | ---: | ---: | --- |"]
    names = sorted({item[0] for item in batch})
    for label in names:
        one, four = batch.get((label, 1)), batch.get((label, 4))
        values = [f"{group['metrics'][metric]['median'] / 1e6:.3f}" if group else "—" for metric in ("written_flush_records_per_sec", "written_close_records_per_sec") for group in (one, four)]
        lines.append(f"| {label} | {values[0]} | {values[1]} | {values[2]} | {values[3]} | {'有' if (one or four)['process_crash_recovery'] else '无'} |")
    lines += ["", "| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for label in names:
        one, four = sampled.get((label, 1)), sampled.get((label, 4))
        quantiles = [f"{group['metrics']['p50_ns']['median']:,.0f} / {group['metrics']['p99_ns']['median']:,.0f}" if group else "—" for group in (one, four)]
        init = [f"{batch[(label, p)]['metrics']['init_ns']['median'] / 1e6:.3f}" if (label, p) in batch else "—" for p in (1, 4)]
        lines.append(f"| {label} | {quantiles[0]} | {quantiles[1]} | {init[0]} | {init[1]} |")
    lines += ["", "| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for label in names:
        values = [f"{batch[(label, p)]['metrics'][metric]['median'] / 1e6:.3f}" if (label, p) in batch else "—" for metric in ("lifecycle_ns", "shutdown_ns") for p in (1, 4)]
        size = f"{batch[(label, 4)]['metrics']['bytes_per_event']['median']:.2f}" if (label, 4) in batch else "—"
        lines.append(f"| {label} | {values[0]} | {values[1]} | {values[2]} | {values[3]} | {size} |")
    lines += ["", "各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。", ""]
    if "foundation_qualification" in report:
        qualification = report["foundation_qualification"]
        lines += ["Foundation 配对资格：`" + qualification["written_close_assessment"] + "`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。", "",
                  "| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |",
                  "| --- | --- | ---: | --- | ---: | --- | --- |"]
        for item in qualification["comparisons"]:
            metric = item["metrics"]["written_records_per_sec"]
            ratio = metric.get("paired_speed_ratio", float("nan"))
            interval = metric.get("paired_ratio_ci95", [float("nan"), float("nan")])
            lines.append(f"| {item['kron_configuration']} | {item['peer']} | {item['producers']} | {item['phase']} | {ratio:.3f} | {interval[0]:.3f}..{interval[1]:.3f} | {metric['assessment']} |")
        lines.append("")
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
