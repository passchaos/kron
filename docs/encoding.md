# 事件编码、验证与二进制归档

`codec.encodedSize`、`codec.encode`、`codec.writeTo`都校验完整借用事件。数组和group的cycle、8层深度、重复group key和attributes/arguments共享256节点预算只有一份遍历实现，位于 `fields.ValueValidator`。格式参数顶层key允许重复；参数内部group仍校验唯一key。

长度计算使用同一遍历的observer统计每个节点自己的wire字节：key为4字节长度与key内容，scalar为tag与固定值，string/bytes为tag、长度和内容，array/group为tag和child count。child由validator遍历，不再单独递归统计一次。公开standalone value size同样先校验。

长度累计使用u128，在完成全树验证后检查u32 wire上限。64-bit目标中，合法事件最多256个value长度、256个key长度和5个event/source字符串长度，总和低于2^74；comptime限制usize最多64位。这样长度溢出不会提前覆盖后续cycle或重复key错误。无效事件和容量不足仍在写入destination之前失败。

`ValueValidator.valueWith/fieldsWith/argumentsWith`可接收typed visitor，回调分别观察当前value或Field，不能递归或修改正在借用的树。自定义visitor的错误会立即结束遍历，可能先于尚未访问节点的校验错误；codec自己的visitor不会返回错误，因此保留完整validation-first契约。

## 二进制归档

`encoder.binary.encode`通过 `codec.writeFramed` 在同一调用内完成：

1. 全树校验并计算payload长度一次。
2. 流式写入256字节hash缓冲，计算payload CRC32。
3. 生成并写入固定archive header。
4. 使用相同私有wire实现流式写出payload。

两次payload遍历是计算CRC后先写header的必要步骤；重复校验和长度计算已经合并。不会导出unchecked写入函数或可复用的validation token。Event以及descriptor、key、string/bytes在整个调用和Writer回调期间都必须保持稳定，这是所有借用编码接口的前置条件。

Runtime 默认 inline 提交路径现在在 route predicate 之前调用 `codec.measure`，用同一次完整树校验得到 wire 长度，并把该长度传给接受后的 `codec.encodeSized`。`encodeSized` 仍重新检查 level 和 destination 容量，只省去同一未变事件的第二次长度遍历；redaction 会重写借用存储，schema binding 使用不同 wire 形状，因此两者继续独立校验/测量。`codec.measure` 有意不检查 level，保持既有顺序：树错误先于 predicate，level 错误只在接受的写入边界出现。公开 `codec.encode` 仍先校验完整树，不导出可复用的 unchecked writer 或 validation token；用不同字段/消息的长度误用由调用契约和 debug assert 拒绝。

消费者 decoded delivery 复用 checked decoder 的树校验：`codec.decode`/`schema_codec.resolve`在完成wire树、节点预算、深度、重复key和长度检查后设置内部`Event.tree_validated`；内部`encoder.common.encodeDecoded`只对该证明跳过第二次`ValueValidator`，否则仍走校验路径。公开`encoder.encode/encodeWithTime`忽略该提示并始终校验；runtime先用admission的`codec.measure`或redaction/binding校验，再由`submitSafeDestination`用可信上下文覆盖调用方提示。binary route继续使用公开校验入口。测试锁定伪造提示的invalid tree仍被公开encoder拒绝、runtime重复key仍返回`DuplicateKey`、decoded text/JSON/logfmt与公开encoder字节一致。

进一步为常见形状增加 fused wire-to-JSON 路径：当前 v4 inline、单个 JSON/text/logfmt route、非 deferred message、无 format args 时，checked wire parser 只解析一次 header/scope/message/trace/source/attributes；nested attributes 使用 caller scratch arena，并在 scratch 中写出与公开 encoder 相同的 JSON/text/logfmt 记录；top-level key 去重和完整 value tag 校验在写入 sink 前完成。其他形状返回 `error.Fallback` 走 decode+encode。journal 协议、公开 encoder 和校验边界不变。

测试锁定 filtered invalid level 仍返回 filtered、invalid tree 仍在 predicate 前失败，并核对 sized 写入与公开 encode 的完整字节一致。Redaction 路径和 prepared schema 仍各自维护入口校验；没有用“之前校验过”跳过公开提交边界。

测试确认size、encode和stream每个节点仅校验一次，archive也是一次prepare；覆盖全部value tags、独立/组合node预算、invalid tree零输出、size overflow后的错误优先级、Secret脱敏和wire字节一致。Runtime、redaction和context仍各自维护它们的入口校验；本轮没有用“之前校验过”跳过公开提交边界。

## 预注册 schema 编码

`schema_codec.encodedReferenceSize` 和 `encodeReference` 现在也通过同一个 validating visitor 统计值长度。顶层字段与格式参数的 key 已保存在 schema 中，因此不计入参考载荷；嵌套 group 的 key 仍写入载荷，由 validator 当前 depth 决定是否计入。两个入口各只进行一次完整树校验，保持 attributes/arguments 共享 256 节点、8 层深度、cycle 与嵌套重复 key 检查。

