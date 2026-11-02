# JSON整数一次写出：三个候选撤回

三个候选都保留整数精度、符号、全部i128/u128范围和失败前缀，但在普通encoder测量中出现稳定JSON负向，全部撤回。生产`decimal.zig`恢复`4dd574f`，`common.writeTaggedValue`恢复原JSON quote→decimal→quote顺序。该实验不影响当前CRC或wire版本。

第一版将native sign/magnitude和JSON safe-integer判断合并，剩余≥23B时small/large helper一次输出可选引号。短buf/stream/wide保留旧顺序，8项模块测试在Debug/Safe/Fast通过，包含40个最终typed边界fixture、全fixed容量与sentinel，以及多内部buffer×物理短写×失败预算的独立std formatter和原回调trace oracle。最终保留实现没有新增这个整数API。

三份各30项encoder对照使用同一member-only baseline，CPU30，每项scalar5/nested20/wide5各300000次，数值变化与完整输出Wyhash消费。三格式的每项checksum/bytes全部一致。较大的plain数字、u128 extrema和负号均包含，不能用scalar5的局部改善掩盖wide5回退。

| JSON candidate | instructions变化 | cycles变化 | scalar5耗时 | nested20耗时 | wide5耗时 |
| --- | ---: | ---: | ---: | ---: | ---: |
| native quoted/unquoted | 约+0.5% | 约+1.7% | 约+1.8%，不确定 | 约+1.0% | 约+3.4% |
| quoted-only | 约−1.1% | 约−0.1%，不确定 | 约−1.5% | 约−1.7% | 约+3.5% |
| inline入口/原wide顺序 | 约−0.6% | 约+1.1% | 约+1.7% | 约−1.1% | 约+4.5% |

text/logfmt控制存在正负变化，即使其对应分支没有引用新JSON入口；二进制布局与窗口身份保留，不归因于无关算法。JSON主要格式存在负向，未升级到完整file或Foundation排名。

初版、quoted-only、inline-wide完整src分别在`candidate-source.tar.xz`、`quoted-only-source.tar.xz`、`inline-wide-source.tar.xz`；`provenance.json`记录三个probe二进制hash，原始30项结果/CSV分别在根、`quoted-only/`、`inline-wide/`。`integer-wire-safe.log`核对融合与普通encoder一致及短错误边界。所有慢值继续保留；只能作为本轮候选否决证据。
