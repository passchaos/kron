# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.161 | 2.238 | 2.159 | 2.236 | 无 |
| foundation mmap | 2.163 | 2.154 | 2.160 | 2.152 | 有 |
| foundation_tracing memory | 2.732 | 2.190 | 2.728 | 2.188 | 无 |
| foundation_tracing mmap | 2.561 | 2.242 | 2.552 | 2.240 | 有 |
| kron async-memory-inline | 2.448 | 2.458 | 2.442 | 2.452 | 无 |
| kron async-mmap-inline | 2.446 | 2.498 | 2.441 | 2.493 | 有 |
| kron spsc-memory-inline | 2.531 | 2.722 | 2.523 | 2.714 | 无 |
| kron spsc-mmap-inline | 2.463 | 2.562 | 2.456 | 2.554 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 354 / 761 | 813 / 30,544 | 0.202 | 0.178 |
| foundation mmap | 496 / 931 | 998 / 7,659 | 12.206 | 11.885 |
| foundation_tracing memory | 233 / 511 | 745 / 30,636 | 0.163 | 0.167 |
| foundation_tracing mmap | 330 / 822 | 912 / 9,695 | 13.114 | 19.965 |
| kron async-memory-inline | 281 / 702 | 876 / 22,054 | 0.549 | 0.550 |
| kron async-mmap-inline | 281 / 688 | 896 / 22,277 | 14.287 | 13.594 |
| kron spsc-memory-inline | 318 / 560 | 274 / 483 | 0.622 | 0.827 |
| kron spsc-mmap-inline | 345 / 587 | 273 / 586 | 12.427 | 18.640 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 47.355 | 45.617 | 0.047 | 0.039 | 299.33 |
| foundation mmap | 61.144 | 59.157 | 0.057 | 0.042 | 299.33 |
| foundation_tracing memory | 37.494 | 46.499 | 0.009 | 0.005 | 299.33 |
| foundation_tracing mmap | 54.966 | 64.843 | 0.009 | 0.007 | 299.33 |
| kron async-memory-inline | 42.220 | 41.982 | 0.028 | 0.023 | 299.37 |
| kron async-mmap-inline | 54.634 | 54.631 | 0.026 | 0.023 | 299.37 |
| kron spsc-memory-inline | 40.889 | 38.305 | 0.022 | 0.020 | 299.03 |
| kron spsc-mmap-inline | 53.434 | 57.710 | 0.023 | 0.022 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.170 | 1.052..1.225 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.901 | 0.819..0.927 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.244 | 1.146..1.412 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.923 | 0.857..0.965 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.090 | 1.069..1.159 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 1.114 | 1.108..1.177 | kron_leads |
| async-memory-inline | foundation | 4 | sampled | 1.110 | 1.097..1.167 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.134 | 1.096..1.201 | kron_leads |
| async-mmap-inline | foundation | 1 | batch | 1.167 | 1.054..1.192 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.990 | 0.808..1.006 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.297 | 1.118..1.397 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.963 | 0.850..1.104 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.158 | 1.064..1.187 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.123 | 0.962..1.256 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.057 | 1.014..1.079 | kron_leads |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.123 | 1.011..1.145 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.179 | 1.030..1.309 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.930 | 0.767..0.948 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.224 | 0.894..1.381 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.924 | 0.668..0.948 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.217 | 1.174..1.283 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.243 | 1.210..1.303 | kron_leads |
| spsc-memory-inline | foundation | 4 | sampled | 1.218 | 1.209..1.267 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.251 | 1.208..1.327 | kron_leads |
| spsc-mmap-inline | foundation | 1 | batch | 1.187 | 1.122..1.211 | kron_leads |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.977 | 0.929..1.009 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.282 | 1.230..1.518 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.978 | 0.923..1.092 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.192 | 0.959..1.302 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.078 | 0.910..1.315 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.107 | 1.071..1.157 | kron_leads |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.153 | 1.129..1.209 | inconclusive |
