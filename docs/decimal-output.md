# 十进制记录输出与完整字符串转义

完整text/JSON/logfmt输出不需要数字的base、width、precision或alignment选项。现在这部分使用专用十进制writer：64位以内的绝对值用native-width的digit-pair循环，i128/u128的较小值复用该路径，宽值以10^19分块后分别生成十进制数字。非leading块补齐19位，包括全零块；最多两次宽值分块，避免逐两位进行宽除法。负号由安全的无符号绝对值处理，包括i128最小值。

64位以内数字在当前Writer还剩至少21字节时，计算精确位数并直接写入现有buffer；只发布实际位数，不调用drain/rebase。小buffer、无buffer的流式Writer和大于u64的宽值继续在最多40字节栈缓冲区生成并执行一次writeAll，不经过通用对齐。独立native helper避免扩大递归value渲染的内联代码；固定powers表为160字节。JSON超出±(2^53−1)的整数仍写成十进制字符串；float、NaN/Inf政策、deferred格式中的base/width/precision保持原通用formatter。该优化不改变捕获表示、journal CRC、schema、accepted/written/durable边界或文件buffer预算。

已完整提供的字符串直接调用同模块的QuotedWriter.consume，避免先绕过无buffer Writer的drain vtable。deferred消息仍通过流式QuotedWriter处理跨参数的UTF-8片段；完整字符串和流式字符串使用同一个consume/byte状态机，保留畸形UTF-8、控制符、换行与JSON key的可逆表示。

Foundation DefaultFormatter的顺序数字生成和直接复制是参考方向。本轮保留原流式Writer接口和每次输出的字节前缀行为，没有引入全事件两遍长度统计、完整消息scratch或依赖上游代码。数字生成集中在decimal.zig，转义保留在escaping.zig，记录布局和安全树验证仍由common.zig负责。

## 正确性验证

- 三项新测试把全部65536个u16值与标准formatter逐字节比较；native整数极值、39组十进制边界、128组二进制边界、全零分块和2048对随机u128/i128都一致。
- 最小signed整数与最大unsigned整数的所有短fixed Writer前缀继续和标准formatter比较。bounded Writer失败不被当作完整记录成功。
- 冻结完整旧模块与当前模块分别调用公开encode，12个完整text/JSON/logfmt输出、16486种fixed缓冲容量前缀逐字节一致。
- 增加独立generic Writer，每次只接受1/3/7字节，在每个字节预算触发失败，49494种完整/失败输出前缀与旧实现一致；发生错误后双方都不再次调用Writer。
- UTF-8片段拼接、nested、所有value tag、整数JSON边界、source、trace、secret、float和无效树零输出继续使用原测试验证。

原始来源、probe和完整文件测量保存在 `bench/evidence/2026-11-01-decimal-output/`。本轮measure使用written文件flush、shutdown和清理边界；数字生成的局部收益不代表durable/fsync吞吐或Foundation/Quill排名。

## 完整流程测量

5种配置、sampled/batch独立进程各5对before/after，共100次实际文件试验，每次100000条测量记录及1000条预热，逐条核对1010万条完整JSON。保持系统时钟、256槽/512字节payload、64KiB文件buffer、CPU0/2/4/6/8/10以及最终written flush、shutdown与清理；初始化和预热另行报告于lifecycle指标。

| batch模式 | before中位条/秒 | after中位条/秒 | 中位变化 | 本轮判断 |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 | 1,092,183 | 1,359,992 | +24.52% | inconclusive |
| shared Memory P4 | 1,217,630 | 1,300,304 | +6.79% | inconclusive |
| SPSC Memory P4 | 1,189,422 | 1,227,039 | +3.16% | inconclusive |
| SPSC Mmap P4 | 1,231,334 | 1,233,869 | +0.21% | inconclusive |
| SPSC Mmap P4 prepared | 1,149,036 | 1,241,312 | +8.03% | inconclusive |

全部吞吐组至少一侧CV或spread超过10%，trial-bootstrap中位置信区间仍重叠。不能将正向中位数宣称为稳定提速；例如SPSC Memory after的spread约63.8%，全部慢值保留于 [comparison.json](../bench/evidence/2026-11-01-decimal-output/comparison.json)。格式、资源预算和可靠性相同的before/after只在各自配置内比较，不能把Memory与Mmap混成统一收益。

编码probe覆盖5个native值、20个nested值及5个接近u128上限的宽值，每类每进程30万条，完整输出参与Wyhash。第一组probe与本轮full-workflow二进制编译部分重叠，其指令/周期和墙钟结果保留但不作为隔离计时资格。随后的5对串行probe没有本轮构建/门禁重叠，输出checksum与字节数均相同，整进程用户态指令中位减少18.50%、cycles减少27.14%，两组PMU计数各自CV/spread低于10%；各类墙钟时间仍inconclusive。这些数值包含输入更新、编码、hash和启动/报告，不能换算为文件日志的收益。

另以完整P4 SPSC Memory文件流程运行5对30万条试验，额外核对301万条日志，全部线程的用户态指令中位减少6.22%，两侧spread约0.02%；cycles中位减少3.37%、task-clock减少3.79%，但两者跨轮波动未通过门槛。完整吞吐中位1.115M→1.285M（+15.31%）仍inconclusive，相关软件计数与slow trials均保留在full-pmu-results.json。这支持完整管线的实际CPU工作量减少，尚不能建立稳定延迟/吞吐收益或跨库排名。

最终Debug/ReleaseSafe定向各26/26、完整ReleaseFast76/76构建步骤与483/483 Zig测试通过；九目标ReleaseSafe实际对象和文件/配置18/18通过。时间处理后续另有实现与证据，不混入本轮源码身份。

## 当前直接buffer路径

当前基线`20d49be`的完整文件profile确认小memcpy热点后，native数字直接输出已进一步实现。新增测试覆盖全部decimal/binary native边界、4096随机native对、已有prefix/未用buffer sentinel，以及1/20/21/64字节内部buffer、下游1/3/7字节短写与所有物理失败前缀。最终公开encoder和冻结源码的12个完整记录、16486 fixed前缀与49494 generic前缀仍一致。

初始inline和digit-count-table方案的nested20探针有约3%负向中位，原始结果保留；最终独立helper消除该项负向中位。100个正式文件试验核对1010万条日志，shared Memory P1/P4、SPSC Memory P4、SPSC Mmap P4和prepared分别提升约3.86%/3.40%/4.04%/3.00%/3.31%，两侧CV/spread均低于10%；只有SPSC Memory P4的trial-bootstrap中位区间不重叠，其他组仍重叠。

另20个完整文件user PMU试验核对602万条日志：SPSC Memory P4 cycles中位减少4.99%，instructions增加1.00%；shared P1 instructions增加1.04%，cycles仍inconclusive。SPSC长流程出现保留的候选慢值，使其吞吐保持inconclusive。这是指令组合与复制成本的变化，不是所有路径指令减少；不能把局部改善叠加为Foundation跨库领先。精确源码、失败前缀、原始慢值与全部探索报告见`bench/evidence/2026-11-01-decimal-direct/`。
