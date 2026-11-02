# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.817 | 2.298 | 1.813 | 2.296 | 无 |
| foundation mmap | 2.155 | 3.210 | 2.142 | 3.203 | 有 |
| foundation_tracing memory | 2.230 | 2.204 | 2.227 | 2.201 | 无 |
| foundation_tracing mmap | 2.739 | 3.280 | 2.729 | 3.273 | 有 |
| kron async-memory-inline | 1.800 | 1.695 | 1.790 | 1.690 | 无 |
| kron async-mmap-inline | 1.808 | 1.685 | 1.804 | 1.681 | 有 |
| kron spsc-memory-inline | 1.828 | 1.918 | 1.823 | 1.911 | 无 |
| kron spsc-mmap-inline | 1.863 | 1.946 | 1.858 | 1.936 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 378 / 658 | 597 / 45,373 | 0.269 | 0.271 |
| foundation mmap | 440 / 921 | 857 / 7,838 | 20.339 | 20.224 |
| foundation_tracing memory | 288 / 593 | 659 / 45,508 | 0.248 | 0.243 |
| foundation_tracing mmap | 339 / 783 | 755 / 7,599 | 14.420 | 12.523 |
| kron async-memory-inline | 312 / 506 | 838 / 47,787 | 0.706 | 0.721 |
| kron async-mmap-inline | 331 / 610 | 830 / 47,630 | 10.941 | 14.849 |
| kron spsc-memory-inline | 305 / 526 | 290 / 446 | 0.809 | 1.048 |
| kron spsc-mmap-inline | 297 / 502 | 287 / 446 | 21.020 | 19.623 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.366 | 44.802 | 0.065 | 0.060 | 299.33 |
| foundation mmap | 67.875 | 52.375 | 0.224 | 0.066 | 299.33 |
| foundation_tracing memory | 45.898 | 46.651 | 0.012 | 0.010 | 299.33 |
| foundation_tracing mmap | 51.331 | 44.144 | 0.010 | 0.010 | 299.33 |
| kron async-memory-inline | 57.556 | 61.176 | 0.097 | 0.073 | 299.37 |
| kron async-mmap-inline | 67.615 | 75.323 | 0.040 | 0.033 | 299.37 |
| kron spsc-memory-inline | 56.688 | 54.285 | 0.035 | 0.032 | 299.03 |
| kron spsc-mmap-inline | 74.818 | 73.064 | 0.037 | 0.028 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 0.986 | 0.979..1.002 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.812 | 0.792..0.817 | peer_leads |
| async-memory-inline | foundation | 1 | sampled | 1.042 | 1.024..1.097 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.894 | 0.875..0.909 | peer_leads |
| async-memory-inline | foundation | 4 | batch | 0.736 | 0.708..1.025 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 0.763 | 0.756..0.768 | peer_leads |
| async-memory-inline | foundation | 4 | sampled | 0.707 | 0.676..0.718 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.749 | 0.726..0.778 | peer_leads |
| async-mmap-inline | foundation | 1 | batch | 0.836 | 0.833..0.847 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.662 | 0.647..0.663 | peer_leads |
| async-mmap-inline | foundation | 1 | sampled | 0.940 | 0.936..0.960 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.734 | 0.727..0.757 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 0.525 | 0.476..0.562 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.513 | 0.491..0.565 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.595 | 0.530..0.658 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.518 | 0.503..0.540 | peer_leads |
| spsc-memory-inline | foundation | 1 | batch | 1.004 | 0.995..1.027 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.824 | 0.810..0.838 | peer_leads |
| spsc-memory-inline | foundation | 1 | sampled | 1.080 | 1.057..1.108 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.916 | 0.902..0.928 | peer_leads |
| spsc-memory-inline | foundation | 4 | batch | 0.833 | 0.823..1.120 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.868 | 0.828..0.887 | peer_leads |
| spsc-memory-inline | foundation | 4 | sampled | 0.803 | 0.780..0.820 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.855 | 0.838..0.883 | peer_leads |
| spsc-mmap-inline | foundation | 1 | batch | 0.871 | 0.850..0.889 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.679 | 0.667..0.706 | peer_leads |
| spsc-mmap-inline | foundation | 1 | sampled | 0.966 | 0.938..1.005 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.757 | 0.753..0.771 | peer_leads |
| spsc-mmap-inline | foundation | 4 | batch | 0.608 | 0.565..0.628 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.594 | 0.573..0.652 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.625 | 0.613..0.737 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.585 | 0.567..0.610 | peer_leads |
