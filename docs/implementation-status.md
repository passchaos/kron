# 当前实现与验收状态

本页记录当前能力、最近门禁和未完成范围。设计目标见 [design.md](design.md)，使用入口见 [usage.md](usage.md)，历次实现和性能记录见 [历史验收快照](history/implementation-before-reorganization.md)。历史计数与测试结果绑定其当时源码，不能自动适用于后续 HEAD。


## 当前范围

Zig 0.16 的 Windows/Linux/macOS/Android/iOS 单机日志，覆盖同步、共享/SPSC 的 Memory/Mmap、text/JSON/logfmt/binary、结构化字段、配置、采样/脱敏、文件/轮转/归档、std.log 与显式 trace 关联。网络 sink/exporter 已移除。Linux 有实际运行资格，其他平台的运行资格独立跟踪。

`Logging` 是统一应用 owner，通过outputs列表管理独立route管线、轮转、稳定writer存储与各自Runtime。常规接入不需要选择第二个资源 owner；底层 Runtime 保留为高级扩展与已有 API。

Logging.Options只保留outputs列表和合计队列预算，默认值直接位于Route字段上。每route独立mode/queue/overflow/redaction/sampling与状态；轮转支持大小、纯时间间隔或两者任一触发，时间轮转在记录边界检查。

## 最近验证

当前保留JSON属性前缀直接输出（cold fallback保持原短写/UTF8/保留key行为）与不可变predicate route位图。最终完整Safe/分发/九目标门禁149/149步骤、623/624测试通过（1默认local skip，专项实际执行）。最终40项文件PMU四组instructions约减少3.04%–3.06%，但Memory P1 cycles约+2.1%局部负向，完整吞吐仍不确定；早期组合P-core P1百万条−3.7%负向和cold/单机制复测全部保留。应用400项核对480万请求、221万完整JSON，32个logged版本吞吐组31个不确定、1个局部领先，无稳定业务回退资格。同源码320项Foundation前端对照核对3232万JSON：E-core对tracing12组/对spdlog10组peer领先；P-core对tracing2组/对spdlog1组kron局部领先，其余不确定，仍未全面超过。源码、全部正负、整数候选否决见[JSON member证据](../bench/evidence/2026-11-02-json-member-direct/README.md)。

当前保留IEEE CRC四lane直接合并：相同六次PCLMUL的依赖层数从3降1，原header/reference/payload分段、tail、seed/final XOR、三个校验点与恢复协议保持。独立GF2基/bitwise/zlib oracle和native任意seed/长度/对齐通过；ReleaseSafe完整门禁149/149步骤、621/622测试通过（1项默认local能力skip），local专项实际执行。320项双拓扑before/after核对3232万JSON，E-core4组/P-core2组关闭吞吐局部领先，其余大多不确定；短P-core SPSC Memory P1 batch负向在百万条复测未重现，所有慢值保留。另同源码320项Foundation对照核对3232万JSON：E-core对tracing 14组peer领先、对spdlog 5组peer领先/2组kron领先；P-core对tracing6组、对spdlog3组kron局部领先，其余不确定，仍未全面超过。源码/门禁/全部数据见[CRC合并证据](../bench/evidence/2026-11-02-crc-parallel-collapse/README.md)。

固定64片shared admission候选通过协议/生命周期测试，E-core P4 cycles局部下降10~12%，但280项完整流程核对4428万JSON后存在尾部/吞吐负向且每Runtime增4096B，已全部撤回；保留独立final-admission无记录唤醒回归。资源、源码与否决见[shared admission实验](../bench/evidence/2026-11-02-shared-admission/README.md)。

2026-11-02前缀CRC候选完成240项完整shared before/after、2424万条JSON核对，第二候选16组配对中位全部提高、11组通过局部门限；但扩展CRC长度出现明显负向，全部候选已撤回，生产CRC恢复97353ff。候选另完成P-core/E-core各160项Foundation spdlog/tracing对照，总核对3232万条JSON；E-core对tracing 12组peer领先、对spdlog 9组peer领先/3组kron领先，P-core多数不确定，未证明同时超过两个前端。该候选结果不作为当前生产源码新排名。保留完整配对资格、manifest组/轮次校验与原分段扩展CRC基准，12项资格/矩阵测试和相关报告gate通过；源码、原始正负值与撤回见[实验报告](../bench/evidence/2026-11-02-prefixed-crc/README.md)。

