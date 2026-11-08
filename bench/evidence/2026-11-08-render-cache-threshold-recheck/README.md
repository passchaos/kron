# Rejected: render-cache schema threshold 1/4

## 候选

fixed-buffer schema encode 让 producer 变快后，复测 shared async schema 的 render-cache offload 阈值。当前值为 `pending > capacity/2`；候选改为 `pending > capacity/4`，让 producer 更早接管 render（producer 从 live event 渲染，consumer 省掉 decode+render）。

## 结果（E-core，500k events，5 轮，cache on）

before = `reference-kron-fixedout2`（阈值 1/2，sha256 `d1e6da7d...`），after = `reference-kron-cachequarter`（阈值 1/4）。比值大于 1 表示 1/4 更快。

| case | quarter | half | ratio 中位 | 95% CI | 资格 |
| --- | ---: | ---: | ---: | --- | --- |
| async-memory-schema P1 | 1.924M | 2.241M | **0.8629** | 0.7391..0.9011 | inconclusive（一轮 host 干扰，kron spread 21.7%） |
| async-mmap-schema P1 | 1.937M | 2.246M | **0.8747** | 0.8180..0.8918 | **peer_leads**（稳定 −12.5%） |
| async-memory-schema P4 | 3.026M | 2.998M | 1.0250 | 0.9692..1.2015 | inconclusive |
| async-mmap-schema P4 | 3.029M | 3.014M | 1.0057 | 0.9739..1.0162 | inconclusive |

1/4 阈值在 P1 稳定回退约 12%–14%，P4 基本持平或略正。说明即使 producer encode 已变快，单个 async producer 仍不能吸收全部 render；过早 offload 会把 render 放到 producer 关键路径上。当前 1/2 阈值在 P1 上仍是更优点。

同窗口补充（`--render-cache=false` vs `true`，2 配置 × 5 轮）：P1 async memory/mmap schema 的 cache-on/off 为 **1.1056/1.1171 qualified lead**，即自适应 offload 本身仍带来约 10%–12% 的收益。

## 决定

保持 `schema_offload_threshold = capacity/2`，生产无改动。证据见本目录。

## 原始数据

- [results.jsonl](results.jsonl)：4 配置 × 5 轮 × 2 binary（40 次，2,004 万条完整 JSON）。
- [cache-onoff/results.jsonl](cache-onoff/results.jsonl)：P1 memory/mmap cache on/off 2 配置 × 5 轮 × 2（20 次，1,002 万条完整 JSON）。
- [manifest.json](manifest.json)：host/load、binary sha256、A/B 参数与核验计数。
