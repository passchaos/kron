# Shared async并发filter reload回归

新增shared async多producer与动态filter反复reload的端到端竞争测试，验证producer在filter切换期间不会丢失accepted/filtered结果，runtime健康计数与sink一致。

## 场景

- 位置：`tests/configuration_integration.zig`，build step `test-configurations`，纳入默认`test`。
- `Runtime.create`：`.submission=.asynchronous`、Memory journal、filter初始`info`、route为1MiB MemorySink。
- 4个OS线程通过event gate后，各自以`runtime.scoped("reload.concurrent")`提交500条info记录，共2000次尝试。
- 主线程执行20次`reloadFilter("warn"/"info")`交替，并在每次后`setLevel(.info)`。
- producer只接受`.accepted`或`.filtered`；其他结果立即失败。
- 线程join后`flush(.written)`、`shutdown(.drain)`。
- 断言：`accepted+filtered==2000`、producer计数等于`health.accepted`/`health.filtered`、`accepted==written`、`pending==0`、sink records==written。

## 结果

- `zig build test-configurations -Doptimize=ReleaseSafe`：**14/14 tests passed**。
- Debug：14/14；ReleaseFast：14/14。
- 独立Safe binary对seed `0x1..0xa`重复执行：10/10通过，每次14/14。
- 完整`test`：**65/65 steps、755/756 tests（1项local skip）**；`verify-local`结果见[verify-local.log](verify-local.log)。

日志见[safe.log](safe.log)、[debug.log](debug.log)、[fast.log](fast.log)、[seeds.log](seeds.log)与[test-full.log](test-full.log)。

## 边界

覆盖Memory journal、4 producer、20次filter reload与setLevel；没有mid-flight `shutdown`/route replacement、mmap recovery或crash/掉电。它补充动态filter与并发提交，不替代SIGKILL/child-VM/多文件系统资格。整体“业界最佳”目标仍未完成。
