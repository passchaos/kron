# 当前完整流程自占采样

8项流程共核验8,008,000条物理JSON。每个窗口分别保留原始perf数据的无损xz档案、报告与source/binary身份；没有同轮速度比较。

| 窗口 | 实际samples / lost | CRC update | JSON record renderer | decimal native | jsonMember | reserve | begin |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ecore-async-memory-P1 | 1011 / 0 | 14.54% | 10.04% | 6.12% | 4.31% | 2.49% | 2.89% |
| ecore-async-memory-P4 | 2033 / 0 | 7.69% | 6.05% | 3.65% | 1.85% | 8.97% | 14.66% |
| ecore-spsc-memory-P4 | 1114 / 0 | 15.76% | 10.06% | 7.33% | 5.97% | 0.93% | 1.26% |
| ecore-spsc-mmap-P4 | 1161 / 0 | 15.32% | 10.29% | 5.98% | 5.62% | 0.60% | 0.67% |
| pcore-async-memory-P1 | 751 / 0 | 6.94% | 11.28% | 4.86% | 2.69% | 3.84% | 5.68% |
| pcore-async-memory-P4 | 1764 / 0 | 3.20% | 5.07% | 2.27% | 1.33% | 9.22% | 16.91% |
| pcore-spsc-memory-P4 | 1020 / 0 | 8.06% | 12.67% | 4.86% | 2.99% | 1.21% | <0.5% / 未入表 |
| pcore-spsc-mmap-P4 | 996 / 0 | 8.02% | 12.00% | 4.90% | 3.04% | 0.95% | 0.86% |

P1和SPSC P4中CRC与JSON/数字/属性名输出占比较高；shared P4的begin/submit/reserve协调成本更显著。占比来自单次约1K-2K采样，包含初始化/预热/关闭清理、不含kernel，不能换算成某优化的可达百分比，也不把binarylayout/宿主噪声当精确因果。

不同窗口与comm样本组保持原样；低于0.5%报告门限的符号不填零。raw perf数据从xz解压可复查，与捕获hash逐项一致，原始未压缩文件留在.zig-cache/current-workflow-profile/raw，不重复存大文件。
