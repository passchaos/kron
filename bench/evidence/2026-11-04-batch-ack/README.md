# 批量消费者确认路径

## 变更

生产默认路径把每个 `.written` 记录的 journal reclaim 和 snapshot pin 释放改成连续批次操作，持久化边界、slot CRC、late-damage 前缀和 recovery 语义不变。

- `Journal.releaseBatchWritten(records, released)`：接受来自 `peekBatchChecked` 的连续 run。逐条重查 identity 与 slot checksum（不重做 schema 解析），成功后一次发布 written 游标、一次更新 occupancy、一次发布 SPSC free position，再按顺序释放每个 slot turn。若中间记录损坏，只释放成功前缀并通过 `released` 返回其长度，然后报错。
- `Snapshot.releaseChannelCount(channel, count)`：同一 `(snapshot, channel)` 的 pin 用一个 `fetchSub(count)` 释放。
- `Runtime.drainJournal`：把连续的 `.written` 记录合并为一个 run；`.durable` 记录仍逐条 `releaseAfter`，并按顺序切开 run。

## 正确性

- 新增 journal 测试：批量顺序确认、乱序拒绝、中间 slot 损坏只确认前缀、peek 后 payload 损坏只确认前缀。
- 既有 late-corruption runtime 测试保持原预期：`coalesced late corruption` 确认 190 条并保留 65 条；`batched written counts` 确认 1 条并保留 2 条。
- `zig build test -Doptimize=ReleaseSafe -j1`：65/65 steps、758/759 tests（1 项 local skip），success。
- `zig build verify-local -Doptimize=ReleaseSafe -j1`：159/159 steps、792/793 tests（1 项 local skip），`verify-local success`。

## E-core A/B

同一 E-core affinity `16,18,20,22,24,26`，baseline 为冻结的生产 binary `68c06b8...`，candidate 为 `1778caa...`。16 个配置（async/spsc × memory/mmap × P1/P4 × inline/schema）各 5 轮，每轮 baseline/candidate 交替，逐条核验 16,160,000 条完整 JSON。

| case | written assessment | ratio | 95% CI | candidate M/s | baseline M/s |
| --- | --- | ---: | --- | ---: | ---: |
| async-memory-inline-p1 | kron_leads | 1.0418 | 1.0219..1.0729 | 1.949 | 1.851 |
| async-memory-schema-p1 | kron_leads | 1.0697 | 1.0565..1.0796 | 2.027 | 1.896 |
| async-memory-inline-p4 | kron_leads | 1.0464 | 1.0141..1.0987 | 1.830 | 1.734 |
| async-memory-schema-p4 | kron_leads | 1.0748 | 1.0527..1.0960 | 1.933 | 1.792 |
| async-mmap-inline-p1 | kron_leads | 1.0338 | 1.0212..1.0433 | 1.898 | 1.837 |
| async-mmap-schema-p1 | kron_leads | 1.0682 | 1.0448..1.0964 | 2.000 | 1.867 |
| async-mmap-inline-p4 | inconclusive | 1.0413 | 1.0172..1.3450 | 1.801 | 1.730 |
| async-mmap-schema-p4 | kron_leads | 1.0827 | 1.0481..1.1043 | 1.967 | 1.783 |
| spsc-memory-inline-p1 | inconclusive | 1.0487 | 0.9904..1.0644 | 1.968 | 1.888 |
| spsc-memory-schema-p1 | kron_leads | 1.1074 | 1.0531..1.1287 | 2.034 | 1.866 |
| spsc-memory-inline-p4 | kron_leads | 1.0338 | 1.0144..1.0661 | 1.980 | 1.926 |
| spsc-memory-schema-p4 | kron_leads | 1.0325 | 1.0240..1.0729 | 2.077 | 2.000 |
| spsc-mmap-inline-p1 | kron_leads | 1.0474 | 1.0113..1.0610 | 1.943 | 1.871 |
| spsc-mmap-schema-p1 | kron_leads | 1.0937 | 1.0817..1.1218 | 2.017 | 1.841 |
| spsc-mmap-inline-p4 | inconclusive | 1.0156 | 0.9922..1.0447 | 1.995 | 1.964 |
| spsc-mmap-schema-p4 | inconclusive | 1.0601 | 1.0110..1.2153 | 2.087 | 1.974 |

`written_records_per_sec`：**12 candidate lead、0 baseline lead、4 inconclusive**。中位比值范围 1.0156..1.1074；4 个 inconclusive 均为 P4，原因是 paired spread/区间未通过，不是稳定回退。`lifecycle_records_per_sec` 与 written 同向，`init_ns`/`shutdown_ns` 在 mmap 下仍受生命周期波动影响，保持 inconclusive。

## 决策

保留。该候选没有 qualified negative axis，且 batch 确认路径在 12/16 配置取得稳定领先。它只改变 consumer 确认/回收的批处理方式，不改变默认 CRC、三检查点、队列预算、durable 语义或恢复契约。

## 边界

这不是 Foundation 跨库矩阵；candidate 仍在 1.8M–2.1M records/s，低于 Foundation 的 2.4M–3.2M。A/B 绑定当前 E-core 安静窗口（host load 约 126，E-core 约 95% idle），不构成普适排名。原始 row 见 [results.jsonl](results.jsonl)，汇总见 [summary.json](summary.json)，源码见 [candidate.patch](candidate.patch)，binary 身份见 [binaries.sha256](binaries.sha256)，窗口负载见 [host-load.txt](host-load.txt)。整体“业界最佳”目标仍未完成。
