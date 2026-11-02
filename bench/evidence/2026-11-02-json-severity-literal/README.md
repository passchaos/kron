# JSON severity固定字面量

**本轮优化已保留。** 基线`cf6cb5a`。JSON encoder此前每条记录写`,"severity":`，再对`@tagName(event.level)`执行`quoted`（ASCII扫描+三次writer调用）。候选把整个severity字段改为按Level枚举选择一个完整literal，一次`writeAll`写出。`err`仍输出`"err"`，text/logfmt路径和公开API不变。

## 正确性

- JSON golden与encoder probe三种格式的完整输出checksum/bytes一致。
- `err`、`fatal`等枚举拼写保持原`@tagName`输出，未改成`Level.label()`的`"error"`。
- Debug/ReleaseFast测试通过；ReleaseSafe完整门禁151/151步骤、641/642项通过（1项系统local能力skip）。

## 普通encoder probe

30项交替PMU，每项300,000次scalar5/nested20/wide5编码、变动数值与完整输出hash：

| 格式 | instructions | cycles | scalar5 ns/record | nested20 | wide5 |
| --- | ---: | ---: | ---: | ---: | ---: |
| JSON | −2.05% | −1.62% | −12.1% | +0.62% | −1.13% |
| text（控制组） | +0.01% | −0.39% | +0.71% | −1.26% | +0.65% |
| logfmt（控制组） | +0.00% | +1.00% | +3.12% | +0.45% | +1.12% |

JSON instructions CV/spread达标且中位区间不重叠；cycles与单个case的ns仍受噪声限制。text/logfmt代码未改，instruction持平，作为控制组。

## 完整shared用户态工作量

40项完整shared真实文件试验核对1204万JSON，Memory/Mmap P1/P4、batch、256槽/512B、64KiB file buffer、4服务量子、portable/written→shutdown→cleanup，CPU0/2/4/6/8/10。

| shared配置 | instructions before→after | 中位变化 | 资格 |
| --- | ---: | ---: | --- |
| Memory P1 | 2,467,837,735→2,425,969,032 | −1.697% | CV/spread达标、区间不重叠 |
| Memory P4 | 2,467,661,780→2,426,305,022 | −1.676% | 达标、区间不重叠 |
| Mmap P1 | 2,467,313,674→2,425,682,805 | −1.687% | 达标、区间不重叠 |
| Mmap P4 | 2,467,993,219→2,425,999,201 | −1.702% | 达标、区间不重叠 |

四组用户态instruction均稳定减少约1.68%–1.70%。80项未插桩workflow核对2408万JSON，吞吐正负混合（Memory P1 batch +6.35%、P4 sampled −5.91%、Mmap P1 batch −1.37%等），不能作为一般throughput/latency收益。

## 采纳与复现

采纳依据是JSON probe与四组完整shared instruction稳定减少、输出字节/错误顺序/公开API/全部门禁不变。workflow正负结果全部保留，不更新Foundation/tracing排名，也不叠加历史百分比。

```sh
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseFast
zig build verify-local check-platforms test-package-distribution test-logging -Doptimize=ReleaseSafe -j1 --summary all
python3 bench/evidence/2026-11-02-json-severity-literal/encoder_compare.py
python3 bench/evidence/2026-11-02-json-severity-literal/measure.py --pmu --capture-name pmu
python3 bench/evidence/2026-11-02-json-severity-literal/measure.py --capture-name workflow
```

`before-provenance.json`固定`cf6cb5a`源码/二进制，`after-provenance.json`固定候选；两个source archive保留拥有文件。脚本拒绝覆盖已有捕获。
