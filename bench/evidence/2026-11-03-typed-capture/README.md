# Typed capture候选撤回

生产代码恢复到 `58596c9`，没有保留新typed入口或Owner转发。性能目标仍是在相同完整输出与完成边界下超过 Foundation/logging + spdlog 和 +tracing。本轮没有达到该目标，也没有运行被拒候选的新Foundation排名。

候选在EmptyContext、非tuple命名struct、成员全部为内建scalar（含optional）时，由库私有构造器固定Field和值描述符，复用静态唯一key与单节点性质，省掉Runtime类型擦除后的重复检查。动态Value、nested、context、managed多输出、prepared site及attached token仍使用原路径。64/65字段预算、clock前捕获失败、clock后参数校验、combined nodes、redaction、prepared错误顺序、公开Event的完整校验、CRC三个校验点和队列预算都保留。完整源和测试已存入source archives及patch，不作为当前公共API。

## 撤回依据

`postclock-ecore-pmu/` 的40项完整文件对照核对4,040,000条JSON，四组用户态instructions约减少8.1%。cycles多数减少，但written关闭吞吐全部inconclusive。它包括完整子进程setup，不代表producer或consumer独立成本。

最终默认双拓扑各160项，每轮100,000事件+1,000warmup、5对轮换；public managed async/SPSC、Memory/Mmap、P1/P4、batch/sampled、五typed数值字段、完整metadata、系统时钟、256槽/512B、64KiB portable文件，written flush→shutdown→cleanup。全部物理JSON逐条独立核验，accepted=written、pending/drop=0；未请求设备durable。

`final-ecore-workflow/` 16个关闭吞吐组中，0个候选领先、3个baseline领先、13个inconclusive。三个局部负向是async Memory P1 batch约0.988×、async Mmap P1 batch约0.980×、SPSC Memory P4 sampled约0.996×。`final-pcore-workflow/` 16组全部inconclusive，不能用其正向中位抵消E-core回退。

`final-prepared-pmu/` 的80项核对8,080,000条JSON。managed prepared site保留旧路径，因此它是代码布局/流程控制组，不能称为direct Runtime prepared typed优化验证。八组关闭吞吐无候选领先，两个P1 shared组baseline领先，其余不确定；instruction也没有普遍减少。

## Metadata别名与真实测试入口

只读审查发现Zig aggregate参数允许按reference传递，`meta: Meta`不足以在source上保证任意clock callback修改外部别名时仍有快照。最终safe候选在clock前通过字段initializer构造private Meta，clock后才组装Event；不依赖未经保证的按值参数复制。

原postclock与private Meta版本的五个构造器测试都在Debug、ReleaseSafe、ReleaseFast通过，包含合法外部Meta别名、数值/descriptor与借用内容突变、64/65字段、极端length及原arguments错误边界。原版实测未暴露metadata变化，仍以显式私有副本保证source契约。修复后的专用gate真实执行五个模块测试和六个公共测试：`meta-snapshot-public-safe.log` 的25/25包含14个导入检查，不能写成25项独立功能测试。

`binary-sections.json` 证明postclock与private Meta版本的 `.text`、`.rodata`、`.data` 完全一致；二进制总hash不同来自其他段。该修复不改变执行代码或性能结论。`meta-ecore-workflow/` 的另160项完整复测再次无候选领先，6个baseline领先、10个inconclusive，支持撤回。第二份P-core复测也完成160项，1组baseline领先、15组inconclusive。全部阶段合计1,280项、129,280,000条物理JSON核对，逐矩阵明细见 `decision.json`。

撤回后只保留既有公共logger上的参数回归：合法array/group format arguments被clock改成cycle/duplicate后，仍是submit error，capture_errors不增长、reservation不前进、admission释放；恢复原树后完整JSON成功。它覆盖shared和attached SPSC，不依赖已撤回的typed API。

## 来源与范围

基线源在既有 `58596c9`；`first/borrow/inline/shared-final/postclock/meta-snapshot` provenance和source archives标明逐阶段实现与二进制hash。初版按值Captured、outlined consumer、inline consumer和选择时点修复的所有负向、失败和慢值继续保留。`decision.json` 汇总全部完成矩阵及物理记录计数，不把中间版本结果叠加成最终提速。

被撤回候选未运行完整verify-local/分发/九平台门禁。此前baseline门禁保持其原身份；本轮专项通过只证明候选的对应行为范围。源码archive与patch保留新API的全部实现和独立测试，包分发和当前使用文档不导出这些入口。
