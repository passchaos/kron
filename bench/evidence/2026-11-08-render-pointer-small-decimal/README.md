# Render pointer path + small-decimal fast path

## 变更

两项内部优化，不改变公开 API、输出格式、journal/CRC/recovery 契约：

1. **事件不再按值穿过渲染调用链**：`common.encodeDecoded`/`encodeWithTime` 新增 `*Ptr` 入口，runtime、fused wire renderer、render cache 和 `MmapSpool` 直接借用调用方 `Event`。此前 `renderWithTime` 因为要对 by-value 参数取地址作为 attribute context，会把整个 `Event`（约 200B，含 trace/source/optional 字段）复制到栈上。现在渲染器直接读原事件。
2. **小整数十进制直写**：`decimal.writeMagnitude` 对 `u64 < 100` 走 1–2 字节直接写入，跳过 `nativeDigits` 的 digit-count 估计和 `/100` 循环。metadata 中 `channel`、`route_mask`、`config_generation`、`trace_flags` 通常是 0/1，正好命中。

`Event` 仍是借用视图；`*Ptr` 只在同步调用期间有效，调用方在返回前不得修改事件。by-value 公共入口保留，内部热路径改用指针入口。

## 正确性

- `zig build test -Doptimize=ReleaseSafe -j1`：**65/65 steps、769/770 tests（1 项 local skip）**，success。
- `zig build verify-local -Doptimize=ReleaseSafe -j1`：**159/159 steps、803/804 tests（1 项 local skip）**，`verify-local success`。
- 既有 encoder oracle 覆盖 `encodeDecoded`/`encodeWithTime`/fused wire 与 decoded 的 byte parity；`decimal` 的 u16 全量、u64/u128 边界、部分写前缀测试保持通过。
- 所有 A/B 与 peer 试验的每条输出都由 `run.py::verify` 逐条解析核对；本轮共核验 **41,410,000** 条完整 JSON（410 次 × 101,000 条）。

## 直接 A/B（同一 host 窗口，E-core `[16,18,20,22,24,26]`，7 轮）

before = HEAD `25aa203` 生产的 `reference-kron`（sha256 `633abd...`）；after = 本候选（sha256 `5be1b0...`）。比值大于 1 表示 after 更快。

| case | after | before | ratio 中位 | ratio 范围 |
| --- | ---: | ---: | ---: | --- |
| spool-ts64-tv batch | 3.249M | 2.998M | **1.0653** | 1.0581..1.1098 |
| spool-ts64-tv sampled | 2.772M | 2.619M | **1.0609** | 1.0313..1.0866 |
| text-memory P1 batch | 2.521M | 2.290M | **1.0908** | 1.0614..1.1934 |
| text-mmap P1 batch | 2.535M | 2.298M | **1.1029** | 1.0062..1.1670 |
| text-memory P4 batch | 4.025M | 4.133M | 0.9820 | 0.9415..1.0798 |
| text-mmap P4 batch | 4.118M | 4.077M | 1.0268 | 0.9273..1.0454 |
| durable-memory P1 batch | 1.972M | 1.875M | **1.0482** | 1.0226..1.0781 |
| durable-mmap P1 batch | 1.962M | 1.866M | **1.0551** | 1.0217..1.0651 |
| render-cache mmap P4 batch | 3.014M | 2.916M | **1.0247** | 1.0062..1.0410 |
| durable-mmap P4 batch | 1.861M | 1.827M | **1.0455** | 0.9857..1.0847 |

`text-memory P4` 是唯一中位为负的轴（0.9820），但 7 轮方向混合（0.9415..1.0798）、spread 超过 10%，不是稳定回退；同窗口 `perf stat` 的 user instructions 从约 530M 降到约 513M（−3.1%），说明候选没有增加工作量，差异来自 4 producer 已把 CPU 占满时的调度噪声。其余 9 轴 6/7 到 7/7 轮为正。

分步隔离（`perf stat` 三次中位）：仅 pointer 版相对 before 在 text-mmap P1 为 instructions 约 −1.8%、cycles 约 −6.0%，spool instructions 约 −2.0%；随后小整数直写再带来 text-mmap instructions 约 −1.7%、cycles 约 −4.6%。合并后 text-mmap P1 吞吐提升约 10%，spool 约 6%，durable P1 约 5%。

