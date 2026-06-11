#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <stdexcept>

// ISA v3 — 32-bit instructions (see docs/isa_v3.md):
//   R-type: [31:26]=opcode [25:23]=rd [22:20]=rs1 [19:17]=rs2
//   I-type: [31:26]=opcode [25:23]=rd [15:0]=imm16
//
// Syntax:
//   ADD/SUB/AND/OR/XOR/MUL/DIV/MOD rd, rs1, rs2
//   NOT/SHL/SHR rd, rs1            MOV rd, rs (pseudo: ADD rd, rs, R0)
//   LDI rd, imm16                  LD rd, [rs1]     ST [rs1], rs2
//   JMP/BEQ/BNE/CALL label|imm     OUT rs1          PUSH rs1   POP rd
//   RET   STI   CLI   IRET   HLT   NOP (pseudo: ADD R0, R0, R0)

struct Line {
    int         addr;
    std::string label;
    std::string mnemonic;
    std::vector<std::string> args;
    int         srcline;
};

static std::string trim(const std::string& s) {
    auto b = s.find_first_not_of(" \t\r\n");
    if (b == std::string::npos) return "";
    auto e = s.find_last_not_of(" \t\r\n");
    return s.substr(b, e - b + 1);
}

static std::string toupper_str(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), ::toupper);
    return s;
}

// Parse "R3", "r3", or "[R3]" -> 3
static int parse_reg(const std::string& s, int srcline) {
    std::string u = toupper_str(trim(s));
    if (u.size() >= 2 && u.front() == '[' && u.back() == ']')
        u = trim(u.substr(1, u.size() - 2));
    if (u.size() < 2 || u[0] != 'R')
        throw std::runtime_error("line " + std::to_string(srcline) + ": expected register, got '" + s + "'");
    int n = std::stoi(u.substr(1));
    if (n < 0 || n > 7)
        throw std::runtime_error("line " + std::to_string(srcline) + ": register out of range R" + std::to_string(n));
    return n;
}

// Parse integer literal: decimal or 0x hex
static int parse_imm(const std::string& s, int srcline) {
    std::string u = trim(s);
    try {
        return (int)std::stol(u, nullptr, 0);
    } catch (...) {
        throw std::runtime_error("line " + std::to_string(srcline) + ": bad immediate '" + s + "'");
    }
}

static uint32_t encode_r(int op, int rd, int rs1, int rs2) {
    return ((uint32_t)(op&63)<<26)|((uint32_t)(rd&7)<<23)|((uint32_t)(rs1&7)<<20)|((uint32_t)(rs2&7)<<17);
}

