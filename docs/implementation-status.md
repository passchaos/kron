# 实现验收清单

本文件跟踪 [整体设计](design.md) 的实际完成证据。未通过运行、故障注入或源码审查的条目保持未完成；不能以类型声明或文档存在替代行为验证。

当前按用户要求完成 Windows/Linux/macOS/Android/iOS 单机日志。网络 sink、HTTP/TLS collector、OTLP exporter及其测试和构建入口已删除。历史门禁计数只代表当时源码，当前能力以本轮门禁为准。

## 当前单机门禁

就绪记录合并交付已完成：原64条服务量子预算1..4保持，每次checked peek合并当前剩余预算内最多256条连续就绪记录，不等待补满；配置组仍最多64，每条CRC/schema/旧路由pin和输出后checked reclaim保持。真实runtime覆盖Memory/Mmap×shared/SPSC×inline/schema，255条第一次屏障全部输出且初始化后零分配；初始晚期损坏零输出，混合旧/新配置最后flush/durable失败保留全部255条与150/105个pin，回收晚期损坏只确认190条并保留65条旧pin。预算与合并定向Debug/Safe/Fast通过；完整ReleaseSafe门禁 **93/93步骤、540/540测试**，包含实际SIGKILL、独立五模式/单线程/源码分发包与Linux宿主自校验；九目标ReleaseSafe对象编译10/10步骤通过，其他平台设备运行仍未取得。两个新子QEMU停机schema ACK31/inline ACK3恢复通过，限Linux6.8/ext4虚拟机。四个记录跟踪数组本机5440→21760字节，消费者栈增加16320字节，配置组与heap/journal/file预算不增。这不是完整编译器栈帧测量。

与基线`45f5ec1`完成portable160项与独立io_uring80项完整文件试验，共2424万条物理JSON逐条核对，accepted=written、pending/drop=0，保持系统墙钟、完整字段和written flush/关闭/清理终点。Portable Memory P1/P4 shared中位提升4.44%/6.90%、SPSC提升5.78%/9.97%，四组CV/spread通过、后三组bootstrap中位区间不重叠；Mmap多数组仍inconclusive。io_uring P4 Memory shared/SPSC中位提升14.18%/23.62%，两组CV/spread通过且区间不重叠；Mmap未资格。共享Memory io_uring p99中位22459→34674ns为可重复负向，portable共享P4尾部负向中位仍inconclusive。保留此前io_uring54项完整行的中断测量及所有慢值，不并入正式80项资格。单对trace pwritev1581→833、futex9184→4533用于诊断，不能等同时间收益。当前源码/归档/二进制/门禁身份及完整限制见[批次合并报告](../bench/evidence/2026-11-01-coalesced-delivery/README.md)与同目录qualification.json；本轮没有新的Foundation或同轮后端排名。

此前源码`c4b7f34`的完整文件portable/io_uring同二进制对照已完成160/160试验、1616万条物理JSON逐条核对：Memory/Mmap、shared/SPSC、P1/P4分别运行五次sampled/batch，所有显式io_uring实际选择linux_uring，accepted=written且pending/drop=0。io_uring中位吞吐在此负载低约17%–19%，8个batch组中6个两侧CV/spread通过、2个inconclusive，全部slow trials保存。checked batch确认边界限制I/O重叠，不能推广为所有负载的后端结论；文件后端报告会拒绝fallback/预算变化/不完整输出。Safe定向8/8步骤、14/14 Zig测试及Python负向校验通过，Memory/Mmap真实worker错误唤醒回归Debug/Fast也通过。新增可复现入口及结果见[该轮io_uring完整对照](../bench/evidence/2026-11-01-uring-current/README.md)。

条件progress wake候选未推广：登记waiter后条件futex唤醒的并发窗口测试通过，160项日志全部正确，但多个共享队列吞吐负向中位和bootstrap重叠未证实收益。饱和追踪总futex数量未下降，说明该负载仍有真实waiters；生产恢复原来通知。保留Memory/Mmap满SPSC队列等待者在worker写失败时被唤醒、返回原错误、两条accepted记录仍pending的实际回归。候选源码、1616万条原始结果与拒绝依据见`bench/evidence/2026-11-01-progress-wakeup/`。

Linux/Android冷Mmap发布省去全文件fsync之前的重复msync，保留文件/父目录fsync；其他平台映射flush和显式strict durable原协议保持。Linux6.8内核与ext4同步源码确认覆盖范围，文件/目录发布失败回归验证初始化失败与锁释放、schema目录失败仍unready且不占reservation。真实子QEMU/ext4 schema ACK17/31与inline ACK3强杀恢复通过。160次Memory/Mmap完整文件对照核对1616万条，全部accepted=written、pending/drop=0；调用追踪msync为5→0、fsync仍10、fallocate仍5。初始化/吞吐全部inconclusive，共享Mmap负向启动中位与SPSC正向中位、全部慢值保留，不宣称稳定性能或跨库优势。最终Safe综合89/89步骤、532/532测试和九目标ReleaseSafe实际对象通过。证据见[Mmap发布](mmap-publication.md)及`bench/evidence/2026-11-01-mmap-publication/`。

按用户最新要求，当前源码`182fc9e`默认budget4仅Memory/Mmap同轮比较Foundation真实spdlog前端＋Rust后台与kron：120/120试验、1212万条物理JSON完整核对，accepted=written且pending/drop=0。Memory P1/P4包含关闭中位M条/s：Foundation1.932/1.990、kron shared2.136/2.063、SPSC2.151/2.106；Mmap为Foundation1.789/2.097、shared2.107/1.741、SPSC2.157/1.911。Memory中位领先、Mmap P4仍落后，Foundation全部吞吐组波动超门限，不宣称两种模式稳定超越。Mmap SPSC P4初始化中位368ms、完整生命周期446ms，对Foundation13ms/62ms，原始慢值与尾分位均保留。完整源码、机器、库、格式/完成边界和逐项报告见[当前Memory/Mmap对照](../bench/cpp_reference/evidence/2026-11-01-memory-mmap-current/README.md)。

