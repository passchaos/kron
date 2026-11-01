# 十进制八位分块与缓冲冷路径

**本轮优化已保留。** 基于生产`7480598`，从当前shared完整profile中的消费者decimal成本继续优化。140项完整文件试验逐条核对4214万JSON，四组shared用户态指令稳定减少3.43%–3.47%；完整吞吐/尾部仍未取得一般资格，没有更新Foundation/tracing排名。

## 数字转换与调用帧

原生u64的大数被分成最多两个10^8尾段，每段固定写4个两位数字，尾段与leading chunk采用u32运算。原有小数字digit-pair循环保留；native direct大数与流式/短buffer/宽整数各自独立noinline，避免其寄存器和temporary frame扩大普通小数字调用。u128仍按10^19分块，native tail再采用八位转换。符号、padding、21B direct-capacity边界、标准Writer失败前缀及精确整数值不改变。

第一版把所有leading chunk都改成u32且内联大数循环，primitive full-u64 cycles约−37.5%，小数却+22%、日志字段组合+5.5%。分开native大数后，小数仍+15%、组合+11%；反汇编确认公共writeMagnitude仍预留大型buffered fallback帧。两个负向版本各50项、每项409.6万计时转换，源码/binary身份及全部结果分别保留在all-u32/、split-native/。

最终把buffered fallback另拆冷函数；writeMagnitude不再出现在native primitive的独立符号中，小数字renderer保持原loop与小frame，large renderer约0x1ca bytes，cold buffered按native/wide独立实例化。初始和最终源码归档包含拥有文件及probe，不能用一个版本的CPU数据给另一个版本背书。

## primitive证据

decimal_probe.zig的4096个确定性值覆盖small（<10^6）、record（系统ns/session/sequence/小字段组合）、full随机u64、signed随机i64、wide随机u128。每process先后逐字节对照std formatter；计时1000批，每批完整buffer暴露给doNotOptimizeAway，不在逐值调用中计时或hash。完整checksum和byte count在before/after相同。probe.py交替5对、50项；PMU用户态instruction/cycles包括startup/preparation/oracle/hash，不是纯计时循环，也不是完整logging。

最终native CPU的中位变化：

| 类型 | instructions | cycles | ns/value | 周期/墙钟资格 |
| --- | ---: | ---: | ---: | --- |
| small | −9.14% | −7.82% | −7.65% | 波动超门限、区间重叠 |
| record | −8.82% | −11.16% | −11.30% | CV/spread达标、区间不重叠 |
| full u64 | −9.65% | −38.07% | −37.87% | CV/spread达标、区间不重叠 |
| signed i64 | −10.22% | −23.37% | −23.58% | CV/spread达标、区间不重叠 |
| wide u128 | −8.88% | −15.57% | −15.45% | CV/spread达标、区间不重叠 |

五组指令均CV/spread达标且中位区间不重叠。小数周期中位虽降低，不能当作稳定延迟承诺。全部原始CSV/row和慢值在primitive-trials/、primitive-results.jsonl及primitive-comparison.json，身份见primitive-provenance.json。

## 当前正确性与完整对照

数字模块Debug/Safe/Fast各6项，包括全部u16、native/wide extrema、decimal/binary边界、4096随机native对与2048 wide对、内部零尾段与leading宽度。原fixed-prefix及1/20/21/64B writer buffer、1/3/7B物理短写、全部失败前缀继续执行。拆分后当前Debug/Safe、generic x86 ReleaseFast各6项通过，AArch64 ReleaseSafe完成编译（没有设备运行声明）；当前encoder相关Safe 52/52含import fixtures通过。

当前完整Safe为148/148步骤、612项通过/1项无libc系统local能力skip，另Logging3/3、27/27；合计151步骤、639项通过。包括九目标对象、源码分发、真实SIGKILL、单线程、native Linux五模式、时间oracle与示例。日志中的compression/decoder诊断带有Zig build的“failed command”字样，但最终两个step均success、整个命令exit0；最初将此误读为失败，已由最终summary纠正，同一二进制直接运行10/10与7/7也通过。这不是跳过失败或重写原始日志。

