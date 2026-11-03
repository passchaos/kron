# aarch64-linux-musl QEMU用户态执行

补充非x86架构的真实二进制执行证据。目标为`aarch64-linux-musl`静态二进制，通过host已注册的`qemu-aarch64` binfmt执行；这不是真实aarch64设备，也不覆盖Windows/macOS/Android/iOS。

## 身份

- 源码：提交`ad3cb1c`加一项test-only可移植性修正（见下）。
- root suite binary：`c9af09bbfafcfa21d6309c4cd2c57f17877db0336ac93b6d3c4cea33b636fc5b`，ELF ARM aarch64 static。
- fuzz binary：`794ab3376184dee13ddef4e72f1bb1302f1cfe4598f8fddb2c4d8e1d7932b746`。
- host binfmt：`/proc/sys/fs/binfmt_misc/qemu-aarch64` → `/usr/libexec/qemu-binfmt/aarch64-binfmt-P`。

## 构建与执行

```sh
zig test src/root.zig -target aarch64-linux-musl -O ReleaseSafe \
  -femit-bin=/tmp/kron-aarch64-tests

zig test -target aarch64-linux-musl -O ReleaseSafe --dep kron \
  -Mroot=tests/journal_fuzz.zig -Mkron=src/root.zig \
  -femit-bin=/tmp/kron-journal-fuzz-aarch64
```

root suite直接以`/tmp/kron-aarch64-tests`运行；fuzz binary对seed `0x1..0x14`逐次执行。

## 结果

- root suite：**455 passed、7 skipped、0 failed**（共462项）。原始输出见[root-suite.log](root-suite.log)。
- fuzz：20/20 seed通过，每个seed执行journal 20,000次随机操作/恢复与archive随机block round-trip，原始输出见[fuzz-20-seeds.log](fuzz-20-seeds.log)。

7项skip均为平台能力相关：

- x86 PCLMUL CRC oracle（aarch64不导入该asm）；
- io_uring rotation与4项LinuxUring probe/batch/fault/depth（qemu-user下不可用）；
- system local time cache（依赖本机zoneinfo/libc路径）。

## test-only修正

`platform.tsc_clock.test.invalid options and rejected capabilities remain explicit`原先假设`Capability.platform_supported`默认为true；aarch64上默认false，导致`rdtscp_unavailable`断言先被`unsupported_platform`拦截。修正为该test的两个capability显式设置`.platform_supported = true`，使rejection顺序与host无关。x86语义不变，生产代码未改。

## 边界

QEMU用户态执行不是真实aarch64硬件、设备驱动或掉电资格；没有运行Windows/macOS/Android/iOS，也没有覆盖被skip的io_uring、PCLMUL或system local time路径。没有性能测量或Foundation排名更新。整体“业界最佳”目标仍未完成。
