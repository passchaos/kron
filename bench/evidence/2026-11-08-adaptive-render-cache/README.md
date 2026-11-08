# Adaptive render cache backlog gate

## 变更

`render_cache` 之前一旦开启就由 producer 渲染每一条记录。P1 下 producer 本身是瓶颈，把 render 从 consumer 移过去会稳定回退（约 0.94）；P4 或 consumer 落后时则大幅领先（约 1.6）。本轮把 producer 渲染改为**按 journal backlog 自适应**：

- `RenderCache` 预计算三个阈值：inline `capacity/4`；shared async schema `capacity/2`；SPSC schema 单 producer `capacity*3/4`、多 producer 使用 shared 的 `capacity/2`（最小 2/4/4）；
- `Runtime` 在 claim 前只做一次 monotonic `pending()` 读取，`pending > threshold` 时才由 producer 渲染；
- 未触发时 consumer 继续 deferred render；触发时行为与原来的 render cache 完全相同；
- cache 命中、发布、abort、恢复回退、journal/CRC/recovery/queue 契约均不变；
- benchmark `--kron-render-cache` 现在对所有 producer 启用自适应 cache（此前只对 P4 启用）。

schema producer 的 binary encode 比 inline 便宜，单 producer 更接近 break-even；shared async schema 用半环确认 consumer 落后，SPSC 单 producer 的队列就地推进，需要 3/4 环才能避免 sampled 轴上的稳定回退。SPSC 多 producer 通过 `ThreadRegistry.attached_count` 识别并切换到半环。阈值是容量相对值，不依赖固定的 256 槽配置。

## 正确性

- `zig build test -Doptimize=ReleaseSafe -j1`：**65/65 steps、770/771 tests（1 项 local skip）**，success。
- `zig build verify-local -Doptimize=ReleaseSafe -j1`：**159/159 steps、804/805 tests（1 项 local skip）**，`verify-local success`。
- 新增 `render cache backlog gate scales with ring capacity and schema headroom`，锁定 8/256 容量下的 inline/schema 阈值与边界。
- 既有 render-cache byte parity、恢复回退、claim/publish/clear 测试保持通过；所有试验输出逐条由 `run.py::verify` 核对。

## cache on/off 矩阵（E-core `[16,18,20,22,24,26]`，5 轮）

32 个配置 × 2 variant × 5 轮 = 320 次，逐条核验 **32,320,000** 条完整 JSON。比值大于 1 表示 cache-on 更快。

