# JSON属性前缀直接写出与predicate route掩码

从`4dd574f`出发，最终保留两个内部机制：JSON attribute前缀在当前Writer有完整容量且key是非保留纯ASCII时，直接生成可选comma、quote、key、quote/colon并一次推进end；escaped/reserved/short/streaming走独立cold helper，保留原逐步失败序列。不可变Selection记录有predicate的route位图，submit只访问已selected的predicate routes，顺序和global predicate/树校验边界不变。

三个JSON整数一次写出候选全部撤回，生产decimal与原quote规则保持原样，见[整数否决](../2026-11-02-json-integer-direct/README.md)。wire/journal/schema/archive版本、CRC三个校验点、typed捕获、默认队列和文件预算不变；Selection每配置版本增加8B派生掩码。内部jsonMember未增加应用选项。

## 字节与错误

独立原key writer序列与新jsonMember比较空、ASCII、reserved、escaped、Unicode、无效UTF8/全部256字节key，枚举所有short fixed容量和已有prefix。完整可写分支从不drain，其他分支的错误/写入前缀逐字节相同；Debug/Safe/Fast专项通过。融合v4/reference JSON与materialized encoder、短input、scratch、mask、nested/type errors重点64项Safe通过。predicate公开测试包括sync/async 64routes的bit63和未selected regex不执行，8/8通过，全部full替换/旧资源继续保留。

早期根筛选只执行导入检查不算目标单测；实际escaping standalone测试与含shape编译的root测试输出分别保留。完整门禁以最终cold-full-safe.log为准：149/149步骤成功、623/624测试通过（1项默认系统local能力skip），另local专项实际执行六时区×五模式oracle。九目标object不替代非Linux设备运行，SIGKILL不替代物理掉电。

## 分开测量与负向复测

CPU30普通public encoder对照30项，每格式scalar5/nested20/wide5各300000次，全部输出checksum和bytes一致。初版direct前缀的JSON用户instructions配对速度比1.067（约减少6.3%）、cycles1.056（约减少5.3%），三个负载都有本轮局部领先。text/logfmt控制原始正负保留，不把布局变化称为无关算法收益。

不包含新整数调用的初版member+predicate shared E-core80项文件核对8,080,000条JSON，八组中只有Memory P1 sampled局部领先，其他inconclusive，Mmap P4有轻微负向中位。P-core async/SPSC160项核对16,160,000条JSON，多数组正负混合，只有async Mmap P4 sampled取得本轮局部资格。完整用户态PMU40项核对4,040,000条JSON，shared Memory/Mmap P1/P4 instructions均约减少2.8%；cycles和吞吐仍不确定。该PMU绑定final-source.tar.xz中未拆cold的版本，不能把百分比直接转移到最终cold源码。

P-core shared Memory P1 short batch中位0.917×，噪声超限，百万条独立10项复测却0.963×、95%区间0.951..0.981，确认本轮局部负向。不能以更少instructions忽略完整吞吐回退。后续拆开predicate和member：predicate-only百万条0.982×（inconclusive）；member-only0.977×（区间跨1），无一般资格。

最终将escaped/short回调从jsonMember热函数拆出，代码体由约1494B降为约534B，writer行为相同。cold版本首轮百万条中位0.972×、区间跨1，期间并发编译新增predicate回归，保留该数据但不作最终资格；无编译复测0.998×、区间0.938..1.044，inconclusive。另member-only inline对照1.027×、区间0.981..1.056，未取得收益资格；保留较小cold热函数，完整吞吐不作一般承诺。

最终cold源码另做40项完整PMU，核对4,040,000条JSON。四组instructions约减少3.04%–3.06%并取得本轮局部资格。cycles正负混合：Memory P1约增加2.1%并取得局部负向，其余不确定；instrumented吞吐配对中位全部为正但全部inconclusive。这个负向仍保留，不能把更少instructions描述为更少CPU cycles或一般速度优势。数据在cold-final-pmu/，绑定最终源码。

所有早期、否决/调整、短/百万条数据在results/summary各目录，源码在member.patch/final.patch/cold-final.patch与对应source archive。syscall诊断100k P1中before/combined pwritev847/885，strace干扰计时，不作为排名或一般写入次数保证。它说明编码局部工作量降低不能自动推导完整流程更快。

## 应用影响与跨库

最终cold源码的业务计算before/after＋无logger比较400项，独立Python整数模型核对4,800,000请求、2,210,080完整JSON，所有checksum和初始化后FailingAllocator检查通过。compute/cache、P1/P4、每条/每16条日志，none/shared/SPSC Memory/Mmap各五对。版本间32个logged吞吐组只有cache P4 every1 SPSC Memory约1.016×取得局部领先，其余不确定，没有确认稳定业务回退；日志开销相对none仍明显，不能称为零影响。应用数据在application/，它使用已有public Runtime入口，managed独立完整文件/跨库另行验收。

两个Foundation真实前端的最终cold同轮P-core/E-core各160项覆盖async/SPSC、Memory/Mmap、P1/P4、batch/sampled、系统时钟、五typed数字、full JSON、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup。初始化、lifecycle、p99/p99.9独立报告，不请求设备durable。原始来源/工具链/二进制与生产逐文件hash在各manifest；配对满足至少5轮、两侧/比值spread≤10%、95%区间不跨1才判断本轮局部领先。未达到的组保持缺口。

两种拓扑共320项核对32,320,000条JSON：E-core对tracing12组peer领先/4组不确定，对spdlog10组peer领先/2组kron领先/4组不确定；P-core对tracing2组kron领先/14组不确定，对spdlog1组kron领先/15组不确定。E-core目标未达到，P-core整体inconclusive。完整数据见[E-core前端报告](../../cpp_reference/evidence/2026-11-02-json-member-ecore/README.md)、[P-core报告](../../cpp_reference/evidence/2026-11-02-json-member-pcore/README.md)，不继承早期百分比。

本轮目标仍是完整超过Foundation/logging + spdlog和+tracing，局部encoder/PMU百分比不能叠加到不同历史基线。

```sh
zig build verify-local test-package-distribution check-platforms -Doptimize=ReleaseSafe -j1 --summary all
python3 bench/evidence/2026-11-02-json-member-direct/application_pairs.py \
  --before BEFORE_APP --after AFTER_APP --output FRESH
python3 bench/cpp_reference/compare_versions.py --before BEFORE --after AFTER \
  --output-dir FRESH --affinity 0,2,4,6,8,10 --events 1000000 \
  --repeats 5 --storages memory --producers 1 --phases batch
```
