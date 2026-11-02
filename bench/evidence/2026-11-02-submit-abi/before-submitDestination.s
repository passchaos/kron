
.zig-cache/submit-abi/before-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fd9b0 <core.runtime.Runtime.submitDestination>:
 10fd9b0:	push   %rbp
 10fd9b1:	mov    %rsp,%rbp
 10fd9b4:	push   %r15
 10fd9b6:	push   %r14
 10fd9b8:	push   %r13
 10fd9ba:	push   %r12
 10fd9bc:	push   %rbx
 10fd9bd:	sub    $0x3d8,%rsp
 10fd9c4:	mov    0xb8(%rcx),%r11d
 10fd9cb:	movzbl 0x10(%r9),%ebx
 10fd9d0:	test   %bl,%bl
 10fd9d2:	sete   %al
 10fd9d5:	test   %r11d,%r11d
 10fd9d8:	setne  %r10b
 10fd9dc:	test   %r10b,%al
 10fd9df:	je     10fd9ec <core.runtime.Runtime.submitDestination+0x3c>
 10fd9e1:	movl   $0xa1,(%rdi)
 10fd9e7:	jmp    10fdb32 <core.runtime.Runtime.submitDestination+0x182>
 10fd9ec:	mov    0x20(%rcx),%r13
 10fd9f0:	mov    0x28(%rcx),%r15
 10fd9f4:	mov    0x30(%rcx),%r14
 10fd9f8:	mov    0x38(%rcx),%r10
 10fd9fc:	test   %bl,%bl
 10fd9fe:	je     10fda26 <core.runtime.Runtime.submitDestination+0x76>
 10fda00:	mov    %r11d,%r11d
 10fda03:	test   %r11,%r11
 10fda06:	je     10fd9e1 <core.runtime.Runtime.submitDestination+0x31>
 10fda08:	mov    0x3148(%rsi),%rax
 10fda0f:	test   %rax,%rax
 10fda12:	je     10fda1f <core.runtime.Runtime.submitDestination+0x6f>
 10fda14:	mov    0x40(%rax),%rbx
 10fda18:	cmp    %r11,%rbx
 10fda1b:	jb     10fd9e1 <core.runtime.Runtime.submitDestination+0x31>
 10fda1d:	jmp    10fda26 <core.runtime.Runtime.submitDestination+0x76>
 10fda1f:	xor    %ebx,%ebx
 10fda21:	cmp    %r11,%rbx
 10fda24:	jb     10fd9e1 <core.runtime.Runtime.submitDestination+0x31>
 10fda26:	mov    %r14,-0x40(%rbp)
 10fda2a:	mov    0x10(%rdx),%rbx
 10fda2e:	mov    0x18(%rdx),%r11
 10fda32:	mov    %fs:0xfffffffffffbb5d8,%r14
 10fda3b:	lea    (%r14,%r14,4),%rax
 10fda3f:	shl    $0x4,%rax
 10fda43:	mov    %fs:0x0,%r12
 10fda4c:	add    %r12,%rax
 10fda4f:	add    $0xfffffffffffba1b0,%rax
 10fda55:	inc    %r14
 10fda58:	nopl   0x0(%rax,%rax,1)
 10fda60:	dec    %r14
 10fda63:	je     10fdb2d <core.runtime.Runtime.submitDestination+0x17d>
 10fda69:	lea    -0x50(%rax),%r12
 10fda6d:	cmp    %rsi,-0x58(%rax)
 10fda71:	mov    %r12,%rax
 10fda74:	jne    10fda60 <core.runtime.Runtime.submitDestination+0xb0>
 10fda76:	mov    (%r12),%r12
 10fda7a:	test   %r12,%r12
 10fda7d:	je     10fdb2d <core.runtime.Runtime.submitDestination+0x17d>
 10fda83:	cmp    %rbx,0x7430(%r12)
 10fda8b:	jne    10fdb2d <core.runtime.Runtime.submitDestination+0x17d>
 10fda91:	cmp    %r11,0x7438(%r12)
 10fda99:	jne    10fdb2d <core.runtime.Runtime.submitDestination+0x17d>
 10fda9f:	mov    0x7498(%r12),%rbx
 10fdaa7:	test   %rbx,%rbx
 10fdaaa:	mov    %rdi,-0x38(%rbp)
 10fdaae:	mov    %rdx,-0x48(%rbp)
 10fdab2:	je     10fdb44 <core.runtime.Runtime.submitDestination+0x194>
 10fdab8:	mov    %r8,-0x68(%rbp)
 10fdabc:	mov    %r9,-0x70(%rbp)
 10fdac0:	mov    %rsi,-0x58(%rbp)
 10fdac4:	mov    %rcx,-0x60(%rbp)
 10fdac8:	vxorps %xmm0,%xmm0,%xmm0
 10fdacc:	vmovups %ymm0,-0xf0(%rbp)
 10fdad4:	vmovups %ymm0,-0x100(%rbp)
 10fdadc:	vmovups %ymm0,-0x120(%rbp)
 10fdae4:	vmovups %ymm0,-0x140(%rbp)
 10fdaec:	vmovups %ymm0,-0x160(%rbp)
 10fdaf4:	lea    -0x160(%rbp),%rdi
 10fdafb:	mov    -0x40(%rbp),%rsi
 10fdaff:	mov    %r10,%rdx
 10fdb02:	vzeroupper
 10fdb05:	call   11171e0 <core.field.ValueValidator.fields>
 10fdb0a:	test   %ax,%ax
 10fdb0d:	jne    10fdb24 <core.runtime.Runtime.submitDestination+0x174>
 10fdb0f:	mov    $0x100,%ecx
 10fdb14:	sub    -0x160(%rbp),%rcx
 10fdb1b:	mov    $0x9f,%ax
 10fdb1f:	cmp    %rcx,%r15
 10fdb22:	jbe    10fdb98 <core.runtime.Runtime.submitDestination+0x1e8>
 10fdb24:	mov    -0x38(%rbp),%rcx
 10fdb28:	mov    %ax,(%rcx)
 10fdb2b:	jmp    10fdb32 <core.runtime.Runtime.submitDestination+0x182>
 10fdb2d:	movw   $0x136,(%rdi)
 10fdb32:	add    $0x3d8,%rsp
 10fdb39:	pop    %rbx
 10fdb3a:	pop    %r12
 10fdb3c:	pop    %r13
 10fdb3e:	pop    %r14
 10fdb40:	pop    %r15
 10fdb42:	pop    %rbp
 10fdb43:	ret
 10fdb44:	mov    %rbx,-0x40(%rbp)
 10fdb48:	mov    %r8,%r14
 10fdb4b:	mov    %r9,%r15
 10fdb4e:	mov    %rsi,%r13
 10fdb51:	mov    0x10(%rbp),%rax
 10fdb55:	cmpb   $0x0,0xe8(%rax)
 10fdb5c:	je     10fdbf4 <core.runtime.Runtime.submitDestination+0x244>
 10fdb62:	lea    -0x80(%rbp),%rdi
 10fdb66:	mov    %rcx,%rbx
 10fdb69:	mov    %rcx,%rsi
 10fdb6c:	call   110ffc0 <core.reference_encoding.measureValues>
 10fdb71:	movzwl -0x78(%rbp),%eax
 10fdb75:	test   %ax,%ax
 10fdb78:	jne    10fdb24 <core.runtime.Runtime.submitDestination+0x174>
 10fdb7a:	mov    -0x80(%rbp),%rax
 10fdb7e:	mov    %rax,-0x90(%rbp)
 10fdb85:	movb   $0x1,-0x88(%rbp)
 10fdb8c:	lea    -0x90(%rbp),%rax
 10fdb93:	jmp    10fdc32 <core.runtime.Runtime.submitDestination+0x282>
 10fdb98:	mov    %rbx,-0x40(%rbp)
 10fdb9c:	test   %r15,%r15
 10fdb9f:	je     10fdbdd <core.runtime.Runtime.submitDestination+0x22d>
 10fdba1:	lea    -0x160(%rbp),%rbx
 10fdba8:	lea    -0xd0(%rbp),%r14
 10fdbaf:	vmovups 0x0(%r13),%ymm0
 10fdbb5:	vmovups %ymm0,-0xd0(%rbp)
 10fdbbd:	mov    %rbx,%rdi
 10fdbc0:	mov    %r14,%rsi
 10fdbc3:	vzeroupper
 10fdbc6:	call   1109020 <core.field.ValueValidator.valueWith__anon_34913>
 10fdbcb:	test   %ax,%ax
 10fdbce:	jne    10fdb24 <core.runtime.Runtime.submitDestination+0x174>
 10fdbd4:	add    $0x30,%r13
 10fdbd8:	dec    %r15
 10fdbdb:	jne    10fdbaf <core.runtime.Runtime.submitDestination+0x1ff>
 10fdbdd:	mov    $0x1071b70,%eax
 10fdbe2:	mov    -0x60(%rbp),%rcx
 10fdbe6:	mov    -0x58(%rbp),%rsi
 10fdbea:	mov    -0x70(%rbp),%r15
 10fdbee:	mov    -0x68(%rbp),%r14
 10fdbf2:	jmp    10fdc38 <core.runtime.Runtime.submitDestination+0x288>
 10fdbf4:	lea    -0xa0(%rbp),%rdi
 10fdbfb:	mov    %rcx,%rbx
 10fdbfe:	mov    %rcx,%rsi
 10fdc01:	call   110fb20 <core.codec.measure>
 10fdc06:	movzwl -0x98(%rbp),%eax
 10fdc0d:	test   %ax,%ax
 10fdc10:	jne    10fdb24 <core.runtime.Runtime.submitDestination+0x174>
 10fdc16:	mov    -0xa0(%rbp),%rax
 10fdc1d:	mov    %rax,-0xb0(%rbp)
 10fdc24:	movb   $0x1,-0xa8(%rbp)
 10fdc2b:	lea    -0xb0(%rbp),%rax
 10fdc32:	mov    %rbx,%rcx
 10fdc35:	mov    %r13,%rsi
 10fdc38:	mov    -0x48(%rbp),%rdi
 10fdc3c:	lea    0x7498(%r12),%rdx
 10fdc44:	cmpq   $0x0,-0x40(%rbp)
 10fdc49:	sete   -0x30(%rbp)
 10fdc4d:	cmpq   $0x0,(%rdx)
 10fdc51:	je     10fdd31 <core.runtime.Runtime.submitDestination+0x381>
 10fdc57:	vmovups (%rdi),%ymm0
 10fdc5b:	vmovups %ymm0,-0x2b0(%rbp)
 10fdc63:	mov    %r12,-0x290(%rbp)
 10fdc6a:	mov    %r14,-0x288(%rbp)
 10fdc71:	mov    0x10(%r15),%rdi
 10fdc75:	mov    %rdi,-0x270(%rbp)
 10fdc7c:	vmovups (%r15),%xmm0
 10fdc81:	vmovaps %xmm0,-0x280(%rbp)
 10fdc89:	mov    0x10(%rbp),%rdi
 10fdc8d:	vmovups (%rdi),%ymm0
 10fdc91:	vmovups 0x20(%rdi),%ymm1
 10fdc96:	vmovups 0x40(%rdi),%ymm2
 10fdc9b:	vmovups 0x60(%rdi),%ymm3
 10fdca0:	vmovups %ymm0,-0x268(%rbp)
 10fdca8:	vmovups %ymm1,-0x248(%rbp)
 10fdcb0:	vmovups %ymm2,-0x228(%rbp)
 10fdcb8:	vmovups %ymm3,-0x208(%rbp)
 10fdcc0:	vmovups 0x80(%rdi),%ymm0
 10fdcc8:	vmovups %ymm0,-0x1e8(%rbp)
 10fdcd0:	vmovups 0xa0(%rdi),%ymm0
 10fdcd8:	vmovups %ymm0,-0x1c8(%rbp)
 10fdce0:	vmovups 0xc0(%rdi),%ymm0
 10fdce8:	vmovups %ymm0,-0x1a8(%rbp)
 10fdcf0:	vmovups 0xd0(%rdi),%ymm0
 10fdcf8:	vmovups %ymm0,-0x198(%rbp)
 10fdd00:	vmovups (%rax),%xmm0
 10fdd04:	vmovups %xmm0,-0x178(%rbp)
 10fdd0c:	movzbl -0x30(%rbp),%eax
 10fdd10:	mov    %al,-0x168(%rbp)
 10fdd16:	lea    -0x4c(%rbp),%rdi
 10fdd1a:	lea    -0x2b0(%rbp),%r8
 10fdd21:	vzeroupper
 10fdd24:	call   10fd7f0 <core.runtime_redaction.submit__anon_33520>
 10fdd29:	mov    -0x4c(%rbp),%ecx
 10fdd2c:	jmp    10fde0c <core.runtime.Runtime.submitDestination+0x45c>
 10fdd31:	vmovups (%rdi),%ymm0
 10fdd35:	vmovups %ymm0,-0x400(%rbp)
 10fdd3d:	mov    %r12,-0x3e0(%rbp)
 10fdd44:	mov    %r14,-0x3d8(%rbp)
 10fdd4b:	mov    0x10(%r15),%rdx
 10fdd4f:	mov    %rdx,-0x3c0(%rbp)
 10fdd56:	vmovups (%r15),%xmm0
 10fdd5b:	vmovaps %xmm0,-0x3d0(%rbp)
 10fdd63:	mov    0x10(%rbp),%rdx
 10fdd67:	vmovups (%rdx),%ymm0
 10fdd6b:	vmovups 0x20(%rdx),%ymm1
 10fdd70:	vmovups 0x40(%rdx),%ymm2
 10fdd75:	vmovups 0x60(%rdx),%ymm3
 10fdd7a:	vmovups %ymm0,-0x3b8(%rbp)
 10fdd82:	vmovups %ymm1,-0x398(%rbp)
 10fdd8a:	vmovups %ymm2,-0x378(%rbp)
 10fdd92:	vmovups %ymm3,-0x358(%rbp)
 10fdd9a:	vmovups 0x80(%rdx),%ymm0
 10fdda2:	vmovups %ymm0,-0x338(%rbp)
 10fddaa:	vmovups 0xa0(%rdx),%ymm0
 10fddb2:	vmovups %ymm0,-0x318(%rbp)
 10fddba:	vmovups 0xc0(%rdx),%ymm0
 10fddc2:	vmovups %ymm0,-0x2f8(%rbp)
 10fddca:	vmovups 0xd0(%rdx),%ymm0
 10fddd2:	vmovups %ymm0,-0x2e8(%rbp)
 10fddda:	vmovups (%rax),%xmm0
 10fddde:	vmovups %xmm0,-0x2c8(%rbp)
 10fdde6:	movzbl -0x30(%rbp),%eax
 10fddea:	mov    %al,-0x2b8(%rbp)
 10fddf0:	lea    -0x50(%rbp),%rdi
 10fddf4:	lea    -0x400(%rbp),%rax
 10fddfb:	mov    %rcx,%rdx
 10fddfe:	mov    %rax,%rcx
 10fde01:	vzeroupper
 10fde04:	call   10fbc70 <core.runtime.Runtime.submitSafeDestination>
 10fde09:	mov    -0x50(%rbp),%ecx
 10fde0c:	mov    -0x38(%rbp),%rax
 10fde10:	mov    %ecx,(%rax)
 10fde12:	jmp    10fdb32 <core.runtime.Runtime.submitDestination+0x182>