Memory/Mmap消费者批次预算显式提供`consumer_batches_per_queue=1..4`，默认4保持原行为；非法预算分配前失败。确定性真实后台在两种存储、共享peer/SPSC peer组合验证1/2/3/4批的peer服务位置1/65/129/161，FIFO、written、零剩余积压与零初始化后分配保持；公开测试观察满SPSC队列真实futex等待，shutdown正确唤醒并abort未完成reservation。固定一批默认候选160项完整文件核对1616万条，p99.9改善而p99明显负向、吞吐未资格，因此未提升为默认。同二进制默认4/显式1的40项再核对404万条，Memory p99中位10.9→82.8µs、p99.9约377.7→114.7µs；Mmap为9.1→84.5µs与391.0→110.7µs，均inconclusive且完整慢值保留。当前Safe综合89/89步骤、530/530测试和九目标实际对象通过；调度取舍见[消费者服务预算](consumer-scheduling.md)及`bench/evidence/2026-11-01-channel-fairness/`。后续性能按用户要求仅分Memory/Mmap比较。

静态scalar捕获按comptime类型计入节点，动态Value/容器/prefix仍完整校验；时钟回调后runtime继续验证最终树，新增共享/SPSC clock制造cycle测试确认不占reservation。长度累计改为每项截u32_max+1的u64，在完整验证后判断TooLarge，8192算术差分及maxInt(usize)/cycle/duplicate优先级通过。组合方案完整PMU SPSC P4/shared P1用户态指令中位下降3.00%/3.32%，static-only为2.68%/2.97%，spread通过；两版共40项PMU核对1204万条JSON。正式100项文件核对1010万条，吞吐全部inconclusive、多个中位下降。额外20项长sampled核对602万条，SPSC p99中位1051→10143ns、p99.9为360195→420294ns，波动未通过门限，负向数据全部保留，不宣称吞吐或尾延迟收益。最终Safe完整89/89步骤、527/527测试及九目标ReleaseSafe实际对象通过。证据见`bench/evidence/2026-11-01-static-scalar/`与`2026-11-01-wire-size/`；后续需检查饱和队列和等待路径的tail，而非只降低producer中位工作量。

批量配置record pin优化资格已完成并拒绝：两个候选分别100项完整文件与20项PMU，共240试验、3224万条物理JSON全部正确，但未取得完整吞吐改善资格，多个负向中位和高spread保留；生产配置/交付模块保持`8a351c0`。保留共享/SPSC旧版本晚期回收损坏回归：written=1、pending=2、检查View与SPSC cache释放后剩余record pins仍阻止旧lease回收，destroy只释放一次。最终三优化级别batch定向均18/18（含import fixtures），证据及候选源码见`bench/evidence/2026-11-01-batch-pins/`。后续优化仍需完整流程证据，不能以原子数量下降宣称收益。

native数字输出进一步直接写入已有Writer buffer：剩余至少21字节时精确计算位数并写入，仅更新实际end；独立helper避免扩张递归value渲染，短buffer/streaming/宽值继续bounded stack fallback。公开encoder的12完整记录、16486 fixed与49494 generic前缀和新增内部buffer物理短写前缀保持；Safe公开时间/配置/predicate/文件30/30、最终完整ReleaseFast89/89步骤和522/522测试通过。100个完整文件试验逐条核对1010万条日志，五组吞吐中位提升3.0%–4.0%，均满足本轮CV/spread，SPSC Memory P4中位区间不重叠，其余仍重叠。另20个长流程核对602万条：SPSC P4 user cycles减少4.99%、instructions增加1.00%，候选极慢producer样本使长流程吞吐仍inconclusive，全部保留。早期inline/table方案nested负向与最终helper结果分别保存；不叠加为Foundation排名。百万条完整流程profile与mmap慢启动调用已确认：一个5.1s启动中msync约3.1s、file/dir fsync约2.0s，协议保持。证据见`bench/evidence/2026-11-01-decimal-direct/`、`2026-11-01-delivery-profile/`和`2026-11-01-init-profile/`。

当前源码`4447fe6`完整文件流程已同轮比较Foundation真实spdlog前端/Rust后台、独立spdlog1.17和kron：140/140项正式试验、1414万条物理JSON全部逐条核对，accepted=written且pending/drop=0。包含关闭的P1/P4中位M条/s：Foundation Memory2.116/2.309、Mmap1.800/2.079，spdlog1.640/0.673，kron SPSC Memory2.174/2.108、Mmap2.251/2.117；shared组及各阶段也分别保存。kron本轮中位高于独立spdlog，P4 Memory仍落后Foundation约9%，P4 Mmap差异小于spread，SPSC Mmap完整生命周期约107ms对Foundation58ms。独立spdlog和部分Foundation组超10%门限，安静窗口跨库优势仍未资格；未启用predicate，正则局部收益不混入该比较。精确源码、完整慢值与分析见[当前完整工作流](../bench/cpp_reference/evidence/2026-11-01-current-workflow/README.md)。

正则匹配热路径已把BOL/EOL条件下的epsilon/assertion展开移到配置编译期，运行期使用两个64位活跃位图，仅遍历消费字节状态；128-state/32-depth/8KiB-input、任意byte、nullable循环、严格anchor和多regex独立状态范围保持。最终方案已在临时完整源码副本通过1004626次ReleaseSafe coverage guided运行（4510 unique），主源码完整ReleaseSafe门禁通过89/89步骤、520/520测试，Debug/Fast公共定向各13/13；主源码另完成1006557次coverage guided运行。八类业务输入与两类完整同步JSON做五对子进程、各五次重复的CPU affinity对照，900项样本输入/匹配/written/JSON hash全一致；最终全部组因spread超门限标inconclusive，中位数的改善不作为稳定吞吐承诺。native x86_64 Pattern为4624→9264 bytes，Predicate为17952→25632 bytes，增加固定配置内存与编译成本。两个早期方案的重叠分支回退与原始报告全部保留，最终方案消除本轮该项负向中位。源码、探针与报告见[正则匹配工作量](regex-performance.md)及`bench/evidence/2026-11-01-regex-active/`；分发包暂存已排除ignored测量产物，修复3.8GB bench产物导致本地fetch超时，重新fetch的独立包五模式通过；原失败保留。长期sanitizer、其他平台运行和安静窗口性能资格仍缺。

