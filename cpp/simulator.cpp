#include <iostream>
#include <fstream>
#include <iomanip>
#include <string>
#include <array>
#include <vector>
#include <cstdint>
#include <stdexcept>

// ISA v3 — see docs/isa_v3.md. This simulator is the reference model;
// `make cosim` checks it against the Verilog gate-level implementation.

enum Op : uint8_t { ADD=0x00, SUB=0x01, AND=0x02, OR=0x03, XOR=0x04,
                    NOT=0x05, SHL=0x06, SHR=0x07, MUL=0x08, DIV=0x09,
                    MOD=0x0A, LDI=0x0B, LD=0x0C, ST=0x0D, JMP=0x0E,
                    BEQ=0x0F, BNE=0x10, OUT=0x11, HLT=0x12, CALL=0x13,
                    RET=0x14, PUSH=0x15, POP=0x16, STI=0x17, CLI=0x18,
                    IRET=0x19 };

static const char* OP_NAMES[] = {"ADD","SUB","AND","OR","XOR","NOT","SHL","SHR",
                                 "MUL","DIV","MOD","LDI","LD","ST","JMP","BEQ",
                                 "BNE","OUT","HLT","CALL","RET","PUSH","POP",
                                 "STI","CLI","IRET"};
static const int NUM_OPS = 0x1A;

using word = uint64_t;             // data path width (matches Verilog WIDTH=64)
constexpr int WORD_HEX = 16;       // hex digits when printing a word

// I/O region (kernel-only)
constexpr uint16_t IO_BASE  = 0xFF00;
constexpr uint16_t IO_IN    = 0xFF00;
constexpr uint16_t IO_OUT   = 0xFF01;
constexpr uint16_t IO_TIMER = 0xFF02;
constexpr uint16_t IO_IVEC  = 0xFF04;
constexpr uint16_t IO_CAUSE = 0xFF05;

// trap causes
constexpr word CAUSE_TIMER = 1, CAUSE_INVALID = 2, CAUSE_PRIV = 3;

struct CPU {
    std::vector<uint32_t> imem = std::vector<uint32_t>(65536, 0);
    std::vector<word>     dmem = std::vector<word>(65536, 0);
    std::array<word,8>    reg {};      // R0–R7
    uint16_t pc        = 0;
    uint16_t sp        = 0xFF00;       // grows down
    bool     zero_flag = false;
    bool     carry_flag= false;
    bool     kernel    = true;         // mode: 1=kernel
    bool     ie        = false;        // interrupt enable
    bool     irq_pending = false;
    word     timer_period = 0;
    word     timer_count  = 0;
    uint16_t ivec      = 0;            // 0 = no handler installed
    word     cause     = 0;
    bool     halted    = false;
    uint64_t cycles    = 0;
    bool     cosim     = false;        // machine-readable OUT lines only

    std::vector<word> input;           // values served by reads of IO_IN
    size_t            input_pos = 0;

    void load_hex(const std::string& path) {
        std::ifstream f(path);
        if (!f) throw std::runtime_error("Cannot open hex file: " + path);
        std::string line;
        int addr = 0;
        while (std::getline(f, line)) {
            auto c = line.find('/');
            if (c != std::string::npos) line = line.substr(0, c);
            while (!line.empty() && (line.back()==' '||line.back()=='\r'||line.back()=='\n'))
                line.pop_back();
            if (line.empty()) continue;
            if (addr >= 65536) throw std::runtime_error("Program too large");
            imem[addr++] = (uint32_t)std::stoul(line, nullptr, 16);
        }
    }

    void load_input(const std::string& path) {
        std::ifstream f(path);
        if (!f) throw std::runtime_error("Cannot open input file: " + path);
        std::string line;
        while (std::getline(f, line)) {
            line = line.substr(0, line.find('/'));
            while (!line.empty() && (line.back()==' '||line.back()=='\r'))
                line.pop_back();
            if (!line.empty())
                input.push_back((word)std::stoull(line, nullptr, 16));
        }
    }

    void print_out(word v) {
        if (cosim)
            std::cout << "OUT " << std::hex << std::setfill('0')
                      << std::setw(WORD_HEX) << v << std::dec << "\n";
    }

