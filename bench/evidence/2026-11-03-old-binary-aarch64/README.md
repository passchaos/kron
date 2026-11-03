# Pre-V3 aarch64旧二进制journal fixtures

在x86_64 pre-V3 fixtures之后，用同一提交`5b1fd7c`的旧源码交叉编译为aarch64-linux-musl，在QEMU用户态生成v1/v2 journal，并由当前x86_64 V3源码读取。补充跨架构旧二进制兼容证据。

## 生成身份

- 旧源码：`5b1fd7c` worktree（V3保留`52b6c16`之前的pre-V3生产源码）。
- 生成程序：[generate_v2_fixture_aarch64.zig](generate_v2_fixture_aarch64.zig)，在旧worktree的`src/`下以`zig build-exe -target aarch64-linux-musl -O ReleaseSafe`交叉编译，binary `f6d0a24212108b7f4744b6de6ce1f295b782f98ebdedd229682ff13af33a89de`。
- 执行：host已注册的`qemu-aarch64` binfmt；程序断言header version 1/2，写v1无schema与v2 schema+ordinary两条commit未release记录。
- 输出fixtures：
  - `tests/fixtures/journal/v1-old-binary-aarch64-5b1fd7c.journal` 4608B，`659676bbbfcc573418551148fbff6d4e3b901234e458e1244a980a7714e4cba6`。
  - `tests/fixtures/journal/v2-old-binary-aarch64-5b1fd7c.journal` 12544B，`f60c279748b66ea12cf7cb2e64315933bddbd7747c60075f9e4d7a1e4899b933`。
- payload带`aarch64`标记，v2 scope/message为`old.binary.v2`/`old registered event`。

## 当前源码验证

`src/journal/schema_journal_tests.zig`新增两个case，把aarch64 fixture复制到临时目录并以`recover=true`打开：

- v1：断言version1、`schema==null`、`schema_ref==null`，恢复`old binary aarch64 v1 payload`，release后无剩余。
- v2：断言version2，恢复schema与ordinary两条未release记录，`resolveSchema`核对旧scope/message，核对`old binary aarch64 v2 schema payload`/`old binary aarch64 v2 ordinary payload`后逐条release。

隔离执行`zig test src/root.zig -O ReleaseSafe --test-filter 'aarch64'`：17/17 tests通过（两个aarch64 fixture case实际执行）。

完整`test`：**65/65 steps、754/755 tests（1项local skip）**；`verify-local`：**159/159 steps、788/789 tests（1项local skip）**，`verify-local success`。日志见[test-full.log](test-full.log)与[verify-local.log](verify-local.log)。

## 边界

这是aarch64-linux-musl旧二进制在QEMU用户态写出的fixture，不是Windows/macOS/Android/iOS旧二进制或更早历史格式；也不替代真实SIGKILL/掉电/多文件系统。fixture是冻结输入，不应随当前源码格式变化重写。整体“业界最佳”目标仍未完成。
