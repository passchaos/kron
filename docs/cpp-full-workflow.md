# 完整日志工作流性能比较

按最新要求，仅Memory/Mmap的当前源码`182fc9e`已同轮比较Foundation真实spdlog前端＋Rust后台与kron默认四批配置：120/120试验、1212万条物理JSON逐条核对，accepted=written且pending/drop=0。Memory中位结果kron领先，Mmap P1中位领先、P4仍落后；所有Foundation吞吐组均超10%波动门限，所以仍未证明两种存储稳定全面超越。原始数据与源码见[当前Memory/Mmap对照](../bench/cpp_reference/evidence/2026-11-01-memory-mmap-current/README.md)。

| 当前Memory/Mmap配置 | P1包含关闭 M条/s | P4包含关闭 M条/s | P4完整生命周期 ms |
| --- | ---: | ---: | ---: |
| Foundation Memory |1.932|1.990|51.31|
| kron shared Memory |2.136|2.063|50.10|
| kron SPSC Memory |2.151|2.106|49.11|
| Foundation Mmap |1.789|2.097|62.04|
| kron shared Mmap |2.107|1.741|86.25|
| kron SPSC Mmap |2.157|1.911|446.39|

包含关闭吞吐计入producer、后台格式化/实际文件写出、最终written flush、shutdown和文件/对象清理；生命周期还计入初始化与预热。Mmap SPSC P4初始化中位368.10ms，对方13.01ms，慢值全部保留。P4 SPSC producer p99.9中位Memory387µs、Mmap372µs，Foundation约66µs/19µs；这些是调用attempt延迟，不是最终可见延迟。只有kron SPSC Memory P4包含关闭吞吐满足本轮局部重复性门限，不能用一侧稳定替代跨库优势资格。可选一批budget的p99/p99.9取舍另见[消费者服务预算](consumer-scheduling.md)，不混入默认排名。下方是各自较早源码的归档对照。

当前源码`4447fe6`已重新与Foundation（真实spdlog C++前端＋Rust后台）和独立spdlog 1.17做同轮完整文件流程对照：140个试验逐条验证1414万条JSON。kron的完整流程中位成绩高于独立spdlog，仍未全面超过Foundation组合；P4 memory约落后9%，P4 mmap稳态接近且差异小于波动，SPSC mmap完整生命周期初始化成本仍较高。源码归档、全部慢值与资格见[当前完整对照](../bench/cpp_reference/evidence/2026-11-01-current-workflow/README.md)。

| 当前源码配置 | P1包含关闭 M条/s | P4包含关闭 M条/s | P4完整生命周期 ms |
| --- | ---: | ---: | ---: |
| Foundation memory | 2.116 | 2.309 | 44.17 |
| Foundation mmap | 1.800 | 2.079 | 58.09 |
| spdlog async | 1.640 | 0.673 | 149.91 |
| kron async memory | 2.141 | 2.064 | 49.73 |
| kron async mmap | 2.188 | 2.075 | 70.45 |
| kron SPSC memory | 2.174 | 2.108 | 49.08 |
| kron SPSC mmap | 2.251 | 2.117 | 107.38 |

这是五次batch试验中位数；包含producer、后台格式化/文件写出、written flush、shutdown和清理。生命周期另包括初始化/预热。spdlog P1/P4 spread约28%/22%，Foundation P1 mmap约38%、P4 memory的关闭成本存在极慢值；达到10%局部重复性门限的其他组也不能仅凭1%–2%的中位差宣称跨库稳定领先。固定CPU affinity仍处于load约85–94的宿主窗口，稳定资格与不同业务负载继续验收。当前组未启用predicate，本轮正则优化的局部收益不用于解释该对照差异。

此前已实现 PCLMUL IEEE CRC、decoded-delivery 校验复用和 fused wire-to-record（JSON/text/logfmt），并在宿主 load 约 88–110 的同一窗口完成了 Foundation/kron 同轮复测：120 个试验、1212 万条记录全部通过独立 oracle，所有组因 spread 超门限标为 inconclusive。同轮中位数显示 kron 在 P1 memory/mmap 领先，P4 仍略落后 Foundation；该窗口不是稳定排名，安静窗口复测仍需完成。详细数据见 `bench/cpp_reference/evidence/2026-11-01-pclmul-same-round/`。下方保留早期源码归档表，不把不同源码窗口的数据混合排名。

2026-11-01跨库测量的归档快照中，kron尚未超过主要高性能C++参考库。单producer的Quill延迟格式化测得约2.26M条/s，Foundation Memory/Mmap约1.94M/1.83M；kron不同配置约0.84–1.24M。4个producer时Foundation约2.27–2.36M，Quill延迟格式化约1.65M，kron约1.06–1.13M。kron的4producer结果高于本轮spdlog async约0.85M。

