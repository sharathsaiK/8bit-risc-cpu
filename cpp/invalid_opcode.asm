; invalid_opcode.asm — tests exception handling for invalid opcodes (cause=2).
;
; An invalid opcode (0x1A = first unused opcode) is embedded with .word.
; The exception handler increments R3 and returns (saved_pc = PC+1, so
; the faulting instruction is skipped and execution continues normally).
;
; Expected: OUT 0x42, R3=1, PC=0x8 (HLT), SP=0xFF00
;
; Layout:
;   0-5  : setup
;   6    : .word 0x68000000  (opcode=0x1A invalid, triggers exception)
;   7    : OUT R1
;   8    : HLT
;   9    : HANDLER (ADD R3, R3, R5)
;   10   : IRET

        LDI  R5, 1          ; 0: constant
        LDI  R1, HANDLER    ; 1: handler address (HANDLER=9)
        LDI  R4, 0xFF04     ; 2: IO_IVEC
        ST   [R4], R1       ; 3: ivec = HANDLER
        LDI  R1, 0x42       ; 4: value to OUT after trap
        LDI  R3, 0          ; 5: exception counter

        .word 0x68000000    ; 6: opcode=0x1A (invalid) -> exception cause=2
        ; execution resumes at 7 after IRET (faulting instruction skipped):
        OUT  R1             ; 7: print 0x42
        HLT                 ; 8 = 0x08

HANDLER:
        ADD  R3, R3, R5    ; 9:  R3++
        IRET               ; 10: return to PC+1 (instruction after the fault)