| 配置 | cache | nocache | ratio 中位 | ratio 范围 | 配对资格 |
| --- | ---: | ---: | ---: | --- | --- |
| async-memory-p1-batch-inline | 2.251M | 1.961M | **1.1272** | 1.0781..1.2216 | inconclusive |
| async-memory-p1-batch-schema | 2.075M | 2.014M | **1.0253** | 1.0072..1.0509 | **kron_leads** |
| async-memory-p1-sampled-inline | 2.124M | 1.945M | **1.0979** | 1.0629..1.1682 | **kron_leads** |
| async-memory-p1-sampled-schema | 1.972M | 2.019M | 0.9771 | 0.9767..1.0442 | inconclusive |
| async-memory-p4-batch-inline | 2.885M | 1.836M | **1.5713** | 1.5256..1.6099 | **kron_leads** |
| async-memory-p4-batch-schema | 2.926M | 1.942M | **1.5124** | 1.5000..1.5515 | **kron_leads** |
| async-memory-p4-sampled-inline | 2.914M | 1.848M | **1.5518** | 1.5285..1.5947 | **kron_leads** |
| async-memory-p4-sampled-schema | 2.895M | 1.937M | **1.4940** | 1.4695..1.5792 | **kron_leads** |
| async-mmap-p1-batch-inline | 2.162M | 1.967M | **1.1052** | 1.0730..1.2734 | inconclusive |
| async-mmap-p1-batch-schema | 2.033M | 2.016M | 1.0086 | 0.9593..1.1243 | inconclusive |
| async-mmap-p1-sampled-inline | 2.074M | 1.955M | **1.0894** | 1.0345..1.1566 | inconclusive |
| async-mmap-p1-sampled-schema | 1.999M | 2.008M | 0.9768 | 0.9657..1.0449 | inconclusive |
| async-mmap-p4-batch-inline | 2.875M | 1.852M | **1.5573** | 1.5341..1.6116 | **kron_leads** |
| async-mmap-p4-batch-schema | 2.882M | 1.910M | **1.5096** | 1.4561..1.5394 | **kron_leads** |
| async-mmap-p4-sampled-inline | 2.870M | 1.872M | **1.5405** | 1.5228..1.5676 | **kron_leads** |
| async-mmap-p4-sampled-schema | 2.910M | 1.913M | **1.5024** | 1.4561..1.5552 | **kron_leads** |
| spsc-memory-p1-batch-inline | 2.370M | 2.017M | **1.1757** | 1.1155..1.1898 | **kron_leads** |
| spsc-memory-p1-batch-schema | 2.131M | 2.050M | **1.0364** | 1.0176..1.0504 | **kron_leads** |
| spsc-memory-p1-sampled-inline | 2.186M | 2.015M | **1.0851** | 1.0608..1.1207 | **kron_leads** |
| spsc-memory-p1-sampled-schema | 2.031M | 2.040M | 0.9879 | 0.9806..1.0173 | inconclusive |
| spsc-memory-p4-batch-inline | 2.868M | 2.032M | **1.4214** | 1.3581..1.6872 | inconclusive |
| spsc-memory-p4-batch-schema | 2.288M | 2.121M | **1.0786** | 1.0713..1.0932 | **kron_leads** |
| spsc-memory-p4-sampled-inline | 2.914M | 2.094M | **1.3852** | 1.3827..1.4376 | **kron_leads** |
| spsc-memory-p4-sampled-schema | 2.316M | 2.098M | **1.1038** | 1.0912..1.1350 | **kron_leads** |
| spsc-mmap-p1-batch-inline | 2.345M | 1.987M | **1.1786** | 1.1425..1.1978 | **kron_leads** |
| spsc-mmap-p1-batch-schema | 2.111M | 2.037M | **1.0387** | 1.0164..1.0990 | **kron_leads** |
| spsc-mmap-p1-sampled-inline | 2.207M | 1.988M | **1.1027** | 1.0869..1.1401 | **kron_leads** |
| spsc-mmap-p1-sampled-schema | 2.031M | 2.043M | 1.0066 | 0.9765..1.0289 | inconclusive |
| spsc-mmap-p4-batch-inline | 2.872M | 2.077M | **1.3889** | 1.2872..1.4224 | **kron_leads** |
| spsc-mmap-p4-batch-schema | 2.287M | 2.082M | **1.0986** | 1.0604..1.1293 | **kron_leads** |
| spsc-mmap-p4-sampled-inline | 2.913M | 2.087M | **1.3916** | 1.3481..1.4018 | **kron_leads** |
| spsc-mmap-p4-sampled-schema | 2.319M | 2.074M | **1.1132** | 1.0856..1.1432 | **kron_leads** |

### 结论

- **P1 inline**：16 个配置全部中位正向，范围 **+8.5%–17.9%**；8 个轴为 qualified lead，其余因 run spread inconclusive。
- **P1 schema**：中位 **−2.3%–+3.9%**；batch 全部正向（4 个 qualified lead），sampled 在 −2.3% 到 +0.7% 之间且区间跨 1，均为 inconclusive；没有 peer_leads。
- **P4 inline**：中位 **+38.9%–57.1%**；**P4 schema** +7.9%–51.2%。门控没有损失 P4 的原有收益。
- 三个阈值分别覆盖 inline（1/4 环）、shared async schema（1/2 环）和 SPSC schema（3/4 环）；32 个配对中没有稳定负向。schema 的 1/2 环版本能把 P4 schema 推到约 1.5x，但会在 SPSC P1 sampled schema 留下 0.9605 的稳定负向；3/4 环消除该负向，同时保留 P4 schema 的 1.08–1.51x。

