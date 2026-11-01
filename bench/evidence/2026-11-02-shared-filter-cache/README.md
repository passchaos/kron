# shared filter热点与候选验证

**全部filter候选已撤回，生产src恢复`2fd7f75`。** 本轮继续优先shared Memory/Mmap，SPSC保持高级可选；本目录不提供新的Foundation+spdlog/tracing排名。共244项profile/PMU/正式试验核对6420.4万条实际JSON，全部慢值和不同源码窗口独立保留。

## 当前完整流程profile

before二进制SHA256来自当前完整前端基线，production src与`2fd7f75`一致。baseline-source.tar.xz冻结src和reference benchmark，before-provenance.json保存二进制/归档身份。四配置为managed Logging、shared Memory/Mmap、P1/P4、batch、100万计时事件+1000 warmup、portable真实文件、完整元数据和系统timestamp、5个数值字段、256槽/512B、64KiB文件buffer。每个actual文件通过独立oracle核对，共400.4万条JSON。

perf采用`cpu_core/cycles/u`、997Hz、DWARF 16KiB调用栈，CPU 0/2/4/6/8/10。包含init/warmup/关闭/cleanup，排除kernel；profile自身有采样与栈开销，不能作为正式吞吐排名。results.json保存完整命令与stage/output核验，self/children报告分别保存；raw perf.data保留在`.zig-cache/shared-current-profile/`，没有提交二进制data。

Memory P4自占采样中Runtime.begin约16.7%、submitSafeDestination约16.3%；Mmap P4约19.6%/17.5%。P1仍有consumer decimal约8.5%的自占样本。begin反汇编在admission CAS、filter reader登记后的publication读取、configuration reader登记后的publication读取处出现集中采样。采样有skid且只有约1K个，不能把某条指令后的比例当作精确锁等待时间或parking_lot因果证据。memory-P4-begin-assembly.txt使用no-source指令输出，避免后续live source编辑影响旧源码行映射。

## 已否决的TLS候选

第一版给普通Runtime admission增加4-entry、每key最多128B的线程本地复制缓存，使用唯一filter身份、完整generation/config binding和永久回绕禁用，不持有snapshot或借用scope。warm hit不执行filter reader RMW，route reader/record pin保持原协议。native符号确认增加672B TLS与8B冷身份counter。

Debug/Safe的真实缓存测试各18/18（含fixtures），真实Memory/Mmap route reader/pin定向16/16，Fast合并定向20/20；公共配置/事务/路由/Logging/outputs Safe 65/65。最初缺显式test import的13项fixture-only探测也原样保留，不作为缓存测试覆盖。

40个固定CPU交替完整PMU试验核对1204万条JSON，四组指令数中位增加0.76%–0.78%、全部CV/spread达标且区间不重叠；周期和完整吞吐没有稳定收益。该版已撤回，所有源码、hash、完整原始row/CSV/日志及决策在tls-rejected/；冻结二进制留在`.zig-cache/decision-cache-reference-after-tls`。不为该候选宣称完整门禁或性能推广资格。

## uniform原子快照候选

第二版只优化没有scope规则的filter。每slot额外保留带版本的默认级别原子word与配置绑定原子值；reader仅复制原子数据并验证publication，避免读取未保护的Filter树。scope规则、full-generation超界与回绕禁用仍使用原SC reader协议；boundFilter冷复制不改动。没有TLS key或身份counter，不新增日志调用分配。

一致性依赖原SC发布顺序：writer先发布中间generation，随后才能重用另一slot。reader若读取到未来binding，其最后publication验证必然看到中间或更新generation，不能返回混合copy；packed word与publication匹配保证binding不会来自较旧发布。超过u56缓存范围时永久禁用uniform mirror，禁用标志在末次publication验证之后读取，使完整u64回绕不能命中第一周期。返回值仍包含完整filter/config generation，Runtime原route binding不匹配时的baseline选择、配置View、accepted pending pin、CRC和required确认不变。

初始uniform版Debug/Safe/Fast定向各17/17（3项性质测试+fixtures）：默认级别/配置绑定、scope fallback、禁止后续allocator分配、完整generation与回绕、四reader并发2000次uniform/scoped交替slot复用。公共配置/事务/路由/Logging/outputs Safe 15/15步骤、65/65测试通过。40项uniform-pmu的完整指令中位增加0.37%–0.46%，周期/吞吐区间仍重叠；该版本的boundDecision变成单独的0x1de-byte函数，基线调用则已经内联。完整源码、二进制与数据归档于uniform-initial/，不能用于最终源码的资格。

