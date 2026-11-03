# Producer-format策略候选

P4/mmap PMU显示kron用户态CPU更少但wall-clock更慢，Foundation用producer_format、kron用consumer deferred format。本候选验证“把JSON格式化移到producer、consumer只写出”是否能缩小P4差距。

实现（仅shadow，不进入生产）：`Runtime.RouteOptions/Route`增加`format_at_capture`；单route、inline、已验证树时producer用`common.encodeDecoded`把最终JSON写入journal payload，consumer的`delivery.emitPreformatted`直接`writeRecord`，跳过decode/format。schema route仍走原deferred路径作为控制组。输出字节由完整JSON oracle逐条核验。

## E-core A/B

同library shadow、同reference workload；before=deferred（生产路径），after=producer_format。E-core async、memory/mmap、P1/P4、batch/sampled、inline/schema：160 trials，逐条核验16,160,000条完整JSON。

- schema=False（treatment，producer_format）：**0 lead、10 qualified negative**。negative包括`async-memory P1 batch` written 0.9813/written+flush 0.9793、`async-memory P4 batch` 0.9887、`async-memory P4 sampled` 0.9758/0.9752/lifecycle 0.9776/p99 0.966、`async-mmap P1 batch` 0.9736。
- schema=True（control，仍走deferred）：0 lead、6 qualified negative（0.98–0.99），属于新增字段/分支造成的binary layout波动。
- 其余98轴inconclusive。

producer_format把consumer的格式化工作移到producer，但kron的producer已经承担capture/encode/CRC/commit；P4时producer成为瓶颈，inline组稳定负向。Foundation的producer_format没有直接迁移价值，因为其producer捕获路径更轻。该候选拒绝，生产保持deferred consumer format。

证据：`flow-ecore/summary.json`、`results.jsonl`、`manifest.json`；shadow源码与before/after binary在`.zig-cache/producer-format`。整体“业界最佳”目标仍未完成。
