# XFS 16-trial child-VM abrupt-loss campaign

在XFS 4-run campaign之后扩展到16个ACK边界，覆盖更多XFS journal replay与ring复用位置。仍是child-VM SIGKILL，不是host物理掉电。

## 身份

- 源码：提交`55a91a8`（未改生产src）。
- writer：`ebb1a0bb20f0333e8d1bf9df8e3dcee654c3962b80400d3765d5b08e6a7cd47c`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- XFS modules：`libcrc32c.ko` `59075d7c…`、`xfs.ko` `de0a1be3…`（完整hash见4-run报告）。
- XFS 512MiB、QEMU TCG、`cache=writeback`、`-snapshot` verify boot、campaign seed `0x4B524F4E`。

## 结果

16/16通过；ACK边界：

`17, 31, 8, 3, 9, 40, 63, 59, 14, 23, 29, 19, 13, 57, 37, 14`

每次verify确认最高generation checkpoint、journal/output high-water mark与通过ACK的完整JSON。crash image SHA-256：

| run | ACK | crash image |
| ---: | ---: | --- |
| 0 | 17 | `6fde2fdf8a14b21eb3f5bf2db23987519b4f70dacb993ec2d94c6d10e81d266f` |
| 1 | 31 | `d51f4cd35d029e2441da3de61a8e78858fa8dfd00ea617df77b0cd6776486f5a` |
| 2 | 8 | `f817c3d717d12458a7ee3a595598f8c358a45821742ae098a0092dd32af33e0d` |
| 3 | 3 | `feddc3b281adfeaf01ad7dac621706a2219ea57d4c5e0aba9202b51fc6fa2413` |
| 4 | 9 | `6fc7e57aab5162a216ff7aa941c55e855d438d0995fb077a83cc954007625abf` |
| 5 | 40 | `d6abd78856d9b0e9fedf9494cccef93d2ef27a9486b50fa9fdb3a5587a93b62a` |
| 6 | 63 | `4b5db4483a7140f3c9c9f3b540ebbdd6eaa57437e573904a1bcd21f97a0887b7` |
| 7 | 59 | `d8ba8a2ccf3563f048ba01685e116d3cc9a44ce88db77406fb95316253bce724` |
| 8 | 14 | `015b40a58f44f8fb99b029353eceb472a07be8bc1f4286453d889e61e5632f0e` |
| 9 | 23 | `403d15611b4f2a5e217d6a33ece1f41152e9f1deccf536d93a34727e0888abfb` |
| 10 | 29 | `4f0270dbbcbc4923be5f6184ff79a59e08d90fe68c7cf5d6a540c7fcf2bca8de` |
| 11 | 19 | `b3b305a1e27769e50489effd5971fae18eb92d60570d8d745aa3effedfd5777c` |
| 12 | 13 | `d9c6a0dbf4b490dd228e58a4fa01f67c48b22da27c719699981a29c66010fa37` |
| 13 | 57 | `2b7f4c6fb3bece8170a62149d3cdabd84e018091065210155e4dc661396979e9` |
| 14 | 37 | `a4fd9698a48578210b27b7e8a0d76bc0465e0371e8b4dda3db32c06c8446c648` |
| 15 | 14 | `558d6af5b529a3206c9fef6afacd39678fad3ab46f0cc71ec04636d4c0d1ebcf` |

完整结果见[results.json](results.json)，串口输出见`run-00.log`…`run-15.log`与[campaign.log](campaign.log)。

## 边界

这是XFS child-VM SIGKILL，不是物理host掉电；`cache=writeback`下未flush写入仍可能经host page cache到达backing file，因此只断言已确认序列存活。没有NFS/CIFS/FUSE/真实设备资格。整体“业界最佳”目标仍未完成。
