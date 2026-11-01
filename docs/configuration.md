# 路由与策略热替换

`replaceConfiguration(routes, policy)` 发布一个不可变配置版本。Policy 包含默认 scope filter、采样和递归 redaction；每个 route 仍可指定独立 filter、格式、required/best_effort 和 written/durable 回收边界。

```zig
const version = try runtime.replaceConfiguration(&.{
    .{ .name = "json", .sink = new_file.sink(), .format = .json },
}, .{
    .default_filter = "info,http=debug",
    .redaction = &.{.{ .key = "password", .action = .mask }},
});
try runtime.flush(.written);
_ = try runtime.collectConfigurations();
```

准备与校验在发布前完成，非法规则、预算不足和 OOM 保留当前版本。`configuration_slots` 默认8，限制同时保留的版本；尚有旧事件/操作时不能覆盖旧槽位，返回 `ConfigSlotsExhausted`。调用者可以等旧事件排空并 collect 后重试。

## 完整来源事务

`configuration_sources` 对 filter、redaction、sampling、sample_bypass 和 predicate 逐字段合并，优先级为 defaults < file < environment < explicit。环境适配仅映射 `KRON_LOG`，由应用显式传入；merge 借用输入，不解析、不分配。空 filter、空 redaction、`.none` sampling 和 predicate `.clear` 都是明确覆盖，缺失字段才继承。

每个不可变配置快照预计算继承全局filter的route级别掩码，包含各route的min_level限制。普通继承route在日志调用时只读取对应级别的掩码；拥有独立scope filter的route仍逐个检查scope阈值，独立filter可以在全局off时接受日志。filter-only reload改变全局阈值，不修改这些派生掩码；完整配置替换从新routes重新计算，旧事件继续使用旧snapshot。掩码每个版本占64字节，不改变route编号、恢复指纹或持久化格式。详见 [过滤性能验证](route-filter-performance.md)。

后台消费一批日志时，对相同非零generation/fingerprint复用一个受保护的View，直到该批交付、barrier和记录确认完成后释放。缓存仅在批次内存在；跨版本分别处理，未知指纹仍报错。失败时临时View释放、记录pin和资源lease继续保留；历史generation=0不省略完整歧义检查。行为和实际查找计数验证见 [批次配置复用](batch-configuration.md)。

```zig
const version = try runtime.replaceConfigurationSources(routes, .{
    .defaults = .{ .filter_spec = "info" },
    .file = application_policy,
    .environment = kron.configuration_sources.fromMap(init.environ_map),
    .explicit = .{ .sampling = .none, .predicate = .clear },
});
```

合并结果的 default_filter 与 routes/predicate/redaction/sampling 一次发布到同一不可变快照。发布成功后输入可释放或覆盖；失败保持当前路由版本、filter generation 和 caller sink lease 责任不变。sink 路径由应用创建sink后作为routes传入；JSON不会执行任意sink工厂。

`replaceConfigurationFile(routes, path, sources)` 在调用线程读取最多16KiB的JSON，替换 `sources.file`，再使用相同完整事务。例如：

```json
{
  "filter": "off,worker=debug",
  "redaction": [{"key": "password", "action": "mask"}],
  "sampling": {"kind": "every", "every": 2},
  "sample_bypass": "warn",
  "predicate": "status >= 500"
}
```

sampling支持none、count（字段count）、every（字段every）、token_bucket（capacity、refill_interval_ns、可选start_ns）。整数完整保留u64范围；负数、小数和溢出被拒绝。predicate=null显式清除。最多16层JSON、64条redaction和既有配置预算；未知字段、重复JSON字段、重复redaction key、非法值或OOM均不发布。`configuration_document.Document.parse` 提供同样解析，可供应用自行读取文件；Document拥有字符串，`override()`借用至deinit。示例：`zig build run-configuration-sources`。

## Filter-only更新

`reloadFilter`、`reloadFilterFile`、`setLevel`/`setLevelChecked`保留轻量更新能力。filter决策绑定其route generation；绑定不匹配时使用快照自带baseline。因此full default_filter之后的reload仍会生效，不产生旧filter配新策略的组合。

filter-only更新在初始化后不分配、不占用route槽，也不重置sampler。`setLevelChecked`只改默认level、保留scope覆盖并返回生命周期错误；`setLevel`通过diagnostic记录错误。后续 `replaceConfiguration(..., default_filter=null)` 继承当前有效filter。writer通过configuration_mutex串行化；SPSC缓存命中只读取publication与owner本地数据，不增加共享reader/pending RMW。

admission固定实际filter generation与route snapshot。嵌套另一Runtime期间的同scope enabled guard保留外层入场决策，直到提交结束。accepted事件的决策保存在route_mask/config_generation，后台不重新过滤。

