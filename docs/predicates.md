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

正则按字节匹配，UTF-8字符可能占多个字节；`.`匹配除LF（`0x0a`）之外的一个字节。`^`只匹配整个输入开头，`$`只匹配整个输入末尾，末尾换行也属于输入。默认search可从任意字节位置开始，空组/空分支及nullable重复仍使用相同有界NFA。

支持`\n \r \t \f \v \a`及恰好两位十六进制的`\xNN`，包括NUL和`0xff`；转义标点按字面匹配。字符类中的首个`]`（也包括`[^]...]`中的位置）是字面量，首尾`-`或`\-`是字面量，其余`a-z`是包含两端的字节范围。反向范围和未闭合字符类返回`InvalidRegex`。Zig字符串、predicate字符串和JSON配置各自的字符串层仍需要正常转义。

`\d/\D/\w/\W/\s/\S`、`\b/\B/\A/\Z`、数字转义/回溯引用、Unicode命名转义、`(?...)`扩展组及未知字母转义明确返回`UnsupportedRegex`，不会被当作普通字母匹配。直接对`^/$`使用量词、重复量词及不完整/非法`\xNN`返回`InvalidRegex`；括号中的nullable断言仍可重复。非法配置事务保持原版本与journal reservation水位。

表达式在配置发布前解析并深拷贝；非法事务保持原配置。accepted事件保存当时路由mask和配置generation，后台不会用最新predicate重新丢弃。按route过滤可只保留部分目标，而全局predicate失败直接返回filtered。

相关外部测试 `test-predicates` 验证接受前过滤、正则预算、redaction顺序、old/new配置交付，以及嵌套Runtime回调时SPSC缓存版本仍保持有效。可运行示例：`zig build run-predicates`。

`test-regex-differential`使用独立Python bytes `re.search`生成可复现语料，以hex传递任意字节，覆盖原短ASCII语料、全部256种字节、换行/CR/控制字符、转义、字符类、空分支与nullable量词。Python的`$`还允许匹配末尾LF之前的位置，因此oracle仅将字符类外未转义的`$`转换为Python绝对末尾`\Z`，其他解析和匹配由Python完成。随机oracle输入不超过6字节，原ASCII语料不超过12字节，避免oracle自身回溯负载；8KiB长输入与超限在单独资源测试中验证。driver同时核对明确编译错误和输入超限，每轮用错误expect/非法hex/无expect/空语料等负向自检证明能够拒绝伪通过。

`test-regex-fuzz`增加8192项正则变异/任意字节编译与4096项predicate parser变异，成功编译后覆盖Pattern副本、输入配置覆盖以及多regex共享状态预算；诊断offset必须留在原spec范围内。它与差分共同进入`verify-local`，属于有界可复现campaign，尚不能替代持续sanitizer fuzz或所有业务正则的性能资格。实现分为`pipeline/regex.zig`的编译与匹配、`pipeline/predicate.zig`的字段规则与配置语法。复现记录见`bench/evidence/2026-11-01-regex-boundaries/`。

匹配热路径使用两个64位活跃状态位图。编译期在四种BOL/EOL条件下展开epsilon与断言循环，输入首位置使用独立initial状态；每个后续位置只检查实际消费字节的活跃状态，输入与状态预算保持。固定编译存储与配置初始化成本增加，具体资源、八类业务负载、完整同步JSON对照和`test-regex-equivalence --fuzz=1M`入口见[正则匹配工作量](regex-performance.md)。