## 同窗口 peer 资格（5 轮，Foundation HEAD `0d1f5b0`）

peer 二进制复用 [2026-11-04 完整 E-core 矩阵](../2026-11-04-current-foundation-full-ecore/) 的冻结 binary；当前 pinned Foundation workspace HEAD 与该 manifest 相同。比值大于 1 表示 kron 更快；至少 5 轮、kron/peer/paired ratio spread 均 ≤10%、95% bootstrap 区间不跨 1 才判 qualified。

| kron 配置 | phase | peer | ratio | 95% CI | 资格 | kron | peer |
| --- | --- | --- | ---: | --- | --- | ---: | ---: |
| async-memory-text P1 | batch | foundation | 1.3861 | 1.353..1.395 | **kron_leads** | 2.522M | 1.819M |
| async-memory-text P1 | batch | foundation_tracing | 1.1399 | 1.127..1.173 | **kron_leads** | 2.522M | 2.197M |
| async-memory-text P1 | sampled | foundation | 1.2853 | 1.252..1.354 | **kron_leads** | 2.199M | 1.711M |
| async-memory-text P1 | sampled | foundation_tracing | 1.1004 | 1.097..1.137 | **kron_leads** | 2.199M | 1.995M |
| async-memory-text P4 | batch | foundation | 1.8257 | 1.800..1.925 | **kron_leads** | 4.089M | 2.207M |
| async-memory-text P4 | batch | foundation_tracing | 1.8962 | 1.779..1.943 | **kron_leads** | 4.089M | 2.163M |
| async-memory-text P4 | sampled | foundation | 1.7940 | 1.750..1.850 | **kron_leads** | 4.033M | 2.255M |
| async-memory-text P4 | sampled | foundation_tracing | 1.7891 | 1.762..1.829 | **kron_leads** | 4.033M | 2.240M |
| async-memory-cache P4 | batch | foundation | 1.3017 | 1.284..1.367 | **kron_leads** | 2.967M | 2.271M |
| async-memory-cache P4 | batch | foundation_tracing | 1.3589 | 1.329..1.391 | **kron_leads** | 2.967M | 2.184M |
| async-memory-cache P4 | sampled | foundation | 1.3686 | 1.342..1.410 | **kron_leads** | 2.980M | 2.171M |
| async-memory-cache P4 | sampled | foundation_tracing | 1.3811 | 1.319..1.412 | **kron_leads** | 2.980M | 2.151M |
| async-memory-durable P1 | batch | foundation | 1.0595 | 1.055..1.156 | **kron_leads** | 1.949M | 1.841M |
| async-memory-durable P1 | batch | foundation_tracing | 0.8996 | 0.886..0.936 | peer_leads | 1.949M | 2.200M |
| async-memory-durable P1 | sampled | foundation | 1.1582 | 1.133..1.170 | **kron_leads** | 1.967M | 1.699M |
| async-memory-durable P1 | sampled | foundation_tracing | 0.9860 | 0.974..1.023 | inconclusive | 1.967M | 1.996M |
| async-mmap-text P1 | batch | foundation | 1.1785 | 1.134..1.210 | **kron_leads** | 2.525M | 2.162M |
| async-mmap-text P1 | batch | foundation_tracing | 0.9174 | 0.902..0.942 | peer_leads | 2.525M | 2.742M |
| async-mmap-text P1 | sampled | foundation | 1.1220 | 1.097..1.208 | inconclusive | 2.211M | 1.950M |
| async-mmap-text P1 | sampled | foundation_tracing | 0.9001 | 0.860..0.933 | inconclusive | 2.211M | 2.505M |
| async-mmap-text P4 | batch | foundation | 1.5054 | 1.350..1.681 | inconclusive | 4.030M | 2.724M |
| async-mmap-text P4 | batch | foundation_tracing | 1.3610 | 1.327..1.518 | inconclusive | 4.030M | 2.887M |
| async-mmap-text P4 | sampled | foundation | 1.3771 | 1.275..1.509 | inconclusive | 4.182M | 2.997M |
| async-mmap-text P4 | sampled | foundation_tracing | 1.4692 | 1.423..1.534 | inconclusive | 4.182M | 2.739M |
| async-mmap-cache P4 | batch | foundation | 0.9915 | 0.893..1.041 | inconclusive | 2.944M | 2.911M |
| async-mmap-cache P4 | batch | foundation_tracing | 1.0597 | 1.037..1.118 | inconclusive | 2.944M | 2.784M |
| async-mmap-cache P4 | sampled | foundation | 0.9877 | 0.911..1.037 | inconclusive | 2.938M | 2.972M |
| async-mmap-cache P4 | sampled | foundation_tracing | 1.0486 | 1.017..1.068 | **kron_leads** | 2.938M | 2.832M |
| async-mmap-durable P1 | batch | foundation | 0.9132 | 0.891..0.925 | peer_leads | 1.940M | 2.112M |
| async-mmap-durable P1 | batch | foundation_tracing | 0.7058 | 0.659..0.732 | inconclusive | 1.940M | 2.752M |
| async-mmap-durable P1 | sampled | foundation | 1.0058 | 0.991..1.023 | inconclusive | 1.969M | 1.957M |
| async-mmap-durable P1 | sampled | foundation_tracing | 0.8110 | 0.772..0.820 | peer_leads | 1.969M | 2.425M |
| spool-mmap-inline P1 | batch | foundation | 1.5174 | 1.416..1.594 | inconclusive | 3.221M | 2.135M |
| spool-mmap-inline P1 | batch | foundation_tracing | 1.1321 | 1.084..1.202 | inconclusive | 3.221M | 2.836M |
| spool-mmap-inline P1 | sampled | foundation | 1.4000 | 1.356..1.426 | **kron_leads** | 2.746M | 1.976M |
| spool-mmap-inline P1 | sampled | foundation_tracing | 1.1103 | 1.101..1.119 | **kron_leads** | 2.746M | 2.487M |

