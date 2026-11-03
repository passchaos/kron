# Concurrent shared producer delivery回归

新增端到端并发测试，覆盖shared async多producer同时admission/reserve/commit，consumer持续写出，直到全部accepted记录被written。该测试是test-only，不改变生产代码或性能默认。

## 场景

- 位置：`tests/async_storage.zig`，build step `test-async-storage`，纳入默认`test`。
- `Runtime.create`：`.submission=.asynchronous`、Memory queue `capacity=64`、`max_record_bytes=512`、`.overflow=.block`、`consumer_batches_per_queue=4`、MemorySink 512KiB。
- 4个OS线程同时通过gate释放后，各自以`runtime.scoped("concurrent")`提交250条记录（`producer` message + producer/index fields），共1000条。
- 线程join后`flush(.written)`与`shutdown(.drain)`；断言`accepted==written==1000`、`journal_pending==0`、sink records==1000。
- 同一测试执行2轮，增加不同调度交错。

## Mid-flight shutdown

新增第二个测试：4个producer线程循环`tryEmit`直到`rejected_closing`；主线程等待至少一条accepted后调用`shutdown(.drain)`。线程join后断言：

- producer累计accepted等于`health.accepted`；
- `health.accepted == health.written`、`journal_pending==0`、sink records==written；
- `health.state == .closed`；
- 至少一个producer观察到`rejected_closing`；
- 没有`dropped_full`或其他错误。

该测试执行2轮，覆盖shutdown与并发admission/queue blocking的竞争。

## 结果

- `zig build test-async-storage -Doptimize=ReleaseSafe`：**9/9 tests passed**。
- Debug：9/9；ReleaseFast：9/9。
- 独立Safe binary对seed `0x1..0x5`（delivery test）与`0x1..0xa`（shutdown test）重复执行：全部通过。
- 完整`test`：**65/65 steps、750/751 tests（1项local skip）**。
- `verify-local`：**159/159 steps、784/785 tests（1项local skip）**，`verify-local success`。

日志见[safe.log](safe.log)、[debug.log](debug.log)、[fast.log](fast.log)、[safe-build.log](safe-build.log)、[seeds.log](seeds.log)、[shutdown-safe.log](shutdown-safe.log)、[shutdown-debug.log](shutdown-debug.log)、[shutdown-fast.log](shutdown-fast.log)、[shutdown-seeds.log](shutdown-seeds.log)、[test-full.log](test-full.log)与[verify-local.log](verify-local.log)。

## 边界

覆盖Memory queue、共享async、固定4 producer、mid-flight `shutdown(.drain)`；没有mmap journal recovery、掉电或随机fuzz seed，也没有在mid-flight调用cut/reload。它补充多producer交付与关闭竞争，不替代SIGKILL/child-VM/多文件系统资格。整体“业界最佳”目标仍未完成。
