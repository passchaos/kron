# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.867 | 2.273 | 1.864 | 2.271 | 无 |
| foundation mmap | 2.095 | 2.458 | 2.085 | 2.454 | 有 |
| foundation_tracing memory | 2.208 | 2.282 | 2.203 | 2.279 | 无 |
| foundation_tracing mmap | 2.818 | 2.898 | 2.809 | 2.892 | 有 |
| kron async-memory-inline | 1.874 | 1.752 | 1.865 | 1.746 | 无 |
| kron async-mmap-inline | 1.871 | 1.752 | 1.866 | 1.749 | 有 |
| kron spsc-memory-inline | 1.944 | 1.994 | 1.937 | 1.987 | 无 |
| kron spsc-mmap-inline | 1.936 | 2.016 | 1.927 | 2.010 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 379 / 714 | 642 / 45,821 | 0.269 | 0.283 |
| foundation mmap | 438 / 864 | 756 / 8,224 | 12.167 | 12.536 |
| foundation_tracing memory | 286 / 621 | 682 / 46,277 | 0.235 | 0.238 |
| foundation_tracing mmap | 342 / 796 | 746 / 7,868 | 12.514 | 12.124 |
| kron async-memory-inline | 323 / 539 | 828 / 45,085 | 0.751 | 0.717 |
| kron async-mmap-inline | 317 / 533 | 819 / 45,990 | 10.576 | 14.518 |
| kron spsc-memory-inline | 309 / 528 | 287 / 468 | 0.790 | 1.062 |
| kron spsc-mmap-inline | 312 / 516 | 281 / 456 | 12.994 | 19.138 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 54.794 | 45.135 | 0.101 | 0.055 | 299.33 |
| foundation mmap | 58.525 | 54.325 | 0.126 | 0.064 | 299.33 |
| foundation_tracing memory | 46.513 | 44.939 | 0.013 | 0.012 | 299.33 |
| foundation_tracing mmap | 49.336 | 48.576 | 0.011 | 0.011 | 299.33 |
| kron async-memory-inline | 55.355 | 59.130 | 0.150 | 0.094 | 299.37 |
| kron async-mmap-inline | 67.137 | 70.571 | 0.124 | 0.031 | 299.37 |
| kron spsc-memory-inline | 53.315 | 52.299 | 0.028 | 0.029 | 299.03 |
| kron spsc-mmap-inline | 65.630 | 69.805 | 0.032 | 0.023 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.009 | 0.969..1.037 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.847 | 0.822..0.858 | peer_leads |
| async-memory-inline | foundation | 1 | sampled | 1.096 | 1.032..1.119 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.935 | 0.892..0.951 | peer_leads |
| async-memory-inline | foundation | 4 | batch | 0.758 | 0.738..0.800 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 0.769 | 0.750..0.793 | peer_leads |
| async-memory-inline | foundation | 4 | sampled | 0.764 | 0.749..0.796 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.790 | 0.748..0.821 | peer_leads |
| async-mmap-inline | foundation | 1 | batch | 0.892 | 0.807..0.910 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.658 | 0.633..0.693 | peer_leads |
| async-mmap-inline | foundation | 1 | sampled | 0.952 | 0.928..0.969 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.756 | 0.733..0.774 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 0.676 | 0.591..0.741 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.616 | 0.592..0.660 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.584 | 0.555..0.654 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.561 | 0.515..0.596 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.037 | 1.002..1.079 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.878 | 0.844..0.891 | peer_leads |
| spsc-memory-inline | foundation | 1 | sampled | 1.119 | 1.114..1.149 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.956 | 0.936..0.977 | peer_leads |
| spsc-memory-inline | foundation | 4 | batch | 0.867 | 0.662..0.910 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.872 | 0.684..0.931 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 0.883 | 0.851..0.908 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.897 | 0.851..0.933 | peer_leads |
| spsc-mmap-inline | foundation | 1 | batch | 0.921 | 0.869..0.942 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.686 | 0.679..0.700 | peer_leads |
| spsc-mmap-inline | foundation | 1 | sampled | 0.990 | 0.982..1.009 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.791 | 0.766..0.797 | peer_leads |
| spsc-mmap-inline | foundation | 4 | batch | 0.819 | 0.671..0.825 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.699 | 0.674..0.806 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.690 | 0.634..0.726 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.633 | 0.607..0.678 | inconclusive |
