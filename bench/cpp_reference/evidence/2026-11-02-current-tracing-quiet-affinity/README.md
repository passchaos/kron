# E-core quiet-affinity tracing对照：tracing全面领先

这是当前源码`647e667`在**无SMT兄弟的物理E-core**（CPU 16/18/20/22/24/26）上的80项缩减同轮抽查，80项试验、8,080,000条JSON逐条核对。它不是默认`auto` P-core窗口的替代排名，而是补充一个不同CPU拓扑下的稳定性证据。

## 范围与身份

`run.py`使用`--libraries foundation_tracing,kron`、`--kron-frontend managed`、`async`、Memory/Mmap、P1/P4、batch/sampled、5次重复、100000事件+1000 warmup、完整JSON metadata与系统墙钟、256队列槽、512B记录预算、64KiB file buffer、portable、written→shutdown→cleanup。`manifest.json`记录affinity、host、Foundation revision、依赖和binary身份。

## 完整关闭吞吐中位

单位M条/s：

| 配置 | Foundation + tracing | kron async | 比值 | 95%区间 | 比值spread | 资格 |
| --- | ---: | ---: | ---: | --- | ---: | --- |
| Memory P1 batch | 2.175 | 1.723 | 0.788 | 0.767..0.793 | 3.3% | tracing领先，达到门限 |
| Memory P1 sampled | 2.004 | 1.692 | 0.845 | 0.824..0.872 | 5.6% | tracing领先，达到门限 |
| Memory P4 batch | 2.228 | 1.631 | 0.729 | 0.678..0.765 | 12.0% | inconclusive |
| Memory P4 sampled | 2.276 | 1.631 | 0.715 | 0.710..0.745 | 4.9% | tracing领先，达到门限 |
| Mmap P1 batch | 2.773 | 1.737 | 0.627 | 0.616..0.637 | 3.4% | tracing领先，达到门限 |
| Mmap P1 sampled | 2.482 | 1.744 | 0.697 | 0.681..0.736 | 8.0% | tracing领先，达到门限 |
| Mmap P4 batch | 2.718 | 1.603 | 0.593 | 0.543..0.597 | 9.1% | inconclusive（tracing spread 11.3%） |
| Mmap P4 sampled | 2.902 | 1.632 | 0.563 | 0.546..0.618 | 12.8% | inconclusive（两侧spread超门限） |

8组中tracing中位全部更高；5组达到本轮两侧spread/区间门限，领先幅度约15%–37%。Memory P4 batch与Mmap P4两组因spread保持inconclusive。

## 与P-core窗口的差异

默认`auto` P-core窗口（CPU 0/2/4/6/8/10）的前两次tracing抽查方向混合，且首轮局部资格未复测。E-core窗口则稳定显示tracing全面领先。这说明当前kron的完整流程性能对CPU拓扑敏感：

- tracing的producer-format/公共JSON路径在E-core上仍保持较高吞吐。
- kron的typed capture、journal reserve/CRC、后台consumer格式化与交付在E-core上相对更慢。
- 该差异不能归因于单一函数；需要分别profile P-core与E-core的producer/consumer阶段，确认是调度、频率、缓存还是队列同步造成。

本页不把E-core结果推广到P-core或服务器默认配置，也不更新跨库排名；完整200项矩阵应分别在P-core和E-core窗口重跑。

## 复现

```sh
python3 bench/cpp_reference/run.py \
  --output-dir bench/cpp_reference/evidence/2026-11-02-current-tracing-quiet-affinity \
  --libraries foundation_tracing,kron --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --kron-frontend managed --kron-modes async \
  --kron-storages memory,mmap --metadata full --affinity 16,18,20,22,24,26 --discard-artifacts
python3 bench/cpp_reference/analyze.py bench/cpp_reference/evidence/2026-11-02-current-tracing-quiet-affinity
```
