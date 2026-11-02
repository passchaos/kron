# 当前kron与raw spdlog缩减同轮抽查

这是当前生产源码`bc908cc`的缩减同轮对照，不是完整Foundation矩阵。宿主仍处高负载窗口；结果只用于确认当前源码没有丢失相对位置，不更新Foundation/tracing排名。

## 范围与身份

`run.py`使用`--libraries spdlog,kron`、`--kron-frontend managed`、`async`、Memory/Mmap、P1/P4、batch/sampled、5次重复、100000事件+1000 warmup、完整JSON metadata与系统墙钟、256队列槽、512B记录预算、64KiB file buffer、portable、written→shutdown→cleanup。60项试验逐条核对6,060,000条物理JSON，accepted=written、pending/drop=0。

spdlog是raw `producer_format`入口（Memory），不是Foundation封装；kron是managed typed-capture-deferred JSON。两者输出metadata/字段布局相同，但timestamp值与channel/sequence分配不同。kron另测Mmap，spdlog没有对应Mmap peer，因此不比较Mmap速度。源码、harness、spdlog依赖和binary身份在`manifest.json`，逐项min/max/spread与10%门限结论在`analysis.json`。artifacts按驱动清理，原始报告保留物理bytes/记录数与file hash。

## 完整关闭吞吐中位

单位M条/s，包含producer、后台格式化/写出、written flush、shutdown与清理；没有请求durable。

| 路径 | Memory P1 batch | P1 sampled | P4 batch | P4 sampled |
| --- | ---: | ---: | ---: | ---: |
| kron async Memory | 2.376 | 2.264 | 2.347 | 2.362 |
| spdlog raw Memory | 1.501 | 1.400 | 0.671 | 0.611 |
| kron async Mmap | 2.367 | 2.275 | 2.313 | 2.289 |

调用延迟中位（ns）：

| 路径 | P1 p50/p99 | P4 p50/p99 |
| --- | ---: | ---: |
| kron async Memory | 338 / 735 | 873 / 24,206 |
| spdlog raw Memory | 596 / 1,767 | 4,698 / 33,270 |
| kron async Mmap | 335 / 613 | 855 / 24,056 |

## 配对吞吐比值

比值是同一重复内`kron/raw spdlog`的written_records_per_sec，5对bootstrap；任一组spread≥10%或区间跨1时保持inconclusive。

| 配置 | 中位比值 | 95%区间 | 比值spread | 资格 |
| --- | ---: | --- | ---: | --- |
| Memory P1 batch | 1.515 | 1.350..1.675 | 21.5% | inconclusive |
| Memory P1 sampled | 1.568 | 1.497..1.668 | 10.8% | inconclusive |
| Memory P4 batch | 3.499 | 3.399..3.617 | 6.2% | local repeatability |
| Memory P4 sampled | 3.713 | 3.574..4.268 | 18.7% | inconclusive |

只有Memory P4 batch达到本轮重复性门限；raw spdlog的P4吞吐明显低于其P1，且先前Foundation + spdlog同轮P4约2.088M/s，说明raw reference入口不能直接替代Foundation前端。因此本页不能声称新的跨库排名，也不能把P4 batch的3.5倍外推到Foundation、tracing或Mmap。

## 复现

```sh
python3 bench/cpp_reference/run.py \
  --output-dir bench/cpp_reference/evidence/2026-11-02-current-managed-frontends \
  --libraries spdlog,kron --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --kron-frontend managed --kron-modes async \
  --kron-storages memory,mmap --metadata full --discard-artifacts
python3 bench/cpp_reference/analyze.py bench/cpp_reference/evidence/2026-11-02-current-managed-frontends
```

完整Foundation + spdlog + tracing矩阵仍需在安静窗口按原200项流程重跑，才能更新跨库排名。
