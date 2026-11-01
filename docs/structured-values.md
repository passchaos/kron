# 显式嵌套字段

字段仍默认只捕获内建标量；容器通过 `array()` 和 `group()` 显式提供，避免自动遍历任意指针或对象图。

```zig
const details = [_]kron.Field{
    kron.kv("status", @as(u16, 200)),
    kron.kv("password", kron.secret("never capture")),
};
const items = [_]kron.Value{
    kron.fields.fromAny(kron.group(&details)),
    kron.fields.fromAny(@as(u64, 42)),
};
log.info("request completed", .{ .results = kron.array(&items) });
```

容器视图借用调用者存储，异步接受前 codec 深拷贝所有描述符、keys、字符串与 bytes。`withOwned` 同样深拷贝全部嵌套存储，正常 emit 不分配堆内存。

事件共享上限为8层容器、256个 value 节点，包含 attributes、格式参数及所有 children。循环、重复 group key、过深和预算超限在写出/接受前返回明确错误；不会输出合法前缀当作成功。Decode 使用调用方固定256个 Field slots 的 arena，不在读取过程中分配。

JSON 输出真实数组/对象，text 输出可读容器，logfmt 将完整容器表示放入一个 quoted value。`{}`/`{any}` 可后台渲染容器，数字和字符串格式符不接受容器。

redaction 对任意 group 层级的完整 key 精确匹配。点号不解释为路径。嵌套格式参数也在入 journal 前处理；顶层参数槽位和顺序保留，避免 drop 操作错位。输入树不被修改，失败和未使用 scratch 清除原值引用。

当前自包含 event payload 为v4/84字节头，schema引用为v5；分别保留旧 v1/v3 和引用v2读取。schema定义的标量版本1与容器版本2独立于事件和 journal 文件版本。

## 显式对象适配

`Adapter` 在编译期选择命名 struct 的成员，持有固定 Field 描述符存储。最多选择 64 个成员，成员存在、类型支持、名称与输出 key 唯一均在编译期检查；没有选择的成员不会被读取。

```zig
const User = struct { id: u64, name: []const u8, password: []const u8 };
var user: User = .{ .id = 42, .name = "alice", .password = "private" };
var storage = kron.Adapter(User, &.{ "id", "name" }).init();
const result = try log.tryEmit(.info, "user", .{
    .user = try storage.capture(&user),
});
_ = result;
```

capture 复制标量并借用字符串/bytes/显式容器；返回的 Group 借用 adapter 本身，下一次 capture 会使旧视图失效。必须将 adapter 保持在稳定地址，并保留源存储直至同步编码或异步 accepted。`withOwned` 会深拷贝这一结构。

`object(selected, &value, field_storage)` 可直接使用调用方 `[]Field`；不足的存储返回 `TooManyFields`。`MappedAdapter(T, maps)` 和 `objectMapped` 使用 `FieldMap{ .member, .key }` 显式重命名。任意对象指针、隐式递归 struct 和按值 byte array 被拒绝；嵌套值通过 `array/group` 提供，并沿用8层/256节点校验。`zig build test-adapter` 与负向编译门禁验证这些契约。
