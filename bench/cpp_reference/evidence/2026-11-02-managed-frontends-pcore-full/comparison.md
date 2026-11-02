# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.085 | 2.059 | 2.080 | 2.056 | 无 |
| foundation mmap | 2.190 | 2.411 | 2.183 | 2.407 | 有 |
| foundation_tracing memory | 2.500 | 2.140 | 2.497 | 2.138 | 无 |
| foundation_tracing mmap | 2.593 | 2.457 | 2.588 | 2.454 | 有 |
| kron async-memory-inline | 2.270 | 2.351 | 2.265 | 2.346 | 无 |
| kron async-mmap-inline | 2.353 | 2.374 | 2.346 | 2.369 | 有 |
| kron spsc-memory-inline | 2.431 | 2.674 | 2.425 | 2.666 | 无 |
| kron spsc-mmap-inline | 2.491 | 2.652 | 2.484 | 2.640 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 348 / 596 | 746 / 32,103 | 0.212 | 0.207 |
| foundation mmap | 484 / 955 | 929 / 8,765 | 12.275 | 12.183 |
| foundation_tracing memory | 236 / 552 | 698 / 33,377 | 0.177 | 0.191 |
| foundation_tracing mmap | 321 / 808 | 818 / 10,276 | 20.009 | 19.683 |
| kron async-memory-inline | 373 / 695 | 819 / 18,416 | 0.582 | 0.580 |
| kron async-mmap-inline | 361 / 624 | 807 / 21,248 | 14.124 | 13.961 |
| kron spsc-memory-inline | 357 / 635 | 284 / 477 | 0.655 | 0.864 |
| kron spsc-mmap-inline | 365 / 725 | 280 / 489 | 13.366 | 38.650 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 49.056 | 49.763 | 0.049 | 0.042 | 299.33 |
| foundation mmap | 59.683 | 55.398 | 0.071 | 0.052 | 299.33 |
| foundation_tracing memory | 40.827 | 47.684 | 0.010 | 0.011 | 299.33 |
| foundation_tracing mmap | 57.668 | 61.210 | 0.012 | 0.007 | 299.33 |
| kron async-memory-inline | 45.473 | 43.885 | 0.027 | 0.035 | 299.37 |
| kron async-mmap-inline | 57.957 | 57.702 | 0.027 | 0.023 | 299.37 |
| kron spsc-memory-inline | 42.672 | 38.989 | 0.023 | 0.021 | 299.03 |
| kron spsc-mmap-inline | 56.745 | 77.589 | 0.026 | 0.020 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
