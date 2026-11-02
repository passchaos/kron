# C++ 和 Foundation Logging 性能对照

当前驱动还支持`--libraries foundation,foundation_tracing,kron --kron-frontend managed`，直接使用Logging的public scoped/attached/prepared入口。默认`runtime`保留历史高级Runtime对照；managed SPSC采用实际默认spin策略，Runtime对照显式sleep，报告逐行记录consumer_idle。

性能验收目标是同时超过 Foundation/logging + spdlog 和 Foundation/logging + tracing。`analyze.py` 对新的公共 full JSON 报告生成 `foundation_qualification`：按 repetition 配对，不混合 Memory/Mmap、producer 数、batch/sampled 或 CPU 拓扑；至少5轮、两侧与配对比值 spread 均≤10%、95%配对bootstrap区间不跨1才判断该组领先。written flush/close、初始化、完整生命周期与调用 p99/p99.9 独立判定。缺少任一前端或任一选定组的配对不能宣告同时超过；关闭吞吐全部领先也只证明这次选定负载，其他性能轴仍需自己的证据。历史报告保留原统计结果，不批量重写。

最新双拓扑320项对照绑定已撤回的CRC候选：E-core对tracing 12组peer领先、对spdlog 9组peer领先/3组kron领先；P-core大多不确定，没有证明同时超过两个前端。CRC其他长度的负向成本使候选全部撤回，详见[完整正负实验](../bench/evidence/2026-11-02-prefixed-crc/README.md)。这些结果保留自己的源码身份，不是恢复后生产源码的新排名。

优化前后二进制可以用 `compare_versions.py --before BEFORE --after AFTER --output-dir FRESH --affinity CPU_LIST` 比较相同的 public managed 文件流程，`--schema both`覆盖v1/v2，`--perf cpu_core|cpu_atom`另外记录完整子进程PMU。每轮完整JSON独立核对，失败现场保留，成功后清理测试日志；统计比值大于1表示after更快。基准与资格测试纳入 `zig build test-cpp-reference-report`。

Foundation tracing的公共JSON对照使用真实Subscriber/fmt层、五个typed数值字段和公开TracingMakeWriter。标准`build_tracing`使用不同的优化写入器与文本格式，通过`--libraries foundation_tracing --metadata native_tracing`单列验证；这些文本数字与公共JSON不能直接作同输出格式排名。所有Foundation源码仅复制到基准目录，库源码不修改，Rust依赖由其Cargo.lock锁定。

本页主要保留历史对照的复现方式与当时结果。最新归档的完整Memory/Mmap同轮对照绑定源码 `e8bd353`，真实Foundation spdlog前端＋Rust后台与kron共200项试验、2020万条物理JSON核对，见 [详细报告](../bench/cpp_reference/evidence/2026-11-01-e8bd353-foundation/detailed-comparison.md)。下面的182fc9e、4447fe6和更早快照保持自己的身份，不作为整理后当前源码的新排名。所有性能入口见 [bench导航](../bench/README.md)。


文件后端可独立测量：`bench/cpp_reference/kron_reference.zig`新增`--backend=portable|linux_uring|auto`及实际后端报告，默认portable。`bench/cpp_reference/compare_backends.py`以同一程序比较两种后端，Memory/Mmap分开逐条核对完整文件。当前160项数据的io_uring中位慢约17%–19%，具体负载与资格见[io_uring证据](../bench/evidence/2026-11-01-uring-current/README.md)。此后端实验未运行Foundation，不用于更新其跨库排名。

此前按Memory/Mmap范围的同轮比较使用源码`182fc9e`默认consumer budget4，只运行Foundation/kron：120项完整文件试验、1212万条JSON全部核对。Memory下kron中位领先，Mmap单producer中位领先、四producer仍落后，波动与初始化/尾部限制见[当前Memory/Mmap证据](../bench/cpp_reference/evidence/2026-11-01-memory-mmap-current/README.md)。没有把更早对照或可选budget1与当前默认结果混合。

