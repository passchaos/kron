# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.822 | 2.425 | 1.820 | 2.422 | 无 |
| foundation mmap | 2.176 | 3.213 | 2.172 | 3.206 | 有 |
| foundation_tracing memory | 2.226 | 2.245 | 2.203 | 2.242 | 无 |
| foundation_tracing mmap | 2.830 | 2.805 | 2.825 | 2.800 | 有 |
| kron async-memory-inline | 1.838 | 1.768 | 1.831 | 1.763 | 无 |
| kron async-memory-schema | 1.857 | 1.791 | 1.850 | 1.787 | 无 |
| kron async-mmap-inline | 1.849 | 1.747 | 1.845 | 1.743 | 有 |
| kron async-mmap-schema | 1.885 | 1.807 | 1.879 | 1.797 | 有 |
| kron spsc-memory-inline | 1.919 | 1.954 | 1.915 | 1.948 | 无 |
| kron spsc-memory-schema | 1.909 | 2.003 | 1.904 | 1.996 | 无 |
| kron spsc-mmap-inline | 1.960 | 1.971 | 1.954 | 1.964 | 有 |
| kron spsc-mmap-schema | 1.876 | 2.011 | 1.871 | 2.002 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 376 / 681 | 588 / 45,214 | 0.268 | 0.264 |
| foundation mmap | 438 / 950 | 739 / 8,148 | 21.861 | 21.401 |
| foundation_tracing memory | 286 / 643 | 689 / 45,382 | 0.233 | 0.239 |
| foundation_tracing mmap | 340 / 773 | 780 / 8,254 | 25.223 | 23.171 |
| kron async-memory-inline | 276 / 530 | 809 / 46,271 | 0.732 | 0.740 |
| kron async-memory-schema | 418 / 705 | 869 / 41,489 | 0.730 | 0.716 |
| kron async-mmap-inline | 280 / 577 | 809 / 45,452 | 920.351 | 17.347 |
| kron async-mmap-schema | 423 / 730 | 840 / 41,076 | 8.594 | 16.767 |
| kron spsc-memory-inline | 294 / 505 | 282 / 444 | 0.836 | 1.103 |
| kron spsc-memory-schema | 453 / 642 | 434 / 590 | 0.808 | 1.118 |
| kron spsc-mmap-inline | 292 / 496 | 282 / 443 | 28.772 | 418.150 |
| kron spsc-mmap-schema | 450 / 643 | 432 / 582 | 22.135 | 51.969 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.064 | 42.363 | 0.065 | 0.057 | 299.33 |
| foundation mmap | 69.323 | 54.179 | 0.085 | 0.072 | 299.33 |
| foundation_tracing memory | 46.532 | 45.585 | 0.011 | 0.010 | 299.33 |
| foundation_tracing mmap | 62.515 | 60.137 | 0.012 | 0.009 | 299.33 |
| kron async-memory-inline | 56.218 | 58.293 | 0.045 | 0.036 | 299.37 |
| kron async-memory-schema | 55.718 | 57.662 | 0.106 | 0.035 | 299.37 |
| kron async-mmap-inline | 975.358 | 75.661 | 0.037 | 0.033 | 299.37 |
| kron async-mmap-schema | 71.034 | 89.282 | 0.039 | 0.032 | 299.37 |
| kron spsc-memory-inline | 53.942 | 53.237 | 0.035 | 0.029 | 299.03 |
| kron spsc-memory-schema | 54.127 | 52.059 | 0.034 | 0.033 | 299.03 |
| kron spsc-mmap-inline | 79.687 | 469.194 | 0.032 | 0.029 | 299.03 |
| kron spsc-mmap-schema | 112.351 | 1218.809 | 0.035 | 0.031 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.006 | 0.993..1.019 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.839 | 0.798..1.312 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.095 | 1.009..7.569 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.909 | 0.876..0.920 | peer_leads |
| async-memory-inline | foundation | 4 | batch | 0.732 | 0.724..0.774 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 0.787 | 0.746..0.812 | peer_leads |
| async-memory-inline | foundation | 4 | sampled | 0.732 | 0.671..0.746 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.772 | 0.751..0.820 | peer_leads |
| async-memory-schema | foundation | 1 | batch | 1.015 | 1.012..1.034 | kron_leads |
| async-memory-schema | foundation_tracing | 1 | batch | 0.847 | 0.814..1.323 | inconclusive |
| async-memory-schema | foundation | 1 | sampled | 1.087 | 1.035..7.678 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.916 | 0.886..0.930 | peer_leads |
| async-memory-schema | foundation | 4 | batch | 0.742 | 0.732..0.778 | peer_leads |
| async-memory-schema | foundation_tracing | 4 | batch | 0.793 | 0.762..0.817 | peer_leads |
| async-memory-schema | foundation | 4 | sampled | 0.745 | 0.708..0.767 | peer_leads |
| async-memory-schema | foundation_tracing | 4 | sampled | 0.794 | 0.777..0.818 | peer_leads |
| async-mmap-inline | foundation | 1 | batch | 0.848 | 0.836..0.871 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.653 | 0.617..0.679 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 0.967 | 0.949..0.978 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.751 | 0.737..0.767 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 0.538 | 0.519..0.550 | peer_leads |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.623 | 0.603..0.647 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.591 | 0.541..0.643 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.612 | 0.578..0.701 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 0.867 | 0.838..0.871 | peer_leads |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.655 | 0.622..0.689 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 0.956 | 0.897..0.968 | peer_leads |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.744 | 0.696..0.765 | peer_leads |
| async-mmap-schema | foundation | 4 | batch | 0.552 | 0.539..0.585 | peer_leads |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.646 | 0.617..0.686 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.599 | 0.560..0.664 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.631 | 0.596..0.731 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.058 | 1.019..1.066 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.860 | 0.819..1.380 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.115 | 1.107..7.963 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.942 | 0.933..0.962 | peer_leads |
| spsc-memory-inline | foundation | 4 | batch | 0.804 | 0.781..0.841 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.859 | 0.809..0.883 | peer_leads |
| spsc-memory-inline | foundation | 4 | sampled | 0.826 | 0.096..0.853 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.873 | 0.105..0.895 | inconclusive |
| spsc-memory-schema | foundation | 1 | batch | 1.036 | 1.018..1.076 | kron_leads |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.865 | 0.836..1.327 | inconclusive |
| spsc-memory-schema | foundation | 1 | sampled | 1.085 | 0.133..7.596 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 0.912 | 0.111..0.918 | inconclusive |
| spsc-memory-schema | foundation | 4 | batch | 0.826 | 0.819..0.876 | peer_leads |
| spsc-memory-schema | foundation_tracing | 4 | batch | 0.885 | 0.845..0.920 | peer_leads |
| spsc-memory-schema | foundation | 4 | sampled | 0.833 | 0.800..0.873 | peer_leads |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 0.895 | 0.875..0.915 | peer_leads |
| spsc-mmap-inline | foundation | 1 | batch | 0.909 | 0.854..0.929 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.667 | 0.658..0.733 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.002 | 0.955..1.032 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.787 | 0.740..0.818 | peer_leads |
| spsc-mmap-inline | foundation | 4 | batch | 0.611 | 0.575..0.635 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.694 | 0.685..0.747 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.655 | 0.619..0.739 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.688 | 0.664..0.806 | inconclusive |
| spsc-mmap-schema | foundation | 1 | batch | 0.851 | 0.847..0.906 | peer_leads |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.662 | 0.620..0.683 | inconclusive |
| spsc-mmap-schema | foundation | 1 | sampled | 0.970 | 0.953..0.990 | peer_leads |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.760 | 0.739..0.771 | peer_leads |
| spsc-mmap-schema | foundation | 4 | batch | 0.615 | 0.598..0.649 | peer_leads |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 0.722 | 0.683..0.764 | inconclusive |
| spsc-mmap-schema | foundation | 4 | sampled | 0.667 | 0.632..0.732 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 0.702 | 0.658..0.818 | inconclusive |
