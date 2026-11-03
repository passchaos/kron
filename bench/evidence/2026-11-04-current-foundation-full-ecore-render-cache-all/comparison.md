# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.831 | 2.224 | 1.827 | 2.221 | 无 |
| foundation mmap | 2.095 | 2.714 | 2.092 | 2.709 | 有 |
| foundation_tracing memory | 2.207 | 2.287 | 2.204 | 2.283 | 无 |
| foundation_tracing mmap | 2.731 | 2.981 | 2.726 | 2.974 | 有 |
| kron async-memory-inline | 1.896 | 2.915 | 1.890 | 2.893 | 无 |
| kron async-memory-schema | 1.944 | 2.923 | 1.938 | 2.908 | 无 |
| kron async-mmap-inline | 1.909 | 2.890 | 1.904 | 2.866 | 有 |
| kron async-mmap-schema | 1.993 | 2.851 | 1.988 | 2.836 | 有 |
| kron spsc-memory-inline | 1.921 | 3.445 | 1.915 | 3.413 | 无 |
| kron spsc-memory-schema | 1.969 | 3.372 | 1.962 | 3.348 | 无 |
| kron spsc-mmap-inline | 1.921 | 3.356 | 1.915 | 3.331 | 有 |
| kron spsc-mmap-schema | 2.004 | 3.450 | 1.998 | 3.419 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 379 / 754 | 643 / 45,553 | 0.271 | 0.265 |
| foundation mmap | 433 / 862 | 706 / 7,276 | 14.502 | 22.725 |
| foundation_tracing memory | 286 / 670 | 674 / 45,146 | 0.283 | 0.256 |
| foundation_tracing mmap | 339 / 771 | 764 / 8,062 | 19.265 | 179.577 |
| kron async-memory-inline | 276 / 484 | 1,005 / 9,359 | 0.726 | 0.732 |
| kron async-memory-schema | 419 / 608 | 1,079 / 5,859 | 0.768 | 0.736 |
| kron async-mmap-inline | 270 / 475 | 989 / 8,398 | 15.584 | 12.388 |
| kron async-mmap-schema | 416 / 590 | 1,093 / 6,842 | 11.893 | 528.502 |
| kron spsc-memory-inline | 293 / 526 | 537 / 704 | 0.833 | 1.071 |
| kron spsc-memory-schema | 450 / 610 | 699 / 916 | 0.855 | 1.133 |
| kron spsc-mmap-inline | 290 / 498 | 544 / 735 | 618.919 | 68.674 |
| kron spsc-mmap-schema | 441 / 615 | 713 / 916 | 33.154 | 44.277 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.092 | 46.150 | 0.063 | 0.063 | 299.33 |
| foundation mmap | 62.169 | 58.861 | 0.080 | 0.072 | 299.33 |
| foundation_tracing memory | 46.322 | 44.764 | 0.012 | 0.010 | 299.33 |
| foundation_tracing mmap | 56.801 | 213.889 | 0.013 | 0.012 | 299.33 |
| kron async-memory-inline | 54.502 | 36.130 | 0.053 | 0.122 | 299.37 |
| kron async-memory-schema | 53.420 | 35.934 | 0.043 | 0.035 | 299.37 |
| kron async-mmap-inline | 67.018 | 48.123 | 0.044 | 0.110 | 299.37 |
| kron async-mmap-schema | 70.583 | 1272.550 | 0.037 | 0.068 | 299.37 |
| kron spsc-memory-inline | 53.887 | 31.293 | 0.035 | 0.029 | 299.03 |
| kron spsc-memory-schema | 52.711 | 31.918 | 0.034 | 0.029 | 299.03 |
| kron spsc-mmap-inline | 672.012 | 99.165 | 0.031 | 0.032 | 299.03 |
| kron spsc-mmap-schema | 1232.078 | 1181.504 | 0.031 | 0.031 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.058 | 0.142..1.912 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.852 | 0.119..0.889 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.138 | 1.106..1.147 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | sampled | 1.056 | 0.955..8.001 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.331 | 1.184..1.350 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.277 | 1.251..1.351 | kron_leads |
| async-memory-inline | foundation | 4 | sampled | 1.223 | 1.198..1.297 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.310 | 1.264..1.387 | kron_leads |
| async-memory-schema | foundation | 1 | batch | 1.061 | 0.162..1.970 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | batch | 0.882 | 0.126..0.891 | inconclusive |
| async-memory-schema | foundation | 1 | sampled | 1.161 | 1.122..1.180 | kron_leads |
| async-memory-schema | foundation_tracing | 1 | sampled | 1.040 | 0.973..8.291 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 1.309 | 1.166..1.365 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | batch | 1.273 | 1.248..1.385 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 1.202 | 1.043..1.264 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | sampled | 1.268 | 1.158..1.351 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 0.908 | 0.492..0.958 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.692 | 0.418..0.716 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 0.982 | 0.913..0.990 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.772 | 0.745..0.791 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 1.056 | 1.008..1.072 | kron_leads |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.964 | 0.950..1.089 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.884 | 0.787..8.646 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.923 | 0.849..0.979 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 0.951 | 0.854..0.958 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.735 | 0.672..0.740 | peer_leads |
| async-mmap-schema | foundation | 1 | sampled | 1.010 | 0.986..1.022 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.799 | 0.775..0.830 | peer_leads |
| async-mmap-schema | foundation | 4 | batch | 1.060 | 0.983..1.077 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.968 | 0.914..1.077 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.877 | 0.750..8.699 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.929 | 0.795..0.971 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.065 | 1.026..1.917 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.858 | 0.833..0.893 | peer_leads |
| spsc-memory-inline | foundation | 1 | sampled | 1.126 | 1.024..1.170 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 1.085 | 0.936..7.199 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.542 | 1.368..1.595 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.489 | 1.471..1.619 | kron_leads |
| spsc-memory-inline | foundation | 4 | sampled | 1.477 | 1.442..1.483 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.557 | 1.512..1.601 | kron_leads |
| spsc-memory-schema | foundation | 1 | batch | 1.085 | 1.073..1.984 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.888 | 0.845..0.918 | peer_leads |
| spsc-memory-schema | foundation | 1 | sampled | 1.191 | 1.174..1.205 | kron_leads |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 1.116 | 1.007..8.343 | inconclusive |
| spsc-memory-schema | foundation | 4 | batch | 1.430 | 1.418..1.556 | kron_leads |
| spsc-memory-schema | foundation_tracing | 4 | batch | 1.466 | 1.447..1.538 | kron_leads |
| spsc-memory-schema | foundation | 4 | sampled | 1.444 | 1.349..1.507 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 1.534 | 1.423..1.604 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.902 | 0.820..0.944 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.697 | 0.665..0.717 | peer_leads |
| spsc-mmap-inline | foundation | 1 | sampled | 0.988 | 0.955..1.006 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.790 | 0.725..0.821 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.214 | 1.137..1.327 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.116 | 1.087..1.234 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.059 | 0.887..9.868 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.054 | 0.993..1.172 | inconclusive |
| spsc-mmap-schema | foundation | 1 | batch | 0.944 | 0.846..0.977 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.733 | 0.667..0.760 | inconclusive |
| spsc-mmap-schema | foundation | 1 | sampled | 1.002 | 0.993..1.022 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.793 | 0.776..0.837 | peer_leads |
| spsc-mmap-schema | foundation | 4 | batch | 1.211 | 0.715..1.318 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 1.126 | 0.684..1.323 | inconclusive |
| spsc-mmap-schema | foundation | 4 | sampled | 1.037 | 0.913..10.334 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 1.104 | 1.021..1.146 | inconclusive |
