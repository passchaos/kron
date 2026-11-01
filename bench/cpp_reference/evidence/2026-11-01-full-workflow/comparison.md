# 完整日志流程实测

共 260 个试验，逐条核对 26,260,000 条完整日志。固定 CPU affinity：[0, 2, 4, 6, 8, 10]。

下表均为五次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.935 | 2.267 | 1.931 | 2.263 | 无 |
| foundation mmap | 1.830 | 2.360 | 1.252 | 2.355 | 有 |
| kron async-memory-inline | 1.044 | 1.073 | 1.043 | 1.072 | 无 |
| kron async-memory-schema | 0.838 | 1.103 | 0.837 | 1.102 | 无 |
| kron async-mmap-inline | 1.106 | 1.087 | 1.105 | 1.086 | 有 |
| kron async-mmap-schema | 1.129 | 1.114 | 1.125 | 1.113 | 有 |
| kron spsc-memory-inline | 1.154 | 1.134 | 1.152 | 1.132 | 无 |
| kron spsc-memory-schema | 1.208 | 1.109 | 1.207 | 1.108 | 无 |
| kron spsc-mmap-inline | 1.102 | 1.062 | 1.100 | 1.060 | 有 |
| kron spsc-mmap-schema | 1.243 | 1.075 | 1.241 | 1.072 | 有 |
| quill deferred_format | 2.262 | 1.650 | 2.255 | 1.645 | 无 |
| quill producer_format | 1.145 | 1.184 | 1.143 | 1.182 | 无 |
| spdlog producer_format | 1.659 | 0.846 | 1.658 | 0.846 | 无 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 452 / 810 | 695 / 31,512 | 0.194 | 0.216 |
| foundation mmap | 497 / 1,376 | 804 / 8,281 | 19.897 | 34.255 |
| kron async-memory-inline | 578 / 16,069 | 769 / 38,907 | 0.579 | 0.536 |
| kron async-memory-schema | 876 / 1,177 | 809 / 33,499 | 0.545 | 0.560 |
| kron async-mmap-inline | 496 / 23,209 | 801 / 36,791 | 13.790 | 37.281 |
| kron async-mmap-schema | 639 / 11,886 | 841 / 29,366 | 7.870 | 17.742 |
| kron spsc-memory-inline | 461 / 20,507 | 404 / 26,109 | 0.617 | 0.889 |
| kron spsc-memory-schema | 578 / 11,611 | 547 / 14,688 | 0.676 | 0.948 |
| kron spsc-mmap-inline | 441 / 22,500 | 404 / 25,731 | 13.359 | 61.359 |
| kron spsc-mmap-schema | 581 / 10,739 | 552 / 13,337 | 28.873 | 29.555 |
| quill deferred_format | 63 / 91 | 56 / 92 | 0.358 | 0.329 |
| quill producer_format | 270 / 451 | 341 / 570 | 0.337 | 0.368 |
| spdlog producer_format | 460 / 1,572 | 725 / 52,289 | 0.119 | 0.127 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 52.732 | 45.107 | 0.101 | 0.089 | 299.33 |
| foundation mmap | 85.899 | 77.397 | 0.100 | 0.091 | 299.33 |
| kron async-memory-inline | 97.645 | 96.152 | 0.033 | 0.028 | 299.37 |
| kron async-memory-schema | 121.778 | 92.556 | 0.039 | 0.028 | 299.37 |
| kron async-mmap-inline | 106.292 | 129.869 | 0.036 | 0.031 | 299.37 |
| kron async-mmap-schema | 104.909 | 138.112 | 0.028 | 0.022 | 299.37 |
| kron spsc-memory-inline | 88.479 | 90.307 | 0.023 | 0.022 | 299.03 |
| kron spsc-memory-schema | 84.688 | 92.477 | 0.028 | 0.024 | 299.03 |
| kron spsc-mmap-inline | 114.999 | 155.467 | 0.027 | 0.025 | 299.03 |
| kron spsc-mmap-schema | 120.681 | 168.481 | 0.023 | 0.036 | 299.03 |
| quill deferred_format | 45.410 | 62.668 | 0.131 | 0.146 | 299.03 |
| quill producer_format | 89.040 | 86.612 | 0.135 | 0.138 | 299.03 |
| spdlog producer_format | 61.221 | 122.428 | 0.027 | 0.028 | 299.33 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。