正则边界本轮补齐：编译/匹配拆到`src/pipeline/regex.zig`，字段规则/配置字符串留在`pipeline/predicate.zig`，保留Pattern/Regex公共别名与原128-state/32-depth/8KiB输入预算。修复首项`]`字符类与控制/两位hex转义，未支持类别/断言/回溯引用/未知字母转义明确返回`UnsupportedRegex`，直接量词化anchor及畸形hex返回`InvalidRegex`；UTF-8按字节、`.`排除LF、`$`严格末尾的原行为由oracle锁定。8个种子共161872项结果（161504项独立Python bytes匹配、360项精确编译拒绝、8项输入超限）及每种子8项driver负向自检全部通过；原短ASCII语料保留。5项模块测试覆盖全部65536对literal与65536对class字节、full range与精确预算边界，Debug/Safe/Fast均通过。新增8192项regex mutation/arbitrary-input与4096项predicate parser mutation进入`test-regex-fuzz`和`verify-local`；最终三优化级别定向门禁通过9/9测试，公共runtime验证失败replacement维持配置与reservation水位、首项`]`的实际交付与末尾LF过滤。语料gzip、原始失败和通过记录见`bench/evidence/2026-11-01-regex-boundaries/`；持续sanitizer fuzz与业务regex性能资格仍未完成。

消费者新增 fused wire-to-JSON 路径：仅对当前自包含 v4 payload、单个 JSON/text/logfmt route、非 deferred message、无 format args；attributes 可为 scalar 或 nested，nested descriptor 使用 caller scratch arena，在 checked wire parser 验证每个 tag/top-level key 后直接写入 caller scratch；其他形状返回 `error.Fallback` 并继续走 decode+encode。journal 格式、公开 encoder、校验边界和 route 语义不变。单元测试用 flat event（含 trace/span/source）与 nested group/array 逐字节比较融合输出与 decode+encode，template 确认 Fallback；完整 `verify-local` 通过 81/81 步骤、510/510 测试（包含 nested 与 text/logfmt fused 验证）；10,000 条 SPSC-memory workflow 的 11,000 条物理记录通过独立 oracle。五对固定 CPU PMU 中 SPSC-memory P4 指令减少 5.94%、async-memory P1 减少 6.20%，spread 0.8%–1.2%；cycles/吞吐仍 inconclusive。100 个完整文件试验结果见 `bench/evidence/2026-11-01-wire-json/`。2026-11-01 负载窗口同轮 Foundation/kron 复测完成 120 个试验、1212 万条记录验证，全部组因 spread 超门限标 inconclusive；同轮中位数显示 P1 kron 领先、P4 Foundation 略领先，稳定排名仍需安静窗口复测，见 [完整工作流](cpp-full-workflow.md) 和 `bench/cpp_reference/evidence/2026-11-01-pclmul-same-round/`。见 [提交热点](performance-hotspots.md)。

消费者 decoded delivery 已复用 decoder 的完整树校验：`codec.decode` 和 `schema_codec.resolve` 在完成 wire 树、节点预算、深度、重复 key 和长度检查后设置内部 `Event.tree_validated`；内部 `encoder.common.encodeDecoded` 仅对该证明跳过第二次树校验，公开 `encoder.encode/encodeWithTime` 仍始终校验并忽略该提示。Runtime 不信任调用方提供的提示，先用 admission 的 `codec.measure` 或 redaction/binding 校验，再由 `submitSafeDestination` 用可信上下文覆盖；binary route 继续走公开校验路径。新增测试锁定：伪造提示的 invalid tree 仍被公开 encoder 拒绝且零输出、`runtime.submit` 的重复 key 仍返回 `DuplicateKey`、decoded text/JSON/logfmt 与公开 encoder 字节一致。`zig build test -Doptimize=ReleaseFast` 通过 35/35 步骤、481/481 测试；完整 `verify-local` 通过 81/81 步骤、505/505 测试；定向 ReleaseSafe proof 10/10 与 predicate 1/1 也通过。五对固定 CPU 完整流程 PMU 中，SPSC-memory P4 用户态指令中位减少 3.73%，async-memory P1 减少 4.49%，两侧 spread 0.5%–1.6%；cycles/task-clock 与吞吐仍 inconclusive。100 个完整文件试验在 52 个、525 万条记录后遇到 mmap 子进程 120 秒超时，已完成的试验全部 accepted=written、pending/drop=0，但不作为吞吐资格。证据见 `bench/evidence/2026-11-01-decoded-delivery/`。

原生 x86_64 的 IEEE CRC block loop 已增加编译期 PCLMUL+SSE2 路径：64-byte 四路 folding、128→64→32 和 Barrett reduction；通用 x86_64、非 x86、短输入和 <16 字节尾部继续使用 portable 16-byte slicing。持久化多项式、reflection、final XOR、commit/peek/release 校验点、schema 引用范围、journal 与恢复格式均不变，不运行时探测、不分配、不增加依赖。CRC 模块差分覆盖 32 对齐×22 长度×14 增量切分并与 `std.hash.Crc32` 逐项比较；`-mcpu=baseline` 重新验证 portable fallback，aarch64 编译通过，journal v1/v2 golden 与 Vort 416 组互操作（`backend=hardware`）通过。完整 ReleaseFast 门禁通过 81/81 构建步骤、503/503 测试；首次运行遇到宿主 I/O 下 crash writer 10 秒未 READY，单独重跑 `test-crash` 与完整门禁复跑均通过。journal 形状 CRC primitive 中位在 256 B/512 B/2 KiB/16 KiB 分别为 95.2→19.0、200→26.3、785→79.6、6312→535 ns；五对完整流程 PMU 的 SPSC-memory P4 用户态指令减少 15.33%、async-memory P1 减少 14.78%，SPSC-memory P4 完整吞吐中位 1.393M→1.816M 条/s 且达到本轮噪声门限。100 个完整文件试验核对 1010 万条 JSON，全部 accepted=written、pending/drop=0；宿主 load 约 110，五组吞吐中位提升 15%–84% 但均标 inconclusive。这是原生 x86_64 路径，通用/非 x86 不获得该加速；跨库排名仍需同轮复测。见 [提交热点](performance-hotspots.md) 和 `bench/evidence/2026-11-01-pclmul-crc/`。

