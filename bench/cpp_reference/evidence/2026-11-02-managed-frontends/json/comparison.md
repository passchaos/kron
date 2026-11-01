# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.024 | 2.092 | 2.020 | 2.088 | 无 |
| foundation mmap | 1.823 | 2.071 | 1.820 | 2.067 | 有 |
| foundation_tracing memory | 2.605 | 2.173 | 2.598 | 2.170 | 无 |
| foundation_tracing mmap | 1.981 | 2.208 | 1.974 | 2.204 | 有 |
| kron async-memory-inline | 2.166 | 2.141 | 2.162 | 2.137 | 无 |
| kron async-mmap-inline | 2.208 | 2.175 | 2.203 | 2.167 | 有 |
| kron spsc-memory-inline | 2.171 | 2.399 | 2.165 | 2.392 | 无 |
| kron spsc-mmap-inline | 2.266 | 2.373 | 2.260 | 2.366 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 348 / 649 | 759 / 31,872 | 0.213 | 0.210 |
| foundation mmap | 510 / 922 | 876 / 9,580 | 21.003 | 25.999 |
| foundation_tracing memory | 239 / 549 | 681 / 30,461 | 0.186 | 0.196 |
| foundation_tracing mmap | 478 / 837 | 935 / 10,460 | 17.147 | 36.821 |
| kron async-memory-inline | 336 / 683 | 836 / 28,943 | 0.582 | 0.599 |
| kron async-mmap-inline | 341 / 666 | 807 / 26,221 | 542.823 | 12.643 |
| kron spsc-memory-inline | 334 / 713 | 291 / 467 | 0.731 | 0.954 |
| kron spsc-mmap-inline | 325 / 587 | 287 / 452 | 25.107 | 1234.763 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 50.450 | 49.300 | 0.090 | 0.078 | 299.33 |
| foundation mmap | 79.001 | 75.437 | 0.094 | 0.085 | 299.33 |
| foundation_tracing memory | 39.462 | 47.008 | 0.011 | 0.007 | 299.33 |
| foundation_tracing mmap | 68.576 | 79.421 | 0.010 | 0.009 | 299.33 |
| kron async-memory-inline | 48.204 | 48.509 | 0.029 | 0.023 | 299.37 |
| kron async-mmap-inline | 588.913 | 59.783 | 0.024 | 0.041 | 299.37 |
| kron spsc-memory-inline | 47.618 | 43.746 | 0.026 | 0.022 | 299.03 |
| kron spsc-mmap-inline | 72.229 | 1285.184 | 0.024 | 0.020 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