此前参考编码在检查完整事件后，为每个顶层 value 计算长度时再次递归校验，写出时调用公开 value writer 又校验一遍。现在 node-local 长度统计位于内部 `wire_size.zig`，底层字节写入位于内部 `wire_write.zig`，供两个已经完整校验的 payload codec 使用。公开 `codec.writeValue` 继续在写出前独立校验，不能通过公共模块取得跳过校验的 writer 或凭证。

参考编码保持原有错误顺序：完整树错误 → schema shape/type 与 level 错误 → wire 长度上限 → destination 容量。长度仍用 u128 累计到校验完成后检查；失败不修改 destination。schema payload v5/84-byte header、旧 v2 读取、inline v4 与旧 v1/v3 读取均保留。新增测试直接计算全部 scalar/container 标签的长度，检查一次遍历计数、nested key、重复 positional key、256 节点与深度边界、长度溢出优先级，以及公开 value writer 无效输入零输出。

## 性能证据

`zig build bench-encoding -Doptimize=ReleaseFast -- --iterations=10000 --repetitions=5`覆盖flat5、两层嵌套和最大256节点，分别测量size、value size、encode与binary archive。完整输出的Wyhash消费成本计入encode/archive，时钟每批只读取一对，测量期间没有堆分配。

修改前源码单独冻结，原始候选和最终u128候选全部保留。五轮交替before/after试验共产生600行；每行checksum、output bytes、payload/value/archive长度、字段/节点、迭代与预算都和基线相同。记录和SHA256位于 `bench/evidence/2026-10-31-encoding-visitor/`。

首次候选每个节点判断overflow增加了小事件成本，因此最终累计器只在全树验证结束后检查上限。多个时钟试验出现明显host/CPU调度波动，全部比较标为inconclusive；包含setup与report的用户态perf计数支持执行指令减少，但不能当作稳定producer延迟或端到端吞吐提升。当前成果是重复工作的减少、准确边界测试和可复现基准，不是行业排名。

2026-11-01 基准增加 `reference_size_only` 和 `reference_encode`，schema 注册、完整 roundtrip 检查与分配都在计时外。修改前源码单独冻结，应用与库均以 ReleaseFast 构建；固定子进程 affinity，五轮交替 before/after，每轮五次重复。450 对结果的完整输出 checksum、wire/归档/参考载荷长度、字段/node/buffer 预算均精确一致。数据位于 `bench/evidence/2026-11-01-schema-encoding/`。

该轮参考长度计算的 flat5、nested8、max256 本机中位成本分别下降约 23%、38%、44%；nested8 参考编码下降约 29%。flat5/max256 参考编码中位数下降，但跨轮 spread 超过 10% 噪声门限，结果仍为 inconclusive。参考编码计时还包含 fixture 更新与完整输出 Wyhash，不能换算为整体 producer 延迟或日志吞吐，也不能据此宣称行业领先。

## 解码和版本矩阵

`test-decoder-matrix` 提供独立有界门禁，并包含于 `test-fuzz`。矩阵区分三个版本域，不把同名版本号视为同一协议：

| 载荷 | 头长度 | schema 定义 | 磁盘读取容器 |
| --- | --- | --- | --- |
| 历史自包含 v1 | 68 | 无 | archive frame v1 |
| 历史自包含 v3 | 76 | 无 | archive frame v1 |
| 当前自包含 v4，scalar/nested | 84 | 无 | archive frame v1 |
| 历史引用 v2 | 76 | scalar v1 | journal 文件 v2 |
| 当前引用 v5，scalar | 84 | scalar v1 | journal 文件 v2 |
| 当前引用 v5，nested动态/格式串 | 84 | nested v2 | journal 文件 v2 |

共8组载荷，各执行2048次确定性变异、所有逐字节截断，以及0–15个Field容量的短scratch检查。变异包括单字节翻转、多字节随机翻转、随机u32结构长度和截断；成功解码必须能精确再编码，历史缺失header字段只能恢复为0。字符串、key、source sentinel的范围必须位于输入或schema，nested描述符必须位于调用者scratch；scratch之外的canary与未使用尾部不得被改写，失败解码也核对输入未改变。成功编码的JSON由独立标准JSON parser检查，变异后无效的deferred格式只允许通过Writer错误边界失败。

schema定义另做完整body的逐字节变异：修改后按协议重新计算带域前缀的SHA256和entry CRC，再调用严格decodeEntry，因此结构错误不能仅靠旧checksum拒绝。合法定义重新生成canonical metadata并核对hash，随后尝试解析引用载荷。磁盘矩阵使用8个真实文件，经公开Reader各独立只读导出两次，核对事件和原始文件字节。历史载荷fixture由明确header转换构造，独立历史golden与plain/compressed混合版本读取仍由原有codec/query测试覆盖。

这套门禁可重复、资源有界，用于兼容和回归；它不是覆盖全部输入的证明，也不替代长期coverage-guided fuzz或硬件故障资格。原始输出与源码身份见 `bench/evidence/2026-11-01-decoder-matrix/`。
