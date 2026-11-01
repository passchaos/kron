# 从高性能日志库落实优化

最新schema形状/类型检查合并遍历候选未推广：完整树校验和长度visitor期间观察schema key/type并延后形状错误，保持tree→metadata/shape→level→overflow优先级，4096项冻结旧/新差分一致。但独立PMU的schema SPSC指令增加0.463%，完整320项吞吐各组未取得资格，因此恢复原实现。全部400项/5640万条文件/PMU结果保存（其中首40项有潜在测试结束重叠，正式clean360项4436万条）；证据见`bench/evidence/2026-11-01-schema-shape-visitor/`。后续schema优化不能重复推广这一未通过的合并遍历机制，应继续从真实profile定位昂贵操作，并保留完整树校验与错误顺序。

设计借鉴以实际热路径和完成边界为依据。Memory/Mmap所有组合稳定超越Foundation的证据仍未取得；各轮排名以当轮源码和完整JSON对照为准。后续从当前热路径的可测成本出发，正式跨库数据见 [完整工作流](cpp-full-workflow.md)。

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

锁实现不能单独解释多producer完整流程差距。所读Foundation源码中，`parking_lot::Mutex/Condvar`保护Memory/Mmap队列状态；Memory通过交换连续RecordBatch并让多个批次共用文件缓冲，Mmap在文件flush后整批确认。kron SPSC reserve不获取共享队列mutex，仍执行每条CRC、配置引用和required输出确认；每checked batch完成flush后才释放slot。这些批量、确认和唤醒策略均影响饱和队列的成本。尚未进行同一实现只替换mutex的对照或将锁等待单独计量，因此不能把性能差距归因于parking_lot。所读拥有源码的版本/文件SHA256保存在`bench/evidence/2026-11-01-mmap-publication/foundation-lock-sites.json`。

1. **同批配置与能力复用**：consumer View复用已实现，一批内相同generation/fingerprint只查找一次；跨版本保持独立View与lease，错误路径释放临时reader、保留record pin。真实shared/SPSC的31条同批记录确认只查找一次。完整shared-Memory P1本机测得约8.9%提升，其他组合仍inconclusive，见 [批次配置复用](batch-configuration.md)。后续已在当前批次每组预计算required durable route位图，避免每条交付和回收重复扫描，并保留原事件的完整durable barrier mask。
2. **批内统计与回收**：连续channel的written统计已聚合，31条实际shared/SPSC记录由31次原子RMW减少为1次；错误退出提交真正已确认的前缀，并发sync/fallback更新继续由fetchAdd合成。100次相同完整文件流程全部验证；prepared SPSC-Mmap中位变化约+3.5%，普通SPSC-Mmap约−1.2%，置信区间仍重叠，其他组合波动较大，本轮不宣称稳定提速，见 [批内确认与统计](batch-accounting.md)。journal游标、CRC和releaseAfter仍逐条处理；进一步合并回收需要先界定损坏发生在批次中间时的成功前缀、schema引用和durable checkpoint契约。
3. **编码输出路径**：完整text/JSON/logfmt记录已经复用同一次完整树校验，后续递归输出保持私有，公共value API继续独立验证。原golden及12个完整输出/16486种短缓冲前缀与冻结源码一致；五对编码probe用户态指令减少14.27%、cycles减少17.90%，完整SPSC文件流程指令减少2.55%，但100次普通文件试验出现较大候选慢值，另10次长流程仍未取得稳定吞吐资格，见 [编码校验复用](encoder-validation.md)。之后针对实际采样中的对齐/复制与转义回调，增加无宽度十进制输出和直接完整字符串consume：native数值直接生成digits，宽整数以10^19分块，所有JSON精度与generic Writer失败前缀保持；串行编码probe指令减少18.50%，完整SPSC文件流程指令减少6.22%，完整吞吐仍inconclusive，见 [数字与转义输出](decimal-output.md)。最新一轮把默认inline admission的完整树校验与长度统计合并：route predicate前调用`codec.measure`，接受后`encodeSized`只检查level/容量并写同一事件，不再重复长度遍历；redaction与prepared schema保持独立入口。完整流程用户态指令中位减少约2.5%，filtered invalid level与invalid tree的错误顺序由测试锁定，吞吐仍inconclusive。随后消费者decoded delivery复用checked decoder的树校验：`codec.decode`/`schema_codec.resolve`设置内部`Event.tree_validated`，内部`encodeDecoded`只对该证明跳过第二次`ValueValidator`，公开encoder忽略提示并始终校验，runtime用可信上下文覆盖调用方提示。五对完整流程PMU中SPSC-memory P4与async-memory P1用户态指令分别减少3.73%/4.49%，cycles与吞吐仍inconclusive。之后为常见形状增加fused wire-to-JSON：单JSON/text/logfmt route、v4 inline、非deferred、无args时一次解析并写出（nested attributes使用scratch arena），其他形状Fallback；SPSC-memory P4与async-memory P1指令再减少5.94%/6.20%。下一步继续研究Foundation的DefaultFormatter先计算appended_size、一次resize后顺序复制，同时保留全部value tags、UTF-8、source、边界和无效树零输出。Foundation的同秒日期缓存适用于日历时间文本；kron当前JSON是完整timestamp_ns，不能用降低时间戳精度来换取该项收益。
4. **捕获与CRC合并**：按BqLog所描述的方向研究共用内存读，但记录长度、借用生命周期与CRC覆盖必须在同一次安全调用内完成，不公开可复用unchecked凭证。

