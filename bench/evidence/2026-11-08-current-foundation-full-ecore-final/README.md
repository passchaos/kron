# Final E-core matrix: durable + multi-producer spool

## 配置

- kron durable 32 配置：async/SPSC × Memory/Mmap × P1/P4 × batch/sampled × inline/schema，全部开启 backlog 自适应 `render_cache`。
- kron `MmapSpool` 4 配置：P1/P4 × batch/sampled，非 durable、每 producer 一个文件/channel、ts64。
- peer：Foundation/spdlog 与 Foundation/tracing，复用 2026-11-04 冻结 binary；pinned Foundation HEAD `0d1f5b0`。
- E-core affinity `[16,18,20,22,24,26]`，100k+1k，5 轮，共 **260 trials**，逐条核验 **26,260,000** 条完整 JSON。

## 结果

**durable（64 对）**：**24 kron lead、19 peer lead、21 inconclusive**。本窗口 peer mmap 明显更快（Foundation P4 mmap sampled 3.454M、tracing P4 mmap batch 3.283M），mmap 轴的 peer lead 比 2026-11-04 安静窗口（19/9/36）多；memory 轴继续领先：

- async/SPSC P1 memory inline 对两前端中位 1.05–1.31；SPSC P1 memory inline 四组 qualified。
- async/SPSC P4 memory inline/schema 对两前端 1.14–1.39，多组 qualified。
- P1/P4 mmap 对 Foundation 部分领先/parity；对 tracing 仍落后（P1 0.73–0.92，P4 batch 0.89–0.93、sampled 0.99–1.14）。

**非 durable multi-producer spool（8 对）**：**5 kron lead、0 peer lead、3 inconclusive**。

| producers | phase | kron | Foundation mmap | tracing mmap | 对 Foundation | 对 tracing |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | batch | 3.265M | 2.168M | 2.829M | **1.490 qualified** | **1.138 qualified** |
| 1 | sampled | 2.870M | 1.987M | 2.445M | **1.416 qualified** | **1.158 qualified** |
| 4 | batch | **8.565M** | 2.854M | 3.283M | 2.928 inconclusive | 2.624 inconclusive |
| 4 | sampled | **7.568M** | 3.454M | 2.671M | **2.228 qualified** | 2.829 inconclusive |

P4 spool 对两前端 2.2–2.9x；batch 因 spool/peer spread 未 qualified，sampled 对 Foundation qualified。spool 是非 durable、无 journal/CRC/recovery、每 producer 一个文件，不能替代 durable 排名。

## 结论

- 最终状态：durable memory 路径对两个前端领先；durable mmap 仍落后 tracing（P1/P4），但 multi-producer spool 在非 durable 类别以 2.2–2.9x 覆盖 P4 mmap、以 1.14–1.49x 覆盖 P1 mmap。
- 本窗口的 durable peer lead 数（19）高于安静窗口（9），主要来自 peer mmap 的窗口速度和更稳定的配对；memory 轴的 qualified lead 数同时增加。两个窗口都应保留，不把窗口差异归因于代码回退。
- durable mmap 的剩余差距仍是 producer 侧 admission/filter/journal 生命周期开销；连续微候选已被否决，下一步需要更大范围重设计（checkpoint-durable spool 或 Logging spool target）。

## 原始数据

- [comparison.md](comparison.md)：中位表与 72 个配对行。
- [results.jsonl](results.jsonl)：260 次原始行。
- [manifest.json](manifest.json)：host/load、binary/source sha256、Foundation HEAD、配置与核对计数。
