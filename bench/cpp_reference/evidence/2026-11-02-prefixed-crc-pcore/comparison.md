# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.042 | 2.312 | 2.040 | 2.310 | 无 |
| foundation mmap | 2.225 | 2.294 | 2.219 | 2.291 | 有 |
| foundation_tracing memory | 2.570 | 2.208 | 2.567 | 2.206 | 无 |
| foundation_tracing mmap | 2.653 | 2.422 | 2.649 | 2.420 | 有 |
| kron async-memory-inline | 2.135 | 2.194 | 2.131 | 2.190 | 无 |
| kron async-mmap-inline | 2.237 | 2.128 | 2.232 | 2.123 | 有 |
| kron spsc-memory-inline | 1.927 | 2.483 | 1.923 | 2.473 | 无 |
| kron spsc-mmap-inline | 2.120 | 2.530 | 2.115 | 2.522 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 360 / 610 | 715 / 33,292 | 0.193 | 0.211 |
| foundation mmap | 469 / 909 | 748 / 3,500 | 12.244 | 15.842 |
| foundation_tracing memory | 236 / 520 | 709 / 33,180 | 0.209 | 0.177 |
| foundation_tracing mmap | 317 / 840 | 858 / 9,605 | 14.594 | 14.529 |
| kron async-memory-inline | 418 / 704 | 856 / 23,800 | 0.581 | 0.575 |
| kron async-mmap-inline | 413 / 708 | 874 / 23,466 | 10.833 | 13.525 |
| kron spsc-memory-inline | 332 / 657 | 280 / 473 | 0.621 | 0.841 |
| kron spsc-mmap-inline | 324 / 628 | 289 / 566 | 13.477 | 19.409 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 49.940 | 44.220 | 0.048 | 0.042 | 299.33 |
| foundation mmap | 59.075 | 57.717 | 0.067 | 0.053 | 299.33 |
| foundation_tracing memory | 39.886 | 46.292 | 0.008 | 0.007 | 299.33 |
| foundation_tracing mmap | 54.242 | 58.915 | 0.012 | 0.007 | 299.33 |
| kron async-memory-inline | 48.192 | 46.959 | 0.038 | 0.028 | 299.37 |
| kron async-mmap-inline | 57.194 | 60.071 | 0.027 | 0.022 | 299.37 |
| kron spsc-memory-inline | 53.480 | 42.085 | 0.020 | 0.026 | 299.03 |
| kron spsc-mmap-inline | 62.721 | 70.684 | 0.023 | 0.022 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.017 | 0.872..1.117 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.833 | 0.806..0.892 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.168 | 0.948..1.456 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.820 | 0.754..0.986 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 0.948 | 0.888..1.022 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 0.992 | 0.963..1.047 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 0.973 | 0.879..1.022 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.965 | 0.874..1.069 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 0.996 | 0.936..1.059 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.842 | 0.726..1.097 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.035 | 0.878..1.254 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.814 | 0.735..1.063 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 0.946 | 0.787..0.987 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.881 | 0.831..0.918 | peer_leads |
| async-mmap-inline | foundation | 4 | sampled | 0.914 | 0.835..1.021 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.925 | 0.858..0.943 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 0.980 | 0.832..1.193 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.800 | 0.736..0.953 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.240 | 1.179..1.423 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.931 | 0.780..1.028 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.070 | 1.025..1.122 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.124 | 1.019..1.161 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 1.146 | 1.093..1.233 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.125 | 1.097..1.185 | kron_leads |
| spsc-mmap-inline | foundation | 1 | batch | 0.916 | 0.757..1.118 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.798 | 0.552..1.142 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.192 | 1.056..1.559 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.913 | 0.831..1.460 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.078 | 0.812..1.190 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.017 | 0.788..1.106 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.070 | 0.945..1.183 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.072 | 0.971..1.138 | inconclusive |
