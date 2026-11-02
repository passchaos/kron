# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.863 | 2.232 | 1.859 | 2.229 | 无 |
| foundation mmap | 2.121 | 2.834 | 2.114 | 2.824 | 有 |
| foundation_tracing memory | 2.201 | 2.291 | 2.198 | 2.288 | 无 |
| foundation_tracing mmap | 2.729 | 2.802 | 2.724 | 2.794 | 有 |
| kron async-memory-inline | 1.843 | 1.717 | 1.831 | 1.714 | 无 |
| kron async-mmap-inline | 1.850 | 1.731 | 1.839 | 1.726 | 有 |
| kron spsc-memory-inline | 1.856 | 1.939 | 1.848 | 1.929 | 无 |
| kron spsc-mmap-inline | 1.885 | 1.957 | 1.881 | 1.951 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 372 / 743 | 654 / 45,863 | 0.248 | 0.279 |
| foundation mmap | 441 / 865 | 763 / 8,105 | 15.383 | 15.878 |
| foundation_tracing memory | 283 / 610 | 686 / 45,244 | 0.230 | 0.226 |
| foundation_tracing mmap | 343 / 776 | 751 / 7,804 | 16.832 | 12.792 |
| kron async-memory-inline | 355 / 576 | 833 / 46,874 | 0.718 | 0.722 |
| kron async-mmap-inline | 353 / 577 | 846 / 46,253 | 5.891 | 12.350 |
| kron spsc-memory-inline | 307 / 501 | 287 / 446 | 0.825 | 1.047 |
| kron spsc-mmap-inline | 299 / 525 | 286 / 434 | 15.809 | 24.813 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 55.157 | 45.931 | 0.103 | 0.059 | 299.33 |
| foundation mmap | 63.360 | 51.052 | 0.164 | 0.114 | 299.33 |
| foundation_tracing memory | 46.605 | 44.706 | 0.011 | 0.010 | 299.33 |
| foundation_tracing mmap | 54.767 | 48.987 | 0.015 | 0.010 | 299.33 |
| kron async-memory-inline | 56.393 | 60.423 | 0.099 | 0.036 | 299.37 |
| kron async-mmap-inline | 61.160 | 70.429 | 0.143 | 0.034 | 299.37 |
| kron spsc-memory-inline | 55.988 | 53.811 | 0.034 | 0.033 | 299.03 |
| kron spsc-mmap-inline | 69.813 | 76.679 | 0.028 | 0.028 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 0.984 | 0.946..0.999 | peer_leads |
| async-memory-inline | foundation_tracing | 1 | batch | 0.828 | 0.808..0.849 | peer_leads |
| async-memory-inline | foundation | 1 | sampled | 1.075 | 1.053..1.102 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.914 | 0.885..0.932 | peer_leads |
| async-memory-inline | foundation | 4 | batch | 0.770 | 0.715..0.786 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 0.750 | 0.696..0.786 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 0.751 | 0.738..0.782 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.759 | 0.738..0.773 | peer_leads |
| async-mmap-inline | foundation | 1 | batch | 0.870 | 0.850..0.876 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.676 | 0.660..0.688 | peer_leads |
| async-mmap-inline | foundation | 1 | sampled | 0.937 | 0.923..0.942 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.761 | 0.750..0.781 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 0.608 | 0.587..0.653 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.610 | 0.557..0.641 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.585 | 0.568..0.599 | peer_leads |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.539 | 0.534..0.558 | peer_leads |
| spsc-memory-inline | foundation | 1 | batch | 0.992 | 0.938..1.040 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.843 | 0.804..0.869 | peer_leads |
| spsc-memory-inline | foundation | 1 | sampled | 1.086 | 1.077..1.132 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.919 | 0.898..0.965 | peer_leads |
| spsc-memory-inline | foundation | 4 | batch | 0.857 | 0.828..0.895 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.861 | 0.799..0.885 | peer_leads |
| spsc-memory-inline | foundation | 4 | sampled | 0.876 | 0.838..0.905 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.870 | 0.863..0.885 | peer_leads |
| spsc-mmap-inline | foundation | 1 | batch | 0.890 | 0.852..0.910 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.689 | 0.668..0.714 | peer_leads |
| spsc-mmap-inline | foundation | 1 | sampled | 0.950 | 0.783..0.986 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.787 | 0.636..0.801 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 0.693 | 0.664..0.745 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.703 | 0.630..0.731 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.674 | 0.640..0.693 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.618 | 0.603..0.644 | peer_leads |
