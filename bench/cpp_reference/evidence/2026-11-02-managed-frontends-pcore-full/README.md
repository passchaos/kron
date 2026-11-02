# P-core完整JSON跨库矩阵：多数inconclusive

当前源码`c0b9706`在默认SMT P-core窗口（CPU0/2/4/6/8/10）的完整JSON同轮矩阵。160项试验、16,160,000条JSON逐条核对。宿主仍处高负载窗口；大多数组的spread超10%，本页只记录方向与资格，不建立稳定排名。

## 完整关闭吞吐中位

单位M条/s：

| 配置 | Foundation spdlog | Foundation tracing | kron async | kron SPSC |
| --- | ---: | ---: | ---: | ---: |
| Memory P1 batch | 2.080 | 2.497 | 2.265 | 2.425 |
| Memory P1 sampled | 1.933 | 2.487 | 2.174 | 2.241 |
| Memory P4 batch | 2.056 | 2.138 | 2.346 | 2.666 |
| Memory P4 sampled | 2.218 | 2.130 | 2.284 | 2.563 |
| Mmap P1 batch | 2.183 | 2.588 | 2.346 | 2.484 |
| Mmap P1 sampled | 1.853 | 2.474 | 2.272 | 2.018 |
| Mmap P4 batch | 2.407 | 2.454 | 2.369 | 2.640 |
| Mmap P4 sampled | 2.254 | 2.265 | 2.313 | 2.640 |

## 配对方向

| 对照 | 方向 | 资格 |
| --- | --- | --- |
| kron async vs spdlog | Memory P1/P4与Mmap P1中位多数≥1；Mmap P4 batch 0.983 | 全部inconclusive（spread 14%–57%） |
| kron async vs tracing | Memory P1 0.924/0.874，Memory P4 1.057/1.106；Mmap P1 0.891/0.915，Mmap P4 0.938/0.925 | 多数inconclusive；tracing在Memory P1/Mmap P1方向领先 |
| kron SPSC vs spdlog | 8组中位均≥1（1.091–1.211） | 全部inconclusive（spread 11%–78%） |
| kron SPSC vs tracing | Memory P1 0.957/0.942，Memory P4 1.193/1.204；Mmap P1 0.931/0.824，Mmap P4 1.056/1.164 | 多数inconclusive；方向混合 |

只有少数组（kron async Memory P4、tracing Memory P4、SPSC Mmap P4等）达到局部spread门限；配对比较仍因另一侧或比值spread保持inconclusive。

## 原生tracing文本控制

`native/`为40项Foundation原生build_tracing文本控制，4,040,000条，单列不参与JSON排名：Memory P1 batch/sampled 1.676M/1.608M，P4 2.637M/2.852M；Mmap P1 0.930M/0.861M，P4 2.271M/2.162M。该窗口同样受宿主负载影响，部分组inconclusive。

## 结论

- P-core窗口受宿主负载影响明显，不能用中位表替代稳定性资格。
- 方向上：kron async/SPSC对spdlog多数≥1；对tracing在Memory P1/Mmap P1落后、在P4部分领先；没有全面胜者。
- 与E-core完整矩阵（Foundation tracing 16/16领先）形成拓扑反差；CPU核心类型必须单独记录。
- 该矩阵不替代功能归一化比较，也不更新Foundation/tracing排名。

## 复现

```sh
python3 bench/cpp_reference/run.py \
  --output-dir bench/cpp_reference/evidence/2026-11-02-managed-frontends-pcore-full \
  --libraries foundation,foundation_tracing,kron --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --kron-frontend managed --kron-modes async,spsc \
  --kron-storages memory,mmap --metadata full --affinity 0,2,4,6,8,10 --discard-artifacts
python3 bench/cpp_reference/analyze.py bench/cpp_reference/evidence/2026-11-02-managed-frontends-pcore-full
```
