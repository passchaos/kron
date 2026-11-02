# 4dd574f E-core完整流程profile

使用`4dd574f`、public managed async Memory P4、CPU16/18/20/22/24/26、1000000事件+1000warmup、五typed数值字段、full JSON、256槽/512B、64KiB portable文件、written flush/关闭终点。`run.py`的独立JSON oracle核对1,001,000条完整物理记录，accepted=written、pending/drop=0。没有请求设备durable。

约10K cpu_atom用户态cycle样本中submitSafeDestination13.48%、begin12.85%、reserve10.76%、CRC update7.40%、encodeJsonWithAttributes7.15%，完整结果在`p4-profile.txt`、`p4-report.json`、`provenance.json`。这轮CRC份额比此前9.5%低，但不同窗口profile比例不能直接证明百分比提速或叠加到跨库排名。

下一实验针对无predicate默认路由扫描及JSON属性前缀Writer小写入，保留所有CRC、事件、恢复和错误边界。共享入场分片与JSON整数候选已有否决结果，不以删除这些契约换取相同语义的性能结论。
