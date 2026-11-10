# Journal/archive 随机fuzz门禁

新增 `tests/journal_fuzz.zig` 与 `test-journal-fuzz`，补充持续fuzz维度；不改变生产源码、格式或默认CRC。

## 覆盖

- Journal：8槽、64B record、mmap文件；20,000次随机reserve/commit/peek/release；随机0..64B payload；每5000 ops deinit并`recover=true`重开，逐条核对已提交未释放记录、pending、writtenTarget和payload。
- Archive：随机1..20条记录、随机1..48B message；`CompressedArchiveSink` + `MemorySink` + `compression.decodeBlock`，逐block用`encoder.binary`/`codec.decode`核对sequence/message/字段。
- 失败时打印`journal fuzz seed=0x...`/`archive fuzz seed=0x...`，可用同一test runner seed复现。

## 实际执行

`zig build test-journal-fuzz -Doptimize=ReleaseSafe -j1 --summary all`连续5个随机seed：

| run | seed | summary |
| --- | --- | --- |
| 1 | `0xff1336e4` | 3/3 steps; 2/2 tests |
| 2 | `0x7fca6226` | 3/3 steps; 2/2 tests |
| 3 | `0x78e24c62` | 3/3 steps; 2/2 tests |
| 4 | `0xd0aa6dda` | 3/3 steps; 2/2 tests |
| 5 | `0x46aa35cc` | 3/3 steps; 2/2 tests |

另以`-Doptimize=Debug`和`-Doptimize=ReleaseFast`各实际执行2/2 tests通过。完整`zig build verify-local -Doptimize=ReleaseSafe -j1 --summary all`实际通过**159/159 steps、777/778 tests（1项local skip）**，`verify-local success`；日志见[verify-local.log](verify-local.log)。测试runner对fuzz step仍打印cosmetic `failed command`行；build summary与exit status确认成功。

## 边界

这是进程内随机操作/恢复与archive round-trip，不是真实SIGKILL、系统掉电、多文件系统或设备资格；journal fuzz的随机模型只覆盖已提交未释放记录和重开recovery，不替代现有crash/power-loss campaign。`test-journal-fuzz`已纳入默认`test` step，`verify-local`会实际执行。

日志见同目录`run-*.log`；源码为[../../../tests/journal_fuzz.zig](../../../tests/journal_fuzz.zig)与[build.zig](../../../build.zig)。整体“业界最佳”目标仍未完成。