默认 inline admission 的完整树校验与长度统计已合并：route predicate 前调用 `codec.measure`，接受后 `codec.encodeSized` 只重新检查 level/容量并写同一未变事件，不再执行第二次长度遍历。Redaction 重写借用存储、prepared schema 使用不同 wire 形状，二者保留独立校验/测量；公开 `codec.encode` 仍独立校验，不导出 unchecked writer 或 validation token。新增 codec 字节一致性/容量/level 测试和公共 predicate 集成测试，锁定 invalid tree 仍在 predicate 前失败、filtered invalid level 仍返回 filtered、嵌套值完整交付。当前完整 ReleaseFast 门禁通过 81/81 构建步骤、502/502 Zig 测试；定向 ReleaseSafe codec/predicate 测试也通过。一次完整 ReleaseSafe `zig build test` 尝试在宿主负载约 110、根盘 98% 占用下阻塞于 `jbd2_log_wait_commit` 超过 18 分钟，已中止且不记为通过；完整 ReleaseSafe 需在更安静的窗口重跑。五对固定 CPU 的完整文件流程 PMU 中，SPSC-memory P4 用户态指令中位减少 2.99%，async-memory P1 减少 3.39%，两侧 relative spread 为 0.5%–1.2%；cycles/task-clock 仍 inconclusive。100 个交替完整文件试验逐条核对 1010 万条 JSON，所有 accepted=written、pending/drop=0，但全部吞吐组至少一侧 CV/spread 超过 10%、bootstrap 区间重叠，故吞吐仍 inconclusive，保留 async P1 负向中位。证据见 `bench/evidence/2026-11-01-admission-measure/`。

固定偏移时间处理已接入：Timestamp/Date/DateTime/Duration分别表示，UTC与显式offset支持RFC3339纳秒格式化/解析；用户明确不需要夏令时，未加入IANA或隐式Local。路由版本拥有同秒缓存，offset/precision进入可选恢复指纹，默认数字输出与原指纹保持。时间Debug/Safe模块各10项（9项实质测试）、五项公共集成与完整400年周期、4096随机timestamp/mutation、独立Python4166时间戳和5845日期oracle通过。实际五模式覆盖积压旧配置、零runtime分配、OOM清理和journal关闭/重开，改变offset/precision被拒绝。当前完整ReleaseFast498项、九目标Safe实际时间路径与23项时间/文件/配置测试通过；Linux异步真实JSON例子也独立核对。独立同秒cache的日期转换由10万次降为1次，窄范围成本约52→22ns（含hash、初次未固定affinity），不作为完整日志吞吐资格。见 [时间处理](time.md) 和 `bench/evidence/2026-11-01-time/`。

十进制记录输出与完整字符串直接转义已实现：无宽度数字不经通用alignment，宽整数按10^19分块；UTF-8共用原状态机，流式消息与float保持原实现。65536个u16及2048对宽整数、12个完整记录/16486种fixed前缀/49494种generic Writer前缀差分通过。Debug/Safe定向各26项、完整ReleaseFast483项与九目标Safe实际对象/18项文件和配置测试通过。100次文件流程核对1010万条日志，全部吞吐仍inconclusive；串行编码probe指令减少18.50%、cycles减少27.14%，完整SPSC文件PMU另核对301万条、指令减少6.22%，但不宣称稳定端到端提速，见 [数字与转义输出](decimal-output.md)。

完整text/JSON/logfmt记录已复用同一次attributes/format_args树校验，递归输出保持私有，独立value API继续完整验证；全tag事件节点访问由27次减少为14次。转义拆到独立内聚模块，公开格式入口与golden保持。两项新增实质测试、Debug/ReleaseSafe编码定向各23/23、12个完整输出/16486种短缓冲前缀与冻结旧源码差分通过。该轮完整ReleaseFast480/480与最终九目标ReleaseSafe实际对象/18项真实文件和配置集成通过。100个完整文件试验核对1010万条日志，部分候选有明显慢值，全部吞吐仍inconclusive；额外五对编码probe用户态指令减少14.27%、cycles减少17.90%，五对P4 SPSC完整文件流程另核对301万条、指令减少2.55%，但稳定吞吐仍未建立。所有负向数据保留，不能把局部CPU计数当整体提速或当前跨库排名，见 [记录编码校验复用](encoder-validation.md) 与 `bench/evidence/2026-11-01-encoder-validation/`。

此前后台批内durable决策与written统计聚合已实现：每个受保护配置组预计算required durable route位图，事件只判断一次确认边界，保留原完整route barrier；连续channel的已确认记录由31次written原子RMW减少为1次，仍使用fetchAdd合成并发同步/fallback计数。四项新实质测试与真实shared/SPSC批次计数回归通过；晚期reclaim损坏仅确认成功前缀，written=1、pending=2，剩余record pin保留。该轮Debug/ReleaseSafe定向各13/13、完整ReleaseFast478/478与九目标ReleaseSafe实际对象/37项配置、事务、deadline、真实文件故障测试通过。100个完整JSON文件流程逐条验证1010万条日志；prepared SPSC-Mmap中位变化约+3.5%，普通SPSC-Mmap约−1.2%，置信区间仍重叠，其余组合波动较大，该轮不宣称稳定端到端收益。见 [批内确认与统计](batch-accounting.md) 和 `bench/evidence/2026-11-01-batch-accounting/`。

