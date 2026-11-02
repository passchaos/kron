# 开发与验证

使用Zig 0.16，在仓库根运行命令。先选与修改相符的最小验证，复用 `.zig-cache` 与已有会话；涉及公共依赖、并发/lifetime、持久化格式、构建或发布时再运行相应组合门禁。

## 常用入口

| 修改范围 | 优先运行 |
| --- | --- |
| Logging配置/输出/所有权（含逐route队列） | `zig build test-logging test-outputs -Doptimize=ReleaseSafe -j1` |
| codec/字段/线程注册等模块 | `zig test src/root.zig -O ReleaseSafe --test-filter 'codec'`；用实际test名称选择子集 |
| source路径/文本位置 | `zig test src/root.zig -O ReleaseSafe --test-filter 'source'`；实际运行 `run-mmap` 和 `run-source-location` |
| 字段/context/对象适配 | `test-field-keys`、`test-capture`、`test-adapter`、`test-redaction-paths`、`test-compile-fail` |
| 内部提交参数与调用者快照 | `test-submission-snapshot`、`test-capture`、`test-redaction-paths`、prepared/binding 重点回归 |
| Memory/Mmap与背压 | `test-journal-progress`、`test-journal-peak`、`test-async-storage`、`test-integration`、相关Runtime queue regression |
| Journal槽位/generation坐标 | `test-journal-coordinates`；共享/SPSC八容量、完整序号/环回与有效CRC错误generation保留证据 |
| 配置和旧版本lifetime | `test-route-policies`、`test-configurations`、`test-transactions`、`test-route-filters`、`test-predicates` |
| TLS admission所有权与复用 | `test-admission-lifecycle`；相关 shared admission View、配置和deadline回归 |
| CRC原生数学与dispatch | `zig test src/platform/crc32.zig -O ReleaseSafe`；根筛选 `partial CRC stripes`，确认实际cases；native/无AVX PCLMUL/generic分别验证 |
| 时钟与时间转换/恢复 | `test-clock-dispatch`、`test-time`（固定偏移与Python oracle）、`test-local-time`（consumer与独立zoneinfo） |
| flush/deadline/关闭 | `test-deadline`、`test-single-threaded`、`test-integration` |
| 实际文件/轮转 | `test-file-delivery`、`test-platform-host`、对应sink模块测试 |
| wire/Reader/压缩 | `test-decoder-matrix`、`test-fuzz`、`test-query`、`test-compression` |
| 正则 | `test-regex-differential`、`test-regex-fuzz`、`test-regex-equivalence` |
| build/dependency/分发 | `test-package`、`test-package-single-threaded`、`test-package-distribution`、`check-platforms` |

表中build step统一加 `zig build ... -Doptimize=ReleaseSafe -j1`，平台对象检查内部固定ReleaseSafe。`--test-filter` 只是选择执行测试，不能把过滤后的通过计数描述为整库覆盖。

根测试可覆盖模块的相对import边界；直接把 `src/core/tests/` 文件作为独立根可能越过模块路径，优先从 `src/root.zig` 筛选。短纯模块可独立验证，例如 `zig test src/submit/source.zig`；有libc的系统时间测试使用 `zig test src/time/root.zig -lc`。

## 完整门禁

```sh
zig build verify-local test-package-distribution -Doptimize=ReleaseSafe -j1 --summary all
zig build check-platforms -j1 --summary all
```

verify-local包含根/公共集成、deadline/配置/文件、工具、compile-fail、版本/损坏矩阵、真实SIGKILL、随机ACK恢复、独立包/单线程与示例编译。源码分发单独在此命令选择。平台step生成九目标真实对象：Linux两架构、Windows、macOS两架构、Android两架构、iOS device/simulator；这些对象不代表设备运行。

Debug/ReleaseFast按变化影响补相关test；已有完整ReleaseSafe成功后，不为文档或日志记录变化重复全部故障campaign。单线程构建提供sync与普通flush/shutdown，timed/async返回明确能力错误。系统local专项显式链接平台libc，默认Linux根测试可按能力跳过local缓存测试；必须另确认专项oracle实际执行。

## 输出与运行检查

例子通常追加cwd中的文件，核对当前stdout对应的session，避免把其他会话/重复运行的尾部混作本次结果。源码路径以仓库根解析，line/column和调用点核对。text无外围引号，JSON保持合法source字符串。格式/日期/脱敏/编号可按同一事件比较多个输出。

运行示例是可逆接入检查，不替代崩溃/过载/durable测试；正常重开journal也不等于强杀或断电。工具只读导出应核验原文件未变。

## 性能与证据

遵循 [benchmark-methodology.md](benchmark-methodology.md)，记录source commit/hash、binary、工具链/优化级别、输入/预算/实际后端、时钟、重复次数、完整记录/结果oracle与所有完成阶段。local日期microbenchmark、CRC/采样等局部成本与完整日志/应用流程分开。

不将不同baseline百分比叠加成当前Foundation/spdlog排名。噪声超限保持inconclusive，原失败/慢值/负向、未完成trial和hardware/filesystem范围保留。性能验证主要入口见 [bench/](../bench/README.md)。

`docs/implementation-status.md` 只维护当前能力、最近有身份的gate与剩余优先级；详细chronology放 `docs/history/` 或对应evidence。冻结源码与原始evidence不随目录整理重写。新输出/格式行为在指南同步说明，package分发根/支持模块同步检查。

## 修改边界

变更前读拥有状态的源码，保留borrowed存储、stable writer地址、thread token、配置pins/lease、reservation/record ownership。仅为便于测试而公开私有实现会扩大API责任，应先选择模块边界或内部test import。

完成一个有验证的功能后提交；有remote时按用户偏好先拉取解决冲突，GitHub remote才推送。本地当前无remote时提交即形成可回溯版本。完整“业界最佳”目标只在对应性能、平台、故障和行为范围全部有证据后判定完成。
