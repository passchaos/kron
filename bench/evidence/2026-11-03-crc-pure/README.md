# Pure/VEX IEEE CRC调度实验

本轮保留AVX目标的三操作数CRC更新，default CRC和所有三个slot校验点不变。完整门禁通过，但没有证明全面超越两个Foundation前端。基线为 `e9301e4`（生产与`58596c9`相同）；它保留default CRC、三个slot校验点、v1/v2格式、多项式、header20/schema24分段、tail与恢复。公开Runtime/Logger、队列和heap预算保持。

## 候选与正确性

pure仅去掉register-only PCLMUL的asm volatile。VEX候选在既有compile-time x86_64/PCLMUL/SSE2条件且目标有AVX时，使用128位三操作数VPCLMUL；其余native旧CPU继续legacy SSE，generic/non-x86仍portable。所有assembly输入/输出约束显式声明，AT&T immediate0x10,b,a,out保留a.low64*b.high64语义。无需手工vzeroupper；inline helper不隐藏YMM clobbers。只读约束审核在`review.json`。

before、pure、vex在Debug/ReleaseSafe/ReleaseFast各6项原模块测试通过，包含独立IEEE oracle、长度/对齐、更新分段、硬件fold每输入基。generic Safe为3通过/1 native-only skip；`x86_64+pclmul+sse2`无AVX路径Safe6/6通过。另外Windows/macOS的真实platform_check对象显式启用PCLMUL+SSE2+AVX编译通过，见`avx-cross-compile.json`，覆盖两个OS ABI的优化分支。它们仍不是设备运行。没有新增或删除CRC步骤，CRC相同不单独证明吞吐。

独立export的 owning update静态分析：before/pure完全相同，函数3102B、20条PCLMUL、238条SIMD moves；VEX2390B、20条VPCLMUL、158条SIMD moves。完整Logger实际 owning `platform.crc32.Crc32.update` 为1444→1412B，静态指令320→310、SIMD register copy9→0，无SIMD spill或新增call；submitSafeDestination/drainJournal/peekChecked/validateSlot/slotChecksum机器码全部相同，三个CRC位置保持。见`full-binary-review.json`。standalone尺寸不作为完整栈或吞吐证明。

## 专项与负向

`measure_primitive.py`使用原 `bench/crc.zig`：20字节header→可选24字节schema→payload，25长度、两版本、16旋转对齐，每binary五invocation、每invocation五内部重复。before/pure/vex轮换，所有checksum一致；每capture3,750原始样本。CPU30 E-core、CPU10 P-core和另一次CPU30复测分别保留。

第一E-core VEX有16组局部领先、1组局部负向、33组不确定，受影响≥64B的速度比几何均值约1.016×；76B/v1约0.988×负向。P-core有3组领先、4组负向、43组不确定，整体约1.000×。第二E-core有3个短负载负向、其余47组不确定，≥64B约1.011×。所有负向继续保留，不能以某几个长度或更少mov宣称一般CRC提速。pure生成代码不变，计时变化不归因于算法改善。详细分布在`primitive-*/summary.json`与`primitive-conclusions.json`。

## 完整流程与来源

候选src的逐文件hash、binary身份、assembly、native/fallback日志、原始数据分别在provenance、archive和各目录。完整流程选public managed async/SPSC、Memory/Mmap、P1/P4、batch/sampled、100k事件+1000warmup、五重复、full JSON/系统时钟、256槽/512B、64KiB portable文件；written flush→shutdown→cleanup，不请求设备durable。双拓扑分别使用CPU16/18/20/22/24/26和CPU0/2/4/6/8/10。

首目录`ecore-workflow/`误在最后参考binary重编译完成前开始。6条已写raw结果后binary身份guard中止，完整目录不参与资格。`qualification-start.json`记录执行顺序错误与最后hash；编译完成且session关闭后，新目录`ecore-clean-workflow/`开始，之后串行P-core与PMU。只有完整的新目录可用于候选保留决定。

`ecore-clean-workflow/` 完成160项、16,160,000条物理JSON。16个关闭吞吐组1个候选局部领先（async Mmap P1 sampled约1.021×）、15个不确定，没有确认局部回退。其他中位正负保留，不能写成一般收益。P-core160项有1个baseline领先（async Mmap P4 batch约0.989×）、15个不确定。诊断汇编的xz压缩与后段约130..142项重叠，资格不作为独立确认，详见`maintenance-overlap.json`。该组另5对百万条独立复测完成10项、10,010,000条JSON，配对中位0.984×、95%区间0.974..1.007，未确认稳定回退，也未获收益。负向中位保留。

最终40项E-core full-process PMU核对4,040,000条JSON。四组instructions约减少0.69%且本轮局部资格成立；cycles正负混合，Mmap P1/P4出现baseline局部领先（速度比约0.938/0.991），完整吞吐全不确定。不能把少指令写成CPU周期减少或全面提速。

另外20项E-core百万条Mmap PMU核对20,020,000条JSON，P1/P4 instructions均约减少0.696%，各自cycles置信区间跨1且未确认短PMU负向。written关闭吞吐中位1.005×/0.999×，全部不确定；原cycle负向和长复测的负向中位保留。

另10项E-core百万条Memory P1完整对照核对10,010,000条JSON，吞吐配对中位1.010×、95%区间0.990..1.016，inconclusive。所有完整有效版本对照400项合计核对76,400,000条JSON；首6项中断数据另列排除。

本轮目标继续是超过Foundation/logging + spdlog及+tracing，完整gate通过151/151步骤、631/632测试（1默认系统local能力skip，六时区×五模式专项实际执行）；Safe源码分发、独立包/单线程、真实SIGKILL与九目标object均成功。source hash在gate前后相同，日志见`full-safe.log`及`full-gate.json`。九目标object不代表设备运行，SIGKILL不代表物理掉电。最终双拓扑Foundation同轮320项核对32,320,000条物理JSON，E-core对spdlog3组kron领先/6组peer领先/7组不确定，对tracing10组peer领先/6组不确定；P-core对spdlog5组kron领先/11组不确定，对tracing5组kron领先/1组peer领先/10组不确定。两个窗口目标均未达到。原始阶段、尾部和资格见[当前E-core报告](../../cpp_reference/evidence/2026-11-03-crc-vex-ecore/README.md)、[P-core报告](../../cpp_reference/evidence/2026-11-03-crc-vex-pcore/README.md)。

保留理由是该有界替换减少实际CRC寄存器复制和指令、native/fallback oracle及完整门禁通过，没有增加ABI/heap/queue责任。完整吞吐、周期和尾延迟不作普遍收益承诺；primitive与短PMU的局部负向及复测全部保留，`qualification.json`记录限制。性能目标仍未达到，下轮有界short-key源码/codegen研究见`next-short-key.md`，尚未实现。
