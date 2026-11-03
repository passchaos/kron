# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.788 | 2.313 | 1.786 | 2.310 | 无 |
| foundation mmap | 2.137 | 2.937 | 2.134 | 2.931 | 有 |
| foundation_tracing memory | 1.981 | 2.221 | 1.978 | 2.218 | 无 |
| foundation_tracing mmap | 2.745 | 2.916 | 2.740 | 2.909 | 有 |
| kron async-memory-inline | 1.783 | 2.211 | 1.779 | 2.205 | 无 |
| kron async-memory-schema | 1.993 | 1.834 | 1.987 | 1.828 | 无 |
| kron async-mmap-inline | 1.841 | 2.669 | 1.835 | 2.654 | 有 |
| kron async-mmap-schema | 1.940 | 1.864 | 1.935 | 1.860 | 有 |
| kron spsc-memory-inline | 1.879 | 1.931 | 1.874 | 1.925 | 无 |
| kron spsc-memory-schema | 1.990 | 1.957 | 1.984 | 1.950 | 无 |
| kron spsc-mmap-inline | 1.882 | 1.797 | 1.877 | 1.791 | 有 |
| kron spsc-mmap-schema | 1.954 | 1.977 | 1.948 | 1.969 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 411 / 771 | 599 / 46,991 | 0.298 | 0.321 |
| foundation mmap | 457 / 917 | 534 / 7,474 | 23.107 | 21.883 |
| foundation_tracing memory | 296 / 722 | 572 / 47,905 | 0.264 | 0.289 |
| foundation_tracing mmap | 341 / 798 | 770 / 8,752 | 27.328 | 209.456 |
| kron async-memory-inline | 291 / 534 | 864 / 1,383 | 0.785 | 0.814 |
| kron async-memory-schema | 427 / 639 | 826 / 35,505 | 0.791 | 0.747 |
| kron async-mmap-inline | 278 / 526 | 974 / 8,913 | 21.557 | 13.932 |
| kron async-mmap-schema | 418 / 609 | 686 / 24,462 | 301.869 | 392.637 |
| kron spsc-memory-inline | 305 / 558 | 285 / 435 | 0.867 | 1.092 |
| kron spsc-memory-schema | 448 / 608 | 425 / 599 | 0.877 | 1.143 |
| kron spsc-mmap-inline | 297 / 541 | 288 / 446 | 157.531 | 51.790 |
| kron spsc-mmap-schema | 453 / 637 | 434 / 600 | 306.719 | 54.228 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 57.965 | 44.382 | 0.066 | 0.057 | 299.33 |
| foundation mmap | 70.712 | 61.793 | 0.072 | 0.081 | 299.33 |
| foundation_tracing memory | 51.585 | 46.195 | 0.012 | 0.012 | 299.33 |
| foundation_tracing mmap | 66.669 | 244.487 | 0.013 | 0.012 | 299.33 |
| kron async-memory-inline | 57.900 | 47.172 | 0.044 | 0.035 | 299.37 |
| kron async-memory-schema | 51.923 | 56.497 | 0.045 | 0.043 | 299.37 |
| kron async-mmap-inline | 81.787 | 51.622 | 0.040 | 0.040 | 299.37 |
| kron async-mmap-schema | 366.041 | 449.210 | 0.042 | 0.040 | 299.37 |
| kron spsc-memory-inline | 55.115 | 53.875 | 0.033 | 0.031 | 299.03 |
| kron spsc-memory-schema | 52.120 | 53.352 | 0.039 | 0.039 | 299.03 |
| kron spsc-mmap-inline | 210.939 | 108.481 | 0.030 | 0.034 | 299.03 |
| kron spsc-mmap-schema | 902.385 | 1071.322 | 0.035 | 0.039 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.052 | 0.875..1.258 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.875 | 0.809..0.920 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.181 | 0.219..1.374 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.938 | 0.188..1.038 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 0.972 | 0.929..1.156 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 0.968 | 0.952..1.192 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.055 | 0.890..1.197 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.088 | 0.957..1.146 | inconclusive |
| async-memory-schema | foundation | 1 | batch | 1.128 | 1.097..1.243 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | batch | 0.913 | 0.854..1.043 | inconclusive |
| async-memory-schema | foundation | 1 | sampled | 1.280 | 1.096..1.305 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.995 | 0.983..1.067 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 0.790 | 0.772..0.791 | peer_leads |
| async-memory-schema | foundation_tracing | 4 | batch | 0.797 | 0.786..0.874 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 0.799 | 0.748..0.916 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | sampled | 0.824 | 0.803..0.902 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 0.837 | 0.658..0.915 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.642 | 0.565..0.713 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 0.927 | 0.904..0.973 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.738 | 0.693..0.758 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 0.842 | 0.650..0.979 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.906 | 0.767..0.912 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.886 | 0.799..1.007 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.816 | 0.764..1.015 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 0.911 | 0.800..0.926 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.705 | 0.651..0.721 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 0.997 | 0.961..1.033 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.787 | 0.748..0.816 | peer_leads |
| async-mmap-schema | foundation | 4 | batch | 0.617 | 0.395..0.729 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.630 | 0.428..0.799 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.606 | 0.372..0.780 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.616 | 0.327..0.694 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.051 | 0.915..1.348 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.846 | 0.798..0.986 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.285 | 0.858..1.310 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.970 | 0.817..1.125 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 0.831 | 0.722..0.883 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.854 | 0.810..0.879 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 0.843 | 0.805..0.947 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.875 | 0.859..0.887 | inconclusive |
| spsc-memory-schema | foundation | 1 | batch | 1.139 | 1.107..1.365 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.948 | 0.885..1.024 | inconclusive |
| spsc-memory-schema | foundation | 1 | sampled | 1.300 | 1.042..1.376 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 0.992 | 0.982..1.159 | inconclusive |
| spsc-memory-schema | foundation | 4 | batch | 0.844 | 0.822..0.850 | peer_leads |
| spsc-memory-schema | foundation_tracing | 4 | batch | 0.852 | 0.845..0.926 | inconclusive |
| spsc-memory-schema | foundation | 4 | sampled | 0.878 | 0.858..0.994 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 0.906 | 0.902..0.937 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.877 | 0.608..0.909 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.667 | 0.522..0.696 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 0.969 | 0.619..1.009 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.758 | 0.482..0.781 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 0.619 | 0.565..0.702 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.632 | 0.554..0.805 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.627 | 0.564..0.791 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.632 | 0.554..0.716 | inconclusive |
| spsc-mmap-schema | foundation | 1 | batch | 0.900 | 0.766..0.933 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.710 | 0.644..0.724 | inconclusive |
| spsc-mmap-schema | foundation | 1 | sampled | 0.961 | 0.881..1.043 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.737 | 0.685..0.808 | inconclusive |
| spsc-mmap-schema | foundation | 4 | batch | 0.668 | 0.557..0.807 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 0.666 | 0.604..0.838 | inconclusive |
| spsc-mmap-schema | foundation | 4 | sampled | 0.709 | 0.618..0.772 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 0.653 | 0.610..0.761 | inconclusive |