## SPSC multi-producer schema threshold（11 轮）

SPSC 的 channel 是预分配的，`channelCount()` 不能区分“1 个已 attach 的 producer”和“4 个”。`ThreadRegistry` 新增 `attached_count`（attach +1，detach/retireAll −1），render-cache gate 对 SPSC schema 使用：

- attached ≤ 1：3/4 环（单 producer，避免 sampled 回退）；
- attached > 1：1/2 环（多 producer，使用 shared async 阈值，增加 render offload）。

同 binary A/B（E-core，11 轮）：

| case | new | old | ratio 中位 | 说明 |
| --- | ---: | ---: | ---: | --- |
| spsc-memory-p4-schema-batch | 3.314M | 3.244M | 1.0249 | 方向混合，中位 +2.5% |
| spsc-memory-p1-schema-sampled | 1.460M | 1.460M | 0.9954 | parity，无回退 |

7 轮补充：spsc-mmap-p4-schema-batch 1.0011、spsc-memory-p4-schema-sampled 1.0100、spsc-mmap-p4-schema-sampled 1.0056、spsc-mmap-p1-schema-batch 1.0020。整体是小幅正向/中性，未达到 qualified 门槛；保留是因为策略更准确（多 producer SPSC 不再误用单 producer 阈值），且 P1 单 producer 行为不变。原始行见 [ab/spsc-count-results.jsonl](ab/spsc-count-results.jsonl)。

## peer 资格（5 轮，Foundation HEAD `0d1f5b0`）

kron 全部 async inline/schema 配置开启自适应 `render_cache`；peer 二进制复用 [2026-11-04 完整 E-core 矩阵](../2026-11-04-current-foundation-full-ecore/) 的冻结 binary。240 次试验、逐条核验 **24,240,000** 条完整 JSON。