上一轮后台批次已实现受保护配置View复用：同一非零generation/fingerprint仅查找一次，旧版本持有到整批barrier与记录确认结束；历史generation=0继续完整查找。5项新测试覆盖64版本、shared/SPSC真实31-record批次、错误指纹与混合sink失败，失败保留record pin/lease并释放临时reader；旧实现会被新lookup回归以31次查找拒绝。该轮Debug与ReleaseSafe定向12项、配置/事务/deadline31项以及完整ReleaseFast474项通过；最终九目标ReleaseSafe实际对象与12项配置集成测试通过。100个相同完整JSON文件流程验证1010万条记录，shared-Memory P1本机中位吞吐约1.16M→1.26M条/s，约8.9%提升；其他组合仍inconclusive，见 [批次配置复用](batch-configuration.md) 与 `bench/evidence/2026-11-01-batch-configuration/`。这些性能数字属于此前快照，不与本轮不同基线混合排名。

完整文件日志profile约24%采样在journal CRC，采用portable 16-byte slicing后保留全部commit/peek/reclaim检查及IEEE协议，表由8KiB增至16KiB。3项CRC模块测试和416组实际Vort互操作、6项真实文件故障、12个随机SIGKILL场景通过；完整ReleaseFast469项与最终九目标ReleaseSafe对象/6项文件故障门禁通过。5对固定CPU的独立CRC过程PMU中位cycles降低24.4%，instructions增加4.3%；120个完整流程与10个百万条长批次共2213万条输出全部正确，但稳定吞吐/尾延迟仍inconclusive。具体Quill/Foundation/fmtlog源码机制与后续批处理改进见 [业界实现与优化方向](industry-performance-lessons.md)，原始报告见 `bench/evidence/2026-11-01-crc-slicing16/`。

完整C++/Foundation性能对照已按用户要求重跑：spdlog1.17、Quill13.1、指定onboard-monorepo Foundation Logging和测试时kron，同一完整JSON字段、系统墙钟、1/4producer、Memory/Mmap与prepared/inline，260个正式试验逐条验证2626万条日志；Foundation原始默认formatter另40个控制试验、404万条日志。结果分别报告初始化、预热、producer、written flush、shutdown和cleanup；没有采用producer-only吞吐或不同JSON输出大小排名。该次对照快照的kron完整流程尚未领先，host噪声使多数稳定倍数仍不成立。4项报告负向测试与最终52个小规模流程smoke均通过；跨库实测源码固定在归档中，CRC更新另有before/after测量，不能混合不同源码数字。见 [完整工作流对照](cpp-full-workflow.md) 和 `bench/cpp_reference/evidence/2026-11-01-full-workflow/`。

路由过滤新增不可变level继承掩码，独立scope filter保留逐route检查；每版本额外64字节，不增加热路径原子/分配，不改变wire或恢复指纹。2940种内部对照、64个route的公开sync/shared/SPSC交付、filter-only与full replacement、旧snapshot与channel cache测试通过。相关Debug1/1、ReleaseSafe15/15、ReleaseFast13/13与原生宿主门禁通过；最终九目标ReleaseSafe实际对象和公共route-filter测试通过。225对enabled-only校验和/预算一致，8个route本机成本下降约12%–18%；40个公共admission/full试验确认200000written/pending0/分配0，但完整吞吐与p99仍inconclusive，见 [路由过滤性能](route-filter-performance.md)。

解码兼容矩阵已补齐8类inline/reference、当前/历史版本、scalar/nested和deferred template输入。每种优化级别完成16,384次变异、2,382项逐字节截断与128种短scratch容量检查；9,319个合法变异通过借用范围、完整树预算、精确再编码和JSON检查。schema定义刷新CRC/hash后54个结构损坏被拒绝、93个合法定义重新核对canonical hash；8个真实文件由Reader各只读导出两次。Debug/ReleaseFast独立矩阵各3/3通过，ReleaseSafe fuzz/query共30/30通过，证据见 `bench/evidence/2026-11-01-decoder-matrix/`。该矩阵已包含于当前完整门禁；长期coverage-guided fuzz仍未完成。

独立 Zig 包新增目标宿主自校验 `qualify DIRECTORY`，测试逻辑可直接在 Zig 移动宿主调用，不依赖 Python 或子进程。Linux普通/单线程ReleaseSafe及普通ReleaseFast运行通过五模式或sync、初始化后runtime零分配、Unicode文件名、普通/schema journal关闭重开与独占锁、只读inspection、轮转保留和实际durable能力；本地fetch源码分发包同样通过。独立包2项测试通过，已有验收目录拒绝复用且输出不变；根test-platform-host门禁2/2步骤通过，包含该入口的Windows PE实际链接通过，其他四平台设备运行仍未取得。见 [平台支持](platforms.md) 与 `bench/evidence/2026-11-01-platform-host/`。新 `test-platform-host` 已接入当前完整verify门禁。

预注册 schema 编码已合并完整树校验与长度统计，并通过内部共享 wire writer 写出，每次参考 size/encode 只校验每节点一次；公开 value writer 继续独立校验。新增4项边界/计数测试通过，ReleaseSafe相关41项编码测试、31项外部编码/双存储/query及实际崩溃门禁通过；最终九目标ReleaseSafe实际对象与编码基准输入测试通过。450对固定affinity before/after checksum、字节数和预算精确一致；本机参考长度计算下降约23%–44%、nested参考编码下降约29%，其他参考编码因noise仍inconclusive，见 [编码与归档](encoding.md)。

随机运行期进程终止已补充：两个 producer，共享/SPSC 与普通/schema 四组合，在 READY 后持续正常提交和写出，再按种子时间实际 SIGKILL。ReleaseSafe/ReleaseFast 正式 `test-runtime-crash` 各 12 个场景与 6 项负向 oracle 测试通过；额外 32 个普通种子和 8 个 u64 边界种子确认 109,419 条完整 ACK 均由输出/恢复覆盖，观察到重复与未完成 reservation。详见 [文件可靠性](file-reliability.md) 和 `bench/evidence/2026-10-31-random-process-crash/`。2026-11-01完整门禁又实际命中1950字节未完成JSON尾部，确认它是journal恢复完整记录的前缀；当前门禁日志见 `bench/evidence/2026-11-01-schema-encoding/`。

