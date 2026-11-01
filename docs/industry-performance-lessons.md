# 从高性能日志库落实优化

设计借鉴以实际热路径和完成边界为依据。2026-11-01的同条件完整JSON对照中位结果尚不支持kron领先于Quill和Foundation；下一步先解决已测得的重复工作。正式数据见 [完整工作流](cpp-full-workflow.md)。

## 源码中确认的机制

| 参考 | 本轮检查的实现或文档 | kron采用与继续优化的方向 |
| --- | --- | --- |
| Quill 13.1 | BackendWorker批量从frontend queue生成TransitEvent，在读完一批后commit_read；一次扫描复用时钟采样 | 保留typed capture与SPSC；进一步减少消费端每条配置查找、游标与统计更新。不能在required输出完成前释放journal槽位 |
| Foundation Logging | Memory的RecordBatch连续字节区+记录end偏移；Mmap整批write/flush成功后complete_batch；flush携带accepted target | 吸收连续批次和整批确认方式，已有admission cut继续定义flush范围；按协议保留pending、配置pin和实际短写处理 |
| Foundation默认formatter | 缓存同秒日期/时区，先算输出大小后一次resize，再复制与写数字；线程缓存formatter clone | 共享encoder应减少重复Writer对齐/小块copy；如果引入静态输出描述符，必须明确失效与配置版本，不把常量测试字节当任意事件 |
| fmtlog | logId首次注册静态元信息、类型专门化getArgSizes/encodeArgs、后台formatToFn与fmt参数存储复用；单poll consumer、按buffer大小/最老字节延时/显式poll(true)刷新 | prepared schema继续显式预热；批量策略同时核对低频可见延迟和终止flush，不能让后续日志不断推迟最老pending |
| NanoLog | 编译期提取静态信息，运行期只捕获动态值，默认二进制并离线解码 | 借鉴静态信息去重，默认text/JSON保持可读；二进制吞吐必须单独报告，不用于完整可读JSON排名 |
| Reckless | 延迟格式化、批量I/O，强调对应用CPU/cache与队列饱和的影响 | 使用包含producer+worker+flush/关闭的工作流；扩展业务负载，统计CPU/内存和tail，不能只看入队中位延迟 |
| BqLog | 官方文档强调模板缓存、copy/hash合并、长度回填、批量I/O以及格式/内存/CPU成本 | 后续检查捕获与CRC是否可共用一次内存访问，输出协议与节点预算不变；压缩输出需独立比较 |

Quill、Foundation与fmtlog条目来自拥有源码；NanoLog/Reckless/BqLog条目来自官方README/设计介绍，后者不是对其全部实现或发布性能的独立验证。fmtlog读取当前master的具体内容并记录文件SHA256，提交查询不可用，因此不虚称固定到某个提交。具体读取源与SHA256在 `bench/evidence/2026-11-01-crc-slicing16/research-sources.json`。不增加生产依赖或直接复制上游实现。

fmtlog的队列数据采用进程内logId、类型专门化函数和部分对象表示，指针参数可要求对象一直存活到poll结束；这些冷/热分离机制有借鉴意义，表示方式不能直接写入kron持久journal。kron保留显式borrowed-call生命周期、字符串/bytes复制和自包含schema身份，并把首次注册/预热成本单独计时。同样，fmtlog源码使用volatile队列索引的发布方式，不能直接照搬到本库跨架构的release/acquire协议。

## 本次发现的工作量差异

对真实100万条、P4 SPSC-memory、完整JSON文件流程进行core PMU profile，约24%的采样落在slotChecksum。kron在producer提交、consumer checked peek和releaseAfter的checked peek都计算CRC。Foundation正常Mmap的peek只读slot descriptor，complete_batch检查顺序并发布FREE；恢复扫描另外检查CRC。两者因此具有不同的正常运行期损坏检查成本。这能解释部分CPU工作差异，但不是完整性能差距的唯一原因。

本轮先优化同一IEEE CRC算法：每轮16字节的portable slicing，保留每个校验点、schema引用参与范围、初值/反射/final XOR和恢复格式。只读表从8KiB增至16KiB。5对固定CPU的独立CRC过程PMU统计中，用户态cycles中位减少约24.4%，instructions增加约4.3%；这是并行化依赖链后的cycle收益，不是减少指令数。微基准时间与完整工作流仍有明显host波动，完整吞吐资格保持inconclusive。

2026-11-01随后在native x86_64加入编译期PCLMUL+SSE2 block folding，通用/非x86/短输入和尾部仍走portable表。journal形状CRC primitive中位在256B/512B/2KiB/16KiB分别下降约80%/87%/90%/92%；五对完整流程PMU的SPSC-memory P4与async-memory P1用户态指令分别减少15.33%/14.78%，SPSC-memory P4完整吞吐中位1.393M→1.816M条/s并达到本轮噪声门限。Vort 416组互操作、journal v1/v2 golden和完整ReleaseFast 503/503测试通过；这是原生x86_64路径，跨库排名仍需同轮复测。见 [提交热点](performance-hotspots.md) 和 `bench/evidence/2026-11-01-pclmul-crc/`。

