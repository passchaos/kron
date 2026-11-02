
.zig-cache/submit-abi/single-event-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fbc90 <core.runtime.Runtime.submitSafeDestination>:
 10fbc90:	push   %rbp
 10fbc91:	mov    %rsp,%rbp
 10fbc94:	push   %r15
 10fbc96:	push   %r14
 10fbc98:	push   %r13
 10fbc9a:	push   %r12
 10fbc9c:	push   %rbx
 10fbc9d:	sub    $0xd18,%rsp
 10fbca4:	mov    %rdx,%r12
 10fbca7:	mov    %rsi,%r14
 10fbcaa:	mov    %rdi,%r15
 10fbcad:	mov    (%rcx),%rax
 10fbcb0:	mov    0x8(%rcx),%r8
 10fbcb4:	mov    0x20(%rcx),%r13
 10fbcb8:	mov    0x28(%rcx),%rdx
 10fbcbc:	mov    %rdx,-0x48(%rbp)
 10fbcc0:	vmovups 0x30(%rcx),%xmm0
 10fbcc5:	vmovaps %xmm0,-0x160(%rbp)
 10fbccd:	movzbl 0x40(%rcx),%edx
 10fbcd1:	mov    %dl,-0x38(%rbp)
 10fbcd4:	mov    0x68(%rcx),%rdx
 10fbcd8:	mov    %rdx,-0xe0(%rbp)
 10fbcdf:	vmovups 0x58(%rcx),%xmm0
 10fbce4:	vmovaps %xmm0,-0xf0(%rbp)
 10fbcec:	movzbl 0x70(%rcx),%edx
 10fbcf0:	mov    %dl,-0x60(%rbp)
 10fbcf3:	mov    %rcx,-0x70(%rbp)
 10fbcf7:	movzbl 0x74(%rcx),%edx
 10fbcfb:	mov    0xb8(%r12),%esi
 10fbd03:	lea    -0x41(%rsi),%edi
 10fbd06:	dec    %esi
 10fbd08:	shl    $0x6,%rsi
 10fbd0c:	cmp    $0xffffffc0,%edi
 10fbd0f:	lea    (%rsi,%rsi,2),%rsi
 10fbd13:	mov    $0x3000,%ebx
 10fbd18:	cmovae %rsi,%rbx
 10fbd1c:	mov    %dl,0xd9(%r12)
 10fbd24:	mov    %rax,0x58(%r12)
 10fbd29:	mov    %r8,0x70(%r12)
 10fbd2e:	mov    0x3178(%r14),%rcx
 10fbd35:	mov    %rcx,0x48(%r12)
 10fbd3a:	mov    0x7438(%r13),%rcx
 10fbd41:	mov    %rcx,0x60(%r12)
 10fbd46:	add    %r14,%rbx
 10fbd49:	mov    0x7430(%r13),%rcx
 10fbd50:	mov    %rcx,0x68(%r12)
 10fbd55:	cmpb   $0x0,0x7420(%r13)
 10fbd5d:	je     10fbe5e <core.runtime.Runtime.submitSafeDestination+0x1ce>
 10fbd63:	vmovups 0xc0(%r12),%xmm0
 10fbd6d:	vmovups %xmm0,-0x320(%rbp)
 10fbd75:	mov    0xd0(%r12),%rax
 10fbd7d:	mov    %rax,-0x310(%rbp)
 10fbd84:	movzbl 0xd8(%r12),%eax
 10fbd8d:	mov    %al,-0x308(%rbp)
 10fbd93:	lea    0x1000(%r13),%rsi
 10fbd9a:	movzbl 0xd9(%r12),%eax
 10fbda3:	mov    %al,-0x307(%rbp)
 10fbda9:	mov    0xda(%r12),%eax
 10fbdb1:	mov    %eax,-0x306(%rbp)
 10fbdb7:	movzwl 0xde(%r12),%eax
 10fbdc0:	mov    %ax,-0x302(%rbp)
 10fbdc7:	vmovups 0xa0(%r12),%ymm0
 10fbdd1:	vmovups %ymm0,-0x340(%rbp)
 10fbdd9:	vmovups 0x80(%r12),%ymm0
 10fbde3:	vmovups %ymm0,-0x360(%rbp)
 10fbdeb:	vmovups (%r12),%ymm0
 10fbdf1:	vmovups 0x20(%r12),%ymm1
 10fbdf8:	vmovups 0x40(%r12),%ymm2
 10fbdff:	vmovups 0x60(%r12),%ymm3
 10fbe06:	vmovups %ymm3,-0x380(%rbp)
 10fbe0e:	vmovups %ymm2,-0x3a0(%rbp)
 10fbe16:	vmovups %ymm1,-0x3c0(%rbp)
 10fbe1e:	vmovups %ymm0,-0x3e0(%rbp)
 10fbe26:	lea    -0xcc(%rbp),%rdi
 10fbe2d:	lea    -0x3e0(%rbp),%rdx
 10fbe34:	vzeroupper
 10fbe37:	call   110cee0 <pipeline.predicate.Predicate.matches>
 10fbe3c:	movzwl -0xcc(%rbp),%eax
 10fbe43:	test   %ax,%ax
 10fbe46:	jne    10fbf88 <core.runtime.Runtime.submitSafeDestination+0x2f8>
 10fbe4c:	cmpb   $0x1,-0xca(%rbp)
 10fbe53:	jne    10fbf8e <core.runtime.Runtime.submitSafeDestination+0x2fe>
 10fbe59:	mov    0x58(%r12),%rax
 10fbe5e:	mov    %r13,-0x68(%rbp)
 10fbe62:	mov    0x7490(%r13),%r13
 10fbe69:	and    %rax,%r13
 10fbe6c:	je     10fbf76 <core.runtime.Runtime.submitSafeDestination+0x2e6>
 10fbe72:	mov    %rbx,-0x58(%rbp)
 10fbe76:	mov    %r14,-0x50(%rbp)
 10fbe7a:	mov    %r15,-0x30(%rbp)
 10fbe7e:	lea    -0xd0(%rbp),%r14
 10fbe85:	lea    -0x770(%rbp),%rbx
 10fbe8c:	jmp    10fbe9b <core.runtime.Runtime.submitSafeDestination+0x20b>
 10fbe8e:	xchg   %ax,%ax
 10fbe90:	blsr   %r13,%r13
 10fbe95:	je     10fbf65 <core.runtime.Runtime.submitSafeDestination+0x2d5>
 10fbe9b:	tzcnt  %r13,%r15
 10fbea0:	imul   $0x7650,%r15,%rsi
 10fbea7:	mov    -0x68(%rbp),%rax
 10fbeab:	add    0x7440(%rax),%rsi
 10fbeb2:	vmovups 0xc0(%r12),%ymm0
 10fbebc:	vmovups %ymm0,-0x6b0(%rbp)
 10fbec4:	vmovups 0xa0(%r12),%ymm0
 10fbece:	vmovups %ymm0,-0x6d0(%rbp)
 10fbed6:	vmovups 0x80(%r12),%ymm0
 10fbee0:	vmovups %ymm0,-0x6f0(%rbp)
 10fbee8:	vmovups (%r12),%ymm0
 10fbeee:	vmovups 0x20(%r12),%ymm1
 10fbef5:	vmovups 0x40(%r12),%ymm2
 10fbefc:	vmovups 0x60(%r12),%ymm3
 10fbf03:	vmovups %ymm3,-0x710(%rbp)
 10fbf0b:	vmovups %ymm2,-0x730(%rbp)
 10fbf13:	vmovups %ymm1,-0x750(%rbp)
 10fbf1b:	vmovups %ymm0,-0x770(%rbp)
 10fbf23:	mov    %r14,%rdi
 10fbf26:	mov    %rbx,%rdx
 10fbf29:	vzeroupper
 10fbf2c:	call   110cee0 <pipeline.predicate.Predicate.matches>
 10fbf31:	movzwl -0xd0(%rbp),%eax
 10fbf38:	test   %ax,%ax
 10fbf3b:	jne    10fccdf <core.runtime.Runtime.submitSafeDestination+0x104f>
 10fbf41:	cmpb   $0x0,-0xce(%rbp)
 10fbf48:	jne    10fbe90 <core.runtime.Runtime.submitSafeDestination+0x200>
 10fbf4e:	mov    $0x1,%eax
 10fbf53:	shlx   %r15,%rax,%rax
 10fbf58:	not    %rax
 10fbf5b:	and    %rax,0x58(%r12)
 10fbf60:	jmp    10fbe90 <core.runtime.Runtime.submitSafeDestination+0x200>
 10fbf65:	mov    0x58(%r12),%rax
 10fbf6a:	mov    -0x30(%rbp),%r15
 10fbf6e:	mov    -0x50(%rbp),%r14
 10fbf72:	mov    -0x58(%rbp),%rbx
 10fbf76:	test   %rax,%rax
 10fbf79:	je     10fbf8e <core.runtime.Runtime.submitSafeDestination+0x2fe>
 10fbf7b:	movzwl 0x31e8(%r14),%eax
 10fbf83:	test   %ax,%ax
 10fbf86:	je     10fbfb1 <core.runtime.Runtime.submitSafeDestination+0x321>
 10fbf88:	mov    %ax,(%r15)
 10fbf8c:	jmp    10fbf9c <core.runtime.Runtime.submitSafeDestination+0x30c>
 10fbf8e:	lock incq 0x48(%rbx)
 10fbf93:	mov    -0x89e15(%rip),%eax        # 1072184 <__anon_29578>
 10fbf99:	mov    %eax,(%r15)
 10fbf9c:	add    $0xd18,%rsp
 10fbfa3:	pop    %rbx
 10fbfa4:	pop    %r12
 10fbfa6:	pop    %r13
 10fbfa8:	pop    %r14
 10fbfaa:	pop    %r15
 10fbfac:	pop    %rbp
 10fbfad:	vzeroupper
 10fbfb0:	ret
 10fbfb1:	cmpb   $0x0,-0x60(%rbp)
 10fbfb5:	je     10fc2be <core.runtime.Runtime.submitSafeDestination+0x62e>
 10fbfbb:	mov    -0x48(%rbp),%r13
 10fbfbf:	test   %r13,%r13
 10fbfc2:	je     10fc3c7 <core.runtime.Runtime.submitSafeDestination+0x737>
 10fbfc8:	cmpb   $0x0,0x288(%r13)
 10fbfd0:	je     10fc3d3 <core.runtime.Runtime.submitSafeDestination+0x743>
 10fbfd6:	mov    %rbx,-0x58(%rbp)
 10fbfda:	mov    -0xf0(%rbp),%ebx
 10fbfe0:	lea    0x208(%r13),%rdi
 10fbfe7:	lea    -0xf0(%rbp),%rsi
 10fbfee:	mov    %rdi,-0xc8(%rbp)
 10fbff5:	call   11326a0 <journal.schema.Registry.validateReady>
 10fbffa:	test   %ax,%ax
 10fbffd:	jne    10fbf88 <core.runtime.Runtime.submitSafeDestination+0x2f8>
 10fbfff:	dec    %ebx
 10fc001:	mov    0x270(%r13),%rax
 10fc008:	imul   $0xd8,%rbx,%rcx
 10fc00f:	vmovups 0xa8(%rax,%rcx,1),%ymm0
 10fc018:	vmovups %ymm0,-0x260(%rbp)
 10fc020:	vmovups 0x88(%rax,%rcx,1),%ymm0
 10fc029:	vmovups %ymm0,-0x280(%rbp)
 10fc031:	vmovups 0x8(%rax,%rcx,1),%ymm0
 10fc037:	vmovups 0x28(%rax,%rcx,1),%ymm1
 10fc03d:	vmovups 0x48(%rax,%rcx,1),%ymm2
 10fc043:	vmovups 0x68(%rax,%rcx,1),%ymm3
 10fc049:	vmovups %ymm3,-0x2a0(%rbp)
 10fc051:	vmovups %ymm2,-0x2c0(%rbp)
 10fc059:	vmovups %ymm1,-0x2e0(%rbp)
 10fc061:	lea    -0x240(%rbp),%rax
 10fc068:	mov    %rax,-0xf8(%rbp)
 10fc06f:	vmovups %ymm0,-0x300(%rbp)
 10fc077:	movb   $0x1,-0x240(%rbp)
 10fc07e:	lea    0x140(%r13),%rcx
 10fc085:	lea    0x31c4(%r14),%r8
 10fc08c:	lea    0x31ee(%r14),%rax
 10fc093:	mov    %rax,-0x60(%rbp)
 10fc097:	lea    0x3110(%r14),%rax
 10fc09e:	mov    %rax,-0x80(%rbp)
 10fc0a2:	lea    0x3118(%r14),%rax
 10fc0a9:	mov    %rax,-0x78(%rbp)
 10fc0ad:	cmpb   $0x0,-0x38(%rbp)
 10fc0b1:	cmove  %r8,%rcx
 10fc0b5:	mov    %rcx,-0x38(%rbp)
 10fc0b9:	mov    %r14,-0x50(%rbp)
 10fc0bd:	je     10fc471 <core.runtime.Runtime.submitSafeDestination+0x7e1>
 10fc0c3:	lea    0x164(%r13),%rbx
 10fc0ca:	lea    -0xf0(%rbp),%rsi
 10fc0d1:	mov    %r15,-0x30(%rbp)
 10fc0d5:	mov    0x140(%r13),%eax
 10fc0dc:	mov    %eax,-0xfc(%rbp)
 10fc0e2:	cmpb   $0x0,0x288(%r13)
 10fc0ea:	jne    10fc190 <core.runtime.Runtime.submitSafeDestination+0x500>
 10fc0f0:	mov    $0x90,%ax
 10fc0f4:	mov    %ax,-0x1f0(%rbp)
 10fc0fb:	movzwl %ax,%ecx
 10fc0fe:	cmp    $0x13b,%ecx
 10fc104:	jne    10fcceb <core.runtime.Runtime.submitSafeDestination+0x105b>
 10fc10a:	mov    -0x50(%rbp),%rcx
 10fc10e:	movzbl 0x31ef(%rcx),%eax
 10fc115:	test   $0x3,%al
 10fc117:	mov    -0x30(%rbp),%r15
 10fc11b:	jne    10fcdb7 <core.runtime.Runtime.submitSafeDestination+0x1127>
 10fc121:	mov    $0x1,%al
 10fc123:	xchg   %al,(%rbx)
 10fc125:	movzwl 0x31e8(%rcx),%eax
 10fc12c:	test   %ax,%ax
 10fc12f:	mov    -0x58(%rbp),%rcx
 10fc133:	jne    10fd2c7 <core.runtime.Runtime.submitSafeDestination+0x1637>
 10fc139:	mov    -0x60(%rbp),%rax
 10fc13d:	movzbl (%rax),%eax
 10fc140:	test   %al,%al
 10fc142:	jne    10fd2dc <core.runtime.Runtime.submitSafeDestination+0x164c>
 10fc148:	mov    -0x80(%rbp),%rax
 10fc14c:	mov    (%rax),%rdi
 10fc14f:	mov    -0x78(%rbp),%rax
 10fc153:	mov    (%rax),%rax
 10fc156:	mov    -0x38(%rbp),%rsi
 10fc15a:	mov    -0xfc(%rbp),%edx
 10fc160:	vzeroupper
 10fc163:	call   *0x68(%rax)
 10fc166:	mov    -0x48(%rbp),%r13
 10fc16a:	xor    %eax,%eax
 10fc16c:	xchg   %al,(%rbx)
 10fc16e:	lea    -0xf0(%rbp),%rsi
 10fc175:	mov    0x140(%r13),%eax
 10fc17c:	mov    %eax,-0xfc(%rbp)
 10fc182:	cmpb   $0x0,0x288(%r13)
 10fc18a:	je     10fc0f0 <core.runtime.Runtime.submitSafeDestination+0x460>
 10fc190:	mov    -0xf0(%rbp),%r14d
 10fc197:	movzwl -0xec(%rbp),%r15d
 10fc19f:	mov    -0xc8(%rbp),%rdi
 10fc1a6:	vzeroupper
 10fc1a9:	call   11326a0 <journal.schema.Registry.validateReady>
 10fc1ae:	test   %ax,%ax
 10fc1b1:	jne    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x464>
 10fc1b7:	lea    -0x150(%rbp),%rdi
 10fc1be:	mov    -0x48(%rbp),%r13
 10fc1c2:	mov    %r13,%rsi
 10fc1c5:	lea    -0x160(%rbp),%rdx
 10fc1cc:	call   10fba50 <journal.journal.Journal.reserveSingleProducer>
 10fc1d1:	movzwl -0x110(%rbp),%eax
 10fc1d8:	test   %ax,%ax
 10fc1db:	jne    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x464>
 10fc1e1:	vmovups -0x140(%rbp),%xmm0
 10fc1e9:	mov    -0x114(%rbp),%eax
 10fc1ef:	cmpl   $0x1,0x2f0(%r13)
 10fc1f7:	je     10fc23b <core.runtime.Runtime.submitSafeDestination+0x5ab>
 10fc1f9:	mov    0x1a0(%r13),%rcx
 10fc200:	mov    0x200(%r13),%rdx
 10fc207:	imul   -0x140(%rbp),%rdx
 10fc20f:	movw   $0x0,0x1026(%rcx,%rdx,1)
 10fc219:	mov    %r14d,0x1020(%rcx,%rdx,1)
 10fc221:	mov    %r15w,0x1024(%rcx,%rdx,1)
 10fc22a:	vmovups -0xea(%rbp),%xmm1
 10fc232:	vmovups %xmm1,0x1028(%rcx,%rdx,1)
 10fc23b:	movw   $0x0,-0x1f0(%rbp)
 10fc244:	vmovups -0x150(%rbp),%xmm1
 10fc24c:	vmovaps %xmm1,-0x230(%rbp)
 10fc254:	vmovaps %xmm0,-0x220(%rbp)
 10fc25c:	mov    -0xe0(%rbp),%rcx
 10fc263:	lea    -0x210(%rbp),%rsi
 10fc26a:	mov    %rcx,0x10(%rsi)
 10fc26e:	vmovaps -0xf0(%rbp),%xmm0
 10fc276:	vmovups %xmm0,(%rsi)
 10fc27a:	movb   $0x1,-0x1f8(%rbp)
 10fc281:	lea    -0x117(%rbp),%rdx
 10fc288:	movzbl 0x2(%rdx),%ecx
 10fc28c:	mov    %cl,0x1b(%rsi)
 10fc28f:	movzwl (%rdx),%ecx
 10fc292:	mov    %cx,0x19(%rsi)
 10fc296:	mov    %eax,-0x1f4(%rbp)
 10fc29c:	lea    -0x230(%rbp),%r13
 10fc2a3:	lea    -0x300(%rbp),%rbx
 10fc2aa:	mov    -0x30(%rbp),%r15
 10fc2ae:	mov    -0x70(%rbp),%rax
 10fc2b2:	lea    -0x240(%rbp),%rcx
 10fc2b9:	jmp    10fc5e3 <core.runtime.Runtime.submitSafeDestination+0x953>
 10fc2be:	mov    -0x48(%rbp),%rsi
 10fc2c2:	test   %rsi,%rsi
 10fc2c5:	mov    -0x68(%rbp),%rcx
 10fc2c9:	je     10fc3dc <core.runtime.Runtime.submitSafeDestination+0x74c>
 10fc2cf:	mov    %rbx,-0x58(%rbp)
 10fc2d3:	lea    0x31ee(%r14),%rax
 10fc2da:	mov    %rax,-0x60(%rbp)
 10fc2de:	lea    0x3110(%r14),%rax
 10fc2e5:	mov    %rax,-0x80(%rbp)
 10fc2e9:	lea    0x3118(%r14),%rax
 10fc2f0:	mov    %rax,-0x78(%rbp)
 10fc2f4:	cmpb   $0x0,-0x38(%rbp)
 10fc2f8:	mov    %r14,-0x50(%rbp)
 10fc2fc:	je     10fc547 <core.runtime.Runtime.submitSafeDestination+0x8b7>
 10fc302:	lea    0x140(%rsi),%rax
 10fc309:	mov    %rax,-0xc8(%rbp)
 10fc310:	lea    0x164(%rsi),%rax
 10fc317:	mov    %rax,-0x38(%rbp)
 10fc31b:	lea    -0xcf8(%rbp),%r13
 10fc322:	lea    -0x160(%rbp),%rbx
 10fc329:	mov    0x140(%rsi),%r14d
 10fc330:	mov    %r13,%rdi
 10fc333:	mov    %rbx,%rdx
 10fc336:	call   10fba50 <journal.journal.Journal.reserveSingleProducer>
 10fc33b:	movzwl -0xcb8(%rbp),%eax
 10fc342:	test   %eax,%eax
 10fc344:	je     10fc5d5 <core.runtime.Runtime.submitSafeDestination+0x945>
 10fc34a:	mov    %r15,-0x30(%rbp)
 10fc34e:	cmp    $0x13b,%eax
 10fc353:	jne    10fcceb <core.runtime.Runtime.submitSafeDestination+0x105b>
 10fc359:	mov    -0x50(%rbp),%rax
 10fc35d:	movzbl 0x31ef(%rax),%eax
 10fc364:	test   $0x3,%al
 10fc366:	jne    10fd083 <core.runtime.Runtime.submitSafeDestination+0x13f3>
 10fc36c:	mov    $0x1,%al
 10fc36e:	mov    -0x38(%rbp),%rcx
 10fc372:	xchg   %al,(%rcx)
 10fc374:	mov    -0x50(%rbp),%rax
 10fc378:	movzwl 0x31e8(%rax),%eax
 10fc37f:	test   %ax,%ax
 10fc382:	jne    10fd2bf <core.runtime.Runtime.submitSafeDestination+0x162f>
 10fc388:	mov    -0x60(%rbp),%rax
 10fc38c:	movzbl (%rax),%eax
 10fc38f:	test   %al,%al
 10fc391:	jne    10fd2d0 <core.runtime.Runtime.submitSafeDestination+0x1640>
 10fc397:	mov    -0x80(%rbp),%rax
 10fc39b:	mov    (%rax),%rdi
 10fc39e:	mov    -0x78(%rbp),%rax
 10fc3a2:	mov    (%rax),%rax
 10fc3a5:	mov    -0xc8(%rbp),%rsi
 10fc3ac:	mov    %r14d,%edx
 10fc3af:	call   *0x68(%rax)
 10fc3b2:	xor    %eax,%eax
 10fc3b4:	mov    -0x38(%rbp),%rcx
 10fc3b8:	xchg   %al,(%rcx)
 10fc3ba:	mov    -0x30(%rbp),%r15
 10fc3be:	mov    -0x48(%rbp),%rsi
 10fc3c2:	jmp    10fc329 <core.runtime.Runtime.submitSafeDestination+0x699>
 10fc3c7:	movl   $0x134,(%r15)
 10fc3ce:	jmp    10fbf9c <core.runtime.Runtime.submitSafeDestination+0x30c>
 10fc3d3:	mov    $0x90,%ax
 10fc3d7:	jmp    10fbf88 <core.runtime.Runtime.submitSafeDestination+0x2f8>
 10fc3dc:	vmovups 0xc0(%r12),%ymm0
 10fc3e6:	vmovups %ymm0,-0xbf0(%rbp)
 10fc3ee:	vmovups 0xa0(%r12),%ymm0
 10fc3f8:	vmovups %ymm0,-0xc10(%rbp)
 10fc400:	vmovups 0x80(%r12),%ymm0
 10fc40a:	vmovups %ymm0,-0xc30(%rbp)
 10fc412:	vmovups (%r12),%ymm0
 10fc418:	vmovups 0x20(%r12),%ymm1
 10fc41f:	vmovups 0x40(%r12),%ymm2
 10fc426:	vmovups 0x60(%r12),%ymm3
 10fc42d:	vmovups %ymm3,-0xc50(%rbp)
 10fc435:	vmovups %ymm2,-0xc70(%rbp)
 10fc43d:	vmovups %ymm1,-0xc90(%rbp)
 10fc445:	vmovups %ymm0,-0xcb0(%rbp)
 10fc44d:	lea    -0x104(%rbp),%rdi
 10fc454:	lea    -0xcb0(%rbp),%rdx
 10fc45b:	mov    %r14,%rsi
 10fc45e:	vzeroupper
 10fc461:	call   1100810 <core.runtime.Runtime.submitSync>
 10fc466:	mov    -0x104(%rbp),%eax
 10fc46c:	jmp    10fbf99 <core.runtime.Runtime.submitSafeDestination+0x309>
 10fc471:	lea    -0x428(%rbp),%rdi
 10fc478:	lea    -0xf0(%rbp),%rdx
 10fc47f:	lea    -0x300(%rbp),%rbx
 10fc486:	mov    (%r8),%r14d
 10fc489:	mov    %r13,%rsi
 10fc48c:	mov    %r8,%r13
 10fc48f:	vzeroupper
 10fc492:	call   10fb7b0 <journal.journal.Journal.reserveWithSchema>
 10fc497:	movzwl -0x3e8(%rbp),%eax
 10fc49e:	test   %eax,%eax
 10fc4a0:	je     10fc530 <core.runtime.Runtime.submitSafeDestination+0x8a0>
 10fc4a6:	mov    %r13,-0xc8(%rbp)
 10fc4ad:	mov    %r15,-0x30(%rbp)
 10fc4b1:	cmp    $0x13b,%eax
 10fc4b6:	jne    10fcceb <core.runtime.Runtime.submitSafeDestination+0x105b>
 10fc4bc:	mov    -0x50(%rbp),%rax
 10fc4c0:	movzbl 0x31ef(%rax),%eax
 10fc4c7:	test   $0x3,%al
 10fc4c9:	jne    10fd0aa <core.runtime.Runtime.submitSafeDestination+0x141a>
 10fc4cf:	mov    -0x50(%rbp),%rax
 10fc4d3:	movzwl 0x31e8(%rax),%eax
 10fc4da:	test   %ax,%ax
 10fc4dd:	mov    -0x30(%rbp),%r15
 10fc4e1:	jne    10fbf88 <core.runtime.Runtime.submitSafeDestination+0x2f8>
 10fc4e7:	mov    -0x60(%rbp),%rax
 10fc4eb:	movzbl (%rax),%eax
 10fc4ee:	test   %al,%al
 10fc4f0:	jne    10fd2b0 <core.runtime.Runtime.submitSafeDestination+0x1620>
 10fc4f6:	mov    -0x80(%rbp),%rax
 10fc4fa:	mov    (%rax),%rdi
 10fc4fd:	mov    -0x78(%rbp),%rax
 10fc501:	mov    (%rax),%rax
 10fc504:	mov    -0x38(%rbp),%rsi
 10fc508:	mov    %r14d,%edx
 10fc50b:	call   *0x68(%rax)
 10fc50e:	mov    -0x30(%rbp),%r15
 10fc512:	mov    -0x48(%rbp),%r13
 10fc516:	lea    -0x428(%rbp),%rdi
 10fc51d:	mov    -0xc8(%rbp),%r8
 10fc524:	lea    -0xf0(%rbp),%rdx
 10fc52b:	jmp    10fc486 <core.runtime.Runtime.submitSafeDestination+0x7f6>
 10fc530:	mov    -0x70(%rbp),%rax
 10fc534:	lea    -0x240(%rbp),%rcx
 10fc53b:	lea    -0x428(%rbp),%r13
 10fc542:	jmp    10fc5e3 <core.runtime.Runtime.submitSafeDestination+0x953>
 10fc547:	lea    0x31c4(%r14),%rbx
 10fc54e:	lea    -0xd40(%rbp),%r13
 10fc555:	mov    (%rbx),%r14d
 10fc558:	mov    %r13,%rdi
 10fc55b:	call   10fb590 <journal.journal.Journal.reserve>
 10fc560:	movzwl -0xd00(%rbp),%eax
 10fc567:	test   %eax,%eax
 10fc569:	je     10fc5d5 <core.runtime.Runtime.submitSafeDestination+0x945>
 10fc56b:	mov    %r15,-0x30(%rbp)
 10fc56f:	cmp    $0x13b,%eax
 10fc574:	jne    10fcceb <core.runtime.Runtime.submitSafeDestination+0x105b>
 10fc57a:	mov    -0x50(%rbp),%rax
 10fc57e:	movzbl 0x31ef(%rax),%eax
 10fc585:	test   $0x3,%al
 10fc587:	jne    10fd083 <core.runtime.Runtime.submitSafeDestination+0x13f3>
 10fc58d:	mov    -0x50(%rbp),%rax
 10fc591:	movzwl 0x31e8(%rax),%eax
 10fc598:	test   %ax,%ax
 10fc59b:	mov    -0x30(%rbp),%r15
 10fc59f:	jne    10fbf88 <core.runtime.Runtime.submitSafeDestination+0x2f8>
 10fc5a5:	mov    -0x60(%rbp),%rax
 10fc5a9:	movzbl (%rax),%eax
 10fc5ac:	test   %al,%al
 10fc5ae:	jne    10fd2b0 <core.runtime.Runtime.submitSafeDestination+0x1620>
 10fc5b4:	mov    -0x80(%rbp),%rax
 10fc5b8:	mov    (%rax),%rdi
 10fc5bb:	mov    -0x78(%rbp),%rax
 10fc5bf:	mov    (%rax),%rax
 10fc5c2:	mov    %rbx,%rsi
 10fc5c5:	mov    %r14d,%edx
 10fc5c8:	call   *0x68(%rax)
 10fc5cb:	mov    -0x30(%rbp),%r15
 10fc5cf:	mov    -0x48(%rbp),%rsi
 10fc5d3:	jmp    10fc555 <core.runtime.Runtime.submitSafeDestination+0x8c5>
 10fc5d5:	mov    $0x1066d08,%ebx
 10fc5da:	mov    $0x1066dc8,%ecx
 10fc5df:	mov    -0x70(%rbp),%rax
 10fc5e3:	vmovups 0x0(%r13),%ymm0
 10fc5e9:	vmovups 0x20(%r13),%ymm1
 10fc5ef:	vmovups %ymm0,-0xc0(%rbp)
 10fc5f7:	vmovups %ymm1,-0xa0(%rbp)
 10fc5ff:	mov    -0xb8(%rbp),%rdx
 10fc606:	mov    %rdx,0x50(%r12)
 10fc60b:	cmpb   $0x0,(%rcx)
 10fc60e:	mov    %rdx,-0x70(%rbp)
 10fc612:	je     10fc75a <core.runtime.Runtime.submitSafeDestination+0xaca>
 10fc618:	vmovups 0xa0(%rbx),%ymm0
 10fc620:	vmovups %ymm0,-0x530(%rbp)
 10fc628:	vmovups 0x80(%rbx),%ymm0
 10fc630:	vmovups %ymm0,-0x550(%rbp)
 10fc638:	vmovups (%rbx),%ymm0
 10fc63c:	vmovups 0x20(%rbx),%ymm1
 10fc641:	vmovups 0x40(%rbx),%ymm2
 10fc646:	vmovups 0x60(%rbx),%ymm3
 10fc64b:	vmovups %ymm3,-0x570(%rbp)
 10fc653:	vmovups %ymm2,-0x590(%rbp)
 10fc65b:	vmovups %ymm1,-0x5b0(%rbp)
 10fc663:	vmovups %ymm0,-0x5d0(%rbp)
 10fc66b:	cmpb   $0x0,0x50(%rax)
 10fc66f:	je     10fc841 <core.runtime.Runtime.submitSafeDestination+0xbb1>
 10fc675:	lea    -0x188(%rbp),%rbx
 10fc67c:	mov    0x48(%rax),%rcx
 10fc680:	vmovups 0xc0(%r12),%ymm0
 10fc68a:	vmovups %ymm0,-0x870(%rbp)
 10fc692:	vmovups 0xa0(%r12),%ymm0
 10fc69c:	vmovups %ymm0,-0x890(%rbp)
 10fc6a4:	vmovups 0x80(%r12),%ymm0
 10fc6ae:	vmovups %ymm0,-0x8b0(%rbp)
 10fc6b6:	vmovups (%r12),%ymm0
 10fc6bc:	vmovups 0x20(%r12),%ymm1
 10fc6c3:	vmovups 0x40(%r12),%ymm2
 10fc6ca:	vmovups 0x60(%r12),%ymm3
 10fc6d1:	vmovups %ymm3,-0x8d0(%rbp)
 10fc6d9:	vmovups %ymm2,-0x8f0(%rbp)
 10fc6e1:	vmovups %ymm1,-0x910(%rbp)
 10fc6e9:	lea    -0x190(%rbp),%rax
 10fc6f0:	mov    %rax,-0x38(%rbp)
 10fc6f4:	vmovups %ymm0,-0x930(%rbp)
 10fc6fc:	movzbl -0x84(%rbp),%eax
 10fc703:	mov    %al,-0x48(%rbp)
 10fc706:	mov    -0xc0(%rbp),%r13
 10fc70d:	mov    -0xb0(%rbp),%r14
 10fc714:	mov    0x200(%r13),%rax
 10fc71b:	imul   %r14,%rax
 10fc71f:	mov    0x1a0(%r13),%rdx
 10fc726:	mov    0x1f8(%r13),%r9
 10fc72d:	lea    (%rdx,%rax,1),%r8
 10fc731:	add    $0x1040,%r8
 10fc738:	lea    -0x198(%rbp),%rdi
 10fc73f:	lea    -0x930(%rbp),%rsi
 10fc746:	lea    -0x5d0(%rbp),%rdx
 10fc74d:	vzeroupper
 10fc750:	call   10fe270 <core.reference_encoding.writeMeasured>
 10fc755:	jmp    10fc9f5 <core.runtime.Runtime.submitSafeDestination+0xd65>
 10fc75a:	cmpb   $0x0,0x50(%rax)
 10fc75e:	je     10fc921 <core.runtime.Runtime.submitSafeDestination+0xc91>
 10fc764:	lea    -0x1b8(%rbp),%rbx
 10fc76b:	mov    0x48(%rax),%rdx
 10fc76f:	vmovups 0xc0(%r12),%ymm0
 10fc779:	vmovups %ymm0,-0xa30(%rbp)
 10fc781:	vmovups 0xa0(%r12),%ymm0
 10fc78b:	vmovups %ymm0,-0xa50(%rbp)
 10fc793:	vmovups 0x80(%r12),%ymm0
 10fc79d:	vmovups %ymm0,-0xa70(%rbp)
 10fc7a5:	vmovups (%r12),%ymm0
 10fc7ab:	vmovups 0x20(%r12),%ymm1
 10fc7b2:	vmovups 0x40(%r12),%ymm2
 10fc7b9:	vmovups 0x60(%r12),%ymm3
 10fc7c0:	vmovups %ymm3,-0xa90(%rbp)
 10fc7c8:	vmovups %ymm2,-0xab0(%rbp)
 10fc7d0:	vmovups %ymm1,-0xad0(%rbp)
 10fc7d8:	lea    -0x1c0(%rbp),%rax
 10fc7df:	mov    %rax,-0x38(%rbp)
 10fc7e3:	vmovups %ymm0,-0xaf0(%rbp)
 10fc7eb:	movzbl -0x84(%rbp),%eax
 10fc7f2:	mov    %al,-0x48(%rbp)
 10fc7f5:	mov    -0xc0(%rbp),%r13
 10fc7fc:	mov    -0xb0(%rbp),%r14
 10fc803:	mov    0x200(%r13),%rax
 10fc80a:	imul   %r14,%rax
 10fc80e:	mov    0x1a0(%r13),%rcx
 10fc815:	mov    0x1f8(%r13),%r8
 10fc81c:	add    %rax,%rcx
 10fc81f:	add    $0x1040,%rcx
 10fc826:	lea    -0x1c8(%rbp),%rdi
 10fc82d:	lea    -0xaf0(%rbp),%rsi
 10fc834:	vzeroupper
 10fc837:	call   10fdb40 <core.codec.encodeSized>
 10fc83c:	jmp    10fc9f5 <core.runtime.Runtime.submitSafeDestination+0xd65>
 10fc841:	lea    -0x1a0(%rbp),%rbx
 10fc848:	vmovups 0xc0(%r12),%ymm0
 10fc852:	vmovups %ymm0,-0x950(%rbp)
 10fc85a:	vmovups 0xa0(%r12),%ymm0
 10fc864:	vmovups %ymm0,-0x970(%rbp)
 10fc86c:	vmovups 0x80(%r12),%ymm0
 10fc876:	vmovups %ymm0,-0x990(%rbp)
 10fc87e:	vmovups (%r12),%ymm0
 10fc884:	vmovups 0x20(%r12),%ymm1
 10fc88b:	vmovups 0x40(%r12),%ymm2
 10fc892:	vmovups 0x60(%r12),%ymm3
 10fc899:	vmovups %ymm3,-0x9b0(%rbp)
 10fc8a1:	vmovups %ymm2,-0x9d0(%rbp)
 10fc8a9:	vmovups %ymm1,-0x9f0(%rbp)
 10fc8b1:	lea    -0x1a8(%rbp),%rax
 10fc8b8:	mov    %rax,-0x38(%rbp)
 10fc8bc:	vmovups %ymm0,-0xa10(%rbp)
 10fc8c4:	movzbl -0x84(%rbp),%eax
 10fc8cb:	mov    %al,-0x48(%rbp)
 10fc8ce:	mov    -0xc0(%rbp),%r13
 10fc8d5:	mov    -0xb0(%rbp),%r14
 10fc8dc:	mov    0x200(%r13),%rax
 10fc8e3:	imul   %r14,%rax
 10fc8e7:	mov    0x1a0(%r13),%rcx
 10fc8ee:	mov    0x1f8(%r13),%r8
 10fc8f5:	add    %rax,%rcx
 10fc8f8:	add    $0x1040,%rcx
 10fc8ff:	lea    -0x1b0(%rbp),%rdi
 10fc906:	lea    -0xa10(%rbp),%rsi
 10fc90d:	lea    -0x5d0(%rbp),%rdx
 10fc914:	vzeroupper
 10fc917:	call   10fe1f0 <core.schema_codec.encodeReference>
 10fc91c:	jmp    10fc9f5 <core.runtime.Runtime.submitSafeDestination+0xd65>
 10fc921:	lea    -0x1d0(%rbp),%rbx
 10fc928:	vmovups 0xc0(%r12),%ymm0
 10fc932:	vmovups %ymm0,-0xb10(%rbp)
 10fc93a:	vmovups 0xa0(%r12),%ymm0
 10fc944:	vmovups %ymm0,-0xb30(%rbp)
 10fc94c:	vmovups 0x80(%r12),%ymm0
 10fc956:	vmovups %ymm0,-0xb50(%rbp)
 10fc95e:	vmovups (%r12),%ymm0
 10fc964:	vmovups 0x20(%r12),%ymm1
 10fc96b:	vmovups 0x40(%r12),%ymm2
 10fc972:	vmovups 0x60(%r12),%ymm3
 10fc979:	vmovups %ymm3,-0xb70(%rbp)
 10fc981:	vmovups %ymm2,-0xb90(%rbp)
 10fc989:	vmovups %ymm1,-0xbb0(%rbp)
 10fc991:	lea    -0x1d8(%rbp),%rax
 10fc998:	mov    %rax,-0x38(%rbp)
 10fc99c:	vmovups %ymm0,-0xbd0(%rbp)
 10fc9a4:	movzbl -0x84(%rbp),%eax
 10fc9ab:	mov    %al,-0x48(%rbp)
 10fc9ae:	mov    -0xc0(%rbp),%r13
 10fc9b5:	mov    -0xb0(%rbp),%r14
 10fc9bc:	mov    0x200(%r13),%rax
 10fc9c3:	imul   %r14,%rax
 10fc9c7:	mov    0x1a0(%r13),%rdx
 10fc9ce:	mov    0x1f8(%r13),%rcx
 10fc9d5:	add    %rax,%rdx
 10fc9d8:	add    $0x1040,%rdx
 10fc9df:	lea    -0x1e0(%rbp),%rdi
 10fc9e6:	lea    -0xbd0(%rbp),%rsi
 10fc9ed:	vzeroupper
 10fc9f0:	call   10fdac0 <core.codec.encode>
 10fc9f5:	movzwl (%rbx),%ebx
 10fc9f8:	test   %ebx,%ebx
 10fc9fa:	je     10fca8a <core.runtime.Runtime.submitSafeDestination+0xdfa>
 10fca00:	testb  $0x1,-0x48(%rbp)
 10fca04:	jne    10fcbc3 <core.runtime.Runtime.submitSafeDestination+0xf33>
 10fca0a:	mov    -0xa8(%rbp),%rax
 10fca11:	test   %rax,%rax
 10fca14:	je     10fcb6e <core.runtime.Runtime.submitSafeDestination+0xede>
 10fca1a:	testb  $0x1,0x2fd(%r13)
 10fca22:	je     10fcbc3 <core.runtime.Runtime.submitSafeDestination+0xf33>
 10fca28:	mov    0x150(%r13),%rcx
 10fca2f:	mov    %rcx,%rdx
 10fca32:	shr    $0x2,%rdx
 10fca36:	xor    %rdx,%rax
 10fca39:	and    $0x3,%ecx
 10fca3c:	or     %rax,%rcx
 10fca3f:	jne    10fcbc3 <core.runtime.Runtime.submitSafeDestination+0xf33>
 10fca45:	mov    %fs:0xfffffffffffbb5a8,%rax
 10fca4e:	test   %rax,%rax
 10fca51:	je     10fcbc3 <core.runtime.Runtime.submitSafeDestination+0xf33>
 10fca57:	mov    0x148(%r13),%rcx
 10fca5e:	cmp    %rax,%rcx
 10fca61:	jne    10fcbc3 <core.runtime.Runtime.submitSafeDestination+0xf33>
 10fca67:	mov    0x160(%r13),%edx
 10fca6e:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fca77:	jne    10fccf7 <core.runtime.Runtime.submitSafeDestination+0x1067>
 10fca7d:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fca85:	jmp    10fcd0f <core.runtime.Runtime.submitSafeDestination+0x107f>
 10fca8a:	mov    0xb8(%r12),%eax
 10fca92:	test   %rax,%rax
 10fca95:	je     10fcaa8 <core.runtime.Runtime.submitSafeDestination+0xe18>
 10fca97:	shl    $0x6,%rax
 10fca9b:	mov    -0x68(%rbp),%rcx
 10fca9f:	add    %rcx,%rax
 10fcaa2:	add    $0xffffffffffffffc0,%rax
 10fcaa6:	jmp    10fcab2 <core.runtime.Runtime.submitSafeDestination+0xe22>
 10fcaa8:	mov    -0x68(%rbp),%rax
 10fcaac:	add    $0x9810,%rax
 10fcab2:	mov    %r15,%r14
 10fcab5:	mov    -0x38(%rbp),%rcx
 10fcab9:	mov    (%rcx),%rbx
 10fcabc:	lock incq (%rax)
 10fcac0:	mov    $0x13c,%r13w
 10fcac5:	cmpb   $0x0,-0x84(%rbp)
 10fcacc:	jne    10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fcad2:	mov    -0xa8(%rbp),%rcx
 10fcad9:	test   %rcx,%rcx
 10fcadc:	je     10fcdf7 <core.runtime.Runtime.submitSafeDestination+0x1167>
 10fcae2:	mov    -0xc0(%rbp),%rax
 10fcae9:	mov    $0x92,%r13w
 10fcaee:	testb  $0x1,0x2fd(%rax)
 10fcaf5:	je     10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fcafb:	mov    0x150(%rax),%rdx
 10fcb02:	mov    %rdx,%rsi
 10fcb05:	shr    $0x2,%rsi
 10fcb09:	mov    $0x94,%r13w
 10fcb0e:	cmp    %rsi,%rcx
 10fcb11:	jne    10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fcb17:	mov    $0x95,%r13w
 10fcb1c:	test   $0x3,%dl
 10fcb1f:	jne    10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fcb25:	mov    %fs:0xfffffffffffbb5a8,%rcx
 10fcb2e:	mov    $0x96,%r13w
 10fcb33:	test   %rcx,%rcx
 10fcb36:	je     10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fcb3c:	mov    0x148(%rax),%rdx
 10fcb43:	cmp    %rcx,%rdx
 10fcb46:	jne    10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fcb4c:	mov    0x160(%rax),%edx
 10fcb52:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fcb5b:	jne    10fcdd7 <core.runtime.Runtime.submitSafeDestination+0x1147>
 10fcb61:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fcb69:	jmp    10fcdef <core.runtime.Runtime.submitSafeDestination+0x115f>
 10fcb6e:	mov    -0x70(%rbp),%rdx
 10fcb72:	mov    0x1a0(%r13),%rcx
 10fcb79:	imul   0x200(%r13),%r14
 10fcb81:	lea    0x1(,%rdx,4),%rax
 10fcb89:	lea    0x3(,%rdx,4),%rdx
 10fcb91:	lock cmpxchg %rdx,0x1000(%rcx,%r14,1)
 10fcb9b:	setne  -0x150(%rbp)
 10fcba2:	jne    10fcbbc <core.runtime.Runtime.submitSafeDestination+0xf2c>
 10fcba4:	cmpq   $0x0,-0xa8(%rbp)
 10fcbac:	je     10fcbbc <core.runtime.Runtime.submitSafeDestination+0xf2c>
 10fcbae:	mov    -0xc0(%rbp),%rax
 10fcbb5:	decq   0x158(%rax)
 10fcbbc:	movb   $0x1,-0x84(%rbp)
 10fcbc3:	mov    -0x50(%rbp),%r14
 10fcbc7:	testb  $0x1,0x31ea(%r14)
 10fcbcf:	je     10fcbdc <core.runtime.Runtime.submitSafeDestination+0xf4c>
 10fcbd1:	mov    -0x60(%rbp),%rax
 10fcbd5:	movzbl (%rax),%eax
 10fcbd8:	test   %al,%al
 10fcbda:	je     10fcc18 <core.runtime.Runtime.submitSafeDestination+0xf88>
 10fcbdc:	lock incl 0x31d8(%r14)
 10fcbe4:	movzbl 0x31ec(%r14),%eax
 10fcbec:	test   $0x1,%al
 10fcbee:	jne    10fcbfb <core.runtime.Runtime.submitSafeDestination+0xf6b>
 10fcbf0:	mov    -0x60(%rbp),%rax
 10fcbf4:	movzbl (%rax),%eax
 10fcbf7:	test   %al,%al
 10fcbf9:	je     10fcc18 <core.runtime.Runtime.submitSafeDestination+0xf88>
 10fcbfb:	lea    0x31d8(%r14),%rsi
 10fcc02:	mov    -0x80(%rbp),%rax
 10fcc06:	mov    (%rax),%rdi
 10fcc09:	mov    -0x78(%rbp),%rax
 10fcc0d:	mov    (%rax),%rax
 10fcc10:	mov    $0xffffffff,%edx
 10fcc15:	call   *0x70(%rax)
 10fcc18:	cmp    $0x137,%ebx
 10fcc1e:	je     10fcc29 <core.runtime.Runtime.submitSafeDestination+0xf99>
 10fcc20:	cmp    $0x62,%ebx
 10fcc23:	jne    10fccc0 <core.runtime.Runtime.submitSafeDestination+0x1030>
 10fcc29:	mov    -0x58(%rbp),%rax
 10fcc2d:	lock incq 0x60(%rax)
 10fcc32:	cmpb   $0x0,-0x84(%rbp)
 10fcc39:	jne    10fcdac <core.runtime.Runtime.submitSafeDestination+0x111c>
 10fcc3f:	mov    -0xa8(%rbp),%rcx
 10fcc46:	test   %rcx,%rcx
 10fcc49:	je     10fcd4d <core.runtime.Runtime.submitSafeDestination+0x10bd>
 10fcc4f:	mov    -0xc0(%rbp),%rax
 10fcc56:	testb  $0x1,0x2fd(%rax)
 10fcc5d:	je     10fcdac <core.runtime.Runtime.submitSafeDestination+0x111c>
 10fcc63:	mov    0x150(%rax),%rdx
 10fcc6a:	mov    %rdx,%rsi
 10fcc6d:	shr    $0x2,%rsi
 10fcc71:	xor    %rsi,%rcx
 10fcc74:	and    $0x3,%edx
 10fcc77:	or     %rcx,%rdx
 10fcc7a:	jne    10fcdac <core.runtime.Runtime.submitSafeDestination+0x111c>
 10fcc80:	mov    %fs:0xfffffffffffbb5a8,%rcx
 10fcc89:	test   %rcx,%rcx
 10fcc8c:	je     10fcdac <core.runtime.Runtime.submitSafeDestination+0x111c>
 10fcc92:	mov    0x148(%rax),%rdx
 10fcc99:	cmp    %rcx,%rdx
 10fcc9c:	jne    10fcdac <core.runtime.Runtime.submitSafeDestination+0x111c>
 10fcca2:	mov    0x160(%rax),%edx
 10fcca8:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fccb1:	jne    10fcd31 <core.runtime.Runtime.submitSafeDestination+0x10a1>
 10fccb3:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fccbb:	jmp    10fcd49 <core.runtime.Runtime.submitSafeDestination+0x10b9>
 10fccc0:	mov    %r14,%rdi
 10fccc3:	mov    %ebx,%esi
 10fccc5:	call   10fd800 <core.runtime.Runtime.reportError>
 10fccca:	lea    -0xc0(%rbp),%rdi
 10fccd1:	call   10fd9c0 <journal.journal.Reservation.abort>
 10fccd6:	mov    %bx,(%r15)
 10fccda:	jmp    10fbf9c <core.runtime.Runtime.submitSafeDestination+0x30c>
 10fccdf:	mov    -0x30(%rbp),%rcx
 10fcce3:	mov    %ax,(%rcx)
 10fcce6:	jmp    10fbf9c <core.runtime.Runtime.submitSafeDestination+0x30c>
 10fcceb:	mov    -0x30(%rbp),%rcx
 10fccef:	mov    %ax,(%rcx)
 10fccf2:	jmp    10fbf9c <core.runtime.Runtime.submitSafeDestination+0x30c>
 10fccf7:	mov    $0xba,%eax
 10fccfc:	syscall
 10fccfe:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fcd06:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fcd0f:	cmp    %eax,%edx
 10fcd11:	jne    10fcbc3 <core.runtime.Runtime.submitSafeDestination+0xf33>
 10fcd17:	mov    -0xc0(%rbp),%r13
 10fcd1e:	mov    -0xb8(%rbp),%rdx
 10fcd25:	mov    -0xb0(%rbp),%r14
 10fcd2c:	jmp    10fcb72 <core.runtime.Runtime.submitSafeDestination+0xee2>
 10fcd31:	mov    $0xba,%eax
 10fcd36:	syscall
 10fcd38:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fcd40:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fcd49:	cmp    %eax,%edx
 10fcd4b:	jne    10fcdac <core.runtime.Runtime.submitSafeDestination+0x111c>
 10fcd4d:	mov    -0xc0(%rbp),%rax
 10fcd54:	mov    -0xb8(%rbp),%rcx
 10fcd5b:	mov    0x1a0(%rax),%rdx
 10fcd62:	mov    0x200(%rax),%rsi
 10fcd69:	imul   -0xb0(%rbp),%rsi
 10fcd71:	lea    0x1(,%rcx,4),%rax
 10fcd79:	lea    0x3(,%rcx,4),%rcx
 10fcd81:	lock cmpxchg %rcx,0x1000(%rdx,%rsi,1)
 10fcd8b:	setne  -0x150(%rbp)
 10fcd92:	jne    10fcdac <core.runtime.Runtime.submitSafeDestination+0x111c>
 10fcd94:	cmpq   $0x0,-0xa8(%rbp)
 10fcd9c:	je     10fcdac <core.runtime.Runtime.submitSafeDestination+0x111c>
 10fcd9e:	mov    -0xc0(%rbp),%rax
 10fcda5:	decq   0x158(%rax)
 10fcdac:	mov    -0x8ac5e(%rip),%eax        # 1072154 <__anon_33693>
 10fcdb2:	jmp    10fbf99 <core.runtime.Runtime.submitSafeDestination+0x309>
 10fcdb7:	and    $0x3,%eax
 10fcdba:	cmp    $0x1,%eax
 10fcdbd:	mov    -0x58(%rbp),%rax
 10fcdc1:	jne    10fd0be <core.runtime.Runtime.submitSafeDestination+0x142e>
 10fcdc7:	lock incq 0x58(%rax)
 10fcdcc:	mov    -0x8ac16(%rip),%eax        # 10721bc <__anon_33638>
 10fcdd2:	jmp    10fbf99 <core.runtime.Runtime.submitSafeDestination+0x309>
 10fcdd7:	mov    $0xba,%eax
 10fcddc:	syscall
 10fcdde:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fcde6:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fcdef:	cmp    %eax,%edx
 10fcdf1:	jne    10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fcdf7:	cmpb   $0x0,-0x88(%rbp)
 10fcdfe:	mov    -0xc0(%rbp),%r15
 10fce05:	je     10fce31 <core.runtime.Runtime.submitSafeDestination+0x11a1>
 10fce07:	cmpb   $0x0,0x288(%r15)
 10fce0f:	je     10fceb4 <core.runtime.Runtime.submitSafeDestination+0x1224>
 10fce15:	lea    -0xa0(%rbp),%rsi
 10fce1c:	lea    0x208(%r15),%rdi
 10fce23:	call   11326a0 <journal.schema.Registry.validateReady>
 10fce28:	test   %ax,%ax
 10fce2b:	jne    10fd2f0 <core.runtime.Runtime.submitSafeDestination+0x1660>
 10fce31:	mov    $0x13d,%r13w
 10fce36:	cmp    0x1f8(%r15),%rbx
 10fce3d:	ja     10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fce3f:	mov    0x200(%r15),%r8
 10fce46:	imul   -0xb0(%rbp),%r8
 10fce4e:	mov    0x1a0(%r15),%r9
 10fce55:	mov    0x1000(%r9,%r8,1),%rax
 10fce5d:	mov    -0xb8(%rbp),%rcx
 10fce64:	lea    0x1(,%rcx,4),%rdx
 10fce6c:	mov    $0x13c,%r13w
 10fce71:	cmp    %rdx,%rax
 10fce74:	jne    10fceb9 <core.runtime.Runtime.submitSafeDestination+0x1229>
 10fce76:	mov    -0xc0(%rbp),%r15
 10fce7d:	mov    -0xb0(%rbp),%rsi
 10fce84:	mov    0x200(%r15),%r12
 10fce8b:	imul   %rsi,%r12
 10fce8f:	add    0x1a0(%r15),%r12
 10fce96:	mov    0x1f0(%r15),%rdi
 10fce9d:	lea    -0x1(%rcx),%rax
 10fcea1:	mov    %rax,%rdx
 10fcea4:	or     %rdi,%rdx
 10fcea7:	shr    $0x20,%rdx
 10fceab:	je     10fcede <core.runtime.Runtime.submitSafeDestination+0x124e>
 10fcead:	xor    %edx,%edx
 10fceaf:	div    %rdi
 10fceb2:	jmp    10fcee2 <core.runtime.Runtime.submitSafeDestination+0x1252>
 10fceb4:	mov    $0x90,%r13w
 10fceb9:	mov    0xb8(%r12),%eax
 10fcec1:	test   %rax,%rax
 10fcec4:	je     10fd304 <core.runtime.Runtime.submitSafeDestination+0x1674>
 10fceca:	shl    $0x6,%rax
 10fcece:	mov    -0x68(%rbp),%rcx
 10fced2:	add    %rax,%rcx
 10fced5:	add    $0xffffffffffffffc0,%rcx
 10fced9:	jmp    10fd30f <core.runtime.Runtime.submitSafeDestination+0x167f>
 10fcede:	xor    %edx,%edx
 10fcee0:	div    %edi
 10fcee2:	cmpl   $0x1,0x2f0(%r15)
 10fceea:	je     10fcf42 <core.runtime.Runtime.submitSafeDestination+0x12b2>
 10fceec:	mov    -0xa0(%rbp),%edi
 10fcef2:	movzwl -0x9c(%rbp),%edx
 10fcef9:	vxorps %xmm0,%xmm0,%xmm0
 10fcefd:	cmpb   $0x0,-0x88(%rbp)
 10fcf04:	vmovups %xmm0,0x1020(%r12)
 10fcf0e:	movq   $0x0,0x1030(%r12)
 10fcf1a:	je     10fcf42 <core.runtime.Runtime.submitSafeDestination+0x12b2>
 10fcf1c:	mov    %edi,0x1020(%r12)
 10fcf24:	lea    -0x9a(%rbp),%rdi
 10fcf2b:	mov    %dx,0x1024(%r12)
 10fcf34:	vmovups (%rdi),%xmm0
 10fcf38:	vmovups %xmm0,0x1028(%r12)
 10fcf42:	lea    0x0(,%rcx,4),%r13
 10fcf4a:	mov    %ebx,0x1018(%r12)
 10fcf52:	xor    %edx,%edx
 10fcf54:	cmpb   $0x0,0x2fc(%r15)
 10fcf5c:	je     10fd02c <core.runtime.Runtime.submitSafeDestination+0x139c>
 10fcf62:	mov    %r9,-0x48(%rbp)
 10fcf66:	mov    %r8,-0x68(%rbp)
 10fcf6a:	inc    %rax
 10fcf6d:	mov    0x1a0(%r15),%rdx
 10fcf74:	imul   0x200(%r15),%rsi
 10fcf7c:	add    %rsi,%rdx
 10fcf7f:	add    $0x1040,%rdx
 10fcf86:	mov    %rdx,-0x60(%rbp)
 10fcf8a:	cmpl   $0x1,0x2f0(%r15)
 10fcf92:	jne    10fcfc1 <core.runtime.Runtime.submitSafeDestination+0x1331>
 10fcf94:	mov    %rcx,-0x150(%rbp)
 10fcf9b:	mov    %rax,-0x148(%rbp)
 10fcfa2:	mov    %ebx,-0x140(%rbp)
 10fcfa8:	movl   $0xffffffff,-0x3c(%rbp)
 10fcfaf:	lea    -0x3c(%rbp),%rdi
 10fcfb3:	lea    -0x150(%rbp),%rsi
 10fcfba:	mov    $0x14,%edx
 10fcfbf:	jmp    10fd00a <core.runtime.Runtime.submitSafeDestination+0x137a>
 10fcfc1:	lea    0x1020(%r12),%rdx
 10fcfc9:	mov    %rdx,-0x38(%rbp)
 10fcfcd:	mov    %rcx,-0x150(%rbp)
 10fcfd4:	mov    %rax,-0x148(%rbp)
 10fcfdb:	mov    %ebx,-0x140(%rbp)
 10fcfe1:	movl   $0xffffffff,-0x3c(%rbp)
 10fcfe8:	lea    -0x3c(%rbp),%rdi
 10fcfec:	lea    -0x150(%rbp),%rsi
 10fcff3:	mov    $0x14,%edx
 10fcff8:	call   113d030 <platform.crc32.Crc32.update>
 10fcffd:	mov    $0x18,%edx
 10fd002:	lea    -0x3c(%rbp),%rdi
 10fd006:	mov    -0x38(%rbp),%rsi
 10fd00a:	call   113d030 <platform.crc32.Crc32.update>
 10fd00f:	lea    -0x3c(%rbp),%rdi
 10fd013:	mov    -0x60(%rbp),%rsi
 10fd017:	mov    %rbx,%rdx
 10fd01a:	call   113d030 <platform.crc32.Crc32.update>
 10fd01f:	mov    -0x3c(%rbp),%edx
 10fd022:	not    %edx
 10fd024:	mov    -0x68(%rbp),%r8
 10fd028:	mov    -0x48(%rbp),%r9
 10fd02c:	mov    %edx,0x101c(%r12)
 10fd034:	or     $0x2,%r13
 10fd038:	mov    %r13,0x1000(%r9,%r8,1)
 10fd040:	cmpq   $0x0,-0xa8(%rbp)
 10fd048:	je     10fd051 <core.runtime.Runtime.submitSafeDestination+0x13c1>
 10fd04a:	decq   0x158(%r15)
 10fd051:	movb   $0x1,-0x84(%rbp)
 10fd058:	mov    -0x58(%rbp),%rax
 10fd05c:	lock incq (%rax)
 10fd060:	mov    -0x50(%rbp),%rdi
 10fd064:	call   10f5890 <core.runtime.Runtime.notify>
 10fd069:	lea    -0xc0(%rbp),%rdi
 10fd070:	call   10fd9c0 <journal.journal.Reservation.abort>
 10fd075:	mov    -0x8af33(%rip),%eax        # 1072148 <__anon_23525>
 10fd07b:	mov    %eax,(%r14)
 10fd07e:	jmp    10fbf9c <core.runtime.Runtime.submitSafeDestination+0x30c>
 10fd083:	and    $0x3,%eax
 10fd086:	cmp    $0x1,%eax
 10fd089:	mov    -0x30(%rbp),%r15
 10fd08d:	mov    -0x58(%rbp),%rax
 10fd091:	je     10fcdc7 <core.runtime.Runtime.submitSafeDestination+0x1137>
 10fd097:	mov    $0x1066d08,%edx
 10fd09c:	mov    $0x1066dc8,%eax
 10fd0a1:	mov    %rax,-0xf8(%rbp)
 10fd0a8:	jmp    10fd0c5 <core.runtime.Runtime.submitSafeDestination+0x1435>
 10fd0aa:	and    $0x3,%eax
 10fd0ad:	cmp    $0x1,%eax
 10fd0b0:	mov    -0x30(%rbp),%r15
 10fd0b4:	mov    -0x58(%rbp),%rax
 10fd0b8:	je     10fcdc7 <core.runtime.Runtime.submitSafeDestination+0x1137>
 10fd0be:	lea    -0x300(%rbp),%rdx
 10fd0c5:	mov    -0xf8(%rbp),%rax
 10fd0cc:	cmpb   $0x0,(%rax)
 10fd0cf:	mov    -0x50(%rbp),%rbx
 10fd0d3:	je     10fd1f6 <core.runtime.Runtime.submitSafeDestination+0x1566>
 10fd0d9:	vmovups 0xa0(%rdx),%ymm0
 10fd0e1:	vmovups %ymm0,-0x5f0(%rbp)
 10fd0e9:	vmovups 0x80(%rdx),%ymm0
 10fd0f1:	vmovups %ymm0,-0x610(%rbp)
 10fd0f9:	vmovups (%rdx),%ymm0
 10fd0fd:	vmovups 0x20(%rdx),%ymm1
 10fd102:	vmovups 0x40(%rdx),%ymm2
 10fd107:	vmovups 0x60(%rdx),%ymm3
 10fd10c:	vmovups %ymm3,-0x630(%rbp)
 10fd114:	vmovups %ymm2,-0x650(%rbp)
 10fd11c:	vmovups %ymm1,-0x670(%rbp)
 10fd124:	vmovups %ymm0,-0x690(%rbp)
 10fd12c:	mov    -0x70(%rbp),%rax
 10fd130:	cmpb   $0x0,0x50(%rax)
 10fd134:	je     10fd158 <core.runtime.Runtime.submitSafeDestination+0x14c8>
 10fd136:	mov    0x48(%rax),%rcx
 10fd13a:	lea    -0x170(%rbp),%rdi
 10fd141:	mov    %r12,%rsi
 10fd144:	vzeroupper
 10fd147:	call   110c940 <core.reference_encoding.sizeMeasured>
 10fd14c:	movzwl -0x168(%rbp),%eax
 10fd153:	jmp    10fd1ed <core.runtime.Runtime.submitSafeDestination+0x155d>
 10fd158:	vmovups 0xc0(%r12),%ymm0
 10fd162:	vmovups %ymm0,-0x790(%rbp)
 10fd16a:	vmovups 0xa0(%r12),%ymm0
 10fd174:	vmovups %ymm0,-0x7b0(%rbp)
 10fd17c:	vmovups 0x80(%r12),%ymm0
 10fd186:	vmovups %ymm0,-0x7d0(%rbp)
 10fd18e:	vmovups (%r12),%ymm0
 10fd194:	vmovups 0x20(%r12),%ymm1
 10fd19b:	vmovups 0x40(%r12),%ymm2
 10fd1a2:	vmovups 0x60(%r12),%ymm3
 10fd1a9:	vmovups %ymm3,-0x7f0(%rbp)
 10fd1b1:	vmovups %ymm2,-0x810(%rbp)
 10fd1b9:	vmovups %ymm1,-0x830(%rbp)
 10fd1c1:	vmovups %ymm0,-0x850(%rbp)
 10fd1c9:	lea    -0x180(%rbp),%rdi
 10fd1d0:	lea    -0x850(%rbp),%rsi
 10fd1d7:	lea    -0x690(%rbp),%rdx
 10fd1de:	vzeroupper
 10fd1e1:	call   1100aa0 <core.schema_codec.encodedReferenceSize>
 10fd1e6:	movzwl -0x178(%rbp),%eax
 10fd1ed:	test   %ax,%ax
 10fd1f0:	jne    10fbf88 <core.runtime.Runtime.submitSafeDestination+0x2f8>
 10fd1f6:	vmovups 0x98(%r12),%ymm0
 10fd200:	vmovups %ymm0,-0x478(%rbp)
 10fd208:	vmovups 0x80(%r12),%ymm0
 10fd212:	vmovups %ymm0,-0x490(%rbp)
 10fd21a:	vmovups (%r12),%ymm0
 10fd220:	vmovups 0x20(%r12),%ymm1
 10fd227:	vmovups 0x40(%r12),%ymm2
 10fd22e:	vmovups 0x60(%r12),%ymm3
 10fd235:	vmovups %ymm3,-0x4b0(%rbp)
 10fd23d:	vmovups %ymm2,-0x4d0(%rbp)
 10fd245:	vmovups %ymm1,-0x4f0(%rbp)
 10fd24d:	vmovups %ymm0,-0x510(%rbp)
 10fd255:	mov    0xdc(%r12),%eax
 10fd25d:	mov    $0x80000000,%ecx
 10fd262:	or     0xb8(%r12),%ecx
 10fd26a:	mov    %eax,-0x434(%rbp)
 10fd270:	vmovups 0xbc(%r12),%ymm0
 10fd27a:	vmovups %ymm0,-0x454(%rbp)
 10fd282:	mov    %ecx,-0x458(%rbp)
 10fd288:	lea    -0x100(%rbp),%rdi
 10fd28f:	lea    -0x510(%rbp),%rdx
 10fd296:	mov    %rbx,%rsi
 10fd299:	mov    -0x68(%rbp),%rcx
 10fd29d:	vzeroupper
 10fd2a0:	call   1100810 <core.runtime.Runtime.submitSync>
 10fd2a5:	mov    -0x100(%rbp),%eax
 10fd2ab:	jmp    10fbf99 <core.runtime.Runtime.submitSafeDestination+0x309>
 10fd2b0:	mov    -0x58(%rbp),%rax
 10fd2b4:	lock incq 0x68(%rax)
 10fd2b9:	mov    -0x30(%rbp),%r15
 10fd2bd:	jmp    10fd2e5 <core.runtime.Runtime.submitSafeDestination+0x1655>
 10fd2bf:	mov    -0x30(%rbp),%r15
 10fd2c3:	mov    -0x38(%rbp),%rbx
 10fd2c7:	xor    %ecx,%ecx
 10fd2c9:	xchg   %cl,(%rbx)
 10fd2cb:	jmp    10fbf88 <core.runtime.Runtime.submitSafeDestination+0x2f8>
 10fd2d0:	mov    -0x30(%rbp),%r15
 10fd2d4:	mov    -0x58(%rbp),%rcx
 10fd2d8:	mov    -0x38(%rbp),%rbx
 10fd2dc:	lock incq 0x68(%rcx)
 10fd2e1:	xor    %eax,%eax
 10fd2e3:	xchg   %al,(%rbx)
 10fd2e5:	mov    -0x8b17b(%rip),%eax        # 1072170 <__anon_33662>
 10fd2eb:	jmp    10fbf99 <core.runtime.Runtime.submitSafeDestination+0x309>
 10fd2f0:	mov    %eax,%r13d
 10fd2f3:	mov    0xb8(%r12),%eax
 10fd2fb:	test   %rax,%rax
 10fd2fe:	jne    10fceca <core.runtime.Runtime.submitSafeDestination+0x123a>
 10fd304:	mov    -0x68(%rbp),%rcx
 10fd308:	add    $0x9810,%rcx
 10fd30f:	lock decq (%rcx)
 10fd313:	lea    -0xc0(%rbp),%rdi
 10fd31a:	call   10fd9c0 <journal.journal.Reservation.abort>
 10fd31f:	mov    %r13w,(%r14)
 10fd323:	jmp    10fbf9c <core.runtime.Runtime.submitSafeDestination+0x30c>