公共接口仅保留 Zig API。独立消费项目通过 `b.dependency("kron")` 和 `dependency.module("kron")` 导入，ReleaseSafe 实际运行 sync/memory/mmap/SPSC-memory/SPSC-mmap，核对 JSON、深拷贝、脱敏、reload、written/pending 和文件数量；单线程消费项目确认 Linux 只有一个 OS 线程，异步模式在创建文件前拒绝。按 ZON `.paths` 经本地 `zig fetch` 形成的源码归档也通过独立五模式运行。Windows x86_64-gnu 独立应用完成实际 PE 链接，尚无设备运行资格。见 [Zig 包接入](package.md) 和 `bench/evidence/2026-10-31-package-consumer/`。较早458项计数保留于对应历史证据。

`zig build verify-local -Doptimize=ReleaseFast -j2 --summary all` 已通过 **81/81构建步骤、498/498 Zig测试**，另通过15项Python回归工具测试、6项恢复oracle负向测试、4项C++工作流报告负向测试、17项负向编译、4096项正则差分、原有6种真实SIGKILL恢复及6个内存/mmap退出和drain场景、10个种子恢复campaign与12个随机运行期SIGKILL场景，独立Zig五模式/单线程消费与原生平台自校验，7项包含版本矩阵的fuzz测试，9个示例编译。独立single-threaded可执行文件验证真实JSON文件、字段选择/脱敏、reload、durable文件flush、关闭和初始化后无runtime分配。最新证据与源码SHA256在 `bench/evidence/2026-11-01-time/qualification.json`；此前483项数字/转义输出、480项记录校验、478项批内统计、474项配置View复用、469项CRC、468项路由过滤、462项schema编码、458项直接捕获、450项文件可靠性、433项编码等门禁保留于对应evidence目录。

默认无context logger直接捕获到最终描述数组，static struct/tuple按实际字段数预留栈空间、最大64；childcontext保留原merge。命名struct由编译期保证内部key唯一，旧prefix/动态key/nested仍校验，共同node预算和原错误优先级保留。新增6项公共capture回归与比较计数测试通过，45对固定session日志checksum/字节/counters精确匹配，相关Safe测试通过。5/10字段同步JSON窄范围中位成本下降约11%/21%，但真实SPSC异步对照仍inconclusive，详见capture.md。最终9目标ReleaseSafe对象编译及6项公共capture测试也通过。

文件可靠性本轮修复：普通轮转无隐式fsync/strictdurable；显式sync确认current和tracked retained archives，归档缺失报错；外部reopen未知目标目录撤销历史durable资格，但written继续。UnsupportedDurability不锁存为普通写故障，真实I/O错误继续锁存。旧配置零pending且requiredwritten完成后，额外durable不支持允许回收并撤销全局历史能力；InputOutput保留lease供重试。9项轮转可靠性/资源测试、6项实际部分写FileSink测试及2项collection测试已通过。

带种子SIGKILL campaign默认10例及高u64种子8例全部通过，覆盖16槽的4–7次环回、两次配置切换、跨代pending、普通/schema载荷、nested/source/secret与CRC；重复inspection保持journal/output哈希。随机化的是负载与epoch边界，在确切READY点杀进程，不宣称任意时刻故障或物理断电资格。详见file-reliability.md。最终9目标ReleaseSafe对象编译和6项实际文件故障测试也通过。

公开codec校验与长度统计合并为同一ValueValidator遍历；归档在完整安全codec调用内一次准备、两次必要hash/output写入，不导出unchecked写入或可保存凭证。测试计数确认size/encode/stream及archive准备每节点仅验证一次；所有tags、共享预算、无效树零输出和长度溢出后的校验优先级通过。相关37项ReleaseSafe与当前/旧版wire测试通过；冻结before模块及600行交替对照的checksum/字节数/shape完全一致。性能波动仍标inconclusive，详见encoding.md。最终9目标ReleaseSafe对象编译及编码基准输入测试也通过。

全局采样every1省略RMW，every2使用有界0/1原子翻转，其他采样策略和公开布局不变；当前x86_64每次every2生成单条lock btc。精确预算测试核对全局数目与最终相位，新增配置事务测试锁定filter-only保留与full replacement重置。采样微基准before/final各105次全部预算通过，但波动使稳定性能资格仍inconclusive，见sampling.md。

主benchmark已支持memory/mmap共享与SPSC、schema、durable file，报告区分queue/mapped字节与恢复能力。新增五项有界可执行检查、CSV/失败报告均通过；两storage各10次主程序捕获分别确认200,000 written、pending/drop0，资源预算严格验证。独立采样成本不等同完整日志吞吐，双存储不作为等价语义优化排名。 最新9目标公共对象编译和相关9项ReleaseSafe测试也通过。

普通异步 `memory_queue` 和mmap `journal`均支持共享/SPSC、schema预注册、热配置、采样、脱敏和同样确认API。7项外部测试包括无文件I/O trap、满队列/关闭、source深拷贝、失败durable回收保持状态、不可durable策略替换不接管lease。真实SIGKILL确认memory丢失pending而mmap恢复3条，prior written输出两者都完整。双模式性能capture各10次确认100,000 written/pending0/分配0，因可靠性不同不作为等价优化排名。 最新9目标公共对象编译和相关10项ReleaseSafe测试也通过。

默认空redaction路径移除约40KiB scratch，非空规则在独立栈函数处理；slot CRC使用自有IEEE实现，native x86_64可选PCLMUL folding，其他目标保持portable slice-by-16，保留校验和所有格式参数。模块oracle、独立slot golden、Vort416项互操作和3项redaction路径测试均通过。[热点报告](performance-hotspots.md)记录此前66次等价配置试验和本轮CRC比较；中位数据改善但尾延迟/噪声使总体inconclusive，未宣称稳定胜出。

完整配置来源事务和有界JSON文件已接入。7项外部事务测试覆盖优先级、策略共同发布、filter-only不占route槽/不重置sampling、失败lease责任、SPSC channel重用、嵌套guard和实际文件。根模块另有两项确定性publication交错测试和warmed SPSC共享RMW计数测试。来源模块5项、Document6项实质测试及OOM扫描也通过Debug/ReleaseSafe定向验证。Runtime filter已隐藏为opaque handle，外部只能通过统一writer API更新，新增负向编译验证无法绕过。

