# E-core完整JSON跨库矩阵

当前源码`c0b9706`（含JSON severity优化）在无SMT兄弟的物理核（CPU16/18/20/22/24/26）上的完整JSON同轮矩阵。160项试验、16,160,000条JSON逐条核对；另40项原生tracing文本控制、4,040,000条。它不是P-core排名的替代；E-core拓扑必须单独记录。

## 范围

`run.py`使用`--libraries foundation,foundation_tracing,kron`、`--kron-frontend managed`、`async,spsc`、Memory/Mmap、P1/P4、batch/sampled、5次重复、100000事件+1000 warmup、完整JSON metadata与系统墙钟、256队列槽、512B记录预算、64KiB file buffer、portable、written→shutdown→cleanup。所有JSON组accepted=written、pending/drop=0；源码、依赖、binary与affinity在`manifest.json`。

## 完整关闭吞吐中位

单位M条/s：

| 配置 | Foundation spdlog | Foundation tracing | kron async | kron SPSC |
| --- | ---: | ---: | ---: | ---: |
| Memory P1 batch | 1.823 | 2.207 | 1.773 | 1.847 |
| Memory P1 sampled | 1.725 | 2.026 | 1.774 | 1.842 |
| Memory P4 batch | 2.277 | 2.222 | 1.644 | 1.882 |
| Memory P4 sampled | 2.342 | 2.219 | 1.640 | 1.893 |
| Mmap P1 batch | 2.137 | 2.701 | 1.759 | 1.844 |
| Mmap P1 sampled | 1.934 | 2.423 | 1.790 | 1.838 |
| Mmap P4 batch | 2.901 | 3.246 | 1.668 | 1.901 |
| Mmap P4 sampled | 2.858 | 2.759 | 1.655 | 1.894 |

## 配对比值

kron/peer，同一重复5对bootstrap：

| kron模式 | 配置 | vs spdlog | 资格 | vs tracing | 资格 |
| --- | --- | ---: | --- | ---: | --- |
| async | Memory P1 batch | 1.002 | inconclusive | 0.809 | tracing领先 |
| async | Memory P1 sampled | 1.058 | 边界/inconclusive | 0.880 | tracing领先 |
| async | Memory P4 batch | 0.808 | spdlog领先 | 0.827 | tracing领先 |
| async | Memory P4 sampled | 0.762 | spdlog领先 | 0.813 | tracing领先 |
| async | Mmap P1 batch | 0.859 | spdlog领先 | 0.677 | tracing领先 |
| async | Mmap P1 sampled | 0.951 | inconclusive | 0.754 | tracing领先 |
| async | Mmap P4 batch | 0.646 | spdlog领先 | 0.586 | tracing领先 |
| async | Mmap P4 sampled | 0.652 | spdlog领先 | 0.687 | tracing领先 |
| SPSC | Memory P1 batch | 1.018 | 边界/inconclusive | 0.835 | tracing领先 |
| SPSC | Memory P1 sampled | 1.063 | kron略领先 | 0.914 | tracing领先 |
| SPSC | Memory P4 batch | 0.832 | spdlog领先 | 0.854 | tracing领先 |
| SPSC | Memory P4 sampled | 0.804 | spdlog领先 | 0.845 | tracing领先 |
| SPSC | Mmap P1 batch | 0.863 | spdlog领先 | 0.684 | tracing领先 |
| SPSC | Mmap P1 sampled | 0.951 | inconclusive | 0.755 | tracing领先 |
| SPSC | Mmap P4 batch | 0.646 | spdlog领先 | 0.586 | tracing领先 |
| SPSC | Mmap P4 sampled | 0.676 | spdlog领先 | 0.687 | tracing领先 |

大多数组spread达标、区间不跨1；具体spread与min/max在`analysis.json`。

## 结论

- E-core上Foundation + tracing在16个对照中全部领先kron async/SPSC；Foundation + spdlog在多数P4/Mmap组领先。
- kron async只在Memory P1 batch接近持平（1.002×），SPSC Memory P1 sampled略领先（1.063×）；其余组落后。
- SPSC比async在E-core提高约5%–15%，但不足以改变Foundation领先的结论。
- 这与P-core窗口（kron Memory P1 batch对spdlog 1.125×局部资格）不同；CPU拓扑是测量身份的一部分。
- 该矩阵不替代P-core或完整功能归一化比较；E-core上Foundation Memory前端没有kron等价journal/CRC/恢复工作，原始吞吐不是同契约排名。

## 原生tracing文本控制

`native/`为40项Foundation原生build_tracing文本控制，4,040,000条，单列不参与JSON排名：Memory P1 batch/sampled 1.537M/1.459M，P4 2.580M/2.765M；Mmap P1 0.867M/0.830M，P4 2.656M/2.666M。

## 复现

```sh
python3 bench/cpp_reference/run.py \
  --output-dir bench/cpp_reference/evidence/2026-11-02-managed-frontends-ecore-full \
  --libraries foundation,foundation_tracing,kron --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --kron-frontend managed --kron-modes async,spsc \
  --kron-storages memory,mmap --metadata full --affinity 16,18,20,22,24,26 --discard-artifacts
python3 bench/cpp_reference/analyze.py bench/cpp_reference/evidence/2026-11-02-managed-frontends-ecore-full
```
