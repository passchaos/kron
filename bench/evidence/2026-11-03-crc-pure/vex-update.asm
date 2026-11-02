  191db0:	55                   	push   rbp
  191db1:	48 89 e5             	mov    rbp,rsp
  191db4:	48 81 ec 30 05 00 00 	sub    rsp,0x530
  191dbb:	89 84 24 20 05 00 00 	mov    DWORD PTR [rsp+0x520],eax
  191dc2:	48 89 94 24 30 04 00 00 	mov    QWORD PTR [rsp+0x430],rdx
  191dca:	48 89 9c 24 38 04 00 00 	mov    QWORD PTR [rsp+0x438],rbx
  191dd2:	48 89 94 24 40 04 00 00 	mov    QWORD PTR [rsp+0x440],rdx
  191dda:	48 89 9c 24 48 04 00 00 	mov    QWORD PTR [rsp+0x448],rbx
  191de2:	48 8b 94 24 48 04 00 00 	mov    rdx,QWORD PTR [rsp+0x448]
  191dea:	48 83 fa 40          	cmp    rdx,0x40
  191dee:	0f 82 36 00 00 00    	jb     191e2a <crc32_pclmul.update+0x7a>
  191df4:	48 8b 94 24 48 04 00 00 	mov    rdx,QWORD PTR [rsp+0x448]
  191dfc:	48 89 94 24 50 04 00 00 	mov    QWORD PTR [rsp+0x450],rdx
  191e04:	89 84 24 24 05 00 00 	mov    DWORD PTR [rsp+0x524],eax
  191e0b:	48 8b 84 24 50 04 00 00 	mov    rax,QWORD PTR [rsp+0x450]
  191e13:	bb 10 00 00 00       	mov    ebx,0x10
  191e18:	48 31 d2             	xor    rdx,rdx
  191e1b:	48 f7 f3             	div    rbx
  191e1e:	48 83 fa 00          	cmp    rdx,0x0
  191e22:	0f 94 c0             	sete   al
  191e25:	e9 0e 00 00 00       	jmp    191e38 <crc32_pclmul.update+0x88>
  191e2a:	89 84 24 24 05 00 00 	mov    DWORD PTR [rsp+0x524],eax
  191e31:	31 c0                	xor    eax,eax
  191e33:	e9 00 00 00 00       	jmp    191e38 <crc32_pclmul.update+0x88>
  191e38:	88 84 24 28 05 00 00 	mov    BYTE PTR [rsp+0x528],al
  191e3f:	8a 84 24 28 05 00 00 	mov    al,BYTE PTR [rsp+0x528]
  191e46:	e8 00 00 00 00       	call   191e4b <crc32_pclmul.update+0x9b>	191e47: R_X86_64_PLT32	debug.assert-0x4
  191e4b:	48 8b 84 24 40 04 00 00 	mov    rax,QWORD PTR [rsp+0x440]
  191e53:	48 89 84 24 58 04 00 00 	mov    QWORD PTR [rsp+0x458],rax
  191e5b:	48 8b 84 24 48 04 00 00 	mov    rax,QWORD PTR [rsp+0x448]
  191e63:	48 89 84 24 60 04 00 00 	mov    QWORD PTR [rsp+0x460],rax
  191e6b:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  191e73:	48 89 84 24 68 04 00 00 	mov    QWORD PTR [rsp+0x468],rax
  191e7b:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  191e7f:	c5 fa 7f 04 24       	vmovdqu XMMWORD PTR [rsp],xmm0
  191e84:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  191e89:	8b 84 24 24 05 00 00 	mov    eax,DWORD PTR [rsp+0x524]
  191e90:	48 89 44 24 10       	mov    QWORD PTR [rsp+0x10],rax
  191e95:	48 c7 44 24 18 00 00 00 00 	mov    QWORD PTR [rsp+0x18],0x0
  191e9e:	c5 f9 ef 4c 24 10    	vpxor  xmm1,xmm0,XMMWORD PTR [rsp+0x10]
  191ea4:	c5 fa 7f 0c 24       	vmovdqu XMMWORD PTR [rsp],xmm1
  191ea9:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  191eb1:	48 8d 50 10          	lea    rdx,[rax+0x10]
  191eb5:	48 89 94 24 70 04 00 00 	mov    QWORD PTR [rsp+0x470],rdx
  191ebd:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
  191ec1:	c5 fa 7f 44 24 20    	vmovdqu XMMWORD PTR [rsp+0x20],xmm0
  191ec7:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  191ecf:	48 8d 50 20          	lea    rdx,[rax+0x20]
  191ed3:	48 89 94 24 78 04 00 00 	mov    QWORD PTR [rsp+0x478],rdx
  191edb:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
  191edf:	c5 fa 7f 44 24 30    	vmovdqu XMMWORD PTR [rsp+0x30],xmm0
  191ee5:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  191eed:	48 8d 50 30          	lea    rdx,[rax+0x30]
  191ef1:	48 89 94 24 80 04 00 00 	mov    QWORD PTR [rsp+0x480],rdx
  191ef9:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
  191efd:	c5 fa 7f 44 24 40    	vmovdqu XMMWORD PTR [rsp+0x40],xmm0
  191f03:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  191f0b:	48 8d 50 40          	lea    rdx,[rax+0x40]
  191f0f:	48 89 94 24 58 04 00 00 	mov    QWORD PTR [rsp+0x458],rdx
  191f17:	48 8b 84 24 60 04 00 00 	mov    rax,QWORD PTR [rsp+0x460]
  191f1f:	48 83 e8 40          	sub    rax,0x40
  191f23:	48 89 84 24 88 04 00 00 	mov    QWORD PTR [rsp+0x488],rax
  191f2b:	0f 92 84 24 90 04 00 00 	setb   BYTE PTR [rsp+0x490]
  191f33:	8a 94 24 90 04 00 00 	mov    dl,BYTE PTR [rsp+0x490]
  191f3a:	48 89 84 24 98 04 00 00 	mov    QWORD PTR [rsp+0x498],rax
  191f42:	0f 92 84 24 a0 04 00 00 	setb   BYTE PTR [rsp+0x4a0]
  191f4a:	80 fa 01             	cmp    dl,0x1
  191f4d:	0f 85 05 00 00 00    	jne    191f58 <crc32_pclmul.update+0x1a8>
  191f53:	e8 00 00 00 00       	call   191f58 <crc32_pclmul.update+0x1a8>	191f54: R_X86_64_PLT32	debug.FullPanic((function 'defaultPanic')).integerOverflow-0x4
  191f58:	48 8b 84 24 98 04 00 00 	mov    rax,QWORD PTR [rsp+0x498]
  191f60:	e9 00 00 00 00       	jmp    191f65 <crc32_pclmul.update+0x1b5>
  191f65:	48 89 84 24 60 04 00 00 	mov    QWORD PTR [rsp+0x460],rax
  191f6d:	48 8b 84 24 60 04 00 00 	mov    rax,QWORD PTR [rsp+0x460]
  191f75:	48 83 f8 40          	cmp    rax,0x40
  191f79:	0f 82 e0 02 00 00    	jb     19225f <crc32_pclmul.update+0x4af>
  191f7f:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  191f84:	c5 fa 7f 44 24 50    	vmovdqu XMMWORD PTR [rsp+0x50],xmm0
  191f8a:	48 c7 c0 00 00 00 00 	mov    rax,0x0	191f8d: R_X86_64_32S	__anon_39308
  191f91:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  191f95:	c5 fa 7f 4c 24 60    	vmovdqu XMMWORD PTR [rsp+0x60],xmm1
  191f9b:	48 c7 c0 00 00 00 00 	mov    rax,0x0	191f9e: R_X86_64_32S	__anon_39308
  191fa2:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  191fa6:	c4 e3 79 44 ca 00    	vpclmullqlqdq xmm1,xmm0,xmm2
  191fac:	c5 fa 7f 4c 24 70    	vmovdqu XMMWORD PTR [rsp+0x70],xmm1
  191fb2:	c5 fa 6f 44 24 20    	vmovdqu xmm0,XMMWORD PTR [rsp+0x20]
  191fb8:	c5 fa 7f 84 24 80 00 00 00 	vmovdqu XMMWORD PTR [rsp+0x80],xmm0
  191fc1:	48 c7 c0 00 00 00 00 	mov    rax,0x0	191fc4: R_X86_64_32S	__anon_39308
  191fc8:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  191fcc:	c5 fa 7f 94 24 90 00 00 00 	vmovdqu XMMWORD PTR [rsp+0x90],xmm2
  191fd5:	48 c7 c0 00 00 00 00 	mov    rax,0x0	191fd8: R_X86_64_32S	__anon_39308
  191fdc:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  191fe0:	c4 e3 79 44 d3 00    	vpclmullqlqdq xmm2,xmm0,xmm3
  191fe6:	c5 fa 7f 94 24 a0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xa0],xmm2
  191fef:	c5 fa 6f 44 24 30    	vmovdqu xmm0,XMMWORD PTR [rsp+0x30]
  191ff5:	c5 fa 7f 84 24 b0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xb0],xmm0
  191ffe:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192001: R_X86_64_32S	__anon_39308
  192005:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  192009:	c5 fa 7f 9c 24 c0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xc0],xmm3
  192012:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192015: R_X86_64_32S	__anon_39308
  192019:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  19201d:	c4 e3 79 44 dc 00    	vpclmullqlqdq xmm3,xmm0,xmm4
  192023:	c5 fa 7f 9c 24 d0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xd0],xmm3
  19202c:	c5 fa 6f 44 24 40    	vmovdqu xmm0,XMMWORD PTR [rsp+0x40]
  192032:	c5 fa 7f 84 24 e0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xe0],xmm0
  19203b:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19203e: R_X86_64_32S	__anon_39308
  192042:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  192046:	c5 fa 7f a4 24 f0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xf0],xmm4
  19204f:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192052: R_X86_64_32S	__anon_39308
  192056:	c5 fa 6f 28          	vmovdqu xmm5,XMMWORD PTR [rax]
  19205a:	c4 e3 79 44 e5 00    	vpclmullqlqdq xmm4,xmm0,xmm5
  192060:	c5 fa 7f a4 24 00 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x100],xmm4
  192069:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  192071:	48 89 84 24 a8 04 00 00 	mov    QWORD PTR [rsp+0x4a8],rax
  192079:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  19207d:	c5 fa 7f 84 24 10 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x110],xmm0
  192086:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  19208e:	48 8d 50 10          	lea    rdx,[rax+0x10]
  192092:	48 89 94 24 b0 04 00 00 	mov    QWORD PTR [rsp+0x4b0],rdx
  19209a:	c5 fa 6f 2a          	vmovdqu xmm5,XMMWORD PTR [rdx]
  19209e:	c5 fa 7f ac 24 20 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x120],xmm5
  1920a7:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  1920af:	48 8d 50 20          	lea    rdx,[rax+0x20]
  1920b3:	48 89 94 24 b8 04 00 00 	mov    QWORD PTR [rsp+0x4b8],rdx
  1920bb:	c5 fa 6f 32          	vmovdqu xmm6,XMMWORD PTR [rdx]
  1920bf:	c5 fa 7f b4 24 30 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x130],xmm6
  1920c8:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  1920d0:	48 8d 50 30          	lea    rdx,[rax+0x30]
  1920d4:	48 89 94 24 c0 04 00 00 	mov    QWORD PTR [rsp+0x4c0],rdx
  1920dc:	c5 fa 6f 3a          	vmovdqu xmm7,XMMWORD PTR [rdx]
  1920e0:	c5 fa 7f bc 24 40 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x140],xmm7
  1920e9:	c5 7a 6f 04 24       	vmovdqu xmm8,XMMWORD PTR [rsp]
  1920ee:	c5 7a 7f 84 24 50 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x150],xmm8
  1920f7:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1920fa: R_X86_64_32S	__anon_39308
  1920fe:	c5 7a 6f 08          	vmovdqu xmm9,XMMWORD PTR [rax]
  192102:	c5 7a 7f 8c 24 60 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x160],xmm9
  19210b:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19210e: R_X86_64_32S	__anon_39308
  192112:	c5 7a 6f 10          	vmovdqu xmm10,XMMWORD PTR [rax]
  192116:	c4 43 39 44 ca 11    	vpclmulhqhqdq xmm9,xmm8,xmm10
  19211c:	c5 31 ef c1          	vpxor  xmm8,xmm9,xmm1
  192120:	c5 b9 ef c8          	vpxor  xmm1,xmm8,xmm0
  192124:	c5 fa 7f 0c 24       	vmovdqu XMMWORD PTR [rsp],xmm1
  192129:	c5 fa 6f 44 24 20    	vmovdqu xmm0,XMMWORD PTR [rsp+0x20]
  19212f:	c5 fa 7f 84 24 70 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x170],xmm0
  192138:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19213b: R_X86_64_32S	__anon_39308
  19213f:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192143:	c5 fa 7f 8c 24 80 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x180],xmm1
  19214c:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19214f: R_X86_64_32S	__anon_39308
  192153:	c5 7a 6f 00          	vmovdqu xmm8,XMMWORD PTR [rax]
  192157:	c4 c3 79 44 c8 11    	vpclmulhqhqdq xmm1,xmm0,xmm8
  19215d:	c5 f1 ef c2          	vpxor  xmm0,xmm1,xmm2
  192161:	c5 f9 ef cd          	vpxor  xmm1,xmm0,xmm5
  192165:	c5 fa 7f 4c 24 20    	vmovdqu XMMWORD PTR [rsp+0x20],xmm1
  19216b:	c5 fa 6f 44 24 30    	vmovdqu xmm0,XMMWORD PTR [rsp+0x30]
  192171:	c5 fa 7f 84 24 90 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x190],xmm0
  19217a:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19217d: R_X86_64_32S	__anon_39308
  192181:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192185:	c5 fa 7f 8c 24 a0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1a0],xmm1
  19218e:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192191: R_X86_64_32S	__anon_39308
  192195:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  192199:	c4 e3 79 44 ca 11    	vpclmulhqhqdq xmm1,xmm0,xmm2
  19219f:	c5 f1 ef c3          	vpxor  xmm0,xmm1,xmm3
  1921a3:	c5 f9 ef ce          	vpxor  xmm1,xmm0,xmm6
  1921a7:	c5 fa 7f 4c 24 30    	vmovdqu XMMWORD PTR [rsp+0x30],xmm1
  1921ad:	c5 fa 6f 44 24 40    	vmovdqu xmm0,XMMWORD PTR [rsp+0x40]
  1921b3:	c5 fa 7f 84 24 b0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1b0],xmm0
  1921bc:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1921bf: R_X86_64_32S	__anon_39308
  1921c3:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  1921c7:	c5 fa 7f 8c 24 c0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1c0],xmm1
  1921d0:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1921d3: R_X86_64_32S	__anon_39308
  1921d7:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  1921db:	c4 e3 79 44 ca 11    	vpclmulhqhqdq xmm1,xmm0,xmm2
  1921e1:	c5 f1 ef c4          	vpxor  xmm0,xmm1,xmm4
  1921e5:	c5 f9 ef cf          	vpxor  xmm1,xmm0,xmm7
  1921e9:	c5 fa 7f 4c 24 40    	vmovdqu XMMWORD PTR [rsp+0x40],xmm1
  1921ef:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  1921f7:	48 8d 50 40          	lea    rdx,[rax+0x40]
  1921fb:	48 89 94 24 58 04 00 00 	mov    QWORD PTR [rsp+0x458],rdx
  192203:	48 8b 84 24 60 04 00 00 	mov    rax,QWORD PTR [rsp+0x460]
  19220b:	48 83 e8 40          	sub    rax,0x40
  19220f:	48 89 84 24 c8 04 00 00 	mov    QWORD PTR [rsp+0x4c8],rax
  192217:	0f 92 84 24 d0 04 00 00 	setb   BYTE PTR [rsp+0x4d0]
  19221f:	8a 94 24 d0 04 00 00 	mov    dl,BYTE PTR [rsp+0x4d0]
  192226:	48 89 84 24 d8 04 00 00 	mov    QWORD PTR [rsp+0x4d8],rax
  19222e:	0f 92 84 24 e0 04 00 00 	setb   BYTE PTR [rsp+0x4e0]
  192236:	80 fa 01             	cmp    dl,0x1
  192239:	0f 85 05 00 00 00    	jne    192244 <crc32_pclmul.update+0x494>
  19223f:	e8 00 00 00 00       	call   192244 <crc32_pclmul.update+0x494>	192240: R_X86_64_PLT32	debug.FullPanic((function 'defaultPanic')).integerOverflow-0x4
  192244:	48 8b 84 24 d8 04 00 00 	mov    rax,QWORD PTR [rsp+0x4d8]
  19224c:	e9 00 00 00 00       	jmp    192251 <crc32_pclmul.update+0x4a1>
  192251:	48 89 84 24 60 04 00 00 	mov    QWORD PTR [rsp+0x460],rax
  192259:	90                   	nop
  19225a:	e9 05 00 00 00       	jmp    192264 <crc32_pclmul.update+0x4b4>
  19225f:	e9 05 00 00 00       	jmp    192269 <crc32_pclmul.update+0x4b9>
  192264:	e9 04 fd ff ff       	jmp    191f6d <crc32_pclmul.update+0x1bd>
  192269:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  19226e:	c5 fa 7f 84 24 d0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1d0],xmm0
  192277:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19227a: R_X86_64_32S	__anon_39318
  19227e:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192282:	c5 fa 7f 8c 24 e0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1e0],xmm1
  19228b:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19228e: R_X86_64_32S	__anon_39318
  192292:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  192296:	c4 e3 79 44 ca 00    	vpclmullqlqdq xmm1,xmm0,xmm2
  19229c:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  1922a1:	c5 fa 7f 84 24 f0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1f0],xmm0
  1922aa:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1922ad: R_X86_64_32S	__anon_39318
  1922b1:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  1922b5:	c5 fa 7f 94 24 00 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x200],xmm2
  1922be:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1922c1: R_X86_64_32S	__anon_39318
  1922c5:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  1922c9:	c4 e3 79 44 d3 11    	vpclmulhqhqdq xmm2,xmm0,xmm3
  1922cf:	c5 f1 ef c2          	vpxor  xmm0,xmm1,xmm2
  1922d3:	c5 fa 7f 84 24 10 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x210],xmm0
  1922dc:	c5 fa 6f 4c 24 20    	vmovdqu xmm1,XMMWORD PTR [rsp+0x20]
  1922e2:	c5 fa 7f 8c 24 20 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x220],xmm1
  1922eb:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1922ee: R_X86_64_32S	__anon_39324
  1922f2:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  1922f6:	c5 fa 7f 94 24 30 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x230],xmm2
  1922ff:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192302: R_X86_64_32S	__anon_39324
  192306:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  19230a:	c4 e3 71 44 d3 00    	vpclmullqlqdq xmm2,xmm1,xmm3
  192310:	c5 fa 6f 4c 24 20    	vmovdqu xmm1,XMMWORD PTR [rsp+0x20]
  192316:	c5 fa 7f 8c 24 40 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x240],xmm1
  19231f:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192322: R_X86_64_32S	__anon_39324
  192326:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  19232a:	c5 fa 7f 9c 24 50 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x250],xmm3
  192333:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192336: R_X86_64_32S	__anon_39324
  19233a:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  19233e:	c4 e3 71 44 dc 11    	vpclmulhqhqdq xmm3,xmm1,xmm4
  192344:	c5 e9 ef cb          	vpxor  xmm1,xmm2,xmm3
  192348:	c5 fa 7f 8c 24 60 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x260],xmm1
  192351:	c5 fa 6f 54 24 30    	vmovdqu xmm2,XMMWORD PTR [rsp+0x30]
  192357:	c5 fa 7f 94 24 70 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x270],xmm2
  192360:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192363: R_X86_64_32S	__anon_39330
  192367:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  19236b:	c5 fa 7f 9c 24 80 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x280],xmm3
  192374:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192377: R_X86_64_32S	__anon_39330
  19237b:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  19237f:	c4 e3 69 44 dc 00    	vpclmullqlqdq xmm3,xmm2,xmm4
  192385:	c5 fa 6f 54 24 30    	vmovdqu xmm2,XMMWORD PTR [rsp+0x30]
  19238b:	c5 fa 7f 94 24 90 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x290],xmm2
  192394:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192397: R_X86_64_32S	__anon_39330
  19239b:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  19239f:	c5 fa 7f a4 24 a0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2a0],xmm4
  1923a8:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1923ab: R_X86_64_32S	__anon_39330
  1923af:	c5 fa 6f 28          	vmovdqu xmm5,XMMWORD PTR [rax]
  1923b3:	c4 e3 69 44 e5 11    	vpclmulhqhqdq xmm4,xmm2,xmm5
  1923b9:	c5 e1 ef d4          	vpxor  xmm2,xmm3,xmm4
  1923bd:	c5 fa 7f 94 24 b0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2b0],xmm2
  1923c6:	c5 f9 ef d9          	vpxor  xmm3,xmm0,xmm1
  1923ca:	c5 e1 ef c2          	vpxor  xmm0,xmm3,xmm2
  1923ce:	c5 fa 6f 4c 24 40    	vmovdqu xmm1,XMMWORD PTR [rsp+0x40]
  1923d4:	c5 f9 ef d1          	vpxor  xmm2,xmm0,xmm1
  1923d8:	c5 fa 7f 14 24       	vmovdqu XMMWORD PTR [rsp],xmm2
  1923dd:	48 8d 84 24 c0 02 00 00 	lea    rax,[rsp+0x2c0]
  1923e5:	48 89 84 24 e8 04 00 00 	mov    QWORD PTR [rsp+0x4e8],rax
  1923ed:	48 8b bc 24 e8 04 00 00 	mov    rdi,QWORD PTR [rsp+0x4e8]
  1923f5:	c6 84 24 29 05 00 00 aa 	mov    BYTE PTR [rsp+0x529],0xaa
  1923fd:	8a 84 24 29 05 00 00 	mov    al,BYTE PTR [rsp+0x529]
  192404:	48 c7 84 24 f0 04 00 00 10 00 00 00 	mov    QWORD PTR [rsp+0x4f0],0x10
  192410:	48 8b 8c 24 f0 04 00 00 	mov    rcx,QWORD PTR [rsp+0x4f0]
  192418:	f3 aa                	rep stos BYTE PTR es:[rdi],al
  19241a:	48 8b 84 24 60 04 00 00 	mov    rax,QWORD PTR [rsp+0x460]
  192422:	48 83 f8 10          	cmp    rax,0x10
  192426:	0f 82 15 01 00 00    	jb     192541 <crc32_pclmul.update+0x791>
  19242c:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  192434:	48 89 84 24 f8 04 00 00 	mov    QWORD PTR [rsp+0x4f8],rax
  19243c:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  192440:	c5 fa 7f 44 24 20    	vmovdqu XMMWORD PTR [rsp+0x20],xmm0
  192446:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  19244b:	c5 fa 7f 84 24 d0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2d0],xmm0
  192454:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192457: R_X86_64_32S	__anon_39330
  19245b:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  19245f:	c5 fa 7f 8c 24 e0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2e0],xmm1
  192468:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19246b: R_X86_64_32S	__anon_39330
  19246f:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  192473:	c4 e3 79 44 ca 00    	vpclmullqlqdq xmm1,xmm0,xmm2
  192479:	c5 fa 7f 8c 24 c0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2c0],xmm1
  192482:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  192487:	c5 fa 7f 84 24 f0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2f0],xmm0
  192490:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192493: R_X86_64_32S	__anon_39330
  192497:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  19249b:	c5 fa 7f 8c 24 00 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x300],xmm1
  1924a4:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1924a7: R_X86_64_32S	__anon_39330
  1924ab:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  1924af:	c4 e3 79 44 ca 11    	vpclmulhqhqdq xmm1,xmm0,xmm2
  1924b5:	c5 fa 6f 44 24 20    	vmovdqu xmm0,XMMWORD PTR [rsp+0x20]
  1924bb:	c5 f1 ef d0          	vpxor  xmm2,xmm1,xmm0
  1924bf:	c5 fa 6f 84 24 c0 02 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x2c0]
  1924c8:	c5 e9 ef c8          	vpxor  xmm1,xmm2,xmm0
  1924cc:	c5 fa 7f 0c 24       	vmovdqu XMMWORD PTR [rsp],xmm1
  1924d1:	48 8b 84 24 58 04 00 00 	mov    rax,QWORD PTR [rsp+0x458]
  1924d9:	48 8d 50 10          	lea    rdx,[rax+0x10]
  1924dd:	48 89 94 24 58 04 00 00 	mov    QWORD PTR [rsp+0x458],rdx
  1924e5:	48 8b 84 24 60 04 00 00 	mov    rax,QWORD PTR [rsp+0x460]
  1924ed:	48 83 e8 10          	sub    rax,0x10
  1924f1:	48 89 84 24 00 05 00 00 	mov    QWORD PTR [rsp+0x500],rax
  1924f9:	0f 92 84 24 08 05 00 00 	setb   BYTE PTR [rsp+0x508]
  192501:	8a 94 24 08 05 00 00 	mov    dl,BYTE PTR [rsp+0x508]
  192508:	48 89 84 24 10 05 00 00 	mov    QWORD PTR [rsp+0x510],rax
  192510:	0f 92 84 24 18 05 00 00 	setb   BYTE PTR [rsp+0x518]
  192518:	80 fa 01             	cmp    dl,0x1
  19251b:	0f 85 05 00 00 00    	jne    192526 <crc32_pclmul.update+0x776>
  192521:	e8 00 00 00 00       	call   192526 <crc32_pclmul.update+0x776>	192522: R_X86_64_PLT32	debug.FullPanic((function 'defaultPanic')).integerOverflow-0x4
  192526:	48 8b 84 24 10 05 00 00 	mov    rax,QWORD PTR [rsp+0x510]
  19252e:	e9 00 00 00 00       	jmp    192533 <crc32_pclmul.update+0x783>
  192533:	48 89 84 24 60 04 00 00 	mov    QWORD PTR [rsp+0x460],rax
  19253b:	90                   	nop
  19253c:	e9 05 00 00 00       	jmp    192546 <crc32_pclmul.update+0x796>
  192541:	e9 05 00 00 00       	jmp    19254b <crc32_pclmul.update+0x79b>
  192546:	e9 cf fe ff ff       	jmp    19241a <crc32_pclmul.update+0x66a>
  19254b:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  192550:	c5 fa 7f 84 24 10 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x310],xmm0
  192559:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19255c: R_X86_64_32S	__anon_39330
  192560:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192564:	c5 fa 7f 8c 24 20 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x320],xmm1
  19256d:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192570: R_X86_64_32S	__anon_39330
  192574:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  192578:	c4 e3 79 44 ca 10    	vpclmullqhqdq xmm1,xmm0,xmm2
  19257e:	c5 fa 7f 8c 24 30 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x330],xmm1
  192587:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  19258c:	c5 fa 7f 84 24 40 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x340],xmm0
  192595:	c5 fa 7f 84 24 50 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x350],xmm0
  19259e:	c5 fa 7f 8c 24 60 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x360],xmm1
  1925a7:	c5 f9 6f 84 24 50 03 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x350]
  1925b0:	31 c0                	xor    eax,eax
  1925b2:	e8 00 00 00 00       	call   1925b7 <crc32_pclmul.update+0x807>	1925b3: R_X86_64_PLT32	simd.shiftElementsLeft__anon_39350-0x4
  1925b7:	c5 f9 ef 8c 24 60 03 00 00 	vpxor  xmm1,xmm0,XMMWORD PTR [rsp+0x360]
  1925c0:	c5 fa 7f 0c 24       	vmovdqu XMMWORD PTR [rsp],xmm1
  1925c5:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  1925ca:	c5 fa 7f 84 24 70 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x370],xmm0
  1925d3:	c5 f9 6f c8          	vmovdqa xmm1,xmm0
  1925d7:	c5 fa 7f 8c 24 80 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x380],xmm1
  1925e0:	c5 fa 7f 8c 24 90 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x390],xmm1
  1925e9:	c5 f9 6f 84 24 90 03 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x390]
  1925f2:	31 c0                	xor    eax,eax
  1925f4:	e8 00 00 00 00       	call   1925f9 <crc32_pclmul.update+0x849>	1925f5: R_X86_64_PLT32	simd.shiftElementsLeft__anon_39362-0x4
  1925f9:	c5 f9 6f c8          	vmovdqa xmm1,xmm0
  1925fd:	c5 fa 7f 8c 24 a0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3a0],xmm1
  192606:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  19260b:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19260e: R_X86_64_32S	__anon_39363
  192612:	c5 f9 db 10          	vpand  xmm2,xmm0,XMMWORD PTR [rax]
  192616:	c5 fa 7f 14 24       	vmovdqu XMMWORD PTR [rsp],xmm2
  19261b:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  192620:	c5 fa 7f 84 24 b0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3b0],xmm0
  192629:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19262c: R_X86_64_32S	__anon_39367
  192630:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  192634:	c5 fa 7f 94 24 c0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3c0],xmm2
  19263d:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192640: R_X86_64_32S	__anon_39367
  192644:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  192648:	c4 e3 79 44 d3 00    	vpclmullqlqdq xmm2,xmm0,xmm3
  19264e:	c5 e9 ef c1          	vpxor  xmm0,xmm2,xmm1
  192652:	c5 fa 7f 04 24       	vmovdqu XMMWORD PTR [rsp],xmm0
  192657:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  19265c:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19265f: R_X86_64_32S	__anon_39363
  192663:	c5 f9 db 08          	vpand  xmm1,xmm0,XMMWORD PTR [rax]
  192667:	c5 fa 7f 8c 24 d0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3d0],xmm1
  192670:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192673: R_X86_64_32S	__anon_39373
  192677:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  19267b:	c5 fa 7f 84 24 e0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3e0],xmm0
  192684:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192687: R_X86_64_32S	__anon_39373
  19268b:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  19268f:	c4 e3 71 44 c2 10    	vpclmullqhqdq xmm0,xmm1,xmm2
  192695:	c5 fa 7f 84 24 f0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3f0],xmm0
  19269e:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1926a1: R_X86_64_32S	__anon_39363
  1926a5:	c5 f9 db 08          	vpand  xmm1,xmm0,XMMWORD PTR [rax]
  1926a9:	c5 fa 7f 8c 24 00 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x400],xmm1
  1926b2:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1926b5: R_X86_64_32S	__anon_39373
  1926b9:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  1926bd:	c5 fa 7f 84 24 10 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x410],xmm0
  1926c6:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1926c9: R_X86_64_32S	__anon_39373
  1926cd:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  1926d1:	c4 e3 71 44 c2 00    	vpclmullqlqdq xmm0,xmm1,xmm2
  1926d7:	c5 fa 7f 84 24 20 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x420],xmm0
  1926e0:	c5 fa 6f 0c 24       	vmovdqu xmm1,XMMWORD PTR [rsp]
  1926e5:	c5 f1 ef d0          	vpxor  xmm2,xmm1,xmm0
  1926e9:	c5 fa 7f 14 24       	vmovdqu XMMWORD PTR [rsp],xmm2
  1926ee:	48 8d 04 24          	lea    rax,[rsp]
  1926f2:	31 d2                	xor    edx,edx
  1926f4:	48 8d 04 d0          	lea    rax,[rax+rdx*8]
  1926f8:	48 8b 10             	mov    rdx,QWORD PTR [rax]
  1926fb:	48 c1 ea 20          	shr    rdx,0x20
  1926ff:	89 d0                	mov    eax,edx
  192701:	48 89 ec             	mov    rsp,rbp
  192704:	5d                   	pop    rbp
  192705:	c3                   	ret
	...
