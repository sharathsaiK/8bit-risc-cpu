; ISA v3 comprehensive test — see tests/cpu_tb.v for expected register values.
;
; Final state expected:
;   R1=0x2A   (21 doubled by CALL DOUBLE — tests MUL + CALL/RET)
;   R2=0xABCD (LDI)
;   R3=0xABCD (PUSH/POP round-trip)
;   R4=0x00   (SUB R1,R1)
;   R5=0x00   (MOD 10 % 5 = 0)
;   R6=0x02   (MOD 7 % 5 = 2)
;   R7=0x42   (set after branch tests)
;   mem[256]=0xABCD (ST [0x100] test)
;   SP=0xFF00 (balanced)
;   PC=0x22   (HLT at address 34)

        LDI  R1, 21         ; 0: R1 = 21
        CALL DOUBLE         ; 1: SP-=1; mem[SP]=2; PC=DOUBLE(28)  ->  R1=42

        LDI  R2, 0xABCD    ; 2: R2 = 0xABCD
        LDI  R5, 0x100     ; 3: R5 = 256 (address for ST)
        ST   [R5], R2       ; 4: mem[256] = 0xABCD
        PUSH R2             ; 5: stack: mem[SP-1]=0xABCD, SP-=1
        POP  R3             ; 6: R3 = 0xABCD, SP+=1
        SUB  R4, R1, R1    ; 7: R4 = 0, ZF=1

        LDI  R5, 10         ; 8: R5 = 10
        LDI  R6, 5          ; 9: R6 = 5
        MOD  R5, R5, R6    ; 10: R5 = 10 % 5 = 0
        LDI  R7, 7          ; 11: R7 = 7
        MOD  R6, R7, R6    ; 12: R6 = 7 % 5 = 2

; branch tests — must end with R7=0x42
        SUB  R7, R1, R1    ; 13: R7 = 0, ZF=1 (42-42=0)
        BEQ  TAKEN1         ; 14: ZF=1 -> jump to 16
        LDI  R7, 0xEE      ; 15: NOT executed
TAKEN1: BNE  BAD            ; 16: ZF=1 -> NOT taken
        LDI  R7, 0x42      ; 17: R7 = 0x42, ZF=0
        BNE  TAKEN2         ; 18: ZF=0 -> jump to 20
        LDI  R7, 0xDD      ; 19: NOT executed
TAKEN2: OUT  R7             ; 20: print 0x42
        JMP  END            ; 21: jump to END(34)
BAD:    LDI  R7, 0xBB      ; 22: NOT executed
        NOP                 ; 23
        NOP                 ; 24
        NOP                 ; 25
        NOP                 ; 26
        NOP                 ; 27

; DOUBLE subroutine: multiplies R1 by 2 using a temp in R5.
; (R5 is overwritten here; main resets it at instruction 8.)
DOUBLE: LDI  R5, 2          ; 28: temp = 2
        MUL  R1, R1, R5    ; 29: R1 = R1 * 2
        RET                 ; 30: PC = mem[SP]; SP+=1

        NOP                 ; 31
        NOP                 ; 32
        NOP                 ; 33
END:    HLT                 ; 34 = 0x22
