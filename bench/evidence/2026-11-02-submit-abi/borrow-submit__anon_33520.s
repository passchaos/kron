
.zig-cache/submit-abi/after-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fd810 <core.runtime_redaction.submit__anon_33520>:
 10fd810:	push   %rbp
 10fd811:	mov    %rsp,%rbp
 10fd814:	push   %r15
 10fd816:	push   %r14
 10fd818:	push   %r13
 10fd81a:	push   %r12
 10fd81c:	push   %rbx
 10fd81d:	sub    $0xa118,%rsp
 10fd824:	mov    %rcx,%r12
 10fd827:	vmovups 0xc0(%rcx),%ymm0
 10fd82f:	vmovups %ymm0,-0x80(%rbp)
 10fd834:	vmovups 0xa0(%rcx),%ymm0
 10fd83c:	vmovups %ymm0,-0xa0(%rbp)
 10fd844:	mov    %r8,%r14
 10fd847:	mov    %rdx,%r13
 10fd84a:	mov    %rsi,%r15
 10fd84d:	mov    %rdi,%rbx
 10fd850:	vmovups 0x80(%rcx),%ymm0
 10fd858:	vmovups %ymm0,-0xc0(%rbp)
 10fd860:	vmovups (%rcx),%ymm0
 10fd864:	vmovups 0x20(%rcx),%ymm1
 10fd869:	vmovups 0x40(%rcx),%ymm2
 10fd86e:	vmovups 0x60(%rcx),%ymm3
 10fd873:	vmovups %ymm3,-0xe0(%rbp)
 10fd87b:	vmovups %ymm2,-0x100(%rbp)
 10fd883:	vmovups %ymm1,-0x120(%rbp)
 10fd88b:	vmovups %ymm0,-0x140(%rbp)
 10fd893:	mov    0x30(%rcx),%rdx
 10fd897:	mov    0x38(%rcx),%rcx
 10fd89b:	lea    -0x48(%rbp),%rdi
 10fd89f:	lea    -0x7140(%rbp),%r8
 10fd8a6:	lea    -0x2140(%rbp),%r9
 10fd8ad:	mov    %r13,%rsi
 10fd8b0:	vzeroupper
 10fd8b3:	call   110e730 <pipeline.redact.Redactor.applyDeep>
 10fd8b8:	movzwl -0x38(%rbp),%eax
 10fd8bc:	test   %ax,%ax
 10fd8bf:	jne    10fd935 <core.runtime_redaction.submit__anon_33520+0x125>
 10fd8c1:	vmovups -0x48(%rbp),%xmm0
 10fd8c6:	vmovaps %xmm0,-0x110(%rbp)
 10fd8ce:	mov    0x20(%r12),%rdx
 10fd8d3:	mov    0x28(%r12),%rcx
 10fd8d8:	lea    -0x60(%rbp),%rdi
 10fd8dc:	lea    -0xa140(%rbp),%r8
 10fd8e3:	lea    -0x4140(%rbp),%r9
 10fd8ea:	mov    %r13,%rsi
 10fd8ed:	call   110ec70 <pipeline.redact.Redactor.applyArgumentsDeep>
 10fd8f2:	movzwl -0x50(%rbp),%eax
 10fd8f6:	test   %ax,%ax
 10fd8f9:	jne    10fd935 <core.runtime_redaction.submit__anon_33520+0x125>
 10fd8fb:	vmovups -0x60(%rbp),%xmm0
 10fd900:	vmovaps %xmm0,-0x120(%rbp)
 10fd908:	lea    -0x2c(%rbp),%rdi
 10fd90c:	lea    -0x140(%rbp),%rdx
 10fd913:	mov    %r15,%rsi
 10fd916:	mov    %r14,%rcx
 10fd919:	call   10fbc70 <core.runtime.Runtime.submitSafeDestination>
 10fd91e:	mov    -0x2c(%rbp),%eax
 10fd921:	mov    %eax,(%rbx)
 10fd923:	add    $0xa118,%rsp
 10fd92a:	pop    %rbx
 10fd92b:	pop    %r12
 10fd92d:	pop    %r13
 10fd92f:	pop    %r14
 10fd931:	pop    %r15
 10fd933:	pop    %rbp
 10fd934:	ret
 10fd935:	mov    %ax,(%rbx)
 10fd938:	jmp    10fd923 <core.runtime_redaction.submit__anon_33520+0x113>