这些是同一开发宿主的五次中位数，大多数吞吐和尾延迟的跨次spread超过10%门限，不能承诺稳定倍数或业界排名。它们仍明确显示当前的优化目标：既需要降低producer成本，也需要提高完整JSON的后台交付能力；极低入队延迟本身不能证明完整日志流程更快。

后续CRC、配置View复用和批内durable决策/written统计各有独立before/after测量，最新实现与门禁见 [验收清单](implementation-status.md) 和 [批内确认与统计](batch-accounting.md)。本文件的跨库数字保持归档身份，不把不同基线的局部变化叠加成当前排名；累计优化后的跨库比较须在同一轮重新测量。

## 机器、源码和输入

- Linux x86_64，Intel Core i9-13900K，32 logical CPU；子进程固定在CPU 0/2/4/6/8/10，选择同组物理核，未修改governor或预留整机。
- 输出位于本机NVMe ext4，单独的实际文件；每批100000条、排除1000条预热，1/4 producer，各5次sampled与5次batch。
- spdlog 1.17.0，Quill 13.1.0，对照时的kron源码快照（SHA256见归档），Foundation Logging 0.1.0源自本地onboard-monorepo提交 `0d1f5b0c5689a3fdc502b1c4c7ed8496eb1d5a94`，冻结拥有源码且未修改。
- C++ GCC13.3.0，`-O3 -DNDEBUG -pthread`；kron Zig0.16.0，应用与库均ReleaseFast；Foundation Rust1.101.0-nightly，锁定Cargo依赖release构建。
- 260个主试验逐条验证26260000条完整日志。所有配置为info、1个file目标、64KiB输出buffer、有界block队列，无rotation、sampling、redaction或额外console。

所有主试验输出同一JSON字段布局：timestamp_ns、severity、scope、message、session、channel、sequence、route_mask、config_generation、trace_flags、5个u64 attributes。标准系统墙钟由对应库调用，timestamp值自然不同；固定session宽度，channel/sequence按库分配，保证事件身份唯一。每条约299字节，字段和值、物理newline、ID集合与文件字节数在完整关闭后逐条核对。没有用C++更小的输出与kron完整JSON混排。

## 计时终点

1. `init_ns`：文件、logger/runtime、队列与后台初始化。
2. `preparation_ns`：producer创建、attachment/预注册、预热和预热flush。
3. `producer_wall_ns`：从放开barrier到全部producer join完成；后台同步重叠工作。
4. `flush_ns`：全部测量记录的written flush完成。
5. `shutdown_ns`：后台停止与join；Quill还移除logger，Foundation执行Close，kron执行shutdown(drain)。
6. `cleanup_ns`：剩余runtime/logger/sink对象释放与文件关闭。

written+flush吞吐使用100000/(3+4)；包含关闭的吞吐使用100000/(3+4+5+6)；lifecycle时间包括1到6及1000条预热。测试结束后的排序、报告格式化和文件读回验证在计时外。不计应用在进入main前的启动和退出，也没有请求设备durable/fdatasync；这是完整written工作流，不能冒充断电持久化性能。

sampled进程的producer调用分别读取一对单调时钟，报告p50/p99/p99.9；batch进程不进行逐条延迟计时。noop时钟对开销单独报告、没有减掉。下表producer分位数不是单条日志最终写出或可见延迟。

## 完整流程与调用延迟结果

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

## Foundation 原生默认formatter控制组

统一JSON通过公开formatter扩展点实现，Foundation在producer调用真实CoreSink/Rust后台；它的已优化默认文本formatter没有用于这组统一JSON。为避免忽略默认formatter优势，另外用其原始默认formatter运行40个同机控制试验，逐条验证4040000条日志。仍为同样事件ID和5个数字字段，但默认日期/level/name/thread前缀加JSON消息约175字节/条。

| Foundation模式 | 1线程written+flush M条/s | 4线程written+flush M条/s | 1线程调用p50/p99 ns | 4线程调用p50/p99 ns |
| --- | ---: | ---: | ---: | ---: |
| memory | 2.944 | 2.422 | 268/554 | 523/22,681 |
| mmap | 2.436 | 2.434 | 487/826 | 643/15,784 |

这组结果属于Foundation本身的默认格式体验，输出与主矩阵不同，不能直接把默认格式倍率用于评价kron完整JSON。它保留64KiB文件buffer与显式预算，未使用Foundation所有生产默认容量。纯Memory两者都没有进程崩溃恢复；Foundation单Mmap和kron mmap都保留已提交待写事件，但格式、checkpoint、目录durability和动态路由能力不同。

