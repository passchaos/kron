# Sanitizer工具诊断：Zig TSan与Valgrind Helgrind

尝试为并发测试补上ThreadSanitizer/Helgrind资格。结论：Zig 0.16的`-fsanitize-thread`没有instrument本项目的Zig代码；Valgrind Helgrind能检测C/普通数据竞争，但把Zig atomic load/store误报为race并在测试中abort。因此sanitizer覆盖仍是工具链限制，不是库代码结论。

## Zig ThreadSanitizer

- `zig build-exe -fsanitize-thread -lc -O Debug`可成功构建。
- 但生成binary没有`__tsan` runtime/symbols（`nm`为空），`ldd`也没有TSan库。
- 故意构造的race（两个线程对同一个`var x: u64`做`x += 1`，`tsan-race-test.zig`）运行后没有TSan报告。
- 结论：该工具链的`-fsanitize-thread`未instrument Zig代码，不能用于本项目资格。

原始输出见[tsan-run.log](tsan-run.log)。

## Valgrind Helgrind

- 下载并解包Ubuntu `valgrind 3.22.0`，`VALGRIND_LIB`指向解包`usr/libexec/valgrind`；host未安装。
- 对上面的故意race，Helgrind正确报告2个errors（证明工具本身可检测race）。
- 对`kron-async-storage`测试binary（10 tests，含delivery/shutdown/mmap并发）运行Helgrind：
  - 报告**1,630,113 errors / 463 contexts**，首项是`worker_sleeping.store`与`beginConfiguration` load等Zig atomic操作被当作race；
  - 随后在`schema.hash.update`附近以SIGABRT终止。
- 结论：Helgrind不识别Zig atomic/futex同步，误报量不可用；未加annotation/suppression前不能作为本项目race资格。

原始输出见[helgrind-async-storage.log](helgrind-async-storage.log)（约1MB）。

## 决策

- 不修改生产代码；不声称sanitizer通过。
- 文档中的“sanitizer/更长soak”缺口保持；未来需要支持Zig atomics的TSan/Helgrind注解或专门的Zig race工具。
- 现有并发/soak/崩溃证据仍有效，但不能替代race sanitizer。

## 边界

没有ASan、MSan、持续soak或真实设备资格；Helgrind的abort/误报不能解释为库中存在race。整体“业界最佳”目标仍未完成。
