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

## Concurrent mmap journal

新增第三个测试：4个producer各提交100条记录到`capacity=64`的mmap journal（`.recover=true`，route `recovery_identity`显式设置），consumer写出到MemorySink。join后`flush(.written)`/`shutdown(.drain)`，断言`accepted==written==400`、`journal_pending==0`、sink records==400；随后`runtime.destroy()`释放journal锁，以同一路径`recover=true`重开，断言`pending()==0`且`peekChecked()==null`。

该测试覆盖shared MPSC reserve/commit、consumer release与mmap recovery路径在真实并发下的组合，不模拟crash或掉电。

## 结果

- `zig build test-async-storage -Doptimize=ReleaseSafe`：**10/10 tests passed**。
- Debug：10/10；ReleaseFast：10/10。
- 独立Safe binary对delivery/shutdown/mmap测试的`0x1..0xa` seed重复执行：全部通过。
- 完整`test`：**65/65 steps、751/752 tests（1项local skip）**。
- `verify-local`：**159/159 steps、785/786 tests（1项local skip）**，`verify-local success`。

日志见[safe.log](safe.log)、[debug.log](debug.log)、[fast.log](fast.log)、[safe-build.log](safe-build.log)、[seeds.log](seeds.log)、[shutdown-safe.log](shutdown-safe.log)、[shutdown-debug.log](shutdown-debug.log)、[shutdown-fast.log](shutdown-fast.log)、[shutdown-seeds.log](shutdown-seeds.log)、[mmap-safe.log](mmap-safe.log)、[mmap-debug.log](mmap-debug.log)、[mmap-fast.log](mmap-fast.log)、[mmap-seeds.log](mmap-seeds.log)、[test-full.log](test-full.log)与[verify-local.log](verify-local.log)。

## 边界

覆盖Memory queue、mmap clean reopen、共享async、固定4 producer、mid-flight `shutdown(.drain)`；没有crash/掉电、随机fuzz seed，也没有在mid-flight调用cut/reload。它补充多producer交付、关闭竞争与mmap并发，不替代SIGKILL/child-VM/多文件系统资格。整体“业界最佳”目标仍未完成。
