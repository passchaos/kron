# aarch64 fuzz 100-seed扫描

在20-seed aarch64 decoder/regex扫描之后，把aarch64 journal/archive、decoder与regex mutation fuzz扩展到100个seed。

## 身份

- 源码：提交`ebe9b868d624ad57f7436deeef73971f9f4552c3`。
- journal/archive fuzz binary：`794ab3376184dee13ddef4e72f1bb1302f1cfe4598f8fddb2c4d8e1d7932b746`。
- regex fuzz binary：`631bc842873a318c15058d43182c53679564c50de1b2e2a627a25018a83383d6`。
- decoder fuzz binary：`5c2b1c3d5e265da965ef87fd46880e2653d3ea4ca834cc984462e401ed554016`。
- 均为`aarch64-linux-musl`静态binary，通过host `qemu-aarch64` binfmt执行；seed `0x1..0x64`。

## 结果

- journal/archive：**100/100 seed通过，0 failures**；每个seed执行journal 20,000次随机操作/恢复与archive随机block round-trip。见[journal-100.log](journal-100.log)。
- regex/predicate：**100/100 seed通过，0 failures**；每个seed执行byte regex与predicate parser mutation。见[regex-100.log](regex-100.log)。
- decoder：**100/100 seed通过，0 failures**；每个seed执行7个test（Reader fixtures + bounded decoder mutation + malformed input/format）。见[decoder-100.log](decoder-100.log)。

## 边界

QEMU用户态执行不是真实aarch64设备；仍是进程内bounded mutation，不替代libFuzzer/ASan/TSan、SIGKILL/掉电或多平台设备。整体“业界最佳”目标仍未完成。