网络删除后，保留的四种格式为text/json/logfmt/binary，原有格式编号不变。trace/span仅用于本地事件关联。TSC真实资格测试区分墙钟与单调时钟，并验证噪声导致校准失败时维持未资格状态并回退到原生时钟；不会要求墙钟永不回拨或忽略校准错误。

| 范围 | 必须完成的证据 | 当前状态 |
| --- | --- | --- |
| 构建与公开模块 | Zig 0.16 Debug/ReleaseSafe/ReleaseFast，示例导入 | Debug/ReleaseSafe 综合验证通过；ReleaseFast 综合门禁通过，最后关闭发布修正的定向 ReleaseFast 验证通过 |
| Zig 包消费 | 独立 b.dependency 导入、源码分发完整性、线程配置传播 | ReleaseSafe 五模式、单线程消费及本地 fetch 源码包运行通过；Windows 独立应用 PE 链接通过，见 package.md |
| Typed fields/encoder | 字段边界、UTF-8、JSON解析、secret、格式校验 | 已实现并通过模块/负向编译测试 |
| 同步管线/context | 多 route、借用/深拷贝、错误反馈、无分配 | 已实现并通过 runtime 与 allocator 测试 |
| 动态配置 | scope边界、并发reload、环境优先级、旧事件决策 | 完整typed sources与有界JSON文件事务、generation-bound filter-only reload、旧admission guard、SPSC缓存无共享RMW已实现并有定向测试 |
| mmap journal | file-backed、提交/环回/校验、reserve缺口恢复 | 已实现；v1/v2固定slot、CRC、generation、恢复水位、schema同步发布已测 |
| 进程崩溃恢复 | 真实SIGKILL、跨进程独立读取、重复标识 | reserved/committed/gap 三种实际杀进程门禁通过 |
| 异步生命周期 | block/drop、flush/barrier、shutdown竞争、失败sink | 共享/per-channel gate、flush cut、关闭发布与最终唤醒已测；deadline正式ReleaseSafe门禁11/11通过，控制槽超时/重试/错误锁存均覆盖 |
| Durable协议 | 输出/checkpoint顺序、能力错误、系统故障测试 | fsync/双checkpoint已测；真实子QEMU强杀后ACK1/3均恢复且原镜像不变；物理断电/随机大规模资格仍未完成 |
| Low latency/SPSC | attach/detach、generation、独立队列、预热 | owner-only配置缓存与每channel版本pins已接入；回调TLS查找/释放资格、detach和旧版本保留均有测试 |
| io_uring | 能力probe、批量写、CQE/短写/在途所有权、对照基准 | 本机真实写/fsync/错误回收通过；保留对照证据 |
| 轮转与多sink | size/retention/reopen、故障与确认边界 | size/time/retention/reopen已测；路由快照、旧记录pins、lease热替换与恢复10项外部测试通过；配置表示已隐藏为opaque handle |
| 采样与脱敏 | fakeclock、并发计数、secret不入journal | count/every/tokenbucket、redaction、secret擦除已测 |
| std.log/trace | 根模块bridge、生命周期、TraceContext/Span | bridge/trace/span用于本地关联，网络输出已删除 |
| 工具与归档 | kroncat follow/level/where/json/recover、坏尾部 | schema/nested/legacy读取、标准zlib压缩归档与23项只读query/follow测试通过；无旧binary依赖 |
| 性能 | producer分位数、drain吞吐、饱和/冷缓存、资源预算 | 调度、真实C++ 60/60对照和资源基准已完成；prepared schema 64/64实测完成并保存；旧初始化超时保留证据，进一步性能优化继续 |
| 平台 | Windows/Linux/macOS/Android/iOS文件、映射、线程、时钟路径与能力边界 | Linux/Windows/Darwin映射后端已实现；9目标实际公共路径ReleaseSafe对象编译通过；Linux运行验证，其他平台设备运行待完成，详见platforms.md |
| 单线程同步 | 无后台线程、真实文件输出、过滤/脱敏、flush/shutdown、能力错误 | 独立single-threaded可执行文件Debug/ReleaseSafe通过；Linux任务数为1，禁止初始化后分配；普通durable文件flush有效，timed/async有明确能力错误 |
| 本地复用 | 可用API、格式兼容性、依赖与实际证据 | Vort实际源码416组CRC互操作与ZKV模型3120+8 checkpoint场景ReleaseSafe通过；slot CRC自有IEEE实现，native x86_64可选PCLMUL、其他目标portable slice-by-16，未引入Vort依赖；详见local-reuse.md |

## 完整目标的剩余验收项

当前门禁证明已实现能力，不能替代下面尚缺的范围。按整体设计继续推进：

| 要求 | 已有证据 | 仍缺的权威证据/实现 |
| --- | --- | --- |
| 可靠性边界 | 固定边界与随机运行期真实应用SIGKILL、子QEMU停机、双checkpoint与fault sink | 更大随机系统停机campaign、不同filesystem/设备、物理掉电资格 |
| 低延迟性能 | 分离时钟microbenchmark、prepared 64rows、C++ 60trials | TSC硬件/校准/跨核资格已验证；仍需独占/固定affinity稳定回归门限及业务负载覆盖 |
| 动态策略 | scope/level缓存、route/redaction/sampler资源快照热替换、旧事件保留；8种子byte regex差分与固定mutation campaign | 字段谓词与有界NFA正则、完整来源事务与有界JSON文件已实现；仍需持续sanitizer fuzz、业务正则性能资格与非默认采样热点优化 |
| 结构化扩展 | 显式group/array、8层/256节点预算、递归脱敏、nullable/source/trace；受限对象适配器5项外部测试及9项负向编译 | 更广nested故障与性能资格 |
| 文件与归档 | size/time轮转、retention/reopen、自包含与标准DEFLATE归档 | 更全面持久化格式升级矩阵、随机/更多文件系统故障门禁 |
| 生态与平台 | std.log、JSON、Windows/aarch64编译、真实单线程同步文件日志 | Windows/macOS/Android/iOS实际运行与journal资格 |

API已明确哪些能力属于可选增强；后续验收应逐项给出源码、运行结果或明确的平台能力边界。本轮以用户更新后的单机范围推进；更大硬件故障和跨平台资格仍按实测报告。

