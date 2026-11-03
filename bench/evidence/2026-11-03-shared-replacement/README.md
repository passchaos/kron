# Shared async配置替换并发回归

新增shared async多producer与route/redaction反复替换的端到端竞争测试。替换通过`replaceConfiguration`执行，包含admission cut、旧configuration lease保留与collect，验证producer在替换期间仍保留全部accepted记录。

## 场景

- 位置：`tests/configuration_integration.zig`，build step `test-configurations`，纳入默认`test`。
- `Runtime.create`：`.submission=.asynchronous`、journal `capacity=8`、`max_record_bytes=4096`、`configuration_slots=4`、初始redaction mask `password`。
- 4个OS线程同时通过event gate后，各自以`runtime.scoped("replacement.concurrent")`提交500条记录（producer/record/password fields），共2000条。
- 主线程交替安装两个MemorySink route，并切换redaction `.mask`/`.drop`，共20次；每次`collectConfigurations()`，`ConfigSlotsExhausted`时先`flush(.written)`再collect重试。
- 替换结束后`flush(.written)`，join producers，再`flush(.written)`。
- 断言：producer累计accepted==2000、等于`health.accepted`与`health.written`；两个sink records之和==accepted；两个sink输出都不含`raw-hot-password`。

## 结果

- `zig build test-configurations -Doptimize=ReleaseSafe`：**13/13 tests passed**。
- Debug：13/13；ReleaseFast：13/13。
- 独立Safe binary对seed `0x1..0xa`重复执行：10/10通过，每次13/13。
- 完整`test`与`verify-local`结果见[test-full.log](test-full.log)与[verify-local.log](verify-local.log)。

日志见[safe.log](safe.log)、[debug.log](debug.log)、[fast.log](fast.log)、[seeds.log](seeds.log)。

## 边界

覆盖shared async、Memory journal、4 producer、20次route/redaction替换与admission cut；没有crash/掉电、mmap recovery或随机fuzz seed，也没有mid-flight `shutdown`（另有独立测试覆盖）。它补充配置替换与并发提交，不替代SIGKILL/child-VM/多文件系统资格。整体“业界最佳”目标仍未完成。
