# V3 child-VM abrupt loss重跑

V3 schema journal与nested/rolling/reopen回归之后，用当前HEAD重新执行QEMU子VM突发终止门禁，验证V3 journal在真实guest ext4与durable checkpoint下仍满足“已确认记录全部存活”的契约。

## 身份

- 源码HEAD：`92368f8a4db36ea468f9912e41f18fb62281b846`。
- writer：`zig build powerloss-writer -Doptimize=ReleaseSafe -j1`，SHA-256 `ac1960443590a075019a9aca41c54857fb7b78f5ef5fe8eb24798993030f5058`。
- guest kernel：Ubuntu `linux-image-unsigned-6.8.0-147-generic`，SHA-256 `a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：静态`/usr/bin/busybox`，SHA-256 `dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- QEMU TCG、`cache=writeback`、ext4、128MiB（campaign）或256MiB（单次）scratch image；未使用KVM，未在host挂载测试文件系统。

## 执行与结果

单次非schema路径：

```sh
python3 tests/power_loss/vm_powerloss.py \
  --testwriter zig-out/bin/kron-powerloss-writer \
  --work-dir /tmp/kron-power-loss-v3
```

结果：`KRON_ACK seq=1`、`KRON_CHECKPOINT_OK seq=1 acked=1`、`KRON_VERIFY_OK acked=1`，PASS。日志见[single-run-writer.log](single-run-writer.log)、[single-run-verify.log](single-run-verify.log)与[single-run-e2fsck.log](single-run-e2fsck.log)。

有界重复schema路径：

```sh
python3 tests/power_loss/campaign.py \
  --testwriter zig-out/bin/kron-powerloss-writer \
  --kernel /tmp/kron-power-loss-v3/kernel/extracted/boot/vmlinuz-6.8.0-147-generic \
  --busybox /tmp/kron-power-loss-v3/initramfs/bin/busybox \
  --output-dir /tmp/kron-powerloss-campaign-v3 --runs 4
```

campaign固定`--schema`，覆盖V3 schema journal/prepared schema引用路径。4/4通过：

| run | kill after ACK | verify | crash image SHA-256 |
| --- | ---: | --- | --- |
| 0 | 17 | `KRON_VERIFY_OK acked=17` | `c2c40fd150354507fb7218908678d149c8a712bf3cc3b64a38839aef396525b7` |
| 1 | 31 | `KRON_VERIFY_OK acked=31` | `ef9ca62bd9ef22c37bcc1e04cfa12cc399810e5c84439412ea3bf2998f6e954a` |
| 2 | 8 | `KRON_VERIFY_OK acked=8` | `2f3e2d8f698961f1470cecc5261bb8fcd9ac4cdca43253f892de110718d780e5` |
| 3 | 3 | `KRON_VERIFY_OK acked=3` | `566d68d3572c69648b6148b221831d10ee40d45379e621f983e728f607e4fe6c` |

完整机器可读结果与逐run命令见[results.json](results.json)，原始串口输出见[run-00.log](run-00.log)、[run-01.log](run-01.log)、[run-02.log](run-02.log)、[run-03.log](run-03.log)与[campaign.log](campaign.log)。

## 验证语义

writer每个记录在public durable flush返回后打印`KRON_ACK seq=N`并继续写入；host在指定ACK边界向QEMU进程发送SIGKILL。verify在`-snapshot`第二boot中确认：

- journal recovery接受一个有效最高generation checkpoint；
- journal/output high-water marks至少达到ACK N；
- 通过N的每条已确认JSON记录都存在且有效；
- malformed tail、重复序号或gap失败。

## 边界

这是**子VM突发终止**，不是host物理掉电：guest flush被`cache=writeback`尊重，但未flush写入仍可能经host page cache到达backing file；因此只断言已确认序列存活，不断言未确认序列缺失。也未覆盖多文件系统/设备、真实电源切断、KVM设备直通或其他guest内核。整体“业界最佳”目标仍未完成。
