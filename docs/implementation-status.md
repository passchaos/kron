# 当前实现与验收状态

本页记录当前能力、最近门禁和未完成范围。设计目标见 [design.md](design.md)，使用入口见 [usage.md](usage.md)，历次实现和性能记录见 [历史验收快照](history/implementation-before-reorganization.md)。历史计数与测试结果绑定其当时源码，不能自动适用于后续 HEAD。


## 当前范围

Zig 0.16 的 Windows/Linux/macOS/Android/iOS 单机日志，覆盖同步、共享/SPSC 的 Memory/Mmap、text/JSON/logfmt/binary、结构化字段、配置、采样/脱敏、文件/轮转/归档、std.log 与显式 trace 关联。网络 sink/exporter 已移除。Linux 有实际运行资格，其他平台的运行资格独立跟踪。

`Logging` 是统一应用 owner，通过outputs列表管理独立route管线、轮转、稳定writer存储与各自Runtime。常规接入不需要选择第二个资源 owner；底层 Runtime 保留为高级扩展与已有 API。

Logging.Options只保留outputs列表和合计队列预算，默认值直接位于Route字段上。每route独立mode/queue/overflow/redaction/sampling与状态；轮转支持大小、纯时间间隔或两者任一触发，时间轮转在记录边界检查。

## 最近验证

当前源码基于58a9a9b，增加owner内部借用、单输出小Frame和多输出循环拆分。ReleaseSafe完整门禁151/151步骤成功、638项通过/1项系统local能力skip，包含独立源码分发、九目标对象、真实SIGKILL和全部示例；ReleaseFast管理/独立输出/capture/route策略61/61，另验证lazy provider修改caller时仍保留本次scope/trace快照。非Linux对象编译不替代设备运行。精确源码和验证见 [owner优化证据](../bench/evidence/2026-11-02-managed-owner-borrow/README.md)。

当前Logging与Foundation真实spdlog及Rust tracing前端完成200项试验、2020万条输出逐条核对。公共JSON为同元数据/五数值字段，原生build_tracing文本单列；稳态吞吐中位与两个组合互有胜负，全部跨库速度比仍因spread/区间保持inconclusive，SPSC p99.9和Mmap启动仍有明显差距。完整阶段和资格见 [当前前端对照](../bench/cpp_reference/evidence/2026-11-02-managed-frontends/detailed-comparison.md)。

常规应用继续以shared Memory/Mmap为主要路径，SPSC保留为高级可选。按channel预算分配counter/cache的后续实验能让普通Runtime少请求15KiB，但100项正式managed完整流程核对3010万条JSON后，P1 batch仍存在负向中位，主路径代价未排除，已恢复e40313f生产源码。资源probe、候选源码、全部慢值及撤回决策见 [线程预算实验](../bench/evidence/2026-11-02-thread-state-budget/README.md)；不据此更新跨库排名。

独立outputs接口的基线验证与当时4%~7%成本绑定58a9a9b，见 [独立输出报告](../bench/evidence/2026-11-02-independent-outputs/README.md)；源码路径和结构整理的早期门禁见 [整理报告](../bench/evidence/2026-11-02-reorganization/README.md)。系统local的八组队列/事件组合和六时区独立oracle继续通过，见 [本地时间证据](../bench/evidence/2026-11-01-system-local-time/README.md)。历史快照不替代当前源码资格。

## 能力与证据入口

| 能力 | 已有验证与文档 | 资格边界 |
| --- | --- | --- |
| Zig 包与应用 owner | 独立 b.dependency、五模式、源码分发、单线程；[包](package.md)、[指南](usage.md) | 版本固定 0.1.0，后续变更需要重新验证 |
| Typed fields/context | 标量、optional、nested、显式对象适配、borrowed/owned、Secret；[字段](capture.md)、[嵌套](structured-values.md) | 显式容器与固定节点/深度预算 |
| 编码与归档 | 四种输出、framing、legacy/current decode、短缓冲/变异、只读 Reader；[编码](encoding.md)、[压缩](compressed-archive.md) | journal/schema/event/archive 的版本独立 |
| 动态配置与策略 | 来源事务、scope filter、配置版本/lease、旧记录目标；[配置](configuration.md)、[predicate](predicates.md)、[采样](sampling.md) | full replacement 和 filter-only 更新的相位/所有权不同 |
| 有界 Memory/Mmap | 共享/SPSC、满队列策略、快照、无分配、schema；[存储](async-storage.md)、[schema](schema.md) | Memory 不恢复 pending，Mmap 至少一次重放 |
| 线程与生命周期 | 线程 token/generation、admission cut、deadline、关闭/失败唤醒；[生命周期](lifecycle.md)、[调度](consumer-scheduling.md) | timeout 不取消后台任务，destroy 是阻塞清理 |
| 文件、轮转与 io_uring | 短写、CQE/在途所有权、size/time/retention/reopen、实际同步；[文件](file-reliability.md) | 后端实现、设备能力与断电资格分别判断 |
| 进程恢复 | committed/reserved/gap/schema/热路由及随机 ACK 的真实 SIGKILL | 进程崩溃测试不能替代系统掉电测试 |
| Durable | 输出/checkpoint 同步顺序、fault sink、子 QEMU 停机恢复；[电源测试](../tests/power_loss/README.md) | 物理断电、多文件系统/设备仍需更广资格 |
| 时间、std.log、trace | RFC3339/固定偏移、独立 oracle、Bridge、显式 TraceContext；[时间](time.md)、[接口](api-design.md) | 固定偏移保持纯Zig，local采用系统DST规则；不内置IANA数据库或完整tracing任务/span生态 |
| 平台与单线程 | 九目标对象/部分链接；Linux 真实文件/恢复与单 OS 线程；[平台](platforms.md) | Windows/macOS/Android/iOS 仍缺设备运行 |
| 性能与应用影响 | 完整文件、用户态 PMU、同轮跨库、应用结果 oracle；[基准导航](../bench/README.md) | 多数完整吞吐/尾部组仍 inconclusive，无普遍最快保证 |

## 剩余工作的优先级

| 优先级 | 差距 | 后续验收 |
| --- | --- | --- |
| 1 | 稳定完整流程与跨库性能 | 对明确源码在低噪声环境建立同语义基线，包括 init/warmup/producer/written/shutdown/cleanup；不叠加历史百分比 |
| 1 | 尾延迟和过载对应用的影响 | burst、持续满队列、慢 sink、更多 producer；检查阻塞、积压年龄、CPU/cache/调度竞争及无 logger 基线 |
| 1 | Mmap 启动与资源成本 | 当前ce5aae9的四配置strace诊断核对8800条JSON，Mmap主要时间在文件/目录fsync；研究fresh初始化dirty-page/发布工作量，保持prefault与恢复/持久化边界。见 [启动诊断](../bench/evidence/2026-11-02-current-init-profile/README.md) |
| 2 | 更广业务/durable 回归覆盖 | 0/5/10 fields、长短字符串、P1/P4/P16、warm/cold、attach/detach、reload/rolling 与独立 durable 测量 |
| 2 | 更广故障、升级与持续 fuzz | 多文件系统/设备系统停机、物理掉电、长期 seed/sanitizer、nested/轮转/版本升级组合 |
| 2 | 非 Linux 平台运行 | 对目标设备实际日志、生命周期、journal 恢复及可用 durable 能力给出报告 |

当前主要功能有验证，完整的“业界最佳”目标仍在推进。后续状态更新只记录实际源码、运行结果或明确的平台能力拒绝。
