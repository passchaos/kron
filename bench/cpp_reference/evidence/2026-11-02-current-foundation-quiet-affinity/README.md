# E-core quiet-affinity Foundation + spdlog对照：kron多数落后

这是当前源码`647e667`在**无SMT兄弟的物理核**（CPU 16/18/20/22/24/26；当前主机拓扑为单线程物理核，通常对应E-core）上的80项缩减同轮抽查，80项试验、8,080,000条JSON逐条核对。它不是默认`auto` P-core窗口的替代排名，而是暴露kron在不同CPU拓扑下的性能差异。

## 完整关闭吞吐中位

单位M条/s：

| 配置 | Foundation + spdlog | kron async | 比值 | 95%区间 | 比值spread | 资格 |
| --- | ---: | ---: | ---: | --- | ---: | --- |
| Memory P1 batch | 1.844 | 1.710 | 0.925 | 0.914..0.950 | 3.8% | spdlog领先约7.5%，达到门限 |
| Memory P1 sampled | 1.725 | 1.704 | 0.989 | 0.983..1.008 | 2.5% | inconclusive（区间跨1，接近持平） |
| Memory P4 batch | 2.232 | 1.617 | 0.724 | 0.661..0.762 | 14.0% | inconclusive（spdlog中位明显更高） |
| Memory P4 sampled | 2.194 | 1.579 | 0.737 | 0.698..0.760 | 8.5% | spdlog领先约26%，达到门限 |
| Mmap P1 batch | 2.054 | 1.730 | 0.838 | 0.825..0.856 | 3.8% | spdlog领先约16%，达到门限 |
| Mmap P1 sampled | 1.939 | 1.700 | 0.885 | 0.869..0.891 | 2.5% | spdlog领先约11.5%，达到门限 |
| Mmap P4 batch | 2.765 | 1.605 | 0.580 | 0.567..0.614 | 8.1% | spdlog领先约42%，达到门限 |
| Mmap P4 sampled | 3.425 | 1.614 | 0.478 | 0.451..0.533 | 17.1% | inconclusive（spdlog中位明显更高） |

除Memory P1 sampled接近持平、Memory P4 batch与Mmap P4 sampled因spread保持inconclusive外，其余5组均显示Foundation + spdlog领先；P4/Mmap差距尤其明显。

## 与P-core窗口的差异

默认`auto` P-core窗口（CPU 0/2/4/6/8/10）的Foundation + spdlog抽查曾显示kron中位多数更高，Memory P1 batch达到局部资格；同一源码在无SMT兄弟的物理核上则多数落后。tracing在相同E-core窗口也全面领先kron。

这说明当前kron的完整流程性能对CPU拓扑高度敏感：

- P-core窗口：kron的producer/consumer路径可与Foundation互有胜负。
- 单线程物理核/E-core窗口：tracing与spdlog的producer-format路径保持较高吞吐，kron的typed capture、journal reserve/CRC、后台consumer格式化与交付相对更慢。
- 需要分别profile两种拓扑的producer/consumer阶段，确认是调度、频率、缓存还是队列同步造成；不能只用单一P-core窗口宣称跨库领先。

本页不把E-core结果推广到P-core或服务器默认配置，也不更新跨库排名；完整200项矩阵应分别在P-core和E-core窗口重跑。

## E-core profile

在相同单线程物理核上以`cpu_atom/cycles/u`（1063 samples，排除kernel）profile kron managed async Memory P1 batch。自占前项：`Crc32.update` 13.24%、`encodeJsonWithAttributes` 10.94%、`submitSafeDestination` 8.60%、`drainJournal` 7.96%、`memcpyFast` 6.00%、`decimal.writeNative` 5.19%、`encodeSized` 4.67%、`quotedAscii` 4.44%、`jsonKey` 3.89%、`codec.measure` 3.69%、`Journal.reserve` 3.64%、`validateSlot` 2.89%。

CRC、journal reserve/validate、measure+encode的双遍历合计占显著比例；这些是kron结构化journal/恢复协议的一部分，Foundation + spdlog Memory入口没有等价的CRC/恢复工作。因此E-core差距不能简单归因于单一“慢函数”，也不能通过删除CRC或恢复边界来换取排名。后续应分别研究measure+encode重复遍历、E-core CRC实现和consumer格式化/调度；保留全部recovery、CRC与错误边界。原始`self.txt`/`run.log`与binary身份在`ecore-profile/`。

另在相同E-core上对`consumer_idle=sleep|spin`做5次batch对照：Memory P1中位1.670M→1.691M（+1.2%），P4 1.590M→1.584M（−0.4%）。spin没有改变整体量级，说明当前差距主要不是consumer唤醒策略；原始结果在`ecore-profile/idle-comparison.json`。

## 复现

```sh
python3 bench/cpp_reference/run.py \
  --output-dir bench/cpp_reference/evidence/2026-11-02-current-foundation-quiet-affinity \
  --libraries foundation,kron --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --kron-frontend managed --kron-modes async \
  --kron-storages memory,mmap --metadata full --affinity 16,18,20,22,24,26 --discard-artifacts
python3 bench/cpp_reference/analyze.py bench/cpp_reference/evidence/2026-11-02-current-foundation-quiet-affinity
```
