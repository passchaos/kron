
.zig-cache/crc-pure/vex-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fb590 <journal.journal.Journal.reserve>:
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:402
 10fb590:	55                   	push   %rbp
 10fb591:	48 89 e5             	mov    %rsp,%rbp
/home/passchaos/project-z/kron/src/journal/journal.zig:403
 10fb594:	f6 86 fd 02 00 00 01 	testb  $0x1,0x2fd(%rsi)
 10fb59b:	74 26                	je     10fb5c3 <journal.journal.Journal.reserve+0x33>
/home/passchaos/project-z/kron/src/journal/journal.zig:403 (discriminator 2)
 10fb59d:	c5 fc 10 05 8b b6 f6 	vmovups -0x94975(%rip),%ymm0        # 1066c30 <__anon_33597+0x20>
 10fb5a4:	ff 
 10fb5a5:	c5 fc 11 47 20       	vmovups %ymm0,0x20(%rdi)
 10fb5aa:	c5 fc 10 05 5e b6 f6 	vmovups -0x949a2(%rip),%ymm0        # 1066c10 <__anon_33597>
 10fb5b1:	ff 
 10fb5b2:	c5 fc 11 07          	vmovups %ymm0,(%rdi)
 10fb5b6:	48 c7 47 40 3a 01 00 	movq   $0x13a,0x40(%rdi)
 10fb5bd:	00 
 10fb5be:	5d                   	pop    %rbp
 10fb5bf:	c5 f8 77             	vzeroupper
 10fb5c2:	c3                   	ret
 10fb5c3:	49 b9 fe ff ff ff ff 	movabs $0x3ffffffffffffffe,%r9
 10fb5ca:	ff ff 3f 
/home/passchaos/project-z/kron/src/journal/journal.zig:404
 10fb5cd:	48 8b 86 a0 01 00 00 	mov    0x1a0(%rsi),%rax
atomic.Value(u64).load():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:21
 10fb5d4:	48 8b 48 40          	mov    0x40(%rax),%rcx
 10fb5d8:	eb 1d                	jmp    10fb5f7 <journal.journal.Journal.reserve+0x67>
journal.journal.Journal.reserve():
 10fb5da:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
/home/passchaos/project-z/kron/src/journal/journal.zig:410
 10fb5e0:	48 8b 86 a0 01 00 00 	mov    0x1a0(%rsi),%rax
atomic.Value(u64).load():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:21 (discriminator 4)
 10fb5e7:	48 8b 40 40          	mov    0x40(%rax),%rax
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:411
 10fb5eb:	48 39 c8             	cmp    %rcx,%rax
 10fb5ee:	48 89 c1             	mov    %rax,%rcx
 10fb5f1:	0f 84 b1 00 00 00    	je     10fb6a8 <journal.journal.Journal.reserve+0x118>
/home/passchaos/project-z/kron/src/journal/journal.zig:406
 10fb5f7:	4c 39 c9             	cmp    %r9,%rcx
 10fb5fa:	0f 87 82 00 00 00    	ja     10fb682 <journal.journal.Journal.reserve+0xf2>
/home/passchaos/project-z/kron/src/journal/journal.zig:407
 10fb600:	4c 8b 86 f0 01 00 00 	mov    0x1f0(%rsi),%r8
 10fb607:	48 89 c8             	mov    %rcx,%rax
 10fb60a:	4c 09 c0             	or     %r8,%rax
 10fb60d:	48 c1 e8 20          	shr    $0x20,%rax
 10fb611:	74 1d                	je     10fb630 <journal.journal.Journal.reserve+0xa0>
 10fb613:	48 89 c8             	mov    %rcx,%rax
 10fb616:	31 d2                	xor    %edx,%edx
 10fb618:	49 f7 f0             	div    %r8
/home/passchaos/project-z/kron/src/journal/journal.zig:408
 10fb61b:	48 8b 86 90 02 00 00 	mov    0x290(%rsi),%rax
atomic.Value(u64).load():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:21 (discriminator 2)
 10fb622:	48 8b 04 d0          	mov    (%rax,%rdx,8),%rax
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:409
 10fb626:	48 39 c8             	cmp    %rcx,%rax
 10fb629:	72 b5                	jb     10fb5e0 <journal.journal.Journal.reserve+0x50>
 10fb62b:	eb 1a                	jmp    10fb647 <journal.journal.Journal.reserve+0xb7>
 10fb62d:	0f 1f 00             	nopl   (%rax)
/home/passchaos/project-z/kron/src/journal/journal.zig:407
 10fb630:	89 c8                	mov    %ecx,%eax
 10fb632:	31 d2                	xor    %edx,%edx
 10fb634:	41 f7 f0             	div    %r8d
