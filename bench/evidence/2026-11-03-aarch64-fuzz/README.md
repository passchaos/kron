# aarch64 decoder/regex fuzz

在aarch64 root suite之外，交叉编译decoder与regex mutation fuzz为aarch64-linux-musl静态binary，并通过host `qemu-aarch64` binfmt执行，补充非x86格式/正则mutation覆盖。

## 身份

- 源码：提交`9bdd80bd36ee2bc15dccd7419e3b3a776afee78e`。
- decoder fuzz binary：`5c2b1c3d5e265da965ef87fd46880e2653d3ea4ca834cc984462e401ed554016`。
- regex fuzz binary：`631bc842873a318c15058d43182c53679564c50de1b2e2a627a25018a83383d6`。
- 构建：`zig test -target aarch64-linux-musl -O ReleaseSafe --dep kron -Mroot=tests/{decoder,regex}_fuzz.zig -Mkron=src/root.zig`。
- 执行：seed `0x1..0x14`，各20个。

## 结果

- decoder fuzz：20/20 seed通过，每个执行7个test（Reader fixtures + bounded decoder mutation + malformed input/format），**0 failures**。见[decoder-20.log](decoder-20.log)。
- regex fuzz：20/20 seed通过，每个执行2个test（byte regex mutation + predicate parser mutation），**0 failures**。见[regex-20.log](regex-20.log)。
- 构建输出见[decoder-build.log](decoder-build.log)与[regex-build.log](regex-build.log)。

## 边界

QEMU用户态执行不是真实aarch64设备；该扫描是进程内bounded mutation，不替代libFuzzer/ASan/TSan、SIGKILL/掉电或多平台设备。整体“业界最佳”目标仍未完成。
