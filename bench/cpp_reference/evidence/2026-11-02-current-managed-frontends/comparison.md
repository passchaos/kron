# 完整日志流程实测

共 60 个试验，逐条核对 6,060,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| kron async-memory-inline | 2.384 | 2.352 | 2.376 | 2.347 | 无 |
| kron async-mmap-inline | 2.373 | 2.318 | 2.367 | 2.313 | 有 |
| spdlog producer_format | 1.501 | 0.671 | 1.501 | 0.671 | 无 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| kron async-memory-inline | 338 / 735 | 873 / 24,206 | 0.624 | 0.591 |
| kron async-mmap-inline | 335 / 613 | 855 / 24,056 | 13.943 | 13.955 |
| spdlog producer_format | 596 / 1,767 | 4,698 / 33,270 | 0.106 | 0.099 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| kron async-memory-inline | 43.388 | 43.939 | 0.046 | 0.030 | 299.37 |
| kron async-mmap-inline | 56.904 | 56.151 | 0.076 | 0.021 | 299.37 |
| spdlog producer_format | 67.450 | 150.592 | 0.023 | 0.024 | 299.33 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
