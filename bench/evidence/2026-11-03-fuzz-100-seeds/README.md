# Journal/archive fuzz 100-seed扩展扫描

`test-journal-fuzz`已在默认`test`中运行，但状态页仍把“长期seed”列为缺口。本轮用同一源码冻结的ReleaseSafe fuzz binary对连续100个独立PRNG seed执行journal与archive随机回归，补充seed覆盖；这不是sanitizer、长时间 soak 或多平台资格。

## 身份

- 源码：提交`cebf759c20681c72457571625f42cce65bfc690d`。
- binary：`5d51455ceb9028889ccdac893810178a44d4b9be3491c859e26068269a44285c`。
- 构建：`zig test -O ReleaseSafe --dep kron -Mkroot=tests/journal_fuzz.zig -Mkron=src/root.zig -femit-bin=/tmp/kron-journal-fuzz`。
- 执行：`/tmp/kron-journal-fuzz --seed=0x1`到`--seed=0x64`，共100个seed。

## 覆盖

每个seed实际执行两个test：

- journal：8槽mmap journal上20,000次随机reserve/commit/peek/release，每5,000 ops以`recover=true`重开并核对已提交未释放记录、pending、writtenTarget与payload；结束时清空并断言无pending。
- archive：随机1..20条记录与message，经`CompressedArchiveSink`+`decodeBlock`逐block round-trip核对。

## 结果

- 100/100 seed通过，`All 2 tests passed`出现100次，`journal fuzz seed=0x...`出现100次。
- 0个失败；完整原始输出见[run.log](run.log)（500行，含每次seed与两个test的OK）。

## 边界

这是**进程内随机操作/恢复**的扩展seed扫描，不替代真实SIGKILL、子VM/物理掉电、多文件系统/设备或ASan/TSan/持续soak；每个test仍是20,000 ops，不是长时间运行。没有生产源码改动，不改变Foundation排名或测试计数。整体“业界最佳”目标仍未完成。
