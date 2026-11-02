
.zig-cache/submit-abi/ref-only-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fbc90 <core.runtime.Runtime.submitSafeDestination>:
 10fbc90:	push   %rbp
 10fbc91:	mov    %rsp,%rbp
 10fbc94:	push   %r15
 10fbc96:	push   %r14
 10fbc98:	push   %r13
 10fbc9a:	push   %r12
 10fbc9c:	push   %rbx
 10fbc9d:	sub    $0xef8,%rsp
 10fbca4:	mov    (%rcx),%r12
 10fbca7:	mov    0x8(%rcx),%r8
 10fbcab:	mov    0x20(%rcx),%r13
 10fbcaf:	mov    0x28(%rcx),%rax
 10fbcb3:	mov    %rax,-0x98(%rbp)
 10fbcba:	vmovups 0x30(%rcx),%xmm0
 10fbcbf:	vmovaps %xmm0,-0x260(%rbp)
 10fbcc7:	movzbl 0x40(%rcx),%eax
 10fbccb:	mov    %al,-0x90(%rbp)
 10fbcd1:	mov    0x68(%rcx),%rax
 10fbcd5:	mov    %rax,-0x140(%rbp)
 10fbcdc:	vmovups 0x58(%rcx),%xmm0
 10fbce1:	vmovaps %xmm0,-0x150(%rbp)
 10fbce9:	movzbl 0x70(%rcx),%eax
 10fbced:	mov    %al,-0x78(%rbp)
 10fbcf0:	mov    %rsi,%r14
 10fbcf3:	mov    %rdi,%rbx
 10fbcf6:	mov    0xb8(%rdx),%edi
 10fbcfc:	lea    -0x41(%rdi),%eax
 10fbcff:	lea    -0x1(%rdi),%esi
 10fbd02:	shl    $0x6,%rsi
 10fbd06:	cmp    $0xffffffc0,%eax
 10fbd09:	lea    (%rsi,%rsi,2),%rax
 10fbd0d:	mov    $0x3000,%r15d
 10fbd13:	mov    0x40(%rdx),%rsi
 10fbd17:	mov    %rsi,-0x180(%rbp)
 10fbd1e:	vmovups (%rdx),%ymm0
 10fbd22:	vmovups 0x20(%rdx),%ymm1
 10fbd27:	vmovups %ymm1,-0x1a0(%rbp)
 10fbd2f:	vmovups %ymm0,-0x1c0(%rbp)
 10fbd37:	mov    0x50(%rdx),%r11
 10fbd3b:	vmovups 0x98(%rdx),%ymm0
 10fbd43:	vmovups %ymm0,-0x1e0(%rbp)
 10fbd4b:	vmovups 0x78(%rdx),%ymm0
 10fbd50:	vmovups %ymm0,-0x200(%rbp)
 10fbd58:	vmovups 0xbc(%rdx),%xmm0
 10fbd60:	vmovups 0xc9(%rdx),%xmm1
 10fbd68:	vmovups %xmm1,-0x123(%rbp)
 10fbd70:	vmovaps %xmm0,-0x130(%rbp)
 10fbd78:	cmovae %rax,%r15
 10fbd7c:	movzwl 0xde(%rdx),%eax
 10fbd83:	mov    %ax,-0x2c(%rbp)
 10fbd87:	mov    0xda(%rdx),%eax
 10fbd8d:	mov    %eax,-0x30(%rbp)
 10fbd90:	mov    %rcx,-0xf8(%rbp)
 10fbd97:	movzbl 0x74(%rcx),%eax
 10fbd9b:	mov    %al,-0x29(%rbp)
 10fbd9e:	add    %r14,%r15
 10fbda1:	mov    0x3178(%r14),%r10
 10fbda8:	cmpb   $0x0,0x7420(%r13)
 10fbdb0:	mov    0x7430(%r13),%rcx
 10fbdb7:	mov    0x7438(%r13),%r9
 10fbdbe:	mov    %rdi,-0x40(%rbp)
 10fbdc2:	mov    %r8,-0x38(%rbp)
 10fbdc6:	mov    %rcx,-0x58(%rbp)
 10fbdca:	mov    %r9,-0x80(%rbp)
 10fbdce:	mov    %r10,-0x68(%rbp)
 10fbdd2:	mov    %r11,-0x100(%rbp)
 10fbdd9:	je     10fbee9 <core.runtime.Runtime.submitSafeDestination+0x259>
 10fbddf:	mov    0x40(%rdx),%rax
 10fbde3:	mov    %rax,-0x3d0(%rbp)
 10fbdea:	vmovups (%rdx),%ymm0
 10fbdee:	vmovups 0x20(%rdx),%ymm1
 10fbdf3:	vmovups %ymm1,-0x3f0(%rbp)
 10fbdfb:	vmovups %ymm0,-0x410(%rbp)
 10fbe03:	mov    %r10,-0x3c8(%rbp)
 10fbe0a:	mov    %r11,-0x3c0(%rbp)
 10fbe11:	mov    %r12,-0x3b8(%rbp)
 10fbe18:	mov    %r9,-0x3b0(%rbp)
 10fbe1f:	mov    %rcx,-0x3a8(%rbp)
 10fbe26:	mov    %r8,-0x3a0(%rbp)
 10fbe2d:	lea    0x78(%rdx),%rax
 10fbe31:	vmovups (%rax),%ymm0
 10fbe35:	vmovups 0x20(%rax),%ymm1
 10fbe3a:	lea    0xbc(%rdx),%rax
 10fbe41:	vmovups %ymm0,-0x398(%rbp)
 10fbe49:	vmovups %ymm1,-0x378(%rbp)
 10fbe51:	mov    %edi,-0x358(%rbp)
 10fbe57:	vmovups (%rax),%xmm0
 10fbe5b:	vmovups 0xd(%rax),%xmm1
 10fbe60:	vmovups %xmm0,-0x354(%rbp)
 10fbe68:	vmovups %xmm1,-0x347(%rbp)
 10fbe70:	movzbl -0x29(%rbp),%eax
 10fbe74:	lea    0xda(%rdx),%rcx
 10fbe7b:	mov    %al,-0x337(%rbp)
 10fbe81:	mov    (%rcx),%eax
 10fbe83:	mov    %eax,-0x336(%rbp)
 10fbe89:	movzwl 0x4(%rcx),%eax
 10fbe8d:	mov    %ax,-0x332(%rbp)
 10fbe94:	lea    0x1000(%r13),%rsi
 10fbe9b:	lea    -0x104(%rbp),%rdi
 10fbea2:	lea    -0x410(%rbp),%rdx
 10fbea9:	vzeroupper
 10fbeac:	call   110d350 <pipeline.predicate.Predicate.matches>
 10fbeb1:	movzwl -0x104(%rbp),%eax
 10fbeb8:	test   %ax,%ax
 10fbebb:	jne    10fc588 <core.runtime.Runtime.submitSafeDestination+0x8f8>
 10fbec1:	cmpb   $0x0,-0x102(%rbp)
 10fbec8:	mov    -0x40(%rbp),%rdi
 10fbecc:	mov    -0x38(%rbp),%r8
 10fbed0:	mov    -0x58(%rbp),%rcx
 10fbed4:	mov    -0x80(%rbp),%r9
 10fbed8:	mov    -0x68(%rbp),%r10
 10fbedc:	mov    -0x100(%rbp),%r11
 10fbee3:	je     10fc06e <core.runtime.Runtime.submitSafeDestination+0x3de>
 10fbee9:	mov    %r15,-0x70(%rbp)
 10fbeed:	mov    %r14,-0x60(%rbp)
 10fbef1:	mov    %rbx,-0x50(%rbp)
 10fbef5:	mov    %r13,-0x88(%rbp)
 10fbefc:	mov    0x7490(%r13),%r15
 10fbf03:	and    %r12,%r15
 10fbf06:	je     10fc04e <core.runtime.Runtime.submitSafeDestination+0x3be>
 10fbf0c:	lea    -0xc48(%rbp),%rbx
 10fbf13:	movzbl -0x29(%rbp),%r14d
 10fbf18:	nopl   0x0(%rax,%rax,1)
 10fbf20:	tzcnt  %r15,%r13
 10fbf25:	imul   $0x7650,%r13,%rsi
 10fbf2c:	mov    -0x88(%rbp),%rax
 10fbf33:	add    0x7440(%rax),%rsi
 10fbf3a:	mov    -0x180(%rbp),%rax
 10fbf41:	mov    %rax,-0xc80(%rbp)
 10fbf48:	vmovups -0x1c0(%rbp),%ymm0
 10fbf50:	vmovups -0x1a0(%rbp),%ymm1
 10fbf58:	vmovups %ymm1,-0xca0(%rbp)
 10fbf60:	vmovups %ymm0,-0xcc0(%rbp)
 10fbf68:	mov    %r10,-0xc78(%rbp)
 10fbf6f:	mov    %r11,-0xc70(%rbp)
 10fbf76:	mov    %r12,-0xc68(%rbp)
 10fbf7d:	mov    %r9,-0xc60(%rbp)
 10fbf84:	mov    %rcx,-0xc58(%rbp)
 10fbf8b:	mov    %r8,-0xc50(%rbp)
 10fbf92:	vmovups -0x200(%rbp),%ymm0
 10fbf9a:	vmovups -0x1e0(%rbp),%ymm1
 10fbfa2:	vmovups %ymm1,0x20(%rbx)
 10fbfa7:	vmovups %ymm0,(%rbx)
 10fbfab:	mov    %edi,-0xc08(%rbp)
 10fbfb1:	vmovups -0x123(%rbp),%xmm0
 10fbfb9:	vmovups %xmm0,0x51(%rbx)
 10fbfbe:	vmovaps -0x130(%rbp),%xmm0
 10fbfc6:	vmovups %xmm0,0x44(%rbx)
 10fbfcb:	mov    %r14b,-0xbe7(%rbp)
 10fbfd2:	movzwl -0x2c(%rbp),%eax
 10fbfd6:	mov    %ax,0x66(%rbx)
 10fbfda:	mov    -0x30(%rbp),%eax
 10fbfdd:	mov    %eax,0x62(%rbx)
 10fbfe0:	lea    -0x108(%rbp),%rdi
 10fbfe7:	lea    -0xcc0(%rbp),%rdx
 10fbfee:	vzeroupper
 10fbff1:	call   110d350 <pipeline.predicate.Predicate.matches>
 10fbff6:	movzwl -0x108(%rbp),%eax
 10fbffd:	test   %ax,%ax
 10fc000:	jne    10fc985 <core.runtime.Runtime.submitSafeDestination+0xcf5>
 10fc006:	mov    $0xfffffffffffffffe,%rax
 10fc00d:	mov    %r13d,%ecx
 10fc010:	rol    %cl,%rax
 10fc013:	cmpb   $0x0,-0x106(%rbp)
 10fc01a:	mov    $0xffffffffffffffff,%rcx
 10fc021:	cmovne %rcx,%rax
 10fc025:	and    %rax,%r12
 10fc028:	blsr   %r15,%r15
 10fc02d:	mov    -0x40(%rbp),%rdi
 10fc031:	mov    -0x38(%rbp),%r8
 10fc035:	mov    -0x58(%rbp),%rcx
 10fc039:	mov    -0x80(%rbp),%r9
 10fc03d:	mov    -0x68(%rbp),%r10
 10fc041:	mov    -0x100(%rbp),%r11
 10fc048:	jne    10fbf20 <core.runtime.Runtime.submitSafeDestination+0x290>
 10fc04e:	test   %r12,%r12
 10fc051:	je     10fc07d <core.runtime.Runtime.submitSafeDestination+0x3ed>
 10fc053:	mov    -0x60(%rbp),%r13
 10fc057:	movzwl 0x31e8(%r13),%eax
 10fc05f:	test   %ax,%ax
 10fc062:	mov    -0x50(%rbp),%r15
 10fc066:	je     10fc0a7 <core.runtime.Runtime.submitSafeDestination+0x417>
 10fc068:	mov    %ax,(%r15)
 10fc06c:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc06e:	lock incq 0x48(%r15)
 10fc073:	mov    -0x89ef5(%rip),%eax        # 1072184 <__anon_29578>
 10fc079:	mov    %eax,(%rbx)
 10fc07b:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc07d:	mov    -0x70(%rbp),%rax
 10fc081:	lock incq 0x48(%rax)
 10fc086:	mov    -0x89f08(%rip),%eax        # 1072184 <__anon_29578>
 10fc08c:	mov    -0x50(%rbp),%rcx
 10fc090:	mov    %eax,(%rcx)
 10fc092:	add    $0xef8,%rsp
 10fc099:	pop    %rbx
 10fc09a:	pop    %r12
 10fc09c:	pop    %r13
 10fc09e:	pop    %r14
 10fc0a0:	pop    %r15
 10fc0a2:	pop    %rbp
 10fc0a3:	vzeroupper
 10fc0a6:	ret
 10fc0a7:	cmpb   $0x0,-0x78(%rbp)
 10fc0ab:	je     10fc1fe <core.runtime.Runtime.submitSafeDestination+0x56e>
 10fc0b1:	mov    -0x98(%rbp),%rbx
 10fc0b8:	test   %rbx,%rbx
 10fc0bb:	je     10fc301 <core.runtime.Runtime.submitSafeDestination+0x671>
 10fc0c1:	cmpb   $0x0,0x288(%rbx)
 10fc0c8:	je     10fc30d <core.runtime.Runtime.submitSafeDestination+0x67d>
 10fc0ce:	mov    -0x150(%rbp),%r14d
 10fc0d5:	lea    0x208(%rbx),%rdi
 10fc0dc:	lea    -0x150(%rbp),%rsi
 10fc0e3:	mov    %rdi,-0x168(%rbp)
 10fc0ea:	vzeroupper
 10fc0ed:	call   1132b10 <journal.schema.Registry.validateReady>
 10fc0f2:	test   %ax,%ax
 10fc0f5:	jne    10fc068 <core.runtime.Runtime.submitSafeDestination+0x3d8>
 10fc0fb:	dec    %r14d
 10fc0fe:	mov    0x270(%rbx),%rax
 10fc105:	imul   $0xd8,%r14,%rcx
 10fc10c:	vmovups 0xa8(%rax,%rcx,1),%ymm0
 10fc115:	vmovups %ymm0,-0xb40(%rbp)
 10fc11d:	vmovups 0x88(%rax,%rcx,1),%ymm0
 10fc126:	vmovups %ymm0,-0xb60(%rbp)
 10fc12e:	vmovups 0x8(%rax,%rcx,1),%ymm0
 10fc134:	vmovups 0x28(%rax,%rcx,1),%ymm1
 10fc13a:	vmovups 0x48(%rax,%rcx,1),%ymm2
 10fc140:	vmovups 0x68(%rax,%rcx,1),%ymm3
 10fc146:	vmovups %ymm3,-0xb80(%rbp)
 10fc14e:	vmovups %ymm2,-0xba0(%rbp)
 10fc156:	vmovups %ymm1,-0xbc0(%rbp)
 10fc15e:	lea    -0xb20(%rbp),%rcx
 10fc165:	vmovups %ymm0,-0xbe0(%rbp)
 10fc16d:	movb   $0x1,-0xb20(%rbp)
 10fc174:	lea    0x140(%rbx),%rdx
 10fc17b:	lea    0x31c4(%r13),%r15
 10fc182:	lea    0x31ee(%r13),%rax
 10fc189:	mov    %rax,-0x78(%rbp)
 10fc18d:	lea    0x3110(%r13),%rax
 10fc194:	mov    %rax,-0xa8(%rbp)
 10fc19b:	lea    0x3118(%r13),%rax
 10fc1a2:	mov    %rax,-0xa0(%rbp)
 10fc1a9:	cmpb   $0x0,-0x90(%rbp)
 10fc1b0:	cmove  %r15,%rdx
 10fc1b4:	mov    %rdx,-0x90(%rbp)
 10fc1bb:	mov    %rbx,%rsi
 10fc1be:	mov    %rcx,-0x160(%rbp)
 10fc1c5:	je     10fc404 <core.runtime.Runtime.submitSafeDestination+0x774>
 10fc1cb:	lea    0x164(%rsi),%rbx
 10fc1d2:	lea    -0x150(%rbp),%rax
 10fc1d9:	lea    -0x248(%rbp),%r13
 10fc1e0:	mov    0x140(%rsi),%ecx
 10fc1e6:	cmpb   $0x0,0x288(%rsi)
 10fc1ed:	mov    %ecx,-0x158(%rbp)
 10fc1f3:	jne    10fca7a <core.runtime.Runtime.submitSafeDestination+0xdea>
 10fc1f9:	jmp    10fc9be <core.runtime.Runtime.submitSafeDestination+0xd2e>
 10fc1fe:	mov    -0x98(%rbp),%rsi
 10fc205:	test   %rsi,%rsi
 10fc208:	je     10fc31a <core.runtime.Runtime.submitSafeDestination+0x68a>
 10fc20e:	lea    0x31ee(%r13),%rax
 10fc215:	mov    %rax,-0x78(%rbp)
 10fc219:	lea    0x3110(%r13),%rax
 10fc220:	mov    %rax,-0xa8(%rbp)
 10fc227:	lea    0x3118(%r13),%rax
 10fc22e:	mov    %rax,-0xa0(%rbp)
 10fc235:	cmpb   $0x0,-0x90(%rbp)
 10fc23c:	je     10fc4d3 <core.runtime.Runtime.submitSafeDestination+0x843>
 10fc242:	lea    0x140(%rsi),%rax
 10fc249:	mov    %rax,-0x90(%rbp)
 10fc250:	lea    0x164(%rsi),%r15
 10fc257:	lea    -0xed0(%rbp),%rbx
 10fc25e:	lea    -0x260(%rbp),%r14
 10fc265:	mov    0x140(%rsi),%r13d
 10fc26c:	mov    %rbx,%rdi
 10fc26f:	mov    %r14,%rdx
 10fc272:	vzeroupper
 10fc275:	call   10fba50 <journal.journal.Journal.reserveSingleProducer>
 10fc27a:	movzwl -0xe90(%rbp),%eax
 10fc281:	test   %eax,%eax
 10fc283:	je     10fc55d <core.runtime.Runtime.submitSafeDestination+0x8cd>
 10fc289:	cmp    $0x13b,%eax
 10fc28e:	jne    10fd3e9 <core.runtime.Runtime.submitSafeDestination+0x1759>
 10fc294:	mov    -0x60(%rbp),%rax
 10fc298:	movzbl 0x31ef(%rax),%eax
 10fc29f:	test   $0x3,%al
 10fc2a1:	jne    10fc590 <core.runtime.Runtime.submitSafeDestination+0x900>
 10fc2a7:	mov    $0x1,%al
 10fc2a9:	xchg   %al,(%r15)
 10fc2ac:	mov    -0x60(%rbp),%rax
 10fc2b0:	movzwl 0x31e8(%rax),%eax
 10fc2b7:	test   %ax,%ax
 10fc2ba:	jne    10fc97e <core.runtime.Runtime.submitSafeDestination+0xcee>
 10fc2c0:	mov    -0x78(%rbp),%rax
 10fc2c4:	movzbl (%rax),%eax
 10fc2c7:	test   %al,%al
 10fc2c9:	jne    10fc991 <core.runtime.Runtime.submitSafeDestination+0xd01>
 10fc2cf:	mov    -0xa8(%rbp),%rax
 10fc2d6:	mov    (%rax),%rdi
 10fc2d9:	mov    -0xa0(%rbp),%rax
 10fc2e0:	mov    (%rax),%rax
 10fc2e3:	mov    -0x90(%rbp),%rsi
 10fc2ea:	mov    %r13d,%edx
 10fc2ed:	call   *0x68(%rax)
 10fc2f0:	xor    %eax,%eax
 10fc2f2:	xchg   %al,(%r15)
 10fc2f5:	mov    -0x98(%rbp),%rsi
 10fc2fc:	jmp    10fc265 <core.runtime.Runtime.submitSafeDestination+0x5d5>
 10fc301:	movl   $0x134,(%r15)
 10fc308:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc30d:	mov    $0x90,%ax
 10fc311:	mov    %ax,(%r15)
 10fc315:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc31a:	mov    -0x180(%rbp),%rax
 10fc321:	mov    %rax,-0xad0(%rbp)
 10fc328:	vmovups -0x1c0(%rbp),%ymm0
 10fc330:	vmovups -0x1a0(%rbp),%ymm1
 10fc338:	vmovups %ymm1,-0xaf0(%rbp)
 10fc340:	vmovups %ymm0,-0xb10(%rbp)
 10fc348:	mov    %r10,-0xac8(%rbp)
 10fc34f:	mov    %r11,-0xac0(%rbp)
 10fc356:	mov    %r12,-0xab8(%rbp)
 10fc35d:	mov    %r9,-0xab0(%rbp)
 10fc364:	mov    %rcx,-0xaa8(%rbp)
 10fc36b:	mov    %r8,-0xaa0(%rbp)
 10fc372:	vmovups -0x200(%rbp),%ymm0
 10fc37a:	vmovups -0x1e0(%rbp),%ymm1
 10fc382:	vmovups %ymm0,-0xa98(%rbp)
 10fc38a:	vmovups %ymm1,-0xa78(%rbp)
 10fc392:	mov    %edi,-0xa58(%rbp)
 10fc398:	vmovups -0x123(%rbp),%xmm0
 10fc3a0:	vmovups %xmm0,-0xa47(%rbp)
 10fc3a8:	vmovaps -0x130(%rbp),%xmm0
 10fc3b0:	vmovups %xmm0,-0xa54(%rbp)
 10fc3b8:	movzbl -0x29(%rbp),%eax
 10fc3bc:	mov    %al,-0xa37(%rbp)
 10fc3c2:	movzwl -0x2c(%rbp),%eax
 10fc3c6:	mov    %ax,-0xa32(%rbp)
 10fc3cd:	mov    -0x30(%rbp),%eax
 10fc3d0:	mov    %eax,-0xa36(%rbp)
 10fc3d6:	lea    -0x174(%rbp),%rdi
 10fc3dd:	lea    -0xb10(%rbp),%rdx
 10fc3e4:	mov    %r13,%rsi
 10fc3e7:	mov    -0x88(%rbp),%rcx
 10fc3ee:	vzeroupper
 10fc3f1:	call   1100c80 <core.runtime.Runtime.submitSync>
 10fc3f6:	mov    -0x174(%rbp),%eax
 10fc3fc:	mov    %eax,(%r15)
 10fc3ff:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc404:	lea    -0xe88(%rbp),%rbx
 10fc40b:	lea    -0x150(%rbp),%r13
 10fc412:	lea    -0xbe0(%rbp),%r14
 10fc419:	mov    (%r15),%eax
 10fc41c:	mov    %eax,-0x168(%rbp)
 10fc422:	mov    %rbx,%rdi
 10fc425:	mov    %r13,%rdx
 10fc428:	vzeroupper
 10fc42b:	call   10fb7b0 <journal.journal.Journal.reserveWithSchema>
 10fc430:	movzwl -0xe48(%rbp),%eax
 10fc437:	test   %eax,%eax
 10fc439:	je     10fc4ba <core.runtime.Runtime.submitSafeDestination+0x82a>
 10fc43b:	mov    %r15,-0x158(%rbp)
 10fc442:	mov    -0x168(%rbp),%edx
 10fc448:	cmp    $0x13b,%eax
 10fc44d:	jne    10fd3e9 <core.runtime.Runtime.submitSafeDestination+0x1759>
 10fc453:	mov    -0x60(%rbp),%rax
 10fc457:	movzbl 0x31ef(%rax),%eax
 10fc45e:	test   $0x3,%al
 10fc460:	jne    10fc5c3 <core.runtime.Runtime.submitSafeDestination+0x933>
 10fc466:	mov    -0x60(%rbp),%rax
 10fc46a:	movzwl 0x31e8(%rax),%eax
 10fc471:	test   %ax,%ax
 10fc474:	jne    10fc985 <core.runtime.Runtime.submitSafeDestination+0xcf5>
 10fc47a:	mov    -0x78(%rbp),%rax
 10fc47e:	movzbl (%rax),%eax
 10fc481:	test   %al,%al
 10fc483:	jne    10fc973 <core.runtime.Runtime.submitSafeDestination+0xce3>
 10fc489:	mov    -0xa8(%rbp),%rax
 10fc490:	mov    (%rax),%rdi
 10fc493:	mov    -0xa0(%rbp),%rax
 10fc49a:	mov    (%rax),%rax
 10fc49d:	mov    -0x90(%rbp),%rsi
 10fc4a4:	call   *0x68(%rax)
 10fc4a7:	mov    -0x98(%rbp),%rsi
 10fc4ae:	mov    -0x158(%rbp),%r15
 10fc4b5:	jmp    10fc419 <core.runtime.Runtime.submitSafeDestination+0x789>
 10fc4ba:	mov    -0x40(%rbp),%rsi
 10fc4be:	mov    -0x38(%rbp),%rdi
 10fc4c2:	mov    -0x58(%rbp),%r8
 10fc4c6:	mov    -0x80(%rbp),%r9
 10fc4ca:	mov    -0x68(%rbp),%r10
 10fc4ce:	jmp    10fcbbc <core.runtime.Runtime.submitSafeDestination+0xf2c>
 10fc4d3:	lea    0x31c4(%r13),%r14
 10fc4da:	lea    -0xf18(%rbp),%rbx
 10fc4e1:	mov    (%r14),%r13d
 10fc4e4:	mov    %rbx,%rdi
 10fc4e7:	vzeroupper
 10fc4ea:	call   10fb590 <journal.journal.Journal.reserve>
 10fc4ef:	movzwl -0xed8(%rbp),%eax
 10fc4f6:	test   %eax,%eax
 10fc4f8:	je     10fc55d <core.runtime.Runtime.submitSafeDestination+0x8cd>
 10fc4fa:	cmp    $0x13b,%eax
 10fc4ff:	jne    10fd3e9 <core.runtime.Runtime.submitSafeDestination+0x1759>
 10fc505:	mov    -0x60(%rbp),%rax
 10fc509:	movzbl 0x31ef(%rax),%eax
 10fc510:	test   $0x3,%al
 10fc512:	jne    10fc590 <core.runtime.Runtime.submitSafeDestination+0x900>
 10fc514:	mov    -0x60(%rbp),%rax
 10fc518:	movzwl 0x31e8(%rax),%eax
 10fc51f:	test   %ax,%ax
 10fc522:	jne    10fc985 <core.runtime.Runtime.submitSafeDestination+0xcf5>
 10fc528:	mov    -0x78(%rbp),%rax
 10fc52c:	movzbl (%rax),%eax
 10fc52f:	test   %al,%al
 10fc531:	jne    10fc973 <core.runtime.Runtime.submitSafeDestination+0xce3>
 10fc537:	mov    -0xa8(%rbp),%rax
 10fc53e:	mov    (%rax),%rdi
 10fc541:	mov    -0xa0(%rbp),%rax
 10fc548:	mov    (%rax),%rax
 10fc54b:	mov    %r14,%rsi
 10fc54e:	mov    %r13d,%edx
 10fc551:	call   *0x68(%rax)
 10fc554:	mov    -0x98(%rbp),%rsi
 10fc55b:	jmp    10fc4e1 <core.runtime.Runtime.submitSafeDestination+0x851>
 10fc55d:	mov    $0x1066d08,%r14d
 10fc563:	mov    $0x1066dc8,%ecx
 10fc568:	mov    -0x40(%rbp),%rsi
 10fc56c:	mov    -0x38(%rbp),%rdi
 10fc570:	mov    -0x58(%rbp),%r8
 10fc574:	mov    -0x80(%rbp),%r9
 10fc578:	mov    -0x68(%rbp),%r10
 10fc57c:	mov    -0xf8(%rbp),%rax
 10fc583:	jmp    10fcbca <core.runtime.Runtime.submitSafeDestination+0xf3a>
 10fc588:	mov    %ax,(%rbx)
 10fc58b:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc590:	and    $0x3,%eax
 10fc593:	cmp    $0x1,%eax
 10fc596:	mov    -0x70(%rbp),%rax
 10fc59a:	mov    -0x40(%rbp),%rdi
 10fc59e:	mov    -0x38(%rbp),%r8
 10fc5a2:	mov    -0x58(%rbp),%r9
 10fc5a6:	mov    -0x68(%rbp),%r10
 10fc5aa:	je     10fd4c8 <core.runtime.Runtime.submitSafeDestination+0x1838>
 10fc5b0:	mov    $0x1066d08,%edx
 10fc5b5:	mov    $0x1066dc8,%eax
 10fc5ba:	mov    %rax,-0x160(%rbp)
 10fc5c1:	jmp    10fc5ea <core.runtime.Runtime.submitSafeDestination+0x95a>
 10fc5c3:	and    $0x3,%eax
 10fc5c6:	cmp    $0x1,%eax
 10fc5c9:	mov    -0x70(%rbp),%rax
 10fc5cd:	mov    -0x40(%rbp),%rdi
 10fc5d1:	mov    -0x38(%rbp),%r8
 10fc5d5:	mov    -0x58(%rbp),%r9
 10fc5d9:	mov    -0x68(%rbp),%r10
 10fc5dd:	je     10fd4c8 <core.runtime.Runtime.submitSafeDestination+0x1838>
 10fc5e3:	lea    -0xbe0(%rbp),%rdx
 10fc5ea:	mov    -0x160(%rbp),%rax
 10fc5f1:	cmpb   $0x0,(%rax)
 10fc5f4:	je     10fc75b <core.runtime.Runtime.submitSafeDestination+0xacb>
 10fc5fa:	vmovups 0xa0(%rdx),%ymm0
 10fc602:	vmovups %ymm0,-0xda0(%rbp)
 10fc60a:	vmovups 0x80(%rdx),%ymm0
 10fc612:	vmovups %ymm0,-0xdc0(%rbp)
 10fc61a:	vmovups (%rdx),%ymm0
 10fc61e:	vmovups 0x20(%rdx),%ymm1
 10fc623:	vmovups 0x40(%rdx),%ymm2
 10fc628:	vmovups 0x60(%rdx),%ymm3
 10fc62d:	vmovups %ymm3,-0xde0(%rbp)
 10fc635:	vmovups %ymm2,-0xe00(%rbp)
 10fc63d:	vmovups %ymm1,-0xe20(%rbp)
 10fc645:	vmovups %ymm0,-0xe40(%rbp)
 10fc64d:	mov    -0xf8(%rbp),%rax
 10fc654:	cmpb   $0x0,0x50(%rax)
 10fc658:	je     10fc77e <core.runtime.Runtime.submitSafeDestination+0xaee>
 10fc65e:	mov    0x48(%rax),%rcx
 10fc662:	mov    -0x180(%rbp),%rax
 10fc669:	mov    %rax,-0x4b0(%rbp)
 10fc670:	vmovups -0x1c0(%rbp),%ymm0
 10fc678:	vmovups -0x1a0(%rbp),%ymm1
 10fc680:	vmovups %ymm1,-0x4d0(%rbp)
 10fc688:	vmovups %ymm0,-0x4f0(%rbp)
 10fc690:	mov    %r10,-0x4a8(%rbp)
 10fc697:	mov    -0x100(%rbp),%r13
 10fc69e:	mov    %r13,-0x4a0(%rbp)
 10fc6a5:	mov    %r12,-0x498(%rbp)
 10fc6ac:	mov    -0x80(%rbp),%r15
 10fc6b0:	mov    %r15,-0x490(%rbp)
 10fc6b7:	mov    %r9,-0x488(%rbp)
 10fc6be:	mov    %r8,-0x480(%rbp)
 10fc6c5:	vmovups -0x200(%rbp),%ymm0
 10fc6cd:	vmovups -0x1e0(%rbp),%ymm1
 10fc6d5:	vmovups %ymm0,-0x478(%rbp)
 10fc6dd:	vmovups %ymm1,-0x458(%rbp)
 10fc6e5:	mov    %edi,-0x438(%rbp)
 10fc6eb:	vmovaps -0x130(%rbp),%xmm0
 10fc6f3:	vmovups %xmm0,-0x434(%rbp)
 10fc6fb:	vmovups -0x123(%rbp),%xmm0
 10fc703:	vmovups %xmm0,-0x427(%rbp)
 10fc70b:	movzbl -0x29(%rbp),%ebx
 10fc70f:	mov    %bl,-0x417(%rbp)
 10fc715:	mov    -0x30(%rbp),%eax
 10fc718:	mov    %eax,-0x416(%rbp)
 10fc71e:	movzwl -0x2c(%rbp),%eax
 10fc722:	mov    %ax,-0x412(%rbp)
 10fc729:	lea    -0x270(%rbp),%rdi
 10fc730:	lea    -0x4f0(%rbp),%rsi
 10fc737:	vzeroupper
 10fc73a:	call   110cdb0 <core.reference_encoding.sizeMeasured>
 10fc73f:	mov    -0x68(%rbp),%r10
 10fc743:	mov    -0x58(%rbp),%r9
 10fc747:	mov    -0x38(%rbp),%r8
 10fc74b:	mov    -0x40(%rbp),%rdi
 10fc74f:	movzwl -0x268(%rbp),%eax
 10fc756:	jmp    10fc879 <core.runtime.Runtime.submitSafeDestination+0xbe9>
 10fc75b:	movzbl -0x29(%rbp),%ebx
 10fc75f:	mov    -0x50(%rbp),%r14
 10fc763:	mov    -0x60(%rbp),%rsi
 10fc767:	mov    -0x88(%rbp),%rcx
 10fc76e:	mov    -0x80(%rbp),%r15
 10fc772:	mov    -0x100(%rbp),%r13
 10fc779:	jmp    10fc891 <core.runtime.Runtime.submitSafeDestination+0xc01>
 10fc77e:	mov    -0x180(%rbp),%rax
 10fc785:	mov    %rax,-0x590(%rbp)
 10fc78c:	vmovups -0x1c0(%rbp),%ymm0
 10fc794:	vmovups -0x1a0(%rbp),%ymm1
 10fc79c:	vmovups %ymm1,-0x5b0(%rbp)
 10fc7a4:	vmovups %ymm0,-0x5d0(%rbp)
 10fc7ac:	mov    %r10,-0x588(%rbp)
 10fc7b3:	mov    -0x100(%rbp),%r13
 10fc7ba:	mov    %r13,-0x580(%rbp)
 10fc7c1:	mov    %r12,-0x578(%rbp)
 10fc7c8:	mov    -0x80(%rbp),%r15
 10fc7cc:	mov    %r15,-0x570(%rbp)
 10fc7d3:	mov    %r9,-0x568(%rbp)
 10fc7da:	mov    %r8,-0x560(%rbp)
 10fc7e1:	vmovups -0x200(%rbp),%ymm0
 10fc7e9:	vmovups -0x1e0(%rbp),%ymm1
 10fc7f1:	vmovups %ymm0,-0x558(%rbp)
 10fc7f9:	vmovups %ymm1,-0x538(%rbp)
 10fc801:	mov    %edi,-0x518(%rbp)
 10fc807:	vmovups -0x123(%rbp),%xmm0
 10fc80f:	vmovups %xmm0,-0x507(%rbp)
 10fc817:	vmovaps -0x130(%rbp),%xmm0
 10fc81f:	vmovups %xmm0,-0x514(%rbp)
 10fc827:	movzbl -0x29(%rbp),%ebx
 10fc82b:	mov    %bl,-0x4f7(%rbp)
 10fc831:	mov    -0x30(%rbp),%eax
 10fc834:	mov    %eax,-0x4f6(%rbp)
 10fc83a:	movzwl -0x2c(%rbp),%eax
 10fc83e:	mov    %ax,-0x4f2(%rbp)
 10fc845:	lea    -0x280(%rbp),%rdi
 10fc84c:	lea    -0x5d0(%rbp),%rsi
 10fc853:	lea    -0xe40(%rbp),%rdx
 10fc85a:	vzeroupper
 10fc85d:	call   1100f10 <core.schema_codec.encodedReferenceSize>
 10fc862:	mov    -0x68(%rbp),%r10
 10fc866:	mov    -0x58(%rbp),%r9
 10fc86a:	mov    -0x38(%rbp),%r8
 10fc86e:	mov    -0x40(%rbp),%rdi
 10fc872:	movzwl -0x278(%rbp),%eax
 10fc879:	test   %ax,%ax
 10fc87c:	mov    -0x50(%rbp),%r14
 10fc880:	mov    -0x60(%rbp),%rsi
 10fc884:	mov    -0x88(%rbp),%rcx
 10fc88b:	jne    10fc9b0 <core.runtime.Runtime.submitSafeDestination+0xd20>
 10fc891:	mov    -0x180(%rbp),%rax
 10fc898:	mov    %rax,-0x670(%rbp)
 10fc89f:	vmovups -0x1c0(%rbp),%ymm0
 10fc8a7:	vmovups -0x1a0(%rbp),%ymm1
 10fc8af:	vmovups %ymm1,-0x690(%rbp)
 10fc8b7:	vmovups %ymm0,-0x6b0(%rbp)
 10fc8bf:	vmovups -0x200(%rbp),%ymm0
 10fc8c7:	vmovups -0x1e0(%rbp),%ymm1
 10fc8cf:	vmovups %ymm0,-0x638(%rbp)
 10fc8d7:	vmovups %ymm1,-0x618(%rbp)
 10fc8df:	vmovaps -0x130(%rbp),%xmm0
 10fc8e7:	vmovups %xmm0,-0x5f4(%rbp)
 10fc8ef:	vmovups -0x123(%rbp),%xmm0
 10fc8f7:	vmovups %xmm0,-0x5e7(%rbp)
 10fc8ff:	mov    -0x30(%rbp),%eax
 10fc902:	mov    %eax,-0x5d6(%rbp)
 10fc908:	movzwl -0x2c(%rbp),%eax
 10fc90c:	mov    %ax,-0x5d2(%rbp)
 10fc913:	or     $0x80000000,%edi
 10fc919:	mov    %r10,-0x668(%rbp)
 10fc920:	mov    %r13,-0x660(%rbp)
 10fc927:	mov    %r12,-0x658(%rbp)
 10fc92e:	mov    %r15,-0x650(%rbp)
 10fc935:	mov    %r9,-0x648(%rbp)
 10fc93c:	mov    %r8,-0x640(%rbp)
 10fc943:	mov    %edi,-0x5f8(%rbp)
 10fc949:	mov    %bl,-0x5d7(%rbp)
 10fc94f:	lea    -0x170(%rbp),%rdi
 10fc956:	lea    -0x6b0(%rbp),%rdx
 10fc95d:	vzeroupper
 10fc960:	call   1100c80 <core.runtime.Runtime.submitSync>
 10fc965:	mov    -0x170(%rbp),%eax
 10fc96b:	mov    %eax,(%r14)
 10fc96e:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc973:	mov    -0x70(%rbp),%rax
 10fc977:	lock incq 0x68(%rax)
 10fc97c:	jmp    10fc9a1 <core.runtime.Runtime.submitSafeDestination+0xd11>
 10fc97e:	mov    %r15,%rbx
 10fc981:	xor    %ecx,%ecx
 10fc983:	xchg   %cl,(%rbx)
 10fc985:	mov    -0x50(%rbp),%rcx
 10fc989:	mov    %ax,(%rcx)
 10fc98c:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc991:	mov    -0x70(%rbp),%rcx
 10fc995:	mov    %r15,%rbx
 10fc998:	lock incq 0x68(%rcx)
 10fc99d:	xor    %eax,%eax
 10fc99f:	xchg   %al,(%rbx)
 10fc9a1:	mov    -0x50(%rbp),%rcx
 10fc9a5:	mov    -0x8a83b(%rip),%eax        # 1072170 <__anon_33660>
 10fc9ab:	jmp    10fc090 <core.runtime.Runtime.submitSafeDestination+0x400>
 10fc9b0:	mov    %ax,(%r14)
 10fc9b4:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fc9b9:	mov    %r13,%r14
 10fc9bc:	jmp    10fc9c5 <core.runtime.Runtime.submitSafeDestination+0xd35>
 10fc9be:	mov    %r13,%r14
 10fc9c1:	mov    $0x90,%ax
 10fc9c5:	mov    %ax,-0x2f0(%rbp)
 10fc9cc:	movzwl %ax,%ecx
 10fc9cf:	cmp    $0x13b,%ecx
 10fc9d5:	mov    -0x40(%rbp),%rdi
 10fc9d9:	mov    -0x38(%rbp),%r8
 10fc9dd:	mov    -0x58(%rbp),%r9
 10fc9e1:	mov    -0x68(%rbp),%r10
 10fc9e5:	jne    10fd3e9 <core.runtime.Runtime.submitSafeDestination+0x1759>
 10fc9eb:	mov    -0x60(%rbp),%rcx
 10fc9ef:	movzbl 0x31ef(%rcx),%eax
 10fc9f6:	test   $0x3,%al
 10fc9f8:	jne    10fd4b8 <core.runtime.Runtime.submitSafeDestination+0x1828>
 10fc9fe:	mov    $0x1,%al
 10fca00:	xchg   %al,(%rbx)
 10fca02:	movzwl 0x31e8(%rcx),%eax
 10fca09:	test   %ax,%ax
 10fca0c:	mov    -0x70(%rbp),%rcx
 10fca10:	jne    10fc981 <core.runtime.Runtime.submitSafeDestination+0xcf1>
 10fca16:	mov    -0x78(%rbp),%rax
 10fca1a:	movzbl (%rax),%eax
 10fca1d:	test   %al,%al
 10fca1f:	jne    10fc998 <core.runtime.Runtime.submitSafeDestination+0xd08>
 10fca25:	mov    -0xa8(%rbp),%rax
 10fca2c:	mov    (%rax),%rdi
 10fca2f:	mov    -0xa0(%rbp),%rax
 10fca36:	mov    (%rax),%rax
 10fca39:	mov    -0x90(%rbp),%rsi
 10fca40:	mov    -0x158(%rbp),%edx
 10fca46:	vzeroupper
 10fca49:	call   *0x68(%rax)
 10fca4c:	mov    -0x98(%rbp),%rsi
 10fca53:	xor    %eax,%eax
 10fca55:	xchg   %al,(%rbx)
 10fca57:	lea    -0x150(%rbp),%rax
 10fca5e:	mov    %r14,%r13
 10fca61:	mov    0x140(%rsi),%ecx
 10fca67:	cmpb   $0x0,0x288(%rsi)
 10fca6e:	mov    %ecx,-0x158(%rbp)
 10fca74:	je     10fc9be <core.runtime.Runtime.submitSafeDestination+0xd2e>
 10fca7a:	mov    -0x150(%rbp),%ecx
 10fca80:	mov    %ecx,-0x16c(%rbp)
 10fca86:	movzwl -0x14c(%rbp),%r15d
 10fca8e:	mov    -0x168(%rbp),%rdi
 10fca95:	mov    %rax,%rsi
 10fca98:	vzeroupper
 10fca9b:	call   1132b10 <journal.schema.Registry.validateReady>
 10fcaa0:	test   %ax,%ax
 10fcaa3:	jne    10fc9b9 <core.runtime.Runtime.submitSafeDestination+0xd29>
 10fcaa9:	mov    %r13,%r14
 10fcaac:	mov    %r13,%rdi
 10fcaaf:	mov    -0x98(%rbp),%r13
 10fcab6:	mov    %r13,%rsi
 10fcab9:	lea    -0x260(%rbp),%rdx
 10fcac0:	call   10fba50 <journal.journal.Journal.reserveSingleProducer>
 10fcac5:	movzwl -0x208(%rbp),%eax
 10fcacc:	test   %ax,%ax
 10fcacf:	jne    10fc9c5 <core.runtime.Runtime.submitSafeDestination+0xd35>
 10fcad5:	vmovups -0x238(%rbp),%xmm0
 10fcadd:	mov    -0x20c(%rbp),%eax
 10fcae3:	cmpl   $0x1,0x2f0(%r13)
 10fcaeb:	mov    -0x40(%rbp),%rsi
 10fcaef:	mov    -0x38(%rbp),%rdi
 10fcaf3:	mov    -0x58(%rbp),%r8
 10fcaf7:	mov    -0x80(%rbp),%r9
 10fcafb:	mov    -0x68(%rbp),%r10
 10fcaff:	je     10fcb4a <core.runtime.Runtime.submitSafeDestination+0xeba>
 10fcb01:	mov    0x1a0(%r13),%rcx
 10fcb08:	mov    0x200(%r13),%rdx
 10fcb0f:	imul   -0x238(%rbp),%rdx
 10fcb17:	movw   $0x0,0x1026(%rcx,%rdx,1)
 10fcb21:	mov    -0x16c(%rbp),%r11d
 10fcb28:	mov    %r11d,0x1020(%rcx,%rdx,1)
 10fcb30:	mov    %r15w,0x1024(%rcx,%rdx,1)
 10fcb39:	vmovups -0x14a(%rbp),%xmm1
 10fcb41:	vmovups %xmm1,0x1028(%rcx,%rdx,1)
 10fcb4a:	movw   $0x0,-0x2f0(%rbp)
 10fcb53:	vmovups -0x248(%rbp),%xmm1
 10fcb5b:	vmovaps %xmm1,-0x330(%rbp)
 10fcb63:	vmovaps %xmm0,-0x320(%rbp)
 10fcb6b:	mov    -0x140(%rbp),%rcx
 10fcb72:	lea    -0x310(%rbp),%r11
 10fcb79:	mov    %rcx,0x10(%r11)
 10fcb7d:	vmovaps -0x150(%rbp),%xmm0
 10fcb85:	vmovups %xmm0,(%r11)
 10fcb8a:	movb   $0x1,-0x2f8(%rbp)
 10fcb91:	lea    -0x20f(%rbp),%rdx
 10fcb98:	movzbl 0x2(%rdx),%ecx
 10fcb9c:	mov    %cl,0x1b(%r11)
 10fcba0:	movzwl (%rdx),%ecx
 10fcba3:	mov    %cx,0x19(%r11)
 10fcba8:	mov    %eax,-0x2f4(%rbp)
 10fcbae:	lea    -0x330(%rbp),%rbx
 10fcbb5:	lea    -0xbe0(%rbp),%r14
 10fcbbc:	mov    -0xf8(%rbp),%rax
 10fcbc3:	lea    -0xb20(%rbp),%rcx
 10fcbca:	vmovups (%rbx),%ymm0
 10fcbce:	vmovups %ymm0,-0xf0(%rbp)
 10fcbd6:	vmovups 0x20(%rbx),%ymm0
 10fcbdb:	vmovups %ymm0,-0xd0(%rbp)
 10fcbe3:	mov    -0xe8(%rbp),%r11
 10fcbea:	cmpb   $0x0,(%rcx)
 10fcbed:	mov    %r11,-0x38(%rbp)
 10fcbf1:	je     10fcd87 <core.runtime.Runtime.submitSafeDestination+0x10f7>
 10fcbf7:	vmovups 0xa0(%r14),%ymm0
 10fcc00:	vmovups %ymm0,-0xce0(%rbp)
 10fcc08:	vmovups 0x80(%r14),%ymm0
 10fcc11:	vmovups %ymm0,-0xd00(%rbp)
 10fcc19:	vmovups (%r14),%ymm0
 10fcc1e:	vmovups 0x20(%r14),%ymm1
 10fcc24:	vmovups 0x40(%r14),%ymm2
 10fcc2a:	vmovups 0x60(%r14),%ymm3
 10fcc30:	vmovups %ymm3,-0xd20(%rbp)
 10fcc38:	vmovups %ymm2,-0xd40(%rbp)
 10fcc40:	vmovups %ymm1,-0xd60(%rbp)
 10fcc48:	vmovups %ymm0,-0xd80(%rbp)
 10fcc50:	cmpb   $0x0,0x50(%rax)
 10fcc54:	je     10fceb6 <core.runtime.Runtime.submitSafeDestination+0x1226>
 10fcc5a:	mov    0x48(%rax),%rcx
 10fcc5e:	mov    -0x180(%rbp),%rax
 10fcc65:	mov    %rax,-0x750(%rbp)
 10fcc6c:	vmovups -0x1c0(%rbp),%ymm0
 10fcc74:	vmovups -0x1a0(%rbp),%ymm1
 10fcc7c:	vmovups %ymm1,-0x770(%rbp)
 10fcc84:	vmovups %ymm0,-0x790(%rbp)
 10fcc8c:	mov    %r10,-0x748(%rbp)
 10fcc93:	mov    %r11,-0x740(%rbp)
 10fcc9a:	mov    %r12,-0x738(%rbp)
 10fcca1:	mov    %r9,-0x730(%rbp)
 10fcca8:	mov    %r8,-0x728(%rbp)
 10fccaf:	mov    %rdi,-0x720(%rbp)
 10fccb6:	vmovups -0x200(%rbp),%ymm0
 10fccbe:	vmovups -0x1e0(%rbp),%ymm1
 10fccc6:	vmovups %ymm0,-0x718(%rbp)
 10fccce:	vmovups %ymm1,-0x6f8(%rbp)
 10fccd6:	lea    -0x288(%rbp),%rbx
 10fccdd:	mov    %esi,-0x6d8(%rbp)
 10fcce3:	vmovaps -0x130(%rbp),%xmm0
 10fcceb:	vmovups %xmm0,-0x6d4(%rbp)
 10fccf3:	lea    -0x290(%rbp),%r14
 10fccfa:	vmovups -0x123(%rbp),%xmm0
 10fcd02:	vmovups %xmm0,-0x6c7(%rbp)
 10fcd0a:	movzbl -0x29(%rbp),%eax
 10fcd0e:	mov    %al,-0x6b7(%rbp)
 10fcd14:	movzwl -0x2c(%rbp),%eax
 10fcd18:	mov    %ax,-0x6b2(%rbp)
 10fcd1f:	mov    -0x30(%rbp),%eax
 10fcd22:	mov    %eax,-0x6b6(%rbp)
 10fcd28:	movzbl -0xb4(%rbp),%r15d
 10fcd30:	mov    -0xf0(%rbp),%r12
 10fcd37:	mov    -0xe0(%rbp),%r13
 10fcd3e:	mov    0x200(%r12),%rax
 10fcd46:	imul   %r13,%rax
 10fcd4a:	mov    0x1a0(%r12),%rdx
 10fcd52:	mov    0x1f8(%r12),%r9
 10fcd5a:	lea    (%rdx,%rax,1),%r8
 10fcd5e:	add    $0x1040,%r8
 10fcd65:	lea    -0x298(%rbp),%rdi
 10fcd6c:	lea    -0x790(%rbp),%rsi
 10fcd73:	lea    -0xd80(%rbp),%rdx
 10fcd7a:	vzeroupper
 10fcd7d:	call   10fe6e0 <core.reference_encoding.writeMeasured>
 10fcd82:	jmp    10fd0fa <core.runtime.Runtime.submitSafeDestination+0x146a>
 10fcd87:	cmpb   $0x0,0x50(%rax)
 10fcd8b:	je     10fcfde <core.runtime.Runtime.submitSafeDestination+0x134e>
 10fcd91:	mov    0x48(%rax),%rdx
 10fcd95:	mov    -0x180(%rbp),%rax
 10fcd9c:	mov    %rax,-0x910(%rbp)
 10fcda3:	vmovups -0x1c0(%rbp),%ymm0
 10fcdab:	vmovups -0x1a0(%rbp),%ymm1
 10fcdb3:	vmovups %ymm1,-0x930(%rbp)
 10fcdbb:	vmovups %ymm0,-0x950(%rbp)
 10fcdc3:	mov    %r10,-0x908(%rbp)
 10fcdca:	mov    %r11,-0x900(%rbp)
 10fcdd1:	mov    %r12,-0x8f8(%rbp)
 10fcdd8:	mov    %r9,-0x8f0(%rbp)
 10fcddf:	mov    %r8,-0x8e8(%rbp)
 10fcde6:	mov    %rdi,-0x8e0(%rbp)
 10fcded:	vmovups -0x200(%rbp),%ymm0
 10fcdf5:	vmovups -0x1e0(%rbp),%ymm1
 10fcdfd:	vmovups %ymm0,-0x8d8(%rbp)
 10fce05:	vmovups %ymm1,-0x8b8(%rbp)
 10fce0d:	lea    -0x2b8(%rbp),%rbx
 10fce14:	mov    %esi,-0x898(%rbp)
 10fce1a:	vmovaps -0x130(%rbp),%xmm0
 10fce22:	vmovups %xmm0,-0x894(%rbp)
 10fce2a:	lea    -0x2c0(%rbp),%r14
 10fce31:	vmovups -0x123(%rbp),%xmm0
 10fce39:	vmovups %xmm0,-0x887(%rbp)
 10fce41:	movzbl -0x29(%rbp),%eax
 10fce45:	mov    %al,-0x877(%rbp)
 10fce4b:	movzwl -0x2c(%rbp),%eax
 10fce4f:	mov    %ax,-0x872(%rbp)
 10fce56:	mov    -0x30(%rbp),%eax
 10fce59:	mov    %eax,-0x876(%rbp)
 10fce5f:	movzbl -0xb4(%rbp),%r15d
 10fce67:	mov    -0xf0(%rbp),%r12
 10fce6e:	mov    -0xe0(%rbp),%r13
 10fce75:	mov    0x200(%r12),%rax
 10fce7d:	imul   %r13,%rax
 10fce81:	mov    0x1a0(%r12),%rcx
 10fce89:	mov    0x1f8(%r12),%r8
 10fce91:	add    %rax,%rcx
 10fce94:	add    $0x1040,%rcx
 10fce9b:	lea    -0x2c8(%rbp),%rdi
 10fcea2:	lea    -0x950(%rbp),%rsi
 10fcea9:	vzeroupper
 10fceac:	call   10fdfb0 <core.codec.encodeSized>
 10fceb1:	jmp    10fd0fa <core.runtime.Runtime.submitSafeDestination+0x146a>
 10fceb6:	mov    -0x180(%rbp),%rax
 10fcebd:	mov    %rax,-0x830(%rbp)
 10fcec4:	vmovups -0x1c0(%rbp),%ymm0
 10fcecc:	vmovups -0x1a0(%rbp),%ymm1
 10fced4:	vmovups %ymm1,-0x850(%rbp)
 10fcedc:	vmovups %ymm0,-0x870(%rbp)
 10fcee4:	mov    %r10,-0x828(%rbp)
 10fceeb:	mov    %r11,-0x820(%rbp)
 10fcef2:	mov    %r12,-0x818(%rbp)
 10fcef9:	mov    %r9,-0x810(%rbp)
 10fcf00:	mov    %r8,-0x808(%rbp)
 10fcf07:	mov    %rdi,-0x800(%rbp)
 10fcf0e:	vmovups -0x200(%rbp),%ymm0
 10fcf16:	vmovups -0x1e0(%rbp),%ymm1
 10fcf1e:	vmovups %ymm0,-0x7f8(%rbp)
 10fcf26:	vmovups %ymm1,-0x7d8(%rbp)
 10fcf2e:	lea    -0x2a0(%rbp),%rbx
 10fcf35:	mov    %esi,-0x7b8(%rbp)
 10fcf3b:	vmovups -0x123(%rbp),%xmm0
 10fcf43:	vmovups %xmm0,-0x7a7(%rbp)
 10fcf4b:	lea    -0x2a8(%rbp),%r14
 10fcf52:	vmovaps -0x130(%rbp),%xmm0
 10fcf5a:	vmovups %xmm0,-0x7b4(%rbp)
 10fcf62:	movzbl -0x29(%rbp),%eax
 10fcf66:	mov    %al,-0x797(%rbp)
 10fcf6c:	movzwl -0x2c(%rbp),%eax
 10fcf70:	mov    %ax,-0x792(%rbp)
 10fcf77:	mov    -0x30(%rbp),%eax
 10fcf7a:	mov    %eax,-0x796(%rbp)
 10fcf80:	movzbl -0xb4(%rbp),%r15d
 10fcf88:	mov    -0xf0(%rbp),%r12
 10fcf8f:	mov    -0xe0(%rbp),%r13
 10fcf96:	mov    0x200(%r12),%rax
 10fcf9e:	imul   %r13,%rax
 10fcfa2:	mov    0x1a0(%r12),%rcx
 10fcfaa:	mov    0x1f8(%r12),%r8
 10fcfb2:	add    %rax,%rcx
 10fcfb5:	add    $0x1040,%rcx
 10fcfbc:	lea    -0x2b0(%rbp),%rdi
 10fcfc3:	lea    -0x870(%rbp),%rsi
 10fcfca:	lea    -0xd80(%rbp),%rdx
 10fcfd1:	vzeroupper
 10fcfd4:	call   10fe660 <core.schema_codec.encodeReference>
 10fcfd9:	jmp    10fd0fa <core.runtime.Runtime.submitSafeDestination+0x146a>
 10fcfde:	mov    -0x180(%rbp),%rax
 10fcfe5:	mov    %rax,-0x9f0(%rbp)
 10fcfec:	vmovups -0x1c0(%rbp),%ymm0
 10fcff4:	vmovups -0x1a0(%rbp),%ymm1
 10fcffc:	vmovups %ymm1,-0xa10(%rbp)
 10fd004:	vmovups %ymm0,-0xa30(%rbp)
 10fd00c:	mov    %r10,-0x9e8(%rbp)
 10fd013:	mov    %r11,-0x9e0(%rbp)
 10fd01a:	mov    %r12,-0x9d8(%rbp)
 10fd021:	mov    %r9,-0x9d0(%rbp)
 10fd028:	mov    %r8,-0x9c8(%rbp)
 10fd02f:	mov    %rdi,-0x9c0(%rbp)
 10fd036:	vmovups -0x200(%rbp),%ymm0
 10fd03e:	vmovups -0x1e0(%rbp),%ymm1
 10fd046:	vmovups %ymm0,-0x9b8(%rbp)
 10fd04e:	vmovups %ymm1,-0x998(%rbp)
 10fd056:	lea    -0x2d0(%rbp),%rbx
 10fd05d:	mov    %esi,-0x978(%rbp)
 10fd063:	vmovups -0x123(%rbp),%xmm0
 10fd06b:	vmovups %xmm0,-0x967(%rbp)
 10fd073:	lea    -0x2d8(%rbp),%r14
 10fd07a:	vmovaps -0x130(%rbp),%xmm0
 10fd082:	vmovups %xmm0,-0x974(%rbp)
 10fd08a:	movzbl -0x29(%rbp),%eax
 10fd08e:	mov    %al,-0x957(%rbp)
 10fd094:	movzwl -0x2c(%rbp),%eax
 10fd098:	mov    %ax,-0x952(%rbp)
 10fd09f:	mov    -0x30(%rbp),%eax
 10fd0a2:	mov    %eax,-0x956(%rbp)
 10fd0a8:	movzbl -0xb4(%rbp),%r15d
 10fd0b0:	mov    -0xf0(%rbp),%r12
 10fd0b7:	mov    -0xe0(%rbp),%r13
 10fd0be:	mov    0x200(%r12),%rax
 10fd0c6:	imul   %r13,%rax
 10fd0ca:	mov    0x1a0(%r12),%rdx
 10fd0d2:	mov    0x1f8(%r12),%rcx
 10fd0da:	add    %rax,%rdx
 10fd0dd:	add    $0x1040,%rdx
 10fd0e4:	lea    -0x2e0(%rbp),%rdi
 10fd0eb:	lea    -0xa30(%rbp),%rsi
 10fd0f2:	vzeroupper
 10fd0f5:	call   10fdf30 <core.codec.encode>
 10fd0fa:	movzwl (%rbx),%ebx
 10fd0fd:	test   %ebx,%ebx
 10fd0ff:	je     10fd193 <core.runtime.Runtime.submitSafeDestination+0x1503>
 10fd105:	test   $0x1,%r15b
 10fd109:	jne    10fd2c6 <core.runtime.Runtime.submitSafeDestination+0x1636>
 10fd10f:	mov    -0xd8(%rbp),%rax
 10fd116:	test   %rax,%rax
 10fd119:	je     10fd26f <core.runtime.Runtime.submitSafeDestination+0x15df>
 10fd11f:	testb  $0x1,0x2fd(%r12)
 10fd128:	je     10fd2c6 <core.runtime.Runtime.submitSafeDestination+0x1636>
 10fd12e:	mov    0x150(%r12),%rcx
 10fd136:	mov    %rcx,%rdx
 10fd139:	shr    $0x2,%rdx
 10fd13d:	xor    %rdx,%rax
 10fd140:	and    $0x3,%ecx
 10fd143:	or     %rax,%rcx
 10fd146:	jne    10fd2c6 <core.runtime.Runtime.submitSafeDestination+0x1636>
 10fd14c:	mov    %fs:0xfffffffffffbb5a8,%rax
 10fd155:	test   %rax,%rax
 10fd158:	je     10fd2c6 <core.runtime.Runtime.submitSafeDestination+0x1636>
 10fd15e:	mov    0x148(%r12),%rcx
 10fd166:	cmp    %rax,%rcx
 10fd169:	jne    10fd2c6 <core.runtime.Runtime.submitSafeDestination+0x1636>
 10fd16f:	mov    0x160(%r12),%edx
 10fd177:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd180:	jne    10fd3f5 <core.runtime.Runtime.submitSafeDestination+0x1765>
 10fd186:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd18e:	jmp    10fd40d <core.runtime.Runtime.submitSafeDestination+0x177d>
 10fd193:	mov    -0x40(%rbp),%rdi
 10fd197:	test   %edi,%edi
 10fd199:	je     10fd1b2 <core.runtime.Runtime.submitSafeDestination+0x1522>
 10fd19b:	mov    %rdi,%rax
 10fd19e:	shl    $0x6,%rax
 10fd1a2:	mov    -0x88(%rbp),%rcx
 10fd1a9:	add    %rcx,%rax
 10fd1ac:	add    $0xffffffffffffffc0,%rax
 10fd1b0:	jmp    10fd1bf <core.runtime.Runtime.submitSafeDestination+0x152f>
 10fd1b2:	mov    -0x88(%rbp),%rax
 10fd1b9:	add    $0x9810,%rax
 10fd1bf:	mov    (%r14),%r12
 10fd1c2:	lock incq (%rax)
 10fd1c6:	mov    $0x13c,%bx
 10fd1ca:	cmpb   $0x0,-0xb4(%rbp)
 10fd1d1:	jne    10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd1d7:	mov    -0xd8(%rbp),%rcx
 10fd1de:	test   %rcx,%rcx
 10fd1e1:	je     10fd4f8 <core.runtime.Runtime.submitSafeDestination+0x1868>
 10fd1e7:	mov    -0xf0(%rbp),%rax
 10fd1ee:	mov    $0x92,%bx
 10fd1f2:	testb  $0x1,0x2fd(%rax)
 10fd1f9:	je     10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd1ff:	mov    0x150(%rax),%rdx
 10fd206:	mov    %rdx,%rsi
 10fd209:	shr    $0x2,%rsi
 10fd20d:	mov    $0x94,%bx
 10fd211:	cmp    %rsi,%rcx
 10fd214:	jne    10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd21a:	mov    $0x95,%bx
 10fd21e:	test   $0x3,%dl
 10fd221:	jne    10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd227:	mov    %fs:0xfffffffffffbb5a8,%rcx
 10fd230:	mov    $0x96,%bx
 10fd234:	test   %rcx,%rcx
 10fd237:	je     10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd23d:	mov    0x148(%rax),%rdx
 10fd244:	cmp    %rcx,%rdx
 10fd247:	jne    10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd24d:	mov    0x160(%rax),%edx
 10fd253:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd25c:	jne    10fd4d8 <core.runtime.Runtime.submitSafeDestination+0x1848>
 10fd262:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd26a:	jmp    10fd4f0 <core.runtime.Runtime.submitSafeDestination+0x1860>
 10fd26f:	mov    -0x38(%rbp),%rdx
 10fd273:	mov    0x1a0(%r12),%rcx
 10fd27b:	imul   0x200(%r12),%r13
 10fd284:	lea    0x1(,%rdx,4),%rax
 10fd28c:	lea    0x3(,%rdx,4),%rdx
 10fd294:	lock cmpxchg %rdx,0x1000(%rcx,%r13,1)
 10fd29e:	setne  -0x248(%rbp)
 10fd2a5:	jne    10fd2bf <core.runtime.Runtime.submitSafeDestination+0x162f>
 10fd2a7:	cmpq   $0x0,-0xd8(%rbp)
 10fd2af:	je     10fd2bf <core.runtime.Runtime.submitSafeDestination+0x162f>
 10fd2b1:	mov    -0xf0(%rbp),%rax
 10fd2b8:	decq   0x158(%rax)
 10fd2bf:	movb   $0x1,-0xb4(%rbp)
 10fd2c6:	mov    -0x60(%rbp),%r15
 10fd2ca:	testb  $0x1,0x31ea(%r15)
 10fd2d2:	je     10fd2df <core.runtime.Runtime.submitSafeDestination+0x164f>
 10fd2d4:	mov    -0x78(%rbp),%rax
 10fd2d8:	movzbl (%rax),%eax
 10fd2db:	test   %al,%al
 10fd2dd:	je     10fd321 <core.runtime.Runtime.submitSafeDestination+0x1691>
 10fd2df:	lock incl 0x31d8(%r15)
 10fd2e7:	movzbl 0x31ec(%r15),%eax
 10fd2ef:	test   $0x1,%al
 10fd2f1:	jne    10fd2fe <core.runtime.Runtime.submitSafeDestination+0x166e>
 10fd2f3:	mov    -0x78(%rbp),%rax
 10fd2f7:	movzbl (%rax),%eax
 10fd2fa:	test   %al,%al
 10fd2fc:	je     10fd321 <core.runtime.Runtime.submitSafeDestination+0x1691>
 10fd2fe:	lea    0x31d8(%r15),%rsi
 10fd305:	mov    -0xa8(%rbp),%rax
 10fd30c:	mov    (%rax),%rdi
 10fd30f:	mov    -0xa0(%rbp),%rax
 10fd316:	mov    (%rax),%rax
 10fd319:	mov    $0xffffffff,%edx
 10fd31e:	call   *0x70(%rax)
 10fd321:	cmp    $0x137,%ebx
 10fd327:	mov    -0x50(%rbp),%r14
 10fd32b:	je     10fd336 <core.runtime.Runtime.submitSafeDestination+0x16a6>
 10fd32d:	cmp    $0x62,%ebx
 10fd330:	jne    10fd3ca <core.runtime.Runtime.submitSafeDestination+0x173a>
 10fd336:	mov    -0x70(%rbp),%rax
 10fd33a:	lock incq 0x60(%rax)
 10fd33f:	cmpb   $0x0,-0xb4(%rbp)
 10fd346:	jne    10fd4aa <core.runtime.Runtime.submitSafeDestination+0x181a>
 10fd34c:	mov    -0xd8(%rbp),%rcx
 10fd353:	test   %rcx,%rcx
 10fd356:	je     10fd44b <core.runtime.Runtime.submitSafeDestination+0x17bb>
 10fd35c:	mov    -0xf0(%rbp),%rax
 10fd363:	testb  $0x1,0x2fd(%rax)
 10fd36a:	je     10fd4aa <core.runtime.Runtime.submitSafeDestination+0x181a>
 10fd370:	mov    0x150(%rax),%rdx
 10fd377:	mov    %rdx,%rsi
 10fd37a:	shr    $0x2,%rsi
 10fd37e:	xor    %rsi,%rcx
 10fd381:	and    $0x3,%edx
 10fd384:	or     %rcx,%rdx
 10fd387:	jne    10fd4aa <core.runtime.Runtime.submitSafeDestination+0x181a>
 10fd38d:	mov    %fs:0xfffffffffffbb5a8,%rcx
 10fd396:	test   %rcx,%rcx
 10fd399:	je     10fd4aa <core.runtime.Runtime.submitSafeDestination+0x181a>
 10fd39f:	mov    0x148(%rax),%rdx
 10fd3a6:	cmp    %rcx,%rdx
 10fd3a9:	jne    10fd4aa <core.runtime.Runtime.submitSafeDestination+0x181a>
 10fd3af:	mov    0x160(%rax),%edx
 10fd3b5:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd3be:	jne    10fd42f <core.runtime.Runtime.submitSafeDestination+0x179f>
 10fd3c0:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd3c8:	jmp    10fd447 <core.runtime.Runtime.submitSafeDestination+0x17b7>
 10fd3ca:	mov    %r15,%rdi
 10fd3cd:	mov    %ebx,%esi
 10fd3cf:	call   10fdc70 <core.runtime.Runtime.reportError>
 10fd3d4:	lea    -0xf0(%rbp),%rdi
 10fd3db:	call   10fde30 <journal.journal.Reservation.abort>
 10fd3e0:	mov    %bx,(%r14)
 10fd3e4:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fd3e9:	mov    -0x50(%rbp),%rcx
 10fd3ed:	mov    %ax,(%rcx)
 10fd3f0:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fd3f5:	mov    $0xba,%eax
 10fd3fa:	syscall
 10fd3fc:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd404:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd40d:	cmp    %eax,%edx
 10fd40f:	jne    10fd2c6 <core.runtime.Runtime.submitSafeDestination+0x1636>
 10fd415:	mov    -0xf0(%rbp),%r12
 10fd41c:	mov    -0xe8(%rbp),%rdx
 10fd423:	mov    -0xe0(%rbp),%r13
 10fd42a:	jmp    10fd273 <core.runtime.Runtime.submitSafeDestination+0x15e3>
 10fd42f:	mov    $0xba,%eax
 10fd434:	syscall
 10fd436:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd43e:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd447:	cmp    %eax,%edx
 10fd449:	jne    10fd4aa <core.runtime.Runtime.submitSafeDestination+0x181a>
 10fd44b:	mov    -0xf0(%rbp),%rax
 10fd452:	mov    -0xe8(%rbp),%rcx
 10fd459:	mov    0x1a0(%rax),%rdx
 10fd460:	mov    0x200(%rax),%rsi
 10fd467:	imul   -0xe0(%rbp),%rsi
 10fd46f:	lea    0x1(,%rcx,4),%rax
 10fd477:	lea    0x3(,%rcx,4),%rcx
 10fd47f:	lock cmpxchg %rcx,0x1000(%rdx,%rsi,1)
 10fd489:	setne  -0x248(%rbp)
 10fd490:	jne    10fd4aa <core.runtime.Runtime.submitSafeDestination+0x181a>
 10fd492:	cmpq   $0x0,-0xd8(%rbp)
 10fd49a:	je     10fd4aa <core.runtime.Runtime.submitSafeDestination+0x181a>
 10fd49c:	mov    -0xf0(%rbp),%rax
 10fd4a3:	decq   0x158(%rax)
 10fd4aa:	mov    -0x8b35c(%rip),%eax        # 1072154 <__anon_33691>
 10fd4b0:	mov    %eax,(%r14)
 10fd4b3:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fd4b8:	and    $0x3,%eax
 10fd4bb:	cmp    $0x1,%eax
 10fd4be:	mov    -0x70(%rbp),%rax
 10fd4c2:	jne    10fc5e3 <core.runtime.Runtime.submitSafeDestination+0x953>
 10fd4c8:	lock incq 0x58(%rax)
 10fd4cd:	mov    -0x8b317(%rip),%eax        # 10721bc <__anon_33636>
 10fd4d3:	jmp    10fc08c <core.runtime.Runtime.submitSafeDestination+0x3fc>
 10fd4d8:	mov    $0xba,%eax
 10fd4dd:	syscall
 10fd4df:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd4e7:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd4f0:	cmp    %eax,%edx
 10fd4f2:	jne    10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd4f8:	cmpb   $0x0,-0xb8(%rbp)
 10fd4ff:	mov    -0xf0(%rbp),%r14
 10fd506:	je     10fd536 <core.runtime.Runtime.submitSafeDestination+0x18a6>
 10fd508:	cmpb   $0x0,0x288(%r14)
 10fd510:	je     10fd5b7 <core.runtime.Runtime.submitSafeDestination+0x1927>
 10fd516:	lea    -0xd0(%rbp),%rsi
 10fd51d:	lea    0x208(%r14),%rdi
 10fd524:	call   1132b10 <journal.schema.Registry.validateReady>
 10fd529:	mov    -0x40(%rbp),%rdi
 10fd52d:	test   %ax,%ax
 10fd530:	jne    10fd786 <core.runtime.Runtime.submitSafeDestination+0x1af6>
 10fd536:	mov    $0x13d,%bx
 10fd53a:	cmp    0x1f8(%r14),%r12
 10fd541:	ja     10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd543:	mov    0x200(%r14),%r13
 10fd54a:	imul   -0xe0(%rbp),%r13
 10fd552:	mov    0x1a0(%r14),%r8
 10fd559:	mov    0x1000(%r8,%r13,1),%rax
 10fd561:	mov    -0xe8(%rbp),%rcx
 10fd568:	lea    0x1(,%rcx,4),%rdx
 10fd570:	mov    $0x13c,%bx
 10fd574:	cmp    %rdx,%rax
 10fd577:	jne    10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
 10fd579:	mov    -0xf0(%rbp),%r15
 10fd580:	mov    -0xe0(%rbp),%rsi
 10fd587:	mov    0x200(%r15),%rbx
 10fd58e:	imul   %rsi,%rbx
 10fd592:	add    0x1a0(%r15),%rbx
 10fd599:	mov    0x1f0(%r15),%rdi
 10fd5a0:	lea    -0x1(%rcx),%rax
 10fd5a4:	mov    %rax,%rdx
 10fd5a7:	or     %rdi,%rdx
 10fd5aa:	shr    $0x20,%rdx
 10fd5ae:	je     10fd5f7 <core.runtime.Runtime.submitSafeDestination+0x1967>
 10fd5b0:	xor    %edx,%edx
 10fd5b2:	div    %rdi
 10fd5b5:	jmp    10fd5fb <core.runtime.Runtime.submitSafeDestination+0x196b>
 10fd5b7:	mov    $0x90,%bx
 10fd5bb:	mov    %rdi,%rax
 10fd5be:	shl    $0x6,%rax
 10fd5c2:	mov    -0x88(%rbp),%rdx
 10fd5c9:	lea    0x9810(%rdx),%rcx
 10fd5d0:	test   %edi,%edi
 10fd5d2:	lea    -0x40(%rdx,%rax,1),%rax
 10fd5d7:	cmove  %rcx,%rax
 10fd5db:	lock decq (%rax)
 10fd5df:	lea    -0xf0(%rbp),%rdi
 10fd5e6:	call   10fde30 <journal.journal.Reservation.abort>
 10fd5eb:	mov    -0x50(%rbp),%rax
 10fd5ef:	mov    %bx,(%rax)
 10fd5f2:	jmp    10fc092 <core.runtime.Runtime.submitSafeDestination+0x402>
 10fd5f7:	xor    %edx,%edx
 10fd5f9:	div    %edi
 10fd5fb:	cmpl   $0x1,0x2f0(%r15)
 10fd603:	je     10fd652 <core.runtime.Runtime.submitSafeDestination+0x19c2>
 10fd605:	mov    -0xd0(%rbp),%edi
 10fd60b:	movzwl -0xcc(%rbp),%edx
 10fd612:	vxorps %xmm0,%xmm0,%xmm0
 10fd616:	cmpb   $0x0,-0xb8(%rbp)
 10fd61d:	vmovups %xmm0,0x1020(%rbx)
 10fd625:	movq   $0x0,0x1030(%rbx)
 10fd630:	je     10fd652 <core.runtime.Runtime.submitSafeDestination+0x19c2>
 10fd632:	mov    %edi,0x1020(%rbx)
 10fd638:	lea    -0xca(%rbp),%rdi
 10fd63f:	mov    %dx,0x1024(%rbx)
 10fd646:	vmovups (%rdi),%xmm0
 10fd64a:	vmovups %xmm0,0x1028(%rbx)
 10fd652:	lea    0x0(,%rcx,4),%r14
 10fd65a:	mov    %r12d,0x1018(%rbx)
 10fd661:	xor    %edx,%edx
 10fd663:	cmpb   $0x0,0x2fc(%r15)
 10fd66b:	je     10fd734 <core.runtime.Runtime.submitSafeDestination+0x1aa4>
 10fd671:	mov    %r8,-0x40(%rbp)
 10fd675:	inc    %rax
 10fd678:	mov    0x1a0(%r15),%rdx
 10fd67f:	imul   0x200(%r15),%rsi
 10fd687:	add    %rsi,%rdx
 10fd68a:	add    $0x1040,%rdx
 10fd691:	mov    %rdx,-0x38(%rbp)
 10fd695:	cmpl   $0x1,0x2f0(%r15)
 10fd69d:	jne    10fd6cd <core.runtime.Runtime.submitSafeDestination+0x1a3d>
 10fd69f:	mov    %rcx,-0x248(%rbp)
 10fd6a6:	mov    %rax,-0x240(%rbp)
 10fd6ad:	mov    %r12d,-0x238(%rbp)
 10fd6b4:	movl   $0xffffffff,-0x44(%rbp)
 10fd6bb:	lea    -0x44(%rbp),%rdi
 10fd6bf:	lea    -0x248(%rbp),%rsi
 10fd6c6:	mov    $0x14,%edx
 10fd6cb:	jmp    10fd716 <core.runtime.Runtime.submitSafeDestination+0x1a86>
 10fd6cd:	lea    0x1020(%rbx),%rdx
 10fd6d4:	mov    %rdx,-0x58(%rbp)
 10fd6d8:	mov    %rcx,-0x248(%rbp)
 10fd6df:	mov    %rax,-0x240(%rbp)
 10fd6e6:	mov    %r12d,-0x238(%rbp)
 10fd6ed:	movl   $0xffffffff,-0x44(%rbp)
 10fd6f4:	lea    -0x44(%rbp),%rdi
 10fd6f8:	lea    -0x248(%rbp),%rsi
 10fd6ff:	mov    $0x14,%edx
 10fd704:	call   113d4a0 <platform.crc32.Crc32.update>
 10fd709:	mov    $0x18,%edx
 10fd70e:	lea    -0x44(%rbp),%rdi
 10fd712:	mov    -0x58(%rbp),%rsi
 10fd716:	call   113d4a0 <platform.crc32.Crc32.update>
 10fd71b:	lea    -0x44(%rbp),%rdi
 10fd71f:	mov    -0x38(%rbp),%rsi
 10fd723:	mov    %r12,%rdx
 10fd726:	call   113d4a0 <platform.crc32.Crc32.update>
 10fd72b:	mov    -0x44(%rbp),%edx
 10fd72e:	not    %edx
 10fd730:	mov    -0x40(%rbp),%r8
 10fd734:	mov    %edx,0x101c(%rbx)
 10fd73a:	or     $0x2,%r14
 10fd73e:	mov    %r14,0x1000(%r8,%r13,1)
 10fd746:	cmpq   $0x0,-0xd8(%rbp)
 10fd74e:	je     10fd757 <core.runtime.Runtime.submitSafeDestination+0x1ac7>
 10fd750:	decq   0x158(%r15)
 10fd757:	movb   $0x1,-0xb4(%rbp)
 10fd75e:	mov    -0x70(%rbp),%rax
 10fd762:	lock incq (%rax)
 10fd766:	mov    -0x60(%rbp),%rdi
 10fd76a:	call   10f5890 <core.runtime.Runtime.notify>
 10fd76f:	lea    -0xf0(%rbp),%rdi
 10fd776:	call   10fde30 <journal.journal.Reservation.abort>
 10fd77b:	mov    -0x8b639(%rip),%eax        # 1072148 <__anon_23525>
 10fd781:	jmp    10fc08c <core.runtime.Runtime.submitSafeDestination+0x3fc>
 10fd786:	mov    %eax,%ebx
 10fd788:	jmp    10fd5bb <core.runtime.Runtime.submitSafeDestination+0x192b>
