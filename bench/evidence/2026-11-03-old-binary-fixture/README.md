# Pre-V3旧二进制v1/v2 journal fixture回归

V3保留后，新增由**真实pre-V3提交`5b1fd7c`**编译运行写出的v1与v2 journal fixtures，验证当前V3源码能读取旧二进制格式及已commit未release的待恢复记录，而不只依赖当前源码的`initialize`/`initializeV2`回填header。

## 覆盖

- v1 fixture：旧二进制`version=1`、`schema_capacity=0`，commit `"old binary v1 payload"`后不release退出。当前源码`recover=true`打开后断言version1、`schema==null`、`schema_ref==null`，恢复payload并release至空。
- v2 fixture：旧二进制`schema_version=2`、`schema_capacity=4`，`registerSchema`写入`old.binary.v2`/`old registered event`并commit schema payload，再commit ordinary payload，均不release。当前源码恢复两条记录，`resolveSchema`断言旧scope/message，核对两条payload并逐条release。
- fixture是冻结输入：v1 4608B、v2 12544B；SHA-256与生成程序见[fixture README](../../../tests/fixtures/journal/README.md)。

## 实际执行

- `zig test src/root.zig -O ReleaseSafe --test-filter 'pre-V3 binary'`：17/17 tests通过（v1/v2两个fixture case实际执行）。
- `zig build test -Doptimize=ReleaseSafe -j1 --summary all`：**65/65 steps、747/748 tests（1项local skip）**。
- `zig build verify-local -Doptimize=ReleaseSafe -j1 --summary all`：**159/159 steps、781/782 tests（1项local skip）**，`verify-local success`；含真实SIGKILL、schema/non-schema恢复、源码分发、单线程、工具和示例。

日志见[test.log](test.log)、[test-full.log](test-full.log)与[verify-local.log](verify-local.log)。测试源码为[../../../src/journal/schema_journal_tests.zig](../../../src/journal/schema_journal_tests.zig)。

## 边界

fixture覆盖真实pre-V3二进制写出的v1/v2 journal，不替代跨平台旧二进制、更早历史格式、真实SIGKILL/掉电或多文件系统/设备系统停机。fixture不应随当前源码格式变化重写；整体“业界最佳”目标仍未完成。