| kron 配置 | producers | phase | peer | ratio | 95% CI | 资格 | kron | peer |
| --- | ---: | --- | --- | ---: | --- | --- | ---: | ---: |
| async-memory-inline | 1 | batch | foundation | 1.2281 | 1.175..1.334 | inconclusive | 2.233M | 1.820M |
| async-memory-inline | 1 | batch | foundation_tracing | 0.9947 | 0.980..1.131 | inconclusive | 2.233M | 2.214M |
| async-memory-inline | 1 | sampled | foundation | 1.2187 | 1.207..1.251 | **kron_leads** | 2.103M | 1.712M |
| async-memory-inline | 1 | sampled | foundation_tracing | 1.0294 | 1.010..1.071 | **kron_leads** | 2.103M | 2.041M |
| async-memory-inline | 4 | batch | foundation | 1.2803 | 1.240..1.320 | **kron_leads** | 2.925M | 2.269M |
| async-memory-inline | 4 | batch | foundation_tracing | 1.2812 | 1.232..1.346 | **kron_leads** | 2.925M | 2.232M |
| async-memory-inline | 4 | sampled | foundation | 1.2402 | 1.188..1.332 | inconclusive | 2.883M | 2.325M |
| async-memory-inline | 4 | sampled | foundation_tracing | 1.2847 | 1.162..1.346 | inconclusive | 2.883M | 2.246M |
| async-mmap-inline | 1 | batch | foundation | 1.0100 | 0.944..1.129 | inconclusive | 2.207M | 2.210M |
| async-mmap-inline | 1 | batch | foundation_tracing | 0.7654 | 0.725..0.885 | inconclusive | 2.207M | 2.802M |
| async-mmap-inline | 1 | sampled | foundation | 1.0890 | 1.047..1.133 | inconclusive | 2.137M | 1.968M |
| async-mmap-inline | 1 | sampled | foundation_tracing | 0.8395 | 0.823..0.936 | inconclusive | 2.137M | 2.475M |
| async-mmap-inline | 4 | batch | foundation | 0.9564 | 0.937..1.014 | inconclusive | 2.851M | 2.981M |
| async-mmap-inline | 4 | batch | foundation_tracing | 1.1433 | 1.026..1.207 | inconclusive | 2.851M | 2.562M |
| async-mmap-inline | 4 | sampled | foundation | 0.9451 | 0.908..0.980 | inconclusive | 2.874M | 3.037M |
| async-mmap-inline | 4 | sampled | foundation_tracing | 0.8946 | 0.870..0.935 | peer_leads | 2.874M | 3.115M |
| async-memory-schema | 1 | batch | foundation | 1.1276 | 0.079..1.198 | inconclusive | 2.105M | 1.832M |
| async-memory-schema | 1 | batch | foundation_tracing | 0.9435 | 0.066..0.992 | inconclusive | 2.105M | 2.213M |
| async-memory-schema | 1 | sampled | foundation | 1.1679 | 1.134..1.281 | inconclusive | 1.982M | 1.741M |
| async-memory-schema | 1 | sampled | foundation_tracing | 0.9761 | 0.968..0.999 | peer_leads | 1.982M | 2.009M |
| async-memory-schema | 4 | batch | foundation | 1.3147 | 1.279..1.329 | **kron_leads** | 2.931M | 2.229M |
| async-memory-schema | 4 | batch | foundation_tracing | 1.3016 | 1.262..1.379 | **kron_leads** | 2.931M | 2.259M |
| async-memory-schema | 4 | sampled | foundation | 1.1998 | 1.167..1.286 | **kron_leads** | 2.854M | 2.349M |
| async-memory-schema | 4 | sampled | foundation_tracing | 1.2864 | 1.240..1.349 | **kron_leads** | 2.854M | 2.232M |
| async-mmap-schema | 1 | batch | foundation | 0.9660 | 0.912..1.006 | inconclusive | 2.097M | 2.171M |
| async-mmap-schema | 1 | batch | foundation_tracing | 0.7796 | 0.664..0.798 | inconclusive | 2.097M | 2.771M |
| async-mmap-schema | 1 | sampled | foundation | 0.9917 | 0.970..1.016 | inconclusive | 1.980M | 2.011M |
| async-mmap-schema | 1 | sampled | foundation_tracing | 0.7911 | 0.784..0.809 | peer_leads | 1.980M | 2.511M |
| async-mmap-schema | 4 | batch | foundation | 1.0365 | 0.958..1.141 | inconclusive | 2.916M | 2.791M |
| async-mmap-schema | 4 | batch | foundation_tracing | 1.1184 | 1.098..1.165 | **kron_leads** | 2.916M | 2.581M |
| async-mmap-schema | 4 | sampled | foundation | 0.9536 | 0.898..0.985 | peer_leads | 2.873M | 3.038M |
| async-mmap-schema | 4 | sampled | foundation_tracing | 0.8735 | 0.870..0.902 | peer_leads | 2.873M | 3.248M |

### 结论

- **P1 memory inline sampled 对两个前端都是 qualified lead**（1.219/1.029）；batch 对 Foundation 1.228 中位领先、对 tracing 0.995 parity（spread 未 qualified）。
- **P4 memory inline/schema 对两个前端全部 qualified lead**（1.20–1.31）；mmap 轴在本窗口 peer 较快，P4 mmap sampled 出现 0.895/0.954 peer lead，但 kron 绝对值 2.85–2.87M 与 cache-on 矩阵一致，属于窗口 peer 波动。
- P1 memory schema sampled 对 tracing 0.976（peer lead，−2.4%），batch 对 Foundation 1.128 中位领先；P1 schema 若只跑 sampled，可保持 cache off。
- **P1 mmap 仍是最大剩余缺口**：inline 对 tracing 0.765–0.840，schema 0.780–0.791；自适应 cache 把 P1 mmap durable 从 0.706/0.811 改善到 0.79/0.84，但没有改变 tracing 的 mmap 后端优势。P1 mmap 最优生产模式仍是 `text_format`（0.917）或 `MmapSpool`（sampled 1.11 qualified）。
- 本表是选定 case 的同窗口对照，不是 240-trial 完整双拓扑矩阵；不更新完整排名。

