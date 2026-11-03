# Decoder mutation fuzz runner-seed扫描

`tests/decoder_fuzz.zig`原先使用固定PRNG种子。本轮把三个test的固定种子与`std.testing.random_seed`异或，使runner seed改变mutation corpus，并执行200个seed。

## 身份

- 源码：提交`84d2ea7`加本轮test-only改动（未改生产src）。
- binary：`355e1e88bc24a9abc36ff1d506d2293f86a22af4e31acfde01811792f790c052`。
- 构建：`zig test -O ReleaseSafe --dep kron -Mroot=tests/decoder_fuzz.zig -Mkron=src/root.zig -femit-bin=/tmp/kron-decoder-fuzz-seeded`。
- 执行：`--seed=0x1`到`--seed=0xc8`，共200个seed。

## 覆盖

每次执行7个test，包括：

- `decoder_matrix`的persistent Reader/legacy/current/schema/version fixtures；
- bounded decoder mutation（4KiB原/变异/再编码，JSON/text/logfmt输出检查）；
- arbitrary malformed codec input（无分配拒绝）；
- malformed deferred format writer error boundary。

## 结果

- **200/200 seed通过，0 failures**；每次`All 7 tests passed`。
- `zig build test-fuzz`在ReleaseSafe、Debug、ReleaseFast各**7/7通过**。
- 原始结果见[run.log](run.log)，构建/运行摘要见[safe.log](safe.log)、[debug.log](debug.log)、[fast.log](fast.log)。

## 边界

进程内bounded mutation，不替代persistent libFuzzer/ASan/TSan、真实SIGKILL/掉电、多文件系统或多平台设备。整体“业界最佳”目标仍未完成。
