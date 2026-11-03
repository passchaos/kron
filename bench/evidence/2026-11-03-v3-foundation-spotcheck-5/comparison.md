# 完整日志流程实测

共 120 个试验，逐条核对 12,120,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.828 | 2.297 | 1.826 | 2.294 | 无 |
| foundation mmap | 2.097 | 2.729 | 2.094 | 2.721 | 有 |
| foundation_tracing memory | 2.172 | 2.231 | 2.170 | 2.229 | 无 |
| foundation_tracing mmap | 2.705 | 2.938 | 2.694 | 2.933 | 有 |
| kron async-memory-schema | 1.851 | 1.790 | 1.843 | 1.786 | 无 |
| kron async-mmap-schema | 1.875 | 1.795 | 1.870 | 1.791 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 375 / 739 | 621 / 45,211 | 0.338 | 0.383 |
| foundation mmap | 435 / 931 | 770 / 8,357 | 18.887 | 18.307 |
| foundation_tracing memory | 285 / 630 | 652 / 45,417 | 0.317 | 0.307 |
| foundation_tracing mmap | 344 / 862 | 822 / 8,593 | 15.572 | 24.797 |
| kron async-memory-schema | 422 / 714 | 851 / 40,871 | 0.729 | 0.743 |
| kron async-mmap-schema | 428 / 706 | 873 / 41,763 | 11.246 | 12.390 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.110 | 44.649 | 0.058 | 0.056 | 299.33 |
| foundation mmap | 67.072 | 56.238 | 0.080 | 0.072 | 299.33 |
| foundation_tracing memory | 47.208 | 46.014 | 0.002 | 0.001 | 299.33 |
| foundation_tracing mmap | 54.551 | 59.810 | 0.012 | 0.011 | 299.33 |
| kron async-memory-schema | 55.876 | 57.612 | 0.043 | 0.037 | 299.37 |
| kron async-mmap-schema | 729.323 | 135.493 | 0.036 | 0.034 | 299.37 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-schema | foundation | 1 | batch | 0.993 | 0.981..1.017 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | batch | 0.848 | 0.821..0.855 | peer_leads |
| async-memory-schema | foundation | 1 | sampled | 1.041 | 1.033..1.101 | kron_leads |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.877 | 0.863..18.638 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 0.777 | 0.763..0.810 | peer_leads |
| async-memory-schema | foundation_tracing | 4 | batch | 0.800 | 0.715..0.820 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 0.796 | 0.765..0.955 | inconclusive |
| async-memory-schema | foundation_tracing | 4 | sampled | 0.781 | 0.745..0.788 | peer_leads |
| async-mmap-schema | foundation | 1 | batch | 0.893 | 0.870..0.926 | peer_leads |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.692 | 0.604..0.726 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 0.919 | 0.903..1.014 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.749 | 0.721..0.816 | inconclusive |
| async-mmap-schema | foundation | 4 | batch | 0.637 | 0.548..0.680 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.608 | 0.591..0.669 | inconclusive |
| async-mmap-schema | foundation | 4 | sampled | 0.631 | 0.612..0.670 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.676 | 0.547..0.698 | inconclusive |
