; Deliberately destroy all argument registers while resolving a target, so a
; forwarding thunk that omits any save/restore cannot accidentally pass the test.
EXTERN AbiTarget:QWORD
EXTERN AbiIndex:DWORD
.code
PUBLIC NestGResolveDwm
NestGResolveDwm PROC
    mov AbiIndex, ecx
    mov rax, AbiTarget
    mov rcx, 11111111h
    mov rdx, 22222222h
    mov r8, 33333333h
    mov r9, 44444444h
    pxor xmm0, xmm0
    pxor xmm1, xmm1
    pxor xmm2, xmm2
    pxor xmm3, xmm3
    ret
NestGResolveDwm ENDP
END
