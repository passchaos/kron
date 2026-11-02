# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.812 | 2.274 | 1.808 | 2.272 | 无 |
| foundation mmap | 2.054 | 2.915 | 2.048 | 2.909 | 有 |
| foundation_tracing memory | 2.209 | 2.241 | 2.206 | 2.238 | 无 |
| foundation_tracing mmap | 2.689 | 2.593 | 2.684 | 2.589 | 有 |
| kron async-memory-inline | 1.847 | 1.782 | 1.843 | 1.776 | 无 |
| kron async-mmap-inline | 1.873 | 1.751 | 1.868 | 1.748 | 有 |
| kron spsc-memory-inline | 1.937 | 1.995 | 1.932 | 1.989 | 无 |
| kron spsc-mmap-inline | 1.925 | 2.002 | 1.918 | 1.995 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 373 / 692 | 599 / 45,259 | 0.276 | 0.257 |
| foundation mmap | 433 / 884 | 778 / 8,361 | 19.437 | 19.539 |
| foundation_tracing memory | 287 / 633 | 681 / 45,020 | 0.254 | 0.244 |
| foundation_tracing mmap | 337 / 782 | 782 / 8,353 | 13.327 | 20.088 |
| kron async-memory-inline | 383 / 589 | 820 / 46,058 | 0.711 | 0.719 |
| kron async-mmap-inline | 396 / 632 | 832 / 45,379 | 11.495 | 11.537 |
| kron spsc-memory-inline | 293 / 505 | 281 / 452 | 0.848 | 1.055 |
| kron spsc-mmap-inline | 295 / 489 | 278 / 452 | 19.923 | 37.795 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.520 | 45.210 | 0.096 | 0.054 | 299.33 |
| foundation mmap | 68.722 | 55.028 | 0.143 | 0.061 | 299.33 |
| foundation_tracing memory | 46.500 | 45.803 | 0.012 | 0.008 | 299.33 |
| foundation_tracing mmap | 51.186 | 57.155 | 0.012 | 0.011 | 299.33 |
| kron async-memory-inline | 56.190 | 57.882 | 0.112 | 0.096 | 299.37 |
| kron async-mmap-inline | 66.537 | 69.985 | 0.036 | 0.093 | 299.37 |
| kron spsc-memory-inline | 53.488 | 52.250 | 0.031 | 0.031 | 299.03 |
| kron spsc-mmap-inline | 72.224 | 88.527 | 0.030 | 0.027 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.019 | 0.984..1.036 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.838 | 0.831..0.851 | peer_leads |
| async-memory-inline | foundation | 1 | sampled | 1.093 | 1.076..1.111 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.934 | 0.923..0.952 | peer_leads |
| async-memory-inline | foundation | 4 | batch | 0.787 | 0.741..0.800 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 0.785 | 0.774..0.801 | peer_leads |
| async-memory-inline | foundation | 4 | sampled | 0.741 | 0.720..0.758 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.793 | 0.739..0.822 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 0.905 | 0.898..0.913 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.694 | 0.679..0.723 | peer_leads |
| async-mmap-inline | foundation | 1 | sampled | 0.950 | 0.934..0.963 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.762 | 0.741..0.772 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 0.607 | 0.580..0.680 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.660 | 0.635..0.743 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.608 | 0.576..0.673 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.615 | 0.567..0.645 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.065 | 1.017..1.090 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.877 | 0.859..0.888 | peer_leads |
| spsc-memory-inline | foundation | 1 | sampled | 1.127 | 1.116..1.154 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.973 | 0.943..1.005 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 0.875 | 0.831..0.896 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.890 | 0.860..0.899 | peer_leads |
| spsc-memory-inline | foundation | 4 | sampled | 0.862 | 0.810..0.877 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.900 | 0.833..0.963 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.939 | 0.930..0.949 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.721 | 0.704..0.741 | peer_leads |
| spsc-mmap-inline | foundation | 1 | sampled | 0.985 | 0.962..0.998 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.788 | 0.758..0.811 | peer_leads |
| spsc-mmap-inline | foundation | 4 | batch | 0.686 | 0.660..0.759 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.751 | 0.724..0.829 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.707 | 0.645..0.750 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.715 | 0.654..0.722 | peer_leads |
