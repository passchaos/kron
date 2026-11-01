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
