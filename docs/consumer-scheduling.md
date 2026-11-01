# Memory/Mmap consumer 服务预算

`consumer_batches_per_queue` 在 Runtime 初始化时选择后台从一条队列连续处理的服务量子数，允许1到4，默认4。每个量子最多64条记录；当前可将剩余量子内已经就绪的连续记录合成一个checked交付窗口，完整写出/barrier和逐条回收后，再取新窗口或服务下一个队列。短窗口也扣除至少一个量子，默认最多连续服务256条，显式1则最多64条。共享主队列与SPSC channel使用同一预算，只有一条队列时仍按该预算运行。同步模式没有后台drain，初始化时仍校验该选项的范围。具体合并与确认边界见[合并交付](coalesced-delivery.md)。

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .submission = .low_latency,
    .memory_queue = .{ .capacity = 256, .max_record_bytes = 512 },
    .max_thread_channels = 4,
    .thread_channel_capacity = 256,
    .consumer_batches_per_queue = 1,
    .routes = routes,
});
```

Mmap使用同一选项，只将queue配置替换为journal文件配置。预算不是延迟deadline，也不改变accepted/written/durable、每线程FIFO、CRC、schema检查、配置快照或slot回收。它在创建时固定，不经过热配置发布；0或大于4的值在分配和创建journal之前返回`InvalidOptions`。

较小预算可以缩短积压peer的服务间隔，同时改变批次局部性与满队列producer的等待分布。p99和p99.9可能呈现不同方向，不能从更公平的服务顺序推断所有分位数更低。默认4保持现有调度，应用应按自己的Memory/Mmap负载分别测量吞吐、p99与p99.9再选择。

确定性真实后台测试在首条写入回调处建立屏障，然后积压160条busy日志和一条peer日志。在Memory/Mmap、共享peer与SPSC peer四种组合中，预算1/2/3/4时，peer分别在第1/65/129/161条busy输出后得到服务；线程内sequence、written计数、零剩余积压和初始化后零分配均核对。该验证以记录数界定服务间隔，不宣称操作系统的墙钟调度上界。

公共集成测试另外观察SPSC满队列上的真实futex等待，shutdown唤醒已admitted producer，后者返回`rejected_closing`并abort自己的未完成reservation。Memory/Mmap分别核对没有accepted记录、没有输出和没有积压残留。原deadline、配置替换、文件错误与恢复测试继续约束同样的生命周期。

`bench/cpp_reference/kron_reference.zig`支持`--consumer-batches=1`至4并在JSON报告中保存值。Memory/Mmap完整性能报告与测量源码、原始失败和默认预算对照位于`bench/evidence/2026-11-01-channel-fairness/`。

同一可执行文件的40项完整文件对照分别验证Memory/Mmap四producer，100k测量记录＋1k预热，五对sampled/batch，共核对404万条JSON。预算4→1的Memory p99中位约10.9→82.8µs、p99.9约377.7→114.7µs；Mmap p99约9.1→84.5µs、p99.9约391.0→110.7µs。所有分位数与吞吐组均因spread超门限标inconclusive；取舍在更早的独立候选对照中也观察到。默认4保持，显式1不能被描述为整体更快或所有尾延迟更低。原始每项计数、顺序、hash、关闭和初始化结果见`tuned-results.jsonl`与`tuned-comparison.json`。

基于`714c470/e8bd353`另测跨队列64条轮次合并窗口：每队列保留原1..4量子，总窗口最多256条，输出屏障共享且逐条CRC/回收保持。四队列Memory/Mmap×inline/schema、稀疏六队列容量分割、peek/flush/durable与晚期损坏定向Debug/Safe/Fast各26项通过，原1/65/129/161 peer位置保持。但440项完整流程/PMU/单量子控制核对5244万条JSON后，吞吐/尾延迟全部因波动保持inconclusive；inline SPSC Memory/Mmap P4 p99.9中位约352µs→86µs，p99却约0.6µs→72–73µs，用户态指令增加约0.58%–0.71%。额外80项与现有一量子控制也未证明一般优势，候选已全量否决，生产恢复原调度。完整失败、资源和正负分布见`bench/evidence/2026-11-01-cross-queue-delivery/`。下一步等待路径优化需从实际进度/唤醒证据出发，不能只挑低p99.9推广默认策略。

SPSC满队列等待现在使用本队列的进程内space epoch。其他队列的完成不会推进该epoch；本队列tombstone/已确认窗口完成后推进，并在已有等待者时唤醒它。只有一位合法SPSC owner登记等待，登记后重新检查worker错误/closing；seq_cst的epoch/登记顺序使并发通知要么唤醒已登记者，要么改变futex检查的expected值。worker退出/错误和shutdown对所有稳定channel通知，即使其本队列没有写出进展。共享producer与control的原global progress协议保持，服务预算与FIFO不变。

独立诊断各12项前后核对242.4万条JSON，SPSC每试验本队列written未变化的wait返回从832–1137降为0；该观测包含立即返回，不能直接解释为真实睡眠次数或完整速度。正式400项文件/PMU/百万条检查核对8440万条JSON。Memory inline SPSC P4长sampled调用p99.9中位366.312→340.708µs（−6.99%），两侧CV/spread通过且区间不重叠；p50/p99与Mmap尾部仍未取得一般资格，极端等待仍约340µs。短流程P1吞吐负向中位约10%与较大波动保留，百万条P1 batch未重现该负向、中位+2.26%但区间重叠。不扩大队列/file budget或增加分配次数，每Journal进程内control增64字节。本队列回收、sleep前shutdown、epoch回绕与不同队列worker失败的真实并发回归见`bench/evidence/2026-11-01-queue-progress/`，不据此更新Foundation跨库排名。

全局进度等待者登记的后续实验已否决：SPSC全局wake调用约414–425→4–8、共享约减少一半，但200项完整流程与80项更长的shared独立复测（共4428万JSON）未证明共享路径整体收益。Memory batch复测中位P1/P4为−1.02%/−2.91%，区间重叠；其他吞吐和尾部组互有正负。生产继续使用原通知协议，源码、全部慢值和决策见 [否决记录](../bench/evidence/2026-11-02-global-progress/README.md)。常规应用优先shared Memory/Mmap；SPSC作为高级可选和退化控制保留。
