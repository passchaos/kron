# fd4e941与当前源码A/B：近期优化没有造成E-core回退

本页回答“最近添加的功能是否让kron变慢”。用同一`bench/main`负载对比`fd4e941`（较早基线）与当前源码，E-core 5次batch，P-core另做控制。它不是跨库排名；`bench/main`只核对自身accepted=written，没有独立JSON oracle。

## E-core结果

CPU 16/18/20/22/24/26（无SMT兄弟的物理核），100000事件+1000 warmup、256槽、512B record、file sink、portable：

| 配置 | fd4e941 | current | current/fd4e941 |
| --- | ---: | ---: | ---: |
| Memory P1 | 1.479M/s | 1.695M/s | **1.146×（+14.6%）** |
| Memory P4 | 1.419M/s | 1.586M/s | **1.118×（+11.8%）** |
| Mmap P1 | 1.487M/s | 1.656M/s | **1.114×（+11.4%）** |
| Mmap P4 | 1.403M/s | 1.505M/s | **1.072×（+7.2%）** |

四组中位均为当前源码更快；5次值范围没有跨越fd4e941中位。近期decimal、typed visitor、metadata、severity、memory/mmap init优化没有造成E-core回退。

## P-core控制

CPU 2/4/6/8/12/14，同一负载：

| 配置 | fd4e941 | current | current/fd4e941 | 观察 |
| --- | ---: | ---: | ---: | --- |
| Memory P1 | 2.000M/s | 2.099M/s | 1.049× | 当前略快 |
| Memory P4 | 2.055M/s | 2.015M/s | 0.980× | 当前略慢 |
| Mmap P1 | 2.037M/s | 1.636M/s | 0.803× | current 5次1.32–2.07M，噪声极大 |
| Mmap P4 | 1.956M/s | 2.123M/s | 1.085× | 当前略快 |

P-core窗口受宿主负载影响明显，Mmap P1出现大幅波动；不能把单个负向中位当作回归。E-core稳定窗口显示当前源码全面更快。

## 为什么E-core仍落后Foundation

A/B只比较kron自身。E-core上Foundation + spdlog/tracing仍更快，原因是：

- Foundation producer-format路径不做kron等价的journal CRC、reserve/validate、typed capture与consumer格式化。
- E-core profile中CRC 13.24%、encodeJson 10.94%、submitSafeDestination 8.60%、drainJournal 7.96%。
- 这是功能/可靠性成本与CPU拓扑差异，不是近期优化把kron变慢。

因此“最初kron比Foundation强”的印象主要来自P-core窗口和特定配置；E-core窗口从未证明全面领先。当前源码相对fd4e941是变快的，但相对Foundation在E-core仍落后。

## 复现

```sh
git archive fd4e941 | tar -x -C /tmp/kron-fd4e941
cd /tmp/kron-fd4e941
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/main.zig -O ReleaseFast -Mkron=src/root.zig -femit-bin=fd4e941-bench
# current
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/main.zig -O ReleaseFast -Mkron=src/root.zig -femit-bin=current-bench
# E-core
taskset -c 16,18,20,22,24,26 BINARY --mode=async --storage=memory --sink=file --backend=portable --events=100000 --warmup-events=1000 --producers=1 --max-record-bytes=512 --journal-slots=256 --work-dir=FRESH --output=json
```

原始E-core/P-core结果在`ecore-results.json`/`pcore-results.json`；源码与binary身份在provenance与source archive。
