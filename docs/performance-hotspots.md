# 默认脱敏与journal CRC热点

后续完整百万条文件流程profile发现数字临时数组到Writer的小memcpy；native decimal已在buffer剩余21字节时直接生成，并保留短写/流式fallback。100个完整before/after试验逐条验证1010万条，五组中位吞吐提升3.0%–4.0%；只有SPSC Memory P4中位区间不重叠。额外长流程user PMU该组cycles下降约5%、instructions增加约1%，候选慢值使其长流程吞吐仍inconclusive。源码与字节/物理失败前缀、探索负向和完整限制见[数字输出](decimal-output.md)及`bench/evidence/2026-11-01-decimal-direct/`。mmap初始化独立trace保留每份journal的msync/file/dir fsync发布，单个慢样本主要等待这些系统调用，不以降低发布协议换取启动排名。

本轮使用公共SPSC logger和完整JSON交付，保持5个数字字段、ZeroClock、256槽journal、sleep worker及written确认。每次10,000条测量事件、1,000条预热；原始报告与源码/binary SHA256在 `bench/evidence/2026-10-31-redaction-crc/`。

默认无redaction规则时，旧实现仍复制fields/arguments并清空四个scratch数组。136个CPU样本中约36%落在 `redact.clearScratch`。新实现先执行完整ValueValidator，规则数为零时直接交给相同编码/提交函数；有规则时进入独立noinline函数，scratch只在调用期间存在。Secret强制替换、节点/深度/cycle/重复key校验、原输入不变和接受前深拷贝均保留。ReleaseFast反汇编中，`submitDestination`栈从 `0xa858` 降到 `0x378`。

移除scratch后，70个样本的profile中约37%落在journal slot CRC，包含commit、consumer peek和release。新增自有纯Zig IEEE CRC32 slice-by-8，仅替换v1/v2 slot计算，不删校验。20字节头、v2的24字节schema引用、多项式与final XOR保持一致，其他header/checkpoint/archive CRC不变。2项模块测试验证496组长度/对齐、1,984种分段更新、256种单字节及golden vectors；Vort实际源码416项互操作也重新通过，无外部运行时依赖。

下列是5次P4完整输出的中位数，当前不能作为稳定保证：

| 实现 | records/s | p50 | p99 |
| --- | ---: | ---: | ---: |
| 修改前 | 521,065 | 6,518ns | 8,515ns |
| 仅移出默认scratch | 581,665 | 941ns | 44,017ns |
| 加上slice-by-8 slot CRC | 988,457 | 722ns | 21,832ns |

更快的producer更容易遇到固定槽数的backpressure，尾延迟依赖后台调度；仅scratch的p99升高，不能用p50下降声称整体胜出。

第二组选择6个物理核的单logical CPU（0,2,4,6,8,10），每配置9次。P1中位吞吐178,278→797,863，P4为423,891→980,182；波动仍超过10%阈值。两组比较均为 **inconclusive**，不通过稳定性能门禁。两组affinity不同，只能各自内部比较。

全部66个试验完成；51个完整输出试验共510,000条accepted=written，pending/drop和测量期Runtime分配均为零，另15个admission-only试验无输出。小规模perf包含初始化，不能等同稳定热点占比。host governor与kernel符号策略没有修改。

工作量减少和行为兼容已有证据；独占稳定环境、业务输入、饱和队列及尾延迟对照仍需继续，当前不宣称业界最快或稳定整体提升。

## 2026-11-01完整流程profile与CRC更新

在当前完整JSON文件工作流中再次profile，P4 SPSC-memory、100万条事件、相同系统时钟与written/关闭终点。约24%的before采样落在journal CRC，其中producer提交约9%、consumer peek/reclaim合计约15%。两次profile各约1K samples，after的CRC update自占比约20%；内联边界与整体工作量不同，不能把profile占比差直接当性能提升。

同一CRC实现改用16-byte slicing后，标准IEEE协议、校验点和范围保持不变，只读表由8KiB增至16KiB。五对固定CPU的独立CRC混合过程PMU统计中，用户态周期减少24.4%，指令数增加4.3%。这证明本机primitive cycle成本降低，不证明端到端吞吐更快。完整before/after工作流实际为120个试验、1212万条验证记录，另10个100万条长批次、1001万条记录；全部日志完整，吞吐/尾延迟仍因host噪声标inconclusive，原慢值保留。

准确计数、原始profile、hardware计数器、微基准和完整流程在 `bench/evidence/2026-11-01-crc-slicing16/`。从Quill、Foundation等优秀库学到的连续批次、批量确认、静态metadata和模板缓存，将按 [业界实现与优化方向](industry-performance-lessons.md) 继续落实；不是用弱化CRC或删输出字段换取排名。

