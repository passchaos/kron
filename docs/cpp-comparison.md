# C++ 和 Foundation Logging 性能对照

当前源码`4447fe6`的Foundation/独立spdlog/kron同轮对照已完成140项试验、1414万条JSON核对。当前中位结果与资格在[完整工作流比较](cpp-full-workflow.md)页首和[当前源码证据](../bench/cpp_reference/evidence/2026-11-01-current-workflow/README.md)；Foundation使用其真实spdlog前端和Rust后台，不是独立spdlog替代实现。当前kron仍未全面超过该组合。

最新实测使用 spdlog 1.17.0、Quill 13.1.0、当前 kron，以及用户指定的 `~/robotics/onboard-monorepo/foundation/logging` C++ 前端与 Rust 后台。结果、完整流程分段和边界见 [完整工作流比较](cpp-full-workflow.md)。2026-11-01 主矩阵 260 个试验逐条确认 26,260,000 条日志；Foundation 原生默认格式另有 40 个试验、4,040,000 条日志。没有日志缺失或格式失败。

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
