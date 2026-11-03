# Flat CRC 仅用于消费校验

独立于此前producer+consumer直接索引版本。此前两核640项完整流程/6464万JSON有throughput局部收益，也有E-core SPSC p99与P-core shared schema p50稳定反例，已按门槛拒绝；见 [direct-index报告](../2026-11-03-crc-flat-segments/direct-index/README.md)。本轮不继承其比值或假称恢复尾部。

一个format-owned privateinline checksumBody按comptime commit/validate及v1/v2角色构造一次原20Bheader，返回raw计算后的u32 CRC。现有checksum/checksumV2保signature和V2first24Bassert，commit仅原Crc32.update。新增internalnoinline validationentry-family，v1无ref、v2typed24ref，validate用fixed20/ref24，再ordinarypayload与原final。无runtimeflag、Root新API、publicproof、skip或aggregate返回。

原Journal.slotChecksum和Reservation.commit body/call保持。仅validateSlot原CRC位置的计算重定向，length/generation/marker仍先，schema/readiness仍后。所有checkedpeek/batch/reclaim/recovery继续validateSlot；releaseAfter保checkedpeek的第三CRC。Archive.Reader.copyCommit稳定header/payloadcopy和range检查之后、schema/codec之前也需显式新validationentry。SPSC使用baseReservation/Journal，不改其commit。

## 实际静态门槛：通过

[actual-review.json](actual-review.json) 由 [audit_actual.py](audit_actual.py) 对冻结的 `before-reference`/`candidate-reference` 实际生成：

- producer `core.runtime.Runtime.submitSafeDestination`：两版均为1048条指令、30个call、frame `0xd18`、372个rsp/rbp引用；地址归一化后整段指令流完全相同，call目标多重集相同，5个RIP相对常量的8字节内容逐一相同。
- 通用 `platform.crc32.Crc32.update`：两版均1412B、310条指令、20条PCLMUL、0 call；地址归一化后完全相同。
- 旧 `Journal.slotChecksum` 独立符号156B/48指令/3 call；candidate因只在producer内联而未单独发射，producer完全相同的指令流保留该3次 `Crc32.update` 调用。
- 24个canonical 1KiB row在candidate ELF中各只有一个物理copy；row0..15与通用update共用同一地址，row16..23仅被validation family引用；rodata仅增加8192B。
- validation family：v1为78指令/1 call/20个row引用（16旧+4新），v2为146指令/1 call/44个row引用（24 row）；只引用上述canonical地址。
- DWARF对象大小不变：Journal 768B、Runtime 12800B、Field 48B。

CRC source仍为 `51d15...`，其独立basis/align/guard/alias证据沿用此前已执行结果；本轮没有重复这些数学测试。

## 正确性

21个具名case（consumer CRC roles、slot CRC、checked generation corruption、recoveryRecordAt、v2 schema ref、batch borrow、parallel producers、mmap/SPSC reopen、SPSC wrap、schema reserve、Reader五case、memory/mmap progress四case）在native Debug/Safe/Fast与generic Safe实际执行通过；无编译、数值、并发或资格失败。详见 [worker-test-manifest.json](worker-test-manifest.json)。

## 完整流程与决定：拒绝

按 [performance-plan.json](performance-plan.json) 的预定门槛，静态和正确性通过后独立运行双拓扑320项完整async/SPSC Memory/Mmap P1/P4 batch/sampled inline/schema流程，每拓扑逐条核验3232万JSON：

- E-core：208轴中50个qualified lead、155 inconclusive、3个qualified negative；written 19 lead/13 inc，written+flush 18 lead/14 inc，lifecycle 10 lead/22 inc，p999 3 lead/13 inc。
- P-core：208轴中1个qualified lead、207 inconclusive、0 negative。

E-core的3个qualified negative是async Memory P4 batch schema `init_ns` 0.95259、async Mmap P1 sampled schema `p99_ns` 0.95984、SPSC Mmap P4 sampled schema `p50_ns` 0.92934。按预定“任一qualified negative即拒绝”的规则不能保留。针对这三个轴各做5轮独立复测：[negative-confirmation.json](negative-confirmation.json) 中init为inconclusive 1.02287、SPSC p50为inconclusive 0.99576，但async Mmap P1 sampled schema p99仍为peer_leads 0.91497（719→782ns），反例复现。

因此candidate撤回，生产保持185e700原算法、三个CRC检查点、完整字段/clock/capture/borrow/pin/barrier预算和默认协议。未运行Foundation前端trial，未更新任何跨库排名；50个E-core局部lead不覆盖复现的p99反例。全部正负、区间和原始320×2项在 [flow-ecore](flow-ecore/summary.json)、[flow-pcore](flow-pcore/summary.json) 保留。整体“业界最佳”目标仍未完成。
