# Shared Journal峰值更新实验

目标继续是完整超越 Foundation/logging + spdlog 和 +tracing。本轮保留direct shared峰值CAS，完整门禁通过，未证明全面超过两个Foundation前端。首条件包装版本因负向撤回，所有证据独立保留。

基线`55cbd76`的生产源码与已验证CRC VEX版本相同。真实Journal.reserve在count<=peak时仍执行locked cmpxchg，schema wrapper同样如此；baseline源码/binary身份已匹配冻结。候选保留occupied.fetchAdd返回的相同count_now，仅在count_now大于monotonic加载的peak时执行原fetchMax。published Journal的peak只增不减；旧低读取只能多做一次max，读到已覆盖count的peak可以安全跳过。未改reservation turn/tail/commit、CRC三个检查、实时mapped written、SPSC、内存/队列预算或public API。

峰值在create/recovery发布前按有效pending初始化。single模式固定且只有owner更新，其既有load+store路径保持；sharedWithSchema走同一shared reserve。source审查和实际新binary必须确认分支没有去掉占用计数或改变错误顺序。

独立公共8项peak回归覆盖实际持有reservations的精确峰值、Memory/Mmap普通/schema四条路径共60并发wave/648条完整记录、Full/oversize/abort/CRC失败与pending、Mmap重新打开。测试不依赖私有峰值hint或实现镜像。原journal/root Safe筛选75项通过，包含恢复缺口/损坏、durable/checkpoint、并发wrap、schema与无分配；这是journal相关选择范围，非整库gate。

性能采集前冻结source、binary并等待全部编译和测试结束。file完整workflow继续managed async/SPSC、Memory/Mmap、P1/P4、系统clock、五typed字段、full JSON、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup，5次配对与独立输出oracle；prepared控制组按实际schema版本分开。不请求device durable。负向、超时或源码变更仍保留，不能从少RMW推出一般吞吐。

源/并发审查确认reclaim不修改峰值，SPSC retire/reactivate不重置，只有发布前create/recovery重建。实际after普通/schema分支均绕过无变化CAS：比较xadd旧count(c-1)<peak等价于c<=peak，没有off-by-one。普通reserve540→556B，schema/SPSC/CRC尺寸不变；无新增call/stack/heap，归一化重定位后其余热点指令序列相同。布局仍768B，occupied720/peak728。详见source-review/binary-review，静态事实不等于吞吐。

基线public7项Safe与候选Debug/Fast7项通过，Safe integration/deadline组合31项通过；扩展schema的最终8项Safe通过。source、build及test哈希冻结后开始串行完整测量。

首40项shared full-process E-core PMU核对4,040,000条JSON。instructions配对中位约减少0.03%–0.07%，只有两组通过局部门限；written关闭吞吐全部inconclusive。Mmap P1 cycles速度比约0.949×局部负向，其余周期多不确定。少无效RMW不能直接等于指令或吞吐减少，全部正负在ecore-pmu。

首E-core默认160项完成、16,160,000条物理JSON。没有候选局部领先，7组baseline领先/9不确定：shared Memory P1 batch/sampled约0.985/0.977×，Mmap P1 sampled约0.972×，另SPSC控制多组约0.97..0.98×局部负向。SPSC生成代码不变仍有whole-binary布局/调度控制成本，不能用shared少CAS解释其慢值。条件包装版不具备保留资格，待P-core/schema及独立更紧凑CAS控制。

P-core默认160项核对16,160,000条JSON，0个候选局部领先、1个baseline领先（shared Mmap P4 batch约0.960×）、15组不确定。条件包装版有两个topology反例，不能依此保留。准备独立直接CAS loop替换重复load+fetchMax包装；该路线仍只更新high_water，不改变公开峰值定义或其他状态。

Schema E-core80项完成8,080,000条JSON，八组关闭吞吐全部inconclusive。首条件包装版总440项核对44,440,000条物理JSON，未取得保留资格。

第二candidate用captured count与首次peak load的直接weakCAS loop；成功严格增，失败返回值已覆盖count则退出，spurious仍重试，published peak只增因此无数字ABA。它不在重试中读取occupied以避免丢历史峰值。独立source/proof/archive保留，需实际二进制审查和测量。

Direct版首40项E-core full-process PMU核对4,040,000条JSON，instructions约减少0.06%但仍是小变化；cycles Memory P1/Mmap P1/P4本轮局部正向，Memory P4不确定。完整吞吐四组全部inconclusive。静态循环复用了初读peak并移除第二load/cmova，但schema wrapper从内联转调用且增长支路新增optional-tag spill，不能单靠小函数视作普遍优化。