## 2026-11-01 负载窗口同轮复测（inconclusive）

同一宿主 load 约 88–110 的窗口，当前 kron 源码（PCLMUL CRC、decoded delivery、fused wire-to-record）与 Foundation 同轮运行 120 个试验，逐条验证 1212 万条物理 JSON；每 trial accepted=written=100000、pending/drop=0。所有吞吐组 relative spread 0.11–1.00，故全部标为 inconclusive，不作为稳定排名。

| 配置 | Foundation 中位 M条/s | kron 中位 M条/s | 方向 |
| --- | ---: | ---: | --- |
| Memory P1 | 1.521 | async memory 1.906 / SPSC memory 2.039 | kron 领先 |
| Memory P4 | 2.224 | async memory 1.938 / SPSC memory 2.043 | Foundation 领先 |
| Mmap P1 | 1.820 | async mmap 1.730 / SPSC mmap 2.167 | SPSC 领先；async 略低 |
| Mmap P4 | 2.204 | async mmap 1.988 / SPSC mmap 2.061 | Foundation 领先 |

producer p50/p99（sampled）显示 P1 调用延迟已与 Foundation 接近：Memory P1 Foundation 349/713ns，kron async 348/1781ns、SPSC 473/877ns；Mmap P1 Foundation 513/926ns，kron async 417/814ns、SPSC 480/861ns。P4 SPSC p50 更低（约 290ns），但完整 written+flush 吞吐仍略低于 Foundation。该窗口说明 PCLMUL/decoded/fused 优化已把差距从归档快照的约 0.46–0.60× 明显缩小，但尚未取得稳定“超过 Foundation”的证据；安静窗口复测仍是必要步骤。原始数据见 `bench/cpp_reference/evidence/2026-11-01-pclmul-same-round/`。

## 资源和实现差异

| 项目 | 本轮设置 |
| --- | --- |
| spdlog | 256个共享async_msg，1个worker，message在producer格式化并复制；payload可能分配；JSON时间前缀在自定义FILE sink写出 |
| Quill | 每producer 64KiB bounded-blocking SPSC队列，额外flush线程队列和每线程最多256-record transit buffer，1个backend；producer-format/deferred两种策略分别标注 |
| Foundation Memory | queue_capacity=256、queue_capacity_bytes=128KiB、无critical reserve，原始spdlog前端与Rust后台；完整formatter在producer执行 |
| Foundation Mmap | 256个576字节slot、4096字节头、约148KiB单共享spool；保存已格式化完整日志；每批先输出flush再回收 |
| kron shared | 256个固定slot、512字节payload，inline约148KiB；预注册追加独立schema表，typed值捕获和后台JSON格式化 |
| kron SPSC | 同样主journal加每producer一个256-slot channel，P1/P4分别有2/5份队列；schema每队列另占固定空间 |

队列单位和后端暂存并不完全相同，不声称严格相同总内存。所有记录通过同一逻辑payload校验；prepared schema只减少重复metadata捕获，固定slot不会因此变小。时间戳都选择系统墙钟，未使用Quill默认TSC或kron ZeroClock；库自己的idle/wait实现不同。

本轮不包含轮转触发、压缩、长字符串、nested字段、热配置、磁盘故障或durable flush，也没有测试NanoLog/Binlog二进制输出。因此这是一个明确业务负载的完整流程比较，不是所有特性的性能排名。

## 波动、启动和关闭

所有完成试验和离群值都保留。mmap初始化有毫秒级中位值，也出现秒级尾部：Foundation约5.4–1817ms，kron各mmap配置约5.4–5176ms；不能把磁盘/调度与不同协议成本单凭这些数字归因到某一个库。Foundation部分关闭出现约0.5–0.75秒离群，造成某些包含关闭的中位数与flush-only结果差异；它们没有被删掉或改记失败。

lifecycle表的每个数字是对应完整区间的中位数，各阶段中位数不能相加重建同一个试验。大多数指标超过10%spread门限，详细min/max、spread和资格在analysis.json中。只有少数组合达到本轮局部重复性门限，不能将其推广成跨机器保证。

早期归档快照的结论是：Quill的延迟格式化显著减少producer工作；Foundation在该轮完整文件流程中更快；当时kron与spdlog的相对结果取决于producer数。最新当前源码结果以页首同轮数据为准；后续优化仍按完整输入profile与完成边界验证，不省略元数据或降低可靠性来声明优势。

原始结果、精确测量源码归档、编译/依赖哈希与当前验证见 [本地验收报告](../bench/cpp_reference/evidence/2026-11-01-full-workflow/README.md)。执行与复现命令见 [C++比较入口](cpp-comparison.md)。
