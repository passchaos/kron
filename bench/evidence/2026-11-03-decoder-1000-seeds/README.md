# Decoder mutation fuzz 1000-seed扫描

在200-seed扫描之后，用同一runner-seed-driven ReleaseSafe decoder fuzz binary扩展到1000个seed。

## 身份

- 源码：提交`943a5bc`（decoder fuzz改动已在`84d2ea7`；生产未改）。
- binary：`355e1e88bc24a9abc36ff1d506d2293f86a22af4e31acfde01811792f790c052`。
- 执行：`--seed=0x1`到`--seed=0x3e8`，共1000个seed。

## 覆盖

每个seed执行7个test：persistent Reader/legacy/current/schema fixtures、bounded decoder mutation、arbitrary malformed codec input、malformed deferred format writer错误边界。

## 结果

- **1000/1000 seed通过，0 failures**；每次`All 7 tests passed`。
- 200-seed阶段证据见[../2026-11-03-decoder-200-seeds/README.md](../2026-11-03-decoder-200-seeds/README.md)。
- 原始结果见[run.log](run.log)。

## 边界

bounded进程内mutation，不替代libFuzzer/ASan/TSan、真实SIGKILL/掉电、多文件系统或多平台设备。整体“业界最佳”目标仍未完成。
