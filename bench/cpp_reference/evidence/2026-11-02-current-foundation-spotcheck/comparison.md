# 完整日志流程实测

共 80 个试验，逐条核对 8,080,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.136 | 2.124 | 2.133 | 2.121 | 无 |
| foundation mmap | 1.924 | 2.194 | 1.917 | 2.189 | 有 |
| kron async-memory-inline | 2.382 | 2.259 | 2.375 | 2.255 | 无 |
| kron async-mmap-inline | 2.339 | 2.370 | 2.333 | 2.364 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 352 / 573 | 850 / 29,491 | 0.182 | 0.185 |
| foundation mmap | 516 / 1,003 | 1,048 / 8,133 | 12.383 | 12.476 |
| kron async-memory-inline | 338 / 689 | 897 / 24,425 | 0.587 | 0.604 |
| kron async-mmap-inline | 334 / 664 | 888 / 23,441 | 14.073 | 14.425 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 48.312 | 48.079 | 0.091 | 0.077 | 299.33 |
| foundation mmap | 66.513 | 58.804 | 0.097 | 0.100 | 299.33 |
| kron async-memory-inline | 43.486 | 45.662 | 0.029 | 0.025 | 299.37 |
| kron async-mmap-inline | 57.268 | 56.508 | 0.027 | 0.021 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
