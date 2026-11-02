# 完整日志流程实测

共 80 个试验，逐条核对 8,080,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.846 | 2.235 | 1.844 | 2.232 | 无 |
| foundation mmap | 2.061 | 2.774 | 2.054 | 2.765 | 有 |
| kron async-memory-inline | 1.719 | 1.623 | 1.710 | 1.617 | 无 |
| kron async-mmap-inline | 1.739 | 1.612 | 1.730 | 1.605 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 374 / 714 | 698 / 46,000 | 0.244 | 0.266 |
| foundation mmap | 439 / 854 | 712 / 7,139 | 19.050 | 19.630 |
| kron async-memory-inline | 355 / 619 | 850 / 52,395 | 0.721 | 0.716 |
| kron async-mmap-inline | 347 / 598 | 864 / 48,987 | 13.863 | 11.773 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 55.576 | 46.015 | 0.067 | 0.061 | 299.33 |
| foundation mmap | 68.734 | 56.775 | 0.146 | 0.066 | 299.33 |
| kron async-memory-inline | 60.219 | 63.610 | 0.077 | 0.090 | 299.37 |
| kron async-mmap-inline | 72.296 | 76.785 | 0.084 | 0.096 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
