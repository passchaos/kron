# 当前Mmap初始化诊断

源码 `ce5aae9`，Zig0.16 ReleaseFast/native，实际portable文件输出。二进制与build身份见 [identity.json](identity.json)，拥有源码hash见 [qualification.json](qualification.json)。本轮只定位启动成本，不修改生产代码，也不建立跨库排名。

四个strace进程，各自运行sampled/batch两个完整阶段；Memory/Mmap、shared/SPSC、四producer、每阶段1000事件及100预热，默认256槽、16KiB记录、64KiB文件缓冲，无schema与durable选项。逐条核对8个物理文件，共8800条合法JSON：身份唯一、每channel sequence递增、五字段数值连续、实际bytes与报告一致；测量accepted=written=1000、pending/drop/errors=0。

| 配置 | 两阶段初始化ms | fallocate次数 | fsync次数 | 全进程fsync总ms |
| --- | --- | ---: | ---: | ---: |
| async-memory | 4.152, 3.831 | 0 | 0 | 0 |
| async-mmap | 1478.320, 204.480 | 2 | 4 | 1659.786 |
| spsc-memory | 15.838, 13.084 | 0 | 0 | 0 |
| spsc-mmap | 562.331, 776.033 | 10 | 20 | 1296.923 |

Mmap trace中的文件/目录fsync耗时占主要部分；shared两阶段分别一个journal，SPSC分别共享加四个channel。Memory没有这些文件发布调用。mmap次数也包含allocator与其他运行期映射，不能当成journal数量。fsync耗时总和是整个进程范围，与两段init的差值包含其他工作与追踪扰动。

命令模板（每配置使用独立work-dir）：

```sh
zig build-exe -O ReleaseFast -mcpu=native --dep kron -Mroot=bench/main.zig \
  -O ReleaseFast -mcpu=native -Mkron=src/root.zig -femit-bin=.zig-cache/kron-current-init-profile
strace -f -qq -ttt -T -e trace=fallocate,mmap,msync,fsync -o TRACE \
  .zig-cache/kron-current-init-profile --mode=spsc --storage=mmap --producers=4 \
  --sink=file --backend=portable --events=1000 --samples=1000 --warmup-events=100 --work-dir=FRESH_PATH
```

最初使用了错误的 `--warmup` 参数，未进入trial，错误单独保存在argument-error.stderr；成功数据使用公开的warmup-events选项。原始trace和全部阶段行保留。

## 后续候选

拥有源码显示fresh映射先prefault可写页，journal初始化随后清零整个映射，再执行文件与目录发布。后续应研究首次初始化的dirty-page/发布工作量，先证明Linux映射/预分配与fresh-zero契约，再以相同record预算、完整JSON、正常/故障恢复和持久化屏障做对照。不能直接删除fsync或把page fault移到producer来宣传启动更快。

目前只确认诊断方向，不承诺收益；单次strace不能提供低噪声性能资格。常规Memory默认模式与完整目标的其余差距见 [当前验收状态](../../../docs/implementation-status.md)。