## 2026-11-01 PCLMUL IEEE CRC

完整JSON流程profile再次把journal CRC放在约四分之一用户态采样中，包含producer commit、consumer checked peek和release三个必要校验点。本轮只替换block循环：编译目标为x86_64且声明PCLMUL+SSE2时，使用4-lane 64-byte folding、128→64→32 reduction和Barrett步骤；通用x86_64、非x86目标、短输入和<16字节尾部仍使用原16-byte slicing表。多项式0xEDB88320、reflection、final XOR、全部校验点、schema引用范围和journal/恢复格式不变；不做运行时CPU探测、不分配、不增加外部依赖。

CRC模块差分测试覆盖标准向量、64种对齐×36种长度、32种对齐×22种长度×14种增量切分，并与`std.hash.Crc32`逐项比较；本机`-mcpu=baseline`重新验证portable fallback，aarch64编译通过，journal v1/v2 golden不变，Vort实际源码416组互操作通过并报告`backend=hardware`。完整ReleaseFast门禁为81/81步骤、503/503测试；首次运行的crash writer在宿主I/O压力下10秒未READY，单独重跑`test-crash`通过，完整门禁复跑也通过。

journal形状CRC primitive（20字节头、可选24字节schema引用、payload）在本机固定CPU下中位：

| payload | before ns/record | after ns/record | 变化 |
| --- | ---: | ---: | ---: |
| 64 B | 24.56 | 13.83 | −43.7% |
| 256 B | 95.23 | 18.98 | −80.1% |
| 512 B | 199.96 | 26.34 | −86.8% |
| 2 KiB | 785.42 | 79.56 | −89.9% |
| 16 KiB | 6312.29 | 535.23 | −91.5% |

五对固定CPU完整流程PMU中，SPSC-memory P4用户态指令中位1,419,594,438→1,202,017,414（−15.33%），async-memory P1 1,279,222,652→1,090,074,869（−14.78%），两侧spread均低于1.2%，为稳定局部测量。SPSC-memory P4完整吞吐中位1.393M→1.816M条/s（+30.3%）并达到本轮CV/spread门限；async-memory P1为1.483M→1.913M（+28.9%），但区间仍重叠。100个交替完整文件试验逐条核对1010万条JSON，全部accepted=written、pending/drop=0；宿主load约110，五组吞吐中位提升15%–84%但全部标inconclusive，不能当作稳定端到端保证。

这是原生x86_64的编译期路径；通用/非x86目标继续使用portable表，不获得该加速。归档Foundation/Quill数字来自不同源码快照和host窗口，本轮没有同轮跨库复测，因此不能据此宣布新的跨库排名。原始数据、源码/二进制身份和复现脚本见 `bench/evidence/2026-11-01-pclmul-crc/`。

## 2026-11-01 decoded delivery 校验复用

PCLMUL CRC之后，完整JSON profile的主要剩余成本转向consumer decode与输出格式化；encoder还会对decoder已经验证过的同一棵树再执行一次完整`ValueValidator`遍历。本轮只对checked decoder证明的事件跳过第二次树校验：`codec.decode`/`schema_codec.resolve`完成wire树、节点预算、深度、重复key和长度检查后设置内部`Event.tree_validated`；内部`encoder.common.encodeDecoded`据此选择已验证renderer，否则仍走公开校验路径。

公开`encoder.encode/encodeWithTime`始终校验并忽略该提示；runtime在admission阶段先执行`codec.measure`或redaction/binding校验，再由`submitSafeDestination`用可信上下文覆盖调用方提供的提示；binary route继续使用公开校验。没有导出unchecked writer或可复用的公开凭证。新增测试锁定伪造提示的cyclic tree仍被公开encoder拒绝且零输出、`runtime.submit`的重复key仍返回`DuplicateKey`、decoded text/JSON/logfmt与公开encoder字节一致。

五对固定CPU完整流程PMU中，SPSC-memory P4用户态指令中位1,192,405,654→1,147,913,047（−3.73%），async-memory P1 1,088,324,949→1,039,471,174（−4.49%），两侧spread 0.5%–1.6%，为稳定局部测量；cycles/task-clock仍因host负载标inconclusive。100个完整文件试验在52个、525万条记录后遇到mmap子进程120秒超时，已完成试验全部accepted=written、pending/drop=0，但不作为吞吐资格。`zig build test -Doptimize=ReleaseFast`通过35/35步骤、481/481测试，完整`verify-local`通过81/81步骤、505/505测试。证据见 `bench/evidence/2026-11-01-decoded-delivery/`。

