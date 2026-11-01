# 当前Logging与Foundation两条前端的完整流程比较

JSON矩阵160/160项试验，逐条核验16,160,000条；原生tracing文本控制40项，逐条核验4,040,000条。所有试验accepted=written、pending/drop=0。

当前kron基于58a9a9b，包含内部owner借用、小入场帧与多输出循环拆分；源码归档和SHA256保留在同目录。主矩阵直接走Logging.scoped/attachThread，SPSC采用其默认spin策略；这不是此前显式sleep的高级Runtime基准。

主矩阵为相同逻辑事件、五个u64字段、完整JSON元数据与系统墙钟，每次100000事件、1000条排空预热、P1/P4、block、256队列槽、512B记录预算、64KiB文件缓冲、portable/written。默认采样none、空脱敏规则、JSON数值时间，单文件inline；性能范围是这一基础profile，其他功能启用后的成本应另测。关闭吞吐包含producer、后台格式化/写出、written flush、shutdown和资源清理，初始化/准备另列。

Foundation + spdlog使用真实C++ Logger.Native及Rust core。tracing公共JSON使用真实Subscriber/fmt和公开TracingMakeWriter，按typed字段构造同布局JSON；原生build_tracing文本单列保留其优化fmt writer。公开MakeWriter为每事件分配Vec并clone Backend，原生private fmt writer借用已格式化缓冲，两种入口不能混为一组。

## 完整关闭吞吐

| 路径 | Memory P1 M条/s | Memory P4 | Mmap P1 | Mmap P4 |
| --- | ---: | ---: | ---: | ---: |
| Foundation + spdlog | 2.020 | 2.088 | 1.820 | 2.067 |
| Foundation + tracing 公共JSON | 2.598 | 2.170 | 1.974 | 2.204 |
| kron Logging shared | 2.162 | 2.137 | 2.203 | 2.167 |
| kron Logging SPSC | 2.165 | 2.392 | 2.260 | 2.366 |

## 调用延迟

每行是sampled试验中位，单位ns，包含两次计时读数；保持原值，不减去noop。

| 路径 | 存储 | P1 p50 / p99 / p99.9 | P4 p50 / p99 / p99.9 |
| --- | --- | ---: | ---: |
| Foundation + spdlog | memory | 348 / 649 / 30,255 | 759 / 31,872 / 53,795 |
| Foundation + spdlog | mmap | 510 / 922 / 2,181 | 876 / 9,580 / 27,835 |
| Foundation + tracing 公共JSON | memory | 239 / 549 / 27,525 | 681 / 30,461 / 53,130 |
| Foundation + tracing 公共JSON | mmap | 478 / 837 / 1,947 | 935 / 10,460 / 25,735 |
| kron Logging shared | memory | 336 / 683 / 18,303 | 836 / 28,943 / 74,271 |
| kron Logging shared | mmap | 341 / 666 / 17,640 | 807 / 26,221 / 67,778 |
| kron Logging SPSC | memory | 334 / 713 / 17,212 | 291 / 467 / 350,774 |
| kron Logging SPSC | mmap | 325 / 587 / 17,828 | 287 / 452 / 348,925 |

## 初始化与100k完整生命周期

| 路径 | 存储 | P1 init ms | P4 init ms | P1生命周期 ms | P4生命周期 ms |
| --- | --- | ---: | ---: | ---: | ---: |
| Foundation + spdlog | memory | 0.213 | 0.210 | 50.450 | 49.300 |
| Foundation + spdlog | mmap | 21.003 | 25.999 | 79.001 | 75.437 |
| Foundation + tracing 公共JSON | memory | 0.186 | 0.196 | 39.462 | 47.008 |
| Foundation + tracing 公共JSON | mmap | 17.147 | 36.821 | 68.576 | 79.421 |
| kron Logging shared | memory | 0.582 | 0.599 | 48.204 | 48.509 |
| kron Logging shared | mmap | 542.823 | 12.643 | 588.913 | 59.783 |
| kron Logging SPSC | memory | 0.731 | 0.954 | 47.618 | 43.746 |
| kron Logging SPSC | mmap | 25.107 | 1234.763 | 72.229 | 1285.184 |

## 相对Foundation的重复性资格