    word io_read(uint16_t addr) {
        switch (addr) {
            case IO_IN:    return input_pos < input.size() ? input[input_pos++] : 0;
            case IO_TIMER: return timer_period;
            case IO_IVEC:  return ivec;
            case IO_CAUSE: return cause;
            default:       return 0;
        }
    }

    bool timer_written = false;   // programming the timer skips that cycle's tick

    void io_write(uint16_t addr, word v) {
        switch (addr) {
            case IO_OUT:   print_out(v); break;
            case IO_TIMER: timer_period = v; timer_count = 0; timer_written = true; break;
            case IO_IVEC:  ivec = (uint16_t)v; break;
            default:       break;   // ignored
        }
    }

    // saved frame: pc | zf<<16 | cf<<17 | mode<<18 | ie<<19
    word make_frame(uint16_t saved_pc) const {
        return (word)saved_pc | ((word)zero_flag<<16) | ((word)carry_flag<<17)
             | ((word)kernel<<18) | ((word)ie<<19);
    }

    void trap_entry(uint16_t saved_pc, word c, bool trace, const char* what) {
        sp -= 1;
        dmem[sp] = make_frame(saved_pc);
        if (trace)
            std::cout << "  ---- " << what << " (cause " << c
                      << "): frame pushed, PC -> 0x" << std::hex << ivec
                      << std::dec << " ----\n";
        pc = ivec;
        kernel = true;
        ie = false;
        cause = c;
    }

    void tick_timer() {
        if (timer_written) { timer_written = false; return; }
        if (timer_period > 0) {
            timer_count += 1;
            if (timer_count >= timer_period) {
                timer_count = 0;
                irq_pending = true;
            }
        }
    }

