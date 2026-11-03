# 完整日志流程实测

共 72 个试验，逐条核对 7,272,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为3次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.876 | 2.277 | 1.812 | 2.272 | 无 |
| foundation mmap | 1.791 | 2.695 | 1.788 | 2.688 | 有 |
| foundation_tracing memory | 2.320 | 2.237 | 2.312 | 2.233 | 无 |
| foundation_tracing mmap | 2.601 | 2.388 | 2.588 | 2.383 | 有 |
| kron async-memory-schema | 1.926 | 1.902 | 1.921 | 1.895 | 无 |
| kron async-mmap-schema | 1.980 | 1.864 | 1.973 | 1.856 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 372 / 708 | 589 / 44,242 | 0.272 | 0.266 |
| foundation mmap | 495 / 915 | 737 / 7,187 | 39.499 | 22.068 |
| foundation_tracing memory | 284 / 605 | 698 / 43,082 | 0.282 | 0.236 |
| foundation_tracing mmap | 427 / 858 | 839 / 8,520 | 329.796 | 460.707 |
| kron async-memory-schema | 434 / 695 | 851 / 38,986 | 0.703 | 0.740 |
| kron async-mmap-schema | 432 / 694 | 857 / 39,376 | 13.634 | 11.534 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.266 | 45.224 | 0.105 | 0.095 | 299.33 |
| foundation mmap | 101.969 | 60.183 | 0.111 | 0.098 | 299.33 |
| foundation_tracing memory | 44.276 | 45.904 | 0.001 | 0.001 | 299.33 |
| foundation_tracing mmap | 367.789 | 505.775 | 0.013 | 0.008 | 299.33 |
| kron async-memory-schema | 53.594 | 54.383 | 0.130 | 0.102 | 299.37 |
| kron async-mmap-schema | 76.590 | 75.155 | 0.036 | 0.029 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-schema | foundation | 1 | batch | 1.092 | 1.009..1.258 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | batch | 0.839 | 0.831..0.851 | inconclusive |
| async-memory-schema | foundation | 1 | sampled | 10.718 | 1.078..11.957 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.908 | 0.893..4.480 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 0.834 | 0.797..0.856 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | batch | 0.844 | 0.789..0.855 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 0.810 | 0.779..1.559 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | sampled | 0.833 | 0.821..0.851 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 1.058 | 0.929..1.212 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.762 | 0.708..0.769 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 1.034 | 0.961..1.076 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.910 | 0.860..0.955 | inconclusive |
| async-mmap-schema | foundation | 4 | batch | 0.690 | 0.685..0.709 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.778 | 0.732..0.837 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.546 | 0.536..0.553 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.700 | 0.695..1.127 | inconclusive |
