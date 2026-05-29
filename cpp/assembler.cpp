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

// Instruction format: [15:13]=opcode [12:10]=rd [9:7]=rs1 [6:4]=rs2 [7:0]=imm8
// R-type: ADD SUB AND OR XOR
// I-type: LDI (op=101, rd, imm8)
// J-type: JMP BEQ (op=110/111, imm8 = label or literal)

struct Line {
    int         addr;
    std::string label;   // defined label (may be empty)
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

// Parse "R3" or "r3" -> 3
static int parse_reg(const std::string& s, int srcline) {
    std::string u = toupper_str(trim(s));
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
        return (int)std::stoi(u, nullptr, 0);
    } catch (...) {
        throw std::runtime_error("line " + std::to_string(srcline) + ": bad immediate '" + s + "'");
    }
}

static uint16_t encode_r(int op, int rd, int rs1, int rs2) {
    return (uint16_t)(((op&7)<<13)|((rd&7)<<10)|((rs1&7)<<7)|((rs2&7)<<4));
}

static uint16_t encode_i(int op, int rd, int imm8) {
    return (uint16_t)(((op&7)<<13)|((rd&7)<<10)|(imm8&0xFF));
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: assembler <input.asm> <output.hex>\n";
        return 1;
    }

    std::ifstream fin(argv[1]);
    if (!fin) { std::cerr << "Cannot open " << argv[1] << "\n"; return 1; }

    std::unordered_map<std::string,int> opcodes = {
        {"ADD",0},{"SUB",1},{"AND",2},{"OR",3},{"XOR",4},
        {"LDI",5},{"JMP",6},{"BEQ",7}
    };
    std::unordered_map<std::string,int> labels;
    std::vector<Line> lines;

    // Pass 1: tokenize + collect labels
    std::string raw;
    int srcline = 0;
    int addr = 0;
    while (std::getline(fin, raw)) {
        ++srcline;
        // strip comments
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
        if (opcodes.find(l.mnemonic) == opcodes.end())
            throw std::runtime_error("line " + std::to_string(srcline) + ": unknown mnemonic '" + l.mnemonic + "'");

        // read comma-separated args
        std::string rest;
        std::getline(ss, rest);
        std::istringstream ars(rest);
        std::string arg;
        while (std::getline(ars, arg, ','))
            l.args.push_back(trim(arg));

        lines.push_back(l);
        ++addr;
    }

    if (addr > 256)
        throw std::runtime_error("Program too large: " + std::to_string(addr) + " instructions (max 256)");

    // Pass 2: encode
    std::vector<uint16_t> rom(addr);
    for (auto& l : lines) {
        int op = opcodes[l.mnemonic];
        uint16_t enc = 0;

        auto resolve = [&](const std::string& s) -> int {
            std::string u = toupper_str(trim(s));
            if (labels.count(u)) return labels[u];
            return parse_imm(s, l.srcline);
        };

        if (l.mnemonic == "ADD" || l.mnemonic == "SUB" ||
            l.mnemonic == "AND" || l.mnemonic == "OR"  || l.mnemonic == "XOR") {
            if (l.args.size() != 3)
                throw std::runtime_error("line " + std::to_string(l.srcline) + ": " + l.mnemonic + " needs rd,rs1,rs2");
            enc = encode_r(op, parse_reg(l.args[0],l.srcline),
                               parse_reg(l.args[1],l.srcline),
                               parse_reg(l.args[2],l.srcline));
        } else if (l.mnemonic == "LDI") {
            if (l.args.size() != 2)
                throw std::runtime_error("line " + std::to_string(l.srcline) + ": LDI needs rd,imm");
            int imm = parse_imm(l.args[1], l.srcline);
            if (imm < 0 || imm > 255)
                throw std::runtime_error("line " + std::to_string(l.srcline) + ": LDI immediate out of range");
            enc = encode_i(op, parse_reg(l.args[0],l.srcline), imm);
        } else if (l.mnemonic == "JMP" || l.mnemonic == "BEQ") {
            if (l.args.size() != 1)
                throw std::runtime_error("line " + std::to_string(l.srcline) + ": " + l.mnemonic + " needs imm/label");
            enc = encode_i(op, 0, resolve(l.args[0]));
        }
        rom[l.addr] = enc;
    }

    // Write hex
    std::ofstream fout(argv[2]);
    if (!fout) { std::cerr << "Cannot write " << argv[2] << "\n"; return 1; }
    for (auto w : rom)
        fout << std::uppercase << std::hex
             << std::setw(4) << std::setfill('0') << w << "\n";  // need <iomanip>

    std::cout << "Assembled " << addr << " instruction(s) -> " << argv[2] << "\n";
    return 0;
}
