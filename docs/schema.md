# Persistent schema 与预注册 logger

普通 v1 journal 每条事件自包含。显式设置 `Journal.Options.schema_capacity > 0` 时启用 v2：数据槽仍从 offset 4096 开始，固定 metadata 表追加在文件尾部。字段名、格式串、scope 和 source 保存一次；引用事件只复制动态值、trace 信息、路由决策和序号。

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .submission = .asynchronous,
    .journal = .{
        .path = "app.journal", .capacity = 256, .max_record_bytes = 4096,
        .schema_capacity = 64, .max_schema_bytes = 4096,
    },
    .routes = routes,
});
const binding = try runtime.prewarmSchema(.{
    .level = .info, .scope = "http", .message = "request {d}",
    .message_template = true, .timestamp_ns = 0,
    .format_args = &.{kron.kv("0", @as(u64, 1))},
    .fields = &.{kron.kv("status", @as(u16, 200))},
});
const log = try runtime.loggerWithSchema(binding);
_ = try log.tryLogf(.info, "request {d}", .{@as(u64, 42)}, .{ .status = @as(u16, 201) });
```

SPSC 使用 `prewarmThreadSchema(channel, example)` 与
`threadLoggerWithSchema(attached, binding)`，保留原 attachment 的 cookie、generation
和线程约束。可运行例子见 [prepared.zig](../examples/prepared.zig)。

## 注册与热路径

prewarm 是显式冷路径：生成 canonical metadata，查重、提交定义并同步文件，再发布进程内 ready 标志。准备好的 logger 直接使用稳定引用，不在每条事件上重新注册、解析或同步 schema。

普通 prewarm 从例子推断当前 captured value kind。`schema_site.metadata` 与 `Runtime.prewarmFormat` 根据 comptime Args/Fields 类型生成完整 kind mask，optional 包含 null，Value 可覆盖已知类型；`prewarmMetadata` 在注册前变换固定 redaction 的 drop/mask 形状。字段名/顺序、格式串或 source 改变时返回 `SchemaMismatch`，不会静默退化或生成新 schema。

schema 不保存示例值，redaction 在 metadata 与动态捕获之前生效。动态字符串仍在调用返回前复制到 journal。预注册与普通 logger 共享 filter、sampling、context 覆盖、secret、flush、shutdown 和错误语义。

## 文件与恢复契约

- 文件头 v2 与 CRC 保护的 schema extension 定义尾部区域，capacity/stride 计入所有 channel 的总 journal 预算。
- 每个定义占独立固定槽，ID 在文件生命周期内不回收/复用；表满或定义过大返回明确错误。
- 内容哈希使用 canonical metadata 的 SHA-256 截取 128 bits，哈希命中后仍比较完整 metadata，不能用地址或部分参数 hash 当身份。
- 引用包含 ID、版本和内容 hash；数据 CRC 覆盖引用及 payload。
- 定义 commit 后必须成功 sync，才能 markReady 和提交引用事件；失败时禁止引用，保留证据并允许重试。
- reopen 在修改数据游标之前校验 schema 表与所有引用。损坏、缺失和未知版本不被当成普通过滤。
- `kroncat` 只读复制定义和 payload，校验稳定快照，不依赖原程序二进制或进程地址。
- 后台交付线程 将引用还原为 Event 后仍输出普通 text/JSON 和自包含 archive frame。

减少的是 producer 捕获字节和重复 metadata，不自动减少固定 data slot stride 占用。v1 默认配置保持兼容；开启 v2 后不应拿旧 v1 layout 选项打开文件。

journal 文件版本、event codec 版本和 archive 帧版本是独立协议。当前自包含 event v4 和 schema引用 payload v5 使用84字节头，保存恢复目标指纹与route generation；历史自包含 v1 为68字节，历史自包含 v3 和schema引用 v2 为76字节。当前读取器保留上述历史版本，缺失的路由身份字段恢复为0；未知版本明确拒绝。archive frame容器保持版本1，payload按其自身codec版本读取。没有稳定route指纹的legacy记录可以只读导出，但运行时不能把它静默重放到未知目标。

schema定义本身也有独立版本：scalar定义v1、支持array/group的定义v2。当前v5事件可使用scalar或nested定义；历史v2引用载荷的兼容矩阵使用scalar定义。不要将journal文件v2、schema定义v2与事件引用v2当成同一个版本。

## 验证范围

模块测试覆盖去重、碰撞比较、metadata 深复制、表容量、sync/ready 故障、reservation 缺口、独立重开、Reader 只读恢复和热路径 allocator。共享/SPSC prepared Runtime 测试验证实际 后台交付线程 输出。

`zig build test-decoder-matrix -Doptimize=ReleaseSafe -j1` 覆盖历史/当前inline载荷、scalar schema与nested schema、动态message与deferred template的8组输入。每组2048次变异、所有截断和短scratch容量均检查边界；合法解码必须精确再编码且所有借用字符串/描述符位于输入、schema或调用者scratch。schema定义变异后重新计算完整性字段，直接检查结构拒绝；8个真实文件由公开Reader各只读导出两次。该矩阵也包含于 `test-fuzz`，属于有界回归，不替代长期fuzz。

QEMU harness 的 `--schema` 选项运行真实 v2 writer。在当前 Linux/ext4 试验中，ACK 3 后强杀整个 QEMU，重启确认全部已 ACK 文件记录及 durable checkpoint；这仍是特定子 VM 的停机试验，不是物理断电的普遍保证。
