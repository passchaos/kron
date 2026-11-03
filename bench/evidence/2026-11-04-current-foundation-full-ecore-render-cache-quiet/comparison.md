# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.828 | 2.470 | 1.826 | 2.467 | 无 |
| foundation mmap | 2.133 | 2.817 | 2.122 | 2.812 | 有 |
| foundation_tracing memory | 2.249 | 2.282 | 2.246 | 2.279 | 无 |
| foundation_tracing mmap | 2.839 | 3.086 | 2.827 | 3.080 | 有 |
| kron async-memory-inline | 1.956 | 2.978 | 1.951 | 2.965 | 无 |
| kron async-memory-schema | 2.017 | 3.014 | 2.010 | 3.002 | 无 |
| kron async-mmap-inline | 1.943 | 3.015 | 1.938 | 3.004 | 有 |
| kron async-mmap-schema | 1.995 | 3.002 | 1.987 | 2.991 | 有 |
| kron spsc-memory-inline | 1.974 | 3.435 | 1.969 | 3.410 | 无 |
| kron spsc-memory-schema | 2.031 | 3.423 | 2.022 | 3.394 | 无 |
| kron spsc-mmap-inline | 1.982 | 3.519 | 1.972 | 3.481 | 有 |
| kron spsc-mmap-schema | 1.989 | 3.547 | 1.979 | 3.518 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 370 / 728 | 650 / 45,174 | 0.257 | 0.254 |
| foundation mmap | 431 / 852 | 707 / 7,336 | 19.969 | 21.166 |
| foundation_tracing memory | 284 / 621 | 656 / 44,610 | 0.245 | 0.236 |
| foundation_tracing mmap | 338 / 759 | 761 / 7,545 | 23.329 | 26.030 |
| kron async-memory-inline | 273 / 472 | 988 / 9,516 | 0.691 | 0.698 |
| kron async-memory-schema | 402 / 603 | 1,101 / 5,756 | 0.696 | 0.715 |
| kron async-mmap-inline | 274 / 481 | 991 / 9,270 | 16.654 | 13.235 |
| kron async-mmap-schema | 411 / 592 | 1,106 / 6,436 | 413.359 | 60.136 |
| kron spsc-memory-inline | 292 / 490 | 523 / 678 | 0.806 | 1.062 |
| kron spsc-memory-schema | 446 / 598 | 695 / 858 | 0.813 | 1.079 |
| kron spsc-mmap-inline | 283 / 475 | 541 / 684 | 157.565 | 122.933 |
| kron spsc-mmap-schema | 434 / 601 | 693 / 855 | 36.181 | 48.858 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 55.965 | 41.676 | 0.062 | 0.054 | 299.33 |
| foundation mmap | 64.113 | 57.392 | 0.074 | 0.066 | 299.33 |
| foundation_tracing memory | 45.347 | 45.112 | 0.011 | 0.009 | 299.33 |
| foundation_tracing mmap | 60.387 | 60.115 | 0.013 | 0.010 | 299.33 |
| kron async-memory-inline | 52.683 | 35.190 | 0.042 | 0.060 | 299.37 |
| kron async-memory-schema | 51.284 | 34.878 | 0.075 | 0.073 | 299.37 |
| kron async-mmap-inline | 68.475 | 47.670 | 0.034 | 0.100 | 299.37 |
| kron async-mmap-schema | 466.733 | 100.521 | 0.092 | 0.034 | 299.37 |
| kron spsc-memory-inline | 52.412 | 31.251 | 0.029 | 0.029 | 299.03 |
| kron spsc-memory-schema | 51.087 | 31.454 | 0.033 | 0.028 | 299.03 |
| kron spsc-mmap-inline | 211.085 | 152.784 | 0.033 | 0.034 | 299.03 |
| kron spsc-mmap-schema | 462.954 | 1224.481 | 0.034 | 0.030 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.062 | 0.985..1.092 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.877 | 0.808..0.886 | peer_leads |
| async-memory-inline | foundation | 1 | sampled | 1.121 | 1.093..1.151 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.963 | 0.946..0.980 | peer_leads |
| async-memory-inline | foundation | 4 | batch | 1.202 | 1.180..1.274 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 1.324 | 1.286..1.400 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.303 | 1.279..1.342 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.296 | 1.228..1.329 | kron_leads |
| async-memory-schema | foundation | 1 | batch | 1.085 | 1.067..1.114 | kron_leads |
| async-memory-schema | foundation_tracing | 1 | batch | 0.884 | 0.865..0.914 | peer_leads |
| async-memory-schema | foundation | 1 | sampled | 1.145 | 1.135..1.163 | kron_leads |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.994 | 0.953..1.017 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 1.250 | 1.136..1.295 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | batch | 1.322 | 1.232..1.536 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 1.264 | 1.202..1.402 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | sampled | 1.246 | 1.179..1.380 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 0.922 | 0.831..0.924 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.681 | 0.674..0.714 | peer_leads |
| async-mmap-inline | foundation | 1 | sampled | 1.006 | 0.973..1.132 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.791 | 0.785..0.818 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 1.074 | 0.987..1.207 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.973 | 0.892..0.980 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.880 | 0.647..0.951 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.924 | 0.669..0.961 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 0.931 | 0.864..0.960 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.708 | 0.689..0.742 | peer_leads |
| async-mmap-schema | foundation | 1 | sampled | 1.026 | 0.983..1.129 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.804 | 0.786..0.827 | peer_leads |
| async-mmap-schema | foundation | 4 | batch | 1.026 | 0.970..1.252 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.977 | 0.877..1.017 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.860 | 0.836..0.950 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.923 | 0.853..0.948 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.079 | 1.046..1.091 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.871 | 0.866..0.905 | peer_leads |
| spsc-memory-inline | foundation | 1 | sampled | 1.153 | 1.071..1.168 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.987 | 0.904..1.010 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.382 | 0.949..1.513 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.492 | 1.125..1.573 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 1.500 | 1.424..1.582 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.495 | 1.342..1.557 | inconclusive |
| spsc-memory-schema | foundation | 1 | batch | 1.099 | 1.068..1.135 | kron_leads |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.915 | 0.872..0.920 | peer_leads |
| spsc-memory-schema | foundation | 1 | sampled | 1.181 | 1.153..1.205 | kron_leads |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 1.001 | 0.983..1.033 | inconclusive |
| spsc-memory-schema | foundation | 4 | batch | 1.373 | 1.347..1.520 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | batch | 1.489 | 1.454..1.677 | inconclusive |
| spsc-memory-schema | foundation | 4 | sampled | 1.521 | 1.355..1.584 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 1.507 | 1.334..1.554 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.919 | 0.848..0.953 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.695 | 0.691..0.720 | peer_leads |
| spsc-mmap-inline | foundation | 1 | sampled | 0.991 | 0.952..1.141 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.798 | 0.773..0.810 | peer_leads |
| spsc-mmap-inline | foundation | 4 | batch | 1.238 | 1.156..1.379 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.120 | 1.062..1.208 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.019 | 0.981..1.075 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.040 | 1.014..1.107 | kron_leads |
| spsc-mmap-schema | foundation | 1 | batch | 0.932 | 0.861..0.986 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.719 | 0.693..0.722 | peer_leads |
| spsc-mmap-schema | foundation | 1 | sampled | 1.020 | 1.005..1.133 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.821 | 0.792..0.828 | peer_leads |
| spsc-mmap-schema | foundation | 4 | batch | 1.217 | 1.156..1.359 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 1.104 | 1.045..1.199 | inconclusive |
| spsc-mmap-schema | foundation | 4 | sampled | 1.009 | 0.891..1.044 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 1.030 | 0.921..1.075 | inconclusive |
