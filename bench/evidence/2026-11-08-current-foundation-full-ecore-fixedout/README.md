# Full E-core matrix after fixed-buffer schema encode

## 配置

- kron 36 配置：async/SPSC × Memory/Mmap × P1/P4 × batch/sampled × inline/schema（32 个 durable）+ `MmapSpool` P1/P4 × batch/sampled（4 个非 durable），全部开启 backlog 自适应 `render_cache`。
- peer：Foundation/spdlog 与 Foundation/tracing，复用 2026-11-04 冻结 binary；pinned Foundation HEAD `0d1f5b0`。
- E-core affinity `[16,18,20,22,24,26]`，100k + 1k，5 轮，共 **260 trials**，逐条核验 **26,260,000** 条完整 JSON。
- kron binary = `reference-kron-fixedout2`（HEAD `2b3f123` 源码，sha256 `d1e6da7d...`）。

## 结果

**durable（64 对）**：**24 kron lead、4 peer lead、36 inconclusive**。上一轮最终矩阵为 24/19/21；peer lead 从 19 降到 4，其余转为 inconclusive（本窗口 spread 更严）。

**非 durable multi-producer spool（8 对）**：**3 kron lead、0 peer lead、5 inconclusive**。P1 batch 3.177M、sampled 2.779M；P4 batch 7.952M、sampled 7.468M；对 Foundation/tracing 中位 1.10–2.98x。

### 剩余 4 个 peer lead（全部是 mmap 对 tracing）

| kron 配置 | producers | phase | kron | tracing | ratio | 95% CI |
| --- | ---: | --- | ---: | ---: | ---: | --- |
| async-mmap-inline | 1 | batch | 2.204M | 2.813M | 0.7860 | 0.763..0.791 |
| async-mmap-schema | 1 | batch | 2.311M | 2.813M | 0.8123 | 0.776..0.835 |
| spsc-mmap-schema | 1 | batch | 2.284M | 2.813M | 0.8119 | 0.789..0.821 |
| spsc-mmap-schema | 4 | sampled | 2.614M | 2.876M | 0.9035 | 0.885..0.954 |

P1 mmap batch 对 tracing 仍是 0.79–0.81；P4 SPSC mmap sampled 为 0.9035。其余 mmap 轴为 inconclusive 或 kron lead。

### 关键改善

- P1 memory schema 对 tracing：async batch 1.0506（inconclusive，窗口 spread）、async sampled **1.0778 lead**、SPSC batch 1.0265（inconclusive）、SPSC sampled **1.0917 lead**。
- P1 mmap schema 对 Foundation：async batch 1.0366（inconclusive）、sampled **1.1068 lead**；SPSC batch 1.0004（parity）、sampled **1.0986 lead**。
- P4 async mmap schema 对 tracing：batch **1.0978 lead**、sampled 1.0278（inconclusive）。
- P4 memory inline/schema 对 tracing 多为 1.15–1.47 lead 或 inconclusive；memory 轴整体已领先。
- spool P4 batch **7.952M**、sampled **7.468M**，对 tracing 2.58–2.98x（batch lead、sampled inconclusive）。

## 结论

- durable memory 路径对两个前端已基本完成超越；剩余 peer lead 只剩 **mmap 对 tracing**，且集中在 **P1 mmap batch（0.79–0.81）** 与 **P4 SPSC mmap sampled（0.9035）**。
- tracing 的 mmap 后端比其 memory 后端快约 25%–27%，是 peer 侧 text spool 的优势；kron 的 mmap journal 相对自身 memory 没有回退，差距来自 binary journal/CRC/measure 契约成本，而不是 mmap 存储本身。
- 本窗口 peer lead 数（4）显著低于上一轮（19），但部分轴从 peer lead 转为 inconclusive 而非直接 lead；排名仍绑定本窗口，不替代安静窗口或 P-core 结果。

## 原始数据

- [results.jsonl](results.jsonl)：260 次原始行（36 配置 × 5 轮 × 2 peer，含 spool）。
- [manifest.json](manifest.json)：host/load、binary/source sha256、Foundation HEAD、配置与核验计数。
