# quotedAscii直接写入候选诊断

`jsonMember`已有完整key直接写入destination的fast path；本轮给`quotedAscii`增加同样的“完整ASCII run + 2引号”直接写入，目标是减少每条string value/scope/message的三次`std.Io.Writer` vtable调用。短/streaming writer保留原三call失败前缀。

## 身份

- 基线：提交`cebf759`（portable默认backend），reference binary `68c06b8109fad63fc8f345ea68882d6ad478b25198268bd3b2287be3a0590094`。
- 候选：只改`src/encoder/escaping.zig`的`quotedAscii`，reference binary `99912560dfea7a67bc3e65e89eef57e649ae2a27133eddd2ba496499abae4559`。
- 两者ReleaseFast、真实ext4文件、完整JSON、explicit portable。

## 正确性

候选在`zig test src/root.zig -O ReleaseSafe --test-filter 'escaping'`中22/22通过，覆盖UTF-8/非法字节、record separator、ASCII word scan、短尾与streaming chunk边界；短/streaming fallback仍保留原三call序列。

## PMU

P-core固定`taskset -c 0,2,4,6,8,10`，runtime async memory P4 batch，500k events，baseline/candidate交替5对。`cpu_core/instructions`（十亿）：

| pair | baseline | candidate | ratio |
| ---: | ---: | ---: | ---: |
| 1 | 4.2536 | 4.2282 | 0.9942 |
| 2 | 4.2573 | 4.2568 | 0.9999 |
| 3 | 4.2613 | 4.2501 | 0.9974 |
| 4 | 4.2547 | 4.2386 | 0.9960 |
| 5 | 4.2678 | 4.2494 | 0.9957 |

中位约**−0.40% instructions**，方向一致但幅度很小。`cpu_core/cycles`五对为0.8503/1.2250/1.0047/0.9811/0.9751，波动远超门限，不能作为稳定收益。原始perf输出见[pmu-pairs.txt](pmu-pairs.txt)。

## 完整流程A/B

- 未pinned、100k events、managed/runtime × memory/mmap × batch/sampled × 3 reps：written ratio混合（managed 0.80–1.05，runtime 0.91–1.07），无稳定方向，见[results-unpinned-100k.jsonl](results-unpinned-100k.jsonl)。
- pinned `0,2,4,6,8,10`、500k events、同矩阵 × 3 reps：written ratio仍混合（managed 0.71–1.02，runtime 0.97–1.09），managed mmap batch三对0.88/0.73/0.67但绝对吞吐同时受窗口负载影响，未达到CV/spread资格，见[results-pinned-500k.jsonl](results-pinned-500k.jsonl)。

## 决策

候选只取得约0.4%的指令下降，没有qualified吞吐或尾部领先，且完整流程出现混合/负向；按预定门槛**撤回**，`src/encoder/escaping.zig`恢复基线。该实验说明string引号的三次vtable调用不是consumer关键路径的主要成本，继续微调单条`writeAll`不足以缩小Foundation P4/mmap差距。

## 边界

PMU/A-B为单机ext4/NVMe、deferred consumer、64KiB buffer、explicit portable；没有Foundation同轮trial，没有更新跨库排名。候选源码已撤回，未进入生产。整体“业界最佳”目标仍未完成。
