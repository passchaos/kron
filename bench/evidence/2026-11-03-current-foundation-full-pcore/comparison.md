# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.893 | 2.295 | 1.889 | 2.293 | 无 |
| foundation mmap | 2.176 | 2.468 | 2.173 | 2.462 | 有 |
| foundation_tracing memory | 2.041 | 2.216 | 2.038 | 2.212 | 无 |
| foundation_tracing mmap | 2.240 | 2.356 | 2.233 | 2.353 | 有 |
| kron async-memory-inline | 2.526 | 2.449 | 2.520 | 2.442 | 无 |
| kron async-memory-schema | 2.075 | 2.226 | 2.067 | 2.222 | 无 |
| kron async-mmap-inline | 2.500 | 2.378 | 2.492 | 2.369 | 有 |
| kron async-mmap-schema | 1.830 | 2.200 | 1.822 | 2.196 | 有 |
| kron spsc-memory-inline | 2.645 | 2.746 | 2.638 | 2.736 | 无 |
| kron spsc-memory-schema | 2.052 | 2.196 | 2.047 | 2.187 | 无 |
| kron spsc-mmap-inline | 1.894 | 2.364 | 1.891 | 2.356 | 有 |
| kron spsc-mmap-schema | 1.374 | 2.694 | 1.372 | 2.686 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 348 / 719 | 787 / 33,378 | 0.207 | 0.254 |
| foundation mmap | 521 / 1,004 | 969 / 7,953 | 22.301 | 22.149 |
| foundation_tracing memory | 239 / 579 | 679 / 32,986 | 0.195 | 0.177 |
| foundation_tracing mmap | 300 / 839 | 761 / 10,401 | 20.822 | 22.711 |
| kron async-memory-inline | 390 / 666 | 786 / 21,612 | 0.578 | 0.603 |
| kron async-memory-schema | 441 / 783 | 982 / 17,285 | 0.570 | 0.571 |
| kron async-mmap-inline | 275 / 611 | 826 / 19,887 | 4.464 | 10.805 |
| kron async-mmap-schema | 457 / 842 | 949 / 15,706 | 13.522 | 10.660 |
| kron spsc-memory-inline | 346 / 599 | 271 / 563 | 0.669 | 0.845 |
| kron spsc-memory-schema | 452 / 788 | 511 / 956 | 0.650 | 0.854 |
| kron spsc-mmap-inline | 308 / 591 | 295 / 627 | 21.575 | 50.841 |
| kron spsc-mmap-schema | 509 / 907 | 493 / 908 | 25.668 | 50.266 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 53.996 | 46.175 | 0.046 | 0.044 | 299.33 |
| foundation mmap | 69.125 | 63.467 | 0.065 | 0.046 | 299.33 |
| foundation_tracing memory | 49.998 | 46.076 | 0.008 | 0.008 | 299.33 |
| foundation_tracing mmap | 70.821 | 66.336 | 0.011 | 0.008 | 299.33 |
| kron async-memory-inline | 40.990 | 42.505 | 0.041 | 0.028 | 299.37 |
| kron async-memory-schema | 49.573 | 46.305 | 0.071 | 0.023 | 299.37 |
| kron async-mmap-inline | 69.665 | 50.129 | 0.033 | 0.029 | 299.37 |
| kron async-mmap-schema | 93.907 | 180.931 | 0.026 | 0.026 | 299.37 |
| kron spsc-memory-inline | 39.296 | 38.078 | 0.025 | 0.023 | 299.03 |
| kron spsc-memory-schema | 50.412 | 48.096 | 0.024 | 0.030 | 299.03 |
| kron spsc-mmap-inline | 78.888 | 94.147 | 0.023 | 0.030 | 299.03 |
| kron spsc-mmap-schema | 108.821 | 1315.980 | 0.026 | 0.024 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.315 | 1.185..1.695 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 1.165 | 0.987..1.287 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.165 | 0.850..1.544 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.975 | 0.762..1.043 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.087 | 0.735..1.121 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.097 | 0.819..1.119 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.126 | 0.675..27.542 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.997 | 0.692..1.203 | inconclusive |
| async-memory-schema | foundation | 1 | batch | 0.946 | 0.716..1.437 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | batch | 0.837 | 0.692..1.075 | inconclusive |
| async-memory-schema | foundation | 1 | sampled | 1.080 | 0.723..1.267 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.811 | 0.776..1.133 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 1.005 | 0.938..1.083 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | batch | 1.037 | 0.992..1.113 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 1.070 | 0.611..25.561 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | sampled | 0.984 | 0.665..1.202 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 1.053 | 0.770..1.529 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 1.159 | 0.579..1.339 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.493 | 1.132..2.231 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.961 | 0.833..1.179 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 0.996 | 0.761..1.054 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.990 | 0.758..1.113 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.943 | 0.706..1.157 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.888 | 0.639..1.080 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 0.827 | 0.633..1.277 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.766 | 0.622..1.121 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 1.008 | 0.923..1.769 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.762 | 0.645..0.847 | inconclusive |
| async-mmap-schema | foundation | 4 | batch | 0.942 | 0.781..1.000 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.936 | 0.812..0.996 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.853 | 0.652..1.135 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.887 | 0.647..1.058 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.237 | 1.163..1.782 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 1.110 | 1.037..1.304 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.270 | 0.886..1.550 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 1.028 | 0.951..1.086 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.196 | 0.710..1.239 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.215 | 0.791..1.315 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 1.194 | 1.134..31.442 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.243 | 1.049..1.290 | inconclusive |
| spsc-memory-schema | foundation | 1 | batch | 0.999 | 0.786..1.377 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.919 | 0.759..1.105 | inconclusive |
| spsc-memory-schema | foundation | 1 | sampled | 1.039 | 0.921..1.247 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 0.787 | 0.746..1.085 | inconclusive |
| spsc-memory-schema | foundation | 4 | batch | 0.996 | 0.711..1.228 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | batch | 0.982 | 0.786..1.211 | inconclusive |
| spsc-memory-schema | foundation | 4 | sampled | 1.100 | 0.925..31.701 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 1.128 | 0.813..1.385 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.945 | 0.647..1.442 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.806 | 0.710..1.123 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.369 | 1.129..1.591 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.903 | 0.598..1.141 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 0.957 | 0.715..1.120 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.010 | 0.743..1.115 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.089 | 1.049..1.151 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.042 | 0.979..1.247 | inconclusive |
| spsc-mmap-schema | foundation | 1 | batch | 0.685 | 0.596..1.309 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.711 | 0.515..0.992 | inconclusive |
| spsc-mmap-schema | foundation | 1 | sampled | 1.041 | 0.696..1.370 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.590 | 0.486..0.903 | inconclusive |
| spsc-mmap-schema | foundation | 4 | batch | 1.087 | 1.010..1.129 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 1.121 | 1.050..1.160 | kron_leads |
| spsc-mmap-schema | foundation | 4 | sampled | 1.062 | 0.914..1.156 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 1.044 | 0.853..1.216 | inconclusive |
