
.zig-cache/submit-abi/before-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fd7f0 <core.runtime_redaction.submit__anon_33520>:
 10fd7f0:	push   %rbp
 10fd7f1:	mov    %rsp,%rbp
 10fd7f4:	push   %r15
 10fd7f6:	push   %r14
 10fd7f8:	push   %r13
 10fd7fa:	push   %r12
 10fd7fc:	push   %rbx
 10fd7fd:	sub    $0xa1f8,%rsp
 10fd804:	mov    %r8,%r15
 10fd807:	mov    %rdx,%r12
 10fd80a:	mov    %rsi,-0x48(%rbp)
 10fd80e:	mov    %rdi,%r14
 10fd811:	mov    0x20(%rcx),%r13
 10fd815:	mov    0x28(%rcx),%rbx
 10fd819:	mov    0x30(%rcx),%rdx
 10fd81d:	mov    0x38(%rcx),%rax
 10fd821:	vmovups (%rcx),%ymm0
 10fd825:	vmovups %ymm0,-0x140(%rbp)
 10fd82d:	vmovups 0xc0(%rcx),%ymm0
 10fd835:	vmovups %ymm0,-0xa0(%rbp)
 10fd83d:	vmovups 0x40(%rcx),%ymm0
 10fd842:	vmovups 0x60(%rcx),%ymm1
 10fd847:	vmovups 0x80(%rcx),%ymm2
 10fd84f:	vmovups 0xa0(%rcx),%ymm3
 10fd857:	vmovups %ymm3,-0xc0(%rbp)
 10fd85f:	vmovups %ymm2,-0xe0(%rbp)
 10fd867:	vmovups %ymm1,-0x100(%rbp)
 10fd86f:	vmovups %ymm0,-0x120(%rbp)
 10fd877:	lea    -0x60(%rbp),%rdi
 10fd87b:	lea    -0x7220(%rbp),%r8
 10fd882:	lea    -0x2220(%rbp),%r9
 10fd889:	mov    %r12,%rsi
 10fd88c:	mov    %rax,%rcx
 10fd88f:	vzeroupper
 10fd892:	call   110e800 <pipeline.redact.Redactor.applyDeep>
 10fd897:	movzwl -0x50(%rbp),%eax
 10fd89b:	test   %ax,%ax
 10fd89e:	jne    10fd992 <core.runtime_redaction.submit__anon_33520+0x1a2>
 10fd8a4:	mov    %r15,-0x40(%rbp)
 10fd8a8:	mov    %r14,-0x38(%rbp)
 10fd8ac:	mov    -0x60(%rbp),%r14
 10fd8b0:	mov    -0x58(%rbp),%r15
 10fd8b4:	lea    -0x78(%rbp),%rdi
 10fd8b8:	lea    -0xa220(%rbp),%r8
 10fd8bf:	lea    -0x4220(%rbp),%r9
 10fd8c6:	mov    %r12,%rsi
 10fd8c9:	mov    %r13,%rdx
 10fd8cc:	mov    %rbx,%rcx
 10fd8cf:	call   110ed40 <pipeline.redact.Redactor.applyArgumentsDeep>
 10fd8d4:	movzwl -0x68(%rbp),%eax
 10fd8d8:	test   %ax,%ax
 10fd8db:	jne    10fd998 <core.runtime_redaction.submit__anon_33520+0x1a8>
 10fd8e1:	vmovups -0x78(%rbp),%xmm0
 10fd8e6:	vmovups -0x140(%rbp),%ymm1
 10fd8ee:	vmovups %ymm1,-0x220(%rbp)
 10fd8f6:	vmovaps %xmm0,-0x200(%rbp)
 10fd8fe:	mov    %r14,-0x1f0(%rbp)
 10fd905:	mov    %r15,-0x1e8(%rbp)
 10fd90c:	vmovups -0x120(%rbp),%ymm0
 10fd914:	vmovups -0x100(%rbp),%ymm1
 10fd91c:	vmovups -0xe0(%rbp),%ymm2
 10fd924:	vmovups %ymm0,-0x1e0(%rbp)
 10fd92c:	vmovups %ymm1,-0x1c0(%rbp)
 10fd934:	vmovups %ymm2,-0x1a0(%rbp)
 10fd93c:	vmovups -0xc0(%rbp),%ymm0
 10fd944:	vmovups %ymm0,-0x180(%rbp)
 10fd94c:	vmovups -0xa0(%rbp),%ymm0
 10fd954:	vmovups %ymm0,-0x160(%rbp)
 10fd95c:	lea    -0x2c(%rbp),%rdi
 10fd960:	lea    -0x220(%rbp),%rdx
 10fd967:	mov    -0x48(%rbp),%rsi
 10fd96b:	mov    -0x40(%rbp),%rcx
 10fd96f:	vzeroupper
 10fd972:	call   10fbc70 <core.runtime.Runtime.submitSafeDestination>
 10fd977:	mov    -0x2c(%rbp),%eax
 10fd97a:	mov    -0x38(%rbp),%rcx
 10fd97e:	mov    %eax,(%rcx)
 10fd980:	add    $0xa1f8,%rsp
 10fd987:	pop    %rbx
 10fd988:	pop    %r12
 10fd98a:	pop    %r13
 10fd98c:	pop    %r14
 10fd98e:	pop    %r15
 10fd990:	pop    %rbp
 10fd991:	ret
 10fd992:	mov    %ax,(%r14)
 10fd996:	jmp    10fd980 <core.runtime_redaction.submit__anon_33520+0x190>
 10fd998:	mov    -0x38(%rbp),%rcx
 10fd99c:	mov    %ax,(%rcx)
 10fd99f:	jmp    10fd980 <core.runtime_redaction.submit__anon_33520+0x190>
