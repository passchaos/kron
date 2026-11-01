# 完整日志流程实测

共 40 个试验，逐条核对 4,040,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation_tracing memory | 1.447 | 2.492 | 1.364 | 2.487 | 无 |
| foundation_tracing mmap | 0.868 | 2.232 | 0.868 | 2.227 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 516 / 1,014 | 767 / 19,885 | 0.194 | 0.161 |
| foundation_tracing mmap | 1,023 / 2,842 | 1,217 / 7,643 | 20.206 | 24.058 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 74.497 | 40.994 | 0.021 | 0.015 | 156.44 |
| foundation_tracing mmap | 188.411 | 69.787 | 0.017 | 0.014 | 156.44 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
