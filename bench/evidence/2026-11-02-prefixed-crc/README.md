# CRC前缀与尾部实验：候选全部撤回

本轮没有保留生产CRC改动。原实现恢复到`97353ff`，默认CRC、三个校验点、v1/v2分段及恢复协议保持原状。保留公共managed完整流程的版本比较工具、Foundation配对资格、扩展的原分段CRC基准和所有正负结果。明确的性能目标仍是超过Foundation/logging + spdlog及Foundation/logging + tracing。

## 完整文件结果与撤回原因

基线为`97353ff`。首候选将20B header或44B header/schema前缀与payload首部拼成64B，再在同一轮PCLMUL中延续，仅做一次最终reduction；完整CRC和所有校验点保留。E-core shared Memory/Mmap、P1/P4、batch/sampled的80项试验核对8,080,000条JSON，只有Memory P4 batch的配对关闭吞吐取得本轮局部领先（1.024×）；P1没有稳定收益。数据在`ecore-workflow/`，源码在`first-candidate.patch`。

第二候选增加4/8字节尾部切片，160项shared inline/schema矩阵核对16,160,000条JSON。16组配对中位全部提高，11组通过至少5轮、两侧与配对比值spread≤10%、95%区间不跨1的门限；inline Memory P1/P4 batch配对为1.028×/1.048×，Mmap P4 batch为1.049×。这仍是当前五数值字段文件负载的局部结果。调用尾延迟大多不确定。数据在`ecore-tail-workflow/`，精确源码在`tail-candidate.patch`与`provenance.json`。

扩展CRC专项却发现第二候选在整块payload（64/256/512B）明显变慢：v1约1.26–1.59×原耗时，v2约1.26–1.33×。简单内联、缩小尾部helper、按payload对齐切换及仅改尾部的隔离控制也未消除所有负向值。因此撤回全部候选，不以某一完整负载的收益作为一般CRC优化资格。`primitive-results.json.xz`的初始schema控制把44B前缀一次update；后续`tail-primitive-results.json.xz`等明确保留原20B+24B+payload更新。初始控制不作为原生产v2的速度基线。全部配对checksum一致。

隔离控制的中间源码没有全部冻结，保留数据和binary哈希作为诊断；不作验收证据。首/第二候选的完整文件实验拥有精确补丁、逐文件生产源码哈希和冻结二进制哈希。所有慢值继续保留；较大的CRC原始数组以无损`.json.xz`保存，解压字节与原采集文件一致。

## 同轮Foundation对照

第二候选另完成两种CPU拓扑的完整160项矩阵，每种逐条核对16,160,000条JSON，总计32,320,000条。两个真实Foundation前端、kron async/SPSC、Memory/Mmap、P1/P4、batch/sampled、系统时钟、256槽/512B、64KiB portable file buffer、written flush→shutdown→cleanup；不请求设备durable。

| 窗口 | 对spdlog的16个配对 | 对tracing的16个配对 |
| --- | --- | --- |
| E-core | kron领先3、peer领先9、不确定4 | peer领先12、不确定4 |
| P-core | kron领先1、不确定15 | kron领先1、peer领先1、不确定14 |

原始数据与各指标分别见[E-core矩阵](../../cpp_reference/evidence/2026-11-02-prefixed-crc-ecore/README.md)和[P-core矩阵](../../cpp_reference/evidence/2026-11-02-prefixed-crc-pcore/README.md)。两个窗口均为`target_not_met_in_selected_cases`，没有证明同时超过两个前端。P-core多数配对受宿主波动影响。候选已撤回，不能把这些结果称为当前生产源码的新排名。

## 验证与后续路径

CRC首候选的native Debug/Safe/Fast各5/5，generic各4通过/1 native-only skip；v1/v2定向各16/16，包含1120组输入×两个版本的独立连续字节流oracle。第二候选同一CRC模块native/generic三优化级别通过，日志保留。它们只证明候选CRC等价，不证明性能或整库完成。

保留的配对工具按manifest验证所有请求组和每个repetition，缺组、重复轮次、格式变化、少于5轮或任一侧高噪声不能宣告领先；初始化、完整生命周期与p99/p99.9独立判定。两份冻结完整矩阵经新增组/轮次校验再验证，配对结果逐项未变，见`analyzer-revalidation.json`。`test-cpp-reference-report`包含12项配对/矩阵负向测试与原有输出、后端、初始化和Zig options检查，日志在`report-gate.log`。扩展后的原生产分段CRC benchmark运行结果在`retained-crc-bench.log`；不以它更新跨库排名。

本轮100万P4 shared基线profile核对1,001,000条JSON，约10K cpu_atom用户态cycle样本：submitSafeDestination 13.45%、begin 12.61%、reserve 10.67%、CRC update 9.50%。样本份额不是可叠加的提速预测。后续优先研究shared admission/配置资源的共享原子竞争，保留未reserve捕获、cut、关闭及旧配置生命周期的完整契约。profile和核对结果在`baseline-profile.txt`、`baseline-profile-result.json`。

复现完整文件版本比较：

```sh
python3 bench/cpp_reference/compare_versions.py \
  --before BEFORE --after AFTER --output-dir FRESH \
  --affinity 16,18,20,22,24,26 --events 100000 --repeats 5 --schema both
zig build test-cpp-reference-report -Doptimize=ReleaseSafe -j1 --summary all
zig build bench-crc -Doptimize=ReleaseFast -j1
```
