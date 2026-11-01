# 完整日志流程实测

共 140 个试验，逐条核对 14,140,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为五次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.120 | 2.335 | 2.116 | 2.309 | 无 |
| foundation mmap | 1.809 | 2.082 | 1.800 | 2.079 | 有 |
| kron async-memory-inline | 2.145 | 2.068 | 2.141 | 2.064 | 无 |
| kron async-mmap-inline | 2.192 | 2.078 | 2.188 | 2.075 | 有 |
| kron spsc-memory-inline | 2.178 | 2.113 | 2.174 | 2.108 | 无 |
| kron spsc-mmap-inline | 2.256 | 2.122 | 2.251 | 2.117 | 有 |
| spdlog producer_format | 1.641 | 0.674 | 1.640 | 0.673 | 无 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 340 / 690 | 761 / 30,286 | 0.175 | 0.169 |
| foundation mmap | 504 / 899 | 974 / 7,824 | 7.705 | 11.551 |
| kron async-memory-inline | 343 / 5,340 | 987 / 14,438 | 0.581 | 0.554 |
| kron async-mmap-inline | 346 / 5,112 | 979 / 15,683 | 9.739 | 21.427 |
| kron spsc-memory-inline | 328 / 5,788 | 336 / 9,048 | 0.648 | 0.892 |
| kron spsc-mmap-inline | 328 / 5,236 | 291 / 9,326 | 16.050 | 60.287 |
| spdlog producer_format | 682 / 1,756 | 3,892 / 31,069 | 0.095 | 0.097 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 48.263 | 44.173 | 0.083 | 0.077 | 299.33 |
| foundation mmap | 63.799 | 58.092 | 0.089 | 0.080 | 299.33 |
| kron async-memory-inline | 47.960 | 49.733 | 0.026 | 0.025 | 299.37 |
| kron async-mmap-inline | 60.324 | 70.446 | 0.025 | 0.023 | 299.37 |
| kron spsc-memory-inline | 55.848 | 49.079 | 0.026 | 0.023 | 299.03 |
| kron spsc-mmap-inline | 61.542 | 107.376 | 0.029 | 0.023 | 299.03 |
| spdlog producer_format | 61.806 | 149.907 | 0.020 | 0.026 | 299.33 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
