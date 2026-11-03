# 完整日志流程实测

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.795 | 2.193 | 1.793 | 2.190 | 无 |
| foundation mmap | 2.130 | 2.672 | 2.099 | 2.667 | 有 |
| foundation_tracing memory | 2.157 | 2.236 | 2.154 | 2.201 | 无 |
| foundation_tracing mmap | 2.831 | 3.253 | 2.825 | 3.245 | 有 |
| kron async-memory-inline | 1.750 | 2.647 | 1.743 | 2.637 | 无 |
| kron async-memory-schema | 1.995 | 1.867 | 1.989 | 1.860 | 无 |
| kron async-mmap-inline | 1.746 | 2.724 | 1.739 | 2.708 | 有 |
| kron async-mmap-schema | 1.950 | 1.871 | 1.941 | 1.866 | 有 |
| kron spsc-memory-inline | 1.905 | 1.936 | 1.900 | 1.926 | 无 |
| kron spsc-memory-schema | 1.958 | 2.031 | 1.952 | 2.022 | 无 |
| kron spsc-mmap-inline | 1.887 | 1.935 | 1.876 | 1.926 | 有 |
| kron spsc-mmap-schema | 1.960 | 2.039 | 1.950 | 2.030 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 379 / 816 | 669 / 46,696 | 0.306 | 0.275 |
| foundation mmap | 443 / 880 | 725 / 7,432 | 19.591 | 170.076 |
| foundation_tracing memory | 288 / 673 | 663 / 47,869 | 0.283 | 0.278 |
| foundation_tracing mmap | 332 / 774 | 793 / 9,283 | 479.679 | 39.917 |
| kron async-memory-inline | 507 / 826 | 962 / 9,403 | 0.802 | 0.790 |
| kron async-memory-schema | 416 / 597 | 851 / 35,362 | 0.783 | 0.756 |
| kron async-mmap-inline | 483 / 690 | 1,010 / 9,175 | 11.743 | 991.732 |
| kron async-mmap-schema | 416 / 624 | 771 / 31,963 | 8.409 | 17.290 |
| kron spsc-memory-inline | 302 / 549 | 283 / 458 | 0.842 | 1.075 |
| kron spsc-memory-schema | 456 / 635 | 438 / 612 | 0.859 | 1.078 |
| kron spsc-mmap-inline | 297 / 555 | 284 / 447 | 372.565 | 74.227 |
| kron spsc-mmap-schema | 455 / 621 | 440 / 627 | 39.560 | 53.391 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.886 | 46.857 | 0.062 | 0.061 | 299.33 |
| foundation mmap | 69.160 | 205.383 | 0.092 | 0.071 | 299.33 |
| foundation_tracing memory | 47.544 | 46.444 | 0.014 | 0.011 | 299.33 |
| foundation_tracing mmap | 515.613 | 70.932 | 0.013 | 0.013 | 299.33 |
| kron async-memory-inline | 59.006 | 39.567 | 0.086 | 0.039 | 299.37 |
| kron async-memory-schema | 51.936 | 55.399 | 0.038 | 0.043 | 299.37 |
| kron async-mmap-inline | 73.843 | 1045.225 | 0.081 | 0.078 | 299.37 |
| kron async-mmap-schema | 78.479 | 73.419 | 0.045 | 0.036 | 299.37 |
| kron spsc-memory-inline | 54.303 | 53.837 | 0.031 | 0.032 | 299.03 |
| kron spsc-memory-schema | 53.001 | 51.346 | 0.036 | 0.034 | 299.03 |
| kron spsc-mmap-inline | 426.723 | 126.997 | 0.034 | 0.032 | 299.03 |
| kron spsc-mmap-schema | 129.204 | 890.086 | 0.039 | 0.034 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.114 | 0.926..1.227 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.811 | 0.785..0.931 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.017 | 0.919..1.189 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.879 | 0.786..0.950 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 1.204 | 0.714..1.318 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.139 | 0.754..21.445 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.277 | 0.957..1.299 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.267 | 0.944..1.292 | inconclusive |
| async-memory-schema | foundation | 1 | batch | 1.091 | 1.037..1.391 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | batch | 0.912 | 0.849..0.936 | peer_leads |
| async-memory-schema | foundation | 1 | sampled | 1.217 | 1.052..1.232 | inconclusive |
| async-memory-schema | foundation_tracing | 1 | sampled | 0.985 | 0.899..1.051 | inconclusive |
| async-memory-schema | foundation | 4 | batch | 0.853 | 0.816..0.865 | peer_leads |
| async-memory-schema | foundation_tracing | 4 | batch | 0.845 | 0.819..14.286 | inconclusive |
| async-memory-schema | foundation | 4 | sampled | 0.873 | 0.817..0.882 | peer_leads |
| async-memory-schema | foundation_tracing | 4 | sampled | 0.853 | 0.812..0.893 | peer_leads |
| async-mmap-inline | foundation | 1 | batch | 0.831 | 0.797..1.002 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.603 | 0.582..0.744 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 0.965 | 0.940..0.984 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.766 | 0.700..0.780 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.009 | 0.721..1.023 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.849 | 0.598..0.887 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.822 | 0.636..1.290 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.966 | 0.684..1.080 | inconclusive |
| async-mmap-schema | foundation | 1 | batch | 0.931 | 0.793..0.957 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | batch | 0.687 | 0.580..0.713 | inconclusive |
| async-mmap-schema | foundation | 1 | sampled | 0.996 | 0.969..1.039 | inconclusive |
| async-mmap-schema | foundation_tracing | 1 | sampled | 0.768 | 0.753..0.802 | peer_leads |
| async-mmap-schema | foundation | 4 | batch | 0.694 | 0.636..0.719 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | batch | 0.575 | 0.559..0.589 | peer_leads |
| async-mmap-schema | foundation | 4 | sampled | 0.546 | 0.478..0.872 | inconclusive |
| async-mmap-schema | foundation_tracing | 4 | sampled | 0.646 | 0.514..0.716 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.040 | 0.684..1.400 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.882 | 0.572..0.896 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.116 | 1.026..1.218 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.928 | 0.867..0.991 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 0.859 | 0.834..0.912 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.863 | 0.835..15.274 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 0.900 | 0.545..0.916 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.893 | 0.540..0.910 | inconclusive |
| spsc-memory-schema | foundation | 1 | batch | 1.098 | 1.068..1.396 | inconclusive |
| spsc-memory-schema | foundation_tracing | 1 | batch | 0.901 | 0.893..0.931 | peer_leads |
| spsc-memory-schema | foundation | 1 | sampled | 1.205 | 1.173..1.262 | kron_leads |
| spsc-memory-schema | foundation_tracing | 1 | sampled | 1.014 | 0.973..1.029 | inconclusive |
| spsc-memory-schema | foundation | 4 | batch | 0.931 | 0.784..0.971 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | batch | 0.904 | 0.828..16.250 | inconclusive |
| spsc-memory-schema | foundation | 4 | sampled | 0.932 | 0.869..0.970 | inconclusive |
| spsc-memory-schema | foundation_tracing | 4 | sampled | 0.926 | 0.857..0.981 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.883 | 0.728..0.968 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.649 | 0.532..0.731 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 0.982 | 0.525..1.005 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.769 | 0.400..0.795 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 0.704 | 0.660..0.743 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.589 | 0.580..0.621 | peer_leads |
| spsc-mmap-inline | foundation | 4 | sampled | 0.581 | 0.487..0.880 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.667 | 0.523..0.764 | inconclusive |
| spsc-mmap-schema | foundation | 1 | batch | 0.946 | 0.908..0.952 | peer_leads |
| spsc-mmap-schema | foundation_tracing | 1 | batch | 0.683 | 0.674..0.720 | peer_leads |
| spsc-mmap-schema | foundation | 1 | sampled | 1.029 | 0.961..1.035 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 1 | sampled | 0.794 | 0.733..0.829 | inconclusive |
| spsc-mmap-schema | foundation | 4 | batch | 0.733 | 0.638..0.777 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | batch | 0.614 | 0.561..0.639 | inconclusive |
| spsc-mmap-schema | foundation | 4 | sampled | 0.625 | 0.591..0.824 | inconclusive |
| spsc-mmap-schema | foundation_tracing | 4 | sampled | 0.708 | 0.594..0.779 | inconclusive |
