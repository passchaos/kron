# Foundation + Rust tracing复测：未复现首轮局部资格

这是与`2026-11-02-current-tracing-spotcheck/`相同配置、相同当前源码`647e667`的第二次80项缩减同轮抽查。80项试验、8,080,000条JSON逐条核对，accepted=written、pending/drop=0。宿主仍在非安静窗口。

## 结果

完整关闭吞吐中位（M条/s）：

| 配置 | Foundation + tracing | kron async | 比值 | 95%区间 | 比值spread | 资格 |
| --- | ---: | ---: | ---: | --- | ---: | --- |
| Memory P1 batch | 2.542 | 2.285 | 0.901 | 0.830..0.994 | 18.2% | inconclusive |
| Memory P1 sampled | 2.555 | 2.046 | 0.839 | 0.752..0.906 | 18.3% | inconclusive |
| Memory P4 batch | 2.360 | 2.273 | 0.963 | 0.888..1.055 | 17.4% | inconclusive |
| Memory P4 sampled | 2.250 | 2.149 | 1.016 | 0.885..1.030 | 14.3% | inconclusive |
| Mmap P1 batch | 2.522 | 2.213 | 0.930 | 0.878..1.070 | 20.7% | inconclusive |
| Mmap P1 sampled | 2.464 | 2.015 | 0.820 | 0.563..1.257 | 84.7% | inconclusive |
| Mmap P4 batch | 2.436 | 2.240 | 0.894 | 0.760..0.997 | 26.5% | inconclusive |
| Mmap P4 sampled | 2.375 | 2.049 | 0.870 | 0.667..0.933 | 30.7% | inconclusive |

本轮8组全部因spread超10%或区间跨1保持inconclusive；tracing中位在8组中均更高，但与首轮方向明显不同。

## 与首轮复测对照

| 配置 | 首轮比值/资格 | 本轮比值/资格 | 复测结论 |
| --- | --- | --- | --- |
| Memory P1 sampled | 0.889，tracing领先，达到门限 | 0.839，spread 18.3% | 方向一致，但未达门限 |
| Memory P4 sampled | 1.123，kron领先，达到门限 | 1.016，spread 14.3% | 未复现，接近持平 |
| Mmap P4 batch | 1.110，kron领先，达到门限 | 0.894，spread 26.5% | 方向翻转，未复现 |

首轮的三个局部资格没有在相同配置的第二轮复现。当前可保留的观察只有“Memory P1的tracing中位方向在两次都领先”，但第二轮spread不达标，不能作为稳定排名；Memory P4与Mmap P4方向翻转，说明当前宿主窗口不足以区分这些入口。

## 结论

当前Foundation + Rust tracing对照保持**inconclusive**。不能把首轮任一局部资格推广为当前跨库排名，也不能声称kron或tracing在P4/Mmap稳定领先。需要安静窗口的完整200项矩阵和更多重复才能更新排名。

## 复现

```sh
python3 bench/cpp_reference/run.py \
  --output-dir bench/cpp_reference/evidence/2026-11-02-current-tracing-spotcheck-2 \
  --libraries foundation_tracing,kron --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --kron-frontend managed --kron-modes async \
  --kron-storages memory,mmap --metadata full --discard-artifacts
python3 bench/cpp_reference/analyze.py bench/cpp_reference/evidence/2026-11-02-current-tracing-spotcheck-2
```