当前源码在7480598之后保留native八位十进制分块与冷buffered输出。ReleaseSafe完整验证151步骤成功、639项通过/1项系统local能力skip，包含独立源码分发、九目标对象、真实SIGKILL和全部示例；数字模块Debug/Safe/Fast与generic CPU各6项、encoder重点52项通过，AArch64另完成编译。140项真实文件核对4214万JSON，shared Memory/Mmap P1/P4的完整用户态指令稳定减少3.43%–3.47%；完整速度与尾部保持inconclusive。精确源码、正负版本、风险复测与验证见 [数字分块证据](../bench/evidence/2026-11-02-decimal-u32-chunks/README.md)。非Linux对象编译不替代设备运行。

随后保留 checked wire typed visitor 与内联 scalar 渲染：`WireInput.valueWith` 在完成同一套树检查后直接回调 typed payload，融合 renderer 跳过中间 `Value` 和通用二次分派；公开 API、aggregate 验证边界和错误优先级不变。40项完整 shared 真实文件核对1204万JSON，Memory/Mmap P1/P4 用户态指令中位减少1.65%–1.69%，四组CV/spread达标且中位区间不重叠；80项workflow与20项P4 sampled复测的完整吞吐/尾部仍正负混合或inconclusive。独立before/after差分17527次比较、9769个valid mutation三格式逐字节一致；ReleaseSafe完整门禁151/151步骤、640/641项通过（1项系统local能力skip），包含源码分发、九目标对象、真实SIGKILL和示例。源码、被否决的outlined版本和全部原始数据见 [wire scalar证据](../bench/evidence/2026-11-02-wire-scalar-render/README.md)。

JSON固定metadata的timestamp/session/sequence/route_mask/config_generation现直接以comptime tag和原始i64/u64写出，跳过临时`Value`、运行时tag分派和u64→u128宽整数路径。40项完整shared核对1204万JSON，四组用户态指令中位减少2.45%–2.48%；80项未插桩workflow核对2408万JSON，八组written吞吐全为正（+0.95%–+5.55%），六组达到本轮噪声门限，Memory/Mmap P4 batch中位区间不重叠。text/logfmt控制组、cycles和尾部波动继续保留，不作为一般速度/尾部承诺。源码、全部正负数据与复现见 [metadata证据](../bench/evidence/2026-11-02-wire-metadata-direct/README.md)。

JSON severity字段改为按Level枚举选择一个完整literal、一次写出，`err`仍保持原`"err"`拼写；text/logfmt不变。JSON encoder probe instructions中位−2.05%；40项完整shared核对1204万JSON，四组用户态指令中位减少1.68%–1.70%。80项workflow吞吐正负混合（Memory P1 batch +6.35%、P4 sampled −5.91%、Mmap P1 batch −1.37%等），不据此宣称一般吞吐收益。源码与全部正负数据见 [severity证据](../bench/evidence/2026-11-02-json-severity-literal/README.md)。

另用同负载对比`fd4e941`与当前源码：E-core 5次batch中current的Memory P1/P4、Mmap P1/P4分别快14.6%/11.8%/11.4%/7.2%，没有近期优化造成的E-core回退。P-core窗口受宿主负载影响较大（Mmap P1出现1.32–2.07M波动），不能把单个负向中位当回归。E-core相对Foundation仍落后，来自journal CRC/恢复、typed capture与consumer格式化的功能成本，而不是这些优化；证据见 [A/B](../bench/evidence/2026-11-02-fd4e941-current-ab/README.md)。

Memory journal初始化原先在`Storage.createMemory`完整清零后由`format.initialize`再次清零，并额外逐页写0；现在memory backing只保留一次完整writable清零，header/checkpoint由`initializeZeroed`/`initializeV2Zeroed`写出，该轮file/mmap仍完整清零。16.8MB journal的batch runtime init中位9.13ms→6.64ms（5/5配对下降），sampled 10.79ms→6.99ms（区间仍重叠）；512B小队列差异低于宿主噪声。该结果只针对初始化局部成本，不代表吞吐或跨库排名；当前ReleaseSafe完整门禁151/151步骤、642/643项通过（1项系统local能力skip），包含新增fresh mmap零契约测试。源码、原始配对数据与复现见 [memory init证据](../bench/evidence/2026-11-02-memory-init-zeroing/README.md)。

Fresh Linux mmap现在在ext4/XFS/btrfs/F2FS等能证明fresh extents读为零的文件系统上只写header/checkpoint，并依赖`MAP_POPULATE`跳过整段清零与逐页写；未知文件系统继续完整清零，Windows/Darwin保留prefault但改为只读touch。16.8MB journal的sampled/batch init中位54.2/53.8ms→8.2/6.9ms，5/5配对下降且中位区间不重叠；512B小队列差异低于宿主噪声。ext4新文件与截断后扩展文件的16MiB探针均为0个非零字节。该结果不代表稳态吞吐、durable或非Linux设备资格；源码、原始配对数据与复现见 [fresh mmap证据](../bench/evidence/2026-11-02-mmap-fresh-zero-init/README.md)。

