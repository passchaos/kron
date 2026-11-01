# 可打印ASCII的扫描与输出

当前完整JSON文件流程的用户态profile中，CRC约占26%，quoted/consume约6%。本轮保留全部CRC校验点，只减少常见scope、message与field key的扫描和中间Writer工作。Go encoding/json和Rust serde_json同样按安全字节连续片段批量复制；本库保留原有DEL、畸形UTF-8、跨参数片段与可逆key政策，不直接复制上游实现。

完整字符串首先寻找第一个需要转义或UTF-8处理的字节。全是可打印ASCII且不含引号/反斜杠时，直接写出引号、原字节和引号；普通JSON key也由相同判定证明UTF-8有效，不再额外执行通用UTF-8验证。以$bytes:开头的key仍使用保留的可逆hex规则，不能把它当成普通key快路径。

扫描器先检查首字节。UTF-8或控制符密集输入立即进入原byte状态机；其余连续片段用有界8字节加载和byte mask判断，在找到第一个特殊字节后回到原实现。8字节读取不越过调用者slice，显式按little endian排列以保持首字节次序，短尾继续原标量规则。跨byte的借位mask可能标记首个匹配之后的相邻位置，因此仅使用首个匹配，不能拿它当逐字节精确分类位图。

初始实现未先判断首字节，六输入probe中Unicode消息中位约+5.7%。该候选和数据已保留，并通过提前返回修正。最终相同probe中Unicode中位约−2%，置信区间仍重叠；不得将这项小变化宣称为稳定收益。大量转义字符的中位约−5.8%，长ASCII约−38%、nested数字约−16.6%。这些只用于审查编码路径，包含输入变动和完整输出hash，不代表文件日志吞吐。

## 正确性与成本对照

- 1835008个相邻byte/位置/对齐组合与独立标量规则相同；短slice/空slice、空格与控制符、word边界及2048个随机输入也覆盖。
- 随机输入以原byte状态机逐字节生成参考，完整字符串与分块流式输出均逐字节比较；原UTF-8/JSON/logfmt和source/nested测试保留。
- 冻结旧模块与当前模块分别调用公开encoder，12个完整记录和16486种fixed Writer前缀一致；每次只接受1/3/7字节的generic Writer在49494种完整/失败预算下保持同样前缀，错误后没有额外回调。
- 初始与最终六输入probe分别保留，最终10个进程核对600万条输出hash/字节。用户态整进程指令中位减少10.68%，cycles减少8.06%，包含numeric/nested/wide、长ASCII、Unicode和转义密集消息；跨输入合计CPU计数不能替代各负载成本或完整文件流程。

冻结before源码、初始候选、首字节修正、精确二进制身份及完整文件对照保存在 `bench/evidence/2026-11-01-ascii-output/`。完整流程继续保持JSON字段、系统时间戳、Memory/Mmap、shared/SPSC、prepared形状、队列/文件buffer预算以及written flush、shutdown与清理终点。

## 完整文件结果

100次同条件before/after试验，每次100000条测量记录和1000条预热，逐条核对1010万条完整JSON。batch与sampled在不同进程，各配置5对交替before/after。CPU固定0/2/4/6/8/10，所有输出hash、物理字节、accepted/written/pending/drop与阶段时间保留。

| batch模式 | before中位条/秒 | after中位条/秒 | 中位变化 | 本轮资格 |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 | 1,337,151 | 1,415,928 | +5.89% | inconclusive |
| shared Memory P4 | 1,338,047 | 1,410,953 | +5.45% | inconclusive |
| SPSC Memory P4 | 1,360,909 | 1,330,091 | −2.26% | inconclusive |
| SPSC Mmap P4 | 1,327,848 | 1,400,393 | +5.46% | inconclusive |
| SPSC Mmap P4 prepared | 1,321,728 | 1,442,009 | +9.10% | inconclusive |

所有吞吐组至少一侧CV或spread超过10%，trial-bootstrap中位置信区间仍重叠。不能根据正向中位数宣称稳定收益，也不能删去SPSC Memory下降或其他slow trials。完整分位数见 [comparison.json](../bench/evidence/2026-11-01-ascii-output/comparison.json)。

额外5对P4 SPSC Memory的完整30万条PMU试验再次核对301万条日志。整进程用户态指令中位减少5.65%，两侧指令计数稳定；cycles中位减少5.38%、task-clock减少5.45%，但波动门槛仍未通过。吞吐中位1.308M→1.391M（+6.30%）仍inconclusive。该组与10万条试验的设计不同，不能合并中位或当作独立阶段成本相减。

这支持完整管线的实际CPU工作量减少，尚不能建立稳定端到端提速、排除所有负载退化或改变既有Foundation/Quill排名。用户态PMU不统计内核I/O工作，独立编码probe包含hash/输入更新，文件测量是written确认而非durable/fsync。
