
.zig-cache/submit-abi/ref-only-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fd790 <core.runtime_redaction.submit__anon_33520>:
 10fd790:	push   %rbp
 10fd791:	mov    %rsp,%rbp
 10fd794:	push   %r15
 10fd796:	push   %r14
 10fd798:	push   %r13
 10fd79a:	push   %r12
 10fd79c:	push   %rbx
 10fd79d:	sub    $0xa118,%rsp
 10fd7a4:	mov    %rcx,%r12
 10fd7a7:	vmovups 0xc0(%rcx),%ymm0
 10fd7af:	vmovups %ymm0,-0x80(%rbp)
 10fd7b4:	vmovups 0xa0(%rcx),%ymm0
 10fd7bc:	vmovups %ymm0,-0xa0(%rbp)
 10fd7c4:	mov    %r8,%r14
 10fd7c7:	mov    %rdx,%r13
 10fd7ca:	mov    %rsi,%r15
 10fd7cd:	mov    %rdi,%rbx
 10fd7d0:	vmovups 0x80(%rcx),%ymm0
 10fd7d8:	vmovups %ymm0,-0xc0(%rbp)
 10fd7e0:	vmovups (%rcx),%ymm0
 10fd7e4:	vmovups 0x20(%rcx),%ymm1
 10fd7e9:	vmovups 0x40(%rcx),%ymm2
 10fd7ee:	vmovups 0x60(%rcx),%ymm3
 10fd7f3:	vmovups %ymm3,-0xe0(%rbp)
 10fd7fb:	vmovups %ymm2,-0x100(%rbp)
 10fd803:	vmovups %ymm1,-0x120(%rbp)
 10fd80b:	vmovups %ymm0,-0x140(%rbp)
 10fd813:	mov    0x30(%rcx),%rdx
 10fd817:	mov    0x38(%rcx),%rcx
 10fd81b:	lea    -0x48(%rbp),%rdi
 10fd81f:	lea    -0x7140(%rbp),%r8
 10fd826:	lea    -0x2140(%rbp),%r9
 10fd82d:	mov    %r13,%rsi
 10fd830:	vzeroupper
 10fd833:	call   110e650 <pipeline.redact.Redactor.applyDeep>
 10fd838:	movzwl -0x38(%rbp),%eax
 10fd83c:	test   %ax,%ax
 10fd83f:	jne    10fd8b5 <core.runtime_redaction.submit__anon_33520+0x125>
 10fd841:	vmovups -0x48(%rbp),%xmm0
 10fd846:	vmovaps %xmm0,-0x110(%rbp)
 10fd84e:	mov    0x20(%r12),%rdx
 10fd853:	mov    0x28(%r12),%rcx
 10fd858:	lea    -0x60(%rbp),%rdi
 10fd85c:	lea    -0xa140(%rbp),%r8
 10fd863:	lea    -0x4140(%rbp),%r9
 10fd86a:	mov    %r13,%rsi
 10fd86d:	call   110eb90 <pipeline.redact.Redactor.applyArgumentsDeep>
 10fd872:	movzwl -0x50(%rbp),%eax
 10fd876:	test   %ax,%ax
 10fd879:	jne    10fd8b5 <core.runtime_redaction.submit__anon_33520+0x125>
 10fd87b:	vmovups -0x60(%rbp),%xmm0
 10fd880:	vmovaps %xmm0,-0x120(%rbp)
 10fd888:	lea    -0x2c(%rbp),%rdi
 10fd88c:	lea    -0x140(%rbp),%rdx
 10fd893:	mov    %r15,%rsi
 10fd896:	mov    %r14,%rcx
 10fd899:	call   10fbc90 <core.runtime.Runtime.submitSafeDestination>
 10fd89e:	mov    -0x2c(%rbp),%eax
 10fd8a1:	mov    %eax,(%rbx)
 10fd8a3:	add    $0xa118,%rsp
 10fd8aa:	pop    %rbx
 10fd8ab:	pop    %r12
 10fd8ad:	pop    %r13
 10fd8af:	pop    %r14
 10fd8b1:	pop    %r15
 10fd8b3:	pop    %rbp
 10fd8b4:	ret
 10fd8b5:	mov    %ax,(%rbx)
 10fd8b8:	jmp    10fd8a3 <core.runtime_redaction.submit__anon_33520+0x113>
