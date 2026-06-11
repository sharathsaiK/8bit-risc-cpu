; privilege.asm — tests privilege mode switching and privilege exceptions.
;
; Kernel switches to user mode via a crafted IRET frame (mode bit = 0).
; User code executes OUT (legal), then HLT twice (privilege violation each time).
; The handler (kernel) increments R3; on the second violation it halts.
;
; Expected OUT sequence: 0x63 (99), 0x2a (42)
; Final: R3=2, PC=0x13 (HLT at DONE=19), SP=0xFEFF (second frame unpopped)
;
; Layout:
;   0-9    : kernel setup + IRET into user mode
;   10     : USER_START (OUT R1)
;   11     : HLT -- trap 1
;   12     : OUT R2   (after returning from trap 1)
;   13     : HLT -- trap 2
;   14     : HANDLER (ADD R3...)
;   18     : IRET
;   19     : DONE / HLT

        LDI  R5, 1          ; 0: constant
        LDI  R1, HANDLER    ; 1: HANDLER=14
        LDI  R4, 0xFF04     ; 2: IO_IVEC
        ST   [R4], R1       ; 3: ivec = HANDLER
        LDI  R1, 99         ; 4: first print value  (0x63)
        LDI  R2, 42         ; 5: second print value (0x2A)
        LDI  R3, 0          ; 6: exception counter

; Build user-mode entry frame: frame = USER_START | (mode=0)<<18 | ...
; USER_START=10 < 2^16 and < 2^18, so bits 16-19 are 0 → mode=0, ie=0, zf=0, cf=0.
        LDI  R4, USER_START ; 7: R4 = 10 (user entry frame)
        PUSH R4             ; 8: push frame to stack
        IRET                ; 9: enter user mode at USER_START (mode=0, ie=0)

; -------- user-mode code --------
USER_START:
        OUT  R1             ; 10: print 99  (legal in user mode)
        HLT                 ; 11: privilege trap -> HANDLER; saved_pc=12
        ; execution resumes here after HANDLER's first IRET:
        OUT  R2             ; 12: print 42
        HLT                 ; 13: privilege trap -> HANDLER; saved_pc=14

; -------- kernel handler --------
HANDLER:
        ADD  R3, R3, R5    ; 14: R3++
        LDI  R4, 2          ; 15: threshold
        SUB  R4, R3, R4    ; 16: R4 = R3 - 2; ZF=1 iff R3==2
        BEQ  DONE           ; 17: if R3==2, we're done
        IRET               ; 18: return to user (restores mode=0, ie=0)

DONE:   HLT                 ; 19 = 0x13 — final halt in kernel mode
