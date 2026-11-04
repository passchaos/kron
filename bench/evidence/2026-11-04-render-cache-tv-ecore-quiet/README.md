# Quiet E-core render_cache P4 raw window (still noisy)

## 配置

生产 `render_cache` opt-in（P4、async/SPSC、memory/mmap、inline），E-core `[17,20,25,27,29,31]`，100k+1k，5 rounds，80 trials，逐条核验 8,080,000 条完整 JSON。

## 中位

| 配置 | batch | sampled |
| --- | ---: | ---: |
| kron async-memory | 2.724M | 2.604M |
| kron async-mmap | 2.906M | 2.718M |
| kron spsc-memory | 3.349M | 3.325M |
| kron spsc-mmap | 3.290M | 3.295M |
| Foundation memory | 2.110M | 2.082M |
| Foundation mmap | 3.089M | 2.663M |
| tracing memory | 2.134M | 2.118M |
| tracing mmap | 2.625M | 2.726M |

## 噪声与结论

本窗口仍不可用：Foundation memory sampled 60.8% outlier、Foundation mmap 15%–17%、tracing mmap 14%–26%、kron async 22%–39%。只有 spsc-memory sampled 8.6%、async-mmap batch 10% 局部稳定，但 peer 仍噪声；绝大多数配对 inconclusive。

这是**原始噪声窗口**，不是排名：spsc 轴中位 3.29–3.35M，对 peer 约 1.5–1.6x，但未 qualified；更早安静窗口的 P4 memory 1.63/1.58 qualified 仍是现有最佳证据。完整数据见[analysis.json](analysis.json)/[comparison.md](comparison.md)/[results.jsonl](results.jsonl)。
