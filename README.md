# 64-bit RISC CPU (Verilog) — ISA v3

A fully custom **64-bit pipelined RISC processor** built from scratch in Verilog, with a
hand-written C++ assembler and cycle-accurate simulator.  Verified by **three-engine
co-simulation**: every program is run on Icarus Verilog, Verilator, and the C++ simulator —
outputs must match byte-for-byte.

---

## What this CPU can do

| Feature | Detail |
|---------|--------|
| **Data width** | 64-bit registers, ALU, and memory words |
| **Pipeline** | 5-stage IF / ID / EX / MEM / WB with full forwarding |
| **Instruction set** | 26 instructions — arithmetic, logic, memory, control flow, I/O, interrupts |
| **Registers** | R0–R7 (64-bit); R0 hardwired to 0 |
| **Memory** | 64K × 64-bit data RAM + 64K × 32-bit instruction ROM |
| **Hardware stack** | PUSH / POP / CALL / RET with a dedicated stack pointer |
| **Interrupts** | Programmable timer — fires a hardware interrupt at a set period |
| **Privilege levels** | Kernel mode and user mode; I/O and privileged instructions are kernel-only |
| **Exceptions** | Invalid opcode and privilege-violation exceptions with a trap handler |
| **Console I/O** | Memory-mapped OUT (print), IN (read), TIMER, IVEC, CAUSE ports |
| **Toolchain** | C++ assembler (labels, hex/decimal literals) + simulator (trace, step, cosim modes) |

---

## Pipeline

```
  ┌────┐  IF/ID  ┌────┐  ID/EX  ┌────┐  EX/MEM  ┌─────┐  MEM/WB  ┌────┐
  │ IF │────────▶│ ID │────────▶│ EX │─────────▶│ MEM │─────────▶│ WB │
  └────┘         └────┘         └────┘           └─────┘           └────┘
   Fetch          Decode          ALU +            Forward           Write
   from ROM       read regs       memory +         result            result to
                  (write-first    branch           to next           register
                  bypass)         resolution       stage             file
```

**Forwarding paths** (no stalls except control hazards):

| Path | Covers |
|------|--------|
| EX/MEM → EX | instruction immediately after a producer |
| MEM/WB → EX | two instructions after a producer |
| MEM/WB → ID | three instructions after (write-first register-file bypass) |

**Control hazard:** taken branches, calls, returns, and traps flush both IF/ID and ID/EX
→ **2-cycle bubble**. No load-use stalls because data-memory reads are combinational in EX.

---

## Instruction Set (ISA v3)

All instructions are **32 bits**:

```
R-type: [31:26] opcode  [25:23] rd  [22:20] rs1  [19:17] rs2  [16:0] —
I-type: [31:26] opcode  [25:23] rd  [22:20] rs1  [15:0]  imm16
```

| Mnemonic | Operation |
|----------|-----------|
| ADD / SUB | 64-bit add / subtract (sets carry flag) |
| AND / OR / XOR / NOT | bitwise logic |
| SHL / SHR | shift left / right by 1 |
| MUL / DIV / MOD | multiply, divide, modulo |
| LDI | load 16-bit immediate (zero-extended) |
| LD / ST | load / store 64-bit word from/to data memory or I/O port |
| JMP / BEQ / BNE | unconditional / conditional branches |
| CALL / RET | subroutine call (pushes return address) / return |
| PUSH / POP | stack operations |
| OUT | print a register to the output stream |
| STI / CLI | enable / disable interrupts |
| IRET | return from interrupt (restores flags, mode, PC) |
| HLT | stop the CPU |

---

## Memory Map

| Address | Port | Access | Description |
|---------|------|--------|-------------|
| `0x0000–0xFEFF` | — | user + kernel | General-purpose data RAM |
| `0xFF00` | IO_IN | kernel | Read next value from input stream |
| `0xFF01` | IO_OUT | kernel | Write value to output stream (also triggers OUT) |
| `0xFF02` | IO_TIMER | kernel | Set timer period (0 = disabled) |
| `0xFF04` | IO_IVEC | kernel | Interrupt/exception handler address |
| `0xFF05` | IO_CAUSE | kernel | Trap cause: 1=timer, 2=invalid opcode, 3=privilege |

