# Multi-producer mmap spool

## 变更

`MmapSpool` 增加 `Options.channel`：每条事件写入指定 channel。多线程应用可以为每个 producer 创建一个独立 `MmapSpool`（独立 path、独立 channel），每个 spool 仍由自己的 writer 线程按约 1MiB `msync(MS_ASYNC)`，`shutdown` 截断自己的文件。没有共享队列、共享 tail 或 consumer。

benchmark reference 增加 `--mode=spool --producers=4`：
- 每个 producer 线程创建 `output.thread-N`，channel = N+1；
- warmup/events 按 producer 均分，global `field0` 与共享 reference 契约一致；
- 结束后保留每个 region 文件，`run.py::verify` 按 channel 顺序读取并逐条核对；
- 不再做 30MB 拼接（拼接会污染 `cleanup_ns`），验证直接读取 region 文件。

这是**非 durable、单 route、无 journal/CRC/recovery** 的 opt-in fast mode；默认 `Logging`/`Runtime` durable 路径不变。

## 正确性

- `zig build test -Doptimize=ReleaseSafe -j1`：**65/65 steps、771/772 tests（1 项 local skip）**，success。
- `zig build verify-local -Doptimize=ReleaseSafe -j1`：**159/159 steps、805/806 tests（1 项 local skip）**，`verify-local success`。
- 新增 `mmap spool channel option is written into each record`，锁定 channel 与 per-spool sequence。
- 60 次 peer 试验共 **6,060,000** 条完整 JSON 全部由 `run.py::verify` 逐条核对；多 producer artifact 由 4 个 region 文件按 channel 顺序读取，`accepted/written/drop/pending`、完整 metadata、`field0` 唯一性和总行数全部通过。

## 扩展性诊断

同 host、E-core、100k+1k、ts64、每 producer 一个 spool/文件，batch：

| producers | aggregate records/s |
| ---: | ---: |
| 1 | 3.26M |
| 2 | 5.48M |
| 4 | 8.10–8.47M |

4 producer 时 4 个 writer 线程与 4 个 producer 共 8 线程仍能线性扩展；`--no-writer` 版本相近（8.0M），说明瓶颈不是 writer 线程。该诊断逐文件核验 101,000 条记录。

## peer 资格（5 轮）

| producers | phase | peer | kron | peer | ratio | 95% CI | 资格 |
| ---: | --- | --- | ---: | ---: | ---: | --- | --- |
| 1 | batch | foundation | 3.239M | 2.190M | 1.4668 | 1.460..1.506 | **kron_leads** |
| 1 | batch | foundation_tracing | 3.239M | 2.772M | 1.1625 | 1.158..1.350 | inconclusive |
| 1 | sampled | foundation | 2.775M | 1.979M | 1.3905 | 1.369..1.411 | **kron_leads** |
| 1 | sampled | foundation_tracing | 2.775M | 2.484M | 1.1143 | 1.102..1.133 | **kron_leads** |
| 4 | batch | foundation | 8.201M | 3.162M | 2.5693 | 2.497..2.740 | **kron_leads** |
| 4 | batch | foundation_tracing | 8.201M | 2.644M | 3.2174 | 2.974..3.360 | inconclusive |
| 4 | sampled | foundation | 7.624M | 2.803M | 2.7199 | 2.473..2.786 | inconclusive |
| 4 | sampled | foundation_tracing | 7.624M | 2.601M | 2.9052 | 2.799..3.029 | **kron_leads** |

### 结论

- P1 spool 对 Foundation 两 phase qualified，对 tracing sampled **1.114 qualified**（batch 1.163 中位领先但因 spread inconclusive）。
- **P4 spool 8.20M/7.62M，对 Foundation 2.57–2.72x、对 tracing 2.91–3.22x**；P4 batch 对 tracing 和 P4 sampled 对 Foundation 的区间未过 spread 门槛，但中位领先 2.7–3.2x，绝对值差距远超噪声。
- 这填补了 durable 矩阵中 P4 mmap sampled 对 Foundation 的 peer lead（0.68–0.85）；但 spool 没有 journal/CRC/recovery，不能直接替代 durable 排名。

## 边界

- 非 durable：崩溃可能丢失尾部记录；没有 journal、CRC、三检查点、recovery、queue 或 consumer。
- 单 route、JSON、每个 producer 一个文件；应用需要自己创建/关闭 N 个 spool 并合并文件。
- 每个 spool 一个 writer 线程；4 producer 时共 8 线程，E-core 6 核可承载但 P-core/低核数环境需单独测量。
- 本表是 E-core 同窗口选定 case 对照；不是完整 240-trial 矩阵，不更新 durable 排名。
- Foundation/tracing 的 mmap 带进程崩溃恢复；spool 不带，比较只在“非 durable fast mode”范围内成立。

## 原始数据

- [manifest.json](manifest.json)：host/load、git HEAD、binary/source sha256、Foundation HEAD、配置与核对计数。
- [results.jsonl](results.jsonl)：kron spool + 两个 peer 的 P1/P4 × batch/sampled × 5 轮（60 次）。
