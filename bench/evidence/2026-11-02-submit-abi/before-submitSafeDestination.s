
.zig-cache/submit-abi/before-reference:     file format elf64-x86-64


Disassembly of section .text:

00000000010fbc70 <core.runtime.Runtime.submitSafeDestination>:
 10fbc70:	push   %rbp
 10fbc71:	mov    %rsp,%rbp
 10fbc74:	push   %r15
 10fbc76:	push   %r14
 10fbc78:	push   %r13
 10fbc7a:	push   %r12
 10fbc7c:	push   %rbx
 10fbc7d:	sub    $0xfb8,%rsp
 10fbc84:	mov    %rsi,%r14
 10fbc87:	mov    %rdi,%rbx
 10fbc8a:	mov    0xb8(%rdx),%edi
 10fbc90:	mov    (%rcx),%r15
 10fbc93:	mov    0x8(%rcx),%r8
 10fbc97:	mov    0x20(%rcx),%r13
 10fbc9b:	mov    0x28(%rcx),%rax
 10fbc9f:	mov    %rax,-0x98(%rbp)
 10fbca6:	vmovups 0x30(%rcx),%xmm0
 10fbcab:	vmovaps %xmm0,-0x230(%rbp)
 10fbcb3:	movzbl 0x40(%rcx),%eax
 10fbcb7:	mov    %al,-0x90(%rbp)
 10fbcbd:	vmovups 0x68(%rcx),%ymm0
 10fbcc2:	vmovups %ymm0,-0xc80(%rbp)
 10fbcca:	vmovups 0x88(%rcx),%ymm0
 10fbcd2:	vmovups %ymm0,-0xc60(%rbp)
 10fbcda:	vmovups 0xa8(%rcx),%ymm0
 10fbce2:	vmovups %ymm0,-0xc40(%rbp)
 10fbcea:	vmovups 0xc8(%rcx),%ymm0
 10fbcf2:	vmovups %ymm0,-0xc20(%rbp)
 10fbcfa:	vmovups 0xe8(%rcx),%ymm0
 10fbd02:	vmovups %ymm0,-0xc00(%rbp)
 10fbd0a:	vmovups 0x108(%rcx),%ymm0
 10fbd12:	vmovups %ymm0,-0xbe0(%rbp)
 10fbd1a:	mov    0x128(%rcx),%rax
 10fbd21:	mov    %rax,-0xbc0(%rbp)
 10fbd28:	vmovups 0x48(%rcx),%ymm0
 10fbd2d:	vmovups %ymm0,-0xca0(%rbp)
 10fbd35:	movzbl 0x130(%rcx),%eax
 10fbd3c:	mov    %al,-0x70(%rbp)
 10fbd3f:	movzbl 0x140(%rcx),%eax
 10fbd46:	mov    %al,-0x2a(%rbp)
 10fbd49:	mov    0x138(%rcx),%rax
 10fbd50:	mov    %rax,-0x128(%rbp)
 10fbd57:	movzbl 0x148(%rcx),%eax
 10fbd5e:	lea    -0x41(%rdi),%ecx
 10fbd61:	lea    -0x1(%rdi),%esi
 10fbd64:	shl    $0x6,%rsi
 10fbd68:	cmp    $0xffffffc0,%ecx
 10fbd6b:	mov    0x40(%rdx),%rcx
 10fbd6f:	mov    %rcx,-0x140(%rbp)
 10fbd76:	vmovups (%rdx),%ymm0
 10fbd7a:	vmovups 0x20(%rdx),%ymm1
 10fbd7f:	vmovups %ymm1,-0x160(%rbp)
 10fbd87:	vmovups %ymm0,-0x180(%rbp)
 10fbd8f:	mov    0x50(%rdx),%r11
 10fbd93:	vmovups 0x98(%rdx),%ymm0
 10fbd9b:	vmovups %ymm0,-0x1a0(%rbp)
 10fbda3:	vmovups 0x78(%rdx),%ymm0
 10fbda8:	vmovups %ymm0,-0x1c0(%rbp)
 10fbdb0:	vmovups 0xbc(%rdx),%xmm0
 10fbdb8:	vmovups 0xc9(%rdx),%xmm1
 10fbdc0:	vmovups %xmm1,-0x113(%rbp)
 10fbdc8:	vmovaps %xmm0,-0x120(%rbp)
 10fbdd0:	mov    0xda(%rdx),%ecx
 10fbdd6:	mov    %ecx,-0x30(%rbp)
 10fbdd9:	lea    (%rsi,%rsi,2),%rcx
 10fbddd:	mov    $0x3000,%r12d
 10fbde3:	movzwl 0xde(%rdx),%esi
 10fbdea:	cmovae %rcx,%r12
 10fbdee:	mov    %si,-0x2c(%rbp)
 10fbdf2:	and    $0x1,%al
 10fbdf4:	mov    %al,-0x29(%rbp)
 10fbdf7:	add    %r14,%r12
 10fbdfa:	cmpb   $0x0,0x7420(%r13)
 10fbe02:	mov    0x3178(%r14),%r10
 10fbe09:	mov    0x7430(%r13),%rcx
 10fbe10:	mov    0x7438(%r13),%r9
 10fbe17:	mov    %rdi,-0x40(%rbp)
 10fbe1b:	mov    %r8,-0x38(%rbp)
 10fbe1f:	mov    %rcx,-0x78(%rbp)
 10fbe23:	mov    %r9,-0x58(%rbp)
 10fbe27:	mov    %r10,-0x68(%rbp)
 10fbe2b:	mov    %r11,-0xf8(%rbp)
 10fbe32:	je     10fbf42 <core.runtime.Runtime.submitSafeDestination+0x2d2>
 10fbe38:	mov    0x40(%rdx),%rax
 10fbe3c:	mov    %rax,-0x3a0(%rbp)
 10fbe43:	vmovups (%rdx),%ymm0
 10fbe47:	vmovups 0x20(%rdx),%ymm1
 10fbe4c:	vmovups %ymm1,-0x3c0(%rbp)
 10fbe54:	vmovups %ymm0,-0x3e0(%rbp)
 10fbe5c:	mov    %r10,-0x398(%rbp)
 10fbe63:	mov    %r11,-0x390(%rbp)
 10fbe6a:	mov    %r15,-0x388(%rbp)
 10fbe71:	mov    %r9,-0x380(%rbp)
 10fbe78:	mov    %rcx,-0x378(%rbp)
 10fbe7f:	mov    %r8,-0x370(%rbp)
 10fbe86:	lea    0x78(%rdx),%rax
 10fbe8a:	vmovups (%rax),%ymm0
 10fbe8e:	vmovups 0x20(%rax),%ymm1
 10fbe93:	lea    0xbc(%rdx),%rax
 10fbe9a:	vmovups %ymm0,-0x368(%rbp)
 10fbea2:	vmovups %ymm1,-0x348(%rbp)
 10fbeaa:	mov    %edi,-0x328(%rbp)
 10fbeb0:	vmovups (%rax),%xmm0
 10fbeb4:	vmovups 0xd(%rax),%xmm1
 10fbeb9:	vmovups %xmm0,-0x324(%rbp)
 10fbec1:	vmovups %xmm1,-0x317(%rbp)
 10fbec9:	movzbl -0x29(%rbp),%eax
 10fbecd:	lea    0xda(%rdx),%rcx
 10fbed4:	mov    %al,-0x307(%rbp)
 10fbeda:	mov    (%rcx),%eax
 10fbedc:	mov    %eax,-0x306(%rbp)
 10fbee2:	movzwl 0x4(%rcx),%eax
 10fbee6:	mov    %ax,-0x302(%rbp)
 10fbeed:	lea    0x1000(%r13),%rsi
 10fbef4:	lea    -0xfc(%rbp),%rdi
 10fbefb:	lea    -0x3e0(%rbp),%rdx
 10fbf02:	vzeroupper
 10fbf05:	call   110d500 <pipeline.predicate.Predicate.matches>
 10fbf0a:	movzwl -0xfc(%rbp),%eax
 10fbf11:	test   %ax,%ax
 10fbf14:	jne    10fc5cd <core.runtime.Runtime.submitSafeDestination+0x95d>
 10fbf1a:	cmpb   $0x0,-0xfa(%rbp)
 10fbf21:	mov    -0x40(%rbp),%rdi
 10fbf25:	mov    -0x38(%rbp),%r8
 10fbf29:	mov    -0x78(%rbp),%rcx
 10fbf2d:	mov    -0x58(%rbp),%r9
 10fbf31:	mov    -0x68(%rbp),%r10
 10fbf35:	mov    -0xf8(%rbp),%r11
 10fbf3c:	je     10fc0cc <core.runtime.Runtime.submitSafeDestination+0x45c>
 10fbf42:	mov    %r12,-0x88(%rbp)
 10fbf49:	mov    %r14,-0x60(%rbp)
 10fbf4d:	mov    %rbx,-0x50(%rbp)
 10fbf51:	mov    %r13,-0x80(%rbp)
 10fbf55:	mov    0x7490(%r13),%r13
 10fbf5c:	and    %r15,%r13
 10fbf5f:	je     10fc0ab <core.runtime.Runtime.submitSafeDestination+0x43b>
 10fbf65:	lea    -0xd08(%rbp),%rbx
 10fbf6c:	movzbl -0x29(%rbp),%r12d
 10fbf71:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10fbf80:	tzcnt  %r13,%r14
 10fbf85:	imul   $0x7650,%r14,%rsi
 10fbf8c:	mov    -0x80(%rbp),%rax
 10fbf90:	add    0x7440(%rax),%rsi
 10fbf97:	mov    -0x140(%rbp),%rax
 10fbf9e:	mov    %rax,-0xd40(%rbp)
 10fbfa5:	vmovups -0x180(%rbp),%ymm0
 10fbfad:	vmovups -0x160(%rbp),%ymm1
 10fbfb5:	vmovups %ymm1,-0xd60(%rbp)
 10fbfbd:	vmovups %ymm0,-0xd80(%rbp)
 10fbfc5:	mov    %r10,-0xd38(%rbp)
 10fbfcc:	mov    %r11,-0xd30(%rbp)
 10fbfd3:	mov    %r15,-0xd28(%rbp)
 10fbfda:	mov    %r9,-0xd20(%rbp)
 10fbfe1:	mov    %rcx,-0xd18(%rbp)
 10fbfe8:	mov    %r8,-0xd10(%rbp)
 10fbfef:	vmovups -0x1c0(%rbp),%ymm0
 10fbff7:	vmovups -0x1a0(%rbp),%ymm1
 10fbfff:	vmovups %ymm1,0x20(%rbx)
 10fc004:	vmovups %ymm0,(%rbx)
 10fc008:	mov    %edi,-0xcc8(%rbp)
 10fc00e:	vmovups -0x113(%rbp),%xmm0
 10fc016:	vmovups %xmm0,0x51(%rbx)
 10fc01b:	vmovaps -0x120(%rbp),%xmm0
 10fc023:	vmovups %xmm0,0x44(%rbx)
 10fc028:	mov    %r12b,-0xca7(%rbp)
 10fc02f:	movzwl -0x2c(%rbp),%eax
 10fc033:	mov    %ax,0x66(%rbx)
 10fc037:	mov    -0x30(%rbp),%eax
 10fc03a:	mov    %eax,0x62(%rbx)
 10fc03d:	lea    -0x100(%rbp),%rdi
 10fc044:	lea    -0xd80(%rbp),%rdx
 10fc04b:	vzeroupper
 10fc04e:	call   110d500 <pipeline.predicate.Predicate.matches>
 10fc053:	movzwl -0x100(%rbp),%eax
 10fc05a:	test   %ax,%ax
 10fc05d:	jne    10fc9c7 <core.runtime.Runtime.submitSafeDestination+0xd57>
 10fc063:	mov    $0xfffffffffffffffe,%rax
 10fc06a:	mov    %r14d,%ecx
 10fc06d:	rol    %cl,%rax
 10fc070:	cmpb   $0x0,-0xfe(%rbp)
 10fc077:	mov    $0xffffffffffffffff,%rcx
 10fc07e:	cmovne %rcx,%rax
 10fc082:	and    %rax,%r15
 10fc085:	blsr   %r13,%r13
 10fc08a:	mov    -0x40(%rbp),%rdi
 10fc08e:	mov    -0x38(%rbp),%r8
 10fc092:	mov    -0x78(%rbp),%rcx
 10fc096:	mov    -0x58(%rbp),%r9
 10fc09a:	mov    -0x68(%rbp),%r10
 10fc09e:	mov    -0xf8(%rbp),%r11
 10fc0a5:	jne    10fbf80 <core.runtime.Runtime.submitSafeDestination+0x310>
 10fc0ab:	test   %r15,%r15
 10fc0ae:	je     10fc0dc <core.runtime.Runtime.submitSafeDestination+0x46c>
 10fc0b0:	mov    -0x60(%rbp),%r13
 10fc0b4:	movzwl 0x31e8(%r13),%eax
 10fc0bc:	test   %ax,%ax
 10fc0bf:	mov    -0x50(%rbp),%r12
 10fc0c3:	je     10fc109 <core.runtime.Runtime.submitSafeDestination+0x499>
 10fc0c5:	mov    %ax,(%r12)
 10fc0ca:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc0cc:	lock incq 0x48(%r12)
 10fc0d2:	mov    -0x89f74(%rip),%eax        # 1072164 <__anon_29578>
 10fc0d8:	mov    %eax,(%rbx)
 10fc0da:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc0dc:	mov    -0x88(%rbp),%rax
 10fc0e3:	lock incq 0x48(%rax)
 10fc0e8:	mov    -0x89f8a(%rip),%eax        # 1072164 <__anon_29578>
 10fc0ee:	mov    -0x50(%rbp),%rcx
 10fc0f2:	mov    %eax,(%rcx)
 10fc0f4:	add    $0xfb8,%rsp
 10fc0fb:	pop    %rbx
 10fc0fc:	pop    %r12
 10fc0fe:	pop    %r13
 10fc100:	pop    %r14
 10fc102:	pop    %r15
 10fc104:	pop    %rbp
 10fc105:	vzeroupper
 10fc108:	ret
 10fc109:	cmpb   $0x0,-0x70(%rbp)
 10fc10d:	je     10fc254 <core.runtime.Runtime.submitSafeDestination+0x5e4>
 10fc113:	mov    -0x98(%rbp),%rbx
 10fc11a:	test   %rbx,%rbx
 10fc11d:	je     10fc359 <core.runtime.Runtime.submitSafeDestination+0x6e9>
 10fc123:	cmpb   $0x0,0x288(%rbx)
 10fc12a:	je     10fc366 <core.runtime.Runtime.submitSafeDestination+0x6f6>
 10fc130:	lea    -0xbd0(%rbp),%rsi
 10fc137:	mov    -0xbd0(%rbp),%r14d
 10fc13e:	lea    0x208(%rbx),%rdi
 10fc145:	mov    %rdi,-0x1d0(%rbp)
 10fc14c:	vzeroupper
 10fc14f:	call   1132de0 <journal.schema.Registry.validateReady>
 10fc154:	test   %ax,%ax
 10fc157:	jne    10fc0c5 <core.runtime.Runtime.submitSafeDestination+0x455>
 10fc15d:	dec    %r14d
 10fc160:	mov    0x270(%rbx),%rax
 10fc167:	imul   $0xd8,%r14,%rcx
 10fc16e:	vmovups 0xa8(%rax,%rcx,1),%ymm0
 10fc177:	vmovups %ymm0,-0xb10(%rbp)
 10fc17f:	vmovups 0x88(%rax,%rcx,1),%ymm0
 10fc188:	vmovups %ymm0,-0xb30(%rbp)
 10fc190:	vmovups 0x8(%rax,%rcx,1),%ymm0
 10fc196:	vmovups 0x28(%rax,%rcx,1),%ymm1
 10fc19c:	vmovups 0x48(%rax,%rcx,1),%ymm2
 10fc1a2:	vmovups 0x68(%rax,%rcx,1),%ymm3
 10fc1a8:	vmovups %ymm3,-0xb50(%rbp)
 10fc1b0:	vmovups %ymm2,-0xb70(%rbp)
 10fc1b8:	vmovups %ymm1,-0xb90(%rbp)
 10fc1c0:	lea    -0xaf0(%rbp),%r10
 10fc1c7:	vmovups %ymm0,-0xbb0(%rbp)
 10fc1cf:	movb   $0x1,-0xaf0(%rbp)
 10fc1d6:	lea    0x140(%rbx),%rdx
 10fc1dd:	mov    %r13,%rax
 10fc1e0:	add    $0x31c4,%r13
 10fc1e7:	lea    0x31ee(%rax),%rcx
 10fc1ee:	mov    %rcx,-0x70(%rbp)
 10fc1f2:	lea    0x3110(%rax),%rcx
 10fc1f9:	mov    %rcx,-0xa8(%rbp)
 10fc200:	add    $0x3118,%rax
 10fc206:	mov    %rax,-0xa0(%rbp)
 10fc20d:	cmpb   $0x0,-0x90(%rbp)
 10fc214:	cmove  %r13,%rdx
 10fc218:	mov    %rdx,-0x90(%rbp)
 10fc21f:	mov    %rbx,%rsi
 10fc222:	je     10fc45c <core.runtime.Runtime.submitSafeDestination+0x7ec>
 10fc228:	lea    0x164(%rsi),%r14
 10fc22f:	mov    %r14,-0x1c8(%rbp)
 10fc236:	mov    0x140(%rsi),%eax
 10fc23c:	cmpb   $0x0,0x288(%rsi)
 10fc243:	mov    %eax,-0x12c(%rbp)
 10fc249:	jne    10fcab2 <core.runtime.Runtime.submitSafeDestination+0xe42>
 10fc24f:	jmp    10fc9f4 <core.runtime.Runtime.submitSafeDestination+0xd84>
 10fc254:	mov    -0x98(%rbp),%rsi
 10fc25b:	test   %rsi,%rsi
 10fc25e:	je     10fc374 <core.runtime.Runtime.submitSafeDestination+0x704>
 10fc264:	lea    0x31ee(%r13),%rax
 10fc26b:	mov    %rax,-0x70(%rbp)
 10fc26f:	lea    0x3110(%r13),%rax
 10fc276:	mov    %rax,-0xa8(%rbp)
 10fc27d:	lea    0x3118(%r13),%rax
 10fc284:	mov    %rax,-0xa0(%rbp)
 10fc28b:	cmpb   $0x0,-0x90(%rbp)
 10fc292:	je     10fc51d <core.runtime.Runtime.submitSafeDestination+0x8ad>
 10fc298:	lea    0x140(%rsi),%rax
 10fc29f:	mov    %rax,-0x90(%rbp)
 10fc2a6:	lea    0x164(%rsi),%r13
 10fc2ad:	lea    -0xf90(%rbp),%rbx
 10fc2b4:	lea    -0x230(%rbp),%r12
 10fc2bb:	mov    0x140(%rsi),%r14d
 10fc2c2:	mov    %rbx,%rdi
 10fc2c5:	mov    %r12,%rdx
 10fc2c8:	vzeroupper
 10fc2cb:	call   10fba30 <journal.journal.Journal.reserveSingleProducer>
 10fc2d0:	movzwl -0xf50(%rbp),%eax
 10fc2d7:	test   %eax,%eax
 10fc2d9:	je     10fc5a8 <core.runtime.Runtime.submitSafeDestination+0x938>
 10fc2df:	cmp    $0x13b,%eax
 10fc2e4:	jne    10fd41a <core.runtime.Runtime.submitSafeDestination+0x17aa>
 10fc2ea:	mov    -0x60(%rbp),%rax
 10fc2ee:	movzbl 0x31ef(%rax),%eax
 10fc2f5:	test   $0x3,%al
 10fc2f7:	jne    10fc5d5 <core.runtime.Runtime.submitSafeDestination+0x965>
 10fc2fd:	mov    $0x1,%al
 10fc2ff:	xchg   %al,0x0(%r13)
 10fc303:	mov    -0x60(%rbp),%rax
 10fc307:	movzwl 0x31e8(%rax),%eax
 10fc30e:	test   %ax,%ax
 10fc311:	jne    10fc9bf <core.runtime.Runtime.submitSafeDestination+0xd4f>
 10fc317:	mov    -0x70(%rbp),%rax
 10fc31b:	movzbl (%rax),%eax
 10fc31e:	test   %al,%al
 10fc320:	jne    10fc9d3 <core.runtime.Runtime.submitSafeDestination+0xd63>
 10fc326:	mov    -0xa8(%rbp),%rax
 10fc32d:	mov    (%rax),%rdi
 10fc330:	mov    -0xa0(%rbp),%rax
 10fc337:	mov    (%rax),%rax
 10fc33a:	mov    -0x90(%rbp),%rsi
 10fc341:	mov    %r14d,%edx
 10fc344:	call   *0x68(%rax)
 10fc347:	xor    %eax,%eax
 10fc349:	xchg   %al,0x0(%r13)
 10fc34d:	mov    -0x98(%rbp),%rsi
 10fc354:	jmp    10fc2bb <core.runtime.Runtime.submitSafeDestination+0x64b>
 10fc359:	movl   $0x134,(%r12)
 10fc361:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc366:	mov    $0x90,%ax
 10fc36a:	mov    %ax,(%r12)
 10fc36f:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc374:	mov    -0x140(%rbp),%rax
 10fc37b:	mov    %rax,-0xaa0(%rbp)
 10fc382:	vmovups -0x180(%rbp),%ymm0
 10fc38a:	vmovups -0x160(%rbp),%ymm1
 10fc392:	vmovups %ymm1,-0xac0(%rbp)
 10fc39a:	vmovups %ymm0,-0xae0(%rbp)
 10fc3a2:	mov    %r10,-0xa98(%rbp)
 10fc3a9:	mov    %r11,-0xa90(%rbp)
 10fc3b0:	mov    %r15,-0xa88(%rbp)
 10fc3b7:	mov    %r9,-0xa80(%rbp)
 10fc3be:	mov    %rcx,-0xa78(%rbp)
 10fc3c5:	mov    %r8,-0xa70(%rbp)
 10fc3cc:	vmovups -0x1c0(%rbp),%ymm0
 10fc3d4:	vmovups -0x1a0(%rbp),%ymm1
 10fc3dc:	vmovups %ymm0,-0xa68(%rbp)
 10fc3e4:	vmovups %ymm1,-0xa48(%rbp)
 10fc3ec:	mov    %edi,-0xa28(%rbp)
 10fc3f2:	vmovups -0x113(%rbp),%xmm0
 10fc3fa:	vmovups %xmm0,-0xa17(%rbp)
 10fc402:	vmovaps -0x120(%rbp),%xmm0
 10fc40a:	vmovups %xmm0,-0xa24(%rbp)
 10fc412:	movzbl -0x29(%rbp),%eax
 10fc416:	mov    %al,-0xa07(%rbp)
 10fc41c:	movzwl -0x2c(%rbp),%eax
 10fc420:	mov    %ax,-0xa02(%rbp)
 10fc427:	mov    -0x30(%rbp),%eax
 10fc42a:	mov    %eax,-0xa06(%rbp)
 10fc430:	lea    -0x134(%rbp),%rdi
 10fc437:	lea    -0xae0(%rbp),%rdx
 10fc43e:	mov    %r13,%rsi
 10fc441:	mov    -0x80(%rbp),%rcx
 10fc445:	vzeroupper
 10fc448:	call   1100e30 <core.runtime.Runtime.submitSync>
 10fc44d:	mov    -0x134(%rbp),%eax
 10fc453:	mov    %eax,(%r12)
 10fc457:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc45c:	lea    -0xf48(%rbp),%rbx
 10fc463:	lea    -0xbb0(%rbp),%r12
 10fc46a:	mov    0x0(%r13),%r14d
 10fc46e:	mov    %rbx,%rdi
 10fc471:	lea    -0xbd0(%rbp),%rdx
 10fc478:	vzeroupper
 10fc47b:	call   10fb790 <journal.journal.Journal.reserveWithSchema>
 10fc480:	movzwl -0xf08(%rbp),%eax
 10fc487:	test   %eax,%eax
 10fc489:	je     10fc4f9 <core.runtime.Runtime.submitSafeDestination+0x889>
 10fc48b:	cmp    $0x13b,%eax
 10fc490:	jne    10fd41a <core.runtime.Runtime.submitSafeDestination+0x17aa>
 10fc496:	mov    -0x60(%rbp),%rax
 10fc49a:	movzbl 0x31ef(%rax),%eax
 10fc4a1:	test   $0x3,%al
 10fc4a3:	jne    10fc602 <core.runtime.Runtime.submitSafeDestination+0x992>
 10fc4a9:	mov    -0x60(%rbp),%rax
 10fc4ad:	movzwl 0x31e8(%rax),%eax
 10fc4b4:	test   %ax,%ax
 10fc4b7:	jne    10fc9c7 <core.runtime.Runtime.submitSafeDestination+0xd57>
 10fc4bd:	mov    -0x70(%rbp),%rax
 10fc4c1:	movzbl (%rax),%eax
 10fc4c4:	test   %al,%al
 10fc4c6:	jne    10fc9aa <core.runtime.Runtime.submitSafeDestination+0xd3a>
 10fc4cc:	mov    -0xa8(%rbp),%rax
 10fc4d3:	mov    (%rax),%rdi
 10fc4d6:	mov    -0xa0(%rbp),%rax
 10fc4dd:	mov    (%rax),%rax
 10fc4e0:	mov    -0x90(%rbp),%rsi
 10fc4e7:	mov    %r14d,%edx
 10fc4ea:	call   *0x68(%rax)
 10fc4ed:	mov    -0x98(%rbp),%rsi
 10fc4f4:	jmp    10fc46a <core.runtime.Runtime.submitSafeDestination+0x7fa>
 10fc4f9:	mov    -0x40(%rbp),%rsi
 10fc4fd:	mov    -0x38(%rbp),%rdi
 10fc501:	mov    -0x78(%rbp),%rcx
 10fc505:	mov    -0x58(%rbp),%r8
 10fc509:	mov    -0x68(%rbp),%r9
 10fc50d:	movzbl -0x2a(%rbp),%eax
 10fc511:	lea    -0xaf0(%rbp),%r10
 10fc518:	jmp    10fcbf5 <core.runtime.Runtime.submitSafeDestination+0xf85>
 10fc51d:	lea    0x31c4(%r13),%r12
 10fc524:	lea    -0xfd8(%rbp),%rbx
 10fc52b:	mov    (%r12),%r14d
 10fc52f:	mov    %rbx,%rdi
 10fc532:	vzeroupper
 10fc535:	call   10fb570 <journal.journal.Journal.reserve>
 10fc53a:	movzwl -0xf98(%rbp),%eax
 10fc541:	test   %eax,%eax
 10fc543:	je     10fc5a8 <core.runtime.Runtime.submitSafeDestination+0x938>
 10fc545:	cmp    $0x13b,%eax
 10fc54a:	jne    10fd41a <core.runtime.Runtime.submitSafeDestination+0x17aa>
 10fc550:	mov    -0x60(%rbp),%rax
 10fc554:	movzbl 0x31ef(%rax),%eax
 10fc55b:	test   $0x3,%al
 10fc55d:	jne    10fc5d5 <core.runtime.Runtime.submitSafeDestination+0x965>
 10fc55f:	mov    -0x60(%rbp),%rax
 10fc563:	movzwl 0x31e8(%rax),%eax
 10fc56a:	test   %ax,%ax
 10fc56d:	jne    10fc9c7 <core.runtime.Runtime.submitSafeDestination+0xd57>
 10fc573:	mov    -0x70(%rbp),%rax
 10fc577:	movzbl (%rax),%eax
 10fc57a:	test   %al,%al
 10fc57c:	jne    10fc9aa <core.runtime.Runtime.submitSafeDestination+0xd3a>
 10fc582:	mov    -0xa8(%rbp),%rax
 10fc589:	mov    (%rax),%rdi
 10fc58c:	mov    -0xa0(%rbp),%rax
 10fc593:	mov    (%rax),%rax
 10fc596:	mov    %r12,%rsi
 10fc599:	mov    %r14d,%edx
 10fc59c:	call   *0x68(%rax)
 10fc59f:	mov    -0x98(%rbp),%rsi
 10fc5a6:	jmp    10fc52b <core.runtime.Runtime.submitSafeDestination+0x8bb>
 10fc5a8:	mov    $0x1066ce8,%r12d
 10fc5ae:	mov    $0x1066da8,%r10d
 10fc5b4:	mov    -0x40(%rbp),%rsi
 10fc5b8:	mov    -0x38(%rbp),%rdi
 10fc5bc:	mov    -0x78(%rbp),%rcx
 10fc5c0:	mov    -0x58(%rbp),%r8
 10fc5c4:	mov    -0x68(%rbp),%r9
 10fc5c8:	jmp    10fcbf1 <core.runtime.Runtime.submitSafeDestination+0xf81>
 10fc5cd:	mov    %ax,(%rbx)
 10fc5d0:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc5d5:	and    $0x3,%eax
 10fc5d8:	cmp    $0x1,%eax
 10fc5db:	mov    -0x60(%rbp),%r12
 10fc5df:	mov    -0x40(%rbp),%rsi
 10fc5e3:	mov    -0x38(%rbp),%rdi
 10fc5e7:	mov    -0x58(%rbp),%r8
 10fc5eb:	mov    -0x68(%rbp),%r9
 10fc5ef:	je     10fd4f5 <core.runtime.Runtime.submitSafeDestination+0x1885>
 10fc5f5:	mov    $0x1066ce8,%edx
 10fc5fa:	mov    $0x1066da8,%r10d
 10fc600:	jmp    10fc630 <core.runtime.Runtime.submitSafeDestination+0x9c0>
 10fc602:	and    $0x3,%eax
 10fc605:	cmp    $0x1,%eax
 10fc608:	mov    -0x60(%rbp),%r12
 10fc60c:	mov    -0x40(%rbp),%rsi
 10fc610:	mov    -0x38(%rbp),%rdi
 10fc614:	mov    -0x58(%rbp),%r8
 10fc618:	mov    -0x68(%rbp),%r9
 10fc61c:	lea    -0xaf0(%rbp),%r10
 10fc623:	je     10fd4f5 <core.runtime.Runtime.submitSafeDestination+0x1885>
 10fc629:	lea    -0xbb0(%rbp),%rdx
 10fc630:	cmpb   $0x0,(%r10)
 10fc634:	je     10fc79a <core.runtime.Runtime.submitSafeDestination+0xb2a>
 10fc63a:	vmovups 0xa0(%rdx),%ymm0
 10fc642:	vmovups %ymm0,-0xe60(%rbp)
 10fc64a:	vmovups 0x80(%rdx),%ymm0
 10fc652:	vmovups %ymm0,-0xe80(%rbp)
 10fc65a:	vmovups (%rdx),%ymm0
 10fc65e:	vmovups 0x40(%rdx),%ymm1
 10fc663:	vmovups 0x60(%rdx),%ymm2
 10fc668:	vmovups %ymm2,-0xea0(%rbp)
 10fc670:	vmovups %ymm1,-0xec0(%rbp)
 10fc678:	vmovups 0x20(%rdx),%ymm1
 10fc67d:	vmovups %ymm1,-0xee0(%rbp)
 10fc685:	vmovups %ymm0,-0xf00(%rbp)
 10fc68d:	cmpb   $0x0,-0x2a(%rbp)
 10fc691:	je     10fc7b6 <core.runtime.Runtime.submitSafeDestination+0xb46>
 10fc697:	mov    -0x140(%rbp),%rax
 10fc69e:	mov    %rax,-0x480(%rbp)
 10fc6a5:	vmovups -0x180(%rbp),%ymm0
 10fc6ad:	vmovups -0x160(%rbp),%ymm1
 10fc6b5:	vmovups %ymm1,-0x4a0(%rbp)
 10fc6bd:	vmovups %ymm0,-0x4c0(%rbp)
 10fc6c5:	mov    %r9,-0x478(%rbp)
 10fc6cc:	mov    -0xf8(%rbp),%r14
 10fc6d3:	mov    %r14,-0x470(%rbp)
 10fc6da:	mov    %r15,-0x468(%rbp)
 10fc6e1:	mov    %r8,-0x460(%rbp)
 10fc6e8:	mov    -0x78(%rbp),%r13
 10fc6ec:	mov    %r13,-0x458(%rbp)
 10fc6f3:	mov    %rdi,-0x450(%rbp)
 10fc6fa:	vmovups -0x1c0(%rbp),%ymm0
 10fc702:	vmovups -0x1a0(%rbp),%ymm1
 10fc70a:	vmovups %ymm0,-0x448(%rbp)
 10fc712:	vmovups %ymm1,-0x428(%rbp)
 10fc71a:	mov    %esi,-0x408(%rbp)
 10fc720:	vmovups -0x113(%rbp),%xmm0
 10fc728:	vmovups %xmm0,-0x3f7(%rbp)
 10fc730:	vmovaps -0x120(%rbp),%xmm0
 10fc738:	vmovups %xmm0,-0x404(%rbp)
 10fc740:	movzbl -0x29(%rbp),%ebx
 10fc744:	mov    %bl,-0x3e7(%rbp)
 10fc74a:	mov    -0x30(%rbp),%eax
 10fc74d:	mov    %eax,-0x3e6(%rbp)
 10fc753:	movzwl -0x2c(%rbp),%eax
 10fc757:	mov    %ax,-0x3e2(%rbp)
 10fc75e:	lea    -0x240(%rbp),%rdi
 10fc765:	lea    -0x4c0(%rbp),%rsi
 10fc76c:	mov    -0x128(%rbp),%rcx
 10fc773:	vzeroupper
 10fc776:	call   110cf60 <core.reference_encoding.sizeMeasured>
 10fc77b:	mov    %r14,%rdx
 10fc77e:	mov    -0x68(%rbp),%r9
 10fc782:	mov    -0x58(%rbp),%r8
 10fc786:	mov    -0x38(%rbp),%rdi
 10fc78a:	mov    -0x40(%rbp),%rsi
 10fc78e:	movzwl -0x238(%rbp),%eax
 10fc795:	jmp    10fc8b4 <core.runtime.Runtime.submitSafeDestination+0xc44>
 10fc79a:	movzbl -0x29(%rbp),%ebx
 10fc79e:	mov    -0x50(%rbp),%r14
 10fc7a2:	mov    -0x80(%rbp),%rcx
 10fc7a6:	mov    -0x78(%rbp),%r13
 10fc7aa:	mov    -0xf8(%rbp),%rdx
 10fc7b1:	jmp    10fc8c5 <core.runtime.Runtime.submitSafeDestination+0xc55>
 10fc7b6:	mov    -0x140(%rbp),%rax
 10fc7bd:	mov    %rax,-0x560(%rbp)
 10fc7c4:	vmovups -0x180(%rbp),%ymm0
 10fc7cc:	vmovups -0x160(%rbp),%ymm1
 10fc7d4:	vmovups %ymm1,-0x580(%rbp)
 10fc7dc:	vmovups %ymm0,-0x5a0(%rbp)
 10fc7e4:	mov    %r9,-0x558(%rbp)
 10fc7eb:	mov    -0xf8(%rbp),%r14
 10fc7f2:	mov    %r14,-0x550(%rbp)
 10fc7f9:	mov    %r15,-0x548(%rbp)
 10fc800:	mov    %r8,-0x540(%rbp)
 10fc807:	mov    -0x78(%rbp),%r13
 10fc80b:	mov    %r13,-0x538(%rbp)
 10fc812:	mov    %rdi,-0x530(%rbp)
 10fc819:	vmovups -0x1c0(%rbp),%ymm0
 10fc821:	vmovups -0x1a0(%rbp),%ymm1
 10fc829:	vmovups %ymm0,-0x528(%rbp)
 10fc831:	vmovups %ymm1,-0x508(%rbp)
 10fc839:	mov    %esi,-0x4e8(%rbp)
 10fc83f:	vmovups -0x113(%rbp),%xmm0
 10fc847:	vmovups %xmm0,-0x4d7(%rbp)
 10fc84f:	vmovaps -0x120(%rbp),%xmm0
 10fc857:	vmovups %xmm0,-0x4e4(%rbp)
 10fc85f:	movzbl -0x29(%rbp),%ebx
 10fc863:	mov    %bl,-0x4c7(%rbp)
 10fc869:	mov    -0x30(%rbp),%eax
 10fc86c:	mov    %eax,-0x4c6(%rbp)
 10fc872:	movzwl -0x2c(%rbp),%eax
 10fc876:	mov    %ax,-0x4c2(%rbp)
 10fc87d:	lea    -0x250(%rbp),%rdi
 10fc884:	lea    -0x5a0(%rbp),%rsi
 10fc88b:	lea    -0xf00(%rbp),%rdx
 10fc892:	vzeroupper
 10fc895:	call   11010c0 <core.schema_codec.encodedReferenceSize>
 10fc89a:	mov    %r14,%rdx
 10fc89d:	mov    -0x68(%rbp),%r9
 10fc8a1:	mov    -0x58(%rbp),%r8
 10fc8a5:	mov    -0x38(%rbp),%rdi
 10fc8a9:	mov    -0x40(%rbp),%rsi
 10fc8ad:	movzwl -0x248(%rbp),%eax
 10fc8b4:	test   %ax,%ax
 10fc8b7:	mov    -0x50(%rbp),%r14
 10fc8bb:	mov    -0x80(%rbp),%rcx
 10fc8bf:	jne    10fc9e6 <core.runtime.Runtime.submitSafeDestination+0xd76>
 10fc8c5:	mov    -0x140(%rbp),%rax
 10fc8cc:	mov    %rax,-0x640(%rbp)
 10fc8d3:	vmovups -0x180(%rbp),%ymm0
 10fc8db:	vmovups -0x160(%rbp),%ymm1
 10fc8e3:	vmovups %ymm1,-0x660(%rbp)
 10fc8eb:	vmovups %ymm0,-0x680(%rbp)
 10fc8f3:	vmovups -0x1c0(%rbp),%ymm0
 10fc8fb:	vmovups -0x1a0(%rbp),%ymm1
 10fc903:	vmovups %ymm0,-0x608(%rbp)
 10fc90b:	vmovups %ymm1,-0x5e8(%rbp)
 10fc913:	vmovaps -0x120(%rbp),%xmm0
 10fc91b:	vmovups %xmm0,-0x5c4(%rbp)
 10fc923:	vmovups -0x113(%rbp),%xmm0
 10fc92b:	vmovups %xmm0,-0x5b7(%rbp)
 10fc933:	mov    -0x30(%rbp),%eax
 10fc936:	mov    %eax,-0x5a6(%rbp)
 10fc93c:	movzwl -0x2c(%rbp),%eax
 10fc940:	mov    %ax,-0x5a2(%rbp)
 10fc947:	or     $0x80000000,%esi
 10fc94d:	mov    %r9,-0x638(%rbp)
 10fc954:	mov    %rdx,-0x630(%rbp)
 10fc95b:	mov    %r15,-0x628(%rbp)
 10fc962:	mov    %r8,-0x620(%rbp)
 10fc969:	mov    %r13,-0x618(%rbp)
 10fc970:	mov    %rdi,-0x610(%rbp)
 10fc977:	mov    %esi,-0x5c8(%rbp)
 10fc97d:	mov    %bl,-0x5a7(%rbp)
 10fc983:	lea    -0x130(%rbp),%rdi
 10fc98a:	lea    -0x680(%rbp),%rdx
 10fc991:	mov    %r12,%rsi
 10fc994:	vzeroupper
 10fc997:	call   1100e30 <core.runtime.Runtime.submitSync>
 10fc99c:	mov    -0x130(%rbp),%eax
 10fc9a2:	mov    %eax,(%r14)
 10fc9a5:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc9aa:	mov    -0x88(%rbp),%rax
 10fc9b1:	lock incq 0x68(%rax)
 10fc9b6:	mov    -0x50(%rbp),%rcx
 10fc9ba:	jmp    10fd521 <core.runtime.Runtime.submitSafeDestination+0x18b1>
 10fc9bf:	mov    %r13,%r14
 10fc9c2:	xor    %ecx,%ecx
 10fc9c4:	xchg   %cl,(%r14)
 10fc9c7:	mov    -0x50(%rbp),%rcx
 10fc9cb:	mov    %ax,(%rcx)
 10fc9ce:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc9d3:	mov    -0x50(%rbp),%rcx
 10fc9d7:	mov    -0x88(%rbp),%rax
 10fc9de:	mov    %r13,%r14
 10fc9e1:	jmp    10fd517 <core.runtime.Runtime.submitSafeDestination+0x18a7>
 10fc9e6:	mov    %ax,(%r14)
 10fc9ea:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fc9ef:	mov    %rbx,%r10
 10fc9f2:	jmp    10fc9f8 <core.runtime.Runtime.submitSafeDestination+0xd88>
 10fc9f4:	mov    $0x90,%ax
 10fc9f8:	mov    %ax,-0x2c0(%rbp)
 10fc9ff:	movzwl %ax,%ecx
 10fca02:	cmp    $0x13b,%ecx
 10fca08:	mov    -0x40(%rbp),%rsi
 10fca0c:	mov    -0x38(%rbp),%rdi
 10fca10:	mov    -0x58(%rbp),%r8
 10fca14:	mov    -0x68(%rbp),%r9
 10fca18:	jne    10fd41a <core.runtime.Runtime.submitSafeDestination+0x17aa>
 10fca1e:	mov    -0x60(%rbp),%r12
 10fca22:	movzbl 0x31ef(%r12),%eax
 10fca2b:	test   $0x3,%al
 10fca2d:	jne    10fd4e9 <core.runtime.Runtime.submitSafeDestination+0x1879>
 10fca33:	mov    $0x1,%al
 10fca35:	mov    -0x1c8(%rbp),%r14
 10fca3c:	xchg   %al,(%r14)
 10fca3f:	movzwl 0x31e8(%r12),%eax
 10fca48:	test   %ax,%ax
 10fca4b:	jne    10fc9c2 <core.runtime.Runtime.submitSafeDestination+0xd52>
 10fca51:	mov    -0x70(%rbp),%rax
 10fca55:	movzbl (%rax),%eax
 10fca58:	test   %al,%al
 10fca5a:	jne    10fd50c <core.runtime.Runtime.submitSafeDestination+0x189c>
 10fca60:	mov    -0xa8(%rbp),%rax
 10fca67:	mov    (%rax),%rdi
 10fca6a:	mov    -0xa0(%rbp),%rax
 10fca71:	mov    (%rax),%rax
 10fca74:	mov    -0x90(%rbp),%rsi
 10fca7b:	mov    -0x12c(%rbp),%edx
 10fca81:	mov    %r10,%rbx
 10fca84:	vzeroupper
 10fca87:	call   *0x68(%rax)
 10fca8a:	mov    %rbx,%r10
 10fca8d:	mov    -0x98(%rbp),%rsi
 10fca94:	xor    %eax,%eax
 10fca96:	xchg   %al,(%r14)
 10fca99:	mov    0x140(%rsi),%eax
 10fca9f:	cmpb   $0x0,0x288(%rsi)
 10fcaa6:	mov    %eax,-0x12c(%rbp)
 10fcaac:	je     10fc9f4 <core.runtime.Runtime.submitSafeDestination+0xd84>
 10fcab2:	mov    %r10,%rbx
 10fcab5:	mov    -0xbd0(%rbp),%r12d
 10fcabc:	movzwl -0xbcc(%rbp),%r13d
 10fcac4:	mov    -0x1d0(%rbp),%rdi
 10fcacb:	lea    -0xbd0(%rbp),%rsi
 10fcad2:	vzeroupper
 10fcad5:	call   1132de0 <journal.schema.Registry.validateReady>
 10fcada:	test   %ax,%ax
 10fcadd:	jne    10fc9ef <core.runtime.Runtime.submitSafeDestination+0xd7f>
 10fcae3:	lea    -0x218(%rbp),%rdi
 10fcaea:	mov    -0x98(%rbp),%r14
 10fcaf1:	mov    %r14,%rsi
 10fcaf4:	lea    -0x230(%rbp),%rdx
 10fcafb:	call   10fba30 <journal.journal.Journal.reserveSingleProducer>
 10fcb00:	movzwl -0x1d8(%rbp),%eax
 10fcb07:	test   %ax,%ax
 10fcb0a:	mov    %rbx,%r10
 10fcb0d:	jne    10fc9f8 <core.runtime.Runtime.submitSafeDestination+0xd88>
 10fcb13:	vmovups -0x208(%rbp),%xmm0
 10fcb1b:	mov    -0x1dc(%rbp),%eax
 10fcb21:	cmpl   $0x1,0x2f0(%r14)
 10fcb29:	mov    -0x40(%rbp),%rsi
 10fcb2d:	mov    -0x38(%rbp),%rdi
 10fcb31:	mov    -0x58(%rbp),%r8
 10fcb35:	mov    -0x68(%rbp),%r9
 10fcb39:	lea    -0xbd0(%rbp),%r11
 10fcb40:	je     10fcb84 <core.runtime.Runtime.submitSafeDestination+0xf14>
 10fcb42:	mov    0x1a0(%r14),%rcx
 10fcb49:	mov    0x200(%r14),%rdx
 10fcb50:	imul   -0x208(%rbp),%rdx
 10fcb58:	movw   $0x0,0x1026(%rcx,%rdx,1)
 10fcb62:	mov    %r12d,0x1020(%rcx,%rdx,1)
 10fcb6a:	mov    %r13w,0x1024(%rcx,%rdx,1)
 10fcb73:	vmovups -0xbca(%rbp),%xmm1
 10fcb7b:	vmovups %xmm1,0x1028(%rcx,%rdx,1)
 10fcb84:	movw   $0x0,-0x2c0(%rbp)
 10fcb8d:	vmovups -0x218(%rbp),%xmm1
 10fcb95:	vmovaps %xmm1,-0x300(%rbp)
 10fcb9d:	vmovaps %xmm0,-0x2f0(%rbp)
 10fcba5:	mov    0x10(%r11),%rcx
 10fcba9:	lea    -0x2e0(%rbp),%rbx
 10fcbb0:	mov    %rcx,0x10(%rbx)
 10fcbb4:	vmovups (%r11),%xmm0
 10fcbb9:	vmovups %xmm0,(%rbx)
 10fcbbd:	movb   $0x1,-0x2c8(%rbp)
 10fcbc4:	lea    -0x1df(%rbp),%rdx
 10fcbcb:	movzbl 0x2(%rdx),%ecx
 10fcbcf:	mov    %cl,0x1b(%rbx)
 10fcbd2:	movzwl (%rdx),%ecx
 10fcbd5:	mov    %cx,0x19(%rbx)
 10fcbd9:	mov    %eax,-0x2c4(%rbp)
 10fcbdf:	lea    -0x300(%rbp),%rbx
 10fcbe6:	lea    -0xbb0(%rbp),%r12
 10fcbed:	mov    -0x78(%rbp),%rcx
 10fcbf1:	movzbl -0x2a(%rbp),%eax
 10fcbf5:	vmovups (%rbx),%ymm0
 10fcbf9:	vmovups %ymm0,-0xf0(%rbp)
 10fcc01:	vmovups 0x20(%rbx),%ymm0
 10fcc06:	vmovups %ymm0,-0xd0(%rbp)
 10fcc0e:	mov    -0xe8(%rbp),%rdx
 10fcc15:	cmpb   $0x0,(%r10)
 10fcc19:	mov    %rdx,-0x38(%rbp)
 10fcc1d:	je     10fcdba <core.runtime.Runtime.submitSafeDestination+0x114a>
 10fcc23:	vmovups 0xa0(%r12),%ymm0
 10fcc2d:	vmovups %ymm0,-0xda0(%rbp)
 10fcc35:	vmovups 0x80(%r12),%ymm0
 10fcc3f:	vmovups %ymm0,-0xdc0(%rbp)
 10fcc47:	vmovups (%r12),%ymm0
 10fcc4d:	vmovups 0x40(%r12),%ymm1
 10fcc54:	vmovups 0x60(%r12),%ymm2
 10fcc5b:	vmovups %ymm2,-0xde0(%rbp)
 10fcc63:	vmovups %ymm1,-0xe00(%rbp)
 10fcc6b:	vmovups 0x20(%r12),%ymm1
 10fcc72:	vmovups %ymm1,-0xe20(%rbp)
 10fcc7a:	vmovups %ymm0,-0xe40(%rbp)
 10fcc82:	test   %al,%al
 10fcc84:	je     10fceea <core.runtime.Runtime.submitSafeDestination+0x127a>
 10fcc8a:	mov    -0x140(%rbp),%rax
 10fcc91:	mov    %rax,-0x720(%rbp)
 10fcc98:	vmovups -0x180(%rbp),%ymm0
 10fcca0:	vmovups -0x160(%rbp),%ymm1
 10fcca8:	vmovups %ymm1,-0x740(%rbp)
 10fccb0:	vmovups %ymm0,-0x760(%rbp)
 10fccb8:	mov    %r9,-0x718(%rbp)
 10fccbf:	mov    %rdx,-0x710(%rbp)
 10fccc6:	mov    %r15,-0x708(%rbp)
 10fcccd:	mov    %r8,-0x700(%rbp)
 10fccd4:	mov    %rcx,-0x6f8(%rbp)
 10fccdb:	mov    %rdi,-0x6f0(%rbp)
 10fcce2:	vmovups -0x1c0(%rbp),%ymm0
 10fccea:	vmovups -0x1a0(%rbp),%ymm1
 10fccf2:	vmovups %ymm0,-0x6e8(%rbp)
 10fccfa:	vmovups %ymm1,-0x6c8(%rbp)
 10fcd02:	lea    -0x258(%rbp),%rbx
 10fcd09:	mov    %esi,-0x6a8(%rbp)
 10fcd0f:	vmovups -0x113(%rbp),%xmm0
 10fcd17:	vmovups %xmm0,-0x697(%rbp)
 10fcd1f:	lea    -0x260(%rbp),%r15
 10fcd26:	vmovaps -0x120(%rbp),%xmm0
 10fcd2e:	vmovups %xmm0,-0x6a4(%rbp)
 10fcd36:	movzbl -0x29(%rbp),%eax
 10fcd3a:	mov    %al,-0x687(%rbp)
 10fcd40:	movzwl -0x2c(%rbp),%eax
 10fcd44:	mov    %ax,-0x682(%rbp)
 10fcd4b:	mov    -0x30(%rbp),%eax
 10fcd4e:	mov    %eax,-0x686(%rbp)
 10fcd54:	movzbl -0xb4(%rbp),%r14d
 10fcd5c:	mov    -0xf0(%rbp),%r12
 10fcd63:	mov    -0xe0(%rbp),%r13
 10fcd6a:	mov    0x200(%r12),%rax
 10fcd72:	imul   %r13,%rax
 10fcd76:	mov    0x1a0(%r12),%rcx
 10fcd7e:	mov    0x1f8(%r12),%r9
 10fcd86:	lea    (%rcx,%rax,1),%r8
 10fcd8a:	add    $0x1040,%r8
 10fcd91:	lea    -0x268(%rbp),%rdi
 10fcd98:	lea    -0x760(%rbp),%rsi
 10fcd9f:	lea    -0xe40(%rbp),%rdx
 10fcda6:	mov    -0x128(%rbp),%rcx
 10fcdad:	vzeroupper
 10fcdb0:	call   10fe890 <core.reference_encoding.writeMeasured>
 10fcdb5:	jmp    10fd12e <core.runtime.Runtime.submitSafeDestination+0x14be>
 10fcdba:	test   %al,%al
 10fcdbc:	je     10fd012 <core.runtime.Runtime.submitSafeDestination+0x13a2>
 10fcdc2:	mov    -0x140(%rbp),%rax
 10fcdc9:	mov    %rax,-0x8e0(%rbp)
 10fcdd0:	vmovups -0x180(%rbp),%ymm0
 10fcdd8:	vmovups -0x160(%rbp),%ymm1
 10fcde0:	vmovups %ymm1,-0x900(%rbp)
 10fcde8:	vmovups %ymm0,-0x920(%rbp)
 10fcdf0:	mov    %r9,-0x8d8(%rbp)
 10fcdf7:	mov    %rdx,-0x8d0(%rbp)
 10fcdfe:	mov    %r15,-0x8c8(%rbp)
 10fce05:	mov    %r8,-0x8c0(%rbp)
 10fce0c:	mov    %rcx,-0x8b8(%rbp)
 10fce13:	mov    %rdi,-0x8b0(%rbp)
 10fce1a:	vmovups -0x1c0(%rbp),%ymm0
 10fce22:	vmovups -0x1a0(%rbp),%ymm1
 10fce2a:	vmovups %ymm0,-0x8a8(%rbp)
 10fce32:	vmovups %ymm1,-0x888(%rbp)
 10fce3a:	lea    -0x288(%rbp),%rbx
 10fce41:	mov    %esi,-0x868(%rbp)
 10fce47:	vmovups -0x113(%rbp),%xmm0
 10fce4f:	vmovups %xmm0,-0x857(%rbp)
 10fce57:	lea    -0x290(%rbp),%r15
 10fce5e:	vmovaps -0x120(%rbp),%xmm0
 10fce66:	vmovups %xmm0,-0x864(%rbp)
 10fce6e:	movzbl -0x29(%rbp),%eax
 10fce72:	mov    %al,-0x847(%rbp)
 10fce78:	movzwl -0x2c(%rbp),%eax
 10fce7c:	mov    %ax,-0x842(%rbp)
 10fce83:	mov    -0x30(%rbp),%eax
 10fce86:	mov    %eax,-0x846(%rbp)
 10fce8c:	movzbl -0xb4(%rbp),%r14d
 10fce94:	mov    -0xf0(%rbp),%r12
 10fce9b:	mov    -0xe0(%rbp),%r13
 10fcea2:	mov    0x200(%r12),%rax
 10fceaa:	imul   %r13,%rax
 10fceae:	mov    0x1a0(%r12),%rcx
 10fceb6:	mov    0x1f8(%r12),%r8
 10fcebe:	add    %rax,%rcx
 10fcec1:	add    $0x1040,%rcx
 10fcec8:	lea    -0x298(%rbp),%rdi
 10fcecf:	lea    -0x920(%rbp),%rsi
 10fced6:	mov    -0x128(%rbp),%rdx
 10fcedd:	vzeroupper
 10fcee0:	call   10fe160 <core.codec.encodeSized>
 10fcee5:	jmp    10fd12e <core.runtime.Runtime.submitSafeDestination+0x14be>
 10fceea:	mov    -0x140(%rbp),%rax
 10fcef1:	mov    %rax,-0x800(%rbp)
 10fcef8:	vmovups -0x180(%rbp),%ymm0
 10fcf00:	vmovups -0x160(%rbp),%ymm1
 10fcf08:	vmovups %ymm1,-0x820(%rbp)
 10fcf10:	vmovups %ymm0,-0x840(%rbp)
 10fcf18:	mov    %r9,-0x7f8(%rbp)
 10fcf1f:	mov    %rdx,-0x7f0(%rbp)
 10fcf26:	mov    %r15,-0x7e8(%rbp)
 10fcf2d:	mov    %r8,-0x7e0(%rbp)
 10fcf34:	mov    %rcx,-0x7d8(%rbp)
 10fcf3b:	mov    %rdi,-0x7d0(%rbp)
 10fcf42:	vmovups -0x1c0(%rbp),%ymm0
 10fcf4a:	vmovups -0x1a0(%rbp),%ymm1
 10fcf52:	vmovups %ymm0,-0x7c8(%rbp)
 10fcf5a:	vmovups %ymm1,-0x7a8(%rbp)
 10fcf62:	lea    -0x270(%rbp),%rbx
 10fcf69:	mov    %esi,-0x788(%rbp)
 10fcf6f:	vmovups -0x113(%rbp),%xmm0
 10fcf77:	vmovups %xmm0,-0x777(%rbp)
 10fcf7f:	lea    -0x278(%rbp),%r15
 10fcf86:	vmovaps -0x120(%rbp),%xmm0
 10fcf8e:	vmovups %xmm0,-0x784(%rbp)
 10fcf96:	movzbl -0x29(%rbp),%eax
 10fcf9a:	mov    %al,-0x767(%rbp)
 10fcfa0:	movzwl -0x2c(%rbp),%eax
 10fcfa4:	mov    %ax,-0x762(%rbp)
 10fcfab:	mov    -0x30(%rbp),%eax
 10fcfae:	mov    %eax,-0x766(%rbp)
 10fcfb4:	movzbl -0xb4(%rbp),%r14d
 10fcfbc:	mov    -0xf0(%rbp),%r12
 10fcfc3:	mov    -0xe0(%rbp),%r13
 10fcfca:	mov    0x200(%r12),%rax
 10fcfd2:	imul   %r13,%rax
 10fcfd6:	mov    0x1a0(%r12),%rcx
 10fcfde:	mov    0x1f8(%r12),%r8
 10fcfe6:	add    %rax,%rcx
 10fcfe9:	add    $0x1040,%rcx
 10fcff0:	lea    -0x280(%rbp),%rdi
 10fcff7:	lea    -0x840(%rbp),%rsi
 10fcffe:	lea    -0xe40(%rbp),%rdx
 10fd005:	vzeroupper
 10fd008:	call   10fe810 <core.schema_codec.encodeReference>
 10fd00d:	jmp    10fd12e <core.runtime.Runtime.submitSafeDestination+0x14be>
 10fd012:	mov    -0x140(%rbp),%rax
 10fd019:	mov    %rax,-0x9c0(%rbp)
 10fd020:	vmovups -0x180(%rbp),%ymm0
 10fd028:	vmovups -0x160(%rbp),%ymm1
 10fd030:	vmovups %ymm1,-0x9e0(%rbp)
 10fd038:	vmovups %ymm0,-0xa00(%rbp)
 10fd040:	mov    %r9,-0x9b8(%rbp)
 10fd047:	mov    %rdx,-0x9b0(%rbp)
 10fd04e:	mov    %r15,-0x9a8(%rbp)
 10fd055:	mov    %r8,-0x9a0(%rbp)
 10fd05c:	mov    %rcx,-0x998(%rbp)
 10fd063:	mov    %rdi,-0x990(%rbp)
 10fd06a:	vmovups -0x1c0(%rbp),%ymm0
 10fd072:	vmovups -0x1a0(%rbp),%ymm1
 10fd07a:	vmovups %ymm0,-0x988(%rbp)
 10fd082:	vmovups %ymm1,-0x968(%rbp)
 10fd08a:	lea    -0x2a0(%rbp),%rbx
 10fd091:	mov    %esi,-0x948(%rbp)
 10fd097:	vmovups -0x113(%rbp),%xmm0
 10fd09f:	vmovups %xmm0,-0x937(%rbp)
 10fd0a7:	lea    -0x2a8(%rbp),%r15
 10fd0ae:	vmovaps -0x120(%rbp),%xmm0
 10fd0b6:	vmovups %xmm0,-0x944(%rbp)
 10fd0be:	movzbl -0x29(%rbp),%eax
 10fd0c2:	mov    %al,-0x927(%rbp)
 10fd0c8:	movzwl -0x2c(%rbp),%eax
 10fd0cc:	mov    %ax,-0x922(%rbp)
 10fd0d3:	mov    -0x30(%rbp),%eax
 10fd0d6:	mov    %eax,-0x926(%rbp)
 10fd0dc:	movzbl -0xb4(%rbp),%r14d
 10fd0e4:	mov    -0xf0(%rbp),%r12
 10fd0eb:	mov    -0xe0(%rbp),%r13
 10fd0f2:	mov    0x200(%r12),%rax
 10fd0fa:	imul   %r13,%rax
 10fd0fe:	mov    0x1a0(%r12),%rdx
 10fd106:	mov    0x1f8(%r12),%rcx
 10fd10e:	add    %rax,%rdx
 10fd111:	add    $0x1040,%rdx
 10fd118:	lea    -0x2b0(%rbp),%rdi
 10fd11f:	lea    -0xa00(%rbp),%rsi
 10fd126:	vzeroupper
 10fd129:	call   10fe0e0 <core.codec.encode>
 10fd12e:	movzwl (%rbx),%ebx
 10fd131:	test   %ebx,%ebx
 10fd133:	je     10fd1c7 <core.runtime.Runtime.submitSafeDestination+0x1557>
 10fd139:	test   $0x1,%r14b
 10fd13d:	jne    10fd2f4 <core.runtime.Runtime.submitSafeDestination+0x1684>
 10fd143:	mov    -0xd8(%rbp),%rax
 10fd14a:	test   %rax,%rax
 10fd14d:	je     10fd29d <core.runtime.Runtime.submitSafeDestination+0x162d>
 10fd153:	testb  $0x1,0x2fd(%r12)
 10fd15c:	je     10fd2f4 <core.runtime.Runtime.submitSafeDestination+0x1684>
 10fd162:	mov    0x150(%r12),%rcx
 10fd16a:	mov    %rcx,%rdx
 10fd16d:	shr    $0x2,%rdx
 10fd171:	xor    %rdx,%rax
 10fd174:	and    $0x3,%ecx
 10fd177:	or     %rax,%rcx
 10fd17a:	jne    10fd2f4 <core.runtime.Runtime.submitSafeDestination+0x1684>
 10fd180:	mov    %fs:0xfffffffffffbb5a8,%rax
 10fd189:	test   %rax,%rax
 10fd18c:	je     10fd2f4 <core.runtime.Runtime.submitSafeDestination+0x1684>
 10fd192:	mov    0x148(%r12),%rcx
 10fd19a:	cmp    %rax,%rcx
 10fd19d:	jne    10fd2f4 <core.runtime.Runtime.submitSafeDestination+0x1684>
 10fd1a3:	mov    0x160(%r12),%edx
 10fd1ab:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd1b4:	jne    10fd426 <core.runtime.Runtime.submitSafeDestination+0x17b6>
 10fd1ba:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd1c2:	jmp    10fd43e <core.runtime.Runtime.submitSafeDestination+0x17ce>
 10fd1c7:	mov    -0x40(%rbp),%rdi
 10fd1cb:	test   %edi,%edi
 10fd1cd:	je     10fd1e3 <core.runtime.Runtime.submitSafeDestination+0x1573>
 10fd1cf:	mov    %rdi,%rax
 10fd1d2:	shl    $0x6,%rax
 10fd1d6:	mov    -0x80(%rbp),%rcx
 10fd1da:	add    %rcx,%rax
 10fd1dd:	add    $0xffffffffffffffc0,%rax
 10fd1e1:	jmp    10fd1ed <core.runtime.Runtime.submitSafeDestination+0x157d>
 10fd1e3:	mov    -0x80(%rbp),%rax
 10fd1e7:	add    $0x9810,%rax
 10fd1ed:	mov    (%r15),%r12
 10fd1f0:	lock incq (%rax)
 10fd1f4:	mov    $0x13c,%bx
 10fd1f8:	cmpb   $0x0,-0xb4(%rbp)
 10fd1ff:	jne    10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd205:	mov    -0xd8(%rbp),%rcx
 10fd20c:	test   %rcx,%rcx
 10fd20f:	je     10fd54c <core.runtime.Runtime.submitSafeDestination+0x18dc>
 10fd215:	mov    -0xf0(%rbp),%rax
 10fd21c:	mov    $0x92,%bx
 10fd220:	testb  $0x1,0x2fd(%rax)
 10fd227:	je     10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd22d:	mov    0x150(%rax),%rdx
 10fd234:	mov    %rdx,%rsi
 10fd237:	shr    $0x2,%rsi
 10fd23b:	mov    $0x94,%bx
 10fd23f:	cmp    %rsi,%rcx
 10fd242:	jne    10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd248:	mov    $0x95,%bx
 10fd24c:	test   $0x3,%dl
 10fd24f:	jne    10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd255:	mov    %fs:0xfffffffffffbb5a8,%rcx
 10fd25e:	mov    $0x96,%bx
 10fd262:	test   %rcx,%rcx
 10fd265:	je     10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd26b:	mov    0x148(%rax),%rdx
 10fd272:	cmp    %rcx,%rdx
 10fd275:	jne    10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd27b:	mov    0x160(%rax),%edx
 10fd281:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd28a:	jne    10fd52c <core.runtime.Runtime.submitSafeDestination+0x18bc>
 10fd290:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd298:	jmp    10fd544 <core.runtime.Runtime.submitSafeDestination+0x18d4>
 10fd29d:	mov    -0x38(%rbp),%rdx
 10fd2a1:	mov    0x1a0(%r12),%rcx
 10fd2a9:	imul   0x200(%r12),%r13
 10fd2b2:	lea    0x1(,%rdx,4),%rax
 10fd2ba:	lea    0x3(,%rdx,4),%rdx
 10fd2c2:	lock cmpxchg %rdx,0x1000(%rcx,%r13,1)
 10fd2cc:	setne  -0x218(%rbp)
 10fd2d3:	jne    10fd2ed <core.runtime.Runtime.submitSafeDestination+0x167d>
 10fd2d5:	cmpq   $0x0,-0xd8(%rbp)
 10fd2dd:	je     10fd2ed <core.runtime.Runtime.submitSafeDestination+0x167d>
 10fd2df:	mov    -0xf0(%rbp),%rax
 10fd2e6:	decq   0x158(%rax)
 10fd2ed:	movb   $0x1,-0xb4(%rbp)
 10fd2f4:	mov    -0x60(%rbp),%r15
 10fd2f8:	testb  $0x1,0x31ea(%r15)
 10fd300:	je     10fd30d <core.runtime.Runtime.submitSafeDestination+0x169d>
 10fd302:	mov    -0x70(%rbp),%rax
 10fd306:	movzbl (%rax),%eax
 10fd309:	test   %al,%al
 10fd30b:	je     10fd34f <core.runtime.Runtime.submitSafeDestination+0x16df>
 10fd30d:	lock incl 0x31d8(%r15)
 10fd315:	movzbl 0x31ec(%r15),%eax
 10fd31d:	test   $0x1,%al
 10fd31f:	jne    10fd32c <core.runtime.Runtime.submitSafeDestination+0x16bc>
 10fd321:	mov    -0x70(%rbp),%rax
 10fd325:	movzbl (%rax),%eax
 10fd328:	test   %al,%al
 10fd32a:	je     10fd34f <core.runtime.Runtime.submitSafeDestination+0x16df>
 10fd32c:	lea    0x31d8(%r15),%rsi
 10fd333:	mov    -0xa8(%rbp),%rax
 10fd33a:	mov    (%rax),%rdi
 10fd33d:	mov    -0xa0(%rbp),%rax
 10fd344:	mov    (%rax),%rax
 10fd347:	mov    $0xffffffff,%edx
 10fd34c:	call   *0x70(%rax)
 10fd34f:	cmp    $0x137,%ebx
 10fd355:	mov    -0x50(%rbp),%r14
 10fd359:	mov    -0x88(%rbp),%rax
 10fd360:	je     10fd36b <core.runtime.Runtime.submitSafeDestination+0x16fb>
 10fd362:	cmp    $0x62,%ebx
 10fd365:	jne    10fd3fb <core.runtime.Runtime.submitSafeDestination+0x178b>
 10fd36b:	lock incq 0x60(%rax)
 10fd370:	cmpb   $0x0,-0xb4(%rbp)
 10fd377:	jne    10fd4db <core.runtime.Runtime.submitSafeDestination+0x186b>
 10fd37d:	mov    -0xd8(%rbp),%rcx
 10fd384:	test   %rcx,%rcx
 10fd387:	je     10fd47c <core.runtime.Runtime.submitSafeDestination+0x180c>
 10fd38d:	mov    -0xf0(%rbp),%rax
 10fd394:	testb  $0x1,0x2fd(%rax)
 10fd39b:	je     10fd4db <core.runtime.Runtime.submitSafeDestination+0x186b>
 10fd3a1:	mov    0x150(%rax),%rdx
 10fd3a8:	mov    %rdx,%rsi
 10fd3ab:	shr    $0x2,%rsi
 10fd3af:	xor    %rsi,%rcx
 10fd3b2:	and    $0x3,%edx
 10fd3b5:	or     %rcx,%rdx
 10fd3b8:	jne    10fd4db <core.runtime.Runtime.submitSafeDestination+0x186b>
 10fd3be:	mov    %fs:0xfffffffffffbb5a8,%rcx
 10fd3c7:	test   %rcx,%rcx
 10fd3ca:	je     10fd4db <core.runtime.Runtime.submitSafeDestination+0x186b>
 10fd3d0:	mov    0x148(%rax),%rdx
 10fd3d7:	cmp    %rcx,%rdx
 10fd3da:	jne    10fd4db <core.runtime.Runtime.submitSafeDestination+0x186b>
 10fd3e0:	mov    0x160(%rax),%edx
 10fd3e6:	cmpb   $0x1,%fs:0xfffffffffffbb5f4
 10fd3ef:	jne    10fd460 <core.runtime.Runtime.submitSafeDestination+0x17f0>
 10fd3f1:	mov    %fs:0xfffffffffffbb5f0,%eax
 10fd3f9:	jmp    10fd478 <core.runtime.Runtime.submitSafeDestination+0x1808>
 10fd3fb:	mov    %r15,%rdi
 10fd3fe:	mov    %ebx,%esi
 10fd400:	call   10fde20 <core.runtime.Runtime.reportError>
 10fd405:	lea    -0xf0(%rbp),%rdi
 10fd40c:	call   10fdfe0 <journal.journal.Reservation.abort>
 10fd411:	mov    %bx,(%r14)
 10fd415:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fd41a:	mov    -0x50(%rbp),%rcx
 10fd41e:	mov    %ax,(%rcx)
 10fd421:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fd426:	mov    $0xba,%eax
 10fd42b:	syscall
 10fd42d:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd435:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd43e:	cmp    %eax,%edx
 10fd440:	jne    10fd2f4 <core.runtime.Runtime.submitSafeDestination+0x1684>
 10fd446:	mov    -0xf0(%rbp),%r12
 10fd44d:	mov    -0xe8(%rbp),%rdx
 10fd454:	mov    -0xe0(%rbp),%r13
 10fd45b:	jmp    10fd2a1 <core.runtime.Runtime.submitSafeDestination+0x1631>
 10fd460:	mov    $0xba,%eax
 10fd465:	syscall
 10fd467:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd46f:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd478:	cmp    %eax,%edx
 10fd47a:	jne    10fd4db <core.runtime.Runtime.submitSafeDestination+0x186b>
 10fd47c:	mov    -0xf0(%rbp),%rax
 10fd483:	mov    -0xe8(%rbp),%rcx
 10fd48a:	mov    0x1a0(%rax),%rdx
 10fd491:	mov    0x200(%rax),%rsi
 10fd498:	imul   -0xe0(%rbp),%rsi
 10fd4a0:	lea    0x1(,%rcx,4),%rax
 10fd4a8:	lea    0x3(,%rcx,4),%rcx
 10fd4b0:	lock cmpxchg %rcx,0x1000(%rdx,%rsi,1)
 10fd4ba:	setne  -0x218(%rbp)
 10fd4c1:	jne    10fd4db <core.runtime.Runtime.submitSafeDestination+0x186b>
 10fd4c3:	cmpq   $0x0,-0xd8(%rbp)
 10fd4cb:	je     10fd4db <core.runtime.Runtime.submitSafeDestination+0x186b>
 10fd4cd:	mov    -0xf0(%rbp),%rax
 10fd4d4:	decq   0x158(%rax)
 10fd4db:	mov    -0x8b3ad(%rip),%eax        # 1072134 <__anon_33688>
 10fd4e1:	mov    %eax,(%r14)
 10fd4e4:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fd4e9:	and    $0x3,%eax
 10fd4ec:	cmp    $0x1,%eax
 10fd4ef:	jne    10fc629 <core.runtime.Runtime.submitSafeDestination+0x9b9>
 10fd4f5:	mov    -0x88(%rbp),%rax
 10fd4fc:	lock incq 0x58(%rax)
 10fd501:	mov    -0x8b36b(%rip),%eax        # 107219c <__anon_33633>
 10fd507:	jmp    10fc0ee <core.runtime.Runtime.submitSafeDestination+0x47e>
 10fd50c:	mov    -0x50(%rbp),%rcx
 10fd510:	mov    -0x88(%rbp),%rax
 10fd517:	lock incq 0x68(%rax)
 10fd51c:	xor    %eax,%eax
 10fd51e:	xchg   %al,(%r14)
 10fd521:	mov    -0x8b3d7(%rip),%eax        # 1072150 <__anon_33657>
 10fd527:	jmp    10fc0f2 <core.runtime.Runtime.submitSafeDestination+0x482>
 10fd52c:	mov    $0xba,%eax
 10fd531:	syscall
 10fd533:	mov    %eax,%fs:0xfffffffffffbb5f0
 10fd53b:	movb   $0x1,%fs:0xfffffffffffbb5f4
 10fd544:	cmp    %eax,%edx
 10fd546:	jne    10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd54c:	cmpb   $0x0,-0xb8(%rbp)
 10fd553:	mov    -0xf0(%rbp),%r14
 10fd55a:	je     10fd58a <core.runtime.Runtime.submitSafeDestination+0x191a>
 10fd55c:	cmpb   $0x0,0x288(%r14)
 10fd564:	je     10fd60b <core.runtime.Runtime.submitSafeDestination+0x199b>
 10fd56a:	lea    -0xd0(%rbp),%rsi
 10fd571:	lea    0x208(%r14),%rdi
 10fd578:	call   1132de0 <journal.schema.Registry.validateReady>
 10fd57d:	mov    -0x40(%rbp),%rdi
 10fd581:	test   %ax,%ax
 10fd584:	jne    10fd7da <core.runtime.Runtime.submitSafeDestination+0x1b6a>
 10fd58a:	mov    $0x13d,%bx
 10fd58e:	cmp    0x1f8(%r14),%r12
 10fd595:	ja     10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd597:	mov    0x200(%r14),%r13
 10fd59e:	imul   -0xe0(%rbp),%r13
 10fd5a6:	mov    0x1a0(%r14),%r8
 10fd5ad:	mov    0x1000(%r8,%r13,1),%rax
 10fd5b5:	mov    -0xe8(%rbp),%rcx
 10fd5bc:	lea    0x1(,%rcx,4),%rdx
 10fd5c4:	mov    $0x13c,%bx
 10fd5c8:	cmp    %rdx,%rax
 10fd5cb:	jne    10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
 10fd5cd:	mov    -0xf0(%rbp),%r15
 10fd5d4:	mov    -0xe0(%rbp),%rsi
 10fd5db:	mov    0x200(%r15),%rbx
 10fd5e2:	imul   %rsi,%rbx
 10fd5e6:	add    0x1a0(%r15),%rbx
 10fd5ed:	mov    0x1f0(%r15),%rdi
 10fd5f4:	lea    -0x1(%rcx),%rax
 10fd5f8:	mov    %rax,%rdx
 10fd5fb:	or     %rdi,%rdx
 10fd5fe:	shr    $0x20,%rdx
 10fd602:	je     10fd648 <core.runtime.Runtime.submitSafeDestination+0x19d8>
 10fd604:	xor    %edx,%edx
 10fd606:	div    %rdi
 10fd609:	jmp    10fd64c <core.runtime.Runtime.submitSafeDestination+0x19dc>
 10fd60b:	mov    $0x90,%bx
 10fd60f:	mov    %rdi,%rax
 10fd612:	shl    $0x6,%rax
 10fd616:	mov    -0x80(%rbp),%rdx
 10fd61a:	lea    0x9810(%rdx),%rcx
 10fd621:	test   %edi,%edi
 10fd623:	lea    -0x40(%rdx,%rax,1),%rax
 10fd628:	cmove  %rcx,%rax
 10fd62c:	lock decq (%rax)
 10fd630:	lea    -0xf0(%rbp),%rdi
 10fd637:	call   10fdfe0 <journal.journal.Reservation.abort>
 10fd63c:	mov    -0x50(%rbp),%rax
 10fd640:	mov    %bx,(%rax)
 10fd643:	jmp    10fc0f4 <core.runtime.Runtime.submitSafeDestination+0x484>
 10fd648:	xor    %edx,%edx
 10fd64a:	div    %edi
 10fd64c:	cmpl   $0x1,0x2f0(%r15)
 10fd654:	je     10fd6a3 <core.runtime.Runtime.submitSafeDestination+0x1a33>
 10fd656:	mov    -0xd0(%rbp),%edi
 10fd65c:	movzwl -0xcc(%rbp),%edx
 10fd663:	vxorps %xmm0,%xmm0,%xmm0
 10fd667:	cmpb   $0x0,-0xb8(%rbp)
 10fd66e:	vmovups %xmm0,0x1020(%rbx)
 10fd676:	movq   $0x0,0x1030(%rbx)
 10fd681:	je     10fd6a3 <core.runtime.Runtime.submitSafeDestination+0x1a33>
 10fd683:	mov    %edi,0x1020(%rbx)
 10fd689:	lea    -0xca(%rbp),%rdi
 10fd690:	mov    %dx,0x1024(%rbx)
 10fd697:	vmovups (%rdi),%xmm0
 10fd69b:	vmovups %xmm0,0x1028(%rbx)
 10fd6a3:	lea    0x0(,%rcx,4),%r14
 10fd6ab:	mov    %r12d,0x1018(%rbx)
 10fd6b2:	xor    %edx,%edx
 10fd6b4:	cmpb   $0x0,0x2fc(%r15)
 10fd6bc:	je     10fd785 <core.runtime.Runtime.submitSafeDestination+0x1b15>
 10fd6c2:	mov    %r8,-0x40(%rbp)
 10fd6c6:	inc    %rax
 10fd6c9:	mov    0x1a0(%r15),%rdx
 10fd6d0:	imul   0x200(%r15),%rsi
 10fd6d8:	add    %rsi,%rdx
 10fd6db:	add    $0x1040,%rdx
 10fd6e2:	mov    %rdx,-0x38(%rbp)
 10fd6e6:	cmpl   $0x1,0x2f0(%r15)
 10fd6ee:	jne    10fd71e <core.runtime.Runtime.submitSafeDestination+0x1aae>
 10fd6f0:	mov    %rcx,-0x218(%rbp)
 10fd6f7:	mov    %rax,-0x210(%rbp)
 10fd6fe:	mov    %r12d,-0x208(%rbp)
 10fd705:	movl   $0xffffffff,-0x44(%rbp)
 10fd70c:	lea    -0x44(%rbp),%rdi
 10fd710:	lea    -0x218(%rbp),%rsi
 10fd717:	mov    $0x14,%edx
 10fd71c:	jmp    10fd767 <core.runtime.Runtime.submitSafeDestination+0x1af7>
 10fd71e:	lea    0x1020(%rbx),%rdx
 10fd725:	mov    %rdx,-0x58(%rbp)
 10fd729:	mov    %rcx,-0x218(%rbp)
 10fd730:	mov    %rax,-0x210(%rbp)
 10fd737:	mov    %r12d,-0x208(%rbp)
 10fd73e:	movl   $0xffffffff,-0x44(%rbp)
 10fd745:	lea    -0x44(%rbp),%rdi
 10fd749:	lea    -0x218(%rbp),%rsi
 10fd750:	mov    $0x14,%edx
 10fd755:	call   113d770 <platform.crc32.Crc32.update>
 10fd75a:	mov    $0x18,%edx
 10fd75f:	lea    -0x44(%rbp),%rdi
 10fd763:	mov    -0x58(%rbp),%rsi
 10fd767:	call   113d770 <platform.crc32.Crc32.update>
 10fd76c:	lea    -0x44(%rbp),%rdi
 10fd770:	mov    -0x38(%rbp),%rsi
 10fd774:	mov    %r12,%rdx
 10fd777:	call   113d770 <platform.crc32.Crc32.update>
 10fd77c:	mov    -0x44(%rbp),%edx
 10fd77f:	not    %edx
 10fd781:	mov    -0x40(%rbp),%r8
 10fd785:	mov    %edx,0x101c(%rbx)
 10fd78b:	or     $0x2,%r14
 10fd78f:	mov    %r14,0x1000(%r8,%r13,1)
 10fd797:	cmpq   $0x0,-0xd8(%rbp)
 10fd79f:	je     10fd7a8 <core.runtime.Runtime.submitSafeDestination+0x1b38>
 10fd7a1:	decq   0x158(%r15)
 10fd7a8:	movb   $0x1,-0xb4(%rbp)
 10fd7af:	mov    -0x88(%rbp),%rax
 10fd7b6:	lock incq (%rax)
 10fd7ba:	mov    -0x60(%rbp),%rdi
 10fd7be:	call   10f5870 <core.runtime.Runtime.notify>
 10fd7c3:	lea    -0xf0(%rbp),%rdi
 10fd7ca:	call   10fdfe0 <journal.journal.Reservation.abort>
 10fd7cf:	mov    -0x8b6ad(%rip),%eax        # 1072128 <__anon_23525>
 10fd7d5:	jmp    10fc0ee <core.runtime.Runtime.submitSafeDestination+0x47e>
 10fd7da:	mov    %eax,%ebx
 10fd7dc:	jmp    10fd60f <core.runtime.Runtime.submitSafeDestination+0x199f>
