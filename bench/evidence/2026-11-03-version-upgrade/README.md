# V1/V2 journal升级兼容回归

V3 schema journal保留后，新增真实v1/v2 journal的升级兼容回归，验证旧格式在当前V3源码下仍可读写和恢复，而不只测试`format`函数golden。

## 覆盖

- v1：`format.initialize`写version1、无schema extension；`Journal.create`；commit；slot CRC用`format.checksum`；`peekChecked`；释放前deinit；`recover=true`重开并核对payload。
- v2：先创建V3 seed，再用`format.initializeV2`+`schema.writeExtension`改写为version2；`Journal.create`走`validateV2`/`readLayout`；`registerSchema`；commit；slot CRC用`format.checksumV2`；`peekChecked`；释放前deinit；`recover=true`重开并核对payload。
- 断言包括实际header version 1/2、v1无schema时slot[32..64]为零、v2 schema引用参与CRC、reopen后`file_version`仍为1/2。

## 实际执行

- `zig test src/root.zig -O ReleaseSafe --test-filter 'v1 and v2 journals remain readable'`：16/16 tests通过（新case实际执行）。
- `zig build test -Doptimize=ReleaseSafe -j1 --summary all`：**65/65 steps、744/745 tests（1项local skip）**。
- `zig build verify-local -Doptimize=ReleaseSafe -j1 --summary all`：**159/159 steps、778/779 tests（1项local skip）**，`verify-local success`；含真实SIGKILL、schema/non-schema恢复、源码分发、单线程、工具和示例。

日志见[test.log](test.log)与[verify-local.log](verify-local.log)。测试源码为[../../../src/journal/schema_journal_tests.zig](../../../src/journal/schema_journal_tests.zig)。

## 边界

该回归验证v1/v2 journal在当前源码下的读写/恢复兼容，不替代旧二进制fixture、真实跨版本设备升级、掉电或多文件系统资格；V3仍是新schema journal默认格式。整体“业界最佳”目标仍未完成。