owner内部借用、单输出小Frame和多输出循环拆分的早期验证仍绑定当时源码，见 [owner优化证据](../bench/evidence/2026-11-02-managed-owner-borrow/README.md)；当前完整门禁继续保留lazy provider修改caller时的scope/trace快照和多输出所有权边界。

最近一次完整同轮跨库对照使用fd4e941的Logging基线，与Foundation真实spdlog及Rust tracing前端完成200项试验、2020万条输出逐条核对。公共JSON为同元数据/五数值字段，原生build_tracing文本单列；稳态吞吐中位与两个组合互有胜负，全部跨库速度比仍因spread/区间保持inconclusive，SPSC p99.9和Mmap启动仍有明显差距。最新数字输出优化不推导该比较的新排名，完整阶段和资格见 [前端对照](../bench/cpp_reference/evidence/2026-11-02-managed-frontends/detailed-comparison.md)。

另以当前bc908cc完成60项raw spdlog/kron缩减同轮抽查，核对606万条JSON；Memory P4 batch的配对吞吐中位3.499、比值spread 6.2%且区间不跨1，其余Memory组因spread或区间保持inconclusive。该入口是raw spdlog而非Foundation封装，且宿主非安静窗口，因此不更新Foundation/tracing排名，也不把3.5倍外推到Mmap或其他组；全部数据见 [缩减抽查](../bench/cpp_reference/evidence/2026-11-02-current-managed-frontends/README.md)。

随后完成80项Foundation + spdlog/kron缩减同轮抽查，核对808万条JSON。Memory P1 batch配对吞吐中位1.125、95%区间1.056..1.146，Foundation/kron两侧spread 6.5%/7.9%，达到本轮局部重复性；Memory P4、Mmap P1/P4及其余sampled组仍因spread或区间跨1保持inconclusive。该窗口同时显示kron完整生命周期与shutdown中位更快，但Memory init约0.587ms vs Foundation 0.182ms、Mmap init约14.073ms vs 12.383ms，初始化/资源成本仍是独立差距。该窗口不替代原200项Foundation/tracing矩阵，也不推广为一般跨库排名；全部正负数据见 [Foundation抽查](../bench/cpp_reference/evidence/2026-11-02-current-foundation-spotcheck/README.md)。

再以当前647e667完成两次相同配置的80项Foundation + Rust tracing/kron缩减同轮抽查，各核对808万条JSON。首轮曾出现Memory P1 sampled tracing领先约11%、Memory P4 sampled与Mmap P4 batch kron领先约12%/11%的局部资格；相同配置第二轮未复现：Memory P1 sampled方向一致但spread 18.3%，Memory P4 sampled接近持平（1.016×），Mmap P4 batch方向翻转为tracing领先（0.894×），全部inconclusive。因此当前P-core tracing对照保持inconclusive，不能把首轮局部资格作为跨库排名；Memory P1的tracing中位方向两次一致，但第二次不达标。该窗口mmap init kron约11.2/14.1ms、tracing约19.3/19.5ms，memory init仍约0.55ms vs 0.15ms。完整200项安静窗口矩阵仍需重跑。数据见 [tracing抽查](../bench/cpp_reference/evidence/2026-11-02-current-tracing-spotcheck/README.md)与 [复测](../bench/cpp_reference/evidence/2026-11-02-current-tracing-spotcheck-2/README.md)。

另在无SMT兄弟的物理核（当前主机CPU16/18/20/22/24/26，通常对应E-core）完成两组80项缩减同轮抽查，各核对808万条JSON。tracing在8组中位全部更高，其中5组达到两侧spread/区间门限；Foundation + spdlog有5组达到门限领先，P4与Mmap差距尤其明显（Mmap P4 batch约0.580×）。这与P-core窗口kron中位多数领先形成明显反差，说明当前完整流程性能对CPU拓扑高度敏感。不能把任一窗口作为全面排名；后续需分别profile P-core/E-core的producer、journal reserve/CRC、consumer格式化与交付阶段，并在两种拓扑重跑完整矩阵。数据见 [E-core tracing](../bench/cpp_reference/evidence/2026-11-02-current-tracing-quiet-affinity/README.md)与 [E-core spdlog](../bench/cpp_reference/evidence/2026-11-02-current-foundation-quiet-affinity/README.md)。

随后完成E-core 160项完整JSON矩阵（16,160,000条逐条核对）及40项原生tracing文本控制。tracing在16个JSON对照中全部领先kron async/SPSC；Foundation + spdlog在多数P4/Mmap组领先；kron async仅Memory P1 batch接近持平（1.002×），SPSC Memory P1 sampled略领先（1.063×），其余组落后。SPSC比async在E-core提高约5%–15%，但不足以改变Foundation领先。该矩阵绑定当前c0b9706源码，不替代P-core或功能归一化比较；数据见 [E-core完整矩阵](../bench/cpp_reference/evidence/2026-11-02-managed-frontends-ecore-full/README.md)。

