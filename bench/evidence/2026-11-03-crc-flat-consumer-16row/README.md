# 仅用原16行表的消费校验CRC

上一版 [flat consumer CRC](../2026-11-03-crc-flat-consumer/README.md) 在消费端使用额外row16..23，E-core有局部吞吐收益但async Mmap P1 sampled schema p99复现为719→782ns，按门槛拒绝。本候选独立重做，不继承其比值：消费校验只使用通用update原有的16个1KiB row，把20B header拆成16+4、24B reference拆成16+8两段固定折叠；producer commit仍走原`Crc32.update`，不增加任何row、runtime flag或公开API。

## 实现与静态门槛：通过

`Crc32.updateFixedParts(N, bytes)`在comptime展开两段：先折叠前16B（top row 15/11/7/3），再用中间state折叠尾部4B（top row 3）或8B（top row 7/3）。所有输入word在唯一一次state写入前读取，保留destination state与输入重叠时的语义。`format.checksum/checksumV2`的commit路径仍是普通update；新增noinline `validationChecksum`只被`validateSlot`和`Archive.Reader.copyCommit`的CRC位置调用，length/generation/marker先、schema/codec后的顺序不变。

[actual-review.json](actual-review.json) 由 [audit_actual.py](audit_actual.py) 对冻结二进制生成：

- producer `submitSafeDestination`：两版均1048指令/30 call/frame `0xd18`/372 stackrefs；归一化指令流与5个RIP常量内容完全相同。
- 通用`Crc32.update`：两版均1412B/310指令/20 PCLMUL，归一化后相同。
- 旧`Journal.slotChecksum` 156B/48指令/3 call在before独立存在；candidate由相同producer内联保留。
- candidate ELF中row0..15各只有一个物理copy，row16..23为0；rodata相对before增长0B。
- validation family：v1 79指令/1 call/16个row地址，v2 145指令/1 call/16个row地址，均只引用row0..15。
- DWARF对象大小不变：Journal 768B、Runtime 12800B、Field 48B。

CRC本体沿用此前51d15方法已执行的basis/seed/alignment/guard/alias数学证据；本轮新增16行身份与16+4/16+8分段的完整oracle测试，native Debug/Safe/Fast与generic Safe实际执行通过。

## 正确性

21个具名case（consumer CRC roles、slot CRC、checked generation corruption、recoveryRecordAt、v2 schema ref、batch borrow、parallel producers、mmap/SPSC reopen、SPSC wrap、schema reserve、Reader五case、memory/mmap progress四case）在native Debug/Safe/Fast与generic Safe实际执行通过；无编译、数值、并发或资格失败。日志见`worker-*.log`，命令见[run_workers.sh](run_workers.sh)。

## 完整流程：按预定门槛拒绝

双拓扑各320项完整async/SPSC Memory/Mmap P1/P4 batch/sampled inline/schema流程，每拓扑逐条核验3232万JSON：

- E-core：208轴中60 qualified lead、142 inconclusive、6 qualified negative；written 23 lead/9 inc，written+flush 23 lead/9 inc，lifecycle 9 lead/23 inc，p999 3 lead/13 inc。
- P-core：208轴全部inconclusive，0 negative。

E-core的6个negative为async Memory P4 batch inline `init_ns` 0.99000、async Memory P4 sampled schema `init_ns` 0.96152、SPSC Memory P1 sampled schema `p50_ns` 0.91485、SPSC Mmap P1 sampled schema `p50_ns` 0.86767、SPSC Mmap P4 sampled schema `p50_ns` 0.94979、SPSC Mmap P4 sampled schema `p99_ns` 0.91860。按预定“任一qualified negative即拒绝”，本版不能保留。

对6个轴各做5轮独立复测：[negative-confirmation.json](negative-confirmation.json) 全部为inconclusive（init 1.06492/1.04025，p50 0.92200/0.88491/0.98065，p99 0.92582），没有一个复现qualified negative。两个窗口期间宿主都有一项与本库无关的100% CPU `zig test`在运行，loadavg约111–118；因此不能把full-run尾部负向归因于候选，也不能用复测的inconclusive替代预定full-run门槛。

candidate撤回，生产保持185e700原算法、三个CRC检查点、完整字段/clock/capture/borrow/pin/barrier预算和默认协议。未运行Foundation前端trial，未更新跨库排名；E-core 23/32 written局部lead不覆盖full-run负向门槛。全部正负与原始数据保留在 [flow-ecore](flow-ecore/summary.json)、[flow-pcore](flow-pcore/summary.json)。整体“业界最佳”目标仍未完成。
