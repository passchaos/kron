# 当前完整日志流程 CPU profile

生产源码与HEADf11771b一致，各失败候选未改变Journal/CRC。参考binary独立从61222f5源码构建，逐文件hash核对当前源码相同（后续HEAD仅docs）。此profile重新定位当前producer/consumer热点，不把旧profile占比当当前成本，也不是速度排名。

8个串行流程：E-core/P-core各4种场景（asyncMemoryP1/P4，SPSC MemoryP4/MmapP4），每次100万事件+1000warmup、fullmetadata/5typednumeric/systemclock、256slot/512B、portable64KiBbuffer、defaultCRC/writtenflush→shutdown→cleanup。所有实际JSON由独立oracle核验，perf采用户态cycles、dwarf调用栈。采样包含setup/warmup/cleanup，周期占比是近似而非精确性能解释。

不与编译/功能tests/其他benchmark并发，raw perf record/report/stat output与JSON验证/source/binary/hostaffinity保持。结果用于选择有实际热点依据的新优化，而不预测百分比或改变Foundation目标。

八项串行capture结束，共8,008,000完整JSON核验，lost均0，实际samples与近似eventcount见summary.json。perf.data.xz逐文件解压hash校验与capture相同，原始rawcache路径在manifest，不删除失败记录。自占summary见analysis.md，任何sample份额不作为吞吐/优化承诺。
