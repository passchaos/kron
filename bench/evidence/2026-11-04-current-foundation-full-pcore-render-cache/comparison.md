# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.003 | 2.195 | 2.001 | 2.192 | 无 |
| foundation mmap | 2.181 | 2.338 | 2.178 | 2.335 | 有 |
| foundation_tracing memory | 2.405 | 2.144 | 2.402 | 2.142 | 无 |
| foundation_tracing mmap | 2.643 | 2.446 | 2.639 | 2.442 | 有 |
| kron async-memory-inline | 2.553 | 3.161 | 2.544 | 3.152 | 无 |
| kron async-memory-schema | 2.237 | 2.598 | 2.232 | 2.581 | 无 |
| kron async-mmap-inline | 2.564 | 2.637 | 2.557 | 2.631 | 有 |
| kron async-mmap-schema | 1.461 | 2.449 | 1.459 | 2.443 | 有 |
| kron spsc-memory-inline | 1.925 | 3.461 | 1.921 | 3.434 | 无 |
| kron spsc-memory-schema | 1.429 | 3.068 | 1.425 | 3.054 | 无 |
| kron spsc-mmap-inline | 1.889 | 3.193 | 1.884 | 3.175 | 有 |
| kron spsc-mmap-schema | 2.138 | 3.284 | 2.133 | 3.258 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 345 / 737 | 782 / 31,856 | 0.216 | 0.234 |
| foundation mmap | 465 / 911 | 839 / 7,867 | 26.071 | 202.664 |
| foundation_tracing memory | 241 / 650 | 661 / 32,480 | 0.235 | 0.175 |
| foundation_tracing mmap | 326 / 829 | 755 / 9,724 | 206.009 | 21.552 |
| kron async-memory-inline | 281 / 579 | 1,055 / 1,659 | 0.765 | 0.576 |
| kron async-memory-schema | 442 / 696 | 1,121 / 1,693 | 0.556 | 0.584 |
| kron async-mmap-inline | 277 / 581 | 956 / 1,611 | 1204.462 | 25.062 |
| kron async-mmap-schema | 433 / 872 | 1,149 / 1,813 | 11.855 | 11.268 |
| kron spsc-memory-inline | 471 / 824 | 545 / 1,097 | 0.637 | 0.883 |
| kron spsc-memory-schema | 446 / 697 | 704 / 1,409 | 0.693 | 0.927 |
| kron spsc-mmap-inline | 447 / 659 | 880 / 1,202 | 24.763 | 50.018 |
| kron spsc-mmap-schema | 682 / 940 | 688 / 1,343 | 888.025 | 436.453 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 50.903 | 46.572 | 0.054 | 0.046 | 299.33 |
| foundation mmap | 71.267 | 244.511 | 0.063 | 0.053 | 299.33 |
| foundation_tracing memory | 42.405 | 47.564 | 0.010 | 0.011 | 299.33 |
| foundation_tracing mmap | 246.262 | 363.595 | 0.013 | 0.011 | 299.33 |
| kron async-memory-inline | 40.855 | 33.069 | 0.036 | 0.024 | 299.37 |
| kron async-memory-schema | 46.397 | 40.173 | 0.032 | 0.030 | 299.37 |
| kron async-mmap-inline | 1262.336 | 63.814 | 0.032 | 0.026 | 299.37 |
| kron async-mmap-schema | 87.926 | 71.294 | 0.038 | 0.031 | 299.37 |
| kron spsc-memory-inline | 53.341 | 31.405 | 0.026 | 0.025 | 299.03 |
| kron spsc-memory-schema | 72.004 | 34.792 | 0.048 | 0.021 | 299.03 |
| kron spsc-mmap-inline | 93.480 | 84.689 | 0.025 | 0.027 | 299.03 |
| kron spsc-mmap-schema | 941.635 | 1293.099 | 0.027 | 0.022 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.210 | 1.144..1.747 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 1.027 | 0.846..1.441 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.478 | 0.926..1.813 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 1.150 | 1.004..1.401 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.392 | 1.144..1.605 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.457 | 1.339..1.538 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.291 | 0.128..1.409 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.312 | 0.132..1.348 | inconclusive |
| async-memory-schema | foundation | 1 | batch | 1.055 | 0.719..1.504 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | batch | 0.888 | 0.610..1.240 | inconclusive |
| async-memory-schema | foundation | 1 | sampled | 1.124 | 0.718..1.252 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.903 | 0.603..1.136 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 1.140 | 1.023..1.314 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | batch | 1.223 | 0.975..1.268 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 1.126 | 0.835..1.538 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | sampled | 1.156 | 0.823..1.497 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 1.168 | 0.782..1.198 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.936 | 0.927..1.015 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.425 | 0.874..26.652 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 1.098 | 0.667..1.110 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.153 | 0.144..1.246 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.039 | 0.137..11.572 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.163 | 1.052..1.387 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.176 | 1.119..1.361 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 0.668 | 0.457..1.033 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.570 | 0.367..0.835 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 1.040 | 0.986..16.070 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.810 | 0.663..0.861 | inconclusive |
| async-mmap-schema | foundation | 4 | batch | 1.055 | 0.785..1.339 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 1.000 | 0.903..7.787 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.950 | 0.760..1.348 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 1.011 | 0.746..1.244 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 0.987 | 0.792..1.294 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.730 | 0.671..1.067 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.063 | 0.731..1.978 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.857 | 0.756..1.325 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.566 | 1.403..2.222 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.655 | 1.550..2.119 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 1.983 | 1.174..2.272 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.930 | 1.156..2.195 | inconclusive |
| spsc-memory-schema | foundation | 1 | batch | 0.960 | 0.619..1.110 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.792 | 0.550..0.899 | inconclusive |
| spsc-memory-schema | foundation | 1 | sampled | 1.086 | 0.615..1.488 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 0.824 | 0.557..1.113 | inconclusive |
| spsc-memory-schema | foundation | 4 | batch | 1.279 | 1.123..1.939 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | batch | 1.500 | 1.149..1.760 | inconclusive |
| spsc-memory-schema | foundation | 4 | sampled | 1.274 | 0.918..1.823 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 1.255 | 0.942..1.774 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.891 | 0.669..1.100 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.841 | 0.536..0.890 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 0.986 | 0.758..24.930 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.684 | 0.591..1.099 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.340 | 1.277..2.218 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.264 | 1.211..12.983 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.469 | 0.844..2.155 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.486 | 0.828..1.989 | inconclusive |
| spsc-mmap-schema | foundation | 1 | batch | 0.992 | 0.548..1.146 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.847 | 0.443..1.034 | inconclusive |
| spsc-mmap-schema | foundation | 1 | sampled | 0.992 | 0.764..12.936 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.583 | 0.470..0.825 | inconclusive |
| spsc-mmap-schema | foundation | 4 | batch | 1.371 | 0.925..2.234 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 1.292 | 0.877..17.333 | inconclusive |
| spsc-mmap-schema | foundation | 4 | sampled | 1.142 | 1.097..1.858 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 1.202 | 1.076..1.715 | inconclusive |
