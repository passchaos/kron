# Rejected: cross-journal prefetch

## 候选

SPSC P4 profile 显示 consumer `drainJournal` self 29%，其中约 26% 样本落在 `peekChecked` 返回后的 batch-length 载入，属于 journal handoff 延迟。候选在 `Journal` 增加 `prefetchNext()`：对下一个已提交 slot（`head < tail`）预取首个 cache line；`drainAvailable` 在开始 drain 前对所有 SPSC channel 各预取一次，让其余 channel 的 slot fetch 与第一个 channel 的处理重叠。未提交 slot 跳过，避免拉取 producer 正在写的 cache line。

## 结果（E-core，500k events，5 轮）

before = `reference-kron-fixedout2`（sha256 `d1e6da7d...`），after = `reference-kron-prefetch2`（sha256 `be77aa0f...`）。

| case | after | before | ratio 中位 | 95% CI | 资格 |
| --- | ---: | ---: | ---: | --- | --- |
| spsc-memory-schema P4 | 2.572M | 2.575M | 0.9960 | 0.8774..1.0057 | inconclusive（kron spread 15.4%） |
| spsc-mmap-schema P4 | 2.566M | 2.603M | **0.9868** | 0.9630..1.0039 | inconclusive（spread 2.6%–6.7%，中位 −1.3%） |
| async-memory-schema P4 | 2.991M | 3.002M | **0.9894** | 0.9859..1.0047 | inconclusive（spread 1.9%–3.3%，中位 −1.1%） |
| async-mmap-schema P4 | 2.992M | 2.974M | 1.0060 | 0.9554..1.0311 | inconclusive（spread 4.9%–8.2%） |

没有 qualified lead。稳定窗口的 SPSC mmap 为 −1.3%，async memory 为 −1.1%；async memory 路径不执行该 prefetch，因此至少一部分是二进制布局差异，SPSC mmap 还可能有 prefetch 引起的 cache 污染/line ping-pong。

## 决定

候选撤回，`src/journal/journal.zig` 与 `src/core/runtime.zig` 恢复 `16c6801`。此前 per-record payload prefetch 也已被否决；prefetch 方向关闭。

## 原始数据

- [results.jsonl](results.jsonl)：4 配置 × 5 轮 × 2 binary（40 次，2,004 万条完整 JSON）。
- [manifest.json](manifest.json)：host/load、binary sha256、A/B 参数与核验计数。