---

## File Structure

```
8bit-risc-cpu/
├── Makefile
├── src/
│   ├── cpu.v               # top-level: 5-stage pipeline, forwarding, traps
│   ├── alu.v               # 64-bit ALU (ADD/SUB/AND/OR/XOR/NOT/SHL/SHR/MUL/DIV/MOD)
│   ├── control_unit.v      # 6-bit opcode decoder
│   ├── register_file.v     # 8 × 64-bit registers (R0 hardwired to 0)
│   ├── data_memory.v       # 64K × 64-bit RAM (sync write, comb read)
│   ├── instruction_memory.v# 64K × 32-bit ROM
│   ├── program_counter.v   # 16-bit PC with load/halt/reset
│   ├── half_adder.v / full_adder.v
├── tests/
│   ├── cpu_tb.v            # self-checking full-CPU test
│   ├── run_tb.v            # generic runner (+hex=<file>)
│   ├── cosim.sh            # 3-engine co-simulation diff
│   └── *.hex               # assembled test programs
├── cpp/
│   ├── assembler.cpp       # two-pass assembler (.asm → .hex)
│   ├── simulator.cpp       # cycle-accurate C++ simulator (trace/step/cosim)
│   ├── test_program.asm    # exercises all 26 instructions
│   ├── fib.asm             # Fibonacci (prints fib(0)–fib(93))
│   ├── timer_irq.asm       # timer interrupt test
│   ├── privilege.asm       # user-mode privilege violation test
│   └── invalid_opcode.asm  # exception handling test
└── sim/                    # compiled testbenches + VCD waveforms
```

---

## How to Run

### Prerequisites
```bash
brew install icarus-verilog verilator surfer
```

### Build and test everything
```bash
make all      # build C++ tools, assemble programs, compile Icarus + Verilator
make test     # unit tests + self-checking CPU test
make cosim    # run all 5 programs on C++, Icarus, and Verilator — diff outputs
```

### Write and run your own program
```bash
./cpp/assembler my_prog.asm my_prog.hex     # assemble
./cpp/simulator my_prog.hex                 # software trace
./cpp/simulator my_prog.hex --step          # step one instruction at a time
vvp sim/run_tb +hex=my_prog.hex            # run on Verilog hardware (Icarus)
./obj_dir/Vrun_tb +hex=my_prog.hex          # run on Verilog hardware (Verilator)
tests/cosim.sh my_prog.hex                  # prove all three agree
```

### View waveforms
```bash
vvp sim/cpu_tb          # generates sim/cpu_tb.vcd
surfer sim/cpu_tb.vcd   # open in Surfer
```

In Surfer: drill into the `cpu_tb/uut` scope and add `if_id_*`, `id_ex_*`,
`ex_mem_*`, `mem_wb_*` signals to watch instructions move through the 5 stages.

---

## Assembly Syntax

```asm
; semicolon comments
        LDI  R1, 10           ; load immediate (decimal or 0x hex)
        LDI  R2, 0xFF04       ; 16-bit immediate
        ST   [R2], R1         ; mem[R2] = R1  (store)
        LD   R3, [R2]         ; R3 = mem[R2]  (load)
        ADD  R4, R1, R3       ; rd, rs1, rs2
        CALL MYFUNC           ; push return addr, jump to label
MYFUNC: MUL  R1, R1, R3
        RET
        STI                   ; enable interrupts
        CLI                   ; disable interrupts
        OUT  R1               ; print R1
        HLT
```

---

## Test Programs

| File | What it tests |
|------|--------------|
| `test_program.asm` | All 26 instructions, CALL/RET, PUSH/POP, branches, memory |
| `fib.asm` | Fibonacci up to fib(93) via a recursive-style loop |
| `timer_irq.asm` | Timer fires every 10 cycles; handler counts interrupts |
| `privilege.asm` | User-mode code triggers a privilege exception, kernel handles it |
| `invalid_opcode.asm` | Bad opcode triggers an exception, kernel halts cleanly |

All five pass co-simulation: C++ simulator, Icarus Verilog, and Verilator produce
identical output.
