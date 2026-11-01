# 字段条件与有界正则过滤

Level/scope 仍在字段构造前判断；`predicate` 在捕获并递归脱敏后、journal reserve/accepted 前判断。可以在 Runtime、配置 Policy 或单个 route 设置表达式：

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .predicate = "tenant == \"prod\"",
    .routes = &.{.{
        .name = "errors", .sink = file.sink(),
        .predicate = "status >= 500 && path =~ \"^/api/(users|orders)$\"",
    }},
});
```

支持 AND、exists、相等/不等/大小比较、prefix、contains、正则。语法包括 `exists(key)`、`== != < <= > >=`、`^=`（prefix）、`*=`（contains）、`=~`（正则）。字符串使用引号，数字比较保留 i128/u128 的精度。NaN 比较返回false，缺少字段不匹配，容器不自动参与标量比较。

元数据目标使用 `@scope`、`@level`、`@message`、`@rendered_message`。message 对延迟格式化事件表示模板；rendered_message只接受显式预编码或普通字符串事件，不在producer中隐式执行昂贵格式化。点号字段名按字面匹配；低层 `Predicate.init` 的 Rule.path 可显式逐group查找，避免 dotted key 歧义。

正则编译为固定预算 Thompson NFA，支持 `.`、`*`、`+`、`?`、`[]`、`^`、`$`、`|`、`()`；无回溯，不支持backreference等表达式会明确失败。每Predicate最多64条规则、8KiB配置、128个正则状态，regex输入最大8KiB，编译嵌套最大32层。匹配不分配内存，超长regex输入返回InputTooLong并且不占journal槽。

表达式在配置发布前解析并深拷贝；非法事务保持原配置。accepted事件保存当时路由mask和配置generation，后台不会用最新predicate重新丢弃。按route过滤可只保留部分目标，而全局predicate失败直接返回filtered。

相关外部测试 `test-predicates` 验证接受前过滤、正则预算、redaction顺序、old/new配置交付，以及嵌套Runtime回调时SPSC缓存版本仍保持有效。可运行示例：`zig build run-predicates`。

`test-regex-differential`使用独立Python `re.search`生成种子ASCII语料，Zig driver逐项比较支持语法的匹配结果。输入限制在短ASCII串，避免oracle自身的回溯负载；差分并不把不支持的backreference等能力算作支持。长输入/嵌套量词的资源上界另由NFA模块测试覆盖。
