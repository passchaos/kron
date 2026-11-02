# 当前kron与Foundation缩减同轮抽查

这是当前生产源码`bc908cc`与真实Foundation + spdlog前端的缩减同轮对照，不是完整200项矩阵。宿主仍处非安静窗口；结果只证明本轮局部重复性，不更新一般跨库排名。

## 范围与身份

`run.py`使用`--libraries foundation,kron`、`--kron-frontend managed`、`async`、Memory/Mmap、P1/P4、batch/sampled、5次重复、100000事件+1000 warmup、完整JSON metadata与系统墙钟、256队列槽、512B记录预算、64KiB file buffer、portable、written→shutdown→cleanup。80项试验逐条核对8,080,000条物理JSON，accepted=written、pending/drop=0。

Foundation是真实spdlog前端＋Rust后台；kron是managed typed-capture-deferred JSON。两者输出metadata/字段布局相同，timestamp值与channel/sequence分配不同。源码、harness、Foundation revision、spdlog依赖和binary身份在`manifest.json`，逐项min/max/spread与10%门限结论在`analysis.json`。artifacts按驱动清理，原始报告保留物理bytes/记录数与file hash。

## 完整关闭吞吐中位

单位M条/s，包含producer、后台格式化/写出、written flush、shutdown与清理；没有请求durable。

| 配置 | Memory P1 batch | P1 sampled | P4 batch | P4 sampled | Mmap P1 batch | P1 sampled | P4 batch | P4 sampled |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Foundation + spdlog | 2.133 | 1.970 | 2.121 | 2.225 | 1.917 | 1.761 | 2.189 | 2.083 |
| kron async | 2.375 | 2.227 | 2.255 | 2.303 | 2.333 | 2.174 | 2.364 | 2.333 |

调用延迟中位（ns，sampled组）：

| 配置 | Memory P1 p50/p99 | Memory P4 p50/p99 | Mmap P1 p50/p99 | Mmap P4 p50/p99 |
| --- | ---: | ---: | ---: | ---: |
| Foundation + spdlog | 352 / 573 | 850 / 29,491 | 516 / 1,003 | 1,048 / 8,133 |
| kron async | 338 / 689 | 897 / 24,425 | 334 / 664 | 888 / 23,441 |

## 配对吞吐比值

比值是同一重复内`kron/Foundation`的written_records_per_sec，5对bootstrap；任一组spread≥10%或区间跨1时保持inconclusive。

| 配置 | 中位比值 | 95%区间 | 比值spread | Foundation/kron spread | 资格 |
| --- | ---: | --- | ---: | --- | --- |
| Memory P1 batch | 1.125 | 1.056..1.146 | 7.9% | 6.5% / 7.9% | local repeatability |
| Memory P1 sampled | 1.130 | 0.894..1.181 | 25.4% | 10.1% / 28.6% | inconclusive |
| Memory P4 batch | 1.097 | 0.923..1.157 | 21.3% | 8.5% / 18.0% | inconclusive |
| Memory P4 sampled | 1.035 | 0.983..1.085 | 9.8% | 4.1% / 9.0% | inconclusive（区间跨1） |
| Mmap P1 batch | 1.241 | 1.098..1.268 | 13.7% | 9.9% / 7.0% | inconclusive |
| Mmap P1 sampled | 1.258 | 1.210..1.435 | 17.9% | 19.4% / 7.9% | inconclusive |
| Mmap P4 batch | 1.097 | 0.960..1.107 | 13.3% | 18.9% / 6.0% | inconclusive |
| Mmap P4 sampled | 1.091 | 1.031..1.129 | 9.0% | 14.0% / 9.4% | inconclusive |

只有Memory P1 batch达到本轮两侧spread与区间门限：kron中位吞吐比Foundation + spdlog高约12.5%。其余组仍因spread或区间跨1保持inconclusive；Mmap P1 sampled的区间整体高于1，但spread超门限，不能作为稳定领先。该窗口不能替代完整200项矩阵，也不更新Foundation/tracing排名。

## 复现

```sh
python3 bench/cpp_reference/run.py \
  --output-dir bench/cpp_reference/evidence/2026-11-02-current-foundation-spotcheck \
  --libraries foundation,kron --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --kron-frontend managed --kron-modes async \
  --kron-storages memory,mmap --metadata full --discard-artifacts
python3 bench/cpp_reference/analyze.py bench/cpp_reference/evidence/2026-11-02-current-foundation-spotcheck
```

完整Foundation + spdlog + tracing矩阵仍需在安静窗口按原200项流程重跑，才能更新跨库排名。
