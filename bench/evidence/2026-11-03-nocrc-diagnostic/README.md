# 当前源码 no-CRC runtime opt-in诊断

此前完整矩阵与PMU把P4/mmap差距指向CRC/journal协议，但那些证据绑定旧源码。本诊断用当前生产V3源码和已有`MemoryQueueOptions.verify_crc=false` opt-in，量化CRC在E-core async memory路径中的当前份额。该模式只允许volatile memory，不改变默认CRC；输出字节和JSON oracle相同。

## E-core A/B

before=production CRC（`68c0...`），after=同library源码、reference设置`verify_crc=false`。E-core async、memory only、P1/P4、batch/sampled、inline/schema：80 trials，逐条核验8,080,000条完整JSON。

- 1 qualified lead：`init_ns` memory P1 sampled schema 1.0617。
- 10 qualified negative：`memory P1 batch inline` written 0.9611/written+flush 0.9628/lifecycle 0.9623；`memory P4 batch inline` 0.9633/0.9658/0.9650；`memory P4 sampled inline` 0.9889/0.9890/0.9867、p99 0.9742。
- 其余41轴inconclusive。

当前窗口没有复现旧compile-time no-CRC诊断的+20%–31%；runtime `verify_crc=false`的after反而稳定慢约1%–4%。这可能来自runtime分支/二进制布局、V3已降低schema CRC成本，或本窗口宿主噪声；不能据此把P4差距归因于CRC-only。旧[memory fast mode](../2026-11-02-memory-fast-mode/README.md)和[nocrc诊断](../2026-11-02-nocrc-diagnostic/README.md)的compile-time结果仍绑定其当时源码/窗口，不叠加到当前。

生产默认CRC和`verify_crc`默认true保持；opt-in仅作为明确接受未检测内存损坏风险的诊断/性能模式。证据：`flow-ecore/summary.json`、`results.jsonl`、`manifest.json`。整体“业界最佳”目标仍未完成。
