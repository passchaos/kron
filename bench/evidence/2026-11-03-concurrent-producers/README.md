# Concurrent shared producer delivery回归

新增端到端并发测试，覆盖shared async多producer同时admission/reserve/commit，consumer持续写出，直到全部accepted记录被written。该测试是test-only，不改变生产代码或性能默认。

## 场景

- 位置：`tests/async_storage.zig`，build step `test-async-storage`，纳入默认`test`。
- `Runtime.create`：`.submission=.asynchronous`、Memory queue `capacity=64`、`max_record_bytes=512`、`.overflow=.block`、`consumer_batches_per_queue=4`、MemorySink 512KiB。
- 4个OS线程同时通过gate释放后，各自以`runtime.scoped("concurrent")`提交250条记录（`producer` message + producer/index fields），共1000条。
- 线程join后`flush(.written)`与`shutdown(.drain)`；断言`accepted==written==1000`、`journal_pending==0`、sink records==1000。
- 同一测试执行2轮，增加不同调度交错。

## 结果

- `zig build test-async-storage -Doptimize=ReleaseSafe`：**8/8 tests passed**。
- Debug：8/8；ReleaseFast：8/8。
- 独立Safe binary对seed `0x1..0x5`重复执行：**5/5通过**，每次8/8。
- 完整`test`：**65/65 steps、749/750 tests（1项local skip）**。

日志见[safe.log](safe.log)、[debug.log](debug.log)、[fast.log](fast.log)、[safe-build.log](safe-build.log)、[seeds.log](seeds.log)与[test-full.log](test-full.log)。

## 边界

该测试只覆盖Memory queue、共享async、固定4 producer/1000 record、无mid-flight close/cut、无mmap journal recovery或掉电；调度交错由OS决定但不作为随机fuzz seed。它补充的是多producer端到端交付，不替代SIGKILL/child-VM/多文件系统资格。整体“业界最佳”目标仍未完成。