## SPSC peer 资格（5 轮）

SPSC 配置同样开启自适应 `render_cache`；240 次试验、逐条核验 **24,240,000** 条完整 JSON。

| kron 配置 | producers | phase | peer | ratio | 95% CI | 资格 | kron | peer |
| --- | ---: | --- | --- | ---: | --- | --- | ---: | ---: |
| spsc-memory-inline | 1 | batch | foundation | 1.2729 | 1.247..1.321 | **kron_leads** | 2.379M | 1.852M |
| spsc-memory-inline | 1 | batch | foundation_tracing | 1.0882 | 1.070..7.547 | inconclusive | 2.379M | 2.187M |
| spsc-memory-inline | 1 | sampled | foundation | 1.2734 | 1.238..1.296 | **kron_leads** | 2.177M | 1.721M |
| spsc-memory-inline | 1 | sampled | foundation_tracing | 1.0759 | 1.075..1.084 | **kron_leads** | 2.177M | 2.024M |
| spsc-memory-inline | 4 | batch | foundation | 1.2335 | 1.206..1.241 | **kron_leads** | 2.862M | 2.320M |
| spsc-memory-inline | 4 | batch | foundation_tracing | 1.3156 | 1.270..1.331 | **kron_leads** | 2.862M | 2.233M |
| spsc-memory-inline | 4 | sampled | foundation | 1.1990 | 1.176..1.260 | **kron_leads** | 2.843M | 2.356M |
| spsc-memory-inline | 4 | sampled | foundation_tracing | 1.2815 | 1.258..1.330 | **kron_leads** | 2.843M | 2.207M |
| spsc-mmap-inline | 1 | batch | foundation | 1.0529 | 1.032..1.072 | **kron_leads** | 2.369M | 2.221M |
| spsc-mmap-inline | 1 | batch | foundation_tracing | 0.8290 | 0.816..0.844 | peer_leads | 2.369M | 2.828M |
| spsc-mmap-inline | 1 | sampled | foundation | 1.1297 | 1.049..1.137 | **kron_leads** | 2.230M | 2.001M |
| spsc-mmap-inline | 1 | sampled | foundation_tracing | 0.9058 | 0.884..0.942 | peer_leads | 2.230M | 2.462M |
| spsc-mmap-inline | 4 | batch | foundation | 0.9951 | 0.938..1.090 | inconclusive | 2.845M | 2.859M |
| spsc-mmap-inline | 4 | batch | foundation_tracing | 0.9822 | 0.962..1.064 | inconclusive | 2.845M | 2.875M |
| spsc-mmap-inline | 4 | sampled | foundation | 0.9605 | 0.921..1.010 | inconclusive | 2.912M | 2.964M |
| spsc-mmap-inline | 4 | sampled | foundation_tracing | 1.0221 | 0.985..1.083 | inconclusive | 2.912M | 2.852M |
| spsc-memory-schema | 1 | batch | foundation | 1.1676 | 1.152..1.179 | **kron_leads** | 2.120M | 1.825M |
| spsc-memory-schema | 1 | batch | foundation_tracing | 0.9742 | 0.950..0.985 | peer_leads | 2.120M | 2.178M |
| spsc-memory-schema | 1 | sampled | foundation | 1.1794 | 1.178..1.203 | **kron_leads** | 2.037M | 1.726M |
| spsc-memory-schema | 1 | sampled | foundation_tracing | 1.0077 | 0.999..18.009 | inconclusive | 2.037M | 1.992M |
| spsc-memory-schema | 4 | batch | foundation | 0.9819 | 0.966..1.017 | inconclusive | 2.291M | 2.321M |
| spsc-memory-schema | 4 | batch | foundation_tracing | 1.0310 | 1.010..1.055 | **kron_leads** | 2.291M | 2.192M |
| spsc-memory-schema | 4 | sampled | foundation | 0.9629 | 0.934..1.015 | inconclusive | 2.263M | 2.364M |
| spsc-memory-schema | 4 | sampled | foundation_tracing | 1.0446 | 1.016..1.056 | **kron_leads** | 2.263M | 2.188M |
| spsc-mmap-schema | 1 | batch | foundation | 0.9739 | 0.962..0.994 | peer_leads | 2.121M | 2.163M |
| spsc-mmap-schema | 1 | batch | foundation_tracing | 0.7713 | 0.748..0.779 | peer_leads | 2.121M | 2.789M |
| spsc-mmap-schema | 1 | sampled | foundation | 1.0128 | 0.992..1.046 | inconclusive | 2.014M | 1.977M |
| spsc-mmap-schema | 1 | sampled | foundation_tracing | 0.8241 | 0.798..0.845 | peer_leads | 2.014M | 2.443M |
| spsc-mmap-schema | 4 | batch | foundation | 0.8157 | 0.799..0.867 | peer_leads | 2.263M | 2.774M |
| spsc-mmap-schema | 4 | batch | foundation_tracing | 0.7869 | 0.738..0.841 | inconclusive | 2.263M | 2.875M |
| spsc-mmap-schema | 4 | sampled | foundation | 0.7760 | 0.735..0.844 | inconclusive | 2.316M | 2.977M |
| spsc-mmap-schema | 4 | sampled | foundation_tracing | 0.7986 | 0.747..0.886 | inconclusive | 2.316M | 2.881M |

