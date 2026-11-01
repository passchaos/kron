# 完整日志流程实测

共 120 个试验，逐条核对 12,120,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为五次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.936 | 1.993 | 1.932 | 1.990 | 无 |
| foundation mmap | 1.792 | 2.102 | 1.789 | 2.097 | 有 |
| kron async-memory-inline | 2.140 | 2.067 | 2.136 | 2.063 | 无 |
| kron async-mmap-inline | 2.111 | 1.744 | 2.107 | 1.741 | 有 |
| kron spsc-memory-inline | 2.155 | 2.111 | 2.151 | 2.106 | 无 |
| kron spsc-mmap-inline | 2.162 | 1.916 | 2.157 | 1.911 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 339 / 655 | 804 / 32,072 | 0.229 | 0.206 |
| foundation mmap | 498 / 949 | 1,056 / 8,933 | 22.675 | 13.012 |
| kron async-memory-inline | 383 / 6,190 | 875 / 17,520 | 0.619 | 0.588 |
| kron async-mmap-inline | 383 / 869 | 891 / 17,009 | 5.649 | 21.422 |
| kron spsc-memory-inline | 413 / 20,571 | 297 / 9,972 | 0.893 | 0.963 |
| kron spsc-mmap-inline | 305 / 6,145 | 274 / 10,450 | 23.881 | 368.098 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 52.599 | 51.313 | 0.085 | 0.078 | 299.33 |
| foundation mmap | 79.506 | 62.042 | 0.100 | 0.104 | 299.33 |
| kron async-memory-inline | 48.163 | 50.096 | 0.031 | 0.027 | 299.37 |
| kron async-mmap-inline | 55.181 | 86.251 | 0.028 | 0.026 | 299.37 |
| kron spsc-memory-inline | 48.472 | 49.106 | 0.034 | 0.026 | 299.03 |
| kron spsc-mmap-inline | 68.779 | 446.387 | 0.026 | 0.029 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
