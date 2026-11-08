# Fixed-buffer schema payload encoding

## 变更

`reference_encoding.writeMeasured` 之前用 `std.Io.Writer.fixed` + `wire.StreamOutput` 写 schema payload。`wire.StreamOutput.writer` 是动态 `std.Io.Writer` 接口，header 的每个整数、每个字段 tag/value 都经过一次 vtable 调用和 out-of-line `memcpy`。inline payload 早已使用具体的 `codec.Output`（固定 buffer + cursor），schema 是唯一残留的动态 writer 热路径。

本候选新增 `wire.FixedOutput`：固定 buffer + cursor，`int` 直接 `std.mem.writeInt` 写入目标位置，`put` 对 blob 做带边界检查的 `@memcpy`；`codec.writeHeaderTo` 改为模块内 `pub`；`writeMeasured` 改用 FixedOutput 写 header、trace/span、message 和全部 values。`sizeMeasured` 仍先校验 shape/level 并计算精确总长，Debug 构建用 `output.index == size` 断言最终长度。

不改变 payload 字节、公开 API、journal/CRC/recovery 契约或错误语义：buffer 不足仍返回 `BufferTooSmall`（原 `WriteFailed` 映射保持不变）。

## 正确性

- 过滤测试：schema **72/72**、reference **35/35**、wire **34/34**、codec **53/53**。
- 完整 root test suite（ReleaseSafe）：**484 passed、1 skipped、0 failed**。
- 集成步骤（ReleaseSafe）：`test-integration`、`test-async-storage`、`test-configurations`、`test-query`、`test-regression`、`test-transactions`、`test-outputs`、`test-file-delivery`、`test-single-threaded` 全部通过。`test-decoder-matrix` 在 build-runner 下报告 failed command，但同一失败在 clean HEAD（`git stash` 后）复现，且 decoder binary 直接运行 **3/3** 通过，属于本机 build-runner 环境问题。

## 直接 A/B

同一 host 窗口，E-core affinity `[16,18,20,22,24,26]`。before = 上一提交 `33a8f1e` 的 `reference-kron-ready`（sha256 `f19c8c86...`），after = 本候选 `reference-kron-fixedout`（sha256 `42cc20f5...`）。比值大于 1 表示 after 更快；资格要求至少 5 轮、kron/peer/paired-ratio spread 均 ≤10%、95% bootstrap 区间不跨 1。

### P1：500k events，5 轮，schema batch

| case | after | before | ratio 中位 | 95% CI | 资格 |
| --- | ---: | ---: | ---: | --- | --- |
| async-memory-schema P1 | 2.294M | 2.142M | **1.0766** | 1.0455..1.1280 | **kron_leads** |
| spsc-memory-schema P1 | 2.281M | 2.152M | **1.0607** | 1.0484..1.0632 | **kron_leads** |
| spsc-mmap-schema P1 | 2.272M | 2.132M | **1.0727** | 1.0523..1.1384 | **kron_leads** |
| async-mmap-schema P1 | 2.268M | 2.074M | 1.0841 | 0.7034..1.1124 | inconclusive（一轮受 host 干扰，kron spread 43.3%） |

P1 的 4 个轴中 3 个 qualified lead；async-mmap 中位 +8.4%，但 5 轮中有一轮受同机其它构建任务干扰，按稳定性门槛保持 inconclusive。P1 schema 从约 2.07–2.15M 提升到约 2.27–2.29M。

最终源码（补一条 `writeHeaderTo` 调用方约束注释后重建，sha256 `d1e6da7d...`）在 async-memory P1 上重跑 5 轮：中位 **1.0857**（2.270M vs 2.110M），与上表 1.0766 一致；同窗口仍有一轮受干扰（kron spread 50%），按门槛保持 inconclusive。

### P4：500k events，5 轮，schema batch

| case | after | before | ratio 中位 | 95% CI | 资格 |
| --- | ---: | ---: | ---: | --- | --- |
| async-memory-schema P4 | 2.992M | 2.924M | 1.0312 | 0.9527..1.0386 | inconclusive（CI 跨1，paired spread 8.3%） |
| async-mmap-schema P4 | 2.993M | 2.978M | 1.0042 | 0.9672..1.0490 | inconclusive |
| spsc-memory-schema P4 | 2.581M | 2.576M | 0.9989 | 0.9927..1.0108 | inconclusive（spread 1.4%–1.8%，CI 跨1） |
| spsc-mmap-schema P4 | 2.572M | 2.582M | 0.9985 | 0.9685..1.0079 | inconclusive（spread 3.3%–4.8%，CI 跨1） |

P4 是 consumer-limited，producer encode 节省不会直接变成吞吐；四轴中位 0.9985–1.0312，无 qualified negative。SPSC P4 的稳定窗口显示 parity（±0.15%）。

## 同窗口 peer 资格（5 轮，500k）

peer 二进制复用 2026-11-04 冻结的 Foundation/spdlog 与 Foundation/tracing binary；kron 使用最终源码 binary（sha256 `d1e6da7d...`）。比值大于 1 表示 kron 更快。