120个before/after完整流程试验覆盖Memory/Mmap、shared/SPSC、P1/P4与sampled/batch，逐条核对1212万条日志。另为审查短批次P1 SPSC apparent regression运行10个百万条试验，核对1001万条；中位吞吐约1.23M→1.31M，但候选有明显慢尾，仍不宣称稳定提升。所有慢值原样保留。

## 已落实与后续实现

1. **同批配置与能力复用**：consumer View复用已实现，一批内相同generation/fingerprint只查找一次；跨版本保持独立View与lease，错误路径释放临时reader、保留record pin。真实shared/SPSC的31条同批记录确认只查找一次。完整shared-Memory P1本机测得约8.9%提升，其他组合仍inconclusive，见 [批次配置复用](batch-configuration.md)。后续已在当前批次每组预计算required durable route位图，避免每条交付和回收重复扫描，并保留原事件的完整durable barrier mask。
2. **批内统计与回收**：连续channel的written统计已聚合，31条实际shared/SPSC记录由31次原子RMW减少为1次；错误退出提交真正已确认的前缀，并发sync/fallback更新继续由fetchAdd合成。100次相同完整文件流程全部验证；prepared SPSC-Mmap中位变化约+3.5%，普通SPSC-Mmap约−1.2%，置信区间仍重叠，其他组合波动较大，本轮不宣称稳定提速，见 [批内确认与统计](batch-accounting.md)。journal游标、CRC和releaseAfter仍逐条处理；进一步合并回收需要先界定损坏发生在批次中间时的成功前缀、schema引用和durable checkpoint契约。
3. **编码输出路径**：完整text/JSON/logfmt记录已经复用同一次完整树校验，后续递归输出保持私有，公共value API继续独立验证。原golden及12个完整输出/16486种短缓冲前缀与冻结源码一致；五对编码probe用户态指令减少14.27%、cycles减少17.90%，完整SPSC文件流程指令减少2.55%，但100次普通文件试验出现较大候选慢值，另10次长流程仍未取得稳定吞吐资格，见 [编码校验复用](encoder-validation.md)。之后针对实际采样中的对齐/复制与转义回调，增加无宽度十进制输出和直接完整字符串consume：native数值直接生成digits，宽整数以10^19分块，所有JSON精度与generic Writer失败前缀保持；串行编码probe指令减少18.50%，完整SPSC文件流程指令减少6.22%，完整吞吐仍inconclusive，见 [数字与转义输出](decimal-output.md)。最新一轮把默认inline admission的完整树校验与长度统计合并：route predicate前调用`codec.measure`，接受后`encodeSized`只检查level/容量并写同一事件，不再重复长度遍历；redaction与prepared schema保持独立入口。完整流程用户态指令中位减少约2.5%，filtered invalid level与invalid tree的错误顺序由测试锁定，吞吐仍inconclusive。随后消费者decoded delivery复用checked decoder的树校验：`codec.decode`/`schema_codec.resolve`设置内部`Event.tree_validated`，内部`encodeDecoded`只对该证明跳过第二次`ValueValidator`，公开encoder忽略提示并始终校验，runtime用可信上下文覆盖调用方提示。五对完整流程PMU中SPSC-memory P4与async-memory P1用户态指令分别减少3.73%/4.49%，cycles与吞吐仍inconclusive。之后为常见形状增加fused wire-to-JSON：单JSON/text/logfmt route、v4 inline、非deferred、无args时一次解析并写出（nested attributes使用scratch arena），其他形状Fallback；SPSC-memory P4与async-memory P1指令再减少5.94%/6.20%。下一步继续研究Foundation的DefaultFormatter先计算appended_size、一次resize后顺序复制，同时保留全部value tags、UTF-8、source、边界和无效树零输出。Foundation的同秒日期缓存适用于日历时间文本；kron当前JSON是完整timestamp_ns，不能用降低时间戳精度来换取该项收益。
4. **捕获与CRC合并**：按BqLog所描述的方向研究共用内存读，但记录长度、借用生命周期与CRC覆盖必须在同一次安全调用内完成，不公开可复用unchecked凭证。

已实现条目按对应证据报告，其余条目是后续优先级。每项须有修改前源码、同语义完整工作流、故障门禁和明确性能限制，最终再与Quill/Foundation同轮复测。移动平台实际资格和长期fuzz仍按总验收清单继续。

参考链接：[Quill BackendWorker](https://github.com/odygrd/quill/blob/v13.1.0/include/quill/backend/BackendWorker.h)、[fmtlog](https://github.com/MengRao/fmtlog)、[NanoLog](https://github.com/PlatformLab/NanoLog)、[Reckless](https://github.com/mattiasflodin/reckless)、[BqLog](https://github.com/Tencent/BqLog)。Foundation使用用户指定本地仓库 [logging](/home/passchaos/robotics/onboard-monorepo/foundation/logging/README.md)。
