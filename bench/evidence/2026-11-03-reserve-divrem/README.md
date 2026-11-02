# Shared reserve 商/余数复用实验

当前为独立候选，完整目标仍为相同完整输出/完成边界下超越Foundation/logging+spdlog与+tracing。baseline HEAD4e35989；当前Journal源码在reserve同一成功attempt先position%capacity、claim后再(position+1-1)/capacity+1，实际native reference每成功预留执行两次DIV。原64/32bit宽度分派独立核对，profile比例仅作历史路由，不作当前精确占比。

候选仅在每次attempt保留position/captured capacity的quotient与remainder，successful claim用quotient+1写generation；失败CAS与tail更新后按新position重算。SequenceExhausted、turn acquire、tail CAS、occupied/peak、reserved marker、schema ready/error、commit/consumer独立generation重算、CRC及ABI不变。capacity从创建后不得通过此优化改值，完整u64域/非2幂budget保持。SPSC作为源码控制。

与并行开发的direct partial CRC分开冻结与测量：本目录owning variant只改journal.zig及必要tests，archive/bin应始终保持原production CRC。所有编译和测试结束后才启动full JSON measurements，baseline/候选身份、slots/bytes/systemclock/written/close/cleanup边界与正负/噪声完整保留。

先核对成功路径动态两次DIV→一次，以及quotient跨CAS的register/spill/newcall和32bit优化是否保持；静态减少不是速度承诺。正确性按容量1/2/3/7/256、多wrap、序号跨2^32/max_sequence、aborted/full/schema/recovery与独立payload/header oracle。最小检查后才升级完整日志门禁与Foundation同轮对照，不把历史profile10.67%全部归因于DIV。

## 源码、回归与actual gate

候选只在reserve attempt的SequenceExhausted之后捕获capacity，计算position/capacity+1与position%capacity，claim后直接写已保存generation。失败tailCAS/turnretry全部重新计算。capacity仅constructor赋值，无合法并发resize；generation保持u64，factory已有sizeOfusize8/little检查拒绝32bit。commit/consumer独立generation检查不改，不增加Reservation字段。

新增shared reserve coordinates回归使用quiescent Memory ring起点0、2^32-3、max_sequence-(3cap+5)，capacity1/2/3/7/256，每段3cap+5次预留。测试按slot独立递增generation，先查reserved header再commit+checked read或abort，并核验payload/written/pending、最后SequenceExhausted。没有逐record镜像production division。原baseline同suiteSafe与候选Debug/Safe/Fast均实际执行一项cases，总16项含15aggregate imports；相关journal选择77/77通过，包含并发wrap、schema、CRC故障、重开与durable控制。

隔离CRC-only/direct实验与reserve-only目录，measured divrem source保持原CRC。before baseline独立从HEAD编译，before2530b4c2b153775ae39d685f3318b77b2d09a53afc8fc1679f45417305b6fc19、candidate9de6e23c8056bac85cbb8dc67494244692dd4d28dd257dac8a585fc26a2f198c；源码/原始fixtures/archive/build命令/hash在provenance。

Actualreserve546→519B、126→114静态指令；每成功DIV2→1。64bitdiv r9和fit-u32的div r9d分派保持，RAX quotient存r10后跨tailCAS和occupied/peak，无新增spill、call或stackframe，原CASboolstack写入不变。reserved marker→sequence→generation顺序保持，Journal768B/所有offset相同。schema/SPSCreserve、slotChecksum、validateSlot、peekChecked、CRCupdate和submitSafeDestination正规化指令一致；loadedCRCconst/table bytes保持，三个检查不删。详情binary-review.json。

## 首测窗口

全部compile/tests结束后才串行测，标准publicmanagedLogging、Memory/Mmap、shared/SPSC、P1/P4、100k+1000warmup、batch/sampled、五typednumeric字段+fullmetadata/systemclock、256slot/512B、64KiBportablefile，writtenflush→shutdown→cleanup，无device durable。

Ecore16/18/20/22/24/26完整160项核对16,160,000物理JSON，sharedMmapP4sampled约1.0224局部writtenclose领先；其余shared组不确定。SPSCMemoryP1sampled控制约0.9970局部负向，原SPSC代码保持，需独立更长复测，不将此结果抹去。lifecycle16组全不确定，p99.9一组候选领先/其余不确定。

Ecore40项full-process PMU另核对4,040,000JSON，instructions配对速度比约1.00106/1.00096/1.00120/1.00134，三组计数资格、一组不确定；MemoryP1cycles局部领先，其余周期与全部PMU吞吐不确定。不由少DIV推断一般throughput，更不叠加到旧Foundationratio。

Pcore/schema窗口与针对SPSC控制的长复测尚待完成，当前只有候选资格，原始positive/negative/noisy与sourceidentity都保留，最终决定不得只挑优势组。

长SPSC控制10项核对10,010,000物理JSON，written-close约0.99198、writtenflush约0.99179与lifecycle约0.99123均不确定，首轮关闭吞吐负向未取得长流程重复资格。但p50长流程约0.95318达到基线局部领先：before中位281ns、after298ns，五轮candidate均较高；p99/p99.9不确定。不能因为SPSC源码未改而擦掉实际p50反例，正在只读核对完整SPSC热callee与binarylayout，shared长矩阵仍未结束。

18个SPSC/managed/clock/codec/CRC实际热符号的正规化指令、调用、栈访问与尺寸一致，没有新增SPSCspill或caller调度；入口统一提前32B，ThreadOwner.begin跨页边界、多个cacheline偏移改变。静态证据不能排除真实p50负向，也不能证明由layout引起，详见spsc-static-control.json。

最终：共530项对照逐条核验134,530,000物理JSON；shared百万条80项/80,080,000JSON的8组吞吐/lifecycle/p50/p99.9均不确定，不能将短MmapP4局部win推广。已有SPSC长p50负向与所有时点/布局/轻量准备重叠保留。因此singledivrem生产候选撤回，journal恢复4e35989，仅保留真实坐标回归；decision.json记录各矩阵/原始计数。后续pow2独立compare原baseline，不叠加本候选速度比。
