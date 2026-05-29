module cpu (
    input clk,
    input rst
);
    // --- Fetch ---
    wire [7:0]  pc;
    wire [15:0] instr;

    // --- Decode ---
    wire [2:0] opcode = instr[15:13];
    wire [2:0] rd     = instr[12:10];
    wire [2:0] rs1    = instr[9:7];
    wire [2:0] rs2    = instr[6:4];
    wire [7:0] imm8   = instr[7:0];

    // --- Control signals ---
    wire [2:0] alu_op;
    wire       reg_write, alu_src, pc_load;
    wire       mem_to_reg;   // reserved

    // --- Register file outputs ---
    wire [7:0] rdata1, rdata2;

    // --- ALU ---
    wire [7:0] alu_result;
    wire       zero, carry_out;
    wire [7:0] alu_b = alu_src ? imm8 : rdata2;

    // --- PC branch target ---
    // JMP/BEQ use imm8 as absolute address
    program_counter pc_inst (
        .clk(clk), .rst(rst),
        .load(pc_load), .pc_in(imm8),
        .pc_out(pc)
    );

    instruction_memory imem (
        .addr(pc),
        .instruction(instr)
    );

    control_unit cu (
        .opcode(opcode), .zero(zero),
        .alu_op(alu_op), .reg_write(reg_write),
        .alu_src(alu_src), .pc_load(pc_load),
        .mem_to_reg(mem_to_reg)
    );

    register_file rf (
        .clk(clk), .we(reg_write),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .write_data(alu_result),
        .read_data1(rdata1), .read_data2(rdata2)
    );

    alu alu_inst (
        .a(rdata1), .b(alu_b), .op(alu_op),
        .result(alu_result), .zero(zero), .carry_out(carry_out)
    );
endmodule
