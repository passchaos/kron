# 完整日志流程实测

共 40 个试验，逐条核对 4,040,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation_tracing memory | 1.678 | 2.640 | 1.676 | 2.637 | 无 |
| foundation_tracing mmap | 0.932 | 2.275 | 0.930 | 2.271 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 515 / 864 | 768 / 20,364 | 0.159 | 0.161 |
| foundation_tracing mmap | 995 / 2,290 | 1,242 / 6,375 | 12.204 | 12.031 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 60.789 | 38.758 | 0.027 | 0.015 | 156.44 |
| foundation_tracing mmap | 120.814 | 57.497 | 0.018 | 0.023 | 156.44 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
