# wire tag与payload合并写出：已否决

基线`bc908cc`包含checked wire typed visitor、内联scalar渲染和JSON固定metadata直接tag写入。候选只改`src/core/wire_write.zig`：把scalar的tag与固定宽度payload、string/bytes的tag与length、array/group的tag与count合并到一次`output.put`，wire字节与分开`int`调用完全相同。

## 决策

30项普通encoder probe交替PMU，每项300,000次scalar5/nested20/wide5编码、变动数值与完整输出hash。JSON instructions中位比值0.999973（−0.003%），cycles +0.24%，三个case在−0.09%–+0.46%内且中位区间全部重叠；text/logfmt同样全部重叠。三种格式的完整输出checksum/bytes一致。

没有取得可测的用户态工作量减少，未运行完整shared PMU或workflow，也没有把0.003%的instruction差异当作收益。生产源码已恢复到`bc908cc`；候选源码和binary仅保留在`candidate-source.tar.xz`/provenance，防止重复实验。

## 身份与复现

`before-provenance.json`固定基线源码/二进制，`after-provenance.json`固定候选；`encoder-trials/`、`encoder-results.jsonl`、`encoder-comparison.json`保存全部30项原始CSV/row与慢值。复现命令：

```sh
python3 bench/evidence/2026-11-02-wire-tag-batching/encoder_compare.py
```

该脚本拒绝覆盖已有捕获；复跑前应复制到新的evidence目录。此轮不涉及完整文件、shared队列、尾部或跨库排名。
