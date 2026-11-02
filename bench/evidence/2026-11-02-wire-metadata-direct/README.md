# JSON固定metadata scalar的直接tag写入

**本轮优化已保留。** 基线`ef7df1e`包含checked wire typed visitor与内联scalar渲染。候选只改`src/encoder/common.zig`中JSON固定metadata的五个scalar写出，不改wire协议、公开API、输出布局或任何分配/预算。

## 改动边界

`encodeJsonWithAttributes`原先用`valueInner(writer, .{ .timestamp_ns = event.timestamp_ns }, .json)`和四个`unsigned`临时union写出timestamp、session、sequence、route_mask、config_generation。该路径把`u64` metadata装进`Value.unsigned: u128`，再进入运行时union switch和宽整数decimal；JSON每条记录因此多出五次通用分派和u128 decimal实例。

候选改为直接调用内部`writeTaggedValue`，以comptime tag和原始`i64`/`u64` payload写出：

```zig
try writeTaggedValue(writer, .timestamp_ns, event.timestamp_ns, .json);
try writeTaggedValue(writer, .unsigned, event.session, .json);
try writeTaggedValue(writer, .unsigned, event.sequence, .json);
try writeTaggedValue(writer, .unsigned, event.route_mask, .json);
try writeTaggedValue(writer, .unsigned, event.config_generation, .json);
```

`writeTaggedValue`复用原JSON精度、quote、decimal和转义逻辑，只是跳过临时union、运行时tag switch和u64→u128扩大。text/logfmt metadata原本已经直接调用`decimal.write`，源码不变；公开encoder、融合renderer和全部错误边界不变。

## 正确性

- 普通encoder probe对json/text/logfmt的scalar5/nested20/wide5三种完整输出逐项比较checksum与bytes，30个PMU trial全部一致。
- `zig build test -Doptimize=Debug`与`-Doptimize=ReleaseFast`通过。
- ReleaseSafe完整门禁151/151步骤、640/641项通过（1项系统local能力skip），包含源码分发、九目标对象、真实SIGKILL、单线程、时间oracle与全部示例；日志中的compression/tsc诊断带Zig build的“failed command”字样，但对应step success、整个命令exit0。
- 完整PMU和workflow的每条物理JSON都由`bench/cpp_reference/run.py`核对：accepted=written、pending/drop=0、metadata/字段/序列/bytes一致。

## 普通encoder probe

30项交替PMU，每项包含300,000次scalar5/nested20/wide5编码、变动数值和完整输出hash；源码/二进制身份见`before-provenance.json`/`after-provenance.json`。

| 格式 | instructions | cycles | scalar5 ns/record | nested20 ns/record | wide5 ns/record |
| --- | ---: | ---: | ---: | ---: | ---: |
| JSON | −2.58% | −1.93% | −2.60% | −1.75% | −1.55% |
| text（控制组） | −0.09% | +3.52% | +3.80% | +3.84% | +1.81% |
| logfmt（控制组） | −0.01% | −1.79% | −3.68% | −1.73% | −0.13% |

JSON五组均CV/spread达标且中位区间不重叠。text/logfmt代码路径未改，其instruction基本持平而cycles/单case出现方向不同的波动；这些是binary layout与测量窗口的控制组结果，不据此宣称text/logfmt改善或退化。全部原始CSV/row和慢值在`encoder-trials/`、`encoder-results.jsonl`、`encoder-comparison.json`。

## 完整shared用户态工作量

40项完整shared真实文件试验核对1204万JSON，配置为Memory/Mmap P1/P4、batch、256槽/512B、64KiB file buffer、4服务量子、portable/written→shutdown→cleanup、CPU0/2/4/6/8/10；PMU包含初始化与清理、排除kernel。

| shared配置 | instructions before→after | 中位变化 | CV/spread | cycles |
| --- | ---: | ---: | --- | --- |
| Memory P1 | 2,529,397,513→2,467,545,112 | −2.445% | 达标、区间不重叠 | 区间重叠 |
| Memory P4 | 2,530,227,935→2,467,900,086 | −2.463% | 达标、区间不重叠 | 区间重叠 |
| Mmap P1 | 2,529,566,393→2,467,338,977 | −2.460% | 达标、区间不重叠 | 区间重叠 |
| Mmap P4 | 2,530,349,839→2,467,615,986 | −2.479% | 达标、区间不重叠 | 区间重叠 |

四组用户态instruction均稳定减少约2.45%–2.48%。同一PMU窗口的written速度：Memory P1 +1.42%（区间重叠）、Memory P4 +4.13%（区间不重叠）、Mmap P1 −1.06%（区间重叠）、Mmap P4 +3.48%（区间不重叠）；cycles全部区间重叠。该结果证明完整shared用户态工作量下降，不单独作为一般throughput/latency资格。

## 未插桩完整文件

80项正式workflow核对2408万JSON，包含producer、consumer JSON/实际文件、written flush、shutdown/destroy/cleanup。吞吐单位为M条/s，全部为正：

| shared配置 | before | after | 中位变化 | CV/spread / 中位区间 |
| --- | ---: | ---: | ---: | --- |
| Memory P1 batch | 2.383 | 2.406 | +0.95% | 达标 / 重叠 |
| Memory P1 sampled | 2.284 | 2.331 | +2.04% | 未达标 / 重叠 |
| Memory P4 batch | 2.353 | 2.434 | +3.44% | 达标 / 不重叠 |
| Memory P4 sampled | 2.339 | 2.426 | +3.74% | 达标 / 不重叠 |
| Mmap P1 batch | 2.400 | 2.428 | +1.16% | 达标 / 重叠 |
| Mmap P1 sampled | 2.227 | 2.350 | +5.55% | 未达标 / 重叠 |
| Mmap P4 batch | 2.353 | 2.467 | +4.84% | 达标 / 不重叠 |
| Mmap P4 sampled | 2.324 | 2.424 | +4.33% | 达标 / 重叠 |

六组达到本轮CV/spread门限；P4 batch的Memory/Mmap中位区间不重叠。sampled的p50基本持平（0.99–1.00），p99在Memory P4、Mmap P1/P4降低，p999多数降低但仍有区间重叠，不能承诺一般尾延迟。全部慢值、分位和阶段在`workflow-comparison.json`与`workflow-results.jsonl`。

## 采纳与复现

采纳依据是JSON encoder probe五组稳定减少、四组完整shared用户态instruction稳定减少约2.45%–2.48%、八组未插桩吞吐全为正且六组稳定，同时输出字节、错误顺序、公开API和全部门禁不变。text/logfmt控制组与cycles/tail的波动继续保留，不据此更新Foundation/spdlog/tracing排名，也不把局部百分比叠加到历史结果。

```sh
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseFast
zig build verify-local check-platforms test-package-distribution test-logging -Doptimize=ReleaseSafe -j1 --summary all
python3 bench/evidence/2026-11-02-wire-metadata-direct/encoder_compare.py
python3 bench/evidence/2026-11-02-wire-metadata-direct/measure.py --pmu --capture-name pmu
python3 bench/evidence/2026-11-02-wire-metadata-direct/measure.py --capture-name workflow
```

`before-provenance.json`固定`ef7df1e`源码与二进制，`after-provenance.json`固定候选；两个source archive保留拥有文件，不能用一个版本的CPU数据给另一个版本背书。脚本拒绝覆盖已有捕获，复跑前应复制到新的evidence目录或更换destination。
