# 后续short-key研究（未实现）

只读核对当前完整vex-reference与source身份后发现，default字段field0..4都是6B；producer codec.measure与fused JSON已经长度筛选并分别比较头DWORD、尾DWORD。unique pair在尾部不等即退出，沒有走通用memcpy/memcmp长循环。不能用“消除默认长比较loop”解释新优化。

Zig std.mem.eql的4..16B公式使用四组u32重叠读；4..8B的后两读重复。当前inline调用点能短路跳过后两读，但仍预算(len/8)*4和end-minus-middle，producer还有相关offset spill；nested的outlined eql helper仍eager四组读。有限可测候选是等长4..8B keys只比较两u32，保持短路；其余长度保留原路径。读取[0,4)与[len-4,len)严格不越界，必须先等长和len区间检查。

TestingAudit保持原逐pair位置、比较顺序与首次重复时的计数；既有DuplicateKey/树/node/decoder错误边界不变。最小test应独立std.mem.eql oracle覆盖0..8、相同/不同长度、不同地址等内容、每字节差异、0..7unaligned和两端guard；随后审生成Logger的offset算术、spill、helper/调用方总代码尺寸。全流程测量必须继续输出完整JSON并保存任何负向，不从少两组读取推出吞吐。

当前还在验证CRC VEX，不在同一候选混入key机制。历史目录检查未发现同机制尝试；typed capture撤回是利用静态key性质省略验证，属于不同设计。本记录只描述下轮待验的范围，未实现、编译或基准。
