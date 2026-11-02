# README 性能试验记录快照（2026-11-03）

以下保存本轮整理前 README 顶部的试验叙述、全部数字与证据链接。它们各自绑定当时源码与窗口；当前能力和未完成目标见 [当前验收状态](../implementation-status.md)。链接按本文位置调整，原始实验数据未重写。

Journal 三入口特化候选已在静态门槛撤回：强制尾调用受到后端、错误集合类型和聚合返回 ABI 限制；保持公开接口的内联变体通过默认 Debug/Safe/Fast/generic 回归，但实际新增返回临时复制，SPSC 栈帧增加、drain 栈帧多 832 字节。源码、原始编译失败和机器码证据见 [入口特化报告](../../bench/evidence/2026-11-03-journal-entry-specialization/README.md)。该实验没有性能试验，生产 Journal 保持原样，下一固定容量精确算术仍需独立验证。

固定容量倒数算术在完整 u64 上通过独立证明和 20 万随机/边界测试，实际使用两次乘法和一次校正，但八容量队列控制有 13/16 组稳定回退、Journal 对象增加 64 字节，候选已撤回且未进入完整日志对照。数学、机器码和全部反例见 [倒数报告](../../bench/evidence/2026-11-03-capacity-reciprocal/README.md)。随后用当前原始生产基线完成八项双拓扑完整流程 profile，核验 800.8 万条 JSON；该 [当前采样](../../bench/evidence/2026-11-03-current-workflow-profile/analysis.md) 只用于定位热点，不提供新的速度排名。

四字节 ASCII 尾扫描的全局和 JSON 属性前缀两个候选均撤回：六字节键有局部收益，但短字符串、较长键或 UTF-8 控制存在稳定回退。生产保持原八字节扫描和 Writer 输出顺序；新增 `test-escaping-tails` 覆盖短尾首匹配、相邻字节和五种公共操作的失败前缀。两拓扑全部正负、编译器新增调用与源码身份见 [尾扫描报告](../../bench/evidence/2026-11-03-ascii-four-byte-tail/README.md)，未更新 Foundation 排名。

TLS 失效槽位清理和紧凑 Frame 两种候选均因完整流程回退撤回，生产保留原 optional decision 与完整槽位清理。880 项对照核对 8888 万条完整 JSON；紧凑表示虽令 TLS 数组少 1 KiB，E-core 仍有六组吞吐回退，未取得保留资格。新增五项生命周期回归覆盖复用、回调嵌套、64 层栈、线程隔离与完整 generation/channel 边界；全部正负及测试发现记录见 [TLS 报告](../../bench/evidence/2026-11-03-tls-leave/README.md)。未更新 Foundation 排名。

CRC 16B 余块延续的无条件分派、零余块守卫和块终点循环三个候选均撤回。双拓扑 54 长度/两种 header 形状共 32400 个计时批次全部 checksum 一致，但各版都有 E-core 控制回退；循环少指令或 241B 局部收益未构成保留资格。新增独立 bitwise/GF2 消息与 seed 基向量、任意 seed/对齐及 45 个 zlib 固定向量回归；完整原始正负和测试发现修正见 [CRC 余块报告](../../bench/evidence/2026-11-03-crc-partial-lanes/README.md)。生产保持原 CRC、三个检查点与恢复格式，未更新 Foundation 排名。

直接加权折叠 CRC 余块的候选通过独立数学与目标验证，但零余块实际增加分派和常量读取成本，未过预设静态门槛，已撤回且未开展性能试验；证据见 [直接折叠报告](../../bench/evidence/2026-11-03-crc-direct-partial/README.md)。共享预留商/余数复用虽将成功路径两次 DIV 降为一次，530 项完整对照核验 1.3453 亿条 JSON 后，长流程未取得稳定收益，SPSC p50 控制有负向，生产候选同样撤回；坐标边界回归与全部结果见 [预留除法报告](../../bench/evidence/2026-11-03-reserve-divrem/README.md)。后续二次幂候选的决定单独记录，不叠加这些结果的速度比。

