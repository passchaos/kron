
/tmp/kron-decimal-probe-after:     file format elf64-x86-64


Disassembly of section .text:

000000000107bc20 <encoder.decimal.writeMagnitude__anon_30578>:
 107bc20:	55                   	push   %rbp
 107bc21:	48 89 e5             	mov    %rsp,%rbp
 107bc24:	41 57                	push   %r15
 107bc26:	41 56                	push   %r14
 107bc28:	41 55                	push   %r13
 107bc2a:	41 54                	push   %r12
 107bc2c:	53                   	push   %rbx
 107bc2d:	48 83 ec 58          	sub    $0x58,%rsp
 107bc31:	49 89 f5             	mov    %rsi,%r13
 107bc34:	49 bc c3 f5 28 5c 8f 	movabs $0x28f5c28f5c28f5c3,%r12
 107bc3b:	c2 f5 28 
 107bc3e:	48 85 d2             	test   %rdx,%rdx
 107bc41:	48 89 7d d0          	mov    %rdi,-0x30(%rbp)
 107bc45:	0f 84 2d 01 00 00    	je     107bd78 <encoder.decimal.writeMagnitude__anon_30578+0x158>
 107bc4b:	49 89 d7             	mov    %rdx,%r15
 107bc4e:	89 4d cc             	mov    %ecx,-0x34(%rbp)
 107bc51:	bb 28 00 00 00       	mov    $0x28,%ebx
 107bc56:	eb 4d                	jmp    107bca5 <encoder.decimal.writeMagnitude__anon_30578+0x85>
 107bc58:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 107bc5f:	00 
 107bc60:	48 8d 3c 2b          	lea    (%rbx,%rbp,1),%rdi
 107bc64:	48 83 c7 91          	add    $0xffffffffffffff91,%rdi
 107bc68:	48 83 c3 ed          	add    $0xffffffffffffffed,%rbx
 107bc6c:	48 29 d8             	sub    %rbx,%rax
 107bc6f:	be 30 00 00 00       	mov    $0x30,%esi
 107bc74:	48 89 c2             	mov    %rax,%rdx
 107bc77:	4d 89 c6             	mov    %r8,%r14
 107bc7a:	4d 89 d5             	mov    %r10,%r13
 107bc7d:	e8 ae 0b 01 00       	call   108c830 <compiler_rt.memset>
 107bc82:	4d 89 ea             	mov    %r13,%r10
 107bc85:	4d 89 f0             	mov    %r14,%r8
 107bc88:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 107bc8c:	4d 89 c5             	mov    %r8,%r13
 107bc8f:	48 b8 ff ff e7 89 04 	movabs $0x8ac7230489e7ffff,%rax
 107bc96:	23 c7 8a 
 107bc99:	49 39 c7             	cmp    %rax,%r15
 107bc9c:	4d 89 d7             	mov    %r10,%r15
 107bc9f:	0f 86 e9 00 00 00    	jbe    107bd8e <encoder.decimal.writeMagnitude__anon_30578+0x16e>
 107bca5:	49 89 de             	mov    %rbx,%r14
 107bca8:	4c 89 ef             	mov    %r13,%rdi
 107bcab:	4c 89 fe             	mov    %r15,%rsi
 107bcae:	48 bb 00 00 e8 89 04 	movabs $0x8ac7230489e80000,%rbx
 107bcb5:	23 c7 8a 
 107bcb8:	48 89 da             	mov    %rbx,%rdx
 107bcbb:	31 c9                	xor    %ecx,%ecx
 107bcbd:	e8 fe 13 01 00       	call   108d0c0 <__udivti3>
 107bcc2:	49 89 c0             	mov    %rax,%r8
 107bcc5:	49 89 d2             	mov    %rdx,%r10
 107bcc8:	48 0f af c3          	imul   %rbx,%rax
 107bccc:	49 29 c5             	sub    %rax,%r13
 107bccf:	49 83 fd 64          	cmp    $0x64,%r13
 107bcd3:	72 6b                	jb     107bd40 <encoder.decimal.writeMagnitude__anon_30578+0x120>
 107bcd5:	4c 89 f3             	mov    %r14,%rbx
 107bcd8:	4c 89 f6             	mov    %r14,%rsi
 107bcdb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 107bce0:	48 8d 46 fe          	lea    -0x2(%rsi),%rax
 107bce4:	4c 89 ea             	mov    %r13,%rdx
 107bce7:	48 c1 ea 02          	shr    $0x2,%rdx
 107bceb:	c4 c2 f3 f6 cc       	mulx   %r12,%rcx,%rcx
 107bcf0:	48 c1 e9 02          	shr    $0x2,%rcx
 107bcf4:	48 6b d1 64          	imul   $0x64,%rcx,%rdx
 107bcf8:	4c 89 ef             	mov    %r13,%rdi
 107bcfb:	48 29 d7             	sub    %rdx,%rdi
 107bcfe:	0f b7 94 3f 56 84 01 	movzwl 0x1018456(%rdi,%rdi,1),%edx
 107bd05:	01 
 107bd06:	66 89 54 35 a2       	mov    %dx,-0x5e(%rbp,%rsi,1)
 107bd0b:	48 89 c6             	mov    %rax,%rsi
 107bd0e:	49 81 fd 0f 27 00 00 	cmp    $0x270f,%r13
 107bd15:	49 89 cd             	mov    %rcx,%r13
 107bd18:	77 c6                	ja     107bce0 <encoder.decimal.writeMagnitude__anon_30578+0xc0>
 107bd1a:	48 83 f9 0a          	cmp    $0xa,%rcx
 107bd1e:	73 2f                	jae    107bd4f <encoder.decimal.writeMagnitude__anon_30578+0x12f>
 107bd20:	80 c9 30             	or     $0x30,%cl
 107bd23:	88 4c 05 a3          	mov    %cl,-0x5d(%rbp,%rax,1)
 107bd27:	48 ff c8             	dec    %rax
 107bd2a:	48 89 d9             	mov    %rbx,%rcx
 107bd2d:	48 29 c1             	sub    %rax,%rcx
 107bd30:	48 83 f9 13          	cmp    $0x13,%rcx
 107bd34:	0f 82 26 ff ff ff    	jb     107bc60 <encoder.decimal.writeMagnitude__anon_30578+0x40>
 107bd3a:	eb 34                	jmp    107bd70 <encoder.decimal.writeMagnitude__anon_30578+0x150>
 107bd3c:	0f 1f 40 00          	nopl   0x0(%rax)
 107bd40:	4c 89 e9             	mov    %r13,%rcx
 107bd43:	4c 89 f3             	mov    %r14,%rbx
 107bd46:	4c 89 f0             	mov    %r14,%rax
 107bd49:	48 83 f9 0a          	cmp    $0xa,%rcx
 107bd4d:	72 d1                	jb     107bd20 <encoder.decimal.writeMagnitude__anon_30578+0x100>
 107bd4f:	0f b7 8c 09 56 84 01 	movzwl 0x1018456(%rcx,%rcx,1),%ecx
 107bd56:	01 
 107bd57:	66 89 4c 05 a2       	mov    %cx,-0x5e(%rbp,%rax,1)
 107bd5c:	48 83 c0 fe          	add    $0xfffffffffffffffe,%rax
 107bd60:	48 89 d9             	mov    %rbx,%rcx
 107bd63:	48 29 c1             	sub    %rax,%rcx
 107bd66:	48 83 f9 13          	cmp    $0x13,%rcx
 107bd6a:	0f 82 f0 fe ff ff    	jb     107bc60 <encoder.decimal.writeMagnitude__anon_30578+0x40>
 107bd70:	48 89 c3             	mov    %rax,%rbx
 107bd73:	e9 10 ff ff ff       	jmp    107bc88 <encoder.decimal.writeMagnitude__anon_30578+0x68>
 107bd78:	49 89 f9             	mov    %rdi,%r9
 107bd7b:	bb 28 00 00 00       	mov    $0x28,%ebx
 107bd80:	49 83 fd 64          	cmp    $0x64,%r13
 107bd84:	73 14                	jae    107bd9a <encoder.decimal.writeMagnitude__anon_30578+0x17a>
 107bd86:	4d 89 e8             	mov    %r13,%r8
 107bd89:	48 89 d8             	mov    %rbx,%rax
 107bd8c:	eb 4c                	jmp    107bdda <encoder.decimal.writeMagnitude__anon_30578+0x1ba>
 107bd8e:	4d 89 c5             	mov    %r8,%r13
 107bd91:	8b 4d cc             	mov    -0x34(%rbp),%ecx
 107bd94:	49 83 fd 64          	cmp    $0x64,%r13
 107bd98:	72 ec                	jb     107bd86 <encoder.decimal.writeMagnitude__anon_30578+0x166>
 107bd9a:	48 89 de             	mov    %rbx,%rsi
 107bd9d:	0f 1f 00             	nopl   (%rax)
 107bda0:	48 8d 46 fe          	lea    -0x2(%rsi),%rax
 107bda4:	4c 89 ea             	mov    %r13,%rdx
 107bda7:	48 c1 ea 02          	shr    $0x2,%rdx
 107bdab:	c4 42 bb f6 c4       	mulx   %r12,%r8,%r8
 107bdb0:	49 c1 e8 02          	shr    $0x2,%r8
 107bdb4:	49 6b d0 64          	imul   $0x64,%r8,%rdx
 107bdb8:	4c 89 ef             	mov    %r13,%rdi
 107bdbb:	48 29 d7             	sub    %rdx,%rdi
 107bdbe:	0f b7 94 3f 56 84 01 	movzwl 0x1018456(%rdi,%rdi,1),%edx
 107bdc5:	01 
 107bdc6:	66 89 54 35 a2       	mov    %dx,-0x5e(%rbp,%rsi,1)
 107bdcb:	48 89 c6             	mov    %rax,%rsi
 107bdce:	49 81 fd 0f 27 00 00 	cmp    $0x270f,%r13
 107bdd5:	4d 89 c5             	mov    %r8,%r13
 107bdd8:	77 c6                	ja     107bda0 <encoder.decimal.writeMagnitude__anon_30578+0x180>
 107bdda:	49 83 f8 0a          	cmp    $0xa,%r8
 107bdde:	73 13                	jae    107bdf3 <encoder.decimal.writeMagnitude__anon_30578+0x1d3>
 107bde0:	41 80 c8 30          	or     $0x30,%r8b
 107bde4:	44 88 44 05 a3       	mov    %r8b,-0x5d(%rbp,%rax,1)
 107bde9:	48 ff c8             	dec    %rax
 107bdec:	48 39 c3             	cmp    %rax,%rbx
 107bdef:	74 19                	je     107be0a <encoder.decimal.writeMagnitude__anon_30578+0x1ea>
 107bdf1:	eb 22                	jmp    107be15 <encoder.decimal.writeMagnitude__anon_30578+0x1f5>
 107bdf3:	43 0f b7 94 00 56 84 	movzwl 0x1018456(%r8,%r8,1),%edx
 107bdfa:	01 01 
 107bdfc:	66 89 54 05 a2       	mov    %dx,-0x5e(%rbp,%rax,1)
 107be01:	48 83 c0 fe          	add    $0xfffffffffffffffe,%rax
 107be05:	48 39 c3             	cmp    %rax,%rbx
 107be08:	75 0b                	jne    107be15 <encoder.decimal.writeMagnitude__anon_30578+0x1f5>
 107be0a:	c6 44 1d a3 30       	movb   $0x30,-0x5d(%rbp,%rbx,1)
 107be0f:	48 ff cb             	dec    %rbx
 107be12:	48 89 d8             	mov    %rbx,%rax
 107be15:	f6 c1 01             	test   $0x1,%cl
 107be18:	75 0b                	jne    107be25 <encoder.decimal.writeMagnitude__anon_30578+0x205>
 107be1a:	48 89 c3             	mov    %rax,%rbx
 107be1d:	48 83 eb 28          	sub    $0x28,%rbx
 107be21:	74 13                	je     107be36 <encoder.decimal.writeMagnitude__anon_30578+0x216>
 107be23:	eb 22                	jmp    107be47 <encoder.decimal.writeMagnitude__anon_30578+0x227>
 107be25:	c6 44 05 a3 2d       	movb   $0x2d,-0x5d(%rbp,%rax,1)
 107be2a:	48 ff c8             	dec    %rax
 107be2d:	48 89 c3             	mov    %rax,%rbx
 107be30:	48 83 eb 28          	sub    $0x28,%rbx
 107be34:	75 11                	jne    107be47 <encoder.decimal.writeMagnitude__anon_30578+0x227>
 107be36:	31 c0                	xor    %eax,%eax
 107be38:	48 83 c4 58          	add    $0x58,%rsp
 107be3c:	5b                   	pop    %rbx
 107be3d:	41 5c                	pop    %r12
 107be3f:	41 5d                	pop    %r13
 107be41:	41 5e                	pop    %r14
 107be43:	41 5f                	pop    %r15
 107be45:	5d                   	pop    %rbp
 107be46:	c3                   	ret
 107be47:	48 f7 db             	neg    %rbx
 107be4a:	4c 8d 2c 28          	lea    (%rax,%rbp,1),%r13
 107be4e:	49 83 c5 a4          	add    $0xffffffffffffffa4,%r13
 107be52:	45 31 f6             	xor    %r14d,%r14d
 107be55:	4c 8d 7d 90          	lea    -0x70(%rbp),%r15
 107be59:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 107be60:	4b 8d 34 2e          	lea    (%r14,%r13,1),%rsi
 107be64:	49 89 dc             	mov    %rbx,%r12
 107be67:	4d 29 f4             	sub    %r14,%r12
 107be6a:	49 8b 79 18          	mov    0x18(%r9),%rdi
 107be6e:	4a 8d 04 27          	lea    (%rdi,%r12,1),%rax
 107be72:	49 3b 41 10          	cmp    0x10(%r9),%rax
 107be76:	77 1e                	ja     107be96 <encoder.decimal.writeMagnitude__anon_30578+0x276>
 107be78:	49 03 79 08          	add    0x8(%r9),%rdi
 107be7c:	4c 89 e2             	mov    %r12,%rdx
 107be7f:	e8 cc 0d 01 00       	call   108cc50 <compiler_rt.memcpy.memcpyFast>
 107be84:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 107be88:	4d 01 61 18          	add    %r12,0x18(%r9)
 107be8c:	4d 01 e6             	add    %r12,%r14
 107be8f:	49 39 de             	cmp    %rbx,%r14
 107be92:	72 cc                	jb     107be60 <encoder.decimal.writeMagnitude__anon_30578+0x240>
 107be94:	eb a0                	jmp    107be36 <encoder.decimal.writeMagnitude__anon_30578+0x216>
 107be96:	49 8b 01             	mov    (%r9),%rax
 107be99:	48 8b 00             	mov    (%rax),%rax
 107be9c:	48 89 75 90          	mov    %rsi,-0x70(%rbp)
 107bea0:	4c 89 65 98          	mov    %r12,-0x68(%rbp)
 107bea4:	b9 01 00 00 00       	mov    $0x1,%ecx
 107bea9:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 107beaf:	48 8d 7d 80          	lea    -0x80(%rbp),%rdi
 107beb3:	4c 89 ce             	mov    %r9,%rsi
 107beb6:	4c 89 fa             	mov    %r15,%rdx
 107beb9:	4d 89 cc             	mov    %r9,%r12
 107bebc:	ff d0                	call   *%rax
 107bebe:	0f b7 45 88          	movzwl -0x78(%rbp),%eax
 107bec2:	66 85 c0             	test   %ax,%ax
 107bec5:	0f 85 6d ff ff ff    	jne    107be38 <encoder.decimal.writeMagnitude__anon_30578+0x218>
 107becb:	4d 89 e1             	mov    %r12,%r9
 107bece:	4c 8b 65 80          	mov    -0x80(%rbp),%r12
 107bed2:	4d 01 e6             	add    %r12,%r14
 107bed5:	49 39 de             	cmp    %rbx,%r14
 107bed8:	72 86                	jb     107be60 <encoder.decimal.writeMagnitude__anon_30578+0x240>
 107beda:	e9 57 ff ff ff       	jmp    107be36 <encoder.decimal.writeMagnitude__anon_30578+0x216>
