; timer_irq.asm — tests timer-driven interrupts.
;
; Sets up a handler that increments R2 on each IRQ.
; Main: runs a 30-iteration loop then halts.
; Timer period: 10 cycles; ie is enabled during the loop.
; OUT R2 at the end prints the IRQ count for cosim comparison.
;
; Layout (instruction addresses):
;   0-8   : setup
;   9     : LOOP (SUB R1, R1, R5)
;   10    : BNE LOOP
;   11    : CLI
;   12    : OUT R2
;   13    : HLT
;   14    : HANDLER (ADD R2, R2, R5)
;   15    : IRET

        LDI  R5, 1          ; 0:  R5=1 (shared constant)
        LDI  R1, HANDLER    ; 1:  handler address (resolved by assembler)
        LDI  R4, 0xFF04     ; 2:  IO_IVEC address
        ST   [R4], R1       ; 3:  ivec = HANDLER
        LDI  R4, 0xFF02     ; 4:  IO_TIMER address
        LDI  R1, 10         ; 5:  timer period = 10
        ST   [R4], R1       ; 6:  start timer (tick skipped this cycle)
        LDI  R1, 30         ; 7:  loop count
        STI                 ; 8:  enable interrupts

LOOP:   SUB  R1, R1, R5    ; 9:  R1--
        BNE  LOOP           ; 10: loop while R1 != 0

        CLI                 ; 11: disable interrupts
        OUT  R2             ; 12: print IRQ count
        HLT                 ; 13

HANDLER:
        ADD  R2, R2, R5    ; 14: R2++ (IRQ counter)
        IRET               ; 15: return to interrupted instruction