| kron 配置 | peer | ratio | 95% CI | 资格 | kron | peer |
| --- | --- | ---: | --- | --- | ---: | ---: |
| async-memory-schema P1 | foundation | 1.2505 | 1.2202..1.4273 | inconclusive（peer spread 10.9%） | 2.257M | 1.800M |
| async-memory-schema P1 | foundation_tracing | **1.0240** | 1.0017..1.0614 | **kron_leads** | 2.257M | 2.204M |
| async-mmap-schema P1 | foundation | **1.0256** | 1.0016..1.0428 | **kron_leads** | 2.241M | 2.185M |
| async-mmap-schema P1 | foundation_tracing | 0.7957 | 0.7883..0.8091 | peer_leads | 2.241M | 2.782M |
| async-memory-schema P4 | foundation | 1.3520 | 1.2856..1.9395 | inconclusive（peer spread 32.1%） | 2.973M | 2.235M |
| async-memory-schema P4 | foundation_tracing | **1.3645** | 1.3316..1.4041 | **kron_leads** | 2.973M | 2.170M |
| async-mmap-schema P4 | foundation | 1.0087 | 0.9339..1.0434 | inconclusive（peer spread 11.3%） | 3.018M | 3.017M |
| async-mmap-schema P4 | foundation_tracing | **1.1850** | 1.1635..1.2043 | **kron_leads** | 3.018M | 2.547M |

关键变化：P1 memory schema 对 tracing 从落后/parity 变为 **qualified lead**；P1 mmap schema 对 Foundation 变为 **qualified lead**；P4 mmap schema 对 tracing **qualified lead**、对 Foundation parity。剩余 durable 差距集中到 **P1 mmap schema 对 tracing（0.796）**。本表是选定 case 的同窗口对照，不是 260-trial 完整矩阵；不更新整体跨库排名。

### SPSC 补充（5 轮，500k）

| kron 配置 | peer | ratio | 95% CI | 资格 | kron | peer |
| --- | --- | ---: | --- | --- | ---: | ---: |
| spsc-memory-schema P1 | foundation | 1.2376 | 1.2180..1.5559 | inconclusive（peer spread 20.8%） | 2.254M | 1.819M |
| spsc-memory-schema P1 | foundation_tracing | **1.0215** | 1.0091..1.0259 | **kron_leads** | 2.254M | 2.204M |
| spsc-mmap-schema P1 | foundation | **1.0408** | 1.0387..1.0676 | **kron_leads** | 2.285M | 2.177M |
| spsc-mmap-schema P1 | foundation_tracing | 0.8128 | 0.7865..0.8379 | peer_leads | 2.285M | 2.811M |
| spsc-memory-schema P4 | foundation | 1.0833 | 0.9565..1.1820 | inconclusive（kron spread 15.0%） | 2.574M | 2.325M |
| spsc-memory-schema P4 | foundation_tracing | 1.1674 | 1.0271..1.2015 | inconclusive（kron spread 15.0%） | 2.574M | 2.153M |
| spsc-mmap-schema P4 | foundation | 0.8715 | 0.7970..0.9616 | inconclusive（spread 11.1%–18.9%） | 2.579M | 2.915M |
| spsc-mmap-schema P4 | foundation_tracing | 0.9283 | 0.8931..1.0924 | inconclusive（spread 19.3%–21.5%） | 2.579M | 2.579M |

SPSC 结论与 async 一致：P1 memory 对 tracing **qualified lead**，P1 mmap 对 Foundation **qualified lead**，但对 tracing 仍为 **0.813 peer lead**。至此剩余唯一稳定的 durable peer lead 是 **P1 mmap schema 对 tracing**（async 0.796、SPSC 0.813）；该轴的 tracing mmap 本身比 tracing memory 快约 25%–27%，差距来自对方 mmap 后端，而不是 kron mmap 相对自身 memory 的回退。

## Instructions

`perf stat -e instructions`，同一 E-core affinity，交替 5 次取中位：

| 配置 | before | after | 变化 | 每条记录 |
| --- | ---: | ---: | ---: | ---: |
| async-mmap-schema P1 batch，500k | 4875.25M | 4382.77M | **−10.10%** | ≈ −982 |
| async-memory-schema P1 batch，500k | 4984.87M | 4516.44M | **−9.40%** | ≈ −935 |
| async-memory-schema P4 batch，500k | 4934.20M | 4503.03M | **−8.74%** | ≈ −860 |

指令下降集中在 producer 的 `writeHeaderTo`/`writeValueTo`：原路径每个整数和 blob 都经过动态 writer vtable + memcpy；FixedOutput 把 header 与标量值变成直接 `writeInt`，blob 只保留必要的一次拷贝。P1 producer-limited，因此约 10% 的全进程指令下降转化为 6%–8% 的吞吐提升。

## 边界

- payload 字节由 schema/reference/wire/codec 的 byte-parity 测试与每条 A/B 输出的 `run.py::verify` 逐条核对；`sizeMeasured` 的 shape/level 校验仍在写入前执行。
- `FixedOutput` 只用于内部 measured 写入；公开 `codec.writeTo`/`writeFramed` 仍走动态 writer，行为不变。
- `writeHeaderTo` 仅是 core 模块内部可见性调整，未新增 root 导出。
- 默认 durable/CRC/recovery、journal 格式、输出字节与 queue 预算未改变。

## 原始数据

- [manifest.json](manifest.json)：host/load、git HEAD、diff sha256、binary sha256、A/B 参数与核验计数。
- [ab-p1/results.jsonl](ab-p1/results.jsonl)：P1 4 配置 × 5 轮 × 2 binary（40 次，2,004 万条完整 JSON）。
- [ab-p4/results.jsonl](ab-p4/results.jsonl)：P4 4 配置 × 5 轮 × 2 binary（40 次，2,004 万条完整 JSON）。
- [ab-confirm/results.jsonl](ab-confirm/results.jsonl)：最终源码重建后在 async-memory P1 的 5 轮确认（10 次，501 万条完整 JSON）。
- [peer/results.jsonl](peer/results.jsonl)：async schema 4 配置 × 3 library × 5 轮（60 次，3,006 万条完整 JSON）。
- [peer-spsc/results.jsonl](peer-spsc/results.jsonl)：SPSC schema 4 配置 × 3 library × 5 轮（60 次，3,006 万条完整 JSON）。
