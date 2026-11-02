# Memory-only CRC opt-out

**新增显式opt-in fast mode；默认仍保留CRC。** `MemoryQueueOptions.verify_crc=false`只对volatile memory queue生效：producer写checksum 0，consumer跳过slot CRC比较；mmap/可恢复journal返回`CrcRequiredForRecovery`。其他reserve/commit/generation/length/sequence/schema/recovery边界不变。

## 结果

生产build，E-core CPU16/18/20/22/24/26，5次batch，100000事件+1000 warmup、256槽、512B、file sink、portable：

| 配置 | 默认CRC | `--no-verify-crc` | 变化 |
| --- | ---: | ---: | ---: |
| Memory P1 | 1.653M/s | 1.984M/s | **+20.0%** |
| Memory P4 | 1.598M/s | 1.968M/s | **+23.1%** |

此前复制源码诊断关闭CRC得到+26.3%/+31.1%；本轮生产option的20%–23%受同一宿主窗口波动影响，但方向一致。

## 契约与边界

- 默认`verify_crc=true`，公开Memory queue、Logging outputs和SPSC memory保持原CRC行为。
- `verify_crc=false`不检测payload内存损坏或部分写入；只适合明确接受该风险的应用。
- mmap/file/recoverable journal拒绝该配置；durable/recovery边界不受影响。
- 新增测试：
  - memory journal在`verify_crc=false`下即使checksum字段被破坏也能交付记录；
  - 可恢复journal对`verify_crc=false`返回`CrcRequiredForRecovery`；
  - managed Logging async/SPSC memory在`verify_crc=false`下完成emit/flush/shutdown；
  - 默认CRC corruption测试继续通过。
- ReleaseSafe完整门禁151/151步骤、644/645项通过（1项系统local能力skip），见本目录`full-safe.log`。

## 复现

```sh
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/main.zig \
  -O ReleaseFast -Mkron=src/root.zig -femit-bin=.zig-cache/kron-fastmode-bench
taskset -c 16,18,20,22,24,26 .zig-cache/kron-fastmode-bench \
  --mode=async --storage=memory --sink=file --backend=portable \
  --events=100000 --warmup-events=1000 --producers=1 \
  --max-record-bytes=512 --journal-slots=256 --no-verify-crc \
  --work-dir=FRESH --output=json
```

原始10行在`results.json`；binary/build身份在`provenance.json`。
