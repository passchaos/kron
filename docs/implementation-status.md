# 当前实现与验收状态

本页记录当前能力、最近门禁和未完成范围。设计目标见 [design.md](design.md)，使用入口见 [usage.md](usage.md)，历次实现和性能记录见 [历史验收快照](history/implementation-before-reorganization.md)。历史计数与测试结果绑定其当时源码，不能自动适用于后续 HEAD。

## 当前范围

Zig 0.16 的 Windows/Linux/macOS/Android/iOS 单机日志，覆盖同步、共享/SPSC 的 Memory/Mmap、text/JSON/logfmt/binary、结构化字段、配置、采样/脱敏、文件/轮转/归档、std.log 与显式 trace 关联。网络 sink/exporter 已移除。Linux 有实际运行资格，其他平台的运行资格独立跟踪。

`Logging` 是统一应用 owner，通过outputs列表管理独立route管线、轮转、稳定writer存储与各自Runtime。常规接入不需要选择第二个资源 owner；底层 Runtime 保留为高级扩展与已有 API。

Logging.Options只保留outputs列表和合计队列预算，默认值直接位于Route字段上。每route独立mode/queue/overflow/redaction/sampling与状态；轮转支持大小、纯时间间隔或两者任一触发，时间轮转在记录边界检查。

## 最近验证

截至 2026-11-10，完整 `test` 为 768/770（2 项 skip）；上一次完整
`verify-local` 为 804/805（1 项 local skip），本次 fixture/文档修复未重跑全部
故障 campaign。fixed-buffer schema encode 后完整 E-core 260-trial
矩阵（2,626 万条 JSON）durable 为 **24 kron lead / 4 peer lead / 36
inconclusive**，spool 为 **3/0/5**；剩余 4 个 peer lead 全部是 mmap 对
tracing。durable memory 已基本完成超越，P1 mmap batch 对 tracing 仍是主要
差距；`text_format`、`MmapSpool` 与 `render_cache` 是 opt-in 快速路径，默认
durable/CRC/recovery/queue 契约不变。

逐次候选、gate 计数、源码身份和全部正负结果已移到
[验证 chronology](history/verification-chronology-2026-11-09.md)。新增验证
追加到该 chronology；本页只更新当前结论、能力表和优先级。完整证据目录见
[证据索引](../bench/evidence/INDEX.md)。

## 能力与证据入口

| 能力 | 已有验证与文档 | 资格边界 |
| --- | --- | --- |
| Zig 包与应用 owner | 独立 b.dependency、五模式、源码分发、单线程；[包](package.md)、[指南](usage.md) | 版本固定 0.1.0，后续变更需要重新验证 |
| Typed fields/context | 标量、optional、nested、显式对象适配、borrowed/owned、Secret；[字段](capture.md)、[嵌套](structured-values.md) | 显式容器与固定节点/深度预算 |
| 编码与归档 | 四种输出、framing、legacy/current decode、短缓冲/变异、只读 Reader；[编码](encoding.md)、[压缩](compressed-archive.md) | journal/schema/event/archive 的版本独立 |
| 动态配置与策略 | 来源事务、scope filter、配置版本/lease、旧记录目标；[配置](configuration.md)、[predicate](predicates.md)、[采样](sampling.md) | full replacement 和 filter-only 更新的相位/所有权不同 |
| 有界 Memory/Mmap | 共享/SPSC、满队列策略、快照、无分配、schema；[存储](async-storage.md)、[schema](schema.md) | Memory 不恢复 pending，Mmap 至少一次重放 |
| 线程与生命周期 | 线程 token/generation、admission cut、deadline、关闭/失败唤醒；[生命周期](lifecycle.md)、[调度](consumer-scheduling.md) | timeout 不取消后台任务，destroy 是阻塞清理 |
| 文件、轮转与 io_uring | 短写、CQE/在途所有权、size/time/retention/reopen、实际同步；默认portable，io_uring显式可选；[文件](file-reliability.md) | 后端实现、设备能力与断电资格分别判断 |
| 进程恢复 | committed/reserved/gap/schema/热路由及随机 ACK 的真实 SIGKILL | 进程崩溃测试不能替代系统掉电测试 |
| Durable | 输出/checkpoint 同步顺序、fault sink、子 QEMU 停机恢复（ext4/XFS/Btrfs/F2FS 16-run campaigns）；[电源测试](../tests/power_loss/README.md) | 物理断电、NFS/设备仍需更广资格 |
| 时间、std.log、trace | RFC3339/固定偏移、独立 oracle、Bridge、显式 TraceContext；[时间](time.md)、[接口](api-design.md) | 固定偏移保持纯Zig，local采用系统DST规则；不内置IANA数据库或完整tracing任务/span生态 |
| 平台与单线程 | 九目标对象/部分链接；Linux 真实文件/恢复与单 OS 线程；[平台](platforms.md) | Windows/macOS/Android/iOS 仍缺设备运行 |
| 性能与应用影响 | 完整文件、用户态 PMU、同轮跨库、应用结果 oracle；[基准导航](../bench/README.md) | 多数完整吞吐/尾部组仍 inconclusive，无普遍最快保证 |

