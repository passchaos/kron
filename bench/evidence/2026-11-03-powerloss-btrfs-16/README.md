# Btrfs 16-trial child-VM abrupt-loss campaign

在Btrfs 4-run campaign之后扩展到16个ACK边界。仍是child-VM SIGKILL，不是host物理掉电。

## 身份

- 源码：提交`55a91a8`（未改生产src）。
- writer：`ebb1a0bb20f0333e8d1bf9df8e3dcee654c3962b80400d3765d5b08e6a7cd47c`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- Btrfs modules：`xor`、`raid6_pq`、`libcrc32c`、`btrfs`（完整hash见4-run报告）。
- Btrfs 512MiB、QEMU TCG、`cache=writeback`、`-snapshot` verify boot、campaign seed `0x4B524F4E`。

## 结果

16/16通过；ACK边界：

`17, 31, 8, 3, 9, 40, 63, 59, 14, 23, 29, 19, 13, 57, 37, 14`

crash image SHA-256：

| run | ACK | crash image |
| ---: | ---: | --- |
| 0 | 17 | `943bfd4a3d1cd34940039dbb790d5877cefa3d2194c77974fce5f2b216d68be6` |
| 1 | 31 | `c968036bfa4a556e17c8c2c60a408af40a26139b45e16fd436aa3a3d27cc0355` |
| 2 | 8 | `478f9f90c9ee3fec6365d438e606ae6ddda03767f375043beeb0beeae3f68d0c` |
| 3 | 3 | `2df8ac7ea2236766f9c1528b28f67dce705c6d40c4de5a4e826503ec18b72c21` |
| 4 | 9 | `84bb4d9eae4b5e68a96025024a32df1cf0ffefbe02229557b12a84e4a7fde934` |
| 5 | 40 | `ab63abd1dda30c109ad2419bb5f67054c51d5db25b3eeb89a389adc58934741f` |
| 6 | 63 | `32534f4cffe0d869f7807ab0a695ed690c8d040d3ec08eb93d609f19358e4ff2` |
| 7 | 59 | `59b1c49d00589eb21cf43de9218739adff3168f7904b68beb0ee13c528208b48` |
| 8 | 14 | `c23f11439901ac8586427c114fdb4ddd0ea8f9d0c1d780a9429dea28cc4ee77f` |
| 9 | 23 | `66861e9b4892cbd2e034e1e173d47a338661f85fb1372c6c0b9c0746bc9954e1` |
| 10 | 29 | `a6b1e934cff99b660204df6a9bec7e9295b2a4b09de46336430fd405183e0fc4` |
| 11 | 19 | `e562484368bd89e74791ca2e8c51ef0e0bf04cb0b591f3e05b799f3a03ca1e31` |
| 12 | 13 | `f8292710aff47326b9ef2d19683ead5d9c34c2a808d3a565c7893f1fbc49adfc` |
| 13 | 57 | `01c20c00d97d6f8c1210be81001d9af6d174831bb09f4189f3ff4b58ac2eb27b` |
| 14 | 37 | `5cdbef9158bce9675a96a2c8d5876cdaf3128807b8577edd6076c65aaebee94a` |
| 15 | 14 | `adc73d07715a17c3863c209937c88b0221fb8fc890134c1ce9028b6aa1abb089` |

完整结果见[results.json](results.json)，串口输出见`run-00.log`…`run-15.log`与[campaign.log](campaign.log)。

## 边界

Btrfs child-VM SIGKILL，不是物理host掉电；只断言已确认序列存活。没有NFS/CIFS/FUSE/真实设备资格。整体“业界最佳”目标仍未完成。
