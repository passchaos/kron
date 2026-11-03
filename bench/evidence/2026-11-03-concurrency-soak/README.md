# 并发测试重复soak

在host高负载窗口下重复执行并发端到端测试，补充“长期seed/soak”覆盖。仅验证正确性，不做性能或设备资格。

## 身份

- 源码：提交`615b2becd9f759bfe7c3946f61aefb8dd4eb0c54`。
- async storage binary：`0ee8abc92580a0f536f454979096b82f818e9d8386b70bae2991c50ee96351a3`，ReleaseSafe，10 tests（delivery/shutdown/mmap并发）。
- configuration binary：`f1221e0c07ca5d5c83462003aeee55a60bda6e4f5015f0a86bf4bfa826b856eb`，ReleaseSafe，13 tests（含shared async replacement）。

## 执行

```sh
for i in $(seq 1 1000); do
  /tmp/kron-async-storage-mmap --seed=$(printf '0x%x' $i) || echo "FAIL seed=$i"
done

for i in $(seq 1 200); do
  /tmp/kron-config-shared --seed=$(printf '0x%x' $i) || echo "FAIL seed=$i"
done
```

## 结果

- async storage：**1000 iterations、0 failures**；每次执行10 tests，其中delivery/shutdown/mmap各2轮并发。
- configuration replacement：**200 iterations、0 failures**；每次执行13 tests，含4 producer×500记录与20次route/redaction替换。
- 原始结果见[async-storage-1000.log](async-storage-1000.log)与[configuration-200.log](configuration-200.log)。

## 边界

这是同一冻结binary的重复进程执行，不是ASan/TSan、真实SIGKILL/掉电、多文件系统或设备运行；host load约124，调度交错丰富但结果只证明未观察到失败。它补充长期seed/soak的一部分，不替代crash/power-loss资格。整体“业界最佳”目标仍未完成。