后续二次幂预留、创建时缓存及完整 Journal 坐标候选也已撤回：前两者虽有局部指令/延迟收益，完整流程仍有吞吐或 schema 控制负向；完整坐标虽消除默认消费者五次 DIV，任意容量出现回退，保持原 CRC 调用边界后仍无收益资格。生产保持原 Journal 数学，新增 `test-journal-coordinates` 验证共享/SPSC 八容量环回、跨 2³²/序号上限以及 CRC 有效但 generation 错误的拒绝和证据保留。全部源码与正负见 [二次幂](../../bench/evidence/2026-11-03-reserve-pow2/README.md)、[缓存预留](../../bench/evidence/2026-11-03-reserve-cached-pow2/README.md)、[完整坐标](../../bench/evidence/2026-11-03-journal-cached-coordinates/README.md) 和 [调用边界](../../bench/evidence/2026-11-03-journal-coordinate-call/README.md)。Foundation 目标仍未达成。

默认时钟回调与内部 inline 两个优化候选因完整流程负向撤回，生产继续原 std.Io 注入路径。960项对照核对9696万完整JSON，减少调用和 Io 复制未证明整体收益；保留回调切换、Io 参数快照、纳秒边界与调用时点回归。完整反例见[clock报告](../../bench/evidence/2026-11-03-default-clock/README.md)，未更新 Foundation 排名。

共享 written 游标现在以 release RMW 发布进度，配合 `writtenTarget()` 的 acquire 读取提供明确的写入可见性；原最大值算法、CRC、恢复和队列预算保持。两种普通 store 性能候选因完整流程回退撤回，880项对照核对8888万JSON，未更新跨库排名。新公共测试覆盖实时游标、失败前缀和 join 前发布观察，详见[written报告](../../bench/evidence/2026-11-03-written-store/README.md)。

当前共享队列只在峰值增长时更新 `high_water`，直接 CAS 循环保留精确最大值、默认 CRC 和实时 written。完整 Safe/分发/恢复/九目标门禁155步骤成功；百万条复测未确认回退，也未取得普遍吞吐收益。最新双拓扑 Foundation 对照核对3232万 JSON：P-core 对 spdlog 7组、对 tracing 4组局部领先，E-core 仍有明显差距，目标未达到。全部负向、调用成本与资格见[峰值报告](../../bench/evidence/2026-11-03-peak-update/README.md)。

短字段名比较的四个候选已撤回：默认完整流程有局部收益，但 1–3 字节及长键输入出现稳定回退。生产保持原比较，新增公共字节 oracle、真实 guard page 和错误顺序回归；全部控制组、原始正负与限制见[短键报告](../../bench/evidence/2026-11-03-short-keys/README.md)。

当前CRC在AVX目标使用三操作数PCLMUL，实际更新函数少9次寄存器复制、完整PMU指令约减少0.7%；默认CRC、三个校验点和恢复保持。完整Safe/分发/SIGKILL/九目标门禁151步骤成功。最新双拓扑Foundation对照核对3232万JSON：P-core对spdlog5组、对tracing5组局部领先，但E-core仍有差距、P-core也有1组对tracing落后，目标未达到；全部负向与复测见[CRC报告](../../bench/evidence/2026-11-03-crc-pure/README.md)。typed capture候选因完整吞吐回退已撤回，边界回归与[证据](../../bench/evidence/2026-11-03-typed-capture/README.md)保留。

此前Runtime内部提交减少Binding/Event复制，保持公开快照和校验；完整门禁151步骤成功。默认PMU四组instructions约减少0.7%，同源码双拓扑Foundation对照核对3232万JSON，P-core对spdlog4组/对tracing2组局部领先，E-core仍未达到目标。所有候选、慢值与快照回归见[提交报告](../../bench/evidence/2026-11-02-submit-abi/README.md)。

此前源码保留JSON属性前缀直接输出与predicate route位图；完整门禁149步骤通过。最终文件PMU四组指令约减少3.0%，周期和完整吞吐仍有正负；400项应用试验核对480万请求、221万完整日志。双拓扑320项Foundation对照仍未全面超过两个组合，所有负向和复测见 [当前JSON报告](../../bench/evidence/2026-11-02-json-member-direct/README.md)。

当前保留IEEE CRC四lane并行合并，完整ReleaseSafe/分发/SIGKILL/九目标对象门禁通过；双拓扑同轮Foundation对照核对3232万条JSON，P-core对tracing6组、对spdlog3组局部领先，其余不确定，E-core仍有明显差距。原始负向、CRC长流程复测和验收边界见 [CRC报告](../../bench/evidence/2026-11-02-crc-parallel-collapse/README.md)。
