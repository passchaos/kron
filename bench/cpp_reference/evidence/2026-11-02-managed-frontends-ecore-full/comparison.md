# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.825 | 2.280 | 1.823 | 2.277 | 无 |
| foundation mmap | 2.149 | 2.907 | 2.137 | 2.901 | 有 |
| foundation_tracing memory | 2.210 | 2.227 | 2.207 | 2.222 | 无 |
| foundation_tracing mmap | 2.711 | 3.254 | 2.701 | 3.246 | 有 |
| kron async-memory-inline | 1.782 | 1.649 | 1.773 | 1.644 | 无 |
| kron async-mmap-inline | 1.764 | 1.671 | 1.759 | 1.668 | 有 |
| kron spsc-memory-inline | 1.852 | 1.888 | 1.847 | 1.882 | 无 |
| kron spsc-mmap-inline | 1.849 | 1.907 | 1.844 | 1.901 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 372 / 653 | 608 / 45,715 | 0.312 | 0.270 |
| foundation mmap | 433 / 936 | 860 / 7,974 | 16.366 | 13.687 |
| foundation_tracing memory | 285 / 600 | 697 / 45,736 | 0.260 | 0.252 |
| foundation_tracing mmap | 342 / 805 | 806 / 8,449 | 12.908 | 12.707 |
| kron async-memory-inline | 356 / 570 | 847 / 49,060 | 0.739 | 0.724 |
| kron async-mmap-inline | 358 / 551 | 847 / 49,784 | 11.061 | 10.941 |
| kron spsc-memory-inline | 326 / 543 | 299 / 455 | 0.812 | 1.046 |
| kron spsc-mmap-inline | 324 / 515 | 304 / 448 | 14.174 | 20.371 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.238 | 45.182 | 0.103 | 0.056 | 299.33 |
| foundation mmap | 64.519 | 49.132 | 0.235 | 0.069 | 299.33 |
| foundation_tracing memory | 46.423 | 46.191 | 0.013 | 0.012 | 299.33 |
| foundation_tracing mmap | 50.387 | 44.960 | 0.014 | 0.012 | 299.33 |
| kron async-memory-inline | 58.141 | 62.667 | 0.153 | 0.092 | 299.37 |
| kron async-mmap-inline | 69.352 | 71.903 | 0.041 | 0.033 | 299.37 |
| kron spsc-memory-inline | 56.012 | 55.099 | 0.034 | 0.024 | 299.03 |
| kron spsc-mmap-inline | 68.729 | 74.680 | 0.032 | 0.026 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
