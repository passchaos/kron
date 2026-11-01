# 本地仓库复用评估

2026-10-31 调研 `~/project-z` 的 46 个主要仓库，排除临时 worktree、vendor 与 zig-pkg。先核对 README、实际 API、Zig 版本、依赖和存储语义，再决定复用范围。没有修改其他仓库，也没有把目标描述当作已经验证的性能成绩。

| 仓库/实际组件 | 对 kron 的用途 | 当前决定 |
| --- | --- | --- |
| Vort `src/checksum.zig` 的 `crc32Best`、`crc32UpdateBest`、`crc32Combine` | 校验 IEEE CRC32 的一次性、增量、分块和硬件实现兼容性 | 可选oracle；journal slot采用自有IEEE实现，native x86_64可选PCLMUL、其他目标portable slice-by-16，无Vort生产依赖 |
| ZKV `src/storage/faultable_device.zig` 的 `FaultableDevice(capacity,max_writes)` | 固定数组、volatile/durable 分离、写前缀持久化、失败 sync 与 crash，检查双 checkpoint 的更新协议 | 已加入可选持久化模型检查，直接使用实际模型和 kron 协议，无复制 |
| ZKV `src/storage/read_window.zig` 的 `Cache(slot_count)` | 固定窗口、borrow pin、positional/mmap 与增长尾部刷新 | 留给未来 kroncat 索引随机查询；当前顺序 consumer 无直接收益 |
| Netz `src/mqtt/persistence/{commit_log,durability}.zig` | 参考完整提交损坏与短尾部的区别，以及 file sync→replace→directory sync | 保留语义参考；kron 已有实现，整包依赖 vail/pbz/zio，不引入 |
| Zigraft `Impl/DynRef/DynMut` | 两指针 borrowed 动态视图与编译期接口契约 | kron 现有 sink vtable 已覆盖需要，引入收益不足 |
| MCAP 的 chunk、CRC、positional index/reference replay | 工具与归档索引设计参考 | 自有日志格式已有恢复与兼容协议；不改变 journal 为 MCAP，不引入整包 |

这些候选都声明 Zig 0.16。Zigraft、Netz 顶层提供 MIT 许可证；Vort、ZKV、MCAP、Hetu、Pangu、Alea、Zev 顶层未发现许可证文件。当前检查使用显式本地路径，默认构建和发布包不复制这些源码；正式采用生产依赖时再固定版本与发布授权。当前 package 的 `.dependencies` 仍为空。

没有找到比 kron 现有 io_uring 后端更合适的独立本地实现，也没有找到比标准库 arena 与现有流式 JSON encoder 更小的公共组件。Hetu 的只读整文件 mapping 不能替代日志所需的独占锁、空间预分配、共享可写映射与恢复协议；Zev 的通用 SIMD 包装不能直接替代 CRC 多项式折叠。Alea 的可复现 corpus 思路可参考，但现有标准库 PRNG 已满足测试要求。

## 实际验证

```sh
zig build check-local-reuse -Dvort-path=/home/passchaos/project-z/vort -Doptimize=ReleaseSafe -j1
zig build check-local-faults -Dzkv-path=/home/passchaos/project-z/zkv -Doptimize=ReleaseSafe -j1
```

Vort 检查通过 **416 组**不同长度/对齐输入，核对一次性 CRC、增量 update、combine、journal v1/v2 的完整校验范围及压缩归档头。当前 x86_64 编译选择 `hardware`。这证明被测实现与持久格式兼容，不证明完整日志性能提升。命令、源码 SHA256 与输出在 `bench/evidence/2026-10-31-local-reuse/checksum-interoperability.json`。

2026-11-01自有CRC改用16-byte slicing后，416组实际Vort互操作ReleaseSafe重新通过，日志与当前源码身份见 `bench/evidence/2026-11-01-crc-slicing16/`。随后native x86_64加入编译期PCLMUL folding，portable表继续作为通用/非x86/短输入路径；416组互操作再次通过并报告`backend=hardware`，见 `bench/evidence/2026-11-01-pclmul-crc/`。这证明持久格式兼容与primitive加速，完整日志吞吐仍须按同轮跨库测量判断，不能用互操作结果单独宣称整体领先。

ZKV 模型检查通过 **3,120 个持久前缀场景**及 **8 个非法边界场景**。覆盖双槽、空/旧有效目标、0–64 字节持久前缀、直接 crash/失败 sync 后 crash，以及 sequence/epoch 的进位与上界。新 checkpoint 的有效字段只有前20字节，后44字节为未变的零填充，因此前缀20起完整目标 entry 已一致，可以合法选择新边界；前缀0–19保持旧边界。测试使用实际 `journal/format.zig` 的编解码和 CRC，不能代表真实 mmap/fsync/物理断电，也不保证 CRC32 检出所有可能碰撞。

受控性能回归工具另见 [performance-regression.md](performance-regression.md)。同一二进制的20次自基线试验全部完成交付，但噪声超过阈值，结果为 `inconclusive`；原始报告归档于 `bench/evidence/2026-10-31-controlled-regression/`。