## 已有运行证据

- `zig build verify -Doptimize=ReleaseSafe -j2 --summary all` 在当前开发阶段通过 189 项测试（包含 160 个库测试、11 个 runtime integration、10 个 query、8 个 benchmark helpers），并执行六个 compile-fail fixture 和三个真实 SIGKILL phase。此后 ReleaseFast 综合门禁通过 194 项测试；最后关闭发布顺序及静态时钟入口修正的相关 ReleaseFast 测试 10/10 通过。后续源码修改必须重新运行相关 gate；此记录不是对未来 HEAD 的保证。
- `tests/crash_recovery.py` 通过新进程 `kroncat` 验证：未提交记录不输出、提交后的源缓冲覆盖不影响事件、reservation 缺口后的完整提交仍可恢复、两次 inspection 不修改 journal。
- `bench/evidence/2026-10-31-file-backends/` 保存相同输入 portable/io_uring 的原始 JSON、汇总和机器信息；不是跨语言排名。
- `bench-dispatch` 将时钟间接调用成本与 journal/encoder/I/O 分开，std_io/native/none 是显式不同 provider，不将 native 或取消时间戳的结果冒充等价语义收益。
- `zig build test-deadline -Doptimize=ReleaseSafe -j1 --summary all` 当前通过11/11外部测试；`src/core/control.zig`的3个独立ReleaseSafe测试通过。`test-fuzz`的三个有界mutation/arbitrary-input/format corpus在Debug通过，不能等同长期fuzz资格。
- `tests/power_loss/evidence/2026-10-31/` 保存两次真实QEMU停机后的文件/journal确认报告。主机没有被重启、断电或挂载测试盘；验证boot写入临时overlay。`test-fuzz`随后ReleaseSafe 3/3也通过。
- 本轮后续 `verify -Doptimize=ReleaseSafe -j2` 已通过280项测试、全部五种SIGKILL阶段与六个compile-fail fixture；覆盖deadline、v2schema、Reader、legacy codec及prepared binding防错标。重新构建的当前v3/v2测试writer再次通过QEMU ACK3后停机恢复，紧凑证据已保存。后续benchmark源码变化仍需要自身门禁。
- 当前 `verify -Doptimize=ReleaseFast -j2` 重跑通过280/280；期间修正了脱敏测试对整条JSON秘密数字搜索的误判，现在解析attributes.token并检查optional实际值。Windows公开模块ReleaseSafe编译通过。该门禁不代表尚未实现的增强能力已完成。
- 本轮 `verify -Doptimize=ReleaseSafe -j2` 已通过358/358测试（包括280库、9配置、10压缩、23query），六个真实SIGKILL阶段与原负向编译也通过。随后opaque配置表示和并发SPSC替换增强的定向Debug/ReleaseFast配置测试10/10通过，新增负向编译确认公共typedAPI不能直接修改Snapshot；当前v4/v5 writer再次通过QEMU ACK3恢复。
- 当前 `verify -Doptimize=ReleaseFast -j2` 全量通过359/359、七个compile-fail fixture、六种SIGKILL阶段与四个示例编译；`run-hot-configuration` ReleaseSafe实际运行并由kroncat解码压缩归档。最后增加的SPSC并发热替换测试覆盖2000accepted==written。ReleaseSafe完整计数358是新增该测试之前的证据，其10项配置定向ReleaseFast门禁与全量当前ReleaseFast已覆盖。

## 继续完成的要求

deadline、子VM故障注入、schema预注册、嵌套字段、资源热替换、标准压缩归档和实际C++对照已实现并有门禁；TSC资格、字段谓词/NFA、配置缓存热点优化及多种子任意字节正则差分/有界mutation已实现；更大随机故障资格、稳定回归基线、持续sanitizer fuzz与更多平台实际运行仍需继续推进。

代码实现继续推进完整目标。本清单用于明确缺口，不用于缩小设计范围或提前宣告完成。

## 当前性能验证的限制

最新完整 benchmark 有界验证在第十一项 SPSC sleep 配置初始化阶段超时；现场只有主线程，等待内核文件页，没有启动 producer/worker。不能把该次未完成验证记为通过，也不能将原因断言为日志死锁或 std.Io 调度成本。失败报告与二进制身份见 [超时证据](../bench/evidence/2026-10-31-clock-dispatch/spsc-sleep-timeout.md)。代码级最终 admission 唤醒与关闭发布分别有定向测试，初始化 I/O 尾延迟仍需进一步验证。

## 配置缓存与快速时钟证据

ReleaseSafe综合门禁388/388通过，谓词/缓存外部测试随后5/5通过；channel pins/cache模块Debug/Safe/Fast27项、TSC真实资格3项及错平台编译通过。by-reference修改移除了routeMaskIn的0x5840字节memcpy；单次P4 admission shared484ns/attached157ns，完整JSON吞吐587K/617K，命令/binary/profile证据见bench/evidence/2026-10-31-snapshot-by-reference。TSC全部100000read资格成立且fallback0，但当前安全实现34.52ns/call慢于NativeClock18.35ns，未声称TSC提升性能。

## 本轮补充资格验证

有界QEMU campaign的4个独立停机边界ACK17/31/8/3全部恢复，17与31覆盖16-slot环回，证据位于tests/power_loss/evidence/2026-10-31-campaign。正则差分门禁与Pythonre.search完成4096项exact比较，Debug/ReleaseSafe通过，故意错误expect的负向driver也确认非零失败。TSC的TLScalibration cache在保持资格和generation/实例cookie检查后实测22.88ns/call，Native15.33ns；当前不宣称TSC更快。

此前 `verify -Doptimize=ReleaseFast -j2` 通过398/398（309库、6谓词/缓存外部、3真实TSC资格及其余集成/工具/基准），六种SIGKILL、七个compile-fail及4096项正则差分全部通过，六个示例编译。配置职责拆到runtime_configuration.zig，owner实例时钟接口及跨Runtime线程本地resource查找/公开释放资格均有验证。当前计数以本文件开头的单机门禁为准。
