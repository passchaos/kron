# 完整日志流程实测

共 80 个试验，逐条核对 8,080,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation_tracing memory | 2.695 | 2.189 | 2.691 | 2.186 | 无 |
| foundation_tracing mmap | 2.098 | 2.215 | 2.094 | 2.211 | 有 |
| kron async-memory-inline | 2.396 | 2.397 | 2.391 | 2.393 | 无 |
| kron async-mmap-inline | 2.420 | 2.459 | 2.412 | 2.455 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 232 / 501 | 774 / 29,048 | 0.152 | 0.147 |
| foundation_tracing mmap | 482 / 787 | 932 / 8,830 | 19.345 | 19.543 |
| kron async-memory-inline | 329 / 680 | 887 / 22,899 | 0.548 | 0.555 |
| kron async-mmap-inline | 388 / 704 | 906 / 23,681 | 11.209 | 14.120 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 37.890 | 46.695 | 0.008 | 0.005 | 299.33 |
| foundation_tracing mmap | 65.943 | 65.576 | 0.011 | 0.007 | 299.33 |
| kron async-memory-inline | 43.154 | 43.130 | 0.031 | 0.026 | 299.37 |
| kron async-mmap-inline | 54.965 | 55.558 | 0.061 | 0.021 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