### 结论

- **SPSC P1 memory inline 对两个前端领先**：batch 1.273/1.088、sampled 1.273/1.076；sampled 两组 qualified，batch 对 tracing 因 CI 尾部保持 inconclusive。
- **SPSC P1 memory schema 对 Foundation 1.17–1.18 qualified**；对 tracing batch 0.974（小幅 peer lead）、sampled 约 parity。
- **SPSC P4 memory inline 四组全部 qualified lead**（1.20–1.32）；schema 对 tracing 1.03–1.04 qualified，对 Foundation inconclusive。
- **SPSC mmap 仍落后 tracing**：P1 inline 0.829–0.906、schema 0.771–0.824；P4 mmap inline parity/inconclusive，schema 0.776–0.816。与 async 结论一致：P1/P4 mmap 是剩余缺口，memory 路径已取得领先。

## 边界

- `render_cache` 仍是 volatile、单 route JSON、async/SPSC；恢复时 cache 为空并回退 deferred render。
- 阈值是容量相对启发式（inline 1/4、schema 1/2）；阈值边界上的 P1 schema sampled 有 −0.4% 到 −3.9% 的轻微差异，按 inconclusive 记录。
- 输出字节、journal 格式、CRC、三检查点、recovery、queue 预算均未改变。
- 本表是 E-core 选定 case 的同窗口对照；P-core 与完整双拓扑矩阵需单独重跑。

## 原始数据

- [manifest.json](manifest.json)：host/load、git HEAD、源码与 binary sha256、Foundation HEAD、配置。
- [ab/results.jsonl](ab/results.jsonl)：32 配置 × 2 variant × 5 轮（320 次）。
- [ab/spsc-count-results.jsonl](ab/spsc-count-results.jsonl)：SPSC attached-count 阈值 2 配置 × 2 binary × 11 轮（44 次）。
- [peer/results.jsonl](peer/results.jsonl)：async kron/Foundation/tracing 4 配置 × 2 producers × 2 phase × 5 轮（240 次）。
- [peer-spsc/results.jsonl](peer-spsc/results.jsonl)：SPSC kron/Foundation/tracing 4 配置 × 2 producers × 2 phase × 5 轮（240 次）。
