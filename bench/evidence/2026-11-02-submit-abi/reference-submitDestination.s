
.zig-cache/submit-abi/ref-only-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fd8c0 <core.runtime.Runtime.submitDestination>:
 10fd8c0:	push   %rbp
 10fd8c1:	mov    %rsp,%rbp
 10fd8c4:	push   %r15
 10fd8c6:	push   %r14
 10fd8c8:	push   %r13
 10fd8ca:	push   %r12
 10fd8cc:	push   %rbx
 10fd8cd:	sub    $0x288,%rsp
 10fd8d4:	vmovups 0xc0(%rcx),%ymm0
 10fd8dc:	vmovups %ymm0,-0x140(%rbp)
 10fd8e4:	vmovups 0xa0(%rcx),%ymm0
 10fd8ec:	vmovups %ymm0,-0x160(%rbp)
 10fd8f4:	vmovups 0x80(%rcx),%ymm0
 10fd8fc:	vmovups %ymm0,-0x180(%rbp)
 10fd904:	vmovups (%rcx),%ymm0
 10fd908:	vmovups 0x20(%rcx),%ymm1
 10fd90d:	vmovups 0x40(%rcx),%ymm2
 10fd912:	vmovups 0x60(%rcx),%ymm3
 10fd917:	vmovups %ymm3,-0x1a0(%rbp)
 10fd91f:	vmovups %ymm2,-0x1c0(%rbp)
 10fd927:	vmovups %ymm1,-0x1e0(%rbp)
 10fd92f:	vmovups %ymm0,-0x200(%rbp)
 10fd937:	movzbl 0x10(%r9),%eax
 10fd93c:	test   %al,%al
 10fd93e:	sete   %r11b
 10fd942:	mov    -0x148(%rbp),%r10d
 10fd949:	test   %r10d,%r10d
 10fd94c:	setne  %bl
 10fd94f:	test   %bl,%r11b
 10fd952:	je     10fd95f <core.runtime.Runtime.submitDestination+0x9f>
 10fd954:	movl   $0xa1,(%rdi)
 10fd95a:	jmp    10fda98 <core.runtime.Runtime.submitDestination+0x1d8>
 10fd95f:	test   %al,%al
 10fd961:	je     10fd98a <core.runtime.Runtime.submitDestination+0xca>
 10fd963:	mov    %r10d,%eax
 10fd966:	test   %rax,%rax
 10fd969:	je     10fd954 <core.runtime.Runtime.submitDestination+0x94>
 10fd96b:	mov    0x3148(%rsi),%r10
 10fd972:	test   %r10,%r10
 10fd975:	je     10fd982 <core.runtime.Runtime.submitDestination+0xc2>
 10fd977:	mov    0x40(%r10),%r10
 10fd97b:	cmp    %rax,%r10
 10fd97e:	jb     10fd954 <core.runtime.Runtime.submitDestination+0x94>
 10fd980:	jmp    10fd98a <core.runtime.Runtime.submitDestination+0xca>
 10fd982:	xor    %r10d,%r10d
 10fd985:	cmp    %rax,%r10
 10fd988:	jb     10fd954 <core.runtime.Runtime.submitDestination+0x94>
 10fd98a:	mov    0x10(%rbp),%r13
 10fd98e:	mov    0x10(%rdx),%r10
 10fd992:	mov    0x18(%rdx),%rax
 10fd996:	mov    %fs:0xfffffffffffbb5d8,%r11
 10fd99f:	lea    (%r11,%r11,4),%rbx
 10fd9a3:	shl    $0x4,%rbx
 10fd9a7:	mov    %fs:0x0,%r14
 10fd9b0:	add    %r14,%rbx
 10fd9b3:	add    $0xfffffffffffba1b0,%rbx
 10fd9ba:	inc    %r11
 10fd9bd:	nopl   (%rax)
 10fd9c0:	dec    %r11
 10fd9c3:	je     10fda93 <core.runtime.Runtime.submitDestination+0x1d3>
 10fd9c9:	lea    -0x50(%rbx),%r14
 10fd9cd:	cmp    %rsi,-0x58(%rbx)
 10fd9d1:	mov    %r14,%rbx
 10fd9d4:	jne    10fd9c0 <core.runtime.Runtime.submitDestination+0x100>
 10fd9d6:	mov    (%r14),%rbx
 10fd9d9:	test   %rbx,%rbx
 10fd9dc:	je     10fda93 <core.runtime.Runtime.submitDestination+0x1d3>
 10fd9e2:	cmp    %r10,0x7430(%rbx)
 10fd9e9:	jne    10fda93 <core.runtime.Runtime.submitDestination+0x1d3>
 10fd9ef:	cmp    %rax,0x7438(%rbx)
 10fd9f6:	jne    10fda93 <core.runtime.Runtime.submitDestination+0x1d3>
 10fd9fc:	mov    0x7498(%rbx),%r14
 10fda03:	test   %r14,%r14
 10fda06:	mov    %rdi,-0x30(%rbp)
 10fda0a:	mov    %rdx,-0x38(%rbp)
 10fda0e:	je     10fdaad <core.runtime.Runtime.submitDestination+0x1ed>
 10fda14:	mov    %r8,-0x60(%rbp)
 10fda18:	mov    %r9,-0x50(%rbp)
 10fda1c:	mov    %rsi,-0x58(%rbp)
 10fda20:	vxorps %xmm0,%xmm0,%xmm0
 10fda24:	vmovups %ymm0,-0x240(%rbp)
 10fda2c:	vmovups %ymm0,-0x250(%rbp)
 10fda34:	vmovups %ymm0,-0x270(%rbp)
 10fda3c:	vmovups %ymm0,-0x290(%rbp)
 10fda44:	vmovups %ymm0,-0x2b0(%rbp)
 10fda4c:	mov    -0x1d0(%rbp),%rsi
 10fda53:	mov    -0x1c8(%rbp),%rdx
 10fda5a:	lea    -0x2b0(%rbp),%rdi
 10fda61:	vzeroupper
 10fda64:	call   1116f10 <core.field.ValueValidator.fields>
 10fda69:	test   %ax,%ax
 10fda6c:	jne    10fda8a <core.runtime.Runtime.submitDestination+0x1ca>
 10fda6e:	mov    -0x1d8(%rbp),%r12
 10fda75:	mov    $0x100,%ecx
 10fda7a:	sub    -0x2b0(%rbp),%rcx
 10fda81:	mov    $0x9f,%ax
 10fda85:	cmp    %rcx,%r12
 10fda88:	jbe    10fdaf2 <core.runtime.Runtime.submitDestination+0x232>
 10fda8a:	mov    -0x30(%rbp),%rcx
 10fda8e:	mov    %ax,(%rcx)
 10fda91:	jmp    10fda98 <core.runtime.Runtime.submitDestination+0x1d8>
 10fda93:	movw   $0x136,(%rdi)
 10fda98:	add    $0x288,%rsp
 10fda9f:	pop    %rbx
 10fdaa0:	pop    %r12
 10fdaa2:	pop    %r13
 10fdaa4:	pop    %r14
 10fdaa6:	pop    %r15
 10fdaa8:	pop    %rbp
 10fdaa9:	vzeroupper
 10fdaac:	ret
 10fdaad:	mov    %r14,-0x48(%rbp)
 10fdab1:	mov    %r8,%r15
 10fdab4:	mov    %r9,%r12
 10fdab7:	mov    %rsi,%r14
 10fdaba:	cmpb   $0x0,0x18(%r13)
 10fdabf:	je     10fdb59 <core.runtime.Runtime.submitDestination+0x299>
 10fdac5:	lea    -0x70(%rbp),%rdi
 10fdac9:	mov    %rcx,%rsi
 10fdacc:	vzeroupper
 10fdacf:	call   110fe10 <core.reference_encoding.measureValues>
 10fdad4:	movzwl -0x68(%rbp),%eax
 10fdad8:	test   %ax,%ax
 10fdadb:	jne    10fda8a <core.runtime.Runtime.submitDestination+0x1ca>
 10fdadd:	mov    -0x70(%rbp),%rax
 10fdae1:	mov    %rax,-0x80(%rbp)
 10fdae5:	movb   $0x1,-0x78(%rbp)
 10fdae9:	lea    -0x80(%rbp),%rax
 10fdaed:	jmp    10fdb97 <core.runtime.Runtime.submitDestination+0x2d7>
 10fdaf2:	mov    %r14,-0x48(%rbp)
 10fdaf6:	test   %r12,%r12
 10fdaf9:	je     10fdb3e <core.runtime.Runtime.submitDestination+0x27e>
 10fdafb:	mov    -0x1e0(%rbp),%r13
 10fdb02:	lea    -0x2b0(%rbp),%r14
 10fdb09:	lea    -0x220(%rbp),%r15
 10fdb10:	vmovups 0x0(%r13),%ymm0
 10fdb16:	vmovups %ymm0,-0x220(%rbp)
 10fdb1e:	mov    %r14,%rdi
 10fdb21:	mov    %r15,%rsi
 10fdb24:	vzeroupper
 10fdb27:	call   1108e70 <core.field.ValueValidator.valueWith__anon_34914>
 10fdb2c:	test   %ax,%ax
 10fdb2f:	jne    10fda8a <core.runtime.Runtime.submitDestination+0x1ca>
 10fdb35:	add    $0x30,%r13
 10fdb39:	dec    %r12
 10fdb3c:	jne    10fdb10 <core.runtime.Runtime.submitDestination+0x250>
 10fdb3e:	mov    $0x1071b90,%eax
 10fdb43:	mov    -0x58(%rbp),%rsi
 10fdb47:	mov    -0x50(%rbp),%r12
 10fdb4b:	mov    -0x60(%rbp),%r15
 10fdb4f:	mov    -0x38(%rbp),%rcx
 10fdb53:	mov    0x10(%rbp),%r13
 10fdb57:	jmp    10fdb9e <core.runtime.Runtime.submitDestination+0x2de>
 10fdb59:	lea    -0x90(%rbp),%rdi
 10fdb60:	mov    %rcx,%rsi
 10fdb63:	vzeroupper
 10fdb66:	call   110f970 <core.codec.measure>
 10fdb6b:	movzwl -0x88(%rbp),%eax
 10fdb72:	test   %ax,%ax
 10fdb75:	jne    10fda8a <core.runtime.Runtime.submitDestination+0x1ca>
 10fdb7b:	mov    -0x90(%rbp),%rax
 10fdb82:	mov    %rax,-0xa0(%rbp)
 10fdb89:	movb   $0x1,-0x98(%rbp)
 10fdb90:	lea    -0xa0(%rbp),%rax
 10fdb97:	mov    %r14,%rsi
 10fdb9a:	mov    -0x38(%rbp),%rcx
 10fdb9e:	vmovups (%rcx),%ymm0
 10fdba2:	vmovups %ymm0,-0x120(%rbp)
 10fdbaa:	mov    %rbx,-0x100(%rbp)
 10fdbb1:	mov    %r15,-0xf8(%rbp)
 10fdbb8:	mov    0x10(%r12),%rcx
 10fdbbd:	mov    %rcx,-0xe0(%rbp)
 10fdbc4:	vmovups (%r12),%xmm0
 10fdbca:	vmovaps %xmm0,-0xf0(%rbp)
 10fdbd2:	vmovups 0x0(%r13),%xmm0
 10fdbd8:	vmovups 0xc(%r13),%xmm1
 10fdbde:	vmovups %xmm1,-0xbc(%rbp)
 10fdbe6:	cmpq   $0x0,-0x48(%rbp)
 10fdbeb:	vmovups %xmm0,-0xc8(%rbp)
 10fdbf3:	vmovups (%rax),%xmm0
 10fdbf7:	vmovups %xmm0,-0xd8(%rbp)
 10fdbff:	sete   -0xac(%rbp)
 10fdc06:	cmpq   $0x0,0x7498(%rbx)
 10fdc0e:	je     10fdc39 <core.runtime.Runtime.submitDestination+0x379>
 10fdc10:	add    $0x7498,%rbx
 10fdc17:	lea    -0x3c(%rbp),%rdi
 10fdc1b:	lea    -0x200(%rbp),%rcx
 10fdc22:	lea    -0x120(%rbp),%r8
 10fdc29:	mov    %rbx,%rdx
 10fdc2c:	vzeroupper
 10fdc2f:	call   10fd790 <core.runtime_redaction.submit__anon_33520>
 10fdc34:	mov    -0x3c(%rbp),%ecx
 10fdc37:	jmp    10fdc56 <core.runtime.Runtime.submitDestination+0x396>
 10fdc39:	lea    -0x40(%rbp),%rdi
 10fdc3d:	lea    -0x200(%rbp),%rdx
 10fdc44:	lea    -0x120(%rbp),%rcx
 10fdc4b:	vzeroupper
 10fdc4e:	call   10fbc90 <core.runtime.Runtime.submitSafeDestination>
 10fdc53:	mov    -0x40(%rbp),%ecx
 10fdc56:	mov    -0x30(%rbp),%rax
 10fdc5a:	mov    %ecx,(%rax)
 10fdc5c:	jmp    10fda98 <core.runtime.Runtime.submitDestination+0x1d8>
