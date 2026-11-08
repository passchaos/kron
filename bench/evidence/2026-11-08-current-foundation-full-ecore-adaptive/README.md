# Full E-core matrix with adaptive render_cache

## 配置

- kron 全部 32 个配置开启 backlog 自适应 `render_cache`（async/SPSC × Memory/Mmap × P1/P4 × batch/sampled × inline/schema）。
- peer 二进制复用 [2026-11-04 完整 E-core 矩阵](../2026-11-04-current-foundation-full-ecore/) 的冻结 binary；当前 pinned Foundation workspace HEAD `0d1f5b0` 与该 manifest 一致。
- E-core affinity `[16,18,20,22,24,26]`，100k+1k，5 轮，共 **240 trials**，逐条核验 **24,240,000** 条完整 JSON。
- 本轮是 adaptive cache 之后的当前排名；kron 配置与 2026-11-04 的 cache-off 矩阵不同，不能直接当作同一配置的前后对比。

## 结果

| 指标 | 本轮 | 2026-11-04 安静窗口（cache-off/P4-only） |
| --- | ---: | ---: |
| kron lead | **19** | 11 |
| peer lead | **9** | 13 |
| inconclusive | 36 | 40 |

剩余 9 个 peer lead 集中在：

- **P1 mmap 对 tracing**：async inline sampled 0.863、async schema sampled 0.833、SPSC inline sampled 0.904、SPSC schema sampled 0.849；batch 中位也低于 tracing 但多为 inconclusive。
- **P4 mmap sampled 对 Foundation**：async inline 0.837、SPSC inline 0.852、SPSC schema 0.676；Foundation 的 P4 mmap sampled 中位 3.407M 是本窗口最高。
- **P1 memory schema batch 对 tracing**：async 0.952、SPSC 0.973（小幅 peer lead）；sampled 已到 parity。

kron 的主要领先：

- P1 memory inline：async sampled 对两前端 1.213/1.042、SPSC batch/sampled 对两前端 1.26–1.35，均 qualified。
- P4 memory inline/schema：对 Foundation 1.29–1.33、对 tracing 1.28–1.38，多组 qualified。
- P1/P4 mmap 对 Foundation：P1 sampled 1.044–1.098、P4 batch/schema 中位 1.00–1.02（部分 inconclusive）。

完整中位与 64 个配对行见 [comparison.md](comparison.md)，原始行见 [results.jsonl](results.jsonl)。

## 结论

- adaptive cache 把 P1 memory 从落后 tracing 推到 parity/领先，并把整体 kron lead 从 11 提升到 19、peer lead 从 13 降到 9。
- 剩余差距几乎全部在 **mmap**：P1 mmap 对 tracing、P4 mmap sampled 对 Foundation。memory 路径已基本完成超越。
- 该窗口 Foundation P4 mmap sampled（3.407M）明显高于其历史中位，kron P4 mmap 绝对值 2.89–2.93M 与 cache-on 矩阵一致；仍按本窗口记录为 peer lead，不外推。

## 边界

- 本矩阵只覆盖 E-core 选定 affinity 和 5 轮；P-core、其他 host load、完整生命周期/尾部指标需单独重跑。
- 所有输出逐条由 `run.py::verify` 核对；accepted/written/drop/pending 一致。
- adaptive cache 是 opt-in；本矩阵为便于比较对所有 kron 配置开启。默认 durable/CRC/recovery/queue 与输出字节不变。
- 该结果不把 P4 或 sampled 的 lead 外推到其他配置，也不替代完整跨平台/跨文件系统证据。

## 原始数据

- [manifest.json](manifest.json)：host/load、git HEAD、binary sha256、Foundation HEAD、配置与核对计数。
- [comparison.md](comparison.md)：中位表、64 个配对资格与剩余 peer lead。
- [results.jsonl](results.jsonl)：240 次原始行。
