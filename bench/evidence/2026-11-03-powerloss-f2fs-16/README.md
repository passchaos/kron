# F2FS 16-trial child-VM abrupt-loss campaign

在F2FS 4-run campaign之后扩展到16个ACK边界。仍是child-VM SIGKILL，不是host物理掉电。

## 身份

- 源码：提交`55a91a8`（未改生产src）。
- writer：`ebb1a0bb20f0333e8d1bf9df8e3dcee654c3962b80400d3765d5b08e6a7cd47c`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- F2FS modules：`crc32_generic`、`lz4hc_compress`、`lz4_compress`、`f2fs`（完整hash见4-run报告）。
- F2FS 128MiB、QEMU TCG、`cache=writeback`、`-snapshot` verify boot、campaign seed `0x4B524F4E`。

## 结果

16/16通过；ACK边界：

`17, 31, 8, 3, 9, 40, 63, 59, 14, 23, 29, 19, 13, 57, 37, 14`

crash image SHA-256：

| run | ACK | crash image |
| ---: | ---: | --- |
| 0 | 17 | `e7ec5d8a42f8a350d1f19e19c52467c62398875791fe4dff5b9fa58deac47553` |
| 1 | 31 | `d7273e5b9ef8b429e27f137349143aad6b69f1cec604e503fc2f2e6bd30e6ffd` |
| 2 | 8 | `cd6b4c735bdc9d0af0ebd40c05d675a33b59d39fc5255d0b3bc7417f9829b3e3` |
| 3 | 3 | `861684617ee513f063e375ecba7789b95b6113628ce0a60b8d441951decb2cc9` |
| 4 | 9 | `803d0acabd50aac5b230b2e6b74febd73d61d81ce76511e4bf5fcfce501112f6` |
| 5 | 40 | `4fec5c59f8980b223833f9fc755815ffd239851313ac4aa4de892a745e4e3538` |
| 6 | 63 | `ec1e100a093d0901e7a02df04738682d5dd51e95dc561f5154d86bca86533341` |
| 7 | 59 | `cdba13d0cd7ac193eafde9b7b1db2383935ae5c442a83c9fe4a1df73137af45b` |
| 8 | 14 | `b29e11cedeab8b095289ebecb8195517cb66bd2c8d464664e40dc25096f64bbd` |
| 9 | 23 | `27342e74cf922d53dfdcb549bb8e62bd4b8b300db4fb80f2011cd4085f946187` |
| 10 | 29 | `e7e379c06e5b175d6dd7dbe66b736f6cec44c858f92a35693c3ad54d7c9d1923` |
| 11 | 19 | `3d14f0db02e061c26a68188ef9da9f701a989be089dfe2aac570ac497c65be51` |
| 12 | 13 | `1c6d75fce2afd71d0fd5894c9f209b10b11101ec717aab02ca7def8bd0ff9547` |
| 13 | 57 | `9240a8f5bb0ac2babb8954708857cce8b5864e2a7b4e3f0bc113a2e40d0f650b` |
| 14 | 37 | `bffa52594f1fac2a529dd5f081fce6f0bba298d0a860d178cf3f3fdff94fa8d3` |
| 15 | 14 | `cb06314f303abec33e33e8dedb9f534700ad96470b70cdfdaab91b3e3fe1e030` |

完整结果见[results.json](results.json)，串口输出见`run-00.log`…`run-15.log`与[campaign.log](campaign.log)。

## 边界

F2FS child-VM SIGKILL，不是物理host掉电；只断言已确认序列存活。没有NFS/CIFS/FUSE/真实设备资格。整体“业界最佳”目标仍未完成。
