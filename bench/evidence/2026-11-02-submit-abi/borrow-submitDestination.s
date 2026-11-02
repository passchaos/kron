
.zig-cache/submit-abi/after-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fd940 <core.runtime.Runtime.submitDestination>:
 10fd940:	push   %rbp
 10fd941:	mov    %rsp,%rbp
 10fd944:	push   %r15
 10fd946:	push   %r14
 10fd948:	push   %r13
 10fd94a:	push   %r12
 10fd94c:	push   %rbx
 10fd94d:	sub    $0x358,%rsp
 10fd954:	vmovups 0xc0(%rcx),%ymm0
 10fd95c:	vmovups %ymm0,-0xc0(%rbp)
 10fd964:	vmovups 0xa0(%rcx),%ymm0
 10fd96c:	vmovups %ymm0,-0xe0(%rbp)
 10fd974:	vmovups 0x80(%rcx),%ymm0
 10fd97c:	vmovups %ymm0,-0x100(%rbp)
 10fd984:	vmovups (%rcx),%ymm0
 10fd988:	vmovups 0x20(%rcx),%ymm1
 10fd98d:	vmovups 0x40(%rcx),%ymm2
 10fd992:	vmovups 0x60(%rcx),%ymm3
 10fd997:	vmovups %ymm3,-0x120(%rbp)
 10fd99f:	vmovups %ymm2,-0x140(%rbp)
 10fd9a7:	vmovups %ymm1,-0x160(%rbp)
 10fd9af:	vmovups %ymm0,-0x180(%rbp)
 10fd9b7:	movzbl 0x10(%r9),%eax
 10fd9bc:	test   %al,%al
 10fd9be:	sete   %r11b
 10fd9c2:	mov    -0xc8(%rbp),%r10d
 10fd9c9:	test   %r10d,%r10d
 10fd9cc:	setne  %bl
 10fd9cf:	test   %bl,%r11b
 10fd9d2:	je     10fd9df <core.runtime.Runtime.submitDestination+0x9f>
 10fd9d4:	movl   $0xa1,(%rdi)
 10fd9da:	jmp    10fdb18 <core.runtime.Runtime.submitDestination+0x1d8>
 10fd9df:	test   %al,%al
 10fd9e1:	je     10fda0a <core.runtime.Runtime.submitDestination+0xca>
 10fd9e3:	mov    %r10d,%eax
 10fd9e6:	test   %rax,%rax
 10fd9e9:	je     10fd9d4 <core.runtime.Runtime.submitDestination+0x94>
 10fd9eb:	mov    0x3148(%rsi),%r10
 10fd9f2:	test   %r10,%r10
 10fd9f5:	je     10fda02 <core.runtime.Runtime.submitDestination+0xc2>
 10fd9f7:	mov    0x40(%r10),%r10
 10fd9fb:	cmp    %rax,%r10
 10fd9fe:	jb     10fd9d4 <core.runtime.Runtime.submitDestination+0x94>
 10fda00:	jmp    10fda0a <core.runtime.Runtime.submitDestination+0xca>
 10fda02:	xor    %r10d,%r10d
 10fda05:	cmp    %rax,%r10
 10fda08:	jb     10fd9d4 <core.runtime.Runtime.submitDestination+0x94>
 10fda0a:	mov    0x10(%rbp),%r12
 10fda0e:	mov    0x10(%rdx),%r10
 10fda12:	mov    0x18(%rdx),%rax
 10fda16:	mov    %fs:0xfffffffffffbb5d8,%r11
 10fda1f:	lea    (%r11,%r11,4),%rbx
 10fda23:	shl    $0x4,%rbx
 10fda27:	mov    %fs:0x0,%r14
 10fda30:	add    %r14,%rbx
 10fda33:	add    $0xfffffffffffba1b0,%rbx
 10fda3a:	inc    %r11
 10fda3d:	nopl   (%rax)
 10fda40:	dec    %r11
 10fda43:	je     10fdb13 <core.runtime.Runtime.submitDestination+0x1d3>
 10fda49:	lea    -0x50(%rbx),%r14
 10fda4d:	cmp    %rsi,-0x58(%rbx)
 10fda51:	mov    %r14,%rbx
 10fda54:	jne    10fda40 <core.runtime.Runtime.submitDestination+0x100>
 10fda56:	mov    (%r14),%rbx
 10fda59:	test   %rbx,%rbx
 10fda5c:	je     10fdb13 <core.runtime.Runtime.submitDestination+0x1d3>
 10fda62:	cmp    %r10,0x7430(%rbx)
 10fda69:	jne    10fdb13 <core.runtime.Runtime.submitDestination+0x1d3>
 10fda6f:	cmp    %rax,0x7438(%rbx)
 10fda76:	jne    10fdb13 <core.runtime.Runtime.submitDestination+0x1d3>
 10fda7c:	mov    0x7498(%rbx),%r14
 10fda83:	test   %r14,%r14
 10fda86:	mov    %rdi,-0x30(%rbp)
 10fda8a:	mov    %rdx,-0x38(%rbp)
 10fda8e:	je     10fdb2d <core.runtime.Runtime.submitDestination+0x1ed>
 10fda94:	mov    %r8,-0x60(%rbp)
 10fda98:	mov    %r9,-0x50(%rbp)
 10fda9c:	mov    %rsi,-0x58(%rbp)
 10fdaa0:	vxorps %xmm0,%xmm0,%xmm0
 10fdaa4:	vmovups %ymm0,-0x1c0(%rbp)
 10fdaac:	vmovups %ymm0,-0x1d0(%rbp)
 10fdab4:	vmovups %ymm0,-0x1f0(%rbp)
 10fdabc:	vmovups %ymm0,-0x210(%rbp)
 10fdac4:	vmovups %ymm0,-0x230(%rbp)
 10fdacc:	mov    -0x150(%rbp),%rsi
 10fdad3:	mov    -0x148(%rbp),%rdx
 10fdada:	lea    -0x230(%rbp),%rdi
 10fdae1:	vzeroupper
 10fdae4:	call   1117110 <core.field.ValueValidator.fields>
 10fdae9:	test   %ax,%ax
 10fdaec:	jne    10fdb0a <core.runtime.Runtime.submitDestination+0x1ca>
 10fdaee:	mov    -0x158(%rbp),%r13
 10fdaf5:	mov    $0x100,%ecx
 10fdafa:	sub    -0x230(%rbp),%rcx
 10fdb01:	mov    $0x9f,%ax
 10fdb05:	cmp    %rcx,%r13
 10fdb08:	jbe    10fdb76 <core.runtime.Runtime.submitDestination+0x236>
 10fdb0a:	mov    -0x30(%rbp),%rcx
 10fdb0e:	mov    %ax,(%rcx)
 10fdb11:	jmp    10fdb18 <core.runtime.Runtime.submitDestination+0x1d8>
 10fdb13:	movw   $0x136,(%rdi)
 10fdb18:	add    $0x358,%rsp
 10fdb1f:	pop    %rbx
 10fdb20:	pop    %r12
 10fdb22:	pop    %r13
 10fdb24:	pop    %r14
 10fdb26:	pop    %r15
 10fdb28:	pop    %rbp
 10fdb29:	vzeroupper
 10fdb2c:	ret
 10fdb2d:	mov    %r14,-0x48(%rbp)
 10fdb31:	mov    %r8,%r15
 10fdb34:	mov    %r9,%r13
 10fdb37:	mov    %rsi,%r14
 10fdb3a:	cmpb   $0x0,0xe8(%r12)
 10fdb43:	je     10fdbdd <core.runtime.Runtime.submitDestination+0x29d>
 10fdb49:	lea    -0x70(%rbp),%rdi
 10fdb4d:	mov    %rcx,%rsi
 10fdb50:	vzeroupper
 10fdb53:	call   110fef0 <core.reference_encoding.measureValues>
 10fdb58:	movzwl -0x68(%rbp),%eax
 10fdb5c:	test   %ax,%ax
 10fdb5f:	jne    10fdb0a <core.runtime.Runtime.submitDestination+0x1ca>
 10fdb61:	mov    -0x70(%rbp),%rax
 10fdb65:	mov    %rax,-0x80(%rbp)
 10fdb69:	movb   $0x1,-0x78(%rbp)
 10fdb6d:	lea    -0x80(%rbp),%rax
 10fdb71:	jmp    10fdc1b <core.runtime.Runtime.submitDestination+0x2db>
 10fdb76:	mov    %r14,-0x48(%rbp)
 10fdb7a:	test   %r13,%r13
 10fdb7d:	je     10fdbc2 <core.runtime.Runtime.submitDestination+0x282>
 10fdb7f:	mov    -0x160(%rbp),%r12
 10fdb86:	lea    -0x230(%rbp),%r14
 10fdb8d:	lea    -0x1a0(%rbp),%r15
 10fdb94:	vmovups (%r12),%ymm0
 10fdb9a:	vmovups %ymm0,-0x1a0(%rbp)
 10fdba2:	mov    %r14,%rdi
 10fdba5:	mov    %r15,%rsi
 10fdba8:	vzeroupper
 10fdbab:	call   1108f50 <core.field.ValueValidator.valueWith__anon_34915>
 10fdbb0:	test   %ax,%ax
 10fdbb3:	jne    10fdb0a <core.runtime.Runtime.submitDestination+0x1ca>
 10fdbb9:	add    $0x30,%r12
 10fdbbd:	dec    %r13
 10fdbc0:	jne    10fdb94 <core.runtime.Runtime.submitDestination+0x254>
 10fdbc2:	mov    $0x1071b70,%eax
 10fdbc7:	mov    -0x58(%rbp),%rsi
 10fdbcb:	mov    -0x50(%rbp),%r13
 10fdbcf:	mov    -0x60(%rbp),%r15
 10fdbd3:	mov    -0x38(%rbp),%rcx
 10fdbd7:	mov    0x10(%rbp),%r12
 10fdbdb:	jmp    10fdc22 <core.runtime.Runtime.submitDestination+0x2e2>
 10fdbdd:	lea    -0x90(%rbp),%rdi
 10fdbe4:	mov    %rcx,%rsi
 10fdbe7:	vzeroupper
 10fdbea:	call   110fa50 <core.codec.measure>
 10fdbef:	movzwl -0x88(%rbp),%eax
 10fdbf6:	test   %ax,%ax
 10fdbf9:	jne    10fdb0a <core.runtime.Runtime.submitDestination+0x1ca>
 10fdbff:	mov    -0x90(%rbp),%rax
 10fdc06:	mov    %rax,-0xa0(%rbp)
 10fdc0d:	movb   $0x1,-0x98(%rbp)
 10fdc14:	lea    -0xa0(%rbp),%rax
 10fdc1b:	mov    %r14,%rsi
 10fdc1e:	mov    -0x38(%rbp),%rcx
 10fdc22:	vmovups (%rcx),%ymm0
 10fdc26:	vmovups %ymm0,-0x380(%rbp)
 10fdc2e:	mov    %rbx,-0x360(%rbp)
 10fdc35:	mov    %r15,-0x358(%rbp)
 10fdc3c:	mov    0x10(%r13),%rcx
 10fdc40:	mov    %rcx,-0x340(%rbp)
 10fdc47:	vmovups 0x0(%r13),%xmm0
 10fdc4d:	vmovaps %xmm0,-0x350(%rbp)
 10fdc55:	vmovups (%r12),%ymm0
 10fdc5b:	vmovups 0x20(%r12),%ymm1
 10fdc62:	vmovups 0x40(%r12),%ymm2
 10fdc69:	vmovups 0x60(%r12),%ymm3
 10fdc70:	vmovups %ymm0,-0x338(%rbp)
 10fdc78:	vmovups %ymm1,-0x318(%rbp)
 10fdc80:	vmovups %ymm2,-0x2f8(%rbp)
 10fdc88:	cmpq   $0x0,-0x48(%rbp)
 10fdc8d:	vmovups %ymm3,-0x2d8(%rbp)
 10fdc95:	vmovups 0x80(%r12),%ymm0
 10fdc9f:	vmovups %ymm0,-0x2b8(%rbp)
 10fdca7:	vmovups 0xa0(%r12),%ymm0
 10fdcb1:	vmovups %ymm0,-0x298(%rbp)
 10fdcb9:	vmovups 0xc0(%r12),%ymm0
 10fdcc3:	vmovups %ymm0,-0x278(%rbp)
 10fdccb:	vmovups 0xd0(%r12),%ymm0
 10fdcd5:	vmovups %ymm0,-0x268(%rbp)
 10fdcdd:	vmovups (%rax),%xmm0
 10fdce1:	vmovups %xmm0,-0x248(%rbp)
 10fdce9:	sete   -0x238(%rbp)
 10fdcf0:	cmpq   $0x0,0x7498(%rbx)
 10fdcf8:	je     10fdd23 <core.runtime.Runtime.submitDestination+0x3e3>
 10fdcfa:	add    $0x7498,%rbx
 10fdd01:	lea    -0x3c(%rbp),%rdi
 10fdd05:	lea    -0x180(%rbp),%rcx
 10fdd0c:	lea    -0x380(%rbp),%r8
 10fdd13:	mov    %rbx,%rdx
 10fdd16:	vzeroupper
 10fdd19:	call   10fd810 <core.runtime_redaction.submit__anon_33520>
 10fdd1e:	mov    -0x3c(%rbp),%ecx
 10fdd21:	jmp    10fdd40 <core.runtime.Runtime.submitDestination+0x400>
 10fdd23:	lea    -0x40(%rbp),%rdi
 10fdd27:	lea    -0x180(%rbp),%rdx
 10fdd2e:	lea    -0x380(%rbp),%rcx
 10fdd35:	vzeroupper
 10fdd38:	call   10fbc70 <core.runtime.Runtime.submitSafeDestination>
 10fdd3d:	mov    -0x40(%rbp),%ecx
 10fdd40:	mov    -0x30(%rbp),%rax
 10fdd44:	mov    %ecx,(%rax)
 10fdd46:	jmp    10fdb18 <core.runtime.Runtime.submitDestination+0x1d8>
