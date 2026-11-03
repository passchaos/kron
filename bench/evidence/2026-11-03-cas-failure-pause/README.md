# CAS 失败后的有限 pause 候选

基线生产算法为185e700，当前HEAD的后续提交只记录实验。精确20/24 CRC两候选已拒绝，见 [固定段记录](../2026-11-03-crc-fixed-segments/README.md)；本轮独立检查shared协调成本，不继承旧CRC或TLS/缓存/分片候选的比值。

候选只在 admission.acquire 与 Journal.reserve 的 CAS 失败分支、保留失败返回的实际值后执行一次 `std.atomic.spinLoopHint`。原successful path、Full/turn/sequence检查、closing/cut/count、原子顺序、wakeup、occupied/peak、capture-before-clock、三个CRC与默认256slot/512B保持。全局admission也服务SPSC，必须保留SPSC控制，不能宣称它只影响shared消费者。

先使用已有closed admission、channel cut/retireAll、并发reserve/wrap、closing publication、flush failure/pin等具名测试，确认实际执行；随后检查native实际pause只出现在CAS失败分支、没有新增成功路径call/frame/spill，CRC/renderer/borrow/wakeup controls保持。通过才执行同轮完整managed JSON before/after：Memory/Mmap、P1/P4、async/SPSC、batch/sampled与schema形状，P/E分别测量，保留全部正负。输出逐条验证，计入written flush、shutdown、cleanup，默认CRC与预算不变。

这只是候选，没有速度资格，也没有Foundation排名变化。另一个待研究方向为global progress按全宽登记等待者减少空futexWake；它必须保每次epoch推进、producer Full和flush/cut两群等待者以及溢出always-wake，不在本轮混入。

## 完整流程决定

候选已拒绝。双拓扑共160项完整流程，逐条核验16160000条物理JSON，accepted/written完整且drop/pending为0，实际managed/fullmetadata/256slot/512B确认。E-core Memory P1 batch的written速度比0.98615、written+flush0.98511、生命周期0.98439均稳定负向，其他49个轴不确定；P-core52个轴全部不确定。全部正负和区间见 [E-core](flow-ecore/summary.json)、[P-core](flow-pcore/summary.json)，比值大于一有利于候选。P-core部分大幅中位变化没有通过spread资格，不作速度承诺。

按预先写出的 [performance-plan.json](performance-plan.json) 门槛，没有扩展SPSC/schema或Foundation试验；SPSC仅有正确性与compiledcontrol证据。生产未应用，defaultCRC、三个检查点与原队列预算保持；原benchmarksource完整复制为reference-source.zig并确认与baselinecommit逐字一致。因果未证明，未采集动态CAS重试次数，不能将这一窗口负向归因于pause或某种layout。

[actual-review.json](actual-review.json) 确认newPAUSE只有两个失败边；reserve546B/frame0，begin1269→1285B/frame72B、8calls和39stackrefs保持，但branchpolarity/失败侧flagtest/NOP/TLScallback relocation改变。所有已检查CRC/consumer/renderer/SPSCreserve控制归一化相同，Runtime12800B/Journal768B及成员offset保持。四配置各8个已有相关具名case实际通过，详见 [test manifest](worker-test-manifest.json)。

下一独立方向是global progress等待者登记与通知握手审查；本轮不混入其新状态或wake省略。整体Foundation两个前端目标仍未达到。