## 剩余工作的优先级

| 优先级 | 差距 | 后续验收 |
| --- | --- | --- |
| 1 | 超过 Foundation/logging + spdlog 与 Foundation/logging + tracing | 对明确源码在低噪声环境建立同语义基线，P-core/E-core分别覆盖 shared/SPSC、Memory/Mmap、P1/P4 与 batch/sampled，独立判断 init/warmup/producer/written/shutdown/cleanup 与 p99/p99.9；完整配对和噪声门限必须达标，不叠加历史百分比 |
| 1 | 尾延迟和过载对应用的影响 | 合成200µs慢sink/64槽诊断已记录：block P1/P4 p99约15–16ms且无丢失，P16 p99约59–81ms；drop p99亚微秒但丢936/1000或1535/1600，fallback p50约0.24ms；仍需burst、积压年龄、CPU/cache/调度竞争及无logger基线。见 [过载尾部诊断](../bench/evidence/2026-11-02-overload-tail/README.md) |
| 1 | Mmap 启动与资源成本 | fresh Linux mmap只写header初始化已把16.8MB journal init中位54.2/53.8ms降到8.2/6.9ms；仍需更广文件系统/设备、dirty-page与持久化边界验证。见 [fresh mmap证据](../bench/evidence/2026-11-02-mmap-fresh-zero-init/README.md)与 [启动诊断](../bench/evidence/2026-11-02-current-init-profile/README.md) |
| 2 | 更广业务/durable 回归覆盖 | 0/5/10 fields、长短字符串、P1/P4/P16、warm/cold、attach/detach、reload/rolling 与独立 durable 测量 |
| 2 | 更广故障、升级与持续 fuzz | journal/archive、regex/predicate与decoder随机fuzz已加入runner-seed扫描（1000/1000/1000 seeds），v1/v2升级兼容、pre-V3旧二进制v1/v2 fixture、nested prepared+rolling+schema journal+reopen组合、V3 child-VM abrupt-loss campaign与XFS/Btrfs/F2FS child-VM campaigns已加入回归；并发soak已有1000/200次重复；tmpfs/ext4与9p共享FS行为已对照；真实ENOSPC FileSink/Journal预分配错误与只读FS初始化拒绝已覆盖；仍缺Windows/macOS/Android/iOS旧二进制/更早历史格式fixture、NFS/CIFS/FUSE/设备系统停机、物理掉电与sanitizer（Zig TSan未instrument/Helgrind不兼容Zig atomics）/更长soak |
| 2 | 非 Linux 平台运行 | aarch64-linux-musl已在QEMU用户态执行root suite与fuzz；Windows/macOS/Android/iOS仍缺目标设备实际日志、生命周期、journal恢复及durable报告 |

当前主要功能有验证，完整的“业界最佳”目标仍在推进。后续状态更新只记录实际源码、运行结果或明确的平台能力拒绝。
