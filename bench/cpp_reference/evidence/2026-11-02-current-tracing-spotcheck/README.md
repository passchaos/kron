# 当前kron与Foundation + Rust tracing缩减同轮抽查

当前生产源码`647e667`与真实Foundation + Rust tracing公共JSON入口的缩减同轮对照。80项试验、8,080,000条JSON逐条核对，accepted=written、pending/drop=0。宿主仍处非安静窗口；本页给出当前窗口的局部资格，不替代完整200项矩阵。

## 范围与身份

`run.py`使用`--libraries foundation_tracing,kron`、`--kron-frontend managed`、`async`、Memory/Mmap、P1/P4、batch/sampled、5次重复、100000事件+1000 warmup、完整JSON metadata与系统墙钟、256队列槽、512B记录预算、64KiB file buffer、portable、written→shutdown→cleanup。tracing是公共MakeWriter JSON入口，kron是managed typed-capture-deferred JSON。源码、harness、Foundation revision、Rust依赖与binary身份在`manifest.json`，逐项min/max/spread与10%门限结论在`analysis.json`。

## 完整关闭吞吐中位

单位M条/s，包含producer、后台格式化/写出、written flush、shutdown与清理；没有请求durable。

| 配置 | Memory P1 batch | P1 sampled | P4 batch | P4 sampled | Mmap P1 batch | P1 sampled | P4 batch | P4 sampled |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Foundation + tracing | 2.691 | 2.612 | 2.186 | 2.148 | 2.094 | 1.945 | 2.211 | 2.259 |
| kron async | 2.391 | 2.313 | 2.393 | 2.378 | 2.412 | 2.237 | 2.455 | 2.403 |

调用延迟中位（ns，sampled组）：

| 配置 | Memory P1 p50/p99 | Memory P4 p50/p99 | Mmap P1 p50/p99 | Mmap P4 p50/p99 |
| --- | ---: | ---: | ---: | ---: |
| Foundation + tracing | 232 / 501 | 774 / 29,048 | 482 / 787 | 932 / 8,830 |
| kron async | 329 / 680 | 887 / 22,899 | 388 / 704 | 906 / 23,681 |

初始化中位：

| 配置 | Memory P1/P4 init ms | Mmap P1/P4 init ms |
| --- | ---: | ---: |
| Foundation + tracing | 0.152 / 0.147 | 19.345 / 19.543 |
| kron async | 0.548 / 0.555 | 11.209 / 14.120 |

kron的mmap init在本轮fresh-zero优化后低于tracing；memory init仍约高0.4ms。tracing的Memory P1 p50/p99更低，kron的Memory P4 p99更低；尾部仍不能作一般保证。

## 配对吞吐比值

比值是同一重复内`kron/Foundation tracing`的written_records_per_sec，5对bootstrap；任一组spread≥10%或区间跨1时保持inconclusive。

| 配置 | 中位比值 | 95%区间 | 比值spread | 两侧spread | 资格 |
| --- | ---: | --- | ---: | --- | --- |
| Memory P1 batch | 0.889 | 0.822..0.921 | 11.1% | 8.5% / 15.7% | inconclusive |
| Memory P1 sampled | 0.889 | 0.848..0.895 | 5.3% | 3.4% / 4.7% | local repeatability：tracing领先约11% |
| Memory P4 batch | 1.098 | 1.000..1.158 | 14.4% | 6.3% / 8.3% | inconclusive（区间触及1） |
| Memory P4 sampled | 1.123 | 1.043..1.147 | 9.3% | 5.6% / 6.5% | local repeatability：kron领先约12% |
| Mmap P1 batch | 1.107 | 1.074..1.376 | 27.2% | 20.0% / 8.9% | inconclusive |
| Mmap P1 sampled | 1.150 | 1.048..1.188 | 12.2% | 7.0% / 9.2% | inconclusive |
| Mmap P4 batch | 1.110 | 1.084..1.120 | 3.3% | 4.0% / 2.4% | local repeatability：kron领先约11% |
| Mmap P4 sampled | 1.059 | 0.834..1.081 | 23.3% | 4.1% / 23.7% | inconclusive |

## 结论与复测

首轮窗口曾出现三个局部资格：Memory P1 sampled tracing领先约11%，Memory P4 sampled与Mmap P4 batch kron领先约12%/11%。但相同配置、相同源码的第二轮80项复测没有复现这些资格：

- Memory P1 sampled：第二轮0.839，方向一致但spread 18.3%，inconclusive。
- Memory P4 sampled：第二轮1.016，接近持平，spread 14.3%，inconclusive。
- Mmap P4 batch：第二轮0.894，方向翻转为tracing领先，spread 26.5%，inconclusive。

因此本页首轮资格只能作为该窗口的局部观察，**不能作为当前跨库排名**。当前Foundation + Rust tracing对照保持inconclusive；Memory P1的tracing中位方向在两次都领先，但第二轮不达标；Memory P4与Mmap P4方向翻转。完整200项安静窗口矩阵仍需重跑。复测数据见 [tracing复测](../2026-11-02-current-tracing-spotcheck-2/README.md)。

## 复现

```sh
python3 bench/cpp_reference/run.py \
  --output-dir bench/cpp_reference/evidence/2026-11-02-current-tracing-spotcheck \
  --libraries foundation_tracing,kron --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --kron-frontend managed --kron-modes async \
  --kron-storages memory,mmap --metadata full --discard-artifacts
python3 bench/cpp_reference/analyze.py bench/cpp_reference/evidence/2026-11-02-current-tracing-spotcheck
```

完整Foundation + spdlog + tracing矩阵仍需在安静窗口按原200项流程重跑，才能更新跨库排名。