### 结论

- `text_format` P1 memory 对两个前端、batch 与 sampled 全部 **qualified lead**；此前对 tracing 仅 batch 1.038，sampled 为 inconclusive。
- `text_format` P4 memory 对两个前端四组全部 **qualified lead**（1.79–1.90）。
- `render_cache` P4 memory 四组全部 **qualified lead**（1.30–1.38）。
- `MmapSpool` P1 mmap sampled 对两个前端 **qualified lead**（Foundation 1.40、tracing 1.11）；batch 中位 1.52/1.13，因 kron batch spread 9.5%、paired ratio 11.7% 保持 inconclusive。这是本轮 E-core P1 mmap 对 tracing 的 qualified lead。
- durable P1 memory：对 Foundation batch/sampled qualified lead；对 tracing 从之前的 0.877/0.963 peer lead 改善到 batch 0.900 peer lead、sampled 0.986 inconclusive。
- 剩余 peer lead 仍是 `async-mmap-text P1` 对 tracing（batch 0.917）和 `async-mmap-durable P1` 对 tracing/Foundation（0.706/0.811 sampled）。P1 mmap 的 durable/带 journal 路径仍落后 tracing 的 producer-format + spool 后端。

本表是选定 case 的同窗口对照，不是 240-trial 完整双拓扑矩阵；不更新完整跨库排名，也不把 P4 或 sampled 的 lead 外推到其他配置。

## 边界

- 输出字节由同一 `verify` 逐条核对；`encodeDecodedPtr` 仍只在 `tree_validated` 时跳过重复校验，公开 encoder 始终校验。
- `writeSmallNative` 仅在 `T == u64` 且 writer 至少剩 21B 时启用，否则回退原 `writeBuffered`；部分写/短 buffer 前缀行为不变。
- 默认 durable/CRC/三检查点/recovery/queue 预算、journal 格式和 `MmapSpool` 语义均未改变。
- P4 text-memory 的直接 A/B 中位 0.9820 但方向混合、spread 超门槛，按 inconclusive 记录，不作为回退或收益证据。

## 原始数据

- [manifest.json](manifest.json)：host/load、git HEAD、diff hash、源码与 binary sha256、Foundation HEAD、试验配置。
- [ab/results.jsonl](ab/results.jsonl)：before/after 10 个配置 × 7 轮原始行（140 次）。
- [peer/results.jsonl](peer/results.jsonl)：kron/Foundation/tracing 9 个配置 × 2 phase × 5 轮原始行（270 次）。