static uint32_t encode_i(int op, int rd, int imm16) {
    return ((uint32_t)(op&63)<<26)|((uint32_t)(rd&7)<<23)|((uint32_t)imm16&0xFFFF);
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: assembler <input.asm> <output.hex>\n";
        return 1;
    }

    std::ifstream fin(argv[1]);
    if (!fin) { std::cerr << "Cannot open " << argv[1] << "\n"; return 1; }

    std::unordered_map<std::string,int> opcodes = {
        {"ADD",0x00},{"SUB",0x01},{"AND",0x02},{"OR",0x03},{"XOR",0x04},
        {"NOT",0x05},{"SHL",0x06},{"SHR",0x07},{"MUL",0x08},{"DIV",0x09},
        {"MOD",0x0A},{"LDI",0x0B},{"LD",0x0C},{"ST",0x0D},{"JMP",0x0E},
        {"BEQ",0x0F},{"BNE",0x10},{"OUT",0x11},{"HLT",0x12},{"CALL",0x13},
        {"RET",0x14},{"PUSH",0x15},{"POP",0x16},{"STI",0x17},{"CLI",0x18},
        {"IRET",0x19},
        {"MOV",0x00},  // pseudo: ADD rd, rs, R0
        {"NOP",0x00}   // pseudo: ADD R0, R0, R0
    };
    std::unordered_map<std::string,int> labels;
    std::vector<Line> lines;

    // Pass 1: tokenize + collect labels
    std::string raw;
    int srcline = 0;
    int addr = 0;
    while (std::getline(fin, raw)) {
        ++srcline;
        auto cpos = raw.find(';');
        if (cpos != std::string::npos) raw = raw.substr(0, cpos);
        raw = trim(raw);
        if (raw.empty()) continue;

        Line l;
        l.srcline = srcline;
        l.addr    = addr;

        // Check for label: "LOOP: ADD ..."
        auto colon = raw.find(':');
        if (colon != std::string::npos) {
            l.label = toupper_str(trim(raw.substr(0, colon)));
            raw = trim(raw.substr(colon + 1));
            if (!l.label.empty())
                labels[l.label] = addr;
        }
        if (raw.empty()) continue;  // label-only line

        std::istringstream ss(raw);
        std::string tok;
        ss >> tok;
        l.mnemonic = toupper_str(tok);
        if (l.mnemonic != ".WORD" && opcodes.find(l.mnemonic) == opcodes.end())
            throw std::runtime_error("line " + std::to_string(srcline) + ": unknown mnemonic '" + l.mnemonic + "'");

        std::string rest;
        std::getline(ss, rest);
        std::istringstream ars(rest);
        std::string arg;
        while (std::getline(ars, arg, ','))
            l.args.push_back(trim(arg));

        lines.push_back(l);
        ++addr;
    }

    if (addr > 65536)
        throw std::runtime_error("Program too large: " + std::to_string(addr) + " instructions (max 65536)");

    // Pass 2: encode
    std::vector<uint32_t> rom(addr);
    for (auto& l : lines) {
        int op = l.mnemonic == ".WORD" ? -1 : opcodes[l.mnemonic];
        uint32_t enc = 0;

        auto resolve = [&](const std::string& s) -> int {
            std::string u = toupper_str(trim(s));
            if (labels.count(u)) return labels[u];
            return parse_imm(s, l.srcline);
        };
        auto need_args = [&](size_t n, const char* usage) {
            if (l.args.size() != n)
                throw std::runtime_error("line " + std::to_string(l.srcline) + ": " + l.mnemonic + " needs " + usage);
        };

        if (l.mnemonic == ".WORD") {
            need_args(1, "imm32");
            enc = (uint32_t)(unsigned long)std::stoul(trim(l.args[0]), nullptr, 0);
        } else if (l.mnemonic == "ADD" || l.mnemonic == "SUB" || l.mnemonic == "AND" ||
            l.mnemonic == "OR"  || l.mnemonic == "XOR" || l.mnemonic == "MUL" ||
            l.mnemonic == "DIV" || l.mnemonic == "MOD") {
            need_args(3, "rd,rs1,rs2");
            enc = encode_r(op, parse_reg(l.args[0],l.srcline),
                               parse_reg(l.args[1],l.srcline),
                               parse_reg(l.args[2],l.srcline));
        } else if (l.mnemonic == "MOV") {
            need_args(2, "rd,rs");
            enc = encode_r(op, parse_reg(l.args[0],l.srcline),
                               parse_reg(l.args[1],l.srcline), 0);
        } else if (l.mnemonic == "NOP") {
            need_args(0, "no operands");
            enc = encode_r(op, 0, 0, 0);
        } else if (l.mnemonic == "NOT" || l.mnemonic == "SHL" || l.mnemonic == "SHR") {
            need_args(2, "rd,rs1");
            enc = encode_r(op, parse_reg(l.args[0],l.srcline),
                               parse_reg(l.args[1],l.srcline), 0);
        } else if (l.mnemonic == "LDI") {
            need_args(2, "rd,imm");
            int imm = resolve(l.args[1]);   // labels allowed: LDI R2, HANDLER
            if (imm < 0 || imm > 65535)
                throw std::runtime_error("line " + std::to_string(l.srcline) + ": LDI immediate out of range (0..65535)");
            enc = encode_i(op, parse_reg(l.args[0],l.srcline), imm);
        } else if (l.mnemonic == "LD") {
            need_args(2, "rd,[rs1]");
            enc = encode_r(op, parse_reg(l.args[0],l.srcline),
                               parse_reg(l.args[1],l.srcline), 0);
        } else if (l.mnemonic == "ST") {
            need_args(2, "[rs1],rs2");
            enc = encode_r(op, 0, parse_reg(l.args[0],l.srcline),
                                  parse_reg(l.args[1],l.srcline));
        } else if (l.mnemonic == "JMP" || l.mnemonic == "BEQ" ||
                   l.mnemonic == "BNE" || l.mnemonic == "CALL") {
            need_args(1, "imm/label");
            enc = encode_i(op, 0, resolve(l.args[0]));
        } else if (l.mnemonic == "OUT" || l.mnemonic == "PUSH") {
            need_args(1, "rs1");
            enc = encode_r(op, 0, parse_reg(l.args[0],l.srcline), 0);
        } else if (l.mnemonic == "POP") {
            need_args(1, "rd");
            enc = encode_r(op, parse_reg(l.args[0],l.srcline), 0, 0);
        } else { // RET, STI, CLI, IRET, HLT
            need_args(0, "no operands");
            enc = encode_r(op, 0, 0, 0);
        }
        rom[l.addr] = enc;
    }

    // Write hex (8 digits per 32-bit word)
    std::ofstream fout(argv[2]);
    if (!fout) { std::cerr << "Cannot write " << argv[2] << "\n"; return 1; }
    for (auto w : rom)
        fout << std::uppercase << std::hex
             << std::setw(8) << std::setfill('0') << w << "\n";

    std::cout << "Assembled " << addr << " instruction(s) -> " << argv[2] << "\n";
    return 0;
}