/home/passchaos/project-z/kron/src/journal/journal.zig:408
 10fb637:	48 8b 86 90 02 00 00 	mov    0x290(%rsi),%rax
atomic.Value(u64).load():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:21 (discriminator 2)
 10fb63e:	48 8b 04 d0          	mov    (%rax,%rdx,8),%rax
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:409
 10fb642:	48 39 c8             	cmp    %rcx,%rax
 10fb645:	72 99                	jb     10fb5e0 <journal.journal.Journal.reserve+0x50>
 10fb647:	4c 8b 96 a0 01 00 00 	mov    0x1a0(%rsi),%r10
/home/passchaos/project-z/kron/src/journal/journal.zig:417
 10fb64e:	76 10                	jbe    10fb660 <journal.journal.Journal.reserve+0xd0>
atomic.Value(u64).load():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:21 (discriminator 6)
 10fb650:	49 8b 4a 40          	mov    0x40(%r10),%rcx
 10fb654:	eb a1                	jmp    10fb5f7 <journal.journal.Journal.reserve+0x67>
journal.journal.Journal.reserve():
 10fb656:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10fb65d:	00 00 00 
/home/passchaos/project-z/kron/src/journal/journal.zig:421
 10fb660:	4c 8d 41 01          	lea    0x1(%rcx),%r8
atomic.Value(u64).cmpxchgWeak():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:39
 10fb664:	48 89 c8             	mov    %rcx,%rax
 10fb667:	f0 4d 0f b1 42 40    	lock cmpxchg %r8,0x40(%r10)
 10fb66d:	0f 95 45 f8          	setne  -0x8(%rbp)
 10fb671:	41 0f 95 c2          	setne  %r10b
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:421 (discriminator 2)
 10fb675:	45 84 d2             	test   %r10b,%r10b
 10fb678:	74 54                	je     10fb6ce <journal.journal.Journal.reserve+0x13e>
 10fb67a:	48 89 c1             	mov    %rax,%rcx
/home/passchaos/project-z/kron/src/journal/journal.zig:423
 10fb67d:	e9 75 ff ff ff       	jmp    10fb5f7 <journal.journal.Journal.reserve+0x67>
/home/passchaos/project-z/kron/src/journal/journal.zig:406 (discriminator 2)
 10fb682:	c5 fc 10 05 0e b6 f6 	vmovups -0x949f2(%rip),%ymm0        # 1066c98 <__anon_33623+0x20>
 10fb689:	ff 
 10fb68a:	c5 fc 11 47 20       	vmovups %ymm0,0x20(%rdi)
 10fb68f:	c5 fc 10 05 e1 b5 f6 	vmovups -0x94a1f(%rip),%ymm0        # 1066c78 <__anon_33623>
 10fb696:	ff 
 10fb697:	c5 fc 11 07          	vmovups %ymm0,(%rdi)
 10fb69b:	48 c7 47 40 b2 00 00 	movq   $0xb2,0x40(%rdi)
 10fb6a2:	00 
 10fb6a3:	5d                   	pop    %rbp
 10fb6a4:	c5 f8 77             	vzeroupper
 10fb6a7:	c3                   	ret
/home/passchaos/project-z/kron/src/journal/journal.zig:415 (discriminator 2)
 10fb6a8:	c5 fc 10 05 30 b6 f6 	vmovups -0x949d0(%rip),%ymm0        # 1066ce0 <__anon_33625+0x20>
 10fb6af:	ff 
 10fb6b0:	c5 fc 11 47 20       	vmovups %ymm0,0x20(%rdi)
 10fb6b5:	c5 fc 10 05 03 b6 f6 	vmovups -0x949fd(%rip),%ymm0        # 1066cc0 <__anon_33625>
 10fb6bc:	ff 
 10fb6bd:	c5 fc 11 07          	vmovups %ymm0,(%rdi)
 10fb6c1:	48 c7 47 40 3b 01 00 	movq   $0x13b,0x40(%rdi)
 10fb6c8:	00 
 10fb6c9:	5d                   	pop    %rbp
 10fb6ca:	c5 f8 77             	vzeroupper
 10fb6cd:	c3                   	ret
 10fb6ce:	41 b9 01 00 00 00    	mov    $0x1,%r9d
atomic.Value(usize).fetchAdd():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:53
 10fb6d4:	f0 4c 0f c1 8e d0 02 	lock xadd %r9,0x2d0(%rsi)
 10fb6db:	00 00 
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:425 (discriminator 2)
 10fb6dd:	49 ff c1             	inc    %r9
