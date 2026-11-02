# Decoder/version/schema fuzz重复campaign

对当前源码运行20次ReleaseSafe `test-fuzz`，每次由Zig build runner生成不同seed，全部exit 0。20个seed：

`0x13233000 0x2b2ca884 0x2d75437a 0x35cd8e40 0x398b99cd 0x4594baa0 0x52c7afdb 0x5978d191 0x64cbb89 0x70f1b077 0x77ba2d6d 0x861940d6 0xa18dde2d 0xae68945a 0xae805239 0xdeb0ae26 0xe29f1f14 0xe74cd506 0xec6d8a5a 0xf3bb4260`

每次日志包含：

- inline/reference/historical payload的truncation与mutation；
- schema structural rejections与valid definitions；
- persistent Reader多fixture、两次独立导出、原始字节不变。

日志中的`failed command`是Zig build对测试进程的诊断字样；对应step success、整个命令exit 0。原始`run-1.log`..`run-20.log`与`status.txt`保留。

## 边界

- 这是确定性smoke corpora的重复seed，不是长期sanitizer/coverage-guided fuzz。
- 没有覆盖物理掉电、多文件系统/设备或非Linux设备运行。
- 不替代完整ReleaseSafe门禁；该门禁当前为151/151 steps、642/643 tests passed（1 skipped）。
