# Zig 包接入

库的公共接口只提供 Zig API。消费项目通过 Zig 包依赖导入 `kron` 模块，使用自身的 allocator 和 `std.Io`；目标平台、优化级别与线程配置由应用构建传入。

在应用的 `build.zig.zon` 中加入本地依赖（路径相对于应用包）：

```zig
.dependencies = .{
    .kron = .{ .path = "../kron" },
},
```

应用的 `build.zig`：

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const single = b.option(bool, "single-threaded", "Use synchronous single-threaded logging") orelse false;
    const kron = b.dependency("kron", .{
        .target = target,
        .optimize = optimize,
        .@"single-threaded" = single,
    });
    const app = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single,
    });
    app.addImport("kron", kron.module("kron"));
    b.installArtifact(b.addExecutable(.{ .name = "app", .root_module = app }));
}
```

`b.dependency` 创建库模块；应用不需要编译或运行库自身的工具和测试。Android/Apple 目标的系统库依赖由模块表达，应用仍需正常平台工具链和沙盒内文件路径；平台编译与运行资格见 [platforms.md](platforms.md)。

## 应用生命周期

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .output = .{ .file = .{ .path = "app.jsonl", .backend = .portable } },
        .mode = .asynchronous,
        .format = .json,
    });
    defer logging.destroy();
    _ = try logging.scoped("app").tryEmit(.info, "started", .{ .version = @as(u32, 1) });
    try logging.shutdown();
}
```

`Logging` 管理全部配置输出和底层 Runtime 的资源，应用停止所有 logger/token 用户后显式 shutdown，再 destroy owner，最后清理应用 I/O 环境。关闭错误应由应用显式处理；`defer` 清理不是 durable 确认。Mmap 设置 `.queue = .{ .mmap = journal_options }`，两者恢复语义不同。全部参数、context/线程所有权与示例见 [详细使用指南](usage.md)。多输出和轮转也使用 Logging；自定义 sink 和跨代恢复等底层扩展仍可使用 Runtime，按 Runtime → sink 顺序销毁。

单线程消费项目使用 `-Dsingle-threaded=true`，Logging 使用默认 `.mode = .sync`，Runtime 使用 `.submission = .sync`，不配置异步队列。普通 flush/shutdown可用，异步/SPSC和带deadline的控制接口有明确能力错误。库模块和应用应传入一致线程配置。

系统本地时间是显式选项：Linux应用在 `b.dependency` 参数中加入 `.@"system-local-time" = true`，或在应用模块设置 `.link_libc=true`，再配置 `.timestamp=.{ .zone=.local }`。默认固定偏移路径不依赖libc。完整转换、缓存和恢复身份契约见 [时间文档](time.md#系统本地时间)。

## 独立消费项目验收

`tests/package_consumer/` 是完整的另一个 Zig 包，具有自己的 `build.zig`、`build.zig.zon` 和源文件，通过 `b.dependency("kron")` 导入库。`test-package`构建并实际运行sync、memory、mmap、SPSC-memory、SPSC-mmap，验证written/pending、文件数量、JSON字段、时间戳、源覆写快照和脱敏。`test-package-single-threaded`另构建单线程包，Linux验证只有一个OS线程，异步模式在创建文件前失败。

```sh
zig build test-package -Doptimize=ReleaseSafe -j1
zig build test-package-single-threaded -Doptimize=ReleaseSafe -j1
zig build test-package-distribution -Doptimize=ReleaseSafe -j1
```

`test-package-distribution` 按库 `build.zig.zon` 的 `.paths` 构造无生成缓存的源码目录，使用 Zig 0.16 的 `zig fetch` 生成内容寻址源码归档，再安全解包到独立目录。新消费项目仅依赖解包后的源码，实际运行同样五种模式。这样可以发现开发目录中存在、发布包中遗漏的模块。该门禁只使用本地临时目录，不发布包，也不访问网络。

本地目录fetch不会自动排除开发工作区的ignored文件。暂存检查按仓库的生成产物规则排除benchmark的`artifacts/`、可执行文件副本和缓存，并在解包后核对这些产物没有进入源码包；benchmark源码、可复现脚本和证据报告继续包含。曾发现约3.8GB本地测量产物使fetch在30秒超时，原始失败保留在`bench/evidence/2026-11-01-regex-active/platform-package.log`。

2026-10-31 的 ReleaseSafe 源码包验收五种模式全部通过；具体包哈希、二进制 SHA256、输出 SHA256 和各模式计数见 [distribution.json](../bench/evidence/2026-10-31-package-consumer/distribution.json)。工作区依赖及单线程消费也已通过。证据中的包哈希对应测试时的源码快照，文档或源码修改后应重新运行门禁生成新快照。

消费应用也可自行运行：

```sh
cd tests/package_consumer
zig build run -Doptimize=ReleaseSafe -- memory /tmp/kron-consumer-memory
zig build run -Doptimize=ReleaseSafe -Dsingle-threaded=true -- sync /tmp/kron-consumer-sync
```

测试驱动把生成缓存放在仓库统一 `.zig-cache`，消费fixture只保留源文件。报告记录宿主平台、实际 Zig 版本、源码文件 SHA256、二进制与输出 SHA256；源码分发模式另记录 Zig 包哈希与归档 SHA256。Windows独立消费项目生成PE并完成链接是构建证据；本机没有Windows/Apple/Android设备，不能把该链接结果描述为运行验证。

## 目标平台自校验

消费应用增加 `qualify DIRECTORY` 模式，使用自身的 allocator 和 `std.Io` 完成测试并输出 JSON 报告。运行期间不需要 Python 或子进程；`test-platform-host` 的 Python 驱动只负责编译、启动和记录结果。

```sh
zig build test-platform-host -Doptimize=ReleaseSafe -j1
cd tests/package_consumer
zig build run -Doptimize=ReleaseSafe -- qualify /tmp/kron-host-check
```

Windows 命令示例：

```powershell
.\kron-package-consumer.exe qualify C:\kron-host-check
```

路径应位于准备验证的可写磁盘上。测试只创建 `DIRECTORY/native-check`；已存在时返回错误，保留原有结果，不清理或覆写日志。生成的 Unicode 文件名、各模式输出、journal 与轮转归档可供人工检查。

Android/iOS 的 Zig 宿主可把 `tests/package_consumer/platform.zig` 作为测试模块编译，给它添加 `kron` import，并调用 `run(allocator, io, sandbox_directory)`。函数返回结构化 `Report`，宿主自行选择显示或保存方式。测试文件不属于生产公共 API，也不创建平台 GUI、C 接口或其他语言桥接。移动平台的文件路径和 `std.Io` 生命周期由宿主负责。

验收覆盖五种运行模式（单线程仅同步）、初始化后的 runtime 零分配、filter reload、字符串/nested快照、脱敏、flush/shutdown/deadline能力、Unicode文件路径、普通与schema journal独占锁/关闭重开/只读inspection、轮转保留和实际durable结果。报告中的 `confirmed` 表示同步协议调用成功，`unsupported` 是具体文件系统或平台能力拒绝；其他I/O错误使测试失败。关闭重开不等同强杀进程或掉电资格。
