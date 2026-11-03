# FileSink writer-thread双缓冲候选

扩展PMU把P4差距定位到consumer单线程decode+format+write和文件写吞吐。本候选在`FileSink`内部增加opt-in `async_writer`：consumer格式化写入active buffer，专用writer线程把上一buffer `writeBatch`到backend，flush/sync/shutdown仍等待完整barrier。默认关闭；slot/CRC/journal/队列预算不变，只多一个64KiB buffer和一个writer线程。

## E-core A/B

before=production同步FileSink（`68c0...`），after=同library + `async_writer=true`。E-core async、memory/mmap、P1/P4、batch/sampled、inline/schema：160 trials，逐条核验16,160,000条完整JSON。

- P1：2 qualified lead（mmap sampled schema 1.0163/1.0164），3 qualified negative（memory batch inline 0.9572/0.9577/lifecycle 0.9592）。
- P4：**0 lead、11 qualified negative**：memory batch inline 0.9296/0.9285/lifecycle 0.9295、memory sampled inline 0.9517/0.9522/lifecycle 0.9509、mmap batch inline 0.9440/0.9426、mmap sampled p99 0.9490，另有init negative。
- 其余轴inconclusive。

6个E-core CPU被4 producer + consumer + writer占满；writer线程、条件变量、buffer swap和跨线程barrier成本超过I/O重叠收益，P4没有空闲核可用。P1有spare核时mmap sampled schema只有约1.6%局部lead，不覆盖P4反例。候选拒绝，生产保持同步FileSink。

证据：`flow-ecore/summary.json`、`results.jsonl`、`manifest.json`；shadow源码、async reference和after binary在`.zig-cache/async-file-sink`。整体“业界最佳”目标仍未完成。
