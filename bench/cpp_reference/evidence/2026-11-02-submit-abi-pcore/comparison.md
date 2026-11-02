# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.160 | 2.257 | 2.158 | 2.255 | 无 |
| foundation mmap | 2.087 | 2.005 | 2.082 | 2.003 | 有 |
| foundation_tracing memory | 2.693 | 2.219 | 2.691 | 2.216 | 无 |
| foundation_tracing mmap | 2.453 | 2.170 | 2.443 | 2.168 | 有 |
| kron async-memory-inline | 2.362 | 2.451 | 2.351 | 2.447 | 无 |
| kron async-mmap-inline | 2.486 | 2.433 | 2.481 | 2.429 | 有 |
| kron spsc-memory-inline | 2.523 | 2.738 | 2.516 | 2.731 | 无 |
| kron spsc-mmap-inline | 2.546 | 2.441 | 2.540 | 2.435 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 348 / 613 | 824 / 30,746 | 0.201 | 0.191 |
| foundation mmap | 469 / 1,014 | 1,001 / 8,005 | 19.704 | 19.799 |
| foundation_tracing memory | 257 / 539 | 737 / 30,958 | 0.191 | 0.174 |
| foundation_tracing mmap | 330 / 837 | 899 / 9,369 | 15.647 | 19.700 |
| kron async-memory-inline | 386 / 682 | 897 / 23,282 | 0.565 | 0.563 |
| kron async-mmap-inline | 291 / 671 | 914 / 22,372 | 10.364 | 10.719 |
| kron spsc-memory-inline | 316 / 578 | 272 / 437 | 0.649 | 0.826 |
| kron spsc-mmap-inline | 381 / 1,044 | 270 / 1,115 | 13.223 | 23.081 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 47.128 | 45.275 | 0.041 | 0.039 | 299.33 |
| foundation mmap | 69.236 | 70.449 | 0.115 | 0.041 | 299.33 |
| foundation_tracing memory | 37.863 | 45.961 | 0.010 | 0.009 | 299.33 |
| foundation_tracing mmap | 54.036 | 68.038 | 0.009 | 0.007 | 299.33 |
| kron async-memory-inline | 43.951 | 42.325 | 0.071 | 0.025 | 299.37 |
| kron async-mmap-inline | 52.607 | 54.424 | 0.026 | 0.022 | 299.37 |
| kron spsc-memory-inline | 41.205 | 38.149 | 0.021 | 0.019 | 299.03 |
| kron spsc-mmap-inline | 54.342 | 66.198 | 0.024 | 0.019 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.150 | 1.058..1.244 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.906 | 0.860..1.005 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.161 | 1.105..1.272 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.917 | 0.864..1.062 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.093 | 1.055..1.112 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 1.121 | 1.069..1.182 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.115 | 1.066..1.146 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.116 | 1.087..1.190 | kron_leads |
| async-mmap-inline | foundation | 1 | batch | 1.232 | 1.145..1.300 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 1.050 | 0.913..1.114 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 1.290 | 1.145..1.379 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.985 | 0.863..1.051 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.220 | 1.159..1.301 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.150 | 1.044..1.198 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.072 | 1.034..1.109 | kron_leads |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.070 | 1.029..1.137 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.212 | 1.118..1.353 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.935 | 0.919..1.167 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.242 | 1.125..1.474 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 1.003 | 0.918..1.082 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.213 | 1.189..1.249 | kron_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.240 | 1.204..1.314 | kron_leads |
| spsc-memory-inline | foundation | 4 | sampled | 1.217 | 1.052..1.295 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.252 | 1.036..1.300 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 1.224 | 1.072..1.335 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.996 | 0.906..1.077 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 1.197 | 0.994..1.328 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.907 | 0.841..0.932 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.222 | 1.187..1.391 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.136 | 1.099..1.197 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.134 | 0.980..1.143 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.104 | 0.975..1.175 | inconclusive |
