# Shared reserve 二次幂坐标实验

当前仅隔离副本准备，未compile/测试/benchmark。baseline原4e35989，不将先前divrem正负当新增速度基线。当前divrem长流程继续原冻结source/bin，不被此副本改变。

只改reserve rangeguard后的capacity坐标：capture非零capacity，mask=capacity-1，2幂时用position>>ctz(capacity)和position&mask；非2幂保留position/capacity与position%capacity同attempt复用。capacity1的shift0/mask0保持，position全u64、max_sequence加一安全；失败CAS/tail变化重新计算，marker/order/schema/commit/consumer独立generation/CRC/SPSC/预算保持，不增加Journal字段/API。

cap255/257/512增加邻界与较大移位回归。候选source只在.zig-cache隔离树，所有基线/候选identity与实际零DIV/单fallbackDIV、fit32/64选择、no spill/newcall、ctz/branch/PHI须验证。此前divrem的SPSC控制p50负向保留；新source不能从更少DIV推吞吐。所有当前performanceprocess退出后才编译新candidate，再独立测完整output，不并发CPUheavy。

正确性阶段：原baseline+扩展8cap坐标Safe通过，候选Debug/Safe/Fast实际一项坐标regression，各16total含15aggregate；related journalSafe77项通过。所有source/CRC/other候选隔离，allcompileended后冻结candidateprovenance和archive。

实际sharedreserve583B/128静态指令（original546B/126），二次幂用nativeBLSR/TZCNT/SHRX/AND零DIV，非pow64/fit-u32仅一条DIV；商跨CAS/peak无newcall/spill，tag/sequence/gen发布order保持。Journal768B/offset相同，所有CRC、SPSC/consumer/controller正规化同baseline。nativeBMI由编译target宣告，非新增asmfeature。queueprobe同机制，actual详见binary-review.json。

独立queue-onlycap1/2/3/7/255/256/257/512：before/after各五invocation×五batch×100000iterations，两拓扑共800rawbatch，全部独立sequence checksum/pending/CRC核验。Ecore8组全不确定，Pcore8组局部领先，fallback无稳定负向；不作为完整日志提速证明。原result/manifests在queue-ecore/queue-pcore。

接下来100k+1000warmup、默认CRC/systemclock/fullJSON、256slot/512B/portable64KiB、writtenflush/close/cleanup的Ecore/Pcore shared/SPSC和schema/PMU串行窗口。所有正负/噪声必须保存，不能用zeroDIV或queueprobe局部数据当Foundation排名。

首Ecore全160项/16,160,000JSON：15组writtenclose不确定、SPSCMmapP4batch约1.0186局部领先；没有稳定负向。lifecycle全不确定；sharedMemoryP1sampled p50约1.1024（候选快约10%）、SPSCMemoryP1sampled p50约1.0242局部领先，其他tail不确定。该SPSC收益不能归因于source未改的SPSC函数，保留window/code布局限制。

Ecore40项PMU/4,040,000JSON：MemoryP4/MmapP4 instructions约少0.12%有局部资格，MemoryP1instructions少约0.115%不确定；MmapP1instructions约+0.258%不确定，原负向保持。MemoryP1cycles约1.0427局部领先，其余cycles与PMU吞吐不确定。未作为完整性能承诺，后续p50长流程与Pcore/schema验证尚待完成。

Pcore160项/16,160,000JSON：sharedMemoryP1batch written-close约0.95544局部基线领先、lifecycle同组基线领先，其余15组不确定；调用p50/p99.9全不确定。这是主路径真实反例，必须保留，不由Ecorep50正向覆盖。后续同组百万条复测与EcoreMemoryP1p50长流程独立测，当前仍未有保留资格。

schema8组written-close全不确定，lifecycle一组基线领先/七不确定；P1Memory/Mmap sampled p50分别约0.89669/0.89979基线局部领先（候选约11%更慢），p99.9全不确定。正向defaultp50不能覆盖prepared反例，当前仍无保留资格。当前40项百万条P1默认双topology复测正在完成，不为重测删schema负向。

PcoreMemoryP1百万条20项/20,020,000JSON：batchwritten/lifecycle中位约1.01577/1.01487均不确定，原100k稳定负向未在长batch取得重复资格；sampled约0.93334/0.93427仍负向中位，但不确定，p50/p99/p99.9均不确定。慢值/所有负向保留，不能据复测不确定宣布没有影响。Ecore长P1尚未结束。

最终本版本不保留：480项实际file对照共84,480,000物理JSON（另queue800rawbatch），default有p50局部收益，但preparedP1稳定p50反例/Pcore短主路径negative存在，长窗口不确定不能确认整体收益；全部正负保持。originalproductionworkspace未应用本候选，仅isolatedsource/binary测量。decision.json记录每个窗口与计数；下一cache模式仍对originalbaseline独立测，不继承此前speed。

EcoreP1百万条20项/20,020,000JSON：sharedwritten/lifecycle约1.00734/1.00704不确定、p50约1.08966正向中位但不确定；SPSCwritten/lifecycle约1.00185/1.00160/p50约1.00344均不确定。短defaultp50局部收益未取得长窗口资格，schema稳定negative与所有其他counterexamples保留。
