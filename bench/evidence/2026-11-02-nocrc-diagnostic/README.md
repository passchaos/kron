# 禁用CRC诊断：量化journal/CRC功能成本

**这是诊断，不是生产候选。** 在复制源码中同时关闭producer CRC写入与consumer CRC校验，用同一`bench/main`负载测量E-core吞吐，以量化journal/CRC占性能差距的比例。生产源码未修改，CRC/recovery契约保持不变。

## 改动

`nocrc-source.tar.xz`中的复制源码只做两处诊断改动：

- `Reservation.commit`写checksum 0，不再计算`slotChecksum`；
- `Journal.validateSlot`跳过checksum比较。

其余journal/reserve/commit/recovery代码不变。该二进制不能用于恢复或持久化资格。

## 结果

E-core CPU16/18/20/22/24/26，5次batch，100000事件+1000 warmup、256槽、512B、file sink、portable：

| 配置 | 当前生产 | 禁用CRC诊断 | 变化 |
| --- | ---: | ---: | ---: |
| Memory P1 | 1.669M/s | 2.108M/s | **+26.3%** |
| Memory P4 | 1.564M/s | 2.050M/s | **+31.1%** |

对照E-core完整矩阵中位：

- Foundation + spdlog Memory P1/P4：1.823/2.277M/s。
- Foundation + tracing Memory P1/P4：2.207/2.222M/s。

禁用CRC后kron Memory P1已高于spdlog、接近tracing；P4仍低于两个Foundation前端。

## 解读

- CRC producer计算+consumer校验是E-core差距的主要组成之一；关闭后吞吐提升约26%–31%。
- 这不是说应该删除CRC。CRC、generation、reserve/commit/recovery是kron可靠性契约的一部分；生产默认必须保留。
- 若未来提供memory-only的显式`verify_crc=false`快速模式，需要独立的API契约、默认值、错误/恢复边界和双拓扑证据；本轮没有实现。
- 该诊断也说明E-core差距不是单一consumer调度或writer调用问题；CRC是主要功能成本。

## 复现

```sh
git archive HEAD | tar -x -C /tmp/kron-nocrc
# apply the two documented CRC-disable edits
cd /tmp/kron-nocrc
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/main.zig \
  -O ReleaseFast -Mkron=src/root.zig -femit-bin=/tmp/kron-nocrc-bench
taskset -c 16,18,20,22,24,26 /tmp/kron-nocrc-bench \
  --mode=async --storage=memory --sink=file --backend=portable \
  --events=100000 --warmup-events=1000 --producers=1 \
  --max-record-bytes=512 --journal-slots=256 --work-dir=FRESH --output=json
```

原始10行在`results.json`；复制源码与binary身份在`nocrc-source.tar.xz`/`provenance.json`。
