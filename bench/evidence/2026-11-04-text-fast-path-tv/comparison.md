# 完整日志流程实测

共 120 个试验，逐条核对 12,120,000 条完整日志。固定 CPU affinity：[21, 23, 25, 27, 29, 31]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.791 | 2.211 | 1.789 | 2.208 | 无 |
| foundation mmap | 2.132 | 2.636 | 2.129 | 2.631 | 有 |
| foundation_tracing memory | 2.208 | 1.982 | 2.203 | 1.980 | 无 |
| foundation_tracing mmap | 2.755 | 3.090 | 2.748 | 3.083 | 有 |
| kron async-memory-inline | 2.324 | 4.057 | 2.307 | 4.015 | 无 |
| kron async-mmap-inline | 2.462 | 3.997 | 2.454 | 3.949 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 376 / 743 | 640 / 47,497 | 0.293 | 0.292 |
| foundation mmap | 437 / 911 | 824 / 8,596 | 18.564 | 139.369 |
| foundation_tracing memory | 285 / 659 | 663 / 46,806 | 0.245 | 0.244 |
| foundation_tracing mmap | 341 / 797 | 795 / 8,032 | 18.417 | 14.040 |
| kron async-memory-inline | 387 / 652 | 910 / 1,457 | 0.777 | 0.770 |
| kron async-mmap-inline | 413 / 752 | 920 / 1,473 | 5.173 | 152.572 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.995 | 46.618 | 0.062 | 0.059 | 299.33 |
| foundation mmap | 65.891 | 177.683 | 0.081 | 0.070 | 299.33 |
| foundation_tracing memory | 46.305 | 51.693 | 0.012 | 0.011 | 299.33 |
| foundation_tracing mmap | 56.313 | 49.245 | 0.015 | 0.011 | 299.33 |
| kron async-memory-inline | 44.706 | 26.479 | 0.155 | 0.117 | 299.37 |
| kron async-mmap-inline | 46.909 | 182.430 | 0.069 | 0.094 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.286 | 1.231..1.357 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | batch | 1.038 | 1.009..1.092 | kron_leads |
| async-memory-inline | foundation | 1 | sampled | 1.293 | 0.957..1.313 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 1.110 | 0.857..1.156 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.830 | 1.712..1.881 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.969 | 1.947..61.070 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.683 | 1.310..1.847 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.790 | 1.368..1.871 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 1.165 | 1.039..1.176 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.888 | 0.872..0.930 | peer_leads |
| async-mmap-inline | foundation | 1 | sampled | 1.049 | 0.979..1.129 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.836 | 0.815..0.911 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.544 | 1.291..1.584 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.281 | 1.138..1.375 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.366 | 1.231..1.534 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.256 | 1.001..1.327 | inconclusive |
