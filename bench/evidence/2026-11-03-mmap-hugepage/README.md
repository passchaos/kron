# Linux mmap透明大页候选

完整Foundation矩阵显示kron在P4/mmap组仍落后（如async-mmap P4 batch 0.538、spsc-mmap P4 batch 0.611）。本候选只在Linux `Mapping.map`的`mmap(MAP_POPULATE)`之后增加best-effort `madvise(MADV_HUGEPAGE)`，目标是减少16.8MB journal随机访问的TLB压力；slot/format/CRC/预算/生命周期均不变，memory路径不经过该函数。

宿主THP策略为`madvise`，候选编译并运行成功；未改变任何公开API、对象大小或journal版本。

## E-core mmap-only A/B

`compare_versions.py`在同一E-core窗口比较production before与THP candidate，只跑mmap、async/SPSC、P1/P4、batch/sampled、inline/schema：160 trials，逐条核验16,160,000条完整JSON。

- 2个qualified lead：`async-mmap P1 batch schema` written 1.0253、written+flush 1.0230（区间不跨1）。
- 11个qualified negative：`async-mmap P1 batch inline` 0.9545/0.9538、`async-mmap P4 sampled inline` 0.9753/0.9763与p99 0.953、`spsc-mmap P1 batch inline` 0.9912/0.9907、`spsc-mmap P1 sampled inline` 0.9855/0.9875、`spsc-mmap P4 sampled inline` 0.9663/0.9665。
- 其余91轴inconclusive。

THP在schema P1 batch有局部收益，但在inline和SPSC mmap组出现稳定负向，且没有覆盖P4/mmap主差距。按预定任一qualified negative即拒绝，生产保持原mapping；未运行完整release gate或Foundation trial。

证据：`flow-ecore/summary.json`、`results.jsonl`、`manifest.json`；before/candidate binary与源码在`.zig-cache/mmap-hugepage`（未进入生产）。整体“业界最佳”目标仍未完成。
