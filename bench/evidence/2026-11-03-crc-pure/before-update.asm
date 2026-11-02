  191db0:	55                   	push   rbp
  191db1:	48 89 e5             	mov    rbp,rsp
  191db4:	48 81 ec 70 06 00 00 	sub    rsp,0x670
  191dbb:	89 84 24 60 06 00 00 	mov    DWORD PTR [rsp+0x660],eax
  191dc2:	48 89 94 24 70 05 00 00 	mov    QWORD PTR [rsp+0x570],rdx
  191dca:	48 89 9c 24 78 05 00 00 	mov    QWORD PTR [rsp+0x578],rbx
  191dd2:	48 89 94 24 80 05 00 00 	mov    QWORD PTR [rsp+0x580],rdx
  191dda:	48 89 9c 24 88 05 00 00 	mov    QWORD PTR [rsp+0x588],rbx
  191de2:	48 8b 94 24 88 05 00 00 	mov    rdx,QWORD PTR [rsp+0x588]
  191dea:	48 83 fa 40          	cmp    rdx,0x40
  191dee:	0f 82 36 00 00 00    	jb     191e2a <crc32_pclmul.update+0x7a>
  191df4:	48 8b 94 24 88 05 00 00 	mov    rdx,QWORD PTR [rsp+0x588]
  191dfc:	48 89 94 24 90 05 00 00 	mov    QWORD PTR [rsp+0x590],rdx
  191e04:	89 84 24 64 06 00 00 	mov    DWORD PTR [rsp+0x664],eax
  191e0b:	48 8b 84 24 90 05 00 00 	mov    rax,QWORD PTR [rsp+0x590]
  191e13:	bb 10 00 00 00       	mov    ebx,0x10
  191e18:	48 31 d2             	xor    rdx,rdx
  191e1b:	48 f7 f3             	div    rbx
  191e1e:	48 83 fa 00          	cmp    rdx,0x0
  191e22:	0f 94 c0             	sete   al
  191e25:	e9 0e 00 00 00       	jmp    191e38 <crc32_pclmul.update+0x88>
  191e2a:	89 84 24 64 06 00 00 	mov    DWORD PTR [rsp+0x664],eax
  191e31:	31 c0                	xor    eax,eax
  191e33:	e9 00 00 00 00       	jmp    191e38 <crc32_pclmul.update+0x88>
  191e38:	88 84 24 68 06 00 00 	mov    BYTE PTR [rsp+0x668],al
  191e3f:	8a 84 24 68 06 00 00 	mov    al,BYTE PTR [rsp+0x668]
  191e46:	e8 00 00 00 00       	call   191e4b <crc32_pclmul.update+0x9b>	191e47: R_X86_64_PLT32	debug.assert-0x4
  191e4b:	48 8b 84 24 80 05 00 00 	mov    rax,QWORD PTR [rsp+0x580]
  191e53:	48 89 84 24 98 05 00 00 	mov    QWORD PTR [rsp+0x598],rax
  191e5b:	48 8b 84 24 88 05 00 00 	mov    rax,QWORD PTR [rsp+0x588]
  191e63:	48 89 84 24 a0 05 00 00 	mov    QWORD PTR [rsp+0x5a0],rax
  191e6b:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  191e73:	48 89 84 24 a8 05 00 00 	mov    QWORD PTR [rsp+0x5a8],rax
  191e7b:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  191e7f:	c5 fa 7f 04 24       	vmovdqu XMMWORD PTR [rsp],xmm0
  191e84:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  191e89:	8b 84 24 64 06 00 00 	mov    eax,DWORD PTR [rsp+0x664]
  191e90:	48 89 44 24 10       	mov    QWORD PTR [rsp+0x10],rax
  191e95:	48 c7 44 24 18 00 00 00 00 	mov    QWORD PTR [rsp+0x18],0x0
  191e9e:	c5 f9 ef 4c 24 10    	vpxor  xmm1,xmm0,XMMWORD PTR [rsp+0x10]
  191ea4:	c5 fa 7f 0c 24       	vmovdqu XMMWORD PTR [rsp],xmm1
  191ea9:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  191eb1:	48 8d 50 10          	lea    rdx,[rax+0x10]
  191eb5:	48 89 94 24 b0 05 00 00 	mov    QWORD PTR [rsp+0x5b0],rdx
  191ebd:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
  191ec1:	c5 fa 7f 44 24 20    	vmovdqu XMMWORD PTR [rsp+0x20],xmm0
  191ec7:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  191ecf:	48 8d 50 20          	lea    rdx,[rax+0x20]
  191ed3:	48 89 94 24 b8 05 00 00 	mov    QWORD PTR [rsp+0x5b8],rdx
  191edb:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
  191edf:	c5 fa 7f 44 24 30    	vmovdqu XMMWORD PTR [rsp+0x30],xmm0
  191ee5:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  191eed:	48 8d 50 30          	lea    rdx,[rax+0x30]
  191ef1:	48 89 94 24 c0 05 00 00 	mov    QWORD PTR [rsp+0x5c0],rdx
  191ef9:	c5 fa 6f 02          	vmovdqu xmm0,XMMWORD PTR [rdx]
  191efd:	c5 fa 7f 44 24 40    	vmovdqu XMMWORD PTR [rsp+0x40],xmm0
  191f03:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  191f0b:	48 8d 50 40          	lea    rdx,[rax+0x40]
  191f0f:	48 89 94 24 98 05 00 00 	mov    QWORD PTR [rsp+0x598],rdx
  191f17:	48 8b 84 24 a0 05 00 00 	mov    rax,QWORD PTR [rsp+0x5a0]
  191f1f:	48 83 e8 40          	sub    rax,0x40
  191f23:	48 89 84 24 c8 05 00 00 	mov    QWORD PTR [rsp+0x5c8],rax
  191f2b:	0f 92 84 24 d0 05 00 00 	setb   BYTE PTR [rsp+0x5d0]
  191f33:	8a 94 24 d0 05 00 00 	mov    dl,BYTE PTR [rsp+0x5d0]
  191f3a:	48 89 84 24 d8 05 00 00 	mov    QWORD PTR [rsp+0x5d8],rax
  191f42:	0f 92 84 24 e0 05 00 00 	setb   BYTE PTR [rsp+0x5e0]
  191f4a:	80 fa 01             	cmp    dl,0x1
  191f4d:	0f 85 05 00 00 00    	jne    191f58 <crc32_pclmul.update+0x1a8>
  191f53:	e8 00 00 00 00       	call   191f58 <crc32_pclmul.update+0x1a8>	191f54: R_X86_64_PLT32	debug.FullPanic((function 'defaultPanic')).integerOverflow-0x4
  191f58:	48 8b 84 24 d8 05 00 00 	mov    rax,QWORD PTR [rsp+0x5d8]
  191f60:	e9 00 00 00 00       	jmp    191f65 <crc32_pclmul.update+0x1b5>
  191f65:	48 89 84 24 a0 05 00 00 	mov    QWORD PTR [rsp+0x5a0],rax
  191f6d:	48 8b 84 24 a0 05 00 00 	mov    rax,QWORD PTR [rsp+0x5a0]
  191f75:	48 83 f8 40          	cmp    rax,0x40
  191f79:	0f 82 f8 03 00 00    	jb     192377 <crc32_pclmul.update+0x5c7>
  191f7f:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  191f84:	c5 fa 7f 44 24 50    	vmovdqu XMMWORD PTR [rsp+0x50],xmm0
  191f8a:	48 c7 c0 00 00 00 00 	mov    rax,0x0	191f8d: R_X86_64_32S	__anon_39310
  191f91:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  191f95:	c5 fa 7f 4c 24 60    	vmovdqu XMMWORD PTR [rsp+0x60],xmm1
  191f9b:	c5 fa 7f 44 24 70    	vmovdqu XMMWORD PTR [rsp+0x70],xmm0
  191fa1:	c5 f9 6f 44 24 70    	vmovdqa xmm0,XMMWORD PTR [rsp+0x70]
  191fa7:	48 c7 c0 00 00 00 00 	mov    rax,0x0	191faa: R_X86_64_32S	__anon_39310
  191fae:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  191fb2:	66 0f 3a 44 c1 00    	pclmullqlqdq xmm0,xmm1
  191fb8:	c5 fa 7f 44 24 70    	vmovdqu XMMWORD PTR [rsp+0x70],xmm0
  191fbe:	c5 fa 6f 44 24 70    	vmovdqu xmm0,XMMWORD PTR [rsp+0x70]
  191fc4:	c5 fa 7f 84 24 80 00 00 00 	vmovdqu XMMWORD PTR [rsp+0x80],xmm0
  191fcd:	c5 fa 6f 4c 24 20    	vmovdqu xmm1,XMMWORD PTR [rsp+0x20]
  191fd3:	c5 fa 7f 8c 24 90 00 00 00 	vmovdqu XMMWORD PTR [rsp+0x90],xmm1
  191fdc:	48 c7 c0 00 00 00 00 	mov    rax,0x0	191fdf: R_X86_64_32S	__anon_39310
  191fe3:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  191fe7:	c5 fa 7f 94 24 a0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xa0],xmm2
  191ff0:	c5 fa 7f 8c 24 b0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xb0],xmm1
  191ff9:	c5 f9 6f 8c 24 b0 00 00 00 	vmovdqa xmm1,XMMWORD PTR [rsp+0xb0]
  192002:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192005: R_X86_64_32S	__anon_39310
  192009:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  19200d:	66 0f 3a 44 ca 00    	pclmullqlqdq xmm1,xmm2
  192013:	c5 fa 7f 8c 24 b0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xb0],xmm1
  19201c:	c5 fa 6f 8c 24 b0 00 00 00 	vmovdqu xmm1,XMMWORD PTR [rsp+0xb0]
  192025:	c5 fa 7f 8c 24 c0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xc0],xmm1
  19202e:	c5 fa 6f 54 24 30    	vmovdqu xmm2,XMMWORD PTR [rsp+0x30]
  192034:	c5 fa 7f 94 24 d0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xd0],xmm2
  19203d:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192040: R_X86_64_32S	__anon_39310
  192044:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  192048:	c5 fa 7f 9c 24 e0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xe0],xmm3
  192051:	c5 fa 7f 94 24 f0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xf0],xmm2
  19205a:	c5 f9 6f 94 24 f0 00 00 00 	vmovdqa xmm2,XMMWORD PTR [rsp+0xf0]
  192063:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192066: R_X86_64_32S	__anon_39310
  19206a:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  19206e:	66 0f 3a 44 d3 00    	pclmullqlqdq xmm2,xmm3
  192074:	c5 fa 7f 94 24 f0 00 00 00 	vmovdqu XMMWORD PTR [rsp+0xf0],xmm2
  19207d:	c5 fa 6f 94 24 f0 00 00 00 	vmovdqu xmm2,XMMWORD PTR [rsp+0xf0]
  192086:	c5 fa 7f 94 24 00 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x100],xmm2
  19208f:	c5 fa 6f 5c 24 40    	vmovdqu xmm3,XMMWORD PTR [rsp+0x40]
  192095:	c5 fa 7f 9c 24 10 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x110],xmm3
  19209e:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1920a1: R_X86_64_32S	__anon_39310
  1920a5:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  1920a9:	c5 fa 7f a4 24 20 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x120],xmm4
  1920b2:	c5 fa 7f 9c 24 30 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x130],xmm3
  1920bb:	c5 f9 6f 9c 24 30 01 00 00 	vmovdqa xmm3,XMMWORD PTR [rsp+0x130]
  1920c4:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1920c7: R_X86_64_32S	__anon_39310
  1920cb:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  1920cf:	66 0f 3a 44 dc 00    	pclmullqlqdq xmm3,xmm4
  1920d5:	c5 fa 7f 9c 24 30 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x130],xmm3
  1920de:	c5 fa 6f 9c 24 30 01 00 00 	vmovdqu xmm3,XMMWORD PTR [rsp+0x130]
  1920e7:	c5 fa 7f 9c 24 40 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x140],xmm3
  1920f0:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  1920f8:	48 89 84 24 e8 05 00 00 	mov    QWORD PTR [rsp+0x5e8],rax
  192100:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  192104:	c5 fa 7f a4 24 50 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x150],xmm4
  19210d:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  192115:	48 8d 50 10          	lea    rdx,[rax+0x10]
  192119:	48 89 94 24 f0 05 00 00 	mov    QWORD PTR [rsp+0x5f0],rdx
  192121:	c5 fa 6f 2a          	vmovdqu xmm5,XMMWORD PTR [rdx]
  192125:	c5 fa 7f ac 24 60 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x160],xmm5
  19212e:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  192136:	48 8d 50 20          	lea    rdx,[rax+0x20]
  19213a:	48 89 94 24 f8 05 00 00 	mov    QWORD PTR [rsp+0x5f8],rdx
  192142:	c5 fa 6f 32          	vmovdqu xmm6,XMMWORD PTR [rdx]
  192146:	c5 fa 7f b4 24 70 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x170],xmm6
  19214f:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  192157:	48 8d 50 30          	lea    rdx,[rax+0x30]
  19215b:	48 89 94 24 00 06 00 00 	mov    QWORD PTR [rsp+0x600],rdx
  192163:	c5 fa 6f 3a          	vmovdqu xmm7,XMMWORD PTR [rdx]
  192167:	c5 fa 7f bc 24 80 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x180],xmm7
  192170:	c5 7a 6f 04 24       	vmovdqu xmm8,XMMWORD PTR [rsp]
  192175:	c5 7a 7f 84 24 90 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x190],xmm8
  19217e:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192181: R_X86_64_32S	__anon_39310
  192185:	c5 7a 6f 08          	vmovdqu xmm9,XMMWORD PTR [rax]
  192189:	c5 7a 7f 8c 24 a0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1a0],xmm9
  192192:	c5 7a 7f 84 24 b0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1b0],xmm8
  19219b:	c5 79 6f 84 24 b0 01 00 00 	vmovdqa xmm8,XMMWORD PTR [rsp+0x1b0]
  1921a4:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1921a7: R_X86_64_32S	__anon_39310
  1921ab:	c5 7a 6f 08          	vmovdqu xmm9,XMMWORD PTR [rax]
  1921af:	66 45 0f 3a 44 c1 11 	pclmulhqhqdq xmm8,xmm9
  1921b6:	c5 7a 7f 84 24 b0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1b0],xmm8
  1921bf:	c5 7a 6f 84 24 b0 01 00 00 	vmovdqu xmm8,XMMWORD PTR [rsp+0x1b0]
  1921c8:	c5 39 ef c8          	vpxor  xmm9,xmm8,xmm0
  1921cc:	c5 b1 ef c4          	vpxor  xmm0,xmm9,xmm4
  1921d0:	c5 fa 7f 04 24       	vmovdqu XMMWORD PTR [rsp],xmm0
  1921d5:	c5 fa 6f 44 24 20    	vmovdqu xmm0,XMMWORD PTR [rsp+0x20]
  1921db:	c5 fa 7f 84 24 c0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1c0],xmm0
  1921e4:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1921e7: R_X86_64_32S	__anon_39310
  1921eb:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  1921ef:	c5 fa 7f a4 24 d0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1d0],xmm4
  1921f8:	c5 fa 7f 84 24 e0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1e0],xmm0
  192201:	c5 f9 6f 84 24 e0 01 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x1e0]
  19220a:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19220d: R_X86_64_32S	__anon_39310
  192211:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  192215:	66 0f 3a 44 c4 11    	pclmulhqhqdq xmm0,xmm4
  19221b:	c5 fa 7f 84 24 e0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1e0],xmm0
  192224:	c5 fa 6f 84 24 e0 01 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x1e0]
  19222d:	c5 f9 ef e1          	vpxor  xmm4,xmm0,xmm1
  192231:	c5 d9 ef c5          	vpxor  xmm0,xmm4,xmm5
  192235:	c5 fa 7f 44 24 20    	vmovdqu XMMWORD PTR [rsp+0x20],xmm0
  19223b:	c5 fa 6f 44 24 30    	vmovdqu xmm0,XMMWORD PTR [rsp+0x30]
  192241:	c5 fa 7f 84 24 f0 01 00 00 	vmovdqu XMMWORD PTR [rsp+0x1f0],xmm0
  19224a:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19224d: R_X86_64_32S	__anon_39310
  192251:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192255:	c5 fa 7f 8c 24 00 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x200],xmm1
  19225e:	c5 fa 7f 84 24 10 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x210],xmm0
  192267:	c5 f9 6f 84 24 10 02 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x210]
  192270:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192273: R_X86_64_32S	__anon_39310
  192277:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  19227b:	66 0f 3a 44 c1 11    	pclmulhqhqdq xmm0,xmm1
  192281:	c5 fa 7f 84 24 10 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x210],xmm0
  19228a:	c5 fa 6f 84 24 10 02 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x210]
  192293:	c5 f9 ef ca          	vpxor  xmm1,xmm0,xmm2
  192297:	c5 f1 ef c6          	vpxor  xmm0,xmm1,xmm6
  19229b:	c5 fa 7f 44 24 30    	vmovdqu XMMWORD PTR [rsp+0x30],xmm0
  1922a1:	c5 fa 6f 44 24 40    	vmovdqu xmm0,XMMWORD PTR [rsp+0x40]
  1922a7:	c5 fa 7f 84 24 20 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x220],xmm0
  1922b0:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1922b3: R_X86_64_32S	__anon_39310
  1922b7:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  1922bb:	c5 fa 7f 8c 24 30 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x230],xmm1
  1922c4:	c5 fa 7f 84 24 40 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x240],xmm0
  1922cd:	c5 f9 6f 84 24 40 02 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x240]
  1922d6:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1922d9: R_X86_64_32S	__anon_39310
  1922dd:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  1922e1:	66 0f 3a 44 c1 11    	pclmulhqhqdq xmm0,xmm1
  1922e7:	c5 fa 7f 84 24 40 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x240],xmm0
  1922f0:	c5 fa 6f 84 24 40 02 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x240]
  1922f9:	c5 f9 ef cb          	vpxor  xmm1,xmm0,xmm3
  1922fd:	c5 f1 ef c7          	vpxor  xmm0,xmm1,xmm7
  192301:	c5 fa 7f 44 24 40    	vmovdqu XMMWORD PTR [rsp+0x40],xmm0
  192307:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  19230f:	48 8d 50 40          	lea    rdx,[rax+0x40]
  192313:	48 89 94 24 98 05 00 00 	mov    QWORD PTR [rsp+0x598],rdx
  19231b:	48 8b 84 24 a0 05 00 00 	mov    rax,QWORD PTR [rsp+0x5a0]
  192323:	48 83 e8 40          	sub    rax,0x40
  192327:	48 89 84 24 08 06 00 00 	mov    QWORD PTR [rsp+0x608],rax
  19232f:	0f 92 84 24 10 06 00 00 	setb   BYTE PTR [rsp+0x610]
  192337:	8a 94 24 10 06 00 00 	mov    dl,BYTE PTR [rsp+0x610]
  19233e:	48 89 84 24 18 06 00 00 	mov    QWORD PTR [rsp+0x618],rax
  192346:	0f 92 84 24 20 06 00 00 	setb   BYTE PTR [rsp+0x620]
  19234e:	80 fa 01             	cmp    dl,0x1
  192351:	0f 85 05 00 00 00    	jne    19235c <crc32_pclmul.update+0x5ac>
  192357:	e8 00 00 00 00       	call   19235c <crc32_pclmul.update+0x5ac>	192358: R_X86_64_PLT32	debug.FullPanic((function 'defaultPanic')).integerOverflow-0x4
  19235c:	48 8b 84 24 18 06 00 00 	mov    rax,QWORD PTR [rsp+0x618]
  192364:	e9 00 00 00 00       	jmp    192369 <crc32_pclmul.update+0x5b9>
  192369:	48 89 84 24 a0 05 00 00 	mov    QWORD PTR [rsp+0x5a0],rax
  192371:	90                   	nop
  192372:	e9 05 00 00 00       	jmp    19237c <crc32_pclmul.update+0x5cc>
  192377:	e9 05 00 00 00       	jmp    192381 <crc32_pclmul.update+0x5d1>
  19237c:	e9 ec fb ff ff       	jmp    191f6d <crc32_pclmul.update+0x1bd>
  192381:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  192386:	c5 fa 7f 84 24 50 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x250],xmm0
  19238f:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192392: R_X86_64_32S	__anon_39317
  192396:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  19239a:	c5 fa 7f 8c 24 60 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x260],xmm1
  1923a3:	c5 fa 7f 84 24 70 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x270],xmm0
  1923ac:	c5 f9 6f 84 24 70 02 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x270]
  1923b5:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1923b8: R_X86_64_32S	__anon_39317
  1923bc:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  1923c0:	66 0f 3a 44 c1 00    	pclmullqlqdq xmm0,xmm1
  1923c6:	c5 fa 7f 84 24 70 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x270],xmm0
  1923cf:	c5 fa 6f 84 24 70 02 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x270]
  1923d8:	c5 fa 6f 0c 24       	vmovdqu xmm1,XMMWORD PTR [rsp]
  1923dd:	c5 fa 7f 8c 24 80 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x280],xmm1
  1923e6:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1923e9: R_X86_64_32S	__anon_39317
  1923ed:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  1923f1:	c5 fa 7f 94 24 90 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x290],xmm2
  1923fa:	c5 fa 7f 8c 24 a0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2a0],xmm1
  192403:	c5 f9 6f 8c 24 a0 02 00 00 	vmovdqa xmm1,XMMWORD PTR [rsp+0x2a0]
  19240c:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19240f: R_X86_64_32S	__anon_39317
  192413:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  192417:	66 0f 3a 44 ca 11    	pclmulhqhqdq xmm1,xmm2
  19241d:	c5 fa 7f 8c 24 a0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2a0],xmm1
  192426:	c5 fa 6f 8c 24 a0 02 00 00 	vmovdqu xmm1,XMMWORD PTR [rsp+0x2a0]
  19242f:	c5 f9 ef d1          	vpxor  xmm2,xmm0,xmm1
  192433:	c5 fa 7f 94 24 b0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2b0],xmm2
  19243c:	c5 fa 6f 44 24 20    	vmovdqu xmm0,XMMWORD PTR [rsp+0x20]
  192442:	c5 fa 7f 84 24 c0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2c0],xmm0
  19244b:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19244e: R_X86_64_32S	__anon_39323
  192452:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192456:	c5 fa 7f 8c 24 d0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2d0],xmm1
  19245f:	c5 fa 7f 84 24 e0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2e0],xmm0
  192468:	c5 f9 6f 84 24 e0 02 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x2e0]
  192471:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192474: R_X86_64_32S	__anon_39323
  192478:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  19247c:	66 0f 3a 44 c1 00    	pclmullqlqdq xmm0,xmm1
  192482:	c5 fa 7f 84 24 e0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2e0],xmm0
  19248b:	c5 fa 6f 84 24 e0 02 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x2e0]
  192494:	c5 fa 6f 4c 24 20    	vmovdqu xmm1,XMMWORD PTR [rsp+0x20]
  19249a:	c5 fa 7f 8c 24 f0 02 00 00 	vmovdqu XMMWORD PTR [rsp+0x2f0],xmm1
  1924a3:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1924a6: R_X86_64_32S	__anon_39323
  1924aa:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  1924ae:	c5 fa 7f 9c 24 00 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x300],xmm3
  1924b7:	c5 fa 7f 8c 24 10 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x310],xmm1
  1924c0:	c5 f9 6f 8c 24 10 03 00 00 	vmovdqa xmm1,XMMWORD PTR [rsp+0x310]
  1924c9:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1924cc: R_X86_64_32S	__anon_39323
  1924d0:	c5 fa 6f 18          	vmovdqu xmm3,XMMWORD PTR [rax]
  1924d4:	66 0f 3a 44 cb 11    	pclmulhqhqdq xmm1,xmm3
  1924da:	c5 fa 7f 8c 24 10 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x310],xmm1
  1924e3:	c5 fa 6f 8c 24 10 03 00 00 	vmovdqu xmm1,XMMWORD PTR [rsp+0x310]
  1924ec:	c5 f9 ef d9          	vpxor  xmm3,xmm0,xmm1
  1924f0:	c5 fa 7f 9c 24 20 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x320],xmm3
  1924f9:	c5 fa 6f 44 24 30    	vmovdqu xmm0,XMMWORD PTR [rsp+0x30]
  1924ff:	c5 fa 7f 84 24 30 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x330],xmm0
  192508:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19250b: R_X86_64_32S	__anon_39329
  19250f:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192513:	c5 fa 7f 8c 24 40 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x340],xmm1
  19251c:	c5 fa 7f 84 24 50 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x350],xmm0
  192525:	c5 f9 6f 84 24 50 03 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x350]
  19252e:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192531: R_X86_64_32S	__anon_39329
  192535:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192539:	66 0f 3a 44 c1 00    	pclmullqlqdq xmm0,xmm1
  19253f:	c5 fa 7f 84 24 50 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x350],xmm0
  192548:	c5 fa 6f 84 24 50 03 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x350]
  192551:	c5 fa 6f 4c 24 30    	vmovdqu xmm1,XMMWORD PTR [rsp+0x30]
  192557:	c5 fa 7f 8c 24 60 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x360],xmm1
  192560:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192563: R_X86_64_32S	__anon_39329
  192567:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  19256b:	c5 fa 7f a4 24 70 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x370],xmm4
  192574:	c5 fa 7f 8c 24 80 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x380],xmm1
  19257d:	c5 f9 6f 8c 24 80 03 00 00 	vmovdqa xmm1,XMMWORD PTR [rsp+0x380]
  192586:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192589: R_X86_64_32S	__anon_39329
  19258d:	c5 fa 6f 20          	vmovdqu xmm4,XMMWORD PTR [rax]
  192591:	66 0f 3a 44 cc 11    	pclmulhqhqdq xmm1,xmm4
  192597:	c5 fa 7f 8c 24 80 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x380],xmm1
  1925a0:	c5 fa 6f 8c 24 80 03 00 00 	vmovdqu xmm1,XMMWORD PTR [rsp+0x380]
  1925a9:	c5 f9 ef e1          	vpxor  xmm4,xmm0,xmm1
  1925ad:	c5 fa 7f a4 24 90 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x390],xmm4
  1925b6:	c5 e9 ef c3          	vpxor  xmm0,xmm2,xmm3
  1925ba:	c5 f9 ef cc          	vpxor  xmm1,xmm0,xmm4
  1925be:	c5 fa 6f 44 24 40    	vmovdqu xmm0,XMMWORD PTR [rsp+0x40]
  1925c4:	c5 f1 ef d0          	vpxor  xmm2,xmm1,xmm0
  1925c8:	c5 fa 7f 14 24       	vmovdqu XMMWORD PTR [rsp],xmm2
  1925cd:	48 8d 84 24 a0 03 00 00 	lea    rax,[rsp+0x3a0]
  1925d5:	48 89 84 24 28 06 00 00 	mov    QWORD PTR [rsp+0x628],rax
  1925dd:	48 8b bc 24 28 06 00 00 	mov    rdi,QWORD PTR [rsp+0x628]
  1925e5:	c6 84 24 69 06 00 00 aa 	mov    BYTE PTR [rsp+0x669],0xaa
  1925ed:	8a 84 24 69 06 00 00 	mov    al,BYTE PTR [rsp+0x669]
  1925f4:	48 c7 84 24 30 06 00 00 10 00 00 00 	mov    QWORD PTR [rsp+0x630],0x10
  192600:	48 8b 8c 24 30 06 00 00 	mov    rcx,QWORD PTR [rsp+0x630]
  192608:	f3 aa                	rep stos BYTE PTR es:[rdi],al
  19260a:	48 8b 84 24 a0 05 00 00 	mov    rax,QWORD PTR [rsp+0x5a0]
  192612:	48 83 f8 10          	cmp    rax,0x10
  192616:	0f 82 5d 01 00 00    	jb     192779 <crc32_pclmul.update+0x9c9>
  19261c:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  192624:	48 89 84 24 38 06 00 00 	mov    QWORD PTR [rsp+0x638],rax
  19262c:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  192630:	c5 fa 7f 44 24 20    	vmovdqu XMMWORD PTR [rsp+0x20],xmm0
  192636:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  19263b:	c5 fa 7f 84 24 b0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3b0],xmm0
  192644:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192647: R_X86_64_32S	__anon_39329
  19264b:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  19264f:	c5 fa 7f 8c 24 c0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3c0],xmm1
  192658:	c5 fa 7f 84 24 d0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3d0],xmm0
  192661:	c5 f9 6f 84 24 d0 03 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x3d0]
  19266a:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19266d: R_X86_64_32S	__anon_39329
  192671:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192675:	66 0f 3a 44 c1 00    	pclmullqlqdq xmm0,xmm1
  19267b:	c5 fa 7f 84 24 d0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3d0],xmm0
  192684:	c5 fa 6f 84 24 d0 03 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x3d0]
  19268d:	c5 fa 7f 84 24 a0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3a0],xmm0
  192696:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  19269b:	c5 fa 7f 84 24 e0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3e0],xmm0
  1926a4:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1926a7: R_X86_64_32S	__anon_39329
  1926ab:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  1926af:	c5 fa 7f 8c 24 f0 03 00 00 	vmovdqu XMMWORD PTR [rsp+0x3f0],xmm1
  1926b8:	c5 fa 7f 84 24 00 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x400],xmm0
  1926c1:	c5 f9 6f 84 24 00 04 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x400]
  1926ca:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1926cd: R_X86_64_32S	__anon_39329
  1926d1:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  1926d5:	66 0f 3a 44 c1 11    	pclmulhqhqdq xmm0,xmm1
  1926db:	c5 fa 7f 84 24 00 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x400],xmm0
  1926e4:	c5 fa 6f 84 24 00 04 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x400]
  1926ed:	c5 fa 6f 4c 24 20    	vmovdqu xmm1,XMMWORD PTR [rsp+0x20]
  1926f3:	c5 f9 ef d1          	vpxor  xmm2,xmm0,xmm1
  1926f7:	c5 fa 6f 84 24 a0 03 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x3a0]
  192700:	c5 e9 ef c8          	vpxor  xmm1,xmm2,xmm0
  192704:	c5 fa 7f 0c 24       	vmovdqu XMMWORD PTR [rsp],xmm1
  192709:	48 8b 84 24 98 05 00 00 	mov    rax,QWORD PTR [rsp+0x598]
  192711:	48 8d 50 10          	lea    rdx,[rax+0x10]
  192715:	48 89 94 24 98 05 00 00 	mov    QWORD PTR [rsp+0x598],rdx
  19271d:	48 8b 84 24 a0 05 00 00 	mov    rax,QWORD PTR [rsp+0x5a0]
  192725:	48 83 e8 10          	sub    rax,0x10
  192729:	48 89 84 24 40 06 00 00 	mov    QWORD PTR [rsp+0x640],rax
  192731:	0f 92 84 24 48 06 00 00 	setb   BYTE PTR [rsp+0x648]
  192739:	8a 94 24 48 06 00 00 	mov    dl,BYTE PTR [rsp+0x648]
  192740:	48 89 84 24 50 06 00 00 	mov    QWORD PTR [rsp+0x650],rax
  192748:	0f 92 84 24 58 06 00 00 	setb   BYTE PTR [rsp+0x658]
  192750:	80 fa 01             	cmp    dl,0x1
  192753:	0f 85 05 00 00 00    	jne    19275e <crc32_pclmul.update+0x9ae>
  192759:	e8 00 00 00 00       	call   19275e <crc32_pclmul.update+0x9ae>	19275a: R_X86_64_PLT32	debug.FullPanic((function 'defaultPanic')).integerOverflow-0x4
  19275e:	48 8b 84 24 50 06 00 00 	mov    rax,QWORD PTR [rsp+0x650]
  192766:	e9 00 00 00 00       	jmp    19276b <crc32_pclmul.update+0x9bb>
  19276b:	48 89 84 24 a0 05 00 00 	mov    QWORD PTR [rsp+0x5a0],rax
  192773:	90                   	nop
  192774:	e9 05 00 00 00       	jmp    19277e <crc32_pclmul.update+0x9ce>
  192779:	e9 05 00 00 00       	jmp    192783 <crc32_pclmul.update+0x9d3>
  19277e:	e9 87 fe ff ff       	jmp    19260a <crc32_pclmul.update+0x85a>
  192783:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  192788:	c5 fa 7f 84 24 10 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x410],xmm0
  192791:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192794: R_X86_64_32S	__anon_39329
  192798:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  19279c:	c5 fa 7f 8c 24 20 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x420],xmm1
  1927a5:	c5 fa 7f 84 24 30 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x430],xmm0
  1927ae:	c5 f9 6f 84 24 30 04 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x430]
  1927b7:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1927ba: R_X86_64_32S	__anon_39329
  1927be:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  1927c2:	66 0f 3a 44 c1 10    	pclmullqhqdq xmm0,xmm1
  1927c8:	c5 fa 7f 84 24 30 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x430],xmm0
  1927d1:	c5 fa 6f 84 24 30 04 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x430]
  1927da:	c5 fa 7f 84 24 40 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x440],xmm0
  1927e3:	c5 fa 6f 0c 24       	vmovdqu xmm1,XMMWORD PTR [rsp]
  1927e8:	c5 fa 7f 8c 24 50 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x450],xmm1
  1927f1:	c5 fa 7f 84 24 60 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x460],xmm0
  1927fa:	c5 fa 7f 8c 24 70 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x470],xmm1
  192803:	c5 f9 6f 84 24 70 04 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x470]
  19280c:	31 c0                	xor    eax,eax
  19280e:	e8 00 00 00 00       	call   192813 <crc32_pclmul.update+0xa63>	19280f: R_X86_64_PLT32	simd.shiftElementsLeft__anon_39349-0x4
  192813:	c5 f9 ef 8c 24 60 04 00 00 	vpxor  xmm1,xmm0,XMMWORD PTR [rsp+0x460]
  19281c:	c5 fa 7f 0c 24       	vmovdqu XMMWORD PTR [rsp],xmm1
  192821:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  192826:	c5 fa 7f 84 24 80 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x480],xmm0
  19282f:	c5 f9 6f c8          	vmovdqa xmm1,xmm0
  192833:	c5 fa 7f 8c 24 90 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x490],xmm1
  19283c:	c5 fa 7f 8c 24 a0 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x4a0],xmm1
  192845:	c5 f9 6f 84 24 a0 04 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x4a0]
  19284e:	31 c0                	xor    eax,eax
  192850:	e8 00 00 00 00       	call   192855 <crc32_pclmul.update+0xaa5>	192851: R_X86_64_PLT32	simd.shiftElementsLeft__anon_39361-0x4
  192855:	c5 f9 6f c8          	vmovdqa xmm1,xmm0
  192859:	c5 fa 7f 8c 24 b0 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x4b0],xmm1
  192862:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  192867:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19286a: R_X86_64_32S	__anon_39362
  19286e:	c5 f9 db 10          	vpand  xmm2,xmm0,XMMWORD PTR [rax]
  192872:	c5 fa 7f 14 24       	vmovdqu XMMWORD PTR [rsp],xmm2
  192877:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  19287c:	c5 fa 7f 84 24 c0 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x4c0],xmm0
  192885:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192888: R_X86_64_32S	__anon_39366
  19288c:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  192890:	c5 fa 7f 94 24 d0 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x4d0],xmm2
  192899:	c5 fa 7f 84 24 e0 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x4e0],xmm0
  1928a2:	c5 f9 6f 84 24 e0 04 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x4e0]
  1928ab:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1928ae: R_X86_64_32S	__anon_39366
  1928b2:	c5 fa 6f 10          	vmovdqu xmm2,XMMWORD PTR [rax]
  1928b6:	66 0f 3a 44 c2 00    	pclmullqlqdq xmm0,xmm2
  1928bc:	c5 fa 7f 84 24 e0 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x4e0],xmm0
  1928c5:	c5 fa 6f 84 24 e0 04 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x4e0]
  1928ce:	c5 f9 ef d1          	vpxor  xmm2,xmm0,xmm1
  1928d2:	c5 fa 7f 14 24       	vmovdqu XMMWORD PTR [rsp],xmm2
  1928d7:	c5 fa 6f 04 24       	vmovdqu xmm0,XMMWORD PTR [rsp]
  1928dc:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1928df: R_X86_64_32S	__anon_39362
  1928e3:	c5 f9 db 08          	vpand  xmm1,xmm0,XMMWORD PTR [rax]
  1928e7:	c5 fa 7f 8c 24 f0 04 00 00 	vmovdqu XMMWORD PTR [rsp+0x4f0],xmm1
  1928f0:	48 c7 c0 00 00 00 00 	mov    rax,0x0	1928f3: R_X86_64_32S	__anon_39372
  1928f7:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  1928fb:	c5 fa 7f 84 24 00 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x500],xmm0
  192904:	c5 fa 7f 8c 24 10 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x510],xmm1
  19290d:	c5 f9 6f 84 24 10 05 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x510]
  192916:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192919: R_X86_64_32S	__anon_39372
  19291d:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192921:	66 0f 3a 44 c1 10    	pclmullqhqdq xmm0,xmm1
  192927:	c5 fa 7f 84 24 10 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x510],xmm0
  192930:	c5 fa 6f 84 24 10 05 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x510]
  192939:	c5 fa 7f 84 24 20 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x520],xmm0
  192942:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192945: R_X86_64_32S	__anon_39362
  192949:	c5 f9 db 08          	vpand  xmm1,xmm0,XMMWORD PTR [rax]
  19294d:	c5 fa 7f 8c 24 30 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x530],xmm1
  192956:	48 c7 c0 00 00 00 00 	mov    rax,0x0	192959: R_X86_64_32S	__anon_39372
  19295d:	c5 fa 6f 00          	vmovdqu xmm0,XMMWORD PTR [rax]
  192961:	c5 fa 7f 84 24 40 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x540],xmm0
  19296a:	c5 fa 7f 8c 24 50 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x550],xmm1
  192973:	c5 f9 6f 84 24 50 05 00 00 	vmovdqa xmm0,XMMWORD PTR [rsp+0x550]
  19297c:	48 c7 c0 00 00 00 00 	mov    rax,0x0	19297f: R_X86_64_32S	__anon_39372
  192983:	c5 fa 6f 08          	vmovdqu xmm1,XMMWORD PTR [rax]
  192987:	66 0f 3a 44 c1 00    	pclmullqlqdq xmm0,xmm1
  19298d:	c5 fa 7f 84 24 50 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x550],xmm0
  192996:	c5 fa 6f 84 24 50 05 00 00 	vmovdqu xmm0,XMMWORD PTR [rsp+0x550]
  19299f:	c5 fa 7f 84 24 60 05 00 00 	vmovdqu XMMWORD PTR [rsp+0x560],xmm0
  1929a8:	c5 fa 6f 0c 24       	vmovdqu xmm1,XMMWORD PTR [rsp]
  1929ad:	c5 f1 ef d0          	vpxor  xmm2,xmm1,xmm0
  1929b1:	c5 fa 7f 14 24       	vmovdqu XMMWORD PTR [rsp],xmm2
  1929b6:	48 8d 04 24          	lea    rax,[rsp]
  1929ba:	31 d2                	xor    edx,edx
  1929bc:	48 8d 04 d0          	lea    rax,[rax+rdx*8]
  1929c0:	48 8b 10             	mov    rdx,QWORD PTR [rax]
  1929c3:	48 c1 ea 20          	shr    rdx,0x20
  1929c7:	89 d0                	mov    eax,edx
  1929c9:	48 89 ec             	mov    rsp,rbp
  1929cc:	5d                   	pop    rbp
  1929cd:	c3                   	ret
	...
