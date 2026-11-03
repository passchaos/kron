# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.391 | 2.052 | 1.389 | 2.050 | 无 |
| foundation mmap | 1.633 | 2.352 | 1.631 | 2.348 | 有 |
| foundation_tracing memory | 1.773 | 2.118 | 1.771 | 2.116 | 无 |
| foundation_tracing mmap | 1.722 | 2.324 | 1.720 | 2.320 | 有 |
| kron async-memory-inline | 1.452 | 3.036 | 1.449 | 3.027 | 无 |
| kron async-memory-schema | 1.479 | 2.927 | 1.476 | 2.919 | 无 |
| kron async-mmap-inline | 2.177 | 2.796 | 2.167 | 2.784 | 有 |
| kron async-mmap-schema | 1.629 | 3.054 | 1.626 | 3.040 | 有 |
| kron spsc-memory-inline | 1.713 | 4.160 | 1.709 | 4.139 | 无 |
| kron spsc-memory-schema | 1.475 | 3.910 | 1.472 | 3.882 | 无 |
| kron spsc-mmap-inline | 1.578 | 4.274 | 1.575 | 4.250 | 有 |
| kron spsc-mmap-schema | 1.581 | 3.912 | 1.578 | 3.889 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 510 / 803 | 763 / 33,832 | 0.302 | 0.307 |
| foundation mmap | 628 / 1,064 | 1,043 / 8,780 | 26.265 | 25.341 |
| foundation_tracing memory | 376 / 690 | 736 / 36,070 | 0.297 | 0.289 |
| foundation_tracing mmap | 498 / 1,040 | 824 / 9,350 | 243.054 | 110.970 |
| kron async-memory-inline | 431 / 727 | 1,038 / 1,714 | 0.600 | 0.778 |
| kron async-memory-schema | 668 / 904 | 1,160 / 1,830 | 0.824 | 0.819 |
| kron async-mmap-inline | 405 / 642 | 1,054 / 1,677 | 31.044 | 16.657 |
| kron async-mmap-schema | 662 / 969 | 1,068 / 1,739 | 14.088 | 8.521 |
| kron spsc-memory-inline | 436 / 717 | 502 / 1,099 | 0.829 | 0.910 |
| kron spsc-memory-schema | 597 / 905 | 672 / 1,118 | 0.704 | 0.926 |
| kron spsc-mmap-inline | 485 / 728 | 766 / 1,060 | 24.126 | 351.511 |
| kron spsc-mmap-schema | 743 / 930 | 752 / 1,115 | 68.110 | 46.206 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 73.223 | 49.798 | 0.059 | 0.053 | 299.33 |
| foundation mmap | 97.940 | 68.221 | 0.066 | 0.060 | 299.33 |
| foundation_tracing memory | 57.366 | 48.105 | 0.013 | 0.010 | 299.33 |
| foundation_tracing mmap | 301.982 | 163.158 | 0.014 | 0.014 | 299.33 |
| kron async-memory-inline | 70.549 | 35.831 | 0.038 | 0.032 | 299.37 |
| kron async-memory-schema | 69.614 | 36.345 | 0.041 | 0.040 | 299.37 |
| kron async-mmap-inline | 77.839 | 52.214 | 0.038 | 0.036 | 299.37 |
| kron async-mmap-schema | 101.179 | 59.202 | 0.029 | 0.027 | 299.37 |
| kron spsc-memory-inline | 60.221 | 25.821 | 0.030 | 0.027 | 299.03 |
| kron spsc-memory-schema | 69.754 | 27.993 | 0.033 | 0.026 | 299.03 |
| kron spsc-mmap-inline | 85.410 | 373.724 | 0.028 | 0.027 | 299.03 |
| kron spsc-mmap-schema | 176.581 | 1239.176 | 0.033 | 0.035 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.227 | 0.611..3.887 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.853 | 0.341..0.999 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.045 | 0.354..1.297 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.837 | 0.328..1.046 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.355 | 0.628..1.659 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.378 | 0.637..1.661 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.065 | 0.552..1.521 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.072 | 0.557..1.517 | inconclusive |
| async-memory-schema | foundation | 1 | batch | 0.991 | 0.925..9.324 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | batch | 0.816 | 0.718..0.869 | inconclusive |
| async-memory-schema | foundation | 1 | sampled | 0.977 | 0.916..1.025 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.805 | 0.687..0.905 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 1.347 | 0.760..1.519 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | batch | 1.268 | 0.670..1.521 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 1.437 | 1.086..1.807 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | sampled | 1.450 | 1.084..1.550 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 1.037 | 0.952..1.500 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 1.148 | 0.887..1.427 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 0.748 | 0.614..1.214 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.851 | 0.571..6.874 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.176 | 0.690..1.274 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.200 | 0.690..1.309 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.311 | 1.119..1.391 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.262 | 1.103..1.394 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 0.988 | 0.834..1.239 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 1.010 | 0.845..1.102 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 0.723 | 0.674..1.117 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.891 | 0.497..5.293 | inconclusive |
| async-mmap-schema | foundation | 4 | batch | 1.295 | 1.047..1.611 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 1.288 | 0.946..1.712 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 1.303 | 1.120..1.668 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 1.373 | 1.023..1.643 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.322 | 1.104..10.986 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.965 | 0.871..1.433 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.468 | 0.950..1.672 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 1.134 | 0.938..1.189 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 2.035 | 1.705..2.606 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 2.040 | 1.777..2.298 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 2.056 | 1.431..2.542 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 2.031 | 1.427..2.528 | inconclusive |
| spsc-memory-schema | foundation | 1 | batch | 1.120 | 0.814..8.918 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.783 | 0.631..1.322 | inconclusive |
| spsc-memory-schema | foundation | 1 | sampled | 0.991 | 0.897..1.404 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 0.886 | 0.668..1.133 | inconclusive |
| spsc-memory-schema | foundation | 4 | batch | 1.927 | 1.696..2.846 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | batch | 1.925 | 1.574..2.850 | inconclusive |
| spsc-memory-schema | foundation | 4 | sampled | 1.781 | 1.392..2.583 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 1.797 | 1.389..2.340 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 1.071 | 0.683..1.562 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.997 | 0.903..1.823 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.094 | 0.710..1.540 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.879 | 0.767..8.720 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.905 | 1.247..2.242 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.728 | 1.273..2.525 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.647 | 1.396..1.967 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.673 | 1.376..1.964 | inconclusive |
| spsc-mmap-schema | foundation | 1 | batch | 0.888 | 0.693..1.102 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.917 | 0.793..0.944 | inconclusive |
| spsc-mmap-schema | foundation | 1 | sampled | 0.824 | 0.613..0.972 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.759 | 0.718..5.455 | inconclusive |
| spsc-mmap-schema | foundation | 4 | batch | 1.743 | 0.259..1.903 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 1.612 | 0.329..1.914 | inconclusive |
| spsc-mmap-schema | foundation | 4 | sampled | 1.698 | 1.027..1.756 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 1.604 | 1.011..1.805 | inconclusive |
