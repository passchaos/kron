# Nested prepared + 轮转 + schema journal组合恢复回归

在v1/v2升级兼容与journal/archive fuzz之后，补齐状态页列出的`nested/轮转/版本升级组合`回归：同一条真实`Logging`管线同时使用prepared nested记录、rolling文件输出与mmap schema journal，并在durable shutdown后用同一journal重开、确认pending清零和schema replay。

## 覆盖

- 单个route：`rolling_file`输出（size轮转、retention 2、portable backend）、`.asynchronous`、JSON、`.mmap`队列（`capacity=8`、`schema_capacity=2`）。
- prepared shape：`logging.prepared(shape)`，顶层`child`为`field.group`（`region`/`attempt`）、`items`为`field.array`（unsigned + null）。
- 连续3条记录使用不同nested值与数组元素，`flushDurable`后`shutdown`；断言`written==3`。
- 关闭后读取active rolling文件，断言3行、nested `region`与`items`字节实际出现。
- 用同一mmap journal重新`Logging.create`，`flush()`后断言`journal_pending==0`；再次`prepared(shape)`写入第4条记录并shutdown，断言rolling文件追加为4行且新nested值出现。

该case验证prepared schema、rolling sink与mmap journal生命周期在同一owner下组合后仍可durable关闭和reopen/replay，而不只分别测试各组件。

## 实际执行

- `zig test src/root.zig -O ReleaseSafe --test-filter 'rolling mmap schema journal reopens and replays prepared nested records'`：17/17 tests通过（新case实际执行）。
- `zig build test -Doptimize=ReleaseSafe -j1 --summary all`：**65/65 steps、745/746 tests（1项local skip）**。
- `zig build verify-local -Doptimize=ReleaseSafe -j1 --summary all`：**159/159 steps、779/780 tests（1项local skip）**，`verify-local success`；含真实SIGKILL、schema/non-schema恢复、源码分发、单线程、工具和示例。

日志见[test.log](test.log)、[test-full.log](test-full.log)与[verify-local.log](verify-local.log)。测试源码为[../../../src/logging/tests.zig](../../../src/logging/tests.zig)。

## 边界

该回归是进程内durable shutdown后的同源码reopen/replay，不冒充SIGKILL、物理掉电或多文件系统/设备系统停机；v1/v2格式兼容由独立[schema journal升级回归](../2026-11-03-version-upgrade/README.md)覆盖，本case不引入旧二进制fixture。整体“业界最佳”目标仍未完成。
