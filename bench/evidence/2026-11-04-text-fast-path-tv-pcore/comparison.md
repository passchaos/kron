# 完整日志流程实测

共 120 个试验，逐条核对 12,120,000 条完整日志。固定 CPU affinity：[1, 3, 5, 7, 9, 11]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.144 | 2.159 | 2.142 | 2.157 | 无 |
| foundation mmap | 2.061 | 2.390 | 2.058 | 2.387 | 有 |
| foundation_tracing memory | 2.700 | 2.204 | 2.698 | 2.203 | 无 |
| foundation_tracing mmap | 2.559 | 2.371 | 2.555 | 2.368 | 有 |
| kron async-memory-inline | 2.005 | 3.466 | 1.995 | 3.442 | 无 |
| kron async-mmap-inline | 2.020 | 3.450 | 2.016 | 3.419 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 344 / 628 | 710 / 32,719 | 0.249 | 0.208 |
| foundation mmap | 470 / 908 | 975 / 7,485 | 18.286 | 14.354 |
| foundation_tracing memory | 237 / 517 | 727 / 32,439 | 0.168 | 0.184 |
| foundation_tracing mmap | 328 / 886 | 764 / 17,503 | 24.353 | 20.453 |
| kron async-memory-inline | 462 / 800 | 946 / 1,506 | 0.588 | 0.566 |
| kron async-mmap-inline | 498 / 833 | 975 / 1,548 | 14.383 | 8.393 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 47.698 | 47.452 | 0.046 | 0.047 | 299.33 |
| foundation mmap | 67.654 | 58.475 | 0.063 | 0.052 | 299.33 |
| foundation_tracing memory | 37.736 | 46.235 | 0.001 | 0.001 | 299.33 |
| foundation_tracing mmap | 67.276 | 66.981 | 0.013 | 0.007 | 299.33 |
| kron async-memory-inline | 51.636 | 30.664 | 0.030 | 0.044 | 299.37 |
| kron async-mmap-inline | 62.569 | 40.308 | 0.081 | 0.188 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 0.975 | 0.887..0.988 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.766 | 0.698..0.783 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.006 | 0.807..10.294 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.755 | 0.654..0.866 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.632 | 1.486..1.805 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.553 | 1.516..1.666 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.661 | 1.257..1.739 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.700 | 1.322..1.792 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 0.978 | 0.847..1.027 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.797 | 0.682..1.004 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 0.973 | 0.861..1.065 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.799 | 0.650..0.834 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.411 | 1.188..1.433 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.443 | 1.126..1.609 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.439 | 1.158..1.533 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.429 | 1.214..1.515 | inconclusive |
