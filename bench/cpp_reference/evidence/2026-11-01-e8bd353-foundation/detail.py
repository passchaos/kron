#!/usr/bin/env python3
"""Detailed same-round comparisons with complete-workflow noise assessment."""
import collections
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def main():
    spec = importlib.util.spec_from_file_location("regression", ROOT / "bench/regression.py")
    regression = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(regression)
    rows = [json.loads(line) for line in (HERE / "results.jsonl").read_text().splitlines()]
    assert len(rows) == 200 and all(row["status"] == "ok" for row in rows)
    grouped = collections.defaultdict(list)
    for row in rows:
        assert row["events"] == row["accepted"] == row["written"] == 100000
        assert row["drop"] == row["final_pending"] == 0 and row["file_records_verified"] == 101000
        assert row["metadata"] == "full" and row["file_buffer_bytes"] == 65536
        assert row["queue_slots"] == 256 and row["has_process_crash_recovery"] == (row["storage"] == "mmap")
        if row["library"] == "kron":
            assert row["backend_selected"] == row["backend_requested"] == "portable"
            assert row["consumer_batches_per_queue"] == 4 and row["max_record_bytes"] == 512
        assert row["total_ns"] == sum(row[name] for name in ("producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns"))
        assert row["lifecycle_ns"] == row["total_ns"] + row["init_ns"] + row["preparation_ns"]
        row["written_flush_records_per_sec"] = 100000 * 1e9 / (row["producer_wall_ns"] + row["flush_ns"])
        grouped[row["library"], row["case"], row["producers"], row["phase"]].append(row)
    groups = []
    index = {}
    for key, selected in sorted(grouped.items()):
        assert len(selected) == 5
        assert sorted(row["repetition"] for row in selected) == list(range(5))
        metrics = ["written_records_per_sec", "written_flush_records_per_sec", "lifecycle_records_per_sec",
                   "producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns", "init_ns", "preparation_ns",
                   "total_ns", "lifecycle_ns", "written_bytes", "queue_reserved_bytes", "journal_reserved_bytes"]
        metrics = [name for name in metrics if name in selected[0]]
        if key[-1] == "sampled":
            metrics += ["p50_ns", "p99_ns", "p999_ns"]
        summarized = {name: regression.summary([row[name] for row in selected]) for name in metrics}
        for value in summarized.values():
            value["repeatable"] = value["cv"] < .1 and value["relative_spread"] < .1
        group = dict(library=key[0], case=key[1], producers=key[2], phase=key[3], metrics=summarized)
        groups.append(group)
        index[key] = group
    comparisons = []
    for group in groups:
        if group["library"] != "kron":
            continue
        mode, storage, shape = group["case"].split("-")
        baseline = index["foundation", storage, group["producers"], group["phase"]]
        compared = {}
        for name, value in group["metrics"].items():
            if name not in baseline["metrics"]:
                continue
            reference = baseline["metrics"][name]
            ratio = value["median"] / reference["median"] if reference["median"] else None
            left, right = reference["median_bootstrap_ci95"], value["median_bootstrap_ci95"]
            overlap = max(left[0], right[0]) <= min(left[1], right[1])
            stable = reference["repeatable"] and value["repeatable"]
            compared[name] = dict(kron_over_foundation=ratio,
                median_change_percent=(ratio - 1) * 100 if ratio is not None else None,
                both_repeatable=stable, bootstrap_intervals_overlap=overlap,
                status="local_difference_supported" if stable and not overlap else "inconclusive")
        comparisons.append(dict(case=group["case"], mode=mode, storage=storage, shape=shape,
                                producers=group["producers"], phase=group["phase"], metrics=compared))
    result = dict(trials=200, physical_records_verified=20200000, pairs=5,
                  source_commit="e8bd353", groups=groups, comparisons=comparisons, noise_limit=.1,
                  scope="Same-round complete JSON/system clocks; written flush/close and init/preparation separate; no media durability")
    (HERE / "detailed-analysis.json").write_text(json.dumps(result, indent=2) + "\n")
    lines = ["# e8bd353 与 Foundation Logging＋spdlog 完整流程对照", "",
             "200项试验，逐条验证20,200,000条JSON。每项100k测量＋1k预热，五次重复；P1/P4分别表示1/4个producer。", "",
             "吞吐单位M条/s，包含producer、后台格式化/文件写出、最终written flush、shutdown和清理；初始化与预热单列。", ""]
    for shape in ("inline", "schema"):
        lines += [f"## {'普通inline' if shape == 'inline' else '预注册schema'}完整吞吐", "",
                  "| 存储 | producer | Foundation＋spdlog | kron shared | 相对变化 | kron SPSC | 相对变化 |",
                  "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
        for storage in ("memory", "mmap"):
            for producers in (1, 4):
                baseline = index["foundation", storage, producers, "batch"]["metrics"]["written_records_per_sec"]["median"]
                values = [index["kron", f"{mode}-{storage}-{shape}", producers, "batch"]["metrics"]["written_records_per_sec"]["median"] for mode in ("async", "spsc")]
                lines.append(f"|{storage}|{producers}|{baseline/1e6:.3f}|{values[0]/1e6:.3f}|{(values[0]/baseline-1)*100:+.2f}%|{values[1]/1e6:.3f}|{(values[1]/baseline-1)*100:+.2f}%|")
        lines += [""]
    lines += ["## 调用延迟、启动与关闭", "",
              "调用分位数来自独立sampled阶段，单位ns；其测量的是一次调用返回，包括满队列阻塞。它不是event到文件的可见延迟。", "",
              "| 实现/队列 | P | p50 | p99 | p99.9 | init ms | preparation ms | flush µs | shutdown µs | cleanup µs | lifecycle ms |",
              "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for library, case in [("foundation", storage) for storage in ("memory", "mmap")] + [("kron", f"{mode}-{storage}-{shape}") for shape in ("inline", "schema") for mode in ("async", "spsc") for storage in ("memory", "mmap")]:
        for producers in (1, 4):
            batch = index[library, case, producers, "batch"]["metrics"]
            sampled = index[library, case, producers, "sampled"]["metrics"]
            values = [f"{sampled[name]['median']:.0f}" for name in ("p50_ns", "p99_ns", "p999_ns")]
            values += [f"{batch[name]['median']/divisor:.3f}" for name, divisor in [("init_ns",1e6),("preparation_ns",1e6),("flush_ns",1e3),("shutdown_ns",1e3),("cleanup_ns",1e3),("lifecycle_ns",1e6)]]
            lines.append(f"|{library} {case}|{producers}|" + "|".join(values) + "|")
    lines += ["", "## 吞吐资格", "",
              "CV与相对spread两侧均小于10%，且bootstrap中位区间不重叠，才将本机差异标为supported；其余为inconclusive。所有慢值保留。", "",
              "| kron配置 | P | 相对吞吐变化 | Foundation CV/spread | kron CV/spread | 区间重叠 | 结论 |",
              "| --- | ---: | ---: | ---: | ---: | --- | --- |"]
    for comparison in comparisons:
        if comparison["phase"] != "batch":
            continue
        case, producers = comparison["case"], comparison["producers"]
        m = comparison["metrics"]["written_records_per_sec"]
        f = index["foundation", comparison["storage"], producers, "batch"]["metrics"]["written_records_per_sec"]
        k = index["kron", case, producers, "batch"]["metrics"]["written_records_per_sec"]
        lines.append(f"|{case}|{producers}|{m['median_change_percent']:+.2f}%|{f['cv']*100:.2f}%/{f['relative_spread']*100:.2f}%|{k['cv']*100:.2f}%/{k['relative_spread']*100:.2f}%|{'是' if m['bootstrap_intervals_overlap'] else '否'}|{m['status']}|")
    lines += ["", "完整分布、阶段与百分位资格见detailed-analysis.json；初始化/预热/关闭各阶段中位数不能相加重建生命周期中位数。资源预算和语义差异见README.md。", ""]
    (HERE / "detailed-comparison.md").write_text("\n".join(lines))
    print("Complete detailed report:200 trials,20,200,000 physical JSON records")


if __name__ == "__main__":
    main()