此前源码`4447fe6`的Foundation/独立spdlog/kron同轮对照已完成140项试验、1414万条JSON核对。该快照中位结果与资格在[完整工作流比较](cpp-full-workflow.md)页首和[当前源码证据](../bench/cpp_reference/evidence/2026-11-01-current-workflow/README.md)；Foundation使用其真实spdlog前端和Rust后台，不是独立spdlog替代实现。当前kron仍未全面超过该组合。

更早主矩阵使用 spdlog 1.17.0、Quill 13.1.0、当前 kron，以及用户指定的 `~/robotics/onboard-monorepo/foundation/logging` C++ 前端与 Rust 后台。结果、完整流程分段和边界见 [完整工作流比较](cpp-full-workflow.md)。2026-11-01 主矩阵 260 个试验逐条确认 26,260,000 条日志；Foundation 原生默认格式另有 40 个试验、4,040,000 条日志。没有日志缺失或格式失败。

```sh
python3 bench/cpp_reference/run.py \
  --deps-dir /tmp/kron-cpp-bench-deps \
  --output-dir /tmp/kron-cpp-workflow \
  --libraries spdlog,quill,foundation,kron \
  --foundation-root ~/robotics/onboard-monorepo/foundation/logging \
  --events 100000 --warmup 1000 --repeats 5 --producers 1,4 \
  --kron-storages memory,mmap --kron-schema both \
  --metadata full --affinity auto --discard-artifacts
python3 bench/cpp_reference/analyze.py /tmp/kron-cpp-workflow
```

`--libraries spdlog,quill,kron` 可在没有本地Foundation仓库时运行。参考库版本和归档SHA256固定在 `bench/cpp_reference/versions.json`；下载后核对哈希，记录编译include树、源码、二进制、编译器、CPU与文件系统。Foundation在输出目录冻结原始cpp/rust源码，以锁定Cargo依赖构建release静态core，再编译真实 `cpp/src/logger.cc` 和公开 `Logger.Native()` 前端；不修改其仓库。

主矩阵保持完整JSON字段布局、系统墙钟、5个u64字段、64KiB文件buffer、block策略和固定队列预算。分别运行有逐次计时的sampled进程，以及没有逐次计时的batch进程。所有记录在关闭后逐条解析验证ID、字段、完整newline与物理字节数。预热不进入稳态分母，初始化/预热/flush/shutdown/清理另行计时；full lifecycle包含库初始化与预热，不包含测试结束后的读回校验。

Foundation `--metadata default_text` 控制组保持它自身已优化的默认formatter，禁止与主矩阵混合排名：日志中仍有同样5个数字字段，但输出约175字节/条，主矩阵约299字节/条。控制组命令：

```sh
python3 bench/cpp_reference/run.py \
  --deps-dir /tmp/kron-cpp-bench-deps \
  --output-dir /tmp/foundation-default-workflow \
  --libraries foundation --events 100000 --warmup 1000 --repeats 5 \
  --producers 1,4 --metadata default_text --affinity auto
```

`--discard-artifacts` 只在试验逐条核验成功后清理输出，保留哈希和计数；失败现场保留。取消该选项可以保留全部日志文件，主矩阵总输出约8GB。任何超时或失败都是未完成数据，不能用部分成功行生成通过结论。单个试验有显式deadline，首次超时后该库后续场景不自动重试。

这些测试没有请求fsync/fdatasync或strict durable；written表示缓冲与在途写入完成，不能当作设备掉电安全。spdlog/Quill使用volatile队列；Foundation单mmap与kron mmap均有进程崩溃恢复，持久化格式、durable/checkpoint和路由契约不同。资源单位和隐藏库缓冲仍需结合报告比较，不能用不同可靠性排名替代性能解释。

## 历史试验

[2026-10-31证据](../bench/cpp_reference/evidence/2026-10-31/README.md) 使用 spdlog 1.12.0、Quill 9.0.0，仅输出C++消息/attributes，kron仍输出完整metadata；未固定affinity，只重复3次。因此历史表只能作为当时开发pilot，不能与当前统一完整JSON的实测混合比较。

原始历史batch中位records/s：spdlog P1/P4为1,288,942/803,928，Quill deferred为3,363,298/2,861,202，kron shared mmap为592,239/619,593。当前主矩阵同时更新了源码、版本、输出、计时终点、affinity和重复次数；新旧数字差异不能直接归因于某项优化。