随后将scope reader/threshold扫描移到noinline冷函数，恢复紧凑的uniform调用。inline诊断的40项完整PMU，指令差额缩到约+0.09%–0.18%；Memory P4 cycles中位约−6.3%并通过CV/spread，但区间仍重叠，其他周期也没有一般资格。源码与全部结果在uniform-inline/。最终保留普通public fn以支持取地址，native二进制仍自动内联default路径；增加函数指针调用检查，最终Fast定向17/17通过。after-provenance.json与candidate-source.tar.xz对应这个最终候选，前三份PMU分别绑定自己的冻结源码，不伪装成最终版本测量。

## 最终完整流程与决策

最终80项未插桩试验，各配置batch/sampled各5对，30万计时事件+1000 warmup；逐条核对2408万条JSON。managed Logging、shared Memory/Mmap、单真实JSON文件、5数字/full metadata/系统clock、256槽/512B/64KiB buffer、4服务量子、block、written→shutdown→cleanup，init/preparation与完整lifecycle另列。CPU固定六个物理core的一个logical CPU，affinity不代表独占。measure.py明确验证frontend/优化级别/实际后端、源码/binary身份以及全部输出，保留全部慢值；没有durable flush。

| shared配置 | before M条/s | candidate M条/s | 中位变化 | CV/spread资格 / 中位区间 |
| --- | ---: | ---: | ---: | --- |
| Memory P1 batch | 2.188 | 2.107 | −3.72% | 未达标 / 重叠 |
| Memory P1 sampled | 2.079 | 2.117 | +1.82% | 未达标 / 重叠 |
| Memory P4 batch | 2.216 | 2.178 | −1.73% | 未达标 / 重叠 |
| Memory P4 sampled | 2.208 | 2.161 | −2.16% | 达标 / 重叠 |
| Mmap P1 batch | 2.181 | 2.295 | +5.23% | 未达标 / 重叠 |
| Mmap P1 sampled | 1.993 | 2.087 | +4.72% | 未达标 / 重叠 |
| Mmap P4 batch | 2.136 | 2.182 | +2.16% | 未达标 / 重叠 |
| Mmap P4 sampled | 2.167 | 2.143 | −1.12% | 达标 / 重叠 |

sampled四组p99.9中位增加约13.7%–20.7%，均超波动门限且区间重叠，没有尾部优势。吞吐与lifecycle全部细节见final-workflow-comparison.json及原始row，不能只选Mmap正向中位作为整体收益。减少filter reader RMW的机制有正确性证据，但额外原子读取、分支/调用和更快入场后的背压取舍未取得完整收益，因此恢复原生产协议。decision.json记录各独立窗口与撤回理由，rejected-candidate.patch供直接审阅；没有为这些撤回候选执行或声称最终完整151-step资格。

撤回后生产src与基线一致，当前Logging/outputs ReleaseFast 6/6步骤、43/43测试通过，见post-revert-fast.log；独立源码分发ReleaseSafe 2/2步骤通过，五模式各2条实际JSON均核对，见post-revert-package-safe.log。四份候选归档内容逐文件匹配各自source hash、四份binary匹配各自身份，当前src严格恢复2fd7f75。后续从当前profile中的消费者wire解析/数字输出推进；不重复推广本轮TLS scope决策或uniform原子镜像，除非机制和证据发生变化。

## 复现

profile.py使用before-provenance指定的冻结baseline，`--capture-name`要求新目录并逐条验证实际JSON。measure.py使用当前provenance的一对冻结binary，拒绝覆盖捕获；运行候选比较前需在独立实验checkout恢复对应candidate-source.tar.xz，live source guard会拒绝已经恢复原实现的HEAD。归档binary留在`.zig-cache`、各provenance记录其身份；新机器重建必须记录新hash，不能冒充原测量。

```sh
python3 bench/evidence/2026-11-02-shared-filter-cache/profile.py --capture-name before-profile-repeat
python3 bench/evidence/2026-11-02-shared-filter-cache/measure.py --capture-name workflow-repeat
```
