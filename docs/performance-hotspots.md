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

## 2026-11-01批次合并后的schema融合

基线`366adc3`的六组百万条完整JSON profile核对600.6万条物理记录，SPSC Memory inline的consumer约占52%用户态core周期采样；prepared SPSC Memory仍有约11%含子调用的decodeRecord和约15%自占的memcpy采样，后者也含producer复制。shared Memory的begin另有显著采样。profile包含setup/preparation/cleanup、排除kernel，不能从这些比例直接计算吞吐或归因某个锁。

当前schema消费者在至少64条已就绪记录的窗口、单JSON/text/logfmt目标、无deferred/args时直接从canonical定义和值渲染，省去top-level Field数组物化与属性二次遍历。短窗口、模板参数、多route和binary继续materialized resolve，同一记录复用canonical查找；类型mask、nested节点/深度/arena、长度、schema身份及原错误优先级保持。输出scratch不足的冷错误路径先完成原reference.resolve，避免后段损坏被记录过大错误掩盖；全部渲染成功后才调用sink。每条CRC、旧配置pin、输出barrier和checked reclaim保持。

三格式all-tags/source/trace/static/dynamic/nested/readable-time与历史v2对照、4096变异/all truncation/scratch guards通过。真实runtime的Memory/Mmap×shared/SPSC×1/64条窗口×16/512字节output×三种schema损坏共48场景确认零sink输出、原错误与所有pending/pin；相关Debug/Safe/Fast各26/26测试通过。完整最终240项文件核对2424万条JSON，prepared Memory P4共享/SPSC吞吐中位提升6.35%/8.03%，CV/spread通过且中位区间不重叠；Mmap多数组与多数尾分位未资格。最终40项完整PMU核对1204万条记录，schema SPSC Memory/Mmap指令减少1.804%/1.802%、shared Memory减少1.906%，两侧spread均小于0.14%；inline control指令增加0.171%。另20项百万条P1核对2002万条，最终Memory/Mmap负向中位0.65%/1.39%、区间重叠，不能声称P1整体改善。

native drainJournal显式栈帧预留37800→40712字节，增加2912字节；不含push/callee/递归总栈。不增加heap/journal/file预算。初始全窗口schema融合的P1负向、被否决header指针版和187项中断捕获均独立保存；完整源码、脚本、机器与资格限制见`bench/evidence/2026-11-01-consumer-post-coalescing/`。当前数据不提供新的Foundation或io_uring排名。
