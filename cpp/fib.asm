; Fibonacci — prints fib(0)..fib(93) via OUT.
; fib(93) = 12,200,160,415,121,876,738 — needs the full 64-bit registers.
        LDI R4, 94          ; how many numbers to print
        LDI R1, 0           ; a
        LDI R2, 1           ; b
        LDI R5, 1           ; constant 1
LOOP:   OUT R1              ; print a
        ADD R3, R1, R2      ; next = a + b
        MOV R1, R2          ; a = b
        MOV R2, R3          ; b = next
        SUB R4, R4, R5      ; count--
        BNE LOOP            ; loop while count != 0
        HLT