已实现条目按对应证据报告，其余条目是后续优先级。每项须有修改前源码、同语义完整工作流、故障门禁和明确性能限制，最终再与Quill/Foundation同轮复测。移动平台实际资格和长期fuzz仍按总验收清单继续。

后续配置record pin批量释放实验已实际执行两版候选，分别以100项完整文件和20项完整PMU试验验证，共核对3224万条日志。语义测试确认31条同配置记录可从31次pin原子减法合成1次，但多个Memory组的负向中位、高spread和不重叠收益缺失使两版均未通过性能推广条件，生产实现恢复逐条pin释放。原始数据保留在`bench/evidence/2026-11-01-batch-pins/`，并保留更强的旧配置晚期损坏/lease回归。引用计数优化必须同时考虑逐条分支、状态维护、缓存竞争和完整流程；源码中看见的重复操作只能提供假设。

## 批次合并后的Memory/Mmap优先级

当前已将原四个64条服务量子内的就绪记录合并为最多256条窗口。240项完整文件试验核对2424万条物理JSON，portable Memory四组中位提升4.4%–10.0%，其中三组bootstrap中位区间不重叠；Mmap多数组未资格。独立io_uring P4 Memory两组中位提升14.2%/23.6%，共享Memory的调用p99也出现可重复负向。单对trace的pwritev1581→833、futex9184→4533只证明本次诊断操作数下降。源码、全部慢值、确认与恢复门禁见 [就绪批次合并](coalesced-delivery.md) 和 [完整证据](../bench/evidence/2026-11-01-coalesced-delivery/README.md)。

下表列的是待验证的候选，优先级综合当前证据、常用路径覆盖与实现复杂度；没有预先承诺百分比收益。新一轮先重新采集批次合并后的producer/consumer/系统调用profile，避免继续使用旧CRC占比解释当前瓶颈。

| 优先级 | 候选与 owning source | 现有成本与拟验证变化 | 验证重点 |
| --- | --- | --- | --- |
| 1 | 有界窗口与满队列尾延迟；`core/runtime.zig`、`core/delivery_batch.zig` | 固定最多256条在吞吐和槽位释放频率之间有取舍；研究按当前积压/输出字节控制窗口，保持每轮64条量子预算，不增加补满等待 | 稀疏、突发、持续饱和负载；P1/P4的完整written吞吐、调用p99/p99.9、低频可见时间与peer服务；不能只挑最优分位数 |
| 2 | 减少consumer到file的复制；`core/delivery.zig`、`sink/file.zig`、`backend/buffer_pool.zig` | 当前格式化到runtime scratch，再由FileSink复制入文件缓冲，io_uring再复制到稳定pool；研究私有的有界reserve/commit或批量writer，在完整验证后提交记录 | 所有格式字节与短缓冲失败前缀；invalid记录零输出；在途缓冲生命周期、partial write、flush/关闭和轮转 |
| 3 | schema/prepared的融合输出与静态元信息复用；`core/runtime.zig`、`core/schema_codec.zig`、`encoder/wire_json.zig` | 当前融合已覆盖inline v4和至少64条就绪窗口的schema，要求单route、无deferred/args；继续研究template路径与静态key/metadata转义缓存 | 按schema身份与配置版本失效，定义持久化先于ready；保留template语义、nullable/nested/source/trace、错误优先级与恢复；注册/preparation单独计时 |
| 4 | 多producer原子与缓存行竞争；`core/runtime.zig`、`core/admission.zig`、`core/thread_registry.zig`、`journal/journal.zig` | shared队列tail/accounting、全局admission/wake和channel counters仍有原子更新；SPSC也存在全局生命周期协调；先用PMU/cache-to-cache诊断定位，再研究热字段分离或精确分片统计 | P1/P4扩展、系统与用户CPU、满队列尾部；flush admission cut、关闭、错误唤醒和准确统计不变；当前证据不能归因于parking_lot |
| 5 | Mmap冷启动与channel准备；`journal/storage.zig`、`platform/mapping/linux.zig`、`core/thread_registry.zig` | mmap建立/初始化/文件与目录发布仍影响生命周期；研究显式预建channel、初始化内存访问与系统调用覆盖范围 | 单独报告init/preparation与written稳态，保留磁盘/channel预算、文件/目录发布和schema顺序；不能把启动同步成本用于解释普通written稳态差距 |
| 6 | io_uring跨窗口流水线；`backend/linux_uring.zig`、`core/runtime.zig` | backend已有稳定buffer pool和CQE进度，但runtime每个交付窗口后flush会排空在途写；研究有限pending windows，让下一窗口格式化与前一窗口I/O重叠 | 只有实际CQE完整成功才推进written/回收；mixed配置pin、短写、失败前缀、shutdown/deadline和资源上界。收益先与portable同轮复测，复杂度高于前几项 |
| 7 | 显式durable的批量checkpoint/reclaim；`journal/journal.zig` | durable `releaseAfter`当前逐条执行数据同步、checkpoint同步及slot失效同步；可研究对已完成durable输出的连续前缀进行有界整批持久回收 | checkpoint/slot复用顺序、torn write、每个失败边界与子VM掉电恢复；只对durable路径有意义，当前普通written性能试验未执行这些逐条同步 |

