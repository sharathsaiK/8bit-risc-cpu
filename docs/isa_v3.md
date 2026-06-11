# ISA v3 Specification

This is the authoritative spec. The C++ simulator, Icarus, and Verilator must
implement it identically; `make cosim` enforces that.

## Instruction format (32-bit)

```
R-type: [31:26] opcode  [25:23] rd  [22:20] rs1  [19:17] rs2
I-type: [31:26] opcode  [25:23] rd  [15:0] imm16
```

## Opcodes

| # | Mnemonic | Semantics |
|---|----------|-----------|
| 0x00 | ADD rd,rs1,rs2 | rd = rs1 + rs2 (sets carry) |
| 0x01 | SUB rd,rs1,rs2 | rd = rs1 - rs2 (carry = no-borrow) |
| 0x02 | AND rd,rs1,rs2 | rd = rs1 & rs2 |
| 0x03 | OR  rd,rs1,rs2 | rd = rs1 \| rs2 |
| 0x04 | XOR rd,rs1,rs2 | rd = rs1 ^ rs2 |
| 0x05 | NOT rd,rs1     | rd = ~rs1 |
| 0x06 | SHL rd,rs1     | rd = rs1 << 1 |
| 0x07 | SHR rd,rs1     | rd = rs1 >> 1 |
| 0x08 | MUL rd,rs1,rs2 | rd = low 64 bits of rs1 * rs2 |
| 0x09 | DIV rd,rs1,rs2 | rd = rs1 / rs2 unsigned; div-by-0 -> all-ones |
| 0x0A | MOD rd,rs1,rs2 | rd = rs1 % rs2 unsigned; mod-by-0 -> rs1 |
| 0x0B | LDI rd,imm16   | rd = zero-extended imm16 |
| 0x0C | LD  rd,[rs1]   | rd = mem[rs1[15:0]] (or I/O read) |
| 0x0D | ST  [rs1],rs2  | mem[rs1[15:0]] = rs2 (or I/O write) |
| 0x0E | JMP imm16      | PC = imm16 |
| 0x0F | BEQ imm16      | if (zf) PC = imm16 |
| 0x10 | BNE imm16      | if (!zf) PC = imm16 |
| 0x11 | OUT rs1        | print rs1 (allowed in user mode) |
| 0x12 | HLT            | stop (kernel-only) |
| 0x13 | CALL imm16     | SP-=1; mem[SP]=PC+1; PC=imm16 |
| 0x14 | RET            | PC = mem[SP][15:0]; SP+=1 |
| 0x15 | PUSH rs1       | SP-=1; mem[SP]=rs1 |
| 0x16 | POP rd         | rd = mem[SP]; SP+=1 |
| 0x17 | STI            | ie = 1 (kernel-only) |
| 0x18 | CLI            | ie = 0 (kernel-only) |
| 0x19 | IRET           | pop frame, restore PC/flags/mode/ie (kernel-only) |

Pseudo-instructions: `MOV rd,rs` = ADD rd,rs,R0; `NOP` = ADD R0,R0,R0.
Any other opcode is invalid and raises an exception (cause 2).

## Flags

Every register-writing instruction (ADD..MOD, LDI, LD, POP) sets
zf = (written value == 0). Only ADD/SUB update cf. IRET restores both.

## Machine state

- R0..R7: 64-bit, R0 hardwired 0
- PC: 16-bit
- SP: 16-bit, reset 0xFF00, grows down (PUSH: SP-=1 then write mem[SP])
- mode: 1=kernel (reset), 0=user
- ie: interrupt enable, reset 0
- timer period / counter, interrupt vector (ivec), cause register

## Memory map (data memory, 65536 x 64-bit)

- 0x0000..0xFEFF: RAM (stack grows down from 0xFF00)
- 0xFF00+ : I/O region, kernel-only
  - 0xFF00 read : next value from the input stream (exhausted -> 0)
  - 0xFF01 write: console output (identical to OUT)
  - 0xFF02 r/w  : timer period (0 = timer off)
  - 0xFF04 r/w  : interrupt/exception vector (0 = no handler)
  - 0xFF05 read : cause of last trap (1=timer, 2=invalid opcode, 3=privilege)
  - any other I/O address: reads 0, writes ignored

## Trap entry/exit

Saved frame (one 64-bit word): `pc | zf<<16 | cf<<17 | mode<<18 | ie<<19`.

Entry (consumes one cycle, instruction at PC does not execute):
SP-=1; mem[SP]=frame; PC=ivec; mode=1; ie=0; cause=N.

- Interrupt: taken at the top of a cycle when (pending && ie && ivec!=0).
  Saved pc = PC (interrupted instruction runs after IRET). Clears pending.
- Exception (invalid opcode, or in user mode: privileged instruction or
  I/O-region LD/ST): saved pc = PC+1 (faulting instruction is skipped).
  Taken regardless of ie. If ivec==0 the CPU halts instead.

IRET: frame = mem[SP]; SP+=1; PC=frame[15:0]; zf=frame[16]; cf=frame[17];
mode=frame[18]; ie=frame[19].

Entering user mode: kernel pushes a crafted frame (mode bit 18 = 0) and IRETs.

## Cycle order (both simulators implement exactly this)

1. If (pending && ie && ivec!=0): interrupt entry. Else decode; if invalid or
   privilege violation: exception entry (or halt if ivec==0). Else execute.
2. After every cycle (including entry cycles), if period>0:
   counter+=1; if counter>=period { counter=0; pending=1 }.

## Privilege rules (user mode, mode==0)

- HLT, STI, CLI, IRET -> exception cause 3
- LD or ST with address >= 0xFF00 -> exception cause 3
- OUT is allowed.
