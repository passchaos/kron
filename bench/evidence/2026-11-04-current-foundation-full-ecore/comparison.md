# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.772 | 2.316 | 1.771 | 2.313 | 无 |
| foundation mmap | 2.322 | 3.223 | 2.317 | 3.216 | 有 |
| foundation_tracing memory | 2.159 | 2.169 | 2.156 | 2.166 | 无 |
| foundation_tracing mmap | 2.781 | 2.782 | 2.770 | 2.777 | 有 |
| kron async-memory-inline | 1.915 | 1.808 | 1.910 | 1.802 | 无 |
| kron async-memory-schema | 2.010 | 1.874 | 2.005 | 1.867 | 无 |
| kron async-mmap-inline | 1.924 | 1.794 | 1.918 | 1.790 | 有 |
| kron async-mmap-schema | 2.039 | 1.904 | 2.029 | 1.899 | 有 |
| kron spsc-memory-inline | 1.940 | 2.011 | 1.935 | 2.004 | 无 |
| kron spsc-memory-schema | 2.018 | 2.088 | 2.012 | 2.076 | 无 |
| kron spsc-mmap-inline | 1.959 | 2.024 | 1.953 | 2.017 | 有 |
| kron spsc-mmap-schema | 2.021 | 2.105 | 2.016 | 2.096 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 378 / 742 | 577 / 45,938 | 0.276 | 0.297 |
| foundation mmap | 443 / 974 | 804 / 8,349 | 15.648 | 872.405 |
| foundation_tracing memory | 286 / 645 | 679 / 45,748 | 0.249 | 0.248 |
| foundation_tracing mmap | 342 / 783 | 810 / 8,592 | 21.348 | 23.600 |
| kron async-memory-inline | 342 / 530 | 796 / 44,355 | 0.722 | 0.755 |
| kron async-memory-schema | 416 / 592 | 867 / 37,468 | 0.743 | 0.749 |
| kron async-mmap-inline | 348 / 519 | 794 / 43,390 | 15.563 | 461.932 |
| kron async-mmap-schema | 418 / 596 | 873 / 37,701 | 13.308 | 11.590 |
| kron spsc-memory-inline | 312 / 518 | 283 / 459 | 0.836 | 1.066 |
| kron spsc-memory-schema | 450 / 613 | 438 / 606 | 0.862 | 1.093 |
| kron spsc-mmap-inline | 322 / 517 | 288 / 460 | 18.214 | 54.261 |
| kron spsc-mmap-schema | 448 / 597 | 427 / 603 | 1223.072 | 354.955 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 57.664 | 44.456 | 0.065 | 0.058 | 299.33 |
| foundation mmap | 62.916 | 904.501 | 0.079 | 0.068 | 299.33 |
| foundation_tracing memory | 47.316 | 47.139 | 0.013 | 0.009 | 299.33 |
| foundation_tracing mmap | 57.770 | 63.671 | 0.012 | 0.011 | 299.33 |
| kron async-memory-inline | 53.973 | 57.178 | 0.043 | 0.082 | 299.37 |
| kron async-memory-schema | 51.496 | 55.131 | 0.140 | 0.041 | 299.37 |
| kron async-mmap-inline | 68.290 | 517.525 | 0.038 | 0.040 | 299.37 |
| kron async-mmap-schema | 72.300 | 72.491 | 0.039 | 0.034 | 299.37 |
| kron spsc-memory-inline | 53.301 | 51.811 | 0.034 | 0.031 | 299.03 |
| kron spsc-memory-schema | 51.423 | 50.191 | 0.030 | 0.033 | 299.03 |
| kron spsc-mmap-inline | 70.199 | 104.280 | 0.034 | 0.031 | 299.03 |
| kron spsc-mmap-schema | 1275.665 | 701.502 | 0.034 | 0.031 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.068 | 1.054..1.084 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | batch | 0.887 | 0.854..0.907 | peer_leads |
| async-memory-inline | foundation | 1 | sampled | 1.137 | 1.114..1.180 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.974 | 0.963..0.989 | peer_leads |
| async-memory-inline | foundation | 4 | batch | 0.773 | 0.740..0.819 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 0.826 | 0.806..2.287 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 0.762 | 0.718..0.780 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.848 | 0.792..1.579 | inconclusive |
| async-memory-schema | foundation | 1 | batch | 1.140 | 1.103..1.201 | kron_leads |
| async-memory-schema | foundation_tracing | 1 | batch | 0.938 | 0.890..1.005 | inconclusive |
| async-memory-schema | foundation | 1 | sampled | 1.183 | 1.140..1.218 | kron_leads |
| async-memory-schema | foundation_tracing | 1 | sampled | 1.009 | 0.991..1.017 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 0.806 | 0.771..0.867 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | batch | 0.862 | 0.854..2.413 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 0.802 | 0.790..0.833 | peer_leads |
| async-memory-schema | foundation_tracing | 4 | sampled | 0.899 | 0.867..1.659 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 0.828 | 0.771..0.943 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.711 | 0.670..12.643 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.010 | 0.890..1.018 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.774 | 0.752..0.799 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 0.554 | 0.551..0.580 | peer_leads |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.639 | 0.622..0.705 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.653 | 0.607..0.688 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.665 | 0.633..0.685 | peer_leads |
| async-mmap-schema | foundation | 1 | batch | 0.871 | 0.853..0.958 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.741 | 0.728..13.474 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 1.066 | 0.959..1.101 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.826 | 0.811..0.845 | peer_leads |
| async-mmap-schema | foundation | 4 | batch | 0.594 | 0.581..0.618 | peer_leads |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.688 | 0.671..0.742 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.685 | 0.648..0.716 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.702 | 0.664..0.730 | peer_leads |
| spsc-memory-inline | foundation | 1 | batch | 1.093 | 1.063..1.158 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.903 | 0.873..0.969 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.161 | 1.141..1.198 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.995 | 0.968..1.022 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 0.865 | 0.842..0.892 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.925 | 0.855..2.604 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 0.845 | 0.829..0.877 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.935 | 0.916..1.815 | inconclusive |
| spsc-memory-schema | foundation | 1 | batch | 1.125 | 1.103..1.205 | kron_leads |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.920 | 0.911..1.008 | inconclusive |
| spsc-memory-schema | foundation | 1 | sampled | 1.191 | 1.157..1.246 | kron_leads |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 1.020 | 1.014..1.031 | kron_leads |
| spsc-memory-schema | foundation | 4 | batch | 0.908 | 0.852..0.925 | peer_leads |
| spsc-memory-schema | foundation_tracing | 4 | batch | 0.959 | 0.897..2.734 | inconclusive |
| spsc-memory-schema | foundation | 4 | sampled | 0.880 | 0.837..0.916 | peer_leads |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 0.958 | 0.943..1.894 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.859 | 0.816..0.917 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.709 | 0.682..12.931 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.036 | 0.888..1.050 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.790 | 0.751..0.806 | peer_leads |
| spsc-mmap-inline | foundation | 4 | batch | 0.629 | 0.614..0.646 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.729 | 0.701..0.782 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.704 | 0.683..0.754 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.740 | 0.716..0.768 | peer_leads |
| spsc-mmap-schema | foundation | 1 | batch | 0.870 | 0.829..0.962 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.733 | 0.720..13.286 | inconclusive |
| spsc-mmap-schema | foundation | 1 | sampled | 1.074 | 0.965..1.115 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.842 | 0.809..0.858 | peer_leads |
| spsc-mmap-schema | foundation | 4 | batch | 0.658 | 0.646..0.664 | peer_leads |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 0.766 | 0.720..0.824 | inconclusive |
| spsc-mmap-schema | foundation | 4 | sampled | 0.763 | 0.707..0.781 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 0.778 | 0.748..0.794 | peer_leads |