此前条件progress wake候选虽然并发门禁通过，完整吞吐仍未取得收益，饱和负载futex次数也未下降，已恢复原通知策略，见`bench/evidence/2026-11-01-progress-wakeup/`。这和批量pin的负向结果说明后续应测量新的成本或改变机制，避免重复推广同一未通过候选。PCLMUL CRC、默认脱敏scratch、重复树校验、批内配置View、written聚合和就绪批次合并均已落实，不作为新的待做项目。

直接渲染到FileSink staging的同步callback候选也已否决：完整280项试验核对3628万条JSON，40项PMU四组用户态指令增加0.48%–0.64%，完整240项吞吐各组中位区间全部重叠，多个默认Memory路径中位负向。候选正确性门禁通过，但额外接口、回调与状态维护没有取得端到端收益；生产恢复`c2f8792`，完整候选/失败与正负原始报告见`bench/evidence/2026-11-01-direct-record-buffer/`。后续减少复制应采用不同机制并重新计量成本，不能把“少一次memcpy”直接作为速度结论。该实验之后转向shared admission已保护配置View的复用，必须保持旧配置lease、采样/filtered结束与异步record pin独立。

随后shared admission已直接复用已验证View，直到end释放reader，accepted record的独立pending pin与原CRC/barrier/reclaim保持。相关真实Memory/Mmap计数、并发旧lease与filtered/sampled/error回归通过。最终320项完整文件、40项PMU及独立10项百万条检查共核对5437万条JSON；shared schema Mmap P1短流程中位+9.55%、独立长流程+4.79%，CV/spread通过且区间不重叠。PMU shared Memory P4却有−3.36%负向中位且区间不重叠；完整workflow多数P4差异区间重叠，不能宣布一般P4收益或完整CPU指令下降。早期测试退出重叠长流程独立保留，不计入正式370项资格。来源与所有限制见`bench/evidence/2026-11-01-admission-view/`；保留该有范围的优化后继续按当前热点推进。

跨队列64条轮次合并窗口已实际验证并否决。完整440项/5244万条JSON显示p99.9降低与p99/p50显著升高并存，吞吐与单量子控制均未取得整体资格，用户态指令增加0.58%–0.71%；候选的调度/跨来源确认成本及更大transitive stack不推广。生产恢复同轮对照的`e8bd353`逻辑；源码、真实FIFO/故障/服务预算门禁与全量分布保留在`bench/evidence/2026-11-01-cross-queue-delivery/`。后续应针对满队列等待者与progress_epoch的跨队列唤醒进行有界诊断；保留worker错误、shutdown和reservation gap的正确唤醒，避免从表面批次大小推导整体低尾延迟。

随后对SPSC满队列等待加入本队列space通知，保持原调度和global control等待。前后各12项诊断发现本队列written未变化的futex返回降为0，但这个计数本身不作为wall-time资格。正式400项完整文件/PMU/百万条对照核对8440万条日志，Memory inline SPSC P4长sampled p99.9中位下降6.99%、局部重复性及区间不重叠成立；p50/p99、Mmap和普通吞吐大多仍inconclusive。没有省略CRC/pin/barrier或提前回收，worker错误/关闭对所有队列通知；登记与epoch的SC握手锁定wait前事件边界，每Journal增加64字节进程内control。保持这项有限收益后，仍需继续降低约340µs的极端等待和明确其他负载资格。原短流程P1负向、全量分布和真实并发测试见`bench/evidence/2026-11-01-queue-progress/`。

参考链接：[Quill BackendWorker](https://github.com/odygrd/quill/blob/v13.1.0/include/quill/backend/BackendWorker.h)、[fmtlog](https://github.com/MengRao/fmtlog)、[NanoLog](https://github.com/PlatformLab/NanoLog)、[Reckless](https://github.com/mattiasflodin/reckless)、[BqLog](https://github.com/Tencent/BqLog)。Foundation使用用户指定本地仓库 [logging](/home/passchaos/robotics/onboard-monorepo/foundation/logging/README.md)。