    // Execute one cycle (instruction or trap entry); false once halted
    bool step(bool trace) {
        // 1. interrupt?
        if (irq_pending && ie && ivec != 0) {
            irq_pending = false;
            trap_entry(pc, CAUSE_TIMER, trace, "IRQ");
            ++cycles;
            tick_timer();
            // 2-stage pipeline bubble after trap entry
            ++cycles;
            tick_timer();
            return true;
        }

        uint32_t instr = imem[pc];
        uint8_t opcode = (instr >> 26) & 0x3F;
        uint8_t rd     = (instr >> 23) & 0x7;
        uint8_t rs1    = (instr >> 20) & 0x7;
        uint8_t rs2    = (instr >> 17) & 0x7;
        uint16_t imm16 =  instr        & 0xFFFF;

        word a = reg[rs1];
        word b = reg[rs2];
        uint16_t maddr = (uint16_t)(a & 0xFFFF);

        // 2. exception?
        bool invalid = opcode >= NUM_OPS;
        bool priv    = !kernel &&
                       (opcode==HLT || opcode==STI || opcode==CLI || opcode==IRET ||
                        ((opcode==LD || opcode==ST) && maddr >= IO_BASE));
        if (invalid || priv) {
            word c = invalid ? CAUSE_INVALID : CAUSE_PRIV;
            if (ivec == 0) {
                halted = true;
                if (trace) std::cout << "  ---- unhandled trap (cause " << c
                                     << ") at PC=0x" << std::hex << pc
                                     << std::dec << ": halting ----\n";
                ++cycles;
                return false;
            }
            trap_entry((uint16_t)(pc + 1), c, trace, invalid ? "EXC invalid" : "EXC privilege");
            ++cycles;
            tick_timer();
            // 2-stage pipeline bubble after trap entry
            ++cycles;
            tick_timer();
            return true;
        }

        // 3. execute
        word result = 0;
        bool write_reg = false;
        bool branch    = false;
        uint16_t branch_target = imm16;

        switch ((Op)opcode) {
            case ADD: { unsigned __int128 r = (unsigned __int128)a + b;
                        result=(word)r; carry_flag=(r>>64)&1; write_reg=true; break; }
            case SUB: { unsigned __int128 r = (unsigned __int128)a + (word)(~b) + 1;
                        result=(word)r; carry_flag=(r>>64)&1; write_reg=true; break; }
            case AND: result = a & b;    write_reg=true; break;
            case OR:  result = a | b;    write_reg=true; break;
            case XOR: result = a ^ b;    write_reg=true; break;
            case NOT: result = ~a;       write_reg=true; break;
            case SHL: result = a << 1;   write_reg=true; break;
            case SHR: result = a >> 1;   write_reg=true; break;
            case MUL: result = a * b;    write_reg=true; break;
            case DIV: result = b ? a / b : ~(word)0; write_reg=true; break;
            case MOD: result = b ? a % b : a;        write_reg=true; break;
            case LDI: result = imm16;    write_reg=true; break;
            case LD:  result = (maddr >= IO_BASE) ? io_read(maddr) : dmem[maddr];
                      write_reg=true; break;
            case ST:  if (maddr >= IO_BASE) io_write(maddr, b);
                      else dmem[maddr] = b;
                      break;
            case JMP:  branch = true; break;
            case BEQ:  branch = zero_flag;  break;
            case BNE:  branch = !zero_flag; break;
            case OUT:  print_out(a); break;
            case HLT:  halted = true; break;
            case CALL: sp -= 1; dmem[sp] = (word)(pc + 1);
                       branch = true; break;
            case RET:  branch = true; branch_target = (uint16_t)dmem[sp]; sp += 1; break;
            case PUSH: sp -= 1; dmem[sp] = a; break;
            case POP:  result = dmem[sp]; sp += 1; write_reg=true; break;
            case STI:  ie = true;  break;
            case CLI:  ie = false; break;
            case IRET: {
                word f = dmem[sp]; sp += 1;
                branch = true; branch_target = (uint16_t)(f & 0xFFFF);
                zero_flag  = (f>>16)&1;
                carry_flag = (f>>17)&1;
                kernel     = (f>>18)&1;
                ie         = (f>>19)&1;
                break;
            }
        }

        if (write_reg && rd != 0)
            reg[rd] = result;
        if (write_reg)
            zero_flag = (result == 0);

        uint16_t next_pc = halted ? pc : (branch ? branch_target : (uint16_t)(pc + 1));

        if (trace) {
            std::cout << std::hex << std::setfill('0')
                      << "  [" << std::setw(4) << (int)pc << "] "
                      << std::setw(8) << instr << "  ";
            std::cout << std::setfill(' ') << std::left << std::setw(4) << OP_NAMES[opcode]
                      << std::right << std::setfill('0');
            switch ((Op)opcode) {
                case ADD: case SUB: case AND: case OR: case XOR:
                case MUL: case DIV: case MOD:
                    std::cout << " R" << (int)rd << ", R" << (int)rs1 << ", R" << (int)rs2; break;
                case NOT: case SHL: case SHR:
                    std::cout << " R" << (int)rd << ", R" << (int)rs1; break;
                case LDI:
                    std::cout << " R" << (int)rd << ", 0x" << std::setw(4) << (int)imm16; break;
                case LD:
                    std::cout << " R" << (int)rd << ", [R" << (int)rs1 << "]"; break;
                case ST:
                    std::cout << " [R" << (int)rs1 << "], R" << (int)rs2; break;
                case JMP: case BEQ: case BNE: case CALL:
                    std::cout << " 0x" << std::setw(4) << (int)imm16; break;
                case OUT: case PUSH:
                    std::cout << " R" << (int)rs1; break;
                case POP:
                    std::cout << " R" << (int)rd; break;
                default: break;
            }
            if (write_reg && rd != 0)
                std::cout << "  => R" << (int)rd << "=0x" << reg[rd];
            if (opcode == ST)
                std::cout << "  => mem[0x" << std::setw(4) << (int)maddr << "]=0x" << b;
            if (opcode == OUT && !cosim)
                std::cout << "  => prints 0x" << a;
            if (opcode == CALL || opcode == RET || opcode == PUSH || opcode == POP)
                std::cout << "  (SP=0x" << std::setw(4) << (int)sp << ")";
            std::cout << "\n" << std::dec;
        }

        pc = next_pc;
        ++cycles;
        tick_timer();
        // 2-stage pipeline: taken branch/call/ret/iret squashes the IF stage →
        // one bubble cycle during which the timer still ticks.
        if (branch && !halted) {
            ++cycles;
            tick_timer();
        }
        return !halted;
    }

