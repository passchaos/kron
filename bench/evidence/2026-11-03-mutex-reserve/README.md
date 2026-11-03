# Mutex shared reserve候选

P4/mmap差距此前排除了idle、THP和生产端格式化。本候选测试“多producer的shared tail CAS是否比mutex慢”：把`Journal.reserve`的tail CAS循环替换为复用现有`sync_mutex`的串行reserve（tail load/store、turn检查、occupied/high_water和slot header写入在锁内），不新增Journal字段、不改变slot/CRC/恢复/队列预算；SPSC `reserveSingleProducer`保持无锁。

## E-core A/B

同library源码、同reference workload；before=production CAS，after=mutex reserve。E-core async、memory/mmap、P1/P4、batch/sampled、inline/schema：160 trials，逐条核验16,160,000条完整JSON。

- **0 qualified lead**。
- P1：5个qualified negative，`async-memory batch inline` written 0.9838/written+flush 0.9833/lifecycle 0.9847，sampled p50 memory 0.9051、mmap 0.9091。
- P4：11个qualified negative，`async-memory batch inline` 0.9602、`batch schema` 0.9752、`sampled inline` 0.9515、`sampled schema` p50 0.9240；mmap组未取得正向资格。
- 其余轴inconclusive。

`std.Io.Mutex`的锁/解锁和futex等待成本高于当前lock-free tail CAS；P1无竞争路径也因锁开销负向，P4竞争路径没有收益。该候选拒绝，生产保持CAS reserve。

证据：`flow-ecore/summary.json`、`results.jsonl`、`manifest.json`；shadow源码与after binary在`.zig-cache/mutex-reserve`。整体“业界最佳”目标仍未完成。
