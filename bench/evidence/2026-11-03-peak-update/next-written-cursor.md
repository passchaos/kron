# 下一轮shared written cursor研究（未实现）

shared advanceWritten只有一个合法consumer写入。constructor scanRecovery发布前重建；peek/peekChecked/peekBatch消耗leading tombstone、releaseAfter正常reclaim和recovery gap推进走同一函数。shared sync/checkpoint只同步或读取，single模式才镜像cursor。Reader是只读；shutdown等待/join worker不是第二consumer。原子word并不使公开peek/release支持多个consumer；ownership handoff需外部同步。

因此可独立测量 `const cursor=self.written(); if(sequence>cursor.load(.monotonic)) cursor.store(sequence,.release);` 替换shared fetchMax，保留即时offset72与不回退，不延后到sync。release store加强writtenTarget acquire读的发布关系，slot turn、配置pending pin和written计数仍在cursor后更新，flush仍依赖delivery mutex，不能把cursor acquire当作所有清理完成的证据。

当前peak候选实际binary三处shared cursor仍cmp/cmova/无条件lock cmpxchg：checked peek leading tombstone0x11180aa、正常release/reclaim0x111dbda、recovery前缀0x111dcca。具体addresses绑定peak after-reference，source/binary身份在当前evidence。这个事实不代表性能收益。

最小回归需Memory/Mmap普通release、leading tombstone和recovery gap在未sync时raw offset72即刻等于writtenTarget；publisher/observer测试只用cursor acquire建立合法先后，不用join替代该关系。保持新live work不被旧recovery tail确认、stale written恢复、checkpoint/durable各阶段失败、晚reclaim CRC损坏、reader gap/latecommit/reuse、cut/关闭和满队列唤醒。最终slot sync失败可能已有durable checkpoint，必须保留原重试而非强求所有状态不动。

本记录只读定位下轮，当前保持peak单候选，不将两机制收益相加，也未编辑/编译/benchmark written路线。
