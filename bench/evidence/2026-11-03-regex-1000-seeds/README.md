# Regex/predicate mutation fuzz 1000-seed扩展

`tests/regex_fuzz.zig`原先使用固定PRNG种子，runner seed不改变corpus。本轮把两个test的固定种子与`std.testing.random_seed`异或，使每次runner seed产生不同mutation corpus，并执行1000个seed。

## 身份

- 源码：提交`3d3cf40`加本轮test-only改动（未改生产src）。
- binary：`3bd220b5110273253e489f7935f8a38c49aea57a24b159f2908384c964ef9dce`。
- 构建：`zig test -O ReleaseSafe --dep kron -Mroot=tests/regex_fuzz.zig -Mkron=src/root.zig -femit-bin=/tmp/kron-regex-fuzz-seeded`。
- 执行：`--seed=0x1`到`--seed=0x3e8`，共1000个seed。

## 覆盖

每个seed执行两个test：

- byte regex mutation：8192次iteration，14个seed pattern的字节变异/截断，配合任意输入与owned fixed-budget状态检查。
- predicate parser mutation：8192次iteration，parser输入变异与成功值所有权检查。

## 结果

- **1000/1000 seed通过，0 failures**；每次`All 2 tests passed`。
- `zig build test-regex-fuzz`在ReleaseSafe、Debug、ReleaseFast各**2/2通过**。
- 原始结果见[run.log](run.log)，构建/运行摘要见[safe.log](safe.log)、[debug.log](debug.log)、[fast.log](fast.log)。

## 边界

该测试是进程内mutation corpus，不替代Python regex differential/equivalence、ASan/TSan、真实SIGKILL/掉电或多平台设备运行。整体“业界最佳”目标仍未完成。
