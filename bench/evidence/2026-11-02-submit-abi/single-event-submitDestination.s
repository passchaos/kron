
.zig-cache/submit-abi/single-event-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fd460 <core.runtime.Runtime.submitDestination>:
 10fd460:	push   %rbp
 10fd461:	mov    %rsp,%rbp
 10fd464:	push   %r15
 10fd466:	push   %r14
 10fd468:	push   %r13
 10fd46a:	push   %r12
 10fd46c:	push   %rbx
 10fd46d:	sub    $0x288,%rsp
 10fd474:	mov    0xb8(%rcx),%r11d
 10fd47b:	movzbl 0x10(%r9),%ebx
 10fd480:	test   %bl,%bl
 10fd482:	sete   %al
 10fd485:	test   %r11d,%r11d
 10fd488:	setne  %r10b
 10fd48c:	test   %r10b,%al
 10fd48f:	je     10fd49c <core.runtime.Runtime.submitDestination+0x3c>
 10fd491:	movl   $0xa1,(%rdi)
 10fd497:	jmp    10fd63d <core.runtime.Runtime.submitDestination+0x1dd>
 10fd49c:	mov    0x20(%rcx),%r13
 10fd4a0:	mov    0x28(%rcx),%r12
 10fd4a4:	mov    0x30(%rcx),%r14
 10fd4a8:	mov    0x38(%rcx),%r10
 10fd4ac:	test   %bl,%bl
 10fd4ae:	je     10fd4d6 <core.runtime.Runtime.submitDestination+0x76>
 10fd4b0:	mov    %r11d,%r11d
 10fd4b3:	test   %r11,%r11
 10fd4b6:	je     10fd491 <core.runtime.Runtime.submitDestination+0x31>
 10fd4b8:	mov    0x3148(%rsi),%rax
 10fd4bf:	test   %rax,%rax
 10fd4c2:	je     10fd4cf <core.runtime.Runtime.submitDestination+0x6f>
 10fd4c4:	mov    0x40(%rax),%rbx
 10fd4c8:	cmp    %r11,%rbx
 10fd4cb:	jb     10fd491 <core.runtime.Runtime.submitDestination+0x31>
 10fd4cd:	jmp    10fd4d6 <core.runtime.Runtime.submitDestination+0x76>
 10fd4cf:	xor    %ebx,%ebx
 10fd4d1:	cmp    %r11,%rbx
 10fd4d4:	jb     10fd491 <core.runtime.Runtime.submitDestination+0x31>
 10fd4d6:	mov    %r14,-0x38(%rbp)
 10fd4da:	mov    0x10(%rdx),%r14
 10fd4de:	mov    0x18(%rdx),%r11
 10fd4e2:	mov    %fs:0xfffffffffffbb5d8,%rbx
 10fd4eb:	lea    (%rbx,%rbx,4),%rax
 10fd4ef:	shl    $0x4,%rax
 10fd4f3:	mov    %fs:0x0,%r15
 10fd4fc:	add    %r15,%rax
 10fd4ff:	add    $0xfffffffffffba1b0,%rax
 10fd505:	inc    %rbx
 10fd508:	nopl   0x0(%rax,%rax,1)
 10fd510:	dec    %rbx
 10fd513:	je     10fd638 <core.runtime.Runtime.submitDestination+0x1d8>
 10fd519:	lea    -0x50(%rax),%r15
 10fd51d:	cmp    %rsi,-0x58(%rax)
 10fd521:	mov    %r15,%rax
 10fd524:	jne    10fd510 <core.runtime.Runtime.submitDestination+0xb0>
 10fd526:	mov    (%r15),%rbx
 10fd529:	test   %rbx,%rbx
 10fd52c:	je     10fd638 <core.runtime.Runtime.submitDestination+0x1d8>
 10fd532:	cmp    %r14,0x7430(%rbx)
 10fd539:	jne    10fd638 <core.runtime.Runtime.submitDestination+0x1d8>
 10fd53f:	cmp    %r11,0x7438(%rbx)
 10fd546:	jne    10fd638 <core.runtime.Runtime.submitDestination+0x1d8>
 10fd54c:	vmovups 0xc0(%rcx),%ymm0
 10fd554:	vmovups %ymm0,-0x1f0(%rbp)
 10fd55c:	vmovups 0xa0(%rcx),%ymm0
 10fd564:	vmovups %ymm0,-0x210(%rbp)
 10fd56c:	vmovups 0x80(%rcx),%ymm0
 10fd574:	vmovups %ymm0,-0x230(%rbp)
 10fd57c:	vmovups (%rcx),%ymm0
 10fd580:	vmovups 0x20(%rcx),%ymm1
 10fd585:	vmovups 0x40(%rcx),%ymm2
 10fd58a:	vmovups 0x60(%rcx),%ymm3
 10fd58f:	vmovups %ymm3,-0x250(%rbp)
 10fd597:	vmovups %ymm2,-0x270(%rbp)
 10fd59f:	vmovups %ymm1,-0x290(%rbp)
 10fd5a7:	vmovups %ymm0,-0x2b0(%rbp)
 10fd5af:	mov    0x7498(%rbx),%r14
 10fd5b6:	test   %r14,%r14
 10fd5b9:	mov    %rdi,-0x30(%rbp)
 10fd5bd:	je     10fd64f <core.runtime.Runtime.submitDestination+0x1ef>
 10fd5c3:	mov    %rdx,-0x58(%rbp)
 10fd5c7:	mov    %r8,-0x60(%rbp)
 10fd5cb:	mov    %r9,-0x48(%rbp)
 10fd5cf:	mov    %rsi,-0x50(%rbp)
 10fd5d3:	vxorps %xmm0,%xmm0,%xmm0
 10fd5d7:	vmovups %ymm0,-0x160(%rbp)
 10fd5df:	vmovups %ymm0,-0x170(%rbp)
 10fd5e7:	vmovups %ymm0,-0x190(%rbp)
 10fd5ef:	vmovups %ymm0,-0x1b0(%rbp)
 10fd5f7:	vmovups %ymm0,-0x1d0(%rbp)
 10fd5ff:	lea    -0x1d0(%rbp),%rdi
 10fd606:	mov    -0x38(%rbp),%rsi
 10fd60a:	mov    %r10,%rdx
 10fd60d:	vzeroupper
 10fd610:	call   1116aa0 <core.field.ValueValidator.fields>
 10fd615:	test   %ax,%ax
 10fd618:	jne    10fd62f <core.runtime.Runtime.submitDestination+0x1cf>
 10fd61a:	mov    $0x100,%ecx
 10fd61f:	sub    -0x1d0(%rbp),%rcx
 10fd626:	mov    $0x9f,%ax
 10fd62a:	cmp    %rcx,%r12
 10fd62d:	jbe    10fd69a <core.runtime.Runtime.submitDestination+0x23a>
 10fd62f:	mov    -0x30(%rbp),%rcx
 10fd633:	mov    %ax,(%rcx)
 10fd636:	jmp    10fd63d <core.runtime.Runtime.submitDestination+0x1dd>
 10fd638:	movw   $0x136,(%rdi)
 10fd63d:	add    $0x288,%rsp
 10fd644:	pop    %rbx
 10fd645:	pop    %r12
 10fd647:	pop    %r13
 10fd649:	pop    %r14
 10fd64b:	pop    %r15
 10fd64d:	pop    %rbp
 10fd64e:	ret
 10fd64f:	mov    %r14,-0x38(%rbp)
 10fd653:	mov    %rdx,%r14
 10fd656:	mov    %r8,%r15
 10fd659:	mov    %r9,%r12
 10fd65c:	mov    %rsi,%r13
 10fd65f:	mov    0x10(%rbp),%rax
 10fd663:	cmpb   $0x0,0x18(%rax)
 10fd667:	je     10fd6f6 <core.runtime.Runtime.submitDestination+0x296>
 10fd66d:	lea    -0x70(%rbp),%rdi
 10fd671:	mov    %rcx,%rsi
 10fd674:	vzeroupper
 10fd677:	call   110f9a0 <core.reference_encoding.measureValues>
 10fd67c:	movzwl -0x68(%rbp),%eax
 10fd680:	test   %ax,%ax
 10fd683:	jne    10fd62f <core.runtime.Runtime.submitDestination+0x1cf>
 10fd685:	mov    -0x70(%rbp),%rax
 10fd689:	mov    %rax,-0x80(%rbp)
 10fd68d:	movb   $0x1,-0x78(%rbp)
 10fd691:	lea    -0x80(%rbp),%rax
 10fd695:	jmp    10fd734 <core.runtime.Runtime.submitDestination+0x2d4>
 10fd69a:	mov    %r14,-0x38(%rbp)
 10fd69e:	test   %r12,%r12
 10fd6a1:	je     10fd6df <core.runtime.Runtime.submitDestination+0x27f>
 10fd6a3:	lea    -0x1d0(%rbp),%r14
 10fd6aa:	lea    -0x140(%rbp),%r15
 10fd6b1:	vmovups 0x0(%r13),%ymm0
 10fd6b7:	vmovups %ymm0,-0x140(%rbp)
 10fd6bf:	mov    %r14,%rdi
 10fd6c2:	mov    %r15,%rsi
 10fd6c5:	vzeroupper
 10fd6c8:	call   1108a00 <core.field.ValueValidator.valueWith__anon_34916>
 10fd6cd:	test   %ax,%ax
 10fd6d0:	jne    10fd62f <core.runtime.Runtime.submitDestination+0x1cf>
 10fd6d6:	add    $0x30,%r13
 10fd6da:	dec    %r12
 10fd6dd:	jne    10fd6b1 <core.runtime.Runtime.submitDestination+0x251>
 10fd6df:	mov    $0x1071b90,%eax
 10fd6e4:	mov    -0x50(%rbp),%rsi
 10fd6e8:	mov    -0x48(%rbp),%r12
 10fd6ec:	mov    -0x60(%rbp),%r15
 10fd6f0:	mov    -0x58(%rbp),%r14
 10fd6f4:	jmp    10fd737 <core.runtime.Runtime.submitDestination+0x2d7>
 10fd6f6:	lea    -0x90(%rbp),%rdi
 10fd6fd:	mov    %rcx,%rsi
 10fd700:	vzeroupper
 10fd703:	call   110f500 <core.codec.measure>
 10fd708:	movzwl -0x88(%rbp),%eax
 10fd70f:	test   %ax,%ax
 10fd712:	jne    10fd62f <core.runtime.Runtime.submitDestination+0x1cf>
 10fd718:	mov    -0x90(%rbp),%rax
 10fd71f:	mov    %rax,-0xa0(%rbp)
 10fd726:	movb   $0x1,-0x98(%rbp)
 10fd72d:	lea    -0xa0(%rbp),%rax
 10fd734:	mov    %r13,%rsi
 10fd737:	vmovups (%r14),%ymm0
 10fd73c:	vmovups %ymm0,-0x120(%rbp)
 10fd744:	mov    %rbx,-0x100(%rbp)
 10fd74b:	mov    %r15,-0xf8(%rbp)
 10fd752:	mov    0x10(%r12),%rcx
 10fd757:	mov    %rcx,-0xe0(%rbp)
 10fd75e:	vmovups (%r12),%xmm0
 10fd764:	vmovaps %xmm0,-0xf0(%rbp)
 10fd76c:	mov    0x10(%rbp),%rcx
 10fd770:	vmovups (%rcx),%xmm0
 10fd774:	vmovups 0xc(%rcx),%xmm1
 10fd779:	vmovups %xmm1,-0xbc(%rbp)
 10fd781:	cmpq   $0x0,-0x38(%rbp)
 10fd786:	vmovups %xmm0,-0xc8(%rbp)
 10fd78e:	vmovups (%rax),%xmm0
 10fd792:	vmovups %xmm0,-0xd8(%rbp)
 10fd79a:	sete   -0xac(%rbp)
 10fd7a1:	cmpq   $0x0,0x7498(%rbx)
 10fd7a9:	je     10fd7d4 <core.runtime.Runtime.submitDestination+0x374>
 10fd7ab:	add    $0x7498,%rbx
 10fd7b2:	lea    -0x3c(%rbp),%rdi
 10fd7b6:	lea    -0x2b0(%rbp),%rcx
 10fd7bd:	lea    -0x120(%rbp),%r8
 10fd7c4:	mov    %rbx,%rdx
 10fd7c7:	vzeroupper
 10fd7ca:	call   10fd330 <core.runtime_redaction.submit__anon_33520>
 10fd7cf:	mov    -0x3c(%rbp),%ecx
 10fd7d2:	jmp    10fd7f1 <core.runtime.Runtime.submitDestination+0x391>
 10fd7d4:	lea    -0x40(%rbp),%rdi
 10fd7d8:	lea    -0x2b0(%rbp),%rdx
 10fd7df:	lea    -0x120(%rbp),%rcx
 10fd7e6:	vzeroupper
 10fd7e9:	call   10fbc90 <core.runtime.Runtime.submitSafeDestination>
 10fd7ee:	mov    -0x40(%rbp),%ecx
 10fd7f1:	mov    -0x30(%rbp),%rax
 10fd7f5:	mov    %ecx,(%rax)
 10fd7f7:	jmp    10fd63d <core.runtime.Runtime.submitDestination+0x1dd>