atomic.Value(usize).fetchMax():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:65
 10fb6e0:	48 8b 86 d8 02 00 00 	mov    0x2d8(%rsi),%rax
 10fb6e7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10fb6ee:	00 00 
 10fb6f0:	4c 39 c8             	cmp    %r9,%rax
 10fb6f3:	4d 89 ca             	mov    %r9,%r10
 10fb6f6:	4c 0f 47 d0          	cmova  %rax,%r10
 10fb6fa:	f0 4c 0f b1 96 d8 02 	lock cmpxchg %r10,0x2d8(%rsi)
 10fb701:	00 00 
 10fb703:	75 eb                	jne    10fb6f0 <journal.journal.Journal.reserve+0x160>
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:428
 10fb705:	48 8b 86 a0 01 00 00 	mov    0x1a0(%rsi),%rax
 10fb70c:	4c 8b 9e 00 02 00 00 	mov    0x200(%rsi),%r11
 10fb713:	49 89 d2             	mov    %rdx,%r10
journal.journal.Journal.slotBytes():
/home/passchaos/project-z/kron/src/journal/journal.zig:287
 10fb716:	4c 0f af da          	imul   %rdx,%r11
journal.format.tag():
/home/passchaos/project-z/kron/src/journal/format.zig:27
 10fb71a:	4a 8d 14 85 01 00 00 	lea    0x1(,%r8,4),%rdx
 10fb721:	00 
atomic.Value(u64).store():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/atomic.zig:25
 10fb722:	4a 89 94 18 00 10 00 	mov    %rdx,0x1000(%rax,%r11,1)
 10fb729:	00 
journal.journal.Journal.slotBytes():
/home/passchaos/project-z/kron/src/journal/journal.zig:287
 10fb72a:	4e 8d 0c 18          	lea    (%rax,%r11,1),%r9
mem.writeInt():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/mem.zig:2022
 10fb72e:	4e 89 84 18 08 10 00 	mov    %r8,0x1008(%rax,%r11,1)
 10fb735:	00 
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:433
 10fb736:	4c 8b 9e f0 01 00 00 	mov    0x1f0(%rsi),%r11
journal.journal.Journal.generation():
/home/passchaos/project-z/kron/src/journal/journal.zig:293
 10fb73d:	48 89 c8             	mov    %rcx,%rax
 10fb740:	4c 09 d8             	or     %r11,%rax
 10fb743:	48 c1 e8 20          	shr    $0x20,%rax
 10fb747:	74 0a                	je     10fb753 <journal.journal.Journal.reserve+0x1c3>
 10fb749:	48 89 c8             	mov    %rcx,%rax
 10fb74c:	31 d2                	xor    %edx,%edx
 10fb74e:	49 f7 f3             	div    %r11
 10fb751:	eb 07                	jmp    10fb75a <journal.journal.Journal.reserve+0x1ca>
 10fb753:	89 c8                	mov    %ecx,%eax
 10fb755:	31 d2                	xor    %edx,%edx
 10fb757:	41 f7 f3             	div    %r11d
 10fb75a:	48 ff c0             	inc    %rax
mem.writeInt():
/home/passchaos/Temp/zig-x86_64-linux-0.16.0/lib/std/mem.zig:2022
 10fb75d:	49 89 81 10 10 00 00 	mov    %rax,0x1010(%r9)
journal.journal.Journal.writeSlotSchema():
/home/passchaos/project-z/kron/src/journal/journal.zig:297
 10fb764:	83 be f0 02 00 00 01 	cmpl   $0x1,0x2f0(%rsi)
 10fb76b:	74 18                	je     10fb785 <journal.journal.Journal.reserve+0x1f5>
/home/passchaos/project-z/kron/src/journal/journal.zig:298
 10fb76d:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 10fb771:	c4 c1 78 11 81 20 10 	vmovups %xmm0,0x1020(%r9)
 10fb778:	00 00 
 10fb77a:	49 c7 81 30 10 00 00 	movq   $0x0,0x1030(%r9)
 10fb781:	00 00 00 00 
journal.journal.Journal.reserve():
/home/passchaos/project-z/kron/src/journal/journal.zig:435 (discriminator 2)
 10fb785:	66 c7 47 40 00 00    	movw   $0x0,0x40(%rdi)
 10fb78b:	48 89 37             	mov    %rsi,(%rdi)
 10fb78e:	4c 89 47 08          	mov    %r8,0x8(%rdi)
 10fb792:	4c 89 57 10          	mov    %r10,0x10(%rdi)
 10fb796:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 10fb79a:	c5 fc 11 47 18       	vmovups %ymm0,0x18(%rdi)
 10fb79f:	48 c7 47 35 00 00 00 	movq   $0x0,0x35(%rdi)
 10fb7a6:	00 
 10fb7a7:	5d                   	pop    %rbp
 10fb7a8:	c5 f8 77             	vzeroupper
 10fb7ab:	c3                   	ret
