# 8-bit RISC CPU (Verilog)

A fully functional 8-bit RISC CPU implemented in Verilog, simulated with Icarus Verilog and visualized in GTKWave.

---

## Architecture

```
          ┌─────────────────────────────────────────────────────┐
          │                      CPU                            │
          │                                                     │
          │  ┌──────────┐    ┌──────────────────┐              │
          │  │  Program │    │  Instruction     │              │
          │  │  Counter │───▶│  Memory (ROM)    │              │
          │  │  (PC)    │    │  256 x 16-bit    │              │
          │  └──────────┘    └────────┬─────────┘              │
          │       ▲                   │ [15:0] instr            │
          │  pc_load + imm8           │                         │
          │       │          ┌────────▼─────────┐              │
          │       │          │  Control Unit    │              │
          │       │          │  (opcode decode) │              │
          │       │          └────────┬─────────┘              │
          │       │    ┌──────────────┤ alu_op, reg_write,      │
          │       │    │              │ alu_src, pc_load        │
          │       │    │     ┌────────▼─────────┐              │
          │       │    │     │  Register File   │              │
          │       │    │     │  R0–R7 (8x8-bit) │              │
          │       │    │     │  R0 = 0 always   │              │
          │       │    │     └──┬──────────┬────┘              │
          │       │    │    rs1 │          │ rs2 / imm8 (mux)  │
          │       │    │        │   ┌──────▼──────┐            │
          │       │    │        └──▶│     ALU     │            │
          │       │    │            │  8 ops      │            │
          │       │    │            │  zero flag  │            │
          │       │    │            └──────┬──────┘            │
          │       │    │           result  │                   │
          │       │    └──────────────────▶│ write_data        │
          │       └───────────── pc_load ◀─┘ (BEQ/JMP)        │
          └─────────────────────────────────────────────────────┘
```

**Pipeline:** Single-cycle (combinational decode + execute, register write on clock edge).

---

## ISA — Instruction Set Architecture

All instructions are **16 bits**:

```
[15:13] opcode  [12:10] rd  [9:7] rs1  [6:4] rs2  [7:0] imm8
```
> `rs2` and `imm8` share bits — the control unit selects which is used via `alu_src`.

| Opcode | Mnemonic | Operation | Type |
|--------|----------|-----------|------|
| `000`  | ADD      | R[rd] = R[rs1] + R[rs2] | R |
| `001`  | SUB      | R[rd] = R[rs1] − R[rs2] | R |
| `010`  | AND      | R[rd] = R[rs1] & R[rs2] | R |
| `011`  | OR       | R[rd] = R[rs1] \| R[rs2] | R |
| `100`  | XOR      | R[rd] = R[rs1] ^ R[rs2] | R |
| `101`  | LDI      | R[rd] = imm8 | I |
| `110`  | JMP      | PC = imm8 | J |
| `111`  | BEQ      | if (zero) PC = imm8 | J |

**ALU operations (3-bit `alu_op`):**
ADD, SUB, AND, OR, XOR, NOT, SHL, SHR

**Registers:** R0–R7 (8-bit). R0 is hardwired to 0.

---

## File Structure

```
8bit-risc-cpu/
├── src/
│   ├── half_adder.v        # 1-bit half adder
│   ├── full_adder.v        # 1-bit full adder (uses half_adder)
│   ├── alu.v               # 8-bit ALU, 8 operations
│   ├── register_file.v     # 8x8-bit register file
│   ├── program_counter.v   # 8-bit PC with load/reset
│   ├── instruction_memory.v# 256x16-bit ROM
│   ├── control_unit.v      # Opcode decoder
│   └── cpu.v               # Top-level integration
├── tests/
│   ├── half_adder_tb.v
│   ├── full_adder_tb.v
│   ├── alu_tb.v
│   ├── register_file_tb.v
│   ├── program_counter_tb.v
│   ├── instruction_memory_tb.v
│   ├── control_unit_tb.v
│   ├── cpu_tb.v            # Full CPU simulation
│   └── program.hex         # Test program loaded into ROM
└── sim/                    # Compiled binaries + VCD waveforms
```

---

## How to Run

### Prerequisites
```bash
brew install icarus-verilog
brew install --cask gtkwave
```