同一源码的P-core 160项完整JSON矩阵（16,160,000条）在默认CPU0/2/4/6/8/10窗口运行，但宿主负载使大多数组spread超10%，配对比较保持inconclusive。方向上kron async/SPSC对spdlog多数≥1；对tracing在Memory P1/Mmap P1落后、在P4部分领先；没有全面胜者。P-core与E-core的拓扑反差必须分别记录，不能合并成单一排名；数据见 [P-core完整矩阵](../bench/cpp_reference/evidence/2026-11-02-managed-frontends-pcore-full/README.md)。

另用复制源码做禁用CRC诊断（非生产、不可恢复）：E-core Memory P1/P4吞吐从1.669/1.564M提升到2.108/2.050M（+26.3%/+31.1%）。这量化了CRC producer/consumer校验是E-core差距的主要组成。随后新增显式opt-in `MemoryQueueOptions.verify_crc=false`：默认仍为true，仅volatile memory queue生效，mmap/可恢复journal返回`CrcRequiredForRecovery`；生产build E-core P1/P4提升20.0%/23.1%。该模式只适合明确接受未检测内存损坏风险的应用，不改变默认可靠性契约；测试覆盖memory opt-out与可恢复journal拒绝。数据见 [nocrc诊断](../bench/evidence/2026-11-02-nocrc-diagnostic/README.md)与 [memory fast mode](../bench/evidence/2026-11-02-memory-fast-mode/README.md)。

常规应用继续以shared Memory/Mmap为主要路径，SPSC保留为高级可选。按channel预算分配counter/cache的后续实验能让普通Runtime少请求15KiB，但100项正式managed完整流程核对3010万条JSON后，P1 batch仍存在负向中位，主路径代价未排除，已恢复e40313f生产源码。资源probe、候选源码、全部慢值及撤回决策见 [线程预算实验](../bench/evidence/2026-11-02-thread-state-budget/README.md)；不据此更新跨库排名。

shared profile与filter reader实验完成244项、6420.4万条JSON核对。TLS scope决策缓存、uniform原子镜像和冷热拆分均未证明完整速度/尾部收益，全部候选撤回；实验结束时src恢复2fd7f75，Logging/outputs Fast 43/43与源码分发五模式通过。完整源码/CPU工作量/慢值见 [shared filter实验](../bench/evidence/2026-11-02-shared-filter-cache/README.md)，随后转向并保留上面的数字输出优化。

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
| 1 | 超过 Foundation/logging + spdlog 与 Foundation/logging + tracing | 对明确源码在低噪声环境建立同语义基线，P-core/E-core分别覆盖 shared/SPSC、Memory/Mmap、P1/P4 与 batch/sampled，独立判断 init/warmup/producer/written/shutdown/cleanup 与 p99/p99.9；完整配对和噪声门限必须达标，不叠加历史百分比 |
| 1 | 尾延迟和过载对应用的影响 | 合成200µs慢sink/64槽诊断已记录：block P1/P4 p99约15–16ms且无丢失，P16 p99约59–81ms；drop p99亚微秒但丢936/1000或1535/1600，fallback p50约0.24ms；仍需burst、积压年龄、CPU/cache/调度竞争及无logger基线。见 [过载尾部诊断](../bench/evidence/2026-11-02-overload-tail/README.md) |
| 1 | Mmap 启动与资源成本 | fresh Linux mmap只写header初始化已把16.8MB journal init中位54.2/53.8ms降到8.2/6.9ms；仍需更广文件系统/设备、dirty-page与持久化边界验证。见 [fresh mmap证据](../bench/evidence/2026-11-02-mmap-fresh-zero-init/README.md)与 [启动诊断](../bench/evidence/2026-11-02-current-init-profile/README.md) |
| 2 | 更广业务/durable 回归覆盖 | 0/5/10 fields、长短字符串、P1/P4/P16、warm/cold、attach/detach、reload/rolling 与独立 durable 测量 |
| 2 | 更广故障、升级与持续 fuzz | 多文件系统/设备系统停机、物理掉电、长期 seed/sanitizer、nested/轮转/版本升级组合 |
| 2 | 非 Linux 平台运行 | 对目标设备实际日志、生命周期、journal 恢复及可用 durable 能力给出报告 |

当前主要功能有验证，完整的“业界最佳”目标仍在推进。后续状态更新只记录实际源码、运行结果或明确的平台能力拒绝。
