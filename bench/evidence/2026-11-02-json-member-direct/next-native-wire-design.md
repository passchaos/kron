# 后续native整数wire设计（只读研究，未实施）

当前五u64属性仍按统一u128 tag/value捕获，85B数值载荷。若在新自包含event v6/84B header引入物理signed64(tag11)/unsigned64(tag12)，同样五值可为45B，精确少40B；宽i128/u128保持原16B值。JSON字节、slot stride/预算不变，CRC覆盖完整实际payload，不能通过删除校验取得同语义排名。分类分支和布局代价仍须实测。

canonical ValueTag保持0..10，新物理tag映射typed callback.accept(.signed,i64)/(.unsigned,u64)，Materializer扩展为现公共i128/u128。signed选择以i64范围为准。只有已检查自包含v6 header启用新tag；v1/v3/v4、schema事件v2/v5、裸writeValue/encodedValueSize继续旧wide模式，遇新tag明确InvalidTag。schema定义/mask/hash、journal和archive frame/container版本保持。

最小拥有源码：wire_write共享物理分类和显式native/wide模式，wire_size用同一分类保证size/write一致；codec measure/write/header/decoder显式保留1/3/4并新增6，route_generation能力明确包含4/5/6，nested只含inline4/6，native只含6。模式传nested/format args，节点/深度/arena与duplicate错误先后保持。reference_encoding/schema_codec明确wide128，不能随共享size helper静默改变v5字节。

Runtime与wire_json融合入口继续接受v4，再加v6；让所有旧v4走materialized fallback可能改变route错误与坏value的先后，不能以“新decoder通过”替代旧路径资格。v6可规定native范围值只用新tag，旧宽tag承载native范围在完整读取后、callback前InvalidValue，保持新版本decode→encode canonical字节不变；公共值域不缩小。若允许双表示，就须明确修改该不变量。

升级矩阵需要冻结v1/v3/v4 body/golden。现decoder_matrix用current body贴旧header、fuzz输入等于current reencode的断言不再自动正确，必须按实际版本生成/比较。覆盖native/wide所有边界、±i64/u64、i128/u128 extrema、safe-integer范围、unaligned、每个截断、unknown version/tag、noncanonical、非法树零输出、budget/shared nodes、callback零调用、sized/stream/framed长度与CRC一致。

旧reference v2/v5 scalar/nested/format错误和字节保持；Reader、工具、压缩/普通archive和journal混合旧/v6、follow/recover只读与版本拒绝；tests/crash_recovery.py、recovery_campaign.py、runtime_crash_oracle.py明确inline4/schema5断言，需保留旧fixture再增inline6。Package、真实进程恢复、route pins/ACK、两Foundation完整JSON和应用oracle都要复测。先完成reader/恢复工具兼容再启用写入，旧程序会拒绝v6，不能称为双向透明升级。

这份设计没有生产代码、测试或性能资格。本轮保留代码仍写inline v4/reference v5。
