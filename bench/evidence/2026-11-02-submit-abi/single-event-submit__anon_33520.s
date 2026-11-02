
.zig-cache/submit-abi/single-event-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fd330 <core.runtime_redaction.submit__anon_33520>:
 10fd330:	push   %rbp
 10fd331:	mov    %rsp,%rbp
 10fd334:	push   %r15
 10fd336:	push   %r14
 10fd338:	push   %r13
 10fd33a:	push   %r12
 10fd33c:	push   %rbx
 10fd33d:	sub    $0xa118,%rsp
 10fd344:	mov    %rcx,%r12
 10fd347:	vmovups 0xc0(%rcx),%ymm0
 10fd34f:	vmovups %ymm0,-0x80(%rbp)
 10fd354:	vmovups 0xa0(%rcx),%ymm0
 10fd35c:	vmovups %ymm0,-0xa0(%rbp)
 10fd364:	mov    %r8,%r14
 10fd367:	mov    %rdx,%r13
 10fd36a:	mov    %rsi,%r15
 10fd36d:	mov    %rdi,%rbx
 10fd370:	vmovups 0x80(%rcx),%ymm0
 10fd378:	vmovups %ymm0,-0xc0(%rbp)
 10fd380:	vmovups (%rcx),%ymm0
 10fd384:	vmovups 0x20(%rcx),%ymm1
 10fd389:	vmovups 0x40(%rcx),%ymm2
 10fd38e:	vmovups 0x60(%rcx),%ymm3
 10fd393:	vmovups %ymm3,-0xe0(%rbp)
 10fd39b:	vmovups %ymm2,-0x100(%rbp)
 10fd3a3:	vmovups %ymm1,-0x120(%rbp)
 10fd3ab:	vmovups %ymm0,-0x140(%rbp)
 10fd3b3:	mov    0x30(%rcx),%rdx
 10fd3b7:	mov    0x38(%rcx),%rcx
 10fd3bb:	lea    -0x48(%rbp),%rdi
 10fd3bf:	lea    -0x7140(%rbp),%r8
 10fd3c6:	lea    -0x2140(%rbp),%r9
 10fd3cd:	mov    %r13,%rsi
 10fd3d0:	vzeroupper
 10fd3d3:	call   110e1e0 <pipeline.redact.Redactor.applyDeep>
 10fd3d8:	movzwl -0x38(%rbp),%eax
 10fd3dc:	test   %ax,%ax
 10fd3df:	jne    10fd455 <core.runtime_redaction.submit__anon_33520+0x125>
 10fd3e1:	vmovups -0x48(%rbp),%xmm0
 10fd3e6:	vmovaps %xmm0,-0x110(%rbp)
 10fd3ee:	mov    0x20(%r12),%rdx
 10fd3f3:	mov    0x28(%r12),%rcx
 10fd3f8:	lea    -0x60(%rbp),%rdi
 10fd3fc:	lea    -0xa140(%rbp),%r8
 10fd403:	lea    -0x4140(%rbp),%r9
 10fd40a:	mov    %r13,%rsi
 10fd40d:	call   110e720 <pipeline.redact.Redactor.applyArgumentsDeep>
 10fd412:	movzwl -0x50(%rbp),%eax
 10fd416:	test   %ax,%ax
 10fd419:	jne    10fd455 <core.runtime_redaction.submit__anon_33520+0x125>
 10fd41b:	vmovups -0x60(%rbp),%xmm0
 10fd420:	vmovaps %xmm0,-0x120(%rbp)
 10fd428:	lea    -0x2c(%rbp),%rdi
 10fd42c:	lea    -0x140(%rbp),%rdx
 10fd433:	mov    %r15,%rsi
 10fd436:	mov    %r14,%rcx
 10fd439:	call   10fbc90 <core.runtime.Runtime.submitSafeDestination>
 10fd43e:	mov    -0x2c(%rbp),%eax
 10fd441:	mov    %eax,(%rbx)
 10fd443:	add    $0xa118,%rsp
 10fd44a:	pop    %rbx
 10fd44b:	pop    %r12
 10fd44d:	pop    %r13
 10fd44f:	pop    %r14
 10fd451:	pop    %r15
 10fd453:	pop    %rbp
 10fd454:	ret
 10fd455:	mov    %ax,(%rbx)
 10fd458:	jmp    10fd443 <core.runtime_redaction.submit__anon_33520+0x113>
