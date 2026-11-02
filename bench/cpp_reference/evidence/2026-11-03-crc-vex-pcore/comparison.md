# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.177 | 2.213 | 2.174 | 2.210 | 无 |
| foundation mmap | 2.025 | 2.195 | 2.023 | 2.193 | 有 |
| foundation_tracing memory | 2.617 | 2.176 | 2.614 | 2.174 | 无 |
| foundation_tracing mmap | 2.520 | 2.123 | 2.516 | 2.121 | 有 |
| kron async-memory-inline | 2.377 | 2.377 | 2.371 | 2.371 | 无 |
| kron async-mmap-inline | 2.322 | 2.394 | 2.315 | 2.383 | 有 |
| kron spsc-memory-inline | 2.523 | 2.703 | 2.518 | 2.696 | 无 |
| kron spsc-mmap-inline | 2.485 | 2.717 | 2.480 | 2.708 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 348 / 618 | 767 / 31,924 | 0.214 | 0.199 |
| foundation mmap | 493 / 922 | 942 / 8,953 | 19.238 | 12.960 |
| foundation_tracing memory | 239 / 520 | 649 / 33,031 | 0.216 | 0.186 |
| foundation_tracing mmap | 320 / 800 | 788 / 9,006 | 12.755 | 19.441 |
| kron async-memory-inline | 295 / 704 | 814 / 22,681 | 0.556 | 0.558 |
| kron async-mmap-inline | 319 / 707 | 917 / 21,809 | 14.192 | 14.182 |
| kron spsc-memory-inline | 349 / 612 | 270 / 473 | 0.629 | 0.832 |
| kron spsc-mmap-inline | 362 / 584 | 270 / 431 | 19.902 | 19.746 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 47.065 | 46.104 | 0.051 | 0.043 | 299.33 |
| foundation mmap | 67.618 | 57.481 | 0.059 | 0.050 | 299.33 |
| foundation_tracing memory | 39.297 | 46.828 | 0.010 | 0.006 | 299.33 |
| foundation_tracing mmap | 54.079 | 66.286 | 0.012 | 0.011 | 299.33 |
| kron async-memory-inline | 43.563 | 43.592 | 0.032 | 0.039 | 299.37 |
| kron async-mmap-inline | 54.924 | 57.200 | 0.039 | 0.031 | 299.37 |
| kron spsc-memory-inline | 41.172 | 38.584 | 0.024 | 0.023 | 299.03 |
| kron spsc-mmap-inline | 60.483 | 56.934 | 0.024 | 0.023 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.117 | 1.077..1.215 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.906 | 0.844..0.935 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.155 | 0.979..1.214 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.903 | 0.774..0.966 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.078 | 1.019..1.107 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 1.090 | 1.026..1.109 | kron_leads |
| async-memory-inline | foundation | 4 | sampled | 1.103 | 1.007..1.153 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.063 | 0.994..1.124 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 1.124 | 0.991..1.308 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.979 | 0.774..1.304 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.197 | 1.071..1.394 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.864 | 0.800..0.995 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.008 | 0.968..1.144 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.126 | 1.001..1.173 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.041 | 0.939..1.070 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.957 | 0.901..1.023 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.172 | 1.076..1.255 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.928 | 0.894..0.980 | peer_leads |
| spsc-memory-inline | foundation | 1 | sampled | 1.162 | 1.084..1.217 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.925 | 0.845..0.948 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.202 | 1.199..1.255 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.226 | 1.204..1.261 | kron_leads |
| spsc-memory-inline | foundation | 4 | sampled | 1.240 | 1.186..1.265 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.218 | 1.141..1.248 | kron_leads |
| spsc-mmap-inline | foundation | 1 | batch | 1.250 | 1.189..1.262 | kron_leads |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.988 | 0.977..1.379 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.289 | 1.145..1.633 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.962 | 0.846..1.167 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.207 | 1.091..1.300 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.279 | 1.221..1.336 | kron_leads |
| spsc-mmap-inline | foundation | 4 | sampled | 1.182 | 1.151..1.234 | kron_leads |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.137 | 1.058..1.160 | kron_leads |
