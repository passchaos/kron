
.zig-cache/submit-abi/after-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fbc70 <core.runtime.Runtime.submitSafeDestination>:
 10fbc70:	push   %rbp
 10fbc71:	mov    %rsp,%rbp
 10fbc74:	push   %r15
 10fbc76:	push   %r14
 10fbc78:	push   %r13
 10fbc7a:	push   %r12
 10fbc7c:	push   %rbx
 10fbc7d:	sub    $0xfb8,%rsp
 10fbc84:	mov    (%rcx),%r15
 10fbc87:	mov    0x8(%rcx),%r8
 10fbc8b:	mov    0x20(%rcx),%r13
 10fbc8f:	mov    0x28(%rcx),%rax
 10fbc93:	mov    %rax,-0xa0(%rbp)
 10fbc9a:	vmovups 0x30(%rcx),%xmm0
 10fbc9f:	vmovaps %xmm0,-0x230(%rbp)
 10fbca7:	movzbl 0x40(%rcx),%eax
 10fbcab:	mov    %al,-0x98(%rbp)
 10fbcb1:	vmovups 0x68(%rcx),%ymm0
 10fbcb6:	vmovups %ymm0,-0xc80(%rbp)
 10fbcbe:	vmovups 0x88(%rcx),%ymm0
 10fbcc6:	vmovups %ymm0,-0xc60(%rbp)
 10fbcce:	vmovups 0xa8(%rcx),%ymm0
 10fbcd6:	vmovups %ymm0,-0xc40(%rbp)
 10fbcde:	vmovups 0xc8(%rcx),%ymm0
 10fbce6:	vmovups %ymm0,-0xc20(%rbp)
 10fbcee:	vmovups 0xe8(%rcx),%ymm0
 10fbcf6:	vmovups %ymm0,-0xc00(%rbp)
 10fbcfe:	vmovups 0x108(%rcx),%ymm0
 10fbd06:	vmovups %ymm0,-0xbe0(%rbp)
 10fbd0e:	mov    0x128(%rcx),%rax
 10fbd15:	mov    %rax,-0xbc0(%rbp)
 10fbd1c:	vmovups 0x48(%rcx),%ymm0
 10fbd21:	vmovups %ymm0,-0xca0(%rbp)
 10fbd29:	movzbl 0x130(%rcx),%eax
 10fbd30:	mov    %al,-0x78(%rbp)
 10fbd33:	mov    %rsi,%r14
 10fbd36:	mov    %rdi,%rbx
 10fbd39:	mov    0xb8(%rdx),%edi
 10fbd3f:	lea    -0x41(%rdi),%eax
 10fbd42:	lea    -0x1(%rdi),%esi
 10fbd45:	shl    $0x6,%rsi
 10fbd49:	cmp    $0xffffffc0,%eax
 10fbd4c:	lea    (%rsi,%rsi,2),%rax
 10fbd50:	mov    $0x3000,%r12d
 10fbd56:	mov    0x40(%rdx),%rsi
 10fbd5a:	mov    %rsi,-0x150(%rbp)
 10fbd61:	vmovups (%rdx),%ymm0
 10fbd65:	vmovups 0x20(%rdx),%ymm1
 10fbd6a:	vmovups %ymm1,-0x170(%rbp)
 10fbd72:	vmovups %ymm0,-0x190(%rbp)
 10fbd7a:	mov    0x50(%rdx),%r11
 10fbd7e:	vmovups 0x98(%rdx),%ymm0
 10fbd86:	vmovups %ymm0,-0x1b0(%rbp)
 10fbd8e:	vmovups 0x78(%rdx),%ymm0
 10fbd93:	vmovups %ymm0,-0x1d0(%rbp)
 10fbd9b:	vmovups 0xbc(%rdx),%xmm0
 10fbda3:	vmovups 0xc9(%rdx),%xmm1
 10fbdab:	vmovups %xmm1,-0x123(%rbp)
 10fbdb3:	vmovaps %xmm0,-0x130(%rbp)
 10fbdbb:	cmovae %rax,%r12
 10fbdbf:	mov    0xda(%rdx),%eax
 10fbdc5:	mov    %eax,-0x30(%rbp)
 10fbdc8:	movzwl 0xde(%rdx),%eax
 10fbdcf:	mov    %ax,-0x2c(%rbp)
 10fbdd3:	mov    %rcx,-0xf8(%rbp)
 10fbdda:	movzbl 0x148(%rcx),%eax
 10fbde1:	mov    %al,-0x29(%rbp)
 10fbde4:	add    %r14,%r12
 10fbde7:	mov    0x3178(%r14),%r10
 10fbdee:	cmpb   $0x0,0x7420(%r13)
 10fbdf6:	mov    0x7430(%r13),%rcx
 10fbdfd:	mov    0x7438(%r13),%r9
 10fbe04:	mov    %rdi,-0x40(%rbp)
 10fbe08:	mov    %r8,-0x38(%rbp)
 10fbe0c:	mov    %rcx,-0x58(%rbp)
 10fbe10:	mov    %r9,-0x70(%rbp)
 10fbe14:	mov    %r10,-0x68(%rbp)
 10fbe18:	mov    %r11,-0x100(%rbp)
 10fbe1f:	je     10fbf2f <core.runtime.Runtime.submitSafeDestination+0x2bf>
 10fbe25:	mov    0x40(%rdx),%rax
 10fbe29:	mov    %rax,-0x3a0(%rbp)
 10fbe30:	vmovups (%rdx),%ymm0
 10fbe34:	vmovups 0x20(%rdx),%ymm1
 10fbe39:	vmovups %ymm1,-0x3c0(%rbp)
 10fbe41:	vmovups %ymm0,-0x3e0(%rbp)
 10fbe49:	mov    %r10,-0x398(%rbp)
 10fbe50:	mov    %r11,-0x390(%rbp)
 10fbe57:	mov    %r15,-0x388(%rbp)
 10fbe5e:	mov    %r9,-0x380(%rbp)
 10fbe65:	mov    %rcx,-0x378(%rbp)
 10fbe6c:	mov    %r8,-0x370(%rbp)
 10fbe73:	lea    0x78(%rdx),%rax
 10fbe77:	vmovups (%rax),%ymm0
 10fbe7b:	vmovups 0x20(%rax),%ymm1
 10fbe80:	lea    0xbc(%rdx),%rax
 10fbe87:	vmovups %ymm0,-0x368(%rbp)
 10fbe8f:	vmovups %ymm1,-0x348(%rbp)
 10fbe97:	mov    %edi,-0x328(%rbp)
 10fbe9d:	vmovups (%rax),%xmm0
 10fbea1:	vmovups 0xd(%rax),%xmm1
 10fbea6:	vmovups %xmm0,-0x324(%rbp)
 10fbeae:	vmovups %xmm1,-0x317(%rbp)
 10fbeb6:	movzbl -0x29(%rbp),%eax
 10fbeba:	lea    0xda(%rdx),%rcx
 10fbec1:	mov    %al,-0x307(%rbp)
 10fbec7:	mov    (%rcx),%eax
 10fbec9:	mov    %eax,-0x306(%rbp)
 10fbecf:	movzwl 0x4(%rcx),%eax
 10fbed3:	mov    %ax,-0x302(%rbp)
 10fbeda:	lea    0x1000(%r13),%rsi
 10fbee1:	lea    -0x104(%rbp),%rdi
 10fbee8:	lea    -0x3e0(%rbp),%rdx
 10fbeef:	vzeroupper
 10fbef2:	call   110d430 <pipeline.predicate.Predicate.matches>
 10fbef7:	movzwl -0x104(%rbp),%eax
 10fbefe:	test   %ax,%ax
 10fbf01:	jne    10fc5d7 <core.runtime.Runtime.submitSafeDestination+0x967>
 10fbf07:	cmpb   $0x0,-0x102(%rbp)
 10fbf0e:	mov    -0x40(%rbp),%rdi
 10fbf12:	mov    -0x38(%rbp),%r8
 10fbf16:	mov    -0x58(%rbp),%rcx
 10fbf1a:	mov    -0x70(%rbp),%r9
 10fbf1e:	mov    -0x68(%rbp),%r10
 10fbf22:	mov    -0x100(%rbp),%r11
 10fbf29:	je     10fc0bf <core.runtime.Runtime.submitSafeDestination+0x44f>
 10fbf2f:	mov    %r12,-0x90(%rbp)
 10fbf36:	mov    %r14,-0x60(%rbp)
 10fbf3a:	mov    %rbx,-0x50(%rbp)
 10fbf3e:	mov    %r13,-0x88(%rbp)
 10fbf45:	mov    0x7490(%r13),%r12
 10fbf4c:	and    %r15,%r12
 10fbf4f:	je     10fc09e <core.runtime.Runtime.submitSafeDestination+0x42e>
 10fbf55:	lea    -0xd08(%rbp),%rbx
 10fbf5c:	movzbl -0x29(%rbp),%r14d
 10fbf61:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10fbf70:	tzcnt  %r12,%r13
 10fbf75:	imul   $0x7650,%r13,%rsi
 10fbf7c:	mov    -0x88(%rbp),%rax
 10fbf83:	add    0x7440(%rax),%rsi
 10fbf8a:	mov    -0x150(%rbp),%rax
 10fbf91:	mov    %rax,-0xd40(%rbp)
 10fbf98:	vmovups -0x190(%rbp),%ymm0
 10fbfa0:	vmovups -0x170(%rbp),%ymm1
 10fbfa8:	vmovups %ymm1,-0xd60(%rbp)
 10fbfb0:	vmovups %ymm0,-0xd80(%rbp)
 10fbfb8:	mov    %r10,-0xd38(%rbp)
 10fbfbf:	mov    %r11,-0xd30(%rbp)
 10fbfc6:	mov    %r15,-0xd28(%rbp)
 10fbfcd:	mov    %r9,-0xd20(%rbp)
 10fbfd4:	mov    %rcx,-0xd18(%rbp)
 10fbfdb:	mov    %r8,-0xd10(%rbp)
 10fbfe2:	vmovups -0x1d0(%rbp),%ymm0
 10fbfea:	vmovups -0x1b0(%rbp),%ymm1
 10fbff2:	vmovups %ymm1,0x20(%rbx)
 10fbff7:	vmovups %ymm0,(%rbx)
 10fbffb:	mov    %edi,-0xcc8(%rbp)
 10fc001:	vmovups -0x123(%rbp),%xmm0
 10fc009:	vmovups %xmm0,0x51(%rbx)
 10fc00e:	vmovaps -0x130(%rbp),%xmm0
 10fc016:	vmovups %xmm0,0x44(%rbx)
 10fc01b:	mov    %r14b,-0xca7(%rbp)
 10fc022:	movzwl -0x2c(%rbp),%eax
 10fc026:	mov    %ax,0x66(%rbx)
 10fc02a:	mov    -0x30(%rbp),%eax
 10fc02d:	mov    %eax,0x62(%rbx)
 10fc030:	lea    -0x108(%rbp),%rdi
 10fc037:	lea    -0xd80(%rbp),%rdx
 10fc03e:	vzeroupper
 10fc041:	call   110d430 <pipeline.predicate.Predicate.matches>
 10fc046:	movzwl -0x108(%rbp),%eax
 10fc04d:	test   %ax,%ax
 10fc050:	jne    10fd527 <core.runtime.Runtime.submitSafeDestination+0x18b7>
 10fc056:	mov    $0xfffffffffffffffe,%rax
 10fc05d:	mov    %r13d,%ecx
 10fc060:	rol    %cl,%rax
 10fc063:	cmpb   $0x0,-0x106(%rbp)
 10fc06a:	mov    $0xffffffffffffffff,%rcx
 10fc071:	cmovne %rcx,%rax
 10fc075:	and    %rax,%r15
 10fc078:	blsr   %r12,%r12
 10fc07d:	mov    -0x40(%rbp),%rdi
 10fc081:	mov    -0x38(%rbp),%r8
 10fc085:	mov    -0x58(%rbp),%rcx
 10fc089:	mov    -0x70(%rbp),%r9
 10fc08d:	mov    -0x68(%rbp),%r10
 10fc091:	mov    -0x100(%rbp),%r11
 10fc098:	jne    10fbf70 <core.runtime.Runtime.submitSafeDestination+0x300>
 10fc09e:	test   %r15,%r15
 10fc0a1:	je     10fc0cf <core.runtime.Runtime.submitSafeDestination+0x45f>
 10fc0a3:	mov    -0x60(%rbp),%r13
 10fc0a7:	movzwl 0x31e8(%r13),%eax
 10fc0af:	test   %ax,%ax
 10fc0b2:	mov    -0x50(%rbp),%r12
 10fc0b6:	je     10fc0fc <core.runtime.Runtime.submitSafeDestination+0x48c>
 10fc0b8:	mov    %ax,(%r12)
 10fc0bd:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fc0bf:	lock incq 0x48(%r12)
 10fc0c5:	mov    -0x89f67(%rip),%eax        # 1072164 <__anon_29578>
 10fc0cb:	mov    %eax,(%rbx)
 10fc0cd:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fc0cf:	mov    -0x90(%rbp),%rax
 10fc0d6:	lock incq 0x48(%rax)
 10fc0db:	mov    -0x89f7d(%rip),%eax        # 1072164 <__anon_29578>
 10fc0e1:	mov    -0x50(%rbp),%rcx
 10fc0e5:	mov    %eax,(%rcx)
 10fc0e7:	add    $0xfb8,%rsp
 10fc0ee:	pop    %rbx
 10fc0ef:	pop    %r12
 10fc0f1:	pop    %r13
 10fc0f3:	pop    %r14
 10fc0f5:	pop    %r15
 10fc0f7:	pop    %rbp
 10fc0f8:	vzeroupper
 10fc0fb:	ret
 10fc0fc:	cmpb   $0x0,-0x78(%rbp)
 10fc100:	je     10fc257 <core.runtime.Runtime.submitSafeDestination+0x5e7>
 10fc106:	mov    -0xa0(%rbp),%rbx
 10fc10d:	test   %rbx,%rbx
 10fc110:	je     10fc366 <core.runtime.Runtime.submitSafeDestination+0x6f6>
 10fc116:	cmpb   $0x0,0x288(%rbx)
 10fc11d:	je     10fc373 <core.runtime.Runtime.submitSafeDestination+0x703>
 10fc123:	lea    -0xbd0(%rbp),%rsi
 10fc12a:	mov    -0xbd0(%rbp),%r14d
 10fc131:	lea    0x208(%rbx),%rdi
 10fc138:	mov    %rdi,-0x1d8(%rbp)
 10fc13f:	vzeroupper
 10fc142:	call   1132d10 <journal.schema.Registry.validateReady>
 10fc147:	test   %ax,%ax
 10fc14a:	jne    10fc0b8 <core.runtime.Runtime.submitSafeDestination+0x448>
 10fc150:	dec    %r14d
 10fc153:	mov    0x270(%rbx),%rax
 10fc15a:	imul   $0xd8,%r14,%rcx
 10fc161:	vmovups 0xa8(%rax,%rcx,1),%ymm0
 10fc16a:	vmovups %ymm0,-0xb10(%rbp)
 10fc172:	vmovups 0x88(%rax,%rcx,1),%ymm0
 10fc17b:	vmovups %ymm0,-0xb30(%rbp)
 10fc183:	vmovups 0x8(%rax,%rcx,1),%ymm0
 10fc189:	vmovups 0x28(%rax,%rcx,1),%ymm1
 10fc18f:	vmovups 0x48(%rax,%rcx,1),%ymm2
 10fc195:	vmovups 0x68(%rax,%rcx,1),%ymm3
 10fc19b:	vmovups %ymm3,-0xb50(%rbp)
 10fc1a3:	vmovups %ymm2,-0xb70(%rbp)
 10fc1ab:	vmovups %ymm1,-0xb90(%rbp)
 10fc1b3:	lea    -0xaf0(%rbp),%rax
 10fc1ba:	mov    %rax,-0x138(%rbp)
 10fc1c1:	vmovups %ymm0,-0xbb0(%rbp)
 10fc1c9:	movb   $0x1,-0xaf0(%rbp)
 10fc1d0:	lea    0x140(%rbx),%rcx
 10fc1d7:	lea    0x31c4(%r13),%r12
 10fc1de:	lea    0x31ee(%r13),%rax
 10fc1e5:	mov    %rax,-0x78(%rbp)
 10fc1e9:	lea    0x3110(%r13),%rax
 10fc1f0:	mov    %rax,-0xb0(%rbp)
 10fc1f7:	lea    0x3118(%r13),%rax
 10fc1fe:	mov    %rax,-0xa8(%rbp)
 10fc205:	cmpb   $0x0,-0x98(%rbp)
 10fc20c:	cmove  %r12,%rcx
 10fc210:	mov    %rcx,-0x98(%rbp)
 10fc217:	mov    %rbx,%rsi
 10fc21a:	je     10fc46c <core.runtime.Runtime.submitSafeDestination+0x7fc>
 10fc220:	lea    0x164(%rsi),%rcx
 10fc227:	lea    -0x220(%rbp),%r14
 10fc22e:	lea    -0xbd0(%rbp),%rbx
 10fc235:	mov    %rcx,-0x80(%rbp)
 10fc239:	mov    0x140(%rsi),%eax
 10fc23f:	mov    %eax,-0x140(%rbp)
 10fc245:	cmpb   $0x0,0x288(%rsi)
 10fc24c:	jne    10fcaaf <core.runtime.Runtime.submitSafeDestination+0xe3f>
 10fc252:	jmp    10fc9ea <core.runtime.Runtime.submitSafeDestination+0xd7a>
 10fc257:	mov    -0xa0(%rbp),%rsi
 10fc25e:	test   %rsi,%rsi
 10fc261:	je     10fc381 <core.runtime.Runtime.submitSafeDestination+0x711>
 10fc267:	lea    0x31ee(%r13),%rax
 10fc26e:	mov    %rax,-0x78(%rbp)
 10fc272:	lea    0x3110(%r13),%rax
 10fc279:	mov    %rax,-0xb0(%rbp)
 10fc280:	lea    0x3118(%r13),%rax
 10fc287:	mov    %rax,-0xa8(%rbp)
 10fc28e:	cmpb   $0x0,-0x98(%rbp)
 10fc295:	je     10fc522 <core.runtime.Runtime.submitSafeDestination+0x8b2>
 10fc29b:	lea    0x140(%rsi),%rax
 10fc2a2:	mov    %rax,-0x98(%rbp)
 10fc2a9:	lea    0x164(%rsi),%r12
 10fc2b0:	lea    -0xf90(%rbp),%rbx
 10fc2b7:	lea    -0x230(%rbp),%r14
 10fc2be:	mov    0x140(%rsi),%r13d
 10fc2c5:	mov    %rbx,%rdi
 10fc2c8:	mov    %r14,%rdx
 10fc2cb:	vzeroupper
 10fc2ce:	call   10fba30 <journal.journal.Journal.reserveSingleProducer>
 10fc2d3:	movzwl -0xf50(%rbp),%eax
 10fc2da:	test   %eax,%eax
 10fc2dc:	je     10fc5ac <core.runtime.Runtime.submitSafeDestination+0x93c>
 10fc2e2:	mov    %r12,-0x80(%rbp)
 10fc2e6:	cmp    $0x13b,%eax
 10fc2eb:	jne    10fd42d <core.runtime.Runtime.submitSafeDestination+0x17bd>
 10fc2f1:	mov    -0x60(%rbp),%rax
 10fc2f5:	movzbl 0x31ef(%rax),%eax
 10fc2fc:	test   $0x3,%al
 10fc2fe:	jne    10fc5df <core.runtime.Runtime.submitSafeDestination+0x96f>
 10fc304:	mov    $0x1,%al
 10fc306:	mov    -0x80(%rbp),%rcx
 10fc30a:	xchg   %al,(%rcx)
 10fc30c:	mov    -0x60(%rbp),%rax
 10fc310:	movzwl 0x31e8(%rax),%eax
 10fc317:	test   %ax,%ax
 10fc31a:	jne    10fd51f <core.runtime.Runtime.submitSafeDestination+0x18af>
 10fc320:	mov    -0x78(%rbp),%rax
 10fc324:	movzbl (%rax),%eax
 10fc327:	test   %al,%al
 10fc329:	jne    10fd533 <core.runtime.Runtime.submitSafeDestination+0x18c3>
 10fc32f:	mov    -0xb0(%rbp),%rax
 10fc336:	mov    (%rax),%rdi
 10fc339:	mov    -0xa8(%rbp),%rax
 10fc340:	mov    (%rax),%rax
 10fc343:	mov    -0x98(%rbp),%rsi
 10fc34a:	mov    %r13d,%edx
 10fc34d:	call   *0x68(%rax)
 10fc350:	xor    %eax,%eax
 10fc352:	mov    -0x80(%rbp),%r12
 10fc356:	xchg   %al,(%r12)
 10fc35a:	mov    -0xa0(%rbp),%rsi
 10fc361:	jmp    10fc2be <core.runtime.Runtime.submitSafeDestination+0x64e>
 10fc366:	movl   $0x134,(%r12)
 10fc36e:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fc373:	mov    $0x90,%ax
 10fc377:	mov    %ax,(%r12)
 10fc37c:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fc381:	mov    -0x150(%rbp),%rax
 10fc388:	mov    %rax,-0xaa0(%rbp)
 10fc38f:	vmovups -0x190(%rbp),%ymm0
 10fc397:	vmovups -0x170(%rbp),%ymm1
 10fc39f:	vmovups %ymm1,-0xac0(%rbp)
 10fc3a7:	vmovups %ymm0,-0xae0(%rbp)
 10fc3af:	mov    %r10,-0xa98(%rbp)
 10fc3b6:	mov    %r11,-0xa90(%rbp)
 10fc3bd:	mov    %r15,-0xa88(%rbp)
 10fc3c4:	mov    %r9,-0xa80(%rbp)
 10fc3cb:	mov    %rcx,-0xa78(%rbp)
 10fc3d2:	mov    %r8,-0xa70(%rbp)
 10fc3d9:	vmovups -0x1d0(%rbp),%ymm0
 10fc3e1:	vmovups -0x1b0(%rbp),%ymm1
 10fc3e9:	vmovups %ymm0,-0xa68(%rbp)
 10fc3f1:	vmovups %ymm1,-0xa48(%rbp)
 10fc3f9:	mov    %edi,-0xa28(%rbp)
 10fc3ff:	vmovups -0x123(%rbp),%xmm0
 10fc407:	vmovups %xmm0,-0xa17(%rbp)
 10fc40f:	vmovaps -0x130(%rbp),%xmm0
 10fc417:	vmovups %xmm0,-0xa24(%rbp)
 10fc41f:	movzbl -0x29(%rbp),%eax
 10fc423:	mov    %al,-0xa07(%rbp)
 10fc429:	movzwl -0x2c(%rbp),%eax
 10fc42d:	mov    %ax,-0xa02(%rbp)
 10fc434:	mov    -0x30(%rbp),%eax
 10fc437:	mov    %eax,-0xa06(%rbp)
 10fc43d:	lea    -0x148(%rbp),%rdi
 10fc444:	lea    -0xae0(%rbp),%rdx
 10fc44b:	mov    %r13,%rsi
 10fc44e:	mov    -0x88(%rbp),%rcx
 10fc455:	vzeroupper
 10fc458:	call   1100d60 <core.runtime.Runtime.submitSync>
 10fc45d:	mov    -0x148(%rbp),%eax
 10fc463:	mov    %eax,(%r12)
 10fc467:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fc46c:	lea    -0xf48(%rbp),%rbx
 10fc473:	lea    -0xbb0(%rbp),%r13
 10fc47a:	mov    (%r12),%r14d
 10fc47e:	mov    %rbx,%rdi
 10fc481:	lea    -0xbd0(%rbp),%rdx
 10fc488:	vzeroupper
 10fc48b:	call   10fb790 <journal.journal.Journal.reserveWithSchema>
 10fc490:	movzwl -0xf08(%rbp),%eax
 10fc497:	test   %eax,%eax
 10fc499:	je     10fc509 <core.runtime.Runtime.submitSafeDestination+0x899>
 10fc49b:	cmp    $0x13b,%eax
 10fc4a0:	jne    10fd42d <core.runtime.Runtime.submitSafeDestination+0x17bd>
 10fc4a6:	mov    -0x60(%rbp),%rax
 10fc4aa:	movzbl 0x31ef(%rax),%eax
 10fc4b1:	test   $0x3,%al
 10fc4b3:	jne    10fc616 <core.runtime.Runtime.submitSafeDestination+0x9a6>
 10fc4b9:	mov    -0x60(%rbp),%rax
 10fc4bd:	movzwl 0x31e8(%rax),%eax
 10fc4c4:	test   %ax,%ax
 10fc4c7:	jne    10fd527 <core.runtime.Runtime.submitSafeDestination+0x18b7>
 10fc4cd:	mov    -0x78(%rbp),%rax
 10fc4d1:	movzbl (%rax),%eax
 10fc4d4:	test   %al,%al
 10fc4d6:	jne    10fc9c7 <core.runtime.Runtime.submitSafeDestination+0xd57>
 10fc4dc:	mov    -0xb0(%rbp),%rax
 10fc4e3:	mov    (%rax),%rdi
 10fc4e6:	mov    -0xa8(%rbp),%rax
 10fc4ed:	mov    (%rax),%rax
 10fc4f0:	mov    -0x98(%rbp),%rsi
 10fc4f7:	mov    %r14d,%edx
 10fc4fa:	call   *0x68(%rax)
 10fc4fd:	mov    -0xa0(%rbp),%rsi
 10fc504:	jmp    10fc47a <core.runtime.Runtime.submitSafeDestination+0x80a>
 10fc509:	mov    -0x40(%rbp),%rsi
 10fc50d:	mov    -0x38(%rbp),%rdi
 10fc511:	mov    -0x58(%rbp),%r8
 10fc515:	mov    -0x70(%rbp),%r9
 10fc519:	mov    -0x68(%rbp),%r10
 10fc51d:	jmp    10fcbf0 <core.runtime.Runtime.submitSafeDestination+0xf80>
 10fc522:	lea    0x31c4(%r13),%r14
 10fc529:	lea    -0xfd8(%rbp),%rbx
 10fc530:	mov    (%r14),%r13d
 10fc533:	mov    %rbx,%rdi
 10fc536:	vzeroupper
 10fc539:	call   10fb570 <journal.journal.Journal.reserve>
 10fc53e:	movzwl -0xf98(%rbp),%eax
 10fc545:	test   %eax,%eax
 10fc547:	je     10fc5ac <core.runtime.Runtime.submitSafeDestination+0x93c>
 10fc549:	cmp    $0x13b,%eax
 10fc54e:	jne    10fd42d <core.runtime.Runtime.submitSafeDestination+0x17bd>
 10fc554:	mov    -0x60(%rbp),%rax
 10fc558:	movzbl 0x31ef(%rax),%eax
 10fc55f:	test   $0x3,%al
 10fc561:	jne    10fc5df <core.runtime.Runtime.submitSafeDestination+0x96f>
 10fc563:	mov    -0x60(%rbp),%rax
 10fc567:	movzwl 0x31e8(%rax),%eax
 10fc56e:	test   %ax,%ax
 10fc571:	jne    10fd527 <core.runtime.Runtime.submitSafeDestination+0x18b7>
 10fc577:	mov    -0x78(%rbp),%rax
 10fc57b:	movzbl (%rax),%eax
 10fc57e:	test   %al,%al
 10fc580:	jne    10fc9c7 <core.runtime.Runtime.submitSafeDestination+0xd57>
 10fc586:	mov    -0xb0(%rbp),%rax
 10fc58d:	mov    (%rax),%rdi
 10fc590:	mov    -0xa8(%rbp),%rax
 10fc597:	mov    (%rax),%rax
 10fc59a:	mov    %r14,%rsi
 10fc59d:	mov    %r13d,%edx
 10fc5a0:	call   *0x68(%rax)
 10fc5a3:	mov    -0xa0(%rbp),%rsi
 10fc5aa:	jmp    10fc530 <core.runtime.Runtime.submitSafeDestination+0x8c0>
 10fc5ac:	mov    $0x1066ce8,%r13d
 10fc5b2:	mov    $0x1066da8,%ecx
 10fc5b7:	mov    -0x40(%rbp),%rsi
 10fc5bb:	mov    -0x38(%rbp),%rdi
 10fc5bf:	mov    -0x58(%rbp),%r8
 10fc5c3:	mov    -0x70(%rbp),%r9
 10fc5c7:	mov    -0x68(%rbp),%r10
 10fc5cb:	mov    -0xf8(%rbp),%rax
 10fc5d2:	jmp    10fcbfe <core.runtime.Runtime.submitSafeDestination+0xf8e>
 10fc5d7:	mov    %ax,(%rbx)
 10fc5da:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fc5df:	and    $0x3,%eax
 10fc5e2:	cmp    $0x1,%eax
 10fc5e5:	mov    -0x60(%rbp),%r13
 10fc5e9:	mov    -0x40(%rbp),%rsi
 10fc5ed:	mov    -0x38(%rbp),%rdi
 10fc5f1:	mov    -0x58(%rbp),%r8
 10fc5f5:	mov    -0x70(%rbp),%r9
 10fc5f9:	mov    -0x68(%rbp),%r10
 10fc5fd:	je     10fd508 <core.runtime.Runtime.submitSafeDestination+0x1898>
 10fc603:	mov    $0x1066ce8,%edx
 10fc608:	mov    $0x1066da8,%eax
 10fc60d:	mov    %rax,-0x138(%rbp)
 10fc614:	jmp    10fc641 <core.runtime.Runtime.submitSafeDestination+0x9d1>
 10fc616:	and    $0x3,%eax
 10fc619:	cmp    $0x1,%eax
 10fc61c:	mov    -0x60(%rbp),%r13
 10fc620:	mov    -0x40(%rbp),%rsi
 10fc624:	mov    -0x38(%rbp),%rdi
 10fc628:	mov    -0x58(%rbp),%r8
 10fc62c:	mov    -0x70(%rbp),%r9
 10fc630:	mov    -0x68(%rbp),%r10
 10fc634:	je     10fd508 <core.runtime.Runtime.submitSafeDestination+0x1898>
 10fc63a:	lea    -0xbb0(%rbp),%rdx
 10fc641:	mov    -0x138(%rbp),%rax
 10fc648:	cmpb   $0x0,(%rax)
 10fc64b:	je     10fc7b8 <core.runtime.Runtime.submitSafeDestination+0xb48>
 10fc651:	vmovups 0xa0(%rdx),%ymm0
 10fc659:	vmovups %ymm0,-0xe60(%rbp)
 10fc661:	vmovups 0x80(%rdx),%ymm0
 10fc669:	vmovups %ymm0,-0xe80(%rbp)
 10fc671:	vmovups (%rdx),%ymm0
 10fc675:	vmovups 0x20(%rdx),%ymm1
 10fc67a:	vmovups 0x40(%rdx),%ymm2
 10fc67f:	vmovups 0x60(%rdx),%ymm3
 10fc684:	vmovups %ymm3,-0xea0(%rbp)
 10fc68c:	vmovups %ymm2,-0xec0(%rbp)
 10fc694:	vmovups %ymm1,-0xee0(%rbp)
 10fc69c:	vmovups %ymm0,-0xf00(%rbp)
 10fc6a4:	mov    -0xf8(%rbp),%rax
 10fc6ab:	cmpb   $0x0,0x140(%rax)
 10fc6b2:	je     10fc7d3 <core.runtime.Runtime.submitSafeDestination+0xb63>
 10fc6b8:	mov    0x138(%rax),%rcx
 10fc6bf:	mov    -0x150(%rbp),%rax
 10fc6c6:	mov    %rax,-0x480(%rbp)
 10fc6cd:	vmovups -0x190(%rbp),%ymm0
 10fc6d5:	vmovups -0x170(%rbp),%ymm1
 10fc6dd:	vmovups %ymm1,-0x4a0(%rbp)
 10fc6e5:	vmovups %ymm0,-0x4c0(%rbp)
 10fc6ed:	mov    %r10,-0x478(%rbp)
 10fc6f4:	mov    -0x100(%rbp),%r12
 10fc6fb:	mov    %r12,-0x470(%rbp)
 10fc702:	mov    %r15,-0x468(%rbp)
 10fc709:	mov    %r9,-0x460(%rbp)
 10fc710:	mov    %r8,-0x458(%rbp)
 10fc717:	mov    %rdi,-0x450(%rbp)
 10fc71e:	vmovups -0x1d0(%rbp),%ymm0
 10fc726:	vmovups -0x1b0(%rbp),%ymm1
 10fc72e:	vmovups %ymm0,-0x448(%rbp)
 10fc736:	vmovups %ymm1,-0x428(%rbp)
 10fc73e:	mov    %esi,-0x408(%rbp)
 10fc744:	vmovaps -0x130(%rbp),%xmm0
 10fc74c:	vmovups %xmm0,-0x404(%rbp)
 10fc754:	vmovups -0x123(%rbp),%xmm0
 10fc75c:	vmovups %xmm0,-0x3f7(%rbp)
 10fc764:	movzbl -0x29(%rbp),%ebx
 10fc768:	mov    %bl,-0x3e7(%rbp)
 10fc76e:	mov    -0x30(%rbp),%eax
 10fc771:	mov    %eax,-0x3e6(%rbp)
 10fc777:	movzwl -0x2c(%rbp),%eax
 10fc77b:	mov    %ax,-0x3e2(%rbp)
 10fc782:	lea    -0x240(%rbp),%rdi
 10fc789:	lea    -0x4c0(%rbp),%rsi
 10fc790:	vzeroupper
 10fc793:	call   110ce90 <core.reference_encoding.sizeMeasured>
 10fc798:	mov    -0x68(%rbp),%r10
 10fc79c:	mov    -0x70(%rbp),%r9
 10fc7a0:	mov    -0x58(%rbp),%r8
 10fc7a4:	mov    -0x38(%rbp),%rdi
 10fc7a8:	mov    -0x40(%rbp),%rsi
 10fc7ac:	movzwl -0x238(%rbp),%eax
 10fc7b3:	jmp    10fc8ce <core.runtime.Runtime.submitSafeDestination+0xc5e>
 10fc7b8:	movzbl -0x29(%rbp),%ebx
 10fc7bc:	mov    -0x50(%rbp),%r14
 10fc7c0:	mov    -0x88(%rbp),%rcx
 10fc7c7:	mov    -0x100(%rbp),%r12
 10fc7ce:	jmp    10fc8e2 <core.runtime.Runtime.submitSafeDestination+0xc72>
 10fc7d3:	mov    -0x150(%rbp),%rax
 10fc7da:	mov    %rax,-0x560(%rbp)
 10fc7e1:	vmovups -0x190(%rbp),%ymm0
 10fc7e9:	vmovups -0x170(%rbp),%ymm1
 10fc7f1:	vmovups %ymm1,-0x580(%rbp)
 10fc7f9:	vmovups %ymm0,-0x5a0(%rbp)
 10fc801:	mov    %r10,-0x558(%rbp)
 10fc808:	mov    -0x100(%rbp),%r12
 10fc80f:	mov    %r12,-0x550(%rbp)
 10fc816:	mov    %r15,-0x548(%rbp)
 10fc81d:	mov    %r9,-0x540(%rbp)
 10fc824:	mov    %r8,-0x538(%rbp)
 10fc82b:	mov    %rdi,-0x530(%rbp)
 10fc832:	vmovups -0x1d0(%rbp),%ymm0
 10fc83a:	vmovups -0x1b0(%rbp),%ymm1
 10fc842:	vmovups %ymm0,-0x528(%rbp)
 10fc84a:	vmovups %ymm1,-0x508(%rbp)
 10fc852:	mov    %esi,-0x4e8(%rbp)
 10fc858:	vmovups -0x123(%rbp),%xmm0
 10fc860:	vmovups %xmm0,-0x4d7(%rbp)
 10fc868:	vmovaps -0x130(%rbp),%xmm0
 10fc870:	vmovups %xmm0,-0x4e4(%rbp)
 10fc878:	movzbl -0x29(%rbp),%ebx
 10fc87c:	mov    %bl,-0x4c7(%rbp)
 10fc882:	mov    -0x30(%rbp),%eax
 10fc885:	mov    %eax,-0x4c6(%rbp)
 10fc88b:	movzwl -0x2c(%rbp),%eax
 10fc88f:	mov    %ax,-0x4c2(%rbp)
 10fc896:	lea    -0x250(%rbp),%rdi
 10fc89d:	lea    -0x5a0(%rbp),%rsi
 10fc8a4:	lea    -0xf00(%rbp),%rdx
 10fc8ab:	vzeroupper
 10fc8ae:	call   1100ff0 <core.schema_codec.encodedReferenceSize>
 10fc8b3:	mov    -0x68(%rbp),%r10
 10fc8b7:	mov    -0x70(%rbp),%r9
 10fc8bb:	mov    -0x58(%rbp),%r8
 10fc8bf:	mov    -0x38(%rbp),%rdi
 10fc8c3:	mov    -0x40(%rbp),%rsi
 10fc8c7:	movzwl -0x248(%rbp),%eax
 10fc8ce:	test   %ax,%ax
 10fc8d1:	mov    -0x50(%rbp),%r14
 10fc8d5:	mov    -0x88(%rbp),%rcx
 10fc8dc:	jne    10fc9dc <core.runtime.Runtime.submitSafeDestination+0xd6c>
 10fc8e2:	mov    -0x150(%rbp),%rax
 10fc8e9:	mov    %rax,-0x640(%rbp)
 10fc8f0:	vmovups -0x190(%rbp),%ymm0
 10fc8f8:	vmovups -0x170(%rbp),%ymm1
 10fc900:	vmovups %ymm1,-0x660(%rbp)
 10fc908:	vmovups %ymm0,-0x680(%rbp)
 10fc910:	vmovups -0x1d0(%rbp),%ymm0
 10fc918:	vmovups -0x1b0(%rbp),%ymm1
 10fc920:	vmovups %ymm0,-0x608(%rbp)
 10fc928:	vmovups %ymm1,-0x5e8(%rbp)
 10fc930:	vmovaps -0x130(%rbp),%xmm0
 10fc938:	vmovups %xmm0,-0x5c4(%rbp)
 10fc940:	vmovups -0x123(%rbp),%xmm0
 10fc948:	vmovups %xmm0,-0x5b7(%rbp)
 10fc950:	mov    -0x30(%rbp),%eax
 10fc953:	mov    %eax,-0x5a6(%rbp)
 10fc959:	movzwl -0x2c(%rbp),%eax
 10fc95d:	mov    %ax,-0x5a2(%rbp)
 10fc964:	or     $0x80000000,%esi
 10fc96a:	mov    %r10,-0x638(%rbp)
 10fc971:	mov    %r12,-0x630(%rbp)
 10fc978:	mov    %r15,-0x628(%rbp)
 10fc97f:	mov    %r9,-0x620(%rbp)
 10fc986:	mov    %r8,-0x618(%rbp)
 10fc98d:	mov    %rdi,-0x610(%rbp)
 10fc994:	mov    %esi,-0x5c8(%rbp)
 10fc99a:	mov    %bl,-0x5a7(%rbp)
 10fc9a0:	lea    -0x144(%rbp),%rdi
 10fc9a7:	lea    -0x680(%rbp),%rdx
 10fc9ae:	mov    %r13,%rsi
 10fc9b1:	vzeroupper
 10fc9b4:	call   1100d60 <core.runtime.Runtime.submitSync>
 10fc9b9:	mov    -0x144(%rbp),%eax
 10fc9bf:	mov    %eax,(%r14)
 10fc9c2:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fc9c7:	mov    -0x90(%rbp),%rax
 10fc9ce:	lock incq 0x68(%rax)
 10fc9d3:	mov    -0x50(%rbp),%rcx
 10fc9d7:	jmp    10fd54b <core.runtime.Runtime.submitSafeDestination+0x18db>
 10fc9dc:	mov    %ax,(%r14)
 10fc9e0:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fc9e5:	mov    %r14,%rbx
 10fc9e8:	jmp    10fc9f4 <core.runtime.Runtime.submitSafeDestination+0xd84>
 10fc9ea:	mov    %rbx,%r12
 10fc9ed:	mov    %r14,%rbx
 10fc9f0:	mov    $0x90,%ax
 10fc9f4:	mov    %ax,-0x2c0(%rbp)
 10fc9fb:	movzwl %ax,%ecx
 10fc9fe:	cmp    $0x13b,%ecx
 10fca04:	mov    -0x40(%rbp),%rsi
 10fca08:	mov    -0x38(%rbp),%rdi
 10fca0c:	mov    -0x58(%rbp),%r8
 10fca10:	mov    -0x70(%rbp),%r9
 10fca14:	mov    -0x68(%rbp),%r10
 10fca18:	jne    10fd42d <core.runtime.Runtime.submitSafeDestination+0x17bd>
 10fca1e:	mov    -0x60(%rbp),%r13
 10fca22:	movzbl 0x31ef(%r13),%eax
 10fca2a:	test   $0x3,%al
 10fca2c:	jne    10fd4fc <core.runtime.Runtime.submitSafeDestination+0x188c>
 10fca32:	mov    $0x1,%al
 10fca34:	mov    -0x80(%rbp),%rcx
 10fca38:	xchg   %al,(%rcx)
 10fca3a:	movzwl 0x31e8(%r13),%eax
 10fca42:	test   %ax,%ax
 10fca45:	jne    10fd51f <core.runtime.Runtime.submitSafeDestination+0x18af>
 10fca4b:	mov    -0x78(%rbp),%rax
 10fca4f:	movzbl (%rax),%eax
 10fca52:	test   %al,%al
 10fca54:	jne    10fd533 <core.runtime.Runtime.submitSafeDestination+0x18c3>
 10fca5a:	mov    -0xb0(%rbp),%rax
 10fca61:	mov    (%rax),%rdi
 10fca64:	mov    -0xa8(%rbp),%rax
 10fca6b:	mov    (%rax),%rax
 10fca6e:	mov    -0x98(%rbp),%rsi
 10fca75:	mov    -0x140(%rbp),%edx
 10fca7b:	vzeroupper
 10fca7e:	call   *0x68(%rax)
 10fca81:	mov    -0xa0(%rbp),%rsi
 10fca88:	xor    %eax,%eax
 10fca8a:	mov    -0x80(%rbp),%rcx
 10fca8e:	xchg   %al,(%rcx)
 10fca90:	mov    %rbx,%r14
 10fca93:	mov    %r12,%rbx
 10fca96:	mov    0x140(%rsi),%eax
 10fca9c:	mov    %eax,-0x140(%rbp)
 10fcaa2:	cmpb   $0x0,0x288(%rsi)
 10fcaa9:	je     10fc9ea <core.runtime.Runtime.submitSafeDestination+0xd7a>
 10fcaaf:	mov    -0xbd0(%rbp),%eax
 10fcab5:	mov    %eax,-0x13c(%rbp)
 10fcabb:	movzwl -0xbcc(%rbp),%r13d
 10fcac3:	mov    -0x1d8(%rbp),%rdi
 10fcaca:	mov    %rbx,%r12
 10fcacd:	mov    %rbx,%rsi
 10fcad0:	vzeroupper
 10fcad3:	call   1132d10 <journal.schema.Registry.validateReady>
 10fcad8:	test   %ax,%ax
 10fcadb:	jne    10fc9e5 <core.runtime.Runtime.submitSafeDestination+0xd75>
 10fcae1:	mov    %r14,%rbx
 10fcae4:	mov    %r14,%rdi
 10fcae7:	mov    -0xa0(%rbp),%r14
 10fcaee:	mov    %r14,%rsi
 10fcaf1:	lea    -0x230(%rbp),%rdx
 10fcaf8:	call   10fba30 <journal.journal.Journal.reserveSingleProducer>
 10fcafd:	movzwl -0x1e0(%rbp),%eax
 10fcb04:	test   %ax,%ax
 10fcb07:	jne    10fc9f4 <core.runtime.Runtime.submitSafeDestination+0xd84>
 10fcb0d:	vmovups -0x210(%rbp),%xmm0
 10fcb15:	mov    -0x1e4(%rbp),%eax
 10fcb1b:	cmpl   $0x1,0x2f0(%r14)
 10fcb23:	mov    -0x40(%rbp),%rsi
 10fcb27:	mov    -0x38(%rbp),%rdi
 10fcb2b:	mov    -0x58(%rbp),%r8
 10fcb2f:	mov    -0x70(%rbp),%r9
 10fcb33:	mov    -0x68(%rbp),%r10
 10fcb37:	je     10fcb82 <core.runtime.Runtime.submitSafeDestination+0xf12>
 10fcb39:	mov    0x1a0(%r14),%rcx
 10fcb40:	mov    0x200(%r14),%rdx
 10fcb47:	imul   -0x210(%rbp),%rdx
 10fcb4f:	movw   $0x0,0x1026(%rcx,%rdx,1)
 10fcb59:	mov    -0x13c(%rbp),%r11d
 10fcb60:	mov    %r11d,0x1020(%rcx,%rdx,1)
 10fcb68:	mov    %r13w,0x1024(%rcx,%rdx,1)
 10fcb71:	vmovups -0xbca(%rbp),%xmm1
 10fcb79:	vmovups %xmm1,0x1028(%rcx,%rdx,1)
 10fcb82:	movw   $0x0,-0x2c0(%rbp)
 10fcb8b:	vmovups -0x220(%rbp),%xmm1
 10fcb93:	vmovaps %xmm1,-0x300(%rbp)
 10fcb9b:	vmovaps %xmm0,-0x2f0(%rbp)
 10fcba3:	mov    0x10(%r12),%rcx
 10fcba8:	lea    -0x2e0(%rbp),%r11
 10fcbaf:	mov    %rcx,0x10(%r11)
 10fcbb3:	vmovups (%r12),%xmm0
 10fcbb9:	vmovups %xmm0,(%r11)
 10fcbbe:	movb   $0x1,-0x2c8(%rbp)
 10fcbc5:	lea    -0x1e7(%rbp),%rdx
 10fcbcc:	movzbl 0x2(%rdx),%ecx
 10fcbd0:	mov    %cl,0x1b(%r11)
 10fcbd4:	movzwl (%rdx),%ecx
 10fcbd7:	mov    %cx,0x19(%r11)
 10fcbdc:	mov    %eax,-0x2c4(%rbp)
 10fcbe2:	lea    -0x300(%rbp),%rbx
 10fcbe9:	lea    -0xbb0(%rbp),%r13
 10fcbf0:	mov    -0xf8(%rbp),%rax
 10fcbf7:	lea    -0xaf0(%rbp),%rcx
 10fcbfe:	vmovups (%rbx),%ymm0
 10fcc02:	vmovups %ymm0,-0xf0(%rbp)
 10fcc0a:	vmovups 0x20(%rbx),%ymm0
 10fcc0f:	vmovups %ymm0,-0xd0(%rbp)
 10fcc17:	mov    -0xe8(%rbp),%r11
 10fcc1e:	cmpb   $0x0,(%rcx)
 10fcc21:	mov    %r11,-0x38(%rbp)
 10fcc25:	je     10fcdc2 <core.runtime.Runtime.submitSafeDestination+0x1152>
 10fcc2b:	vmovups 0xa0(%r13),%ymm0
 10fcc34:	vmovups %ymm0,-0xda0(%rbp)
 10fcc3c:	vmovups 0x80(%r13),%ymm0
 10fcc45:	vmovups %ymm0,-0xdc0(%rbp)
 10fcc4d:	vmovups 0x0(%r13),%ymm0
 10fcc53:	vmovups 0x20(%r13),%ymm1
 10fcc59:	vmovups 0x40(%r13),%ymm2
 10fcc5f:	vmovups 0x60(%r13),%ymm3
 10fcc65:	vmovups %ymm3,-0xde0(%rbp)
 10fcc6d:	vmovups %ymm2,-0xe00(%rbp)
 10fcc75:	vmovups %ymm1,-0xe20(%rbp)
 10fcc7d:	vmovups %ymm0,-0xe40(%rbp)
 10fcc85:	cmpb   $0x0,0x140(%rax)
 10fcc8c:	je     10fcef7 <core.runtime.Runtime.submitSafeDestination+0x1287>
 10fcc92:	mov    0x138(%rax),%rcx
 10fcc99:	mov    -0x150(%rbp),%rax
 10fcca0:	mov    %rax,-0x720(%rbp)
 10fcca7:	vmovups -0x190(%rbp),%ymm0
 10fccaf:	vmovups -0x170(%rbp),%ymm1
 10fccb7:	vmovups %ymm1,-0x740(%rbp)
 10fccbf:	vmovups %ymm0,-0x760(%rbp)
 10fccc7:	mov    %r10,-0x718(%rbp)
 10fccce:	mov    %r11,-0x710(%rbp)
 10fccd5:	mov    %r15,-0x708(%rbp)
 10fccdc:	mov    %r9,-0x700(%rbp)
 10fcce3:	mov    %r8,-0x6f8(%rbp)
 10fccea:	mov    %rdi,-0x6f0(%rbp)
 10fccf1:	vmovups -0x1d0(%rbp),%ymm0
 10fccf9:	vmovups -0x1b0(%rbp),%ymm1
 10fcd01:	vmovups %ymm0,-0x6e8(%rbp)
 10fcd09:	vmovups %ymm1,-0x6c8(%rbp)
 10fcd11:	lea    -0x258(%rbp),%rbx
 10fcd18:	mov    %esi,-0x6a8(%rbp)
 10fcd1e:	vmovaps -0x130(%rbp),%xmm0
 10fcd26:	vmovups %xmm0,-0x6a4(%rbp)
 10fcd2e:	lea    -0x260(%rbp),%r15
 10fcd35:	vmovups -0x123(%rbp),%xmm0
 10fcd3d:	vmovups %xmm0,-0x697(%rbp)
 10fcd45:	movzbl -0x29(%rbp),%eax
 10fcd49:	mov    %al,-0x687(%rbp)
 10fcd4f:	movzwl -0x2c(%rbp),%eax
 10fcd53:	mov    %ax,-0x682(%rbp)
 10fcd5a:	mov    -0x30(%rbp),%eax
 10fcd5d:	mov    %eax,-0x686(%rbp)
 10fcd63:	movzbl -0xb4(%rbp),%r14d
 10fcd6b:	mov    -0xf0(%rbp),%r12
 10fcd72:	mov    -0xe0(%rbp),%r13
 10fcd79:	mov    0x200(%r12),%rax
 10fcd81:	imul   %r13,%rax
 10fcd85:	mov    0x1a0(%r12),%rdx
 10fcd8d:	mov    0x1f8(%r12),%r9
 10fcd95:	lea    (%rdx,%rax,1),%r8
 10fcd99:	add    $0x1040,%r8
 10fcda0:	lea    -0x268(%rbp),%rdi
 10fcda7:	lea    -0x760(%rbp),%rsi
 10fcdae:	lea    -0xe40(%rbp),%rdx
 10fcdb5:	vzeroupper
 10fcdb8:	call   10fe7c0 <core.reference_encoding.writeMeasured>
 10fcdbd:	jmp    10fd13b <core.runtime.Runtime.submitSafeDestination+0x14cb>
 10fcdc2:	cmpb   $0x0,0x140(%rax)
 10fcdc9:	je     10fd01f <core.runtime.Runtime.submitSafeDestination+0x13af>
 10fcdcf:	mov    0x138(%rax),%rdx
 10fcdd6:	mov    -0x150(%rbp),%rax
 10fcddd:	mov    %rax,-0x8e0(%rbp)
 10fcde4:	vmovups -0x190(%rbp),%ymm0
 10fcdec:	vmovups -0x170(%rbp),%ymm1
 10fcdf4:	vmovups %ymm1,-0x900(%rbp)
 10fcdfc:	vmovups %ymm0,-0x920(%rbp)
 10fce04:	mov    %r10,-0x8d8(%rbp)
 10fce0b:	mov    %r11,-0x8d0(%rbp)
 10fce12:	mov    %r15,-0x8c8(%rbp)
 10fce19:	mov    %r9,-0x8c0(%rbp)
 10fce20:	mov    %r8,-0x8b8(%rbp)
 10fce27:	mov    %rdi,-0x8b0(%rbp)
 10fce2e:	vmovups -0x1d0(%rbp),%ymm0
 10fce36:	vmovups -0x1b0(%rbp),%ymm1
 10fce3e:	vmovups %ymm0,-0x8a8(%rbp)
 10fce46:	vmovups %ymm1,-0x888(%rbp)
 10fce4e:	lea    -0x288(%rbp),%rbx
 10fce55:	mov    %esi,-0x868(%rbp)
 10fce5b:	vmovaps -0x130(%rbp),%xmm0
 10fce63:	vmovups %xmm0,-0x864(%rbp)
 10fce6b:	lea    -0x290(%rbp),%r15
 10fce72:	vmovups -0x123(%rbp),%xmm0
 10fce7a:	vmovups %xmm0,-0x857(%rbp)
 10fce82:	movzbl -0x29(%rbp),%eax
 10fce86:	mov    %al,-0x847(%rbp)
 10fce8c:	movzwl -0x2c(%rbp),%eax
 10fce90:	mov    %ax,-0x842(%rbp)
 10fce97:	mov    -0x30(%rbp),%eax
 10fce9a:	mov    %eax,-0x846(%rbp)
 10fcea0:	movzbl -0xb4(%rbp),%r14d
 10fcea8:	mov    -0xf0(%rbp),%r12
 10fceaf:	mov    -0xe0(%rbp),%r13
 10fceb6:	mov    0x200(%r12),%rax
 10fcebe:	imul   %r13,%rax
 10fcec2:	mov    0x1a0(%r12),%rcx
 10fceca:	mov    0x1f8(%r12),%r8
 10fced2:	add    %rax,%rcx
 10fced5:	add    $0x1040,%rcx
 10fcedc:	lea    -0x298(%rbp),%rdi
 10fcee3:	lea    -0x920(%rbp),%rsi
 10fceea:	vzeroupper
 10fceed:	call   10fe090 <core.codec.encodeSized>
 10fcef2:	jmp    10fd13b <core.runtime.Runtime.submitSafeDestination+0x14cb>
 10fcef7:	mov    -0x150(%rbp),%rax
 10fcefe:	mov    %rax,-0x800(%rbp)
 10fcf05:	vmovups -0x190(%rbp),%ymm0
 10fcf0d:	vmovups -0x170(%rbp),%ymm1
 10fcf15:	vmovups %ymm1,-0x820(%rbp)
 10fcf1d:	vmovups %ymm0,-0x840(%rbp)
 10fcf25:	mov    %r10,-0x7f8(%rbp)
 10fcf2c:	mov    %r11,-0x7f0(%rbp)
 10fcf33:	mov    %r15,-0x7e8(%rbp)
 10fcf3a:	mov    %r9,-0x7e0(%rbp)
 10fcf41:	mov    %r8,-0x7d8(%rbp)
 10fcf48:	mov    %rdi,-0x7d0(%rbp)
 10fcf4f:	vmovups -0x1d0(%rbp),%ymm0
 10fcf57:	vmovups -0x1b0(%rbp),%ymm1
 10fcf5f:	vmovups %ymm0,-0x7c8(%rbp)
 10fcf67:	vmovups %ymm1,-0x7a8(%rbp)
 10fcf6f:	lea    -0x270(%rbp),%rbx
 10fcf76:	mov    %esi,-0x788(%rbp)
 10fcf7c:	vmovups -0x123(%rbp),%xmm0
 10fcf84:	vmovups %xmm0,-0x777(%rbp)
 10fcf8c:	lea    -0x278(%rbp),%r15
 10fcf93:	vmovaps -0x130(%rbp),%xmm0
 10fcf9b:	vmovups %xmm0,-0x784(%rbp)
 10fcfa3:	movzbl -0x29(%rbp),%eax
 10fcfa7:	mov    %al,-0x767(%rbp)
 10fcfad:	movzwl -0x2c(%rbp),%eax
 10fcfb1:	mov    %ax,-0x762(%rbp)
 10fcfb8:	mov    -0x30(%rbp),%eax
 10fcfbb:	mov    %eax,-0x766(%rbp)
 10fcfc1:	movzbl -0xb4(%rbp),%r14d
 10fcfc9:	mov    -0xf0(%rbp),%r12
 10fcfd0:	mov    -0xe0(%rbp),%r13
 10fcfd7:	mov    0x200(%r12),%rax
 10fcfdf:	imul   %r13,%rax
 10fcfe3:	mov    0x1a0(%r12),%rcx
 10fcfeb:	mov    0x1f8(%r12),%r8
 10fcff3:	add    %rax,%rcx
 10fcff6:	add    $0x1040,%rcx
 10fcffd:	lea    -0x280(%rbp),%rdi
 10fd004:	lea    -0x840(%rbp),%rsi
 10fd00b:	lea    -0xe40(%rbp),%rdx
 10fd012:	vzeroupper
 10fd015:	call   10fe740 <core.schema_codec.encodeReference>
 10fd01a:	jmp    10fd13b <core.runtime.Runtime.submitSafeDestination+0x14cb>
 10fd01f:	mov    -0x150(%rbp),%rax
 10fd026:	mov    %rax,-0x9c0(%rbp)
 10fd02d:	vmovups -0x190(%rbp),%ymm0
 10fd035:	vmovups -0x170(%rbp),%ymm1
 10fd03d:	vmovups %ymm1,-0x9e0(%rbp)
 10fd045:	vmovups %ymm0,-0xa00(%rbp)
 10fd04d:	mov    %r10,-0x9b8(%rbp)
 10fd054:	mov    %r11,-0x9b0(%rbp)
 10fd05b:	mov    %r15,-0x9a8(%rbp)
 10fd062:	mov    %r9,-0x9a0(%rbp)
 10fd069:	mov    %r8,-0x998(%rbp)
 10fd070:	mov    %rdi,-0x990(%rbp)
 10fd077:	vmovups -0x1d0(%rbp),%ymm0
 10fd07f:	vmovups -0x1b0(%rbp),%ymm1
 10fd087:	vmovups %ymm0,-0x988(%rbp)
 10fd08f:	vmovups %ymm1,-0x968(%rbp)
 10fd097:	lea    -0x2a0(%rbp),%rbx
 10fd09e:	mov    %esi,-0x948(%rbp)
 10fd0a4:	vmovups -0x123(%rbp),%xmm0
 10fd0ac:	vmovups %xmm0,-0x937(%rbp)
 10fd0b4:	lea    -0x2a8(%rbp),%r15
 10fd0bb:	vmovaps -0x130(%rbp),%xmm0
 10fd0c3:	vmovups %xmm0,-0x944(%rbp)
 10fd0cb:	movzbl -0x29(%rbp),%eax
 10fd0cf:	mov    %al,-0x927(%rbp)
 10fd0d5:	movzwl -0x2c(%rbp),%eax
 10fd0d9:	mov    %ax,-0x922(%rbp)
 10fd0e0:	mov    -0x30(%rbp),%eax
 10fd0e3:	mov    %eax,-0x926(%rbp)
 10fd0e9:	movzbl -0xb4(%rbp),%r14d
 10fd0f1:	mov    -0xf0(%rbp),%r12
 10fd0f8:	mov    -0xe0(%rbp),%r13
 10fd0ff:	mov    0x200(%r12),%rax
 10fd107:	imul   %r13,%rax
 10fd10b:	mov    0x1a0(%r12),%rdx
 10fd113:	mov    0x1f8(%r12),%rcx
 10fd11b:	add    %rax,%rdx
 10fd11e:	add    $0x1040,%rdx
 10fd125:	lea    -0x2b0(%rbp),%rdi
 10fd12c:	lea    -0xa00(%rbp),%rsi
 10fd133:	vzeroupper
 10fd136:	call   10fe010 <core.codec.encode>
 10fd13b:	movzwl (%rbx),%ebx
 10fd13e:	test   %ebx,%ebx
 10fd140:	je     10fd1d4 <core.runtime.Runtime.submitSafeDestination+0x1564>
 10fd146:	test   $0x1,%r14b
 10fd14a:	jne    10fd307 <core.runtime.Runtime.submitSafeDestination+0x1697>
 10fd150:	mov    -0xd8(%rbp),%rax
 10fd157:	test   %rax,%rax
 10fd15a:	je     10fd2b0 <core.runtime.Runtime.submitSafeDestination+0x1640>
 10fd160:	testb  $0x1,0x2fd(%r12)
 10fd169:	je     10fd307 <core.runtime.Runtime.submitSafeDestination+0x1697>
 10fd16f:	mov    0x150(%r12),%rcx
 10fd177:	mov    %rcx,%rdx
 10fd17a:	shr    $0x2,%rdx
 10fd17e:	xor    %rdx,%rax
 10fd181:	and    $0x3,%ecx
 10fd184:	or     %rax,%rcx
 10fd187:	jne    10fd307 <core.runtime.Runtime.submitSafeDestination+0x1697>
 10fd18d:	mov    %fs:0xfffffffffffbb5a8,%rax
 10fd196:	test   %rax,%rax
 10fd199:	je     10fd307 <core.runtime.Runtime.submitSafeDestination+0x1697>
 10fd19f:	mov    0x148(%r12),%rcx
 10fd1a7:	cmp    %rax,%rcx
 10fd1aa:	jne    10fd307 <core.runtime.Runtime.submitSafeDestination+0x1697>
 10fd1b0:	mov    0x160(%r12),%edx
 10fd1b8:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd1c1:	jne    10fd439 <core.runtime.Runtime.submitSafeDestination+0x17c9>
 10fd1c7:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd1cf:	jmp    10fd451 <core.runtime.Runtime.submitSafeDestination+0x17e1>
 10fd1d4:	mov    -0x40(%rbp),%rdi
 10fd1d8:	test   %edi,%edi
 10fd1da:	je     10fd1f3 <core.runtime.Runtime.submitSafeDestination+0x1583>
 10fd1dc:	mov    %rdi,%rax
 10fd1df:	shl    $0x6,%rax
 10fd1e3:	mov    -0x88(%rbp),%rcx
 10fd1ea:	add    %rcx,%rax
 10fd1ed:	add    $0xffffffffffffffc0,%rax
 10fd1f1:	jmp    10fd200 <core.runtime.Runtime.submitSafeDestination+0x1590>
 10fd1f3:	mov    -0x88(%rbp),%rax
 10fd1fa:	add    $0x9810,%rax
 10fd200:	mov    (%r15),%r12
 10fd203:	lock incq (%rax)
 10fd207:	mov    $0x13c,%bx
 10fd20b:	cmpb   $0x0,-0xb4(%rbp)
 10fd212:	jne    10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd218:	mov    -0xd8(%rbp),%rcx
 10fd21f:	test   %rcx,%rcx
 10fd222:	je     10fd576 <core.runtime.Runtime.submitSafeDestination+0x1906>
 10fd228:	mov    -0xf0(%rbp),%rax
 10fd22f:	mov    $0x92,%bx
 10fd233:	testb  $0x1,0x2fd(%rax)
 10fd23a:	je     10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd240:	mov    0x150(%rax),%rdx
 10fd247:	mov    %rdx,%rsi
 10fd24a:	shr    $0x2,%rsi
 10fd24e:	mov    $0x94,%bx
 10fd252:	cmp    %rsi,%rcx
 10fd255:	jne    10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd25b:	mov    $0x95,%bx
 10fd25f:	test   $0x3,%dl
 10fd262:	jne    10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd268:	mov    %fs:0xfffffffffffbb5a8,%rcx
 10fd271:	mov    $0x96,%bx
 10fd275:	test   %rcx,%rcx
 10fd278:	je     10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd27e:	mov    0x148(%rax),%rdx
 10fd285:	cmp    %rcx,%rdx
 10fd288:	jne    10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd28e:	mov    0x160(%rax),%edx
 10fd294:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd29d:	jne    10fd556 <core.runtime.Runtime.submitSafeDestination+0x18e6>
 10fd2a3:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd2ab:	jmp    10fd56e <core.runtime.Runtime.submitSafeDestination+0x18fe>
 10fd2b0:	mov    -0x38(%rbp),%rdx
 10fd2b4:	mov    0x1a0(%r12),%rcx
 10fd2bc:	imul   0x200(%r12),%r13
 10fd2c5:	lea    0x1(,%rdx,4),%rax
 10fd2cd:	lea    0x3(,%rdx,4),%rdx
 10fd2d5:	lock cmpxchg %rdx,0x1000(%rcx,%r13,1)
 10fd2df:	setne  -0x220(%rbp)
 10fd2e6:	jne    10fd300 <core.runtime.Runtime.submitSafeDestination+0x1690>
 10fd2e8:	cmpq   $0x0,-0xd8(%rbp)
 10fd2f0:	je     10fd300 <core.runtime.Runtime.submitSafeDestination+0x1690>
 10fd2f2:	mov    -0xf0(%rbp),%rax
 10fd2f9:	decq   0x158(%rax)
 10fd300:	movb   $0x1,-0xb4(%rbp)
 10fd307:	mov    -0x60(%rbp),%r15
 10fd30b:	testb  $0x1,0x31ea(%r15)
 10fd313:	je     10fd320 <core.runtime.Runtime.submitSafeDestination+0x16b0>
 10fd315:	mov    -0x78(%rbp),%rax
 10fd319:	movzbl (%rax),%eax
 10fd31c:	test   %al,%al
 10fd31e:	je     10fd362 <core.runtime.Runtime.submitSafeDestination+0x16f2>
 10fd320:	lock incl 0x31d8(%r15)
 10fd328:	movzbl 0x31ec(%r15),%eax
 10fd330:	test   $0x1,%al
 10fd332:	jne    10fd33f <core.runtime.Runtime.submitSafeDestination+0x16cf>
 10fd334:	mov    -0x78(%rbp),%rax
 10fd338:	movzbl (%rax),%eax
 10fd33b:	test   %al,%al
 10fd33d:	je     10fd362 <core.runtime.Runtime.submitSafeDestination+0x16f2>
 10fd33f:	lea    0x31d8(%r15),%rsi
 10fd346:	mov    -0xb0(%rbp),%rax
 10fd34d:	mov    (%rax),%rdi
 10fd350:	mov    -0xa8(%rbp),%rax
 10fd357:	mov    (%rax),%rax
 10fd35a:	mov    $0xffffffff,%edx
 10fd35f:	call   *0x70(%rax)
 10fd362:	cmp    $0x137,%ebx
 10fd368:	mov    -0x50(%rbp),%r14
 10fd36c:	mov    -0x90(%rbp),%rax
 10fd373:	je     10fd37e <core.runtime.Runtime.submitSafeDestination+0x170e>
 10fd375:	cmp    $0x62,%ebx
 10fd378:	jne    10fd40e <core.runtime.Runtime.submitSafeDestination+0x179e>
 10fd37e:	lock incq 0x60(%rax)
 10fd383:	cmpb   $0x0,-0xb4(%rbp)
 10fd38a:	jne    10fd4ee <core.runtime.Runtime.submitSafeDestination+0x187e>
 10fd390:	mov    -0xd8(%rbp),%rcx
 10fd397:	test   %rcx,%rcx
 10fd39a:	je     10fd48f <core.runtime.Runtime.submitSafeDestination+0x181f>
 10fd3a0:	mov    -0xf0(%rbp),%rax
 10fd3a7:	testb  $0x1,0x2fd(%rax)
 10fd3ae:	je     10fd4ee <core.runtime.Runtime.submitSafeDestination+0x187e>
 10fd3b4:	mov    0x150(%rax),%rdx
 10fd3bb:	mov    %rdx,%rsi
 10fd3be:	shr    $0x2,%rsi
 10fd3c2:	xor    %rsi,%rcx
 10fd3c5:	and    $0x3,%edx
 10fd3c8:	or     %rcx,%rdx
 10fd3cb:	jne    10fd4ee <core.runtime.Runtime.submitSafeDestination+0x187e>
 10fd3d1:	mov    %fs:0xfffffffffffbb5a8,%rcx
 10fd3da:	test   %rcx,%rcx
 10fd3dd:	je     10fd4ee <core.runtime.Runtime.submitSafeDestination+0x187e>
 10fd3e3:	mov    0x148(%rax),%rdx
 10fd3ea:	cmp    %rcx,%rdx
 10fd3ed:	jne    10fd4ee <core.runtime.Runtime.submitSafeDestination+0x187e>
 10fd3f3:	mov    0x160(%rax),%edx
 10fd3f9:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd402:	jne    10fd473 <core.runtime.Runtime.submitSafeDestination+0x1803>
 10fd404:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd40c:	jmp    10fd48b <core.runtime.Runtime.submitSafeDestination+0x181b>
 10fd40e:	mov    %r15,%rdi
 10fd411:	mov    %ebx,%esi
 10fd413:	call   10fdd50 <core.runtime.Runtime.reportError>
 10fd418:	lea    -0xf0(%rbp),%rdi
 10fd41f:	call   10fdf10 <journal.journal.Reservation.abort>
 10fd424:	mov    %bx,(%r14)
 10fd428:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fd42d:	mov    -0x50(%rbp),%rcx
 10fd431:	mov    %ax,(%rcx)
 10fd434:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fd439:	mov    $0xba,%eax
 10fd43e:	syscall
 10fd440:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd448:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd451:	cmp    %eax,%edx
 10fd453:	jne    10fd307 <core.runtime.Runtime.submitSafeDestination+0x1697>
 10fd459:	mov    -0xf0(%rbp),%r12
 10fd460:	mov    -0xe8(%rbp),%rdx
 10fd467:	mov    -0xe0(%rbp),%r13
 10fd46e:	jmp    10fd2b4 <core.runtime.Runtime.submitSafeDestination+0x1644>
 10fd473:	mov    $0xba,%eax
 10fd478:	syscall
 10fd47a:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd482:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd48b:	cmp    %eax,%edx
 10fd48d:	jne    10fd4ee <core.runtime.Runtime.submitSafeDestination+0x187e>
 10fd48f:	mov    -0xf0(%rbp),%rax
 10fd496:	mov    -0xe8(%rbp),%rcx
 10fd49d:	mov    0x1a0(%rax),%rdx
 10fd4a4:	mov    0x200(%rax),%rsi
 10fd4ab:	imul   -0xe0(%rbp),%rsi
 10fd4b3:	lea    0x1(,%rcx,4),%rax
 10fd4bb:	lea    0x3(,%rcx,4),%rcx
 10fd4c3:	lock cmpxchg %rcx,0x1000(%rdx,%rsi,1)
 10fd4cd:	setne  -0x220(%rbp)
 10fd4d4:	jne    10fd4ee <core.runtime.Runtime.submitSafeDestination+0x187e>
 10fd4d6:	cmpq   $0x0,-0xd8(%rbp)
 10fd4de:	je     10fd4ee <core.runtime.Runtime.submitSafeDestination+0x187e>
 10fd4e0:	mov    -0xf0(%rbp),%rax
 10fd4e7:	decq   0x158(%rax)
 10fd4ee:	mov    -0x8b3c0(%rip),%eax        # 1072134 <__anon_33692>
 10fd4f4:	mov    %eax,(%r14)
 10fd4f7:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fd4fc:	and    $0x3,%eax
 10fd4ff:	cmp    $0x1,%eax
 10fd502:	jne    10fc63a <core.runtime.Runtime.submitSafeDestination+0x9ca>
 10fd508:	mov    -0x90(%rbp),%rax
 10fd50f:	lock incq 0x58(%rax)
 10fd514:	mov    -0x8b37e(%rip),%eax        # 107219c <__anon_33637>
 10fd51a:	jmp    10fc0e1 <core.runtime.Runtime.submitSafeDestination+0x471>
 10fd51f:	xor    %ecx,%ecx
 10fd521:	mov    -0x80(%rbp),%rdx
 10fd525:	xchg   %cl,(%rdx)
 10fd527:	mov    -0x50(%rbp),%rcx
 10fd52b:	mov    %ax,(%rcx)
 10fd52e:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fd533:	mov    -0x50(%rbp),%rcx
 10fd537:	mov    -0x90(%rbp),%rax
 10fd53e:	mov    -0x80(%rbp),%rdx
 10fd542:	lock incq 0x68(%rax)
 10fd547:	xor    %eax,%eax
 10fd549:	xchg   %al,(%rdx)
 10fd54b:	mov    -0x8b401(%rip),%eax        # 1072150 <__anon_33661>
 10fd551:	jmp    10fc0e5 <core.runtime.Runtime.submitSafeDestination+0x475>
 10fd556:	mov    $0xba,%eax
 10fd55b:	syscall
 10fd55d:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd565:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd56e:	cmp    %eax,%edx
 10fd570:	jne    10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd576:	cmpb   $0x0,-0xb8(%rbp)
 10fd57d:	mov    -0xf0(%rbp),%r14
 10fd584:	je     10fd5b4 <core.runtime.Runtime.submitSafeDestination+0x1944>
 10fd586:	cmpb   $0x0,0x288(%r14)
 10fd58e:	je     10fd635 <core.runtime.Runtime.submitSafeDestination+0x19c5>
 10fd594:	lea    -0xd0(%rbp),%rsi
 10fd59b:	lea    0x208(%r14),%rdi
 10fd5a2:	call   1132d10 <journal.schema.Registry.validateReady>
 10fd5a7:	mov    -0x40(%rbp),%rdi
 10fd5ab:	test   %ax,%ax
 10fd5ae:	jne    10fd807 <core.runtime.Runtime.submitSafeDestination+0x1b97>
 10fd5b4:	mov    $0x13d,%bx
 10fd5b8:	cmp    0x1f8(%r14),%r12
 10fd5bf:	ja     10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd5c1:	mov    0x200(%r14),%r13
 10fd5c8:	imul   -0xe0(%rbp),%r13
 10fd5d0:	mov    0x1a0(%r14),%r8
 10fd5d7:	mov    0x1000(%r8,%r13,1),%rax
 10fd5df:	mov    -0xe8(%rbp),%rcx
 10fd5e6:	lea    0x1(,%rcx,4),%rdx
 10fd5ee:	mov    $0x13c,%bx
 10fd5f2:	cmp    %rdx,%rax
 10fd5f5:	jne    10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
 10fd5f7:	mov    -0xf0(%rbp),%r15
 10fd5fe:	mov    -0xe0(%rbp),%rsi
 10fd605:	mov    0x200(%r15),%rbx
 10fd60c:	imul   %rsi,%rbx
 10fd610:	add    0x1a0(%r15),%rbx
 10fd617:	mov    0x1f0(%r15),%rdi
 10fd61e:	lea    -0x1(%rcx),%rax
 10fd622:	mov    %rax,%rdx
 10fd625:	or     %rdi,%rdx
 10fd628:	shr    $0x20,%rdx
 10fd62c:	je     10fd675 <core.runtime.Runtime.submitSafeDestination+0x1a05>
 10fd62e:	xor    %edx,%edx
 10fd630:	div    %rdi
 10fd633:	jmp    10fd679 <core.runtime.Runtime.submitSafeDestination+0x1a09>
 10fd635:	mov    $0x90,%bx
 10fd639:	mov    %rdi,%rax
 10fd63c:	shl    $0x6,%rax
 10fd640:	mov    -0x88(%rbp),%rdx
 10fd647:	lea    0x9810(%rdx),%rcx
 10fd64e:	test   %edi,%edi
 10fd650:	lea    -0x40(%rdx,%rax,1),%rax
 10fd655:	cmove  %rcx,%rax
 10fd659:	lock decq (%rax)
 10fd65d:	lea    -0xf0(%rbp),%rdi
 10fd664:	call   10fdf10 <journal.journal.Reservation.abort>
 10fd669:	mov    -0x50(%rbp),%rax
 10fd66d:	mov    %bx,(%rax)
 10fd670:	jmp    10fc0e7 <core.runtime.Runtime.submitSafeDestination+0x477>
 10fd675:	xor    %edx,%edx
 10fd677:	div    %edi
 10fd679:	cmpl   $0x1,0x2f0(%r15)
 10fd681:	je     10fd6d0 <core.runtime.Runtime.submitSafeDestination+0x1a60>
 10fd683:	mov    -0xd0(%rbp),%edi
 10fd689:	movzwl -0xcc(%rbp),%edx
 10fd690:	vxorps %xmm0,%xmm0,%xmm0
 10fd694:	cmpb   $0x0,-0xb8(%rbp)
 10fd69b:	vmovups %xmm0,0x1020(%rbx)
 10fd6a3:	movq   $0x0,0x1030(%rbx)
 10fd6ae:	je     10fd6d0 <core.runtime.Runtime.submitSafeDestination+0x1a60>
 10fd6b0:	mov    %edi,0x1020(%rbx)
 10fd6b6:	lea    -0xca(%rbp),%rdi
 10fd6bd:	mov    %dx,0x1024(%rbx)
 10fd6c4:	vmovups (%rdi),%xmm0
 10fd6c8:	vmovups %xmm0,0x1028(%rbx)
 10fd6d0:	lea    0x0(,%rcx,4),%r14
 10fd6d8:	mov    %r12d,0x1018(%rbx)
 10fd6df:	xor    %edx,%edx
 10fd6e1:	cmpb   $0x0,0x2fc(%r15)
 10fd6e9:	je     10fd7b2 <core.runtime.Runtime.submitSafeDestination+0x1b42>
 10fd6ef:	mov    %r8,-0x40(%rbp)
 10fd6f3:	inc    %rax
 10fd6f6:	mov    0x1a0(%r15),%rdx
 10fd6fd:	imul   0x200(%r15),%rsi
 10fd705:	add    %rsi,%rdx
 10fd708:	add    $0x1040,%rdx
 10fd70f:	mov    %rdx,-0x38(%rbp)
 10fd713:	cmpl   $0x1,0x2f0(%r15)
 10fd71b:	jne    10fd74b <core.runtime.Runtime.submitSafeDestination+0x1adb>
 10fd71d:	mov    %rcx,-0x220(%rbp)
 10fd724:	mov    %rax,-0x218(%rbp)
 10fd72b:	mov    %r12d,-0x210(%rbp)
 10fd732:	movl   $0xffffffff,-0x44(%rbp)
 10fd739:	lea    -0x44(%rbp),%rdi
 10fd73d:	lea    -0x220(%rbp),%rsi
 10fd744:	mov    $0x14,%edx
 10fd749:	jmp    10fd794 <core.runtime.Runtime.submitSafeDestination+0x1b24>
 10fd74b:	lea    0x1020(%rbx),%rdx
 10fd752:	mov    %rdx,-0x58(%rbp)
 10fd756:	mov    %rcx,-0x220(%rbp)
 10fd75d:	mov    %rax,-0x218(%rbp)
 10fd764:	mov    %r12d,-0x210(%rbp)
 10fd76b:	movl   $0xffffffff,-0x44(%rbp)
 10fd772:	lea    -0x44(%rbp),%rdi
 10fd776:	lea    -0x220(%rbp),%rsi
 10fd77d:	mov    $0x14,%edx
 10fd782:	call   113d6a0 <platform.crc32.Crc32.update>
 10fd787:	mov    $0x18,%edx
 10fd78c:	lea    -0x44(%rbp),%rdi
 10fd790:	mov    -0x58(%rbp),%rsi
 10fd794:	call   113d6a0 <platform.crc32.Crc32.update>
 10fd799:	lea    -0x44(%rbp),%rdi
 10fd79d:	mov    -0x38(%rbp),%rsi
 10fd7a1:	mov    %r12,%rdx
 10fd7a4:	call   113d6a0 <platform.crc32.Crc32.update>
 10fd7a9:	mov    -0x44(%rbp),%edx
 10fd7ac:	not    %edx
 10fd7ae:	mov    -0x40(%rbp),%r8
 10fd7b2:	mov    %edx,0x101c(%rbx)
 10fd7b8:	or     $0x2,%r14
 10fd7bc:	mov    %r14,0x1000(%r8,%r13,1)
 10fd7c4:	cmpq   $0x0,-0xd8(%rbp)
 10fd7cc:	je     10fd7d5 <core.runtime.Runtime.submitSafeDestination+0x1b65>
 10fd7ce:	decq   0x158(%r15)
 10fd7d5:	movb   $0x1,-0xb4(%rbp)
 10fd7dc:	mov    -0x90(%rbp),%rax
 10fd7e3:	lock incq (%rax)
 10fd7e7:	mov    -0x60(%rbp),%rdi
 10fd7eb:	call   10f5870 <core.runtime.Runtime.notify>
 10fd7f0:	lea    -0xf0(%rbp),%rdi
 10fd7f7:	call   10fdf10 <journal.journal.Reservation.abort>
 10fd7fc:	mov    -0x8b6da(%rip),%eax        # 1072128 <__anon_23525>
 10fd802:	jmp    10fc0e1 <core.runtime.Runtime.submitSafeDestination+0x471>
 10fd807:	mov    %eax,%ebx
 10fd809:	jmp    10fd639 <core.runtime.Runtime.submitSafeDestination+0x19c9>
