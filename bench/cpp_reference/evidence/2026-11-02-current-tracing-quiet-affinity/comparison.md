# 完整日志流程实测

共 80 个试验，逐条核对 8,080,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation_tracing memory | 2.178 | 2.231 | 2.175 | 2.228 | 无 |
| foundation_tracing mmap | 2.779 | 2.723 | 2.773 | 2.718 | 有 |
| kron async-memory-inline | 1.727 | 1.635 | 1.723 | 1.631 | 无 |
| kron async-mmap-inline | 1.744 | 1.611 | 1.737 | 1.603 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 288 / 612 | 684 / 46,250 | 0.224 | 0.225 |
| foundation_tracing mmap | 339 / 771 | 807 / 8,258 | 15.884 | 12.395 |
| kron async-memory-inline | 354 / 617 | 832 / 50,716 | 0.717 | 0.731 |
| kron async-mmap-inline | 352 / 556 | 823 / 50,860 | 10.649 | 14.922 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation_tracing memory | 46.985 | 46.040 | 0.013 | 0.010 | 299.33 |
| foundation_tracing mmap | 51.888 | 50.331 | 0.014 | 0.009 | 299.33 |
| kron async-memory-inline | 59.737 | 62.937 | 0.104 | 0.034 | 299.37 |
| kron async-mmap-inline | 69.141 | 78.468 | 0.035 | 0.030 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