比值为同轮配对吞吐kron/Foundation，>1代表kron更快。95%区间对五个配对比值作bootstrap；任一组spread超过10%，或区间跨1，结论保持inconclusive。

| kron模式 | 存储/producer | 对照 | 比值 | 95%区间 | 两组spread | 资格 |
| --- | --- | --- | ---: | --- | --- | --- |
| async | memory/P1 | Foundation + spdlog | 1.071 | 1.029..1.557 | 6.2% / 37.6% | inconclusive |
| async | memory/P1 | Foundation + tracing 公共JSON | 0.826 | 0.779..0.950 | 6.2% / 17.1% | inconclusive |
| async | memory/P4 | Foundation + spdlog | 1.001 | 0.900..1.070 | 13.2% / 11.3% | inconclusive |
| async | memory/P4 | Foundation + tracing 公共JSON | 0.943 | 0.901..1.037 | 13.2% / 16.9% | inconclusive |
| async | mmap/P1 | Foundation + spdlog | 1.204 | 0.909..1.543 | 44.7% / 25.7% | inconclusive |
| async | mmap/P1 | Foundation + tracing 公共JSON | 1.098 | 0.689..1.156 | 44.7% / 15.1% | inconclusive |
| async | mmap/P4 | Foundation + spdlog | 1.047 | 0.781..1.128 | 7.5% / 32.7% | inconclusive |
| async | mmap/P4 | Foundation + tracing 公共JSON | 0.967 | 0.907..1.115 | 7.5% / 19.9% | inconclusive |
| spsc | memory/P1 | Foundation + spdlog | 1.024 | 0.820..1.727 | 28.3% / 37.6% | inconclusive |
| spsc | memory/P1 | Foundation + tracing 公共JSON | 0.833 | 0.723..0.919 | 28.3% / 17.1% | inconclusive |
| spsc | memory/P4 | Foundation + spdlog | 1.145 | 1.052..1.174 | 1.5% / 11.3% | inconclusive |
| spsc | memory/P4 | Foundation + tracing 公共JSON | 1.102 | 0.967..1.122 | 1.5% / 16.9% | inconclusive |
| spsc | mmap/P1 | Foundation + spdlog | 1.320 | 1.180..1.584 | 10.1% / 25.7% | inconclusive |
| spsc | mmap/P1 | Foundation + tracing 公共JSON | 1.154 | 1.036..1.197 | 10.1% / 15.1% | inconclusive |
| spsc | mmap/P4 | Foundation + spdlog | 1.105 | 0.869..1.188 | 18.6% / 32.7% | inconclusive |
| spsc | mmap/P4 | Foundation + tracing 公共JSON | 1.053 | 0.940..1.236 | 18.6% / 19.9% | inconclusive |

## 原生Foundation build_tracing文本控制

这是标准Rust入口，输出UTC时间、level、file/line/thread及五个字段。它的输出布局和字节数与主JSON矩阵不同，单列实际结果，不据此作同格式速度比。

| 存储 | P1完整关闭 M条/s | P4完整关闭 | P1 p50/p99/p99.9 ns | P4 p50/p99/p99.9 ns | bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| memory | 1.364 | 2.487 | 516 / 1,014 / 19,674 | 767 / 19,885 / 31,922 | 156.44 |
| mmap | 0.868 | 2.227 | 1,023 / 2,842 / 3,698 | 1,217 / 7,643 / 38,149 | 156.44 |

## 范围和资源

Memory不恢复未交付记录，Mmap有进程崩溃恢复；本轮只有written确认，没有请求介质durable。Foundation保存producer已格式化文本，kron保存结构化事件并在consumer格式化，恢复/CRC/配置版本/route lease协议不同。SPSC的每producer队列还保留一个共享队列，其内存和Mmap启动工作更多。

固定CPU affinity来自manifest，宿主未独占CPU或文件系统。全部慢值、min/max和10%spread资格保留在analysis.json；中位表不能替代稳定资格。没有把历史局部优化百分比叠加为当前跨库排名。

完整原值在json/results.jsonl、native/results.jsonl；依赖、编译命令、当前生产源码和二进制SHA256在各manifest。详细阶段表保留producer/flush/shutdown/cleanup/init/preparation，便于区分稳态与冷启动。
