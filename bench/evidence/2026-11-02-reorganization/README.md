# 仓库结构整理验收

基线 `7e98358`。目标是让单一Logging入口、模块职责、测试位置及当前/历史文档清晰可维护，保留原有producer/consumer、恢复和所有权语义。源码hash与最终检查见 [qualification.json](qualification.json)。

## 变化

- Logging选项/前置校验、输出资源、owner与测试集中到 `src/logging/`，根公共名称保持。
- Runtime、codec与线程registry测试集中到 `src/core/tests/`，由所属模块test import纳入；87项具名test正文逐项一致，仅import位置/格式调整。
- codec与registry移除test段后的生产代码与基线完全一致；Runtime只调整test imports，Logging保留直接Runtime handles。
- `build/validation.zig` 归拢九目标生产对象与18示例入口，distribution包含新build支持，根examples入口与repo-relative source路径保持。
- README精简为接入/能力/导航，当前状态页与整体设计围绕实际接口和完整资格。旧设计/README/验收chronology保留 `docs/history/`，原冻结源码和evidence没有移动或改排名。
- 添加docs/code-structure/development及examples/tests/bench/tools索引，逐条检查文档链接。

## 验证

`zig build verify-local test-package-distribution -Doptimize=ReleaseSafe -j1 --summary all`：130/130步骤成功，582项通过，1项local缓存test在无libc根构建中按能力跳过。local专项与独立Python oracle实际运行通过。

根模块425通过/1skip，Logging定向27/27；实际Mmap、source位置和std.log示例运行通过。独立包/分发、单线程、Reader/编码/损坏矩阵、配置/deadline/文件故障、负向编译、12组随机ACK SIGKILL和18示例编译均通过完整gate。

最终九目标ReleaseSafe对象编译10/10步骤成功，原始结果见 `platforms-safe.log`；对象编译不代替设备运行。

## 范围

本轮没有新的完整性能或Foundation排名。稳定跨库/尾部与过载、Mmap启动和资源、业务/durable范围、长期fuzz/多文件系统故障及Windows/macOS/Android/iOS原生运行资格仍在 [当前验收页](../../../docs/implementation-status.md) 跟踪。历史快照和负向/未资格数据保留自己的源码身份。
