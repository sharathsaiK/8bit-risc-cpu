#include <iostream>
#include <fstream>
#include <iomanip>
#include <string>
#include <array>
#include <cstdint>
#include <stdexcept>

// Opcodes matching the Verilog ISA
enum Op : uint8_t { ADD=0, SUB=1, AND=2, OR=3, XOR=4, LDI=5, JMP=6, BEQ=7 };

static const char* OP_NAMES[] = {"ADD","SUB","AND","OR","XOR","LDI","JMP","BEQ"};

struct CPU {
    std::array<uint8_t,256> rom  {};
    std::array<uint8_t,256> rom_hi{};   // high byte of each 16-bit word
    std::array<uint16_t,256> imem{};
    std::array<uint8_t,8>   reg  {};    // R0–R7
    uint8_t  pc        = 0;
    bool     zero_flag = false;
    bool     carry_flag= false;
    uint64_t cycles    = 0;

    void load_hex(const std::string& path) {
        std::ifstream f(path);
        if (!f) throw std::runtime_error("Cannot open hex file: " + path);
        std::string line;
        int addr = 0;
        while (std::getline(f, line)) {
            // strip comments and whitespace
            auto c = line.find('/');
            if (c != std::string::npos) line = line.substr(0, c);
            while (!line.empty() && (line.back()==' '||line.back()=='\r'||line.back()=='\n'))
                line.pop_back();
            if (line.empty()) continue;
            if (addr >= 256) throw std::runtime_error("Program too large");
            imem[addr++] = (uint16_t)std::stoi(line, nullptr, 16);
        }
    }

    // Execute one instruction, return false when halting (JMP to self)
    bool step(bool trace) {
        uint16_t instr = imem[pc];
        uint8_t opcode = (instr >> 13) & 0x7;
        uint8_t rd     = (instr >> 10) & 0x7;
        uint8_t rs1    = (instr >>  7) & 0x7;
        uint8_t rs2    = (instr >>  4) & 0x7;
        uint8_t imm8   =  instr        & 0xFF;

        uint8_t a = reg[rs1];
        uint8_t b = reg[rs2];
        uint8_t result = 0;
        bool    write_reg = false;
        bool    branch    = false;

        switch ((Op)opcode) {
            case ADD: { uint16_t r = (uint16_t)a + b;  result=r&0xFF; carry_flag=(r>>8)&1; write_reg=true; break; }
            case SUB: { uint16_t r = (uint16_t)a + (uint8_t)(~b) + 1; result=r&0xFF; carry_flag=(r>>8)&1; write_reg=true; break; }
            case AND: result = a & b;  write_reg=true; break;
            case OR:  result = a | b;  write_reg=true; break;
            case XOR: result = a ^ b;  write_reg=true; break;
            case LDI: result = imm8;   write_reg=true; break;
            case JMP: branch  = true;  break;
            case BEQ: branch  = zero_flag; break;
        }

        if (write_reg && rd != 0)
            reg[rd] = result;
        if (write_reg)
            zero_flag = (result == 0);

        uint8_t next_pc = branch ? imm8 : (uint8_t)(pc + 1);

        if (trace) {
            // print PC and raw instruction word
            std::cout << std::hex << std::setfill('0')
                      << "  [" << std::setw(2) << (int)pc << "] "
                      << std::setw(4) << instr << "  ";
            // mnemonic (space-padded)
            std::cout << std::setfill(' ') << std::left << std::setw(4) << OP_NAMES[opcode]
                      << std::right << std::setfill('0');
            if (opcode <= XOR)
                std::cout << " R" << (int)rd << ", R" << (int)rs1 << ", R" << (int)rs2;
            else if (opcode == LDI)
                std::cout << " R" << (int)rd << ", 0x" << std::setw(2) << (int)imm8;
            else
                std::cout << " 0x" << std::setw(2) << (int)imm8;
            if (write_reg && rd != 0)
                std::cout << "  => R" << (int)rd << "=0x" << std::setw(2) << (int)reg[rd];
            std::cout << "\n" << std::dec;
        }

        bool halted = (branch && imm8 == pc);
        pc = next_pc;
        ++cycles;
        return !halted;
    }

    void run(int max_cycles = 100000, bool trace = true) {
        if (trace)
            std::cout << "Cycle  PC   Instr  Op   Operands         Effect\n"
                      << "-----  ---  -----  ---  ---------------  ------\n";
        while (cycles < (uint64_t)max_cycles) {
            if (!step(trace)) break;
        }
        if (cycles >= (uint64_t)max_cycles)
            std::cerr << "WARNING: hit cycle limit (" << max_cycles << ") — possible infinite loop\n";
    }

    void dump_regs() const {
        std::cout << "\nRegister file:\n";
        for (int i = 0; i < 8; ++i)
            std::cout << "  R" << i << " = 0x" << std::hex << std::setfill('0')
                      << std::setw(2) << (int)reg[i]
                      << "  (" << std::dec << (int)reg[i] << ")\n";
        std::cout << "  PC = 0x" << std::hex << std::setw(2) << (int)pc << "\n";
        std::cout << "  zero=" << zero_flag << "  carry=" << carry_flag
                  << "  cycles=" << std::dec << cycles << "\n";
    }
};

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: simulator <program.hex> [--no-trace]\n";
        return 1;
    }
    bool trace = true;
    for (int i = 2; i < argc; ++i)
        if (std::string(argv[i]) == "--no-trace") trace = false;

    try {
        CPU cpu;
        cpu.load_hex(argv[1]);
        cpu.run(100000, trace);
        cpu.dump_regs();
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
