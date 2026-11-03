# V3 schema CRC：reference+padding与payload一次折叠

此前 [16行消费校验](../2026-11-03-crc-flat-consumer-16row/README.md) 只复用原16个row，E-core有23/32 written局部lead但full-run有6个latency/init负向，已拒绝。本候选不再改CRC表，而是改schema journal的CRC输入：V3把24B schema reference与8B零padding并入payload的连续区间，producer和consumer都只做`header(20B)`加`[32..64+length]`两次update，而不是原来的header、reference、payload三次。V1/V2 journal继续按原CRC读取，新schema journal写V3。

slot布局、256槽/512B预算、三个CRC检查点、schema extension、公开API和V1/V2错误顺序均不变。`writeSlotSchema`仍只写32..56，56..64保持零；V3 CRC覆盖这些零字节，因此输入在slot内连续。Archive Reader从64B slot header读取`before[32..64]`，用语义等价的`checksumV3`分段计算。

## 兼容性

- `format.schema_version_v2=2`保留，`schema_version=3`成为新schema journal默认；`initializeV3`/`validateV3`与V2共用布局。
- `Journal.create`从已校验header读取`file_version`；旧V2 journal走`validateV2`和`checksumV2`，新V3走`validateV3`和`checksumV3Slot`。
- `schema.readLayout`接受journal version 2或3；`Archive.Reader`的version switch与`copyCommit`分别处理V1/V2/V3。
- `tests/tool_query.zig`的`refreshSlotCRC`改为按journal version决定是否加入56..64 padding，并把测试末尾的硬编码`2`改为恢复原header version；生产V2 reader五项回归仍实际通过。
- Python crash campaign仍断言schema journal version=2；因候选未进入生产，这些脚本未改、未运行。若后续保留V3，必须先让它们接受2/3并重跑真实SIGKILL。

## 静态与正确性：通过

[actual-review.json](actual-review.json) 由 [audit_actual.py](audit_actual.py) 生成：

- V1/V2 `Journal.slotChecksum`保持156B/48指令/3 call，与baseline逐项相同；producer frame保持`0xd18`，通用`Crc32.update`保持1412B/20 PCLMUL。
- producer由1048/30/372变为1066/32/378：新增的是V3路径的两个update与一个version分支；V1/V2的3次update和slotChecksum边界保留。
- `validateSlot`由636B/154/2变为669B/166/3，新增V3 checksum分支；`checksumV3Slot`独立82B/28指令/2 call。
- rodata增长0B；DWARF对象大小Journal768B/Runtime12800B/Field48B不变。

V3 golden常量`0x4be88818`由独立Python zlib计算；`checksumV3`与`checksumV3Slot`在0..512多种长度下与`std.hash.Crc32`逐项一致。21个具名CRC/Journal/Reader/progress case在native Debug/Safe/Fast与generic Safe实际执行通过，包括V2旧journal重开、V3 reopen/recovery、schema ref corruption、archive reader和SPSC wrap。

## 完整流程：V3 treatment强正向，V1 control有微小负向

最终隔离版（`flow-ecore-inline`/`flow-pcore-inline`，binary `ee8f...`）双拓扑各320项、每拓扑3232万JSON：

- E-core schema=True（V3 treatment）：208轴中**41 qualified lead、63 inconclusive、0 negative**；written 13/16 lead、written+flush 13/16、lifecycle 6/16、p50 4/8、p99 3/8、p999 2/8。
- E-core schema=False（V1 control）：101 inconclusive、1 lead、**2 qualified negative**；都是async mmap P1 batch，written ratio 0.99860、written+flush 0.99837。
- P-core两个schema全部inconclusive，0 negative。

按预定“任一qualified negative即拒绝”，最终版仍被拒绝。两个control轴各做5轮定向复测：[control-confirmation.json](control-confirmation.json) 中written为inconclusive 1.00369、written+flush为inconclusive 0.98624，没有一个复现qualified negative；因此不能把这两个0.14%级control负向当作稳定回归，也不能用复测替代预定full-run门槛。

### 隔离迭代

同一V3 CRC先后尝试三种代码组织，全部原始数据保留：

| 版本 | E-core V1 control | E-core V3 treatment | 目录 |
| --- | --- | --- | --- |
| 单函数switch，全部内联 | 13 negative | 50 lead / 0 negative | [flow-ecore-unseparated](flow-ecore-unseparated/summary.json) |
| 恢复原slotChecksum，V3分支隔离 | **2 negative** | 41 lead / 0 negative | [flow-ecore-inline](flow-ecore-inline/summary.json) |
| V3 checksum noinline | 20 negative | 49 lead / 0 negative | [flow-ecore-noinline](flow-ecore-noinline/summary.json) |

隔离版把control负向从13降到2，同时保留41个V3 lead；noinline进一步缩小producer，却让control负向升到20，说明binary layout/对齐对V1路径的影响大于调用边界。最终选择隔离版，但不越过预定门槛。

另试两版out-of-line commit，均未运行性能trial：V1 commit完全out-of-line时producer为915条指令、`Reservation.commit`/`commitV3`各成独立调用，V1路径合计约1095条且新增commit调用边界；V1 commit强制inline、V3 commit noinline时producer frame `0xd28`（比baseline +16B）且`slotChecksum`不再内联。两者都未过预设no-new-frame/call边界，因此没有full JSON对照；冻结候选仍为隔离inline版`ee8f...`。这说明在共享commit函数内很难同时保持V1 byte-identical与V3 out-of-line收益，下一候选需要独立gate或不同杠杆。

## 第二独立窗口：treatment复现，control负向不复现

同一binary `ee8f...` 在E-core再跑一个320项完整窗口（[flow-ecore-inline-2](flow-ecore-inline-2/summary.json)，逐条核验3232万JSON）：

- schema=True V3 treatment：**40 qualified lead、64 inconclusive、0 negative**，与第一窗口的41 lead/0 negative一致。
- schema=False V1 control：103 inconclusive、1 lead、**0 negative**；第一窗口的2个0.14%负向未复现。
- 两窗口treatment合计81个qualified lead、0 negative；control只在第一窗口出现2个非复现负向。
- 加上两个control轴的5轮定向复测全部inconclusive，可以判定第一窗口的control负向是窗口/布局波动，而不是V3 feature回归。

按文档化full-run gate，第一窗口仍有2个qualified negative，因此生产不应用。但证据已改变下一步：V3 feature本身稳定，需要显式决定treatment-only gate/control容差，或实现V1 byte-identical路径；在进入生产前还必须把Python crash campaign更新为接受journal version 3并重跑，以及执行完整release gate。当前生产仍保持185e700原算法/V1/V2格式/三CRC/预算，未运行Foundation trial或更新排名。整体“业界最佳”目标仍未完成。
