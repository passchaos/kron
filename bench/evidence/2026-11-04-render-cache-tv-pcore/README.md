# P-core render_cache P4 raw window (very noisy)

## 配置

生产 `render_cache` opt-in（P4、async/SPSC、memory/mmap、inline），P-core `[0,2,4,7,9,12]`，100k+1k，5 rounds，80 trials，逐条核验 8,080,000 条完整 JSON。

## 中位

| 配置 | batch | sampled |
| --- | ---: | ---: |
| kron async-memory | 2.510M | 2.678M |
| kron async-mmap | 2.278M | 2.744M |
| kron spsc-memory | 2.889M | 2.657M |
| kron spsc-mmap | 3.194M | 3.478M |
| Foundation memory | 2.090M | 2.239M |
| Foundation mmap | 2.434M | 2.572M |
| tracing memory | 2.076M | 2.125M |
| tracing mmap | 2.272M | 2.513M |

## 噪声与结论

本窗口不可用：Foundation memory batch spread 97.3%、tracing memory batch 90.4%、kron batch 31%–50%、tracing mmap 11%–17%。绝大多数配对 inconclusive。只有 kron async-memory sampled 自身 5.3% 稳定，但 peer 仍噪声。

这是**原始噪声窗口**，不是排名；render_cache P4 的安静窗口 qualified evidence（P4 memory 1.63/1.58）仍是现有最佳证据。完整数据见[analysis.json](analysis.json)/[comparison.md](comparison.md)/[results.jsonl](results.jsonl)。
