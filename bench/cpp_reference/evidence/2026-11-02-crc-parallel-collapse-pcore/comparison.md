# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.118 | 2.130 | 2.116 | 2.128 | 无 |
| foundation mmap | 2.191 | 2.272 | 2.188 | 2.269 | 有 |
| foundation_tracing memory | 2.704 | 2.150 | 2.700 | 2.148 | 无 |
| foundation_tracing mmap | 2.532 | 2.336 | 2.522 | 2.334 | 有 |
| kron async-memory-inline | 2.452 | 2.342 | 2.429 | 2.338 | 无 |
| kron async-mmap-inline | 2.362 | 2.319 | 2.352 | 2.315 | 有 |
| kron spsc-memory-inline | 2.399 | 2.662 | 2.394 | 2.654 | 无 |
| kron spsc-mmap-inline | 2.579 | 2.658 | 2.568 | 2.649 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 345 / 655 | 797 / 31,067 | 0.221 | 0.203 |
| foundation mmap | 495 / 930 | 1,028 / 8,414 | 15.872 | 15.691 |
| foundation_tracing memory | 239 / 531 | 737 / 31,937 | 0.177 | 0.186 |
| foundation_tracing mmap | 317 / 799 | 912 / 8,689 | 15.163 | 15.042 |
| kron async-memory-inline | 350 / 755 | 934 / 22,902 | 0.569 | 0.563 |
| kron async-mmap-inline | 318 / 568 | 919 / 22,388 | 12.085 | 11.408 |
| kron spsc-memory-inline | 294 / 610 | 280 / 476 | 0.642 | 0.843 |
| kron spsc-mmap-inline | 377 / 591 | 279 / 434 | 19.491 | 54.130 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 48.574 | 47.899 | 0.043 | 0.041 | 299.33 |
| foundation mmap | 61.507 | 61.236 | 0.199 | 0.047 | 299.33 |
| foundation_tracing memory | 37.964 | 47.498 | 0.010 | 0.006 | 299.33 |
| foundation_tracing mmap | 57.928 | 58.540 | 0.013 | 0.006 | 299.33 |
| kron async-memory-inline | 42.554 | 44.082 | 0.033 | 0.025 | 299.37 |
| kron async-mmap-inline | 57.166 | 56.910 | 0.073 | 0.022 | 299.37 |
| kron spsc-memory-inline | 43.157 | 39.312 | 0.025 | 0.022 | 299.03 |
| kron spsc-mmap-inline | 60.497 | 92.332 | 0.025 | 0.024 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.145 | 1.108..1.379 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.915 | 0.879..0.979 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.015 | 1.012..1.298 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.818 | 0.724..0.891 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.081 | 1.062..1.142 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 1.079 | 1.045..1.123 | kron_leads |
| async-memory-inline | foundation | 4 | sampled | 1.056 | 0.975..1.102 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.103 | 1.050..1.131 | kron_leads |
| async-mmap-inline | foundation | 1 | batch | 1.070 | 0.709..1.165 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.933 | 0.665..1.192 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.276 | 1.051..1.404 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.917 | 0.860..0.990 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.020 | 0.885..1.112 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.962 | 0.829..1.034 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.045 | 0.931..1.154 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.013 | 0.987..1.048 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.169 | 1.067..1.376 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.928 | 0.859..0.942 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.310 | 1.071..1.434 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.939 | 0.860..0.984 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.243 | 1.198..1.299 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.237 | 1.189..1.257 | kron_leads |
| spsc-memory-inline | foundation | 4 | sampled | 1.173 | 1.133..1.247 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.221 | 1.203..1.251 | kron_leads |
| spsc-mmap-inline | foundation | 1 | batch | 1.142 | 1.126..1.265 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 1.018 | 1.000..1.258 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.237 | 1.184..1.404 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.990 | 0.844..1.013 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.162 | 1.096..1.187 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.111 | 1.068..1.155 | kron_leads |
| spsc-mmap-inline | foundation | 4 | sampled | 1.162 | 1.085..1.280 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.135 | 1.098..1.164 | kron_leads |