普通调用先读取带绑定的filter决策，再取得route快照；完整事务先发布route快照，再发布同代filter。这个顺序避免已取得旧route的调用退回该route最初的baseline，丢掉此前已完成的reload。SPSC在验证线程owner后使用相同观察顺序；已入场调用直接使用线程本地保存的决策。Runtime内部filter使用opaque handle，公开只读 `currentFilterGeneration()`；独立的 `DynamicFilter`仍可单独使用。

## 旧事件与资源所有权

每个成功 admission 固定同一快照，直到字段捕获、脱敏和提交完成。accepted journal record 另持有该快照，后台按记录的 `route_generation + route_fingerprint` 找回原目标；最新 filter、格式或 sink 不会重新解释旧事件。

省略 `RouteOptions.release` 时，sink 由调用者拥有。调用者不能只因为新配置已发布就销毁旧 sink；先 flush，再使用 `configurationReadyToCollect(version)` 和 `collectConfigurations()` 确认旧版本可以回收。

显式提供 `release = .{ .context = owner, .release = callback }` 时，成功发布转移该资源 lease 的责任。相同 context+callback 的 lease 在全部版本间计数，最后依赖消失才调用一次。发布失败或 Runtime 初始化失败不接管 caller ownership。release 回调在路由写锁和 Runtime delivery/configuration 锁外运行；可发布其他配置，但不能重入关闭/销毁正在清理的 Runtime。

collect 对候选 retired 版本确认无生产者/记录/控制操作引用，完成最终 required 写出和可用的 durable barrier，再按精确版本 token 回收。回调期间产生的新 retired 版本不被这次收集误释放。

额外durable收尾遇到UnsupportedDurability时，仍允许已经完成required written且没有pending record的版本回收，并撤销全局历史durable资格。实际InputOutput等错误仍保留版本/lease供重试；pending引用保证尚未满足其required reclaim边界的记录不会进入这一回收流程。

## Deadline 与恢复

`flushRoutesUntil` 在调用时解析命名 route，并在控制任务中持有那个版本的 lease。超时后发布新配置不会把仍在执行的操作转到新目标。

`flush(.written)` 覆盖保留的历史 required 版本。全局 durable 还需考虑已经退休的历史目标：如果曾存在不支持 durable 的 required 目标，运行时保守返回 `UnsupportedDurability`。针对显式 route 的 durable flush 不会宣告其他历史目标已经持久化。

重启时必须配置正确的当前 `initial_route_generation`，并在 `recovery_versions` 中提供尚有未交付记录的旧代与目标身份：

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .routes = current_routes,
    .initial_route_generation = 2,
    .recovery_versions = &.{.{ .generation = 1, .routes = old_routes }},
    .submission = .asynchronous,
    .journal = journal_options,
});
```

初始化验证全部待恢复记录的绑定，而不是只检查第一条。缺失旧目标、身份不符或歧义返回错误并保留 journal；不会静默投递到新文件。历史资源可用新实例恢复，但其稳定 recovery identity 必须匹配。

`test-configurations` 验证旧/新目标分流、admitted producer 保留旧策略、容量/OOM/初始化失败责任、共享lease、回调重入、deadline lease 和跨代恢复。`test-crash` 的 hot-routes 阶段强杀真实 Runtime 后，由新进程导出两代记录。
`test-transactions` 验证完整来源发布、filter-only更新与采样配额、失败责任、channel重用、延迟publication交错、嵌套guard和真实JSON文件。根模块的warmed SPSC计数测试直接检查global reader/pending与DynamicFilter reader RMW不增长。

## SPSC配置缓存

每个attached channel持有自己的已验证版本缓存。稳态cache hit只读取publication和owner本地数据，producer/control共享计数与channel计数分开。accepted记录仍保留对应channel/version引用，只有ack后释放；刷新先pin新版本，再释放旧缓存。

缓存由所属同步线程更新，detach在确认没有admission后释放；collection不会行政修改缓存，因为enabled/filtered可在admission之外读取。空闲attachment可能保留旧配置槽，直到该线程下一次调用刷新缓存或detach。这是有界资源行为，不能用强行覆盖旧cache消除。

嵌套不同Runtime回调中的outer enabled guard返回outer正在使用的TLS缓存版本，不提前刷新或释放。公共release入口也检查真实retire、cookie与active admission，不能在事件执行中丢掉唯一pin。

`max_configuration_bytes`控制每版本metadata预算，Runtime默认2MiB，可覆盖64个固定预算route；`configuration_slots`限制同时保留版本数。字段predicate增加固定配置存储，不能把预算等同字符串长度。
