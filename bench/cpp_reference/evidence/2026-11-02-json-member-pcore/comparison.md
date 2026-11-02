# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.137 | 2.206 | 2.134 | 2.204 | 无 |
| foundation mmap | 2.023 | 2.087 | 2.020 | 2.085 | 有 |
| foundation_tracing memory | 2.675 | 2.138 | 2.671 | 2.137 | 无 |
| foundation_tracing mmap | 2.580 | 2.380 | 2.576 | 2.377 | 有 |
| kron async-memory-inline | 2.363 | 2.365 | 2.357 | 2.360 | 无 |
| kron async-mmap-inline | 2.370 | 2.343 | 2.362 | 2.336 | 有 |
| kron spsc-memory-inline | 2.430 | 2.678 | 2.423 | 2.670 | 无 |
| kron spsc-mmap-inline | 2.550 | 2.677 | 2.543 | 2.664 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 353 / 668 | 831 / 30,575 | 0.225 | 0.221 |
| foundation mmap | 506 / 941 | 1,002 / 7,529 | 12.661 | 12.928 |
| foundation_tracing memory | 237 / 531 | 734 / 32,344 | 0.180 | 0.214 |
| foundation_tracing mmap | 336 / 822 | 832 / 9,115 | 12.360 | 15.602 |
| kron async-memory-inline | 364 / 717 | 898 / 19,457 | 0.575 | 0.566 |
| kron async-mmap-inline | 337 / 695 | 848 / 21,474 | 12.363 | 14.922 |
| kron spsc-memory-inline | 374 / 642 | 299 / 555 | 0.685 | 0.832 |
| kron spsc-mmap-inline | 314 / 517 | 279 / 531 | 12.723 | 27.288 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 47.776 | 46.294 | 0.047 | 0.038 | 299.33 |
| foundation mmap | 71.171 | 62.331 | 0.076 | 0.051 | 299.33 |
| foundation_tracing memory | 38.363 | 47.650 | 0.009 | 0.006 | 299.33 |
| foundation_tracing mmap | 52.915 | 57.819 | 0.019 | 0.008 | 299.33 |
| kron async-memory-inline | 43.949 | 43.778 | 0.050 | 0.026 | 299.37 |
| kron async-mmap-inline | 56.588 | 59.356 | 0.033 | 0.025 | 299.37 |
| kron spsc-memory-inline | 42.848 | 38.929 | 0.024 | 0.022 | 299.03 |
| kron spsc-mmap-inline | 54.403 | 71.257 | 0.024 | 0.024 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.074 | 0.842..1.342 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.899 | 0.669..0.922 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.115 | 0.995..1.189 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.869 | 0.752..1.073 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.070 | 1.005..1.104 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 1.098 | 1.029..1.158 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.113 | 1.036..1.154 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.110 | 1.075..1.166 | kron_leads |
| async-mmap-inline | foundation | 1 | batch | 1.183 | 1.107..1.516 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.889 | 0.859..0.953 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.251 | 1.148..1.539 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.960 | 0.875..0.995 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.110 | 0.994..1.181 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.983 | 0.891..1.017 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.030 | 0.947..1.077 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.008 | 0.872..1.029 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.180 | 1.093..1.361 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.923 | 0.886..1.122 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.108 | 1.020..1.237 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.904 | 0.770..1.071 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.179 | 1.051..1.268 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.275 | 1.001..1.308 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 1.244 | 1.127..1.267 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.243 | 1.169..1.283 | kron_leads |
| spsc-mmap-inline | foundation | 1 | batch | 1.227 | 1.121..1.633 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.977 | 0.870..1.053 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.235 | 0.881..1.633 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.970 | 0.698..1.056 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.266 | 1.091..1.319 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.089 | 0.978..1.177 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.121 | 0.666..1.132 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.041 | 0.717..1.109 | inconclusive |