    void run(uint64_t max_cycles = 10000000, bool trace = true) {
        if (trace)
            std::cout << "Cycle  PC     Instr     Op   Operands         Effect\n"
                      << "-----  ----   --------  ---  ---------------  ------\n";
        while (cycles < max_cycles) {
            if (!step(trace)) break;
        }
        if (cycles >= max_cycles)
            std::cerr << "WARNING: hit cycle limit (" << max_cycles << ") — possible infinite loop\n";
    }

    // Print the register file (two rows of four), highlighting changed registers
    void print_reg_line(const std::array<word,8>& prev) const {
        for (int i = 0; i < 8; ++i) {
            if (i % 4 == 0) std::cout << "       ";
            bool changed = reg[i] != prev[i];
            if (changed) std::cout << "\033[1;32m";
            std::cout << "R" << i << "=" << std::hex << std::setfill('0')
                      << std::setw(WORD_HEX) << reg[i];
            if (changed) std::cout << "\033[0m";
            std::cout << ((i % 4 == 3) ? "" : "  ");
            if (i == 3) std::cout << "\n";
        }
        std::cout << std::dec << "   z=" << zero_flag << " c=" << carry_flag
                  << " mode=" << (kernel ? "kern" : "user")
                  << " ie=" << ie << std::hex << " sp=" << sp << std::dec << "\n";
    }

    void run_stepped(uint64_t max_cycles = 10000000) {
        std::cout << "Step mode: Enter = next cycle, q = quit\n\n"
                  << "Cycle  PC     Instr     Op   Operands         Effect\n"
                  << "-----  ----   --------  ---  ---------------  ------\n";
        while (cycles < max_cycles) {
            std::array<word,8> prev = reg;
            bool running = step(true);
            print_reg_line(prev);
            if (!running) {
                std::cout << "\nCPU halted after " << cycles << " cycles.\n";
                break;
            }
            std::string line;
            if (!std::getline(std::cin, line) || line == "q") break;
        }
    }

    void dump_regs() const {
        std::cout << "\nRegister file:\n";
        for (int i = 0; i < 8; ++i)
            std::cout << "  R" << i << " = 0x" << std::hex << std::setfill('0')
                      << std::setw(WORD_HEX) << reg[i]
                      << "  (" << std::dec << reg[i] << ")\n";
        std::cout << std::hex << "  PC = 0x" << std::setw(4) << (int)pc
                  << "   SP = 0x" << std::setw(4) << (int)sp << "\n" << std::dec;
        std::cout << "  zero=" << zero_flag << "  carry=" << carry_flag
                  << "  mode=" << (kernel ? "kernel" : "user") << "  ie=" << ie
                  << "  cycles=" << cycles << "\n";
    }

    // machine-readable final state, matches run_tb.v output for cosim diff
    void dump_cosim() const {
        std::cout << std::hex << std::setfill('0');
        for (int i = 1; i < 8; ++i)
            std::cout << "R" << std::dec << i << "=" << std::hex
                      << std::setw(WORD_HEX) << reg[i] << "\n";
        std::cout << "PC=" << std::setw(4) << (int)pc << "\n";
        std::cout << "SP=" << std::setw(4) << (int)sp << std::dec << "\n";
    }
};

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: simulator <program.hex> [--no-trace] [--step] [--cosim] [--in=<file>]\n";
        return 1;
    }
    bool trace = true;
    bool step_mode = false;
    bool cosim = false;
    std::string input_file;
    for (int i = 2; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--no-trace") trace = false;
        if (a == "--step")     step_mode = true;
        if (a == "--cosim")    { cosim = true; trace = false; }
        if (a.rfind("--in=", 0) == 0) input_file = a.substr(5);
    }

    try {
        CPU cpu;
        cpu.cosim = cosim;
        cpu.load_hex(argv[1]);
        if (!input_file.empty()) cpu.load_input(input_file);
        if (step_mode) cpu.run_stepped();
        else           cpu.run(10000000, trace);
        if (cosim) cpu.dump_cosim();
        else       cpu.dump_regs();
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
