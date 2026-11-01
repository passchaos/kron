# 完整日志流程实测

共 200 个试验，逐条核对 20,200,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为五次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 2.205 | 2.320 | 2.155 | 2.317 | 无 |
| foundation mmap | 1.893 | 2.100 | 1.886 | 2.097 | 有 |
| kron async-memory-inline | 2.216 | 2.219 | 2.213 | 2.215 | 无 |
| kron async-memory-schema | 1.824 | 2.048 | 1.819 | 2.044 | 无 |
| kron async-mmap-inline | 2.231 | 2.243 | 2.227 | 2.239 | 有 |
| kron async-mmap-schema | 1.684 | 2.002 | 1.676 | 1.998 | 有 |
| kron spsc-memory-inline | 2.353 | 2.398 | 2.342 | 2.391 | 无 |
| kron spsc-memory-schema | 1.999 | 2.228 | 1.986 | 2.223 | 无 |
| kron spsc-mmap-inline | 2.327 | 2.367 | 2.322 | 2.360 | 有 |
| kron spsc-mmap-schema | 1.831 | 2.168 | 1.828 | 2.163 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 349 / 540 | 805 / 28,689 | 0.177 | 0.190 |
| foundation mmap | 493 / 868 | 991 / 7,982 | 24.804 | 22.728 |
| kron async-memory-inline | 371 / 639 | 792 / 29,333 | 0.562 | 0.537 |
| kron async-memory-schema | 541 / 856 | 943 / 30,416 | 0.589 | 0.567 |
| kron async-mmap-inline | 326 / 638 | 826 / 29,105 | 11.772 | 18.702 |
| kron async-mmap-schema | 527 / 1,712 | 970 / 30,396 | 14.236 | 12.161 |
| kron spsc-memory-inline | 386 / 598 | 283 / 605 | 0.653 | 0.926 |
| kron spsc-memory-schema | 499 / 748 | 459 / 706 | 0.676 | 0.937 |
| kron spsc-mmap-inline | 296 / 686 | 279 / 663 | 28.964 | 1248.936 |
| kron spsc-mmap-schema | 494 / 1,620 | 483 / 1,169 | 23.829 | 896.002 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 47.233 | 44.146 | 0.117 | 0.062 | 299.33 |
| foundation mmap | 77.850 | 70.924 | 0.274 | 0.066 | 299.33 |
| kron async-memory-inline | 46.588 | 46.484 | 0.030 | 0.023 | 299.37 |
| kron async-memory-schema | 56.293 | 50.232 | 0.035 | 0.023 | 299.37 |
| kron async-mmap-inline | 57.361 | 71.246 | 0.025 | 0.021 | 299.37 |
| kron async-mmap-schema | 579.501 | 507.879 | 0.067 | 0.021 | 299.37 |
| kron spsc-memory-inline | 44.358 | 43.439 | 0.023 | 0.024 | 299.03 |
| kron spsc-memory-schema | 51.862 | 46.716 | 0.039 | 0.021 | 299.03 |
| kron spsc-mmap-inline | 72.748 | 1290.771 | 0.024 | 0.027 | 299.03 |
| kron spsc-mmap-schema | 971.520 | 953.507 | 0.028 | 0.024 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
