.intel_syntax noprefix
.text
.extern NestGResolveDwm
.global NestGDwm0
.seh_proc NestGDwm0
NestGDwm0:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 0
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm1
.seh_proc NestGDwm1
NestGDwm1:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 1
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm2
.seh_proc NestGDwm2
NestGDwm2:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 2
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm3
.seh_proc NestGDwm3
NestGDwm3:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 3
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm4
.seh_proc NestGDwm4
NestGDwm4:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 4
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm5
.seh_proc NestGDwm5
NestGDwm5:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 5
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm6
.seh_proc NestGDwm6
NestGDwm6:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 6
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm7
.seh_proc NestGDwm7
NestGDwm7:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 7
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm8
.seh_proc NestGDwm8
NestGDwm8:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 8
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm9
.seh_proc NestGDwm9
NestGDwm9:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 9
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm10
.seh_proc NestGDwm10
NestGDwm10:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 10
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm11
.seh_proc NestGDwm11
NestGDwm11:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 11
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm12
.seh_proc NestGDwm12
NestGDwm12:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 12
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm13
.seh_proc NestGDwm13
NestGDwm13:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 13
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm14
.seh_proc NestGDwm14
NestGDwm14:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 14
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm15
.seh_proc NestGDwm15
NestGDwm15:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 15
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm16
.seh_proc NestGDwm16
NestGDwm16:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 16
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm17
.seh_proc NestGDwm17
NestGDwm17:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 17
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm18
.seh_proc NestGDwm18
NestGDwm18:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 18
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm19
.seh_proc NestGDwm19
NestGDwm19:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 19
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm20
.seh_proc NestGDwm20
NestGDwm20:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 20
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm21
.seh_proc NestGDwm21
NestGDwm21:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 21
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm22
.seh_proc NestGDwm22
NestGDwm22:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 22
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm23
.seh_proc NestGDwm23
NestGDwm23:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 23
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm24
.seh_proc NestGDwm24
NestGDwm24:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 24
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm25
.seh_proc NestGDwm25
NestGDwm25:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 25
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm26
.seh_proc NestGDwm26
NestGDwm26:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 26
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm27
.seh_proc NestGDwm27
NestGDwm27:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 27
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm28
.seh_proc NestGDwm28
NestGDwm28:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 28
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm29
.seh_proc NestGDwm29
NestGDwm29:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 29
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm30
.seh_proc NestGDwm30
NestGDwm30:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 30
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm31
.seh_proc NestGDwm31
NestGDwm31:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 31
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm32
.seh_proc NestGDwm32
NestGDwm32:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 32
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm33
.seh_proc NestGDwm33
NestGDwm33:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 33
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm34
.seh_proc NestGDwm34
NestGDwm34:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 34
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm35
.seh_proc NestGDwm35
NestGDwm35:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 35
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm36
.seh_proc NestGDwm36
NestGDwm36:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 36
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm37
.seh_proc NestGDwm37
NestGDwm37:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 37
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm38
.seh_proc NestGDwm38
NestGDwm38:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 38
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm39
.seh_proc NestGDwm39
NestGDwm39:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 39
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm40
.seh_proc NestGDwm40
NestGDwm40:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 40
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm41
.seh_proc NestGDwm41
NestGDwm41:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 41
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm42
.seh_proc NestGDwm42
NestGDwm42:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 42
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm43
.seh_proc NestGDwm43
NestGDwm43:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 43
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm44
.seh_proc NestGDwm44
NestGDwm44:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 44
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm45
.seh_proc NestGDwm45
NestGDwm45:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 45
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm46
.seh_proc NestGDwm46
NestGDwm46:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 46
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm47
.seh_proc NestGDwm47
NestGDwm47:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 47
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm48
.seh_proc NestGDwm48
NestGDwm48:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 48
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm49
.seh_proc NestGDwm49
NestGDwm49:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 49
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm50
.seh_proc NestGDwm50
NestGDwm50:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 50
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm51
.seh_proc NestGDwm51
NestGDwm51:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 51
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm52
.seh_proc NestGDwm52
NestGDwm52:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 52
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm53
.seh_proc NestGDwm53
NestGDwm53:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 53
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm54
.seh_proc NestGDwm54
NestGDwm54:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 54
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm55
.seh_proc NestGDwm55
NestGDwm55:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 55
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm56
.seh_proc NestGDwm56
NestGDwm56:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 56
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm57
.seh_proc NestGDwm57
NestGDwm57:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 57
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm58
.seh_proc NestGDwm58
NestGDwm58:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 58
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm59
.seh_proc NestGDwm59
NestGDwm59:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 59
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm60
.seh_proc NestGDwm60
NestGDwm60:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 60
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm61
.seh_proc NestGDwm61
NestGDwm61:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 61
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm62
.seh_proc NestGDwm62
NestGDwm62:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 62
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm63
.seh_proc NestGDwm63
NestGDwm63:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 63
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm64
.seh_proc NestGDwm64
NestGDwm64:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 64
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm65
.seh_proc NestGDwm65
NestGDwm65:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 65
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm66
.seh_proc NestGDwm66
NestGDwm66:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 66
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm67
.seh_proc NestGDwm67
NestGDwm67:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 67
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm68
.seh_proc NestGDwm68
NestGDwm68:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 68
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm69
.seh_proc NestGDwm69
NestGDwm69:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 69
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm70
.seh_proc NestGDwm70
NestGDwm70:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 70
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm71
.seh_proc NestGDwm71
NestGDwm71:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 71
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm72
.seh_proc NestGDwm72
NestGDwm72:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 72
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm73
.seh_proc NestGDwm73
NestGDwm73:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 73
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm74
.seh_proc NestGDwm74
NestGDwm74:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 74
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm75
.seh_proc NestGDwm75
NestGDwm75:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 75
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm76
.seh_proc NestGDwm76
NestGDwm76:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 76
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm77
.seh_proc NestGDwm77
NestGDwm77:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 77
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm78
.seh_proc NestGDwm78
NestGDwm78:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 78
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm79
.seh_proc NestGDwm79
NestGDwm79:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 79
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm80
.seh_proc NestGDwm80
NestGDwm80:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 80
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm81
.seh_proc NestGDwm81
NestGDwm81:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 81
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm82
.seh_proc NestGDwm82
NestGDwm82:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 82
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm83
.seh_proc NestGDwm83
NestGDwm83:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 83
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm84
.seh_proc NestGDwm84
NestGDwm84:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 84
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm85
.seh_proc NestGDwm85
NestGDwm85:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 85
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm86
.seh_proc NestGDwm86
NestGDwm86:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 86
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm87
.seh_proc NestGDwm87
NestGDwm87:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 87
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm88
.seh_proc NestGDwm88
NestGDwm88:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 88
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm89
.seh_proc NestGDwm89
NestGDwm89:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 89
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm90
.seh_proc NestGDwm90
NestGDwm90:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 90
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm91
.seh_proc NestGDwm91
NestGDwm91:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 91
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm92
.seh_proc NestGDwm92
NestGDwm92:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 92
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm93
.seh_proc NestGDwm93
NestGDwm93:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 93
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm94
.seh_proc NestGDwm94
NestGDwm94:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 94
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm95
.seh_proc NestGDwm95
NestGDwm95:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 95
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm96
.seh_proc NestGDwm96
NestGDwm96:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 96
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm97
.seh_proc NestGDwm97
NestGDwm97:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 97
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm98
.seh_proc NestGDwm98
NestGDwm98:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 98
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm99
.seh_proc NestGDwm99
NestGDwm99:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 99
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm100
.seh_proc NestGDwm100
NestGDwm100:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 100
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm101
.seh_proc NestGDwm101
NestGDwm101:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 101
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
.global NestGDwm102
.seh_proc NestGDwm102
NestGDwm102:
 sub rsp, 0xA8
 .seh_stackalloc 0xA8
 .seh_endprologue
 mov [rsp+0x20], rcx
 mov [rsp+0x28], rdx
 mov [rsp+0x30], r8
 mov [rsp+0x38], r9
 movdqu [rsp+0x40], xmm0
 movdqu [rsp+0x50], xmm1
 movdqu [rsp+0x60], xmm2
 movdqu [rsp+0x70], xmm3
 mov ecx, 102
 call NestGResolveDwm
 mov rcx, [rsp+0x20]
 mov rdx, [rsp+0x28]
 mov r8, [rsp+0x30]
 mov r9, [rsp+0x38]
 movdqu xmm0, [rsp+0x40]
 movdqu xmm1, [rsp+0x50]
 movdqu xmm2, [rsp+0x60]
 movdqu xmm3, [rsp+0x70]
 add rsp, 0xA8
 jmp rax
.seh_endproc
