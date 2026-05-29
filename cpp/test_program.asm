; 8-bit RISC CPU test program
; Exercises every instruction including labels and BEQ

        LDI R1, 10          ; R1 = 10
        LDI R2, 5           ; R2 = 5
        ADD R3, R1, R2      ; R3 = 15
        SUB R4, R1, R2      ; R4 = 5
        AND R5, R1, R2      ; R5 = 0  (0x0A & 0x05)
        OR  R6, R1, R2      ; R6 = 15 (0x0A | 0x05)
        XOR R7, R1, R2      ; R7 = 15 (0x0A ^ 0x05)

; BEQ test: R5 == 0, so zero flag is set from last XOR? No, reset with SUB
        SUB R1, R5, R5      ; R1 = 0, sets zero flag
        BEQ SKIP            ; zero=1, branch to SKIP
        LDI R1, 0xFF        ; should NOT execute

SKIP:   LDI R2, 0x42        ; R2 = 0x42, proves branch was taken

HALT:   JMP HALT            ; infinite loop (halt)
