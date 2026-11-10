# Pre-V3旧二进制journal fixtures

`v1-old-binary-5b1fd7c.journal`与`v2-old-binary-5b1fd7c.journal`由**提交`5b1fd7c`**（V3保留`52b6c16`之前的pre-V3生产源码）实际编译运行生成，而不是由当前源码的`format.initialize`/`initializeV2`回填header。另有`*-aarch64-*` fixtures由同一旧源码交叉编译为aarch64-linux-musl并在QEMU用户态执行生成。用于证明当前V3源码能读取旧二进制写出的v1 journal与v2 schema journal，以及其中已commit未release的待恢复记录。

## 生成身份

- 生成源码：`5b1fd7c` worktree，v1 `version=1`、v2 `schema_version=2`。
- x86_64生成程序：在该worktree的`src/`下临时创建`v2_fixture_gen.zig`，以`zig run src/v2_fixture_gen.zig`执行；使用`std.process.Init`的gpa/io。
- aarch64生成程序：同一`v2_fixture_gen.zig`以`zig build-exe -target aarch64-linux-musl -O ReleaseSafe`交叉编译，通过host `qemu-aarch64` binfmt执行；输出payload带`aarch64`标记。
- 两个journal均为`capacity=4`、`max_record_bytes=64`；v1 `schema_capacity=0`，v2 `schema_capacity=4`、`max_schema_bytes=1024`。
- v1：`reserve`并commit `"old binary [aarch64 ]v1 payload"`，不release，直接`deinit`。
- v2：先`registerSchema(.{ .scope = "old.binary.v2", .message = "old registered event" })`并commit schema payload；再`reserve`并commit ordinary payload；不release，直接`deinit`。
- 生成程序断言各自header version为1/2；`strings`可见`KRONJNL1`、v2的`KRONSCH1`、两条payload、`old.binary.v2`与message。

文件身份：

| fixture | 大小 | SHA-256 |
| --- | --- | --- |
| `v1-old-binary-5b1fd7c.journal` | 4608B | `ecc0fcd4767357c3f78fafa146a57c3fc30ed233e976c5ccb3779e9a184f0e44` |
| `v2-old-binary-5b1fd7c.journal` | 12544B | `fe0d12fdda2fb9133042c718d71bdc4f9e5fd20c465f3018d976d9d645f09704` |
| `v1-old-binary-aarch64-5b1fd7c.journal` | 4608B | `659676bbbfcc573418551148fbff6d4e3b901234e458e1244a980a7714e4cba6` |
| `v2-old-binary-aarch64-5b1fd7c.journal` | 12544B | `f60c279748b66ea12cf7cb2e64315933bddbd7747c60075f9e4d7a1e4899b933` |

原始 x86_64 fixture 文件在仓库历史中缺失；2026-11-10 用同一 `5b1fd7c` worktree
和本页生成程序重新生成。journal header 含随机 session identity，因此 SHA-256
与早先记录不同；header version、schema 布局和 payload 语义保持不变。

生成程序核心：

```zig
// v1
const v1 = try journal.Journal.create(init.gpa, init.io, .{
    .path = "v1-old-binary.journal",
    .capacity = 4,
    .max_record_bytes = 64,
    .schema_capacity = 0,
    .max_schema_bytes = 0,
});
var v1_reservation = try v1.reserve();
// commit "old binary v1 payload"; intentionally do not release
v1.deinit();

// v2
const v2 = try journal.Journal.create(init.gpa, init.io, .{
    .path = "v2-old-binary.journal",
    .capacity = 4,
    .max_record_bytes = 64,
    .schema_capacity = 4,
    .max_schema_bytes = 1024,
});
const reference = try v2.registerSchema(.{ .scope = "old.binary.v2", .message = "old registered event" });
var schema_reservation = try v2.reserveWithSchema(reference);
// commit schema payload, then commit an ordinary payload
// intentionally do not release either record
v2.deinit();
```

## 当前源码验证

`src/journal/schema_journal_tests.zig`中的fixture cases把文件复制到临时目录，以`recover=true`打开：

- x86_64 v1：断言header version为1、`schema == null`、`schema_ref == null`，恢复并核对`"old binary v1 payload"`，release后无剩余记录。
- x86_64 v2：断言header version为2，通过`peekChecked`恢复schema与ordinary两条未release记录；对schema record调用`resolveSchema`，断言旧二进制写入的scope/message；核对两条payload后逐条`release`。
- aarch64 v1/v2：同一断言与aarch64 payload；验证aarch64旧二进制写出的journal可由当前x86_64 V3源码读取。

隔离执行`zig test src/root.zig -O ReleaseSafe --test-filter 'aarch64'`：17/17 tests通过（两个aarch64 fixture case实际执行）；`--test-filter 'pre-V3 binary'`覆盖x86_64 fixtures。

## 边界

这些fixture覆盖真实pre-V3二进制写出的v1/v2 journal，包括aarch64旧二进制；不替代Windows/macOS/Android/iOS旧二进制、更早历史格式、真实SIGKILL/掉电或多文件系统/设备系统停机。fixture是冻结输入，不应随当前源码格式变化重写。