另测schema Record借用Definition指针以避免consumer第二次ready lookup：完整test 35/35、481/481通过，但固定CPU PMU的SPSC-memory P4与async-memory P1用户态指令分别+0.68%/+1.38%，没有减少工作量，已回退到decoded-delivery的81/81、505/505源码状态。负向数据保留在 `bench/evidence/2026-11-01-schema-record-pointer/`，不再作为后续候选。

readHeader前缀复用候选同样被否决：codec/schema定向测试通过，但完整流程指令变化+0.40%/−0.07%，在噪声内且没有可测收益，已回退到同一已验证源码状态；原始PMU与二进制保留在 `bench/evidence/2026-11-01-codec-header-reuse/`。

## 2026-11-01 fused wire-to-JSON consumer path

CRC与decoded-delivery之后，consumer剩余成本主要是`decodeRecord`的Event/Field物化与随后JSON树的第二次遍历。本轮为常见形状增加融合路径：当前自包含v4 payload、恰好一个JSON/text/logfmt route、非deferred message、无format args；attributes可为scalar或nested，nested descriptor使用caller scratch arena。融合renderer只解析一次header/scope/message/trace/source/attributes，并在caller scratch中写出与公开encoder相同的JSON/text/logfmt记录；每个value tag由checked wire parser验证，top-level key去重后才写入sink。corrupt payload返回原decoder错误，其他形状返回`error.Fallback`并走原decode+encode路径；journal格式、公开encoder、校验边界和route语义不变。

单元测试用flat event（覆盖unsigned/signed/string/bool/float/duration/timestamp/null、trace/span/source）和nested group/array逐字节比较融合输出与`decode + encodeWithTime(.json)`；deferred message确认Fallback。完整`verify-local`通过81/81步骤、510/510测试（含nested与text/logfmt fused验证）；10,000条SPSC-memory完整文件workflow的11,000条物理记录通过独立oracle。五对固定CPU完整流程PMU中，SPSC-memory P4用户态指令中位1,154,112,566→1,085,502,232（−5.94%），async-memory P1 1,040,240,533→975,795,731（−6.20%），两侧spread 0.8%–1.2%，为稳定局部测量；cycles/吞吐仍inconclusive。100个完整文件试验结果保存在`bench/evidence/2026-11-01-wire-json/`，用于输出与吞吐核对，但不改变跨库排名。

该路径刻意收窄：legacy payload、schema reference、template/args、多route和binary继续走原路径；nested attributes已支持；公开encoder仍独立校验，融合路径只在完整记录验证成功后写入scratch。

## 2026-11-02 checked wire typed visitor与内联scalar渲染

基线`5b72254`的shared Memory/Mmap P1/P4完整profile核对400.4万条JSON，`wire.render`自占约11.1%/5.0%，`WireInput.value`约3.4%/1.5%，`valueInner`约2.8%/1.5%；样本约1K、零lost，profile包含初始化/清理并排除kernel，不能把采样比例换算成精确周期或吞吐。

`WireInput.valueWith(receiver)`沿用同一tag、长度、节点、深度、nested、重复key与arena预算检查，成功后以comptime tag和typed payload调用`receiver.accept`；公开`value()`用内部Materializer构造原`Value`，外部API与错误集合不变。array/group仍完整解析后才交给callback，不允许callback观察部分验证的aggregate。融合JSON/text/logfmt的`ValueWriter`按tag编译scalar写出，跳过中间`Value`物化和通用二次分派；schema kind mask在payload完整验证后检查，malformed/truncated优先级和“只有完整scratch记录才交给sink”保持不变。公开value/event仍完整校验借用树，没有导出unchecked writer、复用凭证或删除CRC。

独立before/after模块差分对flat all-scalar/UTF8/bytes/extrema、nested与最大256-node fixture执行17527次比较；9769个valid mutation在JSON/text/logfmt中逐字节一致，原decoder和原fused renderer各自作为独立oracle。新增测试确认damaged bool、截断整数、节点预算和重复group在callback前失败且调用次数为零，合法complete group只调用一次。Root Debug 20/20、Safe 59/59、最终Fast 60/60通过；ReleaseSafe完整门禁151/151步骤、640/641项通过（1项系统local能力skip），包含源码分发、九目标对象、真实SIGKILL和示例。