正式对照使用managed Logging、shared Memory/Mmap P1/P4、完整JSON、5数值/full metadata/系统clock、256槽/512B/64KiB buffer、4量子、block、written/关闭/cleanup；init/preparation/lifecycle单列。before-provenance指定的fd4e941二进制与7480598生产src/reference相同；after源码/binary在所有自身编译结束后冻结，PMU与未插桩工作流独立捕获。primitive改善不叠加为Foundation或tracing排名。

40项完整文件PMU逐条核对1204万条物理JSON，用户态instruction中位：Memory P1/P4分别−3.474%/−3.451%，Mmap P1/P4为−3.432%/−3.466%。四组CV/spread均达标，中位95%区间均不重叠。PMU包含初始化、producer/consumer和关闭/cleanup，排除kernel；这证明本机完整流程用户态工作量降低，不能替代实际吞吐或durable介质性能。cycles与PMU窗口的written吞吐中位仍受噪声/重叠区间限制，所有值保留在pmu-comparison.json。

## 未插桩完整文件与风险复测

80项正式workflow核对2408万JSON。下表为包含producer、consumer JSON/实际文件、written flush、shutdown/destroy/cleanup的中位吞吐，单位M条/s；init/preparation另列。

| shared配置 | before | after | 中位变化 | CV/spread / 中位区间 |
| --- | ---: | ---: | ---: | --- |
| Memory P1 batch | 2.226 | 2.296 | +3.14% | 未达标 / 重叠 |
| Memory P1 sampled | 2.257 | 2.250 | −0.33% | 未达标 / 重叠 |
| Memory P4 batch | 2.178 | 2.267 | +4.08% | 达标 / 重叠 |
| Memory P4 sampled | 2.216 | 2.215 | −0.07% | 未达标 / 重叠 |
| Mmap P1 batch | 2.211 | 2.336 | +5.65% | 未达标 / 重叠 |
| Mmap P1 sampled | 2.254 | 2.118 | −6.02% | 未达标 / 重叠 |
| Mmap P4 batch | 2.241 | 2.279 | +1.68% | 未达标 / 重叠 |
| Mmap P4 sampled | 2.236 | 2.205 | −1.39% | 未达标 / 重叠 |

sampled各组p50/p99/p99.9均未取得一般资格，所有慢值与初始化/关闭阶段在workflow-comparison.json中保留。针对Mmap P1 sampled的−6%信号，另20项相同30万事件/1000 warmup的P1 sampled独立复测，核对602万条JSON：Memory/Mmap吞吐中位分别+0.76%/+1.48%，均区间重叠；最初Mmap负向没有重现。完整分位与stage在p1-sampled-repeat-comparison.json，不拼接成单一低噪声窗口。

采纳依据是所有整数/失败前缀/完整门禁兼容、五类primitive指令减少、四组完整shared指令稳定减少，以及未复现原sampled负向。不能把batch中位+1.7%–5.6%或局部周期结果当稳定速度承诺。没有扩大heap/queue/file预算，没有新增依赖或每emit分配；更广字段/业务、更多输出与CPU架构的性能资格仍需单列。

## 复现与身份

before/after-provenance.json固定完整日志binary与source，candidate-source.tar.xz包含所有src、reference与primitive probe。primitive-provenance.json固定最终两份probe；all-u32/与split-native/保留被否决的两版和完整负向。environment.json保存CPU拓扑、affinity与governor；原始row每项保存load和实际命令。decision.json绑定全部140个文件trial与源码采纳结果。

```sh
zig test src/encoder/decimal.zig -O ReleaseSafe
zig build verify-local check-platforms test-package-distribution test-logging -Doptimize=ReleaseSafe -j1 --summary all
python3 bench/evidence/2026-11-02-decimal-u32-chunks/measure.py --capture-name workflow-repeat
python3 bench/evidence/2026-11-02-decimal-u32-chunks/measure.py --p1-sampled --capture-name p1-repeat-2
```

所有脚本拒绝覆盖已有捕获；需先按provenance构建/恢复冻结binary，fresh build记录新身份。probe.py的固定primitive结果路径用于本轮捕获，复跑前复制到新的evidence目录或更换destination，保留原始数据。
