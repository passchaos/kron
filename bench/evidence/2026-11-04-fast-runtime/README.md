# Dedicated FastRuntime candidate

## 设计

尝试用独立SPSC text ring替代Runtime的admission/measure/journal：

- producer：logger capture + `common.encodeDecoded` 渲染 + ring claim/publish；
- consumer：单线程drain + FileSink写/flush；
- 无journal/CRC/recovery/admission/measure；opt-in独立API。

候选源码与benchmark参考保留在[candidate/](candidate/)；生产`src/`已恢复基线（未采用）。

## P1 结果

同一E-core窗口，100k events + 1k warmup，P1 async，FileSink 64KiB：

| idle | written_records_per_sec | total_ns |
| --- | ---: | ---: |
| sleep | 2.119M | 47.18ms |
| spin | 2.281M | 43.85ms |

对照：现有text fast path P1 1.89M–2.23M；Foundation/tracing memory P1 2.0M–2.18M；tracing mmap P1 2.4M–2.97M。

## 决策

FastRuntime P1 2.12M–2.28M，没有超过现有text fast path的稳定水平，也没有缩小tracing mmap P1差距。原因不是ring/admission，而是producer render+capture约2.3M的上限，以及tracing mmap backend的spool/writer重叠。候选不进入生产；模块/参考保留，下一步应做 **mmap spool + writer output backend**，而不是继续简化ring。

初始sleep版本因producer wake flag缺失而deadlock；归档候选已包含修复（`producer_waiting`）。sleep/spin原始stdout见[sleep.json](sleep.json)/[spin.json](spin.json)，binary身份见[binaries.sha256](binaries.sha256)。
