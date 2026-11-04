# Render cache P4 with tree_validated (noisy raw window)

## 配置

生产 `render_cache` opt-in（P4、async/SPSC、memory/mmap、inline），E-core `[23,25,27,29,31,21]`，100k+1k，5 rounds，80 trials，逐条核验 8,080,000 条完整 JSON。

## 中位

| 配置 | batch | sampled |
| --- | ---: | ---: |
| kron async-memory | 2.928M | 2.937M |
| kron async-mmap | 2.940M | 2.924M |
| kron spsc-memory | 3.436M | 3.416M |
| kron spsc-mmap | 3.398M | 3.378M |
| Foundation memory | 2.281M | 2.271M |
| Foundation mmap | 2.850M | 2.547M |
| tracing memory | 2.126M | 2.136M |
| tracing mmap | 2.604M | 3.128M |

## 噪声与结论

本窗口 peer/spool spread 很大：tracing memory batch 92.6% outlier、Foundation mmap 14%–17%、tracing mmap batch 19%；kron async-memory 11%–12%、spsc 10%–22%。绝大多数配对 inconclusive；只有 async-mmap batch/sampled 自身 spread 3%–5%，但 peer 仍噪声。

这是**原始噪声窗口**，不是排名：render_cache P4 中位领先多数轴（async-memory 1.28–1.38x、spsc 1.35–1.62x），但 tree_validated 的增量在本窗口无法隔离。完整数据见[analysis.json](analysis.json)/[comparison.md](comparison.md)/[results.jsonl](results.jsonl)。