最初typed writer生成多个独立调用，40项完整PMU指令中位只减少约0.15%，没有cycle/速度资格，源码和原始数据保留在`outlined-writers/`。改为comptime-tag内联后，40项完整shared真实文件核对1204万条JSON，用户态instruction中位：Memory P1/P4 −1.686%/−1.664%，Mmap P1/P4 −1.652%/−1.656%；四组CV/spread达标且中位95%区间不重叠。cycles与该PMU窗口的written速度仍区间重叠，不能作为一般throughput/latency收益。80项未插桩workflow核对2408万条JSON，八组吞吐正负混合；20项P4 sampled复测核对602万条JSON，Memory −0.12%、Mmap +2.85%，后者仍inconclusive。`valueInner` code size约0x641→0xfbc属于被测候选取舍，不假定inlining一定更快。

保留依据是完整校验/错误优先级/独立差分/完整门禁兼容，以及四组完整shared指令稳定减少；不据此更新Foundation/tracing排名。源码、二进制、全部CSV/慢值、被否决版本和复现脚本见`bench/evidence/2026-11-02-wire-scalar-render/`。

## 2026-11-02 JSON固定metadata直接tag写入

typed visitor之后，JSON metadata仍通过`valueInner(writer, .{ .unsigned = event.session }, .json)`等临时union写出timestamp、session、sequence、route_mask、config_generation。该路径把`u64`装进`Value.unsigned: u128`，再经过运行时tag switch和宽整数decimal；每条JSON记录多出五次通用分派与u128实例。

候选改为直接调用内部`writeTaggedValue`，以comptime tag和原始`i64`/`u64` payload写出这五个字段。JSON精度、quote、decimal、转义、公开API、wire协议和错误边界不变；text/logfmt metadata原本已经直接`decimal.write`，源码未改。没有新增分配、依赖或每emit工作，公开value/event仍完整校验。

普通encoder probe的30项交替PMU中，JSON instructions/cycles中位−2.58%/−1.93%，scalar5/nested20/wide5的ns/record分别−2.60%/−1.75%/−1.55%，五组CV/spread达标且中位区间不重叠；三种格式的完整输出checksum/bytes一致。text/logfmt控制组instruction基本持平，text cycles/单case出现+1.8%–+3.8%、logfmt cycles −1.79%的方向差异；由于这两个路径源码未改，只作为binary layout/测量窗口的控制组保留，不宣称改善或退化。

40项完整shared真实文件核对1204万JSON，用户态instruction中位：Memory P1/P4 −2.445%/−2.463%，Mmap P1/P4 −2.460%/−2.479%；四组CV/spread达标且中位区间不重叠。cycles全部区间重叠；同窗口written为Memory P1 +1.42%（重叠）、Memory P4 +4.13%（不重叠）、Mmap P1 −1.06%（重叠）、Mmap P4 +3.48%（不重叠）。80项未插桩workflow核对2408万JSON，八组written吞吐全为正（+0.95%–+5.55%），六组达到本轮噪声门限，Memory/Mmap P4 batch中位区间不重叠；sampled p50基本持平，p99/p999多数降低但仍有区间重叠，不能承诺一般尾延迟。

采纳依据是JSON probe与四组完整shared指令稳定减少、八组未插桩吞吐全为正且六组稳定，同时输出字节、错误顺序、公开API和全部门禁不变。text/logfmt控制组、cycles和尾部波动全部保留；不更新Foundation/spdlog/tracing排名，也不叠加历史百分比。源码、二进制、原始CSV/row、慢值与复现脚本见`bench/evidence/2026-11-02-wire-metadata-direct/`。

## 2026-11-02 JSON severity固定字面量

JSON encoder此前每条记录写`,"severity":`，再对`@tagName(event.level)`执行`quoted`。候选按Level枚举选择一个完整literal一次写出；`err`仍输出`"err"`，text/logfmt不变。30项encoder probe的JSON instructions中位−2.05%，text/logfmt控制组instruction持平；40项完整shared核对1204万JSON，Memory/Mmap P1/P4指令中位减少1.68%–1.70%，四组CV/spread达标且区间不重叠。80项workflow吞吐正负混合（Memory P1 batch +6.35%、P4 sampled −5.91%、Mmap P1 batch −1.37%等），不作为一般吞吐收益。源码与全部正负数据见`bench/evidence/2026-11-02-json-severity-literal/`。

## 2026-11-02 Memory journal单次清零初始化

Memory journal此前经历三次清零：`Storage.createMemory`完整`@memset`、逐4096字节volatile写0、随后`format.initialize`/`initializeV2`再次完整`@memset`。候选删除逐页循环，memory backing保留唯一一次完整writable清零，并新增`initializeZeroed`/`initializeV2Zeroed`只写header、identity、CRC和checkpoint；file/mmap继续使用完整清零入口，避免复用映射中的旧字节被当成有效slot payload。