Direct E-core完整160项核对16,160,000条JSON：1组候选局部领先（shared Memory P1 sampled约1.024×）、1组baseline领先（SPSC Mmap P1 sampled约0.985×）、14组不确定；默认batch多数接近1，不推导一般提速。SPSC实际代码归一化相同仍存在完整布局/调度控制负向，必须保留并精细复测。

Direct P-core默认160项核对16,160,000条JSON，16组关闭吞吐均inconclusive，没有稳定收益或负向资格。source不变，PMU的局部周期胜出不能代替这个结果。E-core sampled尾部也有部分SPSC p50/p99局部负向，实际SPSC指令虽相同但原值仍保留，需复测后决定。

将direct if/capture写法改为optional `orelse break` 的compact控制编译后，实际`.text/.rodata/.data`与direct逐字节完全相同。它不能消除标签栈写或schema取消内联，不重复计时。compact独立archive/source/binary身份保留，生产恢复已测direct源码。

当前用固定direct binary独立复测E-core SPSC Mmap P1 sampled负向，并以四组shared Memory/Mmap P1/P4百万条batch验证实际吞吐；期间无编译/改源码。

SPSC Mmap P1 sampled负向独立10项百万条复测核对10,010,000条JSON：written close配对中位1.009×、95%区间0.997..1.015，p50/p99/p99.9全部区间跨1且噪声/置信不确定，沒有复现短流程的稳定SPSC负向。原负向/尾部全保留，不以复测消去。

Direct shared百万条batch40项核对40,040,000条JSON：Memory P1/P4配对速度比1.001/1.009×、Mmap P1/P4 1.005/1.004×，四组input/ratio spread均≤10%，但95%区间全部跨1，完整吞吐仍不确定。它未确认回退，也未提供普遍提速资格。

保留directCAS进入完整门禁的依据是严格保持精确峰值、减少稳态无变化RMW、复用firstload/失败覆盖退出，PMU局部周期证据及独立long复测未确认负向。所有原short负向与layout/调用成本保留，不以少RMW直接宣称最佳。conditional包装版撤回、compact只保留代码身份；最终完整门禁与Foundation对照后记录资格。

累计930项完整版本对照核对138,930,000条物理JSON，分版本见completed-measurements；其中direct490项94,490,000条，不把首包装版百分比继承到direct或Foundation排名。

最终direct源码完成完整ReleaseSafe/源码分发/独立包/真实SIGKILL/九目标对象gate，source guard前后相同。日志与命令在full-safe.log/gate-status.json，非Linux对象不代表设备运行、SIGKILL不代表物理掉电。最终baseline与direct的公共8项都通过，directDebug/Safe/Fast均执行Memory/Mmap、普通/schema峰值及恢复测试。

最终direct完整门禁155/155步骤成功，648/649测试通过（1默认system local能力skip，六时区×五模式oracle已实际执行）。新public8项与既有field9项均进入完整gate，source/测试/构建身份在验证前后相同。

最新两个Foundation真实前端的双拓扑320项核对32,320,000条JSON：E-core对spdlog3组kron领先/5组peer领先/8组不确定，对tracing11组peer领先/5组不确定；P-core对spdlog7组kron领先/9组不确定，对tracing4组kron领先/12组不确定。E-core written-close目标未达到，P-core整体inconclusive，整体仍未超越两个前端。原始输入/依赖/source/binary、所有阶段与尾部见[当前E-core报告](../../cpp_reference/evidence/2026-11-03-peak-direct-ecore/README.md)、[P-core报告](../../cpp_reference/evidence/2026-11-03-peak-direct-pcore/README.md)。

保留理由与限制记录在qualification.json。没有公开新选项/验证proof或减少default CRC，完整throughput/周期/尾部不作普遍承诺。下一独立候选是shared written的singleconsumer有条件release store，不延后实时cursor；只读协议研究在next-written-cursor.md，未实现，不能把未来潜力作为本轮完成证据。

收尾修正journal.zig一条旧注释（fetchMax改为CAS failure value，同样源码行数），没有代码变动。final-source/provenance记录当前字节，原direct-source/provenance保持门禁/测量身份；重新编译后的`.text/.data/.rodata`与measured direct逐字节相同，见final-code-equivalence。没有因注释修正重复故障或基准，最终qualification明确关联两个source身份。
