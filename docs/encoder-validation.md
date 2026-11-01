# 完整记录编码的校验复用

text、JSON、logfmt的公开encode入口保留相同签名与输出布局。每次调用先完整校验attributes和format_args，共享256个value节点、8层container深度与重复key规则；成功后才进入同一模块内的私有递归输出。字段值不再逐项重复调用validateValue，固定类型metadata也直接使用同一私有输出方法。

完整编码入口不返回校验凭证，不导出可绕过验证的value writer，也不允许把校验结果保留到另一次调用。独立common.value继续完整验证自己的输入，延迟格式化中的nested参数仍通过这个安全入口渲染。所有descriptor、key和借用bytes必须在整个编码调用期间保持有效且不变，writer回调也必须遵守这个借用条件。

结构上把UTF-8流式转义、hex和可逆key表示拆到escaping.zig；common.zig拥有完整记录校验、三种布局和私有value输出，json/text/logfmt模块保留公开入口与各自golden测试。独立格式入口以comptime选择布局，不增加运行时格式分发。没有生产依赖、堆分配、完整消息scratch或新wire格式。

这一步对应Foundation formatter减少重复工作与集中处理的方向。当前仍保留原std.Io.Writer写入顺序和输出片段，没有加入两遍输出长度计算或缓存格式模板；Foundation的日历日期缓存不适用于保持完整timestamp_ns的JSON输出。

## 正确性证据

- 实际公开text/JSON/logfmt入口覆盖全部11种value tag、嵌套容器和unused格式参数，记录的14个节点只校验14次。旧实现被相同测试以27次遍历拒绝；测试用单独复制的旧源码，不修改测量baseline。
- 独立common.value仍验证合法完整树，并在重复key失败时保持零输出。原cycle、深度、重复key、attributes/arguments共享预算测试继续覆盖全部encoder格式。
- 对冻结旧源码与当前源码进行独立模块对照，12个完整text/JSON/logfmt输出逐字节相同；16,486种短缓冲区容量的错误和已写前缀相同。输入包含整数极值、NaN/Inf/subnormal、畸形UTF-8、可逆key、source/trace、secret、nested和跨参数UTF-8拼接。
- 原JSON解析与golden、logfmt nested、流式转义、长消息和capture深拷贝测试继续验证。格式错误与底层writer失败仍返回原错误；“无效树零输出”不表示任意I/O失败均零输出。

完整文件测量、精确源码/二进制身份与最终门禁保存在 `bench/evidence/2026-11-01-encoder-validation/`。局部遍历次数减少不能替代端到端吞吐或Quill/Foundation排名的证据。

当前Debug/ReleaseSafe编码定向各23/23通过；完整ReleaseFast verify-local通过76/76构建步骤、480/480 Zig测试，包含当前/历史格式解码矩阵、独立包五模式与Linux宿主自校验、配置替换、固定/随机SIGKILL以及查询工具。最终ReleaseSafe通过16/16构建步骤：九目标实际生成公共路径对象，真实文件交付与配置集成18/18通过。精确来源见 [qualification.json](../bench/evidence/2026-11-01-encoder-validation/qualification.json)。先前478项是批内统计轮次的历史证据，不能替代本轮校验；非Linux设备实际运行仍未取得。

## 完整流程与慢值调查

100次完整文件对照逐条验证1010万条日志，包含最终written flush、shutdown与对象清理，保留全部字段和系统timestamp。每个配置的sampled/batch分别运行5对before/after，CPU固定0/2/4/6/8/10。

| batch模式 | before中位条/秒 | after中位条/秒 | 中位变化 | 本轮资格 |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 | 1,088,241 | 924,220 | −15.07% | inconclusive |
| shared Memory P4 | 1,188,972 | 1,226,172 | +3.13% | inconclusive |
| SPSC Memory P4 | 1,199,412 | 923,631 | −22.99% | inconclusive |
| SPSC Mmap P4 | 1,190,182 | 1,121,010 | −5.81% | inconclusive |
| SPSC Mmap P4 prepared | 1,222,309 | 968,104 | −20.80% | inconclusive |

所有吞吐组至少一侧CV或spread超过10%，trial-bootstrap中位置信区间全部重叠。候选的明显慢值不能删去，也不能单凭节点计数下降认定端到端改善；SPSC Memory after的各次结果为0.884/1.233/1.224/0.903/0.924M条/s。完整原始数据见 [comparison.json](../bench/evidence/2026-11-01-encoder-validation/comparison.json)。

为调查慢值，另执行5对固定CPU0的编码probe：每进程分别编码30万条5个scalar和30万条20个nested scalar的JSON，逐条变动数值、完整输出参与Wyhash，before/after的checksum和字节数一致。用户态core PMU的整进程指令中位减少14.27%、cycles减少17.90%；两类墙钟时间仍未通过噪声阈值。该结果涵盖编码、数值更新与输出消费，不包含journal、文件I/O或后台交付。

进一步对最明显慢值的P4 SPSC Memory完整文件流程运行5对30万条试验，额外验证301万条日志。整进程用户态指令中位减少2.55%，cycles中位增加2.62%，task-clock增加2.15%；before的cycles/task-clock跨轮spread约17.6%/19.7%。完整吞吐中位1.200M→1.265M（+5.39%），仍inconclusive。软件context-switch/migration计数也有较大波动，不能据此断言最初慢值的唯一原因。

这些证据支持编码实际工作量减少，但尚不能确认完整日志稳定提速或彻底排除特定工作负载退化。保留实现、全部负向结果和CPU计数，后续在更稳定环境继续验证；不会把独立probe的cycles变化换算成完整文件吞吐。测量边界是written，不是fsync/durable。既有跨库表使用较早源码，累计优化后的Foundation/Quill比较必须同轮复测。
