# 平台支持与能力边界

目标平台为 **Windows、Linux、macOS、Android 和 iOS**。当前文件、journal、时钟和线程接口使用共同公共 API；与操作系统相关的映射/预分配/同步实现分别位于 `src/platform/mapping/{linux,windows,darwin}.zig`。当前共享 journal 要求64位、小端目标；32位 journal 没有资格。

| 平台 | 文件与共享 journal 实现 | 文件后端/时钟 | 当前验证 |
| --- | --- | --- | --- |
| Linux x86_64/aarch64 | fallocate、MAP_SHARED、msync、file/dir fsync | portable，可选io_uring；NativeClock；x86_64可选TSC | x86_64真实单机运行/崩溃门禁；两架构公共调用路径ReleaseSafe对象编译 |
| Windows x86_64 | FileAllocationInformation、CreateFileMappingW/MapViewOfFile、FlushViewOfFile、文件flush | portable；标准库原生系统时钟fallback | 完整公共调用路径对象编译；Windows后端PE链接与KERNEL32/ntdll导入检查；独立 Zig 包消费应用 PE 链接；尚未运行真机 |
| macOS arm64/x86_64 | F_PREALLOCATE、MAP_SHARED、msync、fsync；strict durable额外F_FULLFSYNC | portable；标准库原生系统时钟fallback | 两架构实际公共路径Mach-O对象编译；尚未运行真机 |
| Android arm64/x86_64 | Linux映射实现；app可写文件系统路径 | portable；允许时可选io_uring；NativeClock | Android ABI公共调用路径对象编译；尚未设备运行 |
| iOS arm64/device与arm64/simulator | Darwin映射实现；app沙盒可写路径 | portable；标准库原生系统时钟fallback | device/simulator实际公共路径Mach-O对象编译；尚未设备运行 |

`zig build check-platforms -j1` 强制生成9个目标的实际对象，入口 `src/platform_check.zig` 会分析同步文件写入、静态时钟、filter reload、flush/deadline/shutdown、SPSC attach/emit/detach、schema-capable journal、恢复Reader。它比只检查声明覆盖更多实际路径，但**交叉编译不证明运行成功、系统调用可用或设备耐久性**。Apple app链接需要正常Xcode SDK/libSystem；Android app链接需要正常NDK/bionic，本机对象检查没有安装或替代这些SDK。

`kron.platform` 提供编译期 `target`、`synchronous`、`shared_journal`、`asynchronous`、`spsc`、`directory_durable_protocol`、`io_uring` 和 `tsc`。能力值表示实现存在；运行时磁盘、权限、内核、app沙盒或文件系统仍可返回明确错误。自动后端在io_uring不可用时选择portable。

## 同步与durable

各平台都将页同步与文件同步分开。mmap journal初始化与schema-ready通过普通文件发布协议完成；其accepted表示事件已完整提交到共享文件映射。内存异步的accepted只进入进程内queue。两者都不能替代设备断电的durable确认，详见 [异步存储](async-storage.md)。

Linux/Android strict durable执行msync、文件sync和父目录sync。Darwin strict durable进一步执行F_FULLFSYNC，若文件/目录不支持这一协议返回 `UnsupportedDurability`，不会降低为普通flush成功。Darwin预分配核对已分配块数，只申请差额，失败fallback重新核对，避免重开journal反复扩大实际磁盘保留。

Windows可以页flush与文件flush，但本实现没有可确认新建目录项耐久的等价协议，因此 `directory_durable_protocol=false`，文件sink/journal strict durable返回 `UnsupportedDurability`。同步written和普通mmap异步/进程崩溃恢复仍可使用。没有把FlushViewOfFile当作完整设备durable保证。

移动应用必须由宿主传入沙盒内路径；日志库不会请求额外权限或保证系统挂起时继续执行。应用需要在平台生命周期回调内显式flush/shutdown并处理结果。iOS保护文件在锁屏或系统挂起时可能不可访问；Android的内核策略可能拒绝io_uring，这些均通过实际I/O结果处理。

## 运行验证

```sh
zig build verify-local -Doptimize=ReleaseFast -j1
zig build test-single-threaded -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
zig build test-package test-package-single-threaded -Doptimize=ReleaseSafe -j1
zig build test-platform-host -Doptimize=ReleaseSafe -j1
```

独立 Zig 包消费项目实际运行五种模式的 Linux 结果与 Windows PE 链接证据位于 `bench/evidence/2026-10-31-package-consumer/`。测试驱动按宿主选择 Windows `.exe` 后缀；报告包含实际宿主、工具链和线程计数。仅 Linux 单线程运行使用 `/proc/self/task` 确认 OS 线程数，其他平台不会把缺少这一检查记作通过。源码归档接入另见 [Zig 包接入](package.md)。

单线程构建仅支持同步runtime；普通文件flush、durable能力与shutdown可用，timed控制返回 `TimedControlUnavailable`，async/SPSC初始化返回 `ThreadsUnavailable`。当前Linux可执行文件确认进程仅一个线程，初始化后提交/flush没有新增runtime分配。

Linux的SIGKILL与子QEMU停机证据继续有效于被测Linux配置；不可用作Windows/Apple/Android真机断电资格。后续各平台必须以设备运行、崩溃恢复、文件系统和生命周期测试补足运行证据。

## 可在目标设备运行的 Zig 自校验

独立消费应用的 `qualify DIRECTORY` 入口使用原生 Zig 校验五种提交模式、Unicode文件名、filter reload、初始化后runtime零分配、深拷贝/脱敏、普通与schema journal关闭重开、只读inspection、独占锁、轮转保留和实际durable能力。测试结果作为JSON返回；移动Zig宿主可直接调用同一 `platform.zig` 中的 `run(allocator, io, sandbox_directory)`，无需Python或子进程，接入见 [package.md](package.md)。

Linux ReleaseSafe 普通构建和single-threaded构建、普通ReleaseFast构建以及本地fetch源码包均实际通过；单线程报告仅包含sync模式。测试重复使用已有目录必须失败且保留原有输出，相关独立包测试通过。含自校验入口的Windows独立应用已实际PE链接通过。设备验收需要在设备上执行该入口并保存报告，不能用Linux自校验或Windows链接替代。当前主机没有Wine/Android设备与模拟器/Apple SDK或设备，因此尚未产生其他四平台的运行报告。
