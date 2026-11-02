# 完整日志流程实测

共 80 个试验，逐条核对 8,080,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation_tracing memory | 2.547 | 2.362 | 2.542 | 2.360 | 无 |
| foundation_tracing mmap | 2.526 | 2.439 | 2.522 | 2.436 | 有 |
| kron async-memory-inline | 2.289 | 2.278 | 2.285 | 2.273 | 无 |
| kron async-mmap-inline | 2.236 | 2.245 | 2.213 | 2.240 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 237 / 525 | 622 / 31,973 | 0.192 | 0.180 |
| foundation_tracing mmap | 328 / 842 | 877 / 8,455 | 12.258 | 14.252 |
| kron async-memory-inline | 411 / 800 | 639 / 15,432 | 0.576 | 0.568 |
| kron async-mmap-inline | 350 / 788 | 780 / 29,230 | 14.092 | 12.004 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 40.209 | 43.400 | 0.010 | 0.010 | 299.33 |
| foundation_tracing mmap | 58.519 | 55.984 | 0.012 | 0.010 | 299.33 |
| kron async-memory-inline | 44.978 | 45.794 | 0.033 | 0.036 | 299.37 |
| kron async-mmap-inline | 56.718 | 59.890 | 0.029 | 0.023 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