`init_probe.py`用async Memory、file sink、256槽、`max-record-bytes=65536`（约16.8MB journal），5对交替before/after。batch runtime init中位9.130ms→6.638ms（5/5配对下降，比值0.565–0.739），bootstrap中位区间不重叠；sampled中位10.793ms→6.992ms，4/5下降但区间仍重叠。512B小队列（约147KB）省去的清零工作低于宿主噪声，5对方向混合、区间全部重叠，不能据此宣称回归或收益。file/mmap初始化路径和全部CRC/slot/recovery协议不变；ReleaseSafe完整门禁151/151步骤、641/642项通过（1项系统local能力skip）。

该优化只证明memory journal初始化局部成本下降，不代表producer/consumer吞吐、Mmap启动或跨库排名。原始20项/phase、全部命令/stdout/stderr与source/binary身份见`bench/evidence/2026-11-02-memory-init-zeroing/`。

## 2026-11-02 Fresh Linux mmap只写header初始化

Fresh mmap此前对整段映射执行`@memset`，并在`Mapping.open`逐页写同一字节，导致所有页变脏，publication/fsync需要回写整个journal。Linux `map`已使用`MAP_POPULATE`；fresh file在`setLength`+`fallocate`后由ext4/XFS/btrfs/F2FS等文件系统提供读为零的unwritten extents。候选让这些文件系统只写header/identity/CRC/checkpoint，未知文件系统继续完整清零；Windows/Darwin保留prefault但改为volatile read，不无谓dirty页，freshZeroed返回false。

ext4 zero探针对16MiB新文件与写入4KiB后truncate到0再扩展的文件读取全部bytes，两者均0个非零字节。`mmap_init_probe.py`用async Mmap、file sink、256槽、64KiB record（约16.8MB journal）5对交替：sampled init 54.212ms→8.227ms（0.152），batch 53.809ms→6.948ms（0.129）；5/5配对下降，中位区间不重叠。512B小队列中位0.945/0.961，区间重叠，差异低于噪声。该结果只证明fresh mmap初始化局部成本，不代表producer/consumer吞吐、Mmap稳态、durable或跨库排名；非Linux设备运行资格仍未取得。原始数据与复现见`bench/evidence/2026-11-02-mmap-fresh-zero-init/`。

## 2026-11-01批次合并后的schema融合

基线`366adc3`的六组百万条完整JSON profile核对600.6万条物理记录，SPSC Memory inline的consumer约占52%用户态core周期采样；prepared SPSC Memory仍有约11%含子调用的decodeRecord和约15%自占的memcpy采样，后者也含producer复制。shared Memory的begin另有显著采样。profile包含setup/preparation/cleanup、排除kernel，不能从这些比例直接计算吞吐或归因某个锁。

当前schema消费者在至少64条已就绪记录的窗口、单JSON/text/logfmt目标、无deferred/args时直接从canonical定义和值渲染，省去top-level Field数组物化与属性二次遍历。短窗口、模板参数、多route和binary继续materialized resolve，同一记录复用canonical查找；类型mask、nested节点/深度/arena、长度、schema身份及原错误优先级保持。输出scratch不足的冷错误路径先完成原reference.resolve，避免后段损坏被记录过大错误掩盖；全部渲染成功后才调用sink。每条CRC、旧配置pin、输出barrier和checked reclaim保持。

三格式all-tags/source/trace/static/dynamic/nested/readable-time与历史v2对照、4096变异/all truncation/scratch guards通过。真实runtime的Memory/Mmap×shared/SPSC×1/64条窗口×16/512字节output×三种schema损坏共48场景确认零sink输出、原错误与所有pending/pin；相关Debug/Safe/Fast各26/26测试通过。完整最终240项文件核对2424万条JSON，prepared Memory P4共享/SPSC吞吐中位提升6.35%/8.03%，CV/spread通过且中位区间不重叠；Mmap多数组与多数尾分位未资格。最终40项完整PMU核对1204万条记录，schema SPSC Memory/Mmap指令减少1.804%/1.802%、shared Memory减少1.906%，两侧spread均小于0.14%；inline control指令增加0.171%。另20项百万条P1核对2002万条，最终Memory/Mmap负向中位0.65%/1.39%、区间重叠，不能声称P1整体改善。

native drainJournal显式栈帧预留37800→40712字节，增加2912字节；不含push/callee/递归总栈。不增加heap/journal/file预算。初始全窗口schema融合的P1负向、被否决header指针版和187项中断捕获均独立保存；完整源码、脚本、机器与资格限制见`bench/evidence/2026-11-01-consumer-post-coalescing/`。当前数据不提供新的Foundation或io_uring排名。
