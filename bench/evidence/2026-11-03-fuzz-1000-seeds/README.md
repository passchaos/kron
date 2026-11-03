# Journal/archive fuzz 1000-seed扩展扫描

在100-seed扫描之后，用同一冻结ReleaseSafe fuzz binary对1000个连续PRNG seed执行journal与archive随机回归，进一步补充seed覆盖。仍是进程内随机操作，不是sanitizer、长时间soak或crash/power-loss资格。

## 身份

- 源码：提交`e8022826f303321d0b2e649246632ae1c497c9a7`。
- binary：`5d51455ceb9028889ccdac893810178a44d4b9be3491c859e26068269a44285c`（与100-seed扫描相同，生产源码未变）。
- 构建：`zig test -O ReleaseSafe --dep kron -Mroot=tests/journal_fuzz.zig -Mkron=src/root.zig -femit-bin=/tmp/kron-journal-fuzz-1000`。
- 执行：`--seed=0x1`到`--seed=0x3e8`，共1000个seed。

## 覆盖

每个seed实际执行两个test：

- journal：8槽mmap journal上20,000次随机reserve/commit/peek/release，每5,000 ops以`recover=true`重开并核对已提交未释放记录、pending、writtenTarget与payload。
- archive：随机1..20条记录与message，经`CompressedArchiveSink`+`decodeBlock`逐block round-trip核对。

## 结果

- **1000/1000 seed通过，0 failures**；每次`All 2 tests passed`。
- 原始结果见[run.log](run.log)，构建输出见[build.log](build.log)。

## 边界

这是同一冻结binary的重复进程执行，不是ASan/TSan、真实SIGKILL/掉电、多文件系统或设备运行；每个test仍是20,000 ops，不是长时间soak。它补充seed覆盖，不替代crash/power-loss资格。整体“业界最佳”目标仍未完成。