### Run all module tests
```bash
cd 8bit-risc-cpu

iverilog -o sim/half_adder_tb      src/half_adder.v tests/half_adder_tb.v && vvp sim/half_adder_tb
iverilog -o sim/full_adder_tb      src/half_adder.v src/full_adder.v tests/full_adder_tb.v && vvp sim/full_adder_tb
iverilog -o sim/alu_tb             src/half_adder.v src/full_adder.v src/alu.v tests/alu_tb.v && vvp sim/alu_tb
iverilog -o sim/register_file_tb   src/register_file.v tests/register_file_tb.v && vvp sim/register_file_tb
iverilog -o sim/program_counter_tb src/program_counter.v tests/program_counter_tb.v && vvp sim/program_counter_tb
iverilog -o sim/instruction_memory_tb src/instruction_memory.v tests/instruction_memory_tb.v && vvp sim/instruction_memory_tb
iverilog -o sim/control_unit_tb    src/control_unit.v tests/control_unit_tb.v && vvp sim/control_unit_tb
```

### Run the full CPU simulation
```bash
iverilog -o sim/cpu_tb \
  src/half_adder.v src/full_adder.v src/alu.v \
  src/register_file.v src/program_counter.v \
  src/instruction_memory.v src/control_unit.v \
  src/cpu.v tests/cpu_tb.v && vvp sim/cpu_tb
```

### View waveform
```bash
open /Applications/gtkwave.app sim/cpu_tb.vcd
```
In GTKWave: File → Open New Tab → `sim/cpu_tb.vcd`, then drag signals (`clk`, `rst`, `pc`, `opcode`, `alu_res`, `r1`–`r7`) into the wave viewer.

---

## C++ Extension — Assembler & Simulator

A standalone C++ toolchain that lets you write assembly, assemble it to hex, and run it — no Verilog toolchain needed.

### Files

| File | Purpose |
|------|---------|
| `cpp/assembler.cpp` | Two-pass assembler: `.asm` → `.hex` |
| `cpp/simulator.cpp` | Cycle-accurate CPU simulator with per-instruction trace |
| `cpp/test_program.asm` | Demo program exercising all opcodes and labels |
| `cpp/Makefile` | Builds both tools and runs end-to-end test |

### Build & Run

```bash
cd cpp
make          # builds assembler and simulator
make test     # assembles test_program.asm and simulates it
```

Or manually:

```bash
./assembler my_program.asm out.hex   # assemble
./simulator out.hex                  # simulate with trace
./simulator out.hex --no-trace       # just show final register state
```

### Assembly Syntax

```asm
; Comments with semicolon
        LDI R1, 10          ; load immediate (decimal or 0x hex)
        LDI R2, 0x05
        ADD R3, R1, R2      ; R-type: rd, rs1, rs2
        SUB R4, R1, R2
        AND R5, R1, R2
        OR  R6, R1, R2
        XOR R7, R1, R2
        SUB R1, R5, R5      ; sets zero flag
        BEQ SKIP            ; branch if zero flag set
        LDI R1, 0xFF        ; skipped
SKIP:   LDI R2, 0x42        ; label target
HALT:   JMP HALT            ; halt loop
```

### Simulator Trace Output

```
Cycle  PC   Instr  Op   Operands         Effect
-----  ---  -----  ---  ---------------  ------
  [00] a40a  LDI  R1, 0x0a  => R1=0x0a
  [01] a805  LDI  R2, 0x05  => R2=0x05
  [02] 0ca0  ADD  R3, R1, R2  => R3=0x0f
  [08] e00a  BEQ  0x0a
  [0a] a842  LDI  R2, 0x42  => R2=0x42
  [0b] c00b  JMP  0x0b
```

Each row shows: PC, raw 16-bit instruction word, mnemonic, operands, and the register effect after execution.

---

## Test Program

The program loaded into ROM (`tests/program.hex`) exercises every R-type instruction:

```asm
LDI R1, 0x0A      ; R1 = 10
LDI R2, 0x05      ; R2 = 5
ADD R3, R1, R2    ; R3 = 15  (0x0F)
SUB R4, R1, R2    ; R4 = 5   (0x05)
AND R5, R1, R2    ; R5 = 0   (0x0A & 0x05 = 0)
OR  R6, R1, R2    ; R6 = 15  (0x0F)
XOR R7, R1, R2    ; R7 = 15  (0x0F)
JMP 0x07          ; halt (jump to self)
```

Expected register state after simulation:

| Register | Value |
|----------|-------|
| R1 | `0x0A` |
| R2 | `0x05` |
| R3 | `0x0F` |
| R4 | `0x05` |
| R5 | `0x00` |
| R6 | `0x0F` |
| R7 | `0x0F` |
