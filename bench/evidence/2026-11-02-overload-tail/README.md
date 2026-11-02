# 慢sink过载尾部诊断

本页量化有界队列在慢consumer下的producer尾部延迟与过载策略差异。**这是合成慢sink诊断，不是产品吞吐排名。**

## 方法

- `probe.zig`使用公开`Runtime`：async Memory queue 64槽、512B record、单route。
- 自定义`SlowSink`在每个record中sleep 200µs，consumer最多约5000 records/s。
- 1000 events，P1/P4，block/drop_newest/fallback_sync各5次。
- CPU16/18/20/22/24/26（E-core），记录每次emit前后时间，报告p50/p99/max、accepted/written/dropped、total。
- 原始30行在`results.jsonl`；binary/source身份在`provenance.json`。

## 结果中位

| 策略 | 配置 | accepted | written | dropped | p50 | p99 | max | total |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| block | P1 | 1000 | 1000 | 0 | 283ns | 15.75ms | 16.06ms | 250.98ms |
| block | P4 | 1000 | 1000 | 0 | 595ns | 15.98ms | 96.70ms | 250.79ms |
| drop_newest | P1 | 64 | 64 | 936 | 149ns | 0.45µs | 7.98µs | 16.36ms |
| drop_newest | P4 | 64 | 64 | 936 | 152ns | 0.55µs | 7.97µs | 16.39ms |
| fallback_sync | P1 | 1000 | 1000 | 0 | 237.55µs | 1.48ms | 16.47ms | 251.57ms |
| fallback_sync | P4 | 1000 | 1000 | 0 | 253.96µs | 2.48ms | 157.73ms | 251.12ms |

P16（1600 events，16 producers）另测：

| 策略 | accepted | written | dropped | p50 | p99 | max | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| block | 1600 | 1600 | 0 | 759ns | 80.71ms | 264.30ms | 403.34ms |
| drop_newest | 65 | 65 | 1535 | 150ns | 2.56µs | 7.39µs | 16.56ms |
| fallback_sync | 1600 | 1600 | 0 | 254.23µs | 58.79ms | 342.64ms | 401.09ms |

## 解读

- **block**：无丢失，accepted=written=1000；但队列满后producer阻塞，p99约15–16ms，接近64槽×200µs的排队上界；P4 max受线程调度影响可到约97ms。
- **drop_newest**：producer p99保持在亚微秒级，但只保留consumer能处理的64条，936条被丢弃；适合可丢日志。
- **fallback_sync**：无丢失，但满队列时producer直接执行慢写，p50被推到约0.24–0.25ms，p99约1.5–2.5ms；P4 max可达约158ms。它把阻塞从队列等待转移到producer同步写。
- **P16**：block/fallback的p99升到约59–81ms、max到约264–343ms，说明阻塞尾部随producer数量放大；drop仍保持亚微秒级p99，但只保留65/1600条。
- 三种策略都正确完成flush/shutdown；high water均为64，说明队列上界生效。

## 边界

- 单一合成慢sink、固定200µs延迟、E-core；不代表真实磁盘、网络或业务负载。
- 没有测量durable介质、drop policy下的下游补偿或backpressure反馈。
- 该结果用于说明策略取舍：需要无丢失时，block/fallback的尾部成本必须被应用接受；需要低producer延迟时，应使用drop或更小的同步窗口。

## 复现

```sh
zig build-exe -O ReleaseFast --dep kron \
  -Mroot=bench/evidence/2026-11-02-overload-tail/probe.zig \
  -O ReleaseFast -Mkron=src/root.zig -femit-bin=.zig-cache/kron-overload-probe
python3 bench/evidence/2026-11-02-overload-tail/run_probe.py
```

`run_probe.py`拒绝覆盖已有捕获；复跑前复制到新的evidence目录。
