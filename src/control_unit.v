// Instruction format: [15:13]=opcode [12:10]=rd [9:7]=rs1 [6:4]=rs2 [7:0]=imm8
// opcodes: 000=ADD 001=SUB 010=AND 011=OR 100=XOR 101=LDI 110=JMP 111=BEQ
module control_unit (
    input  [2:0] opcode,
    input        zero,           // ALU zero flag
    output reg [2:0] alu_op,     // forwarded to ALU
    output reg       reg_write,  // enable register file write
    output reg       alu_src,    // 1 = use imm8 as second ALU operand
    output reg       pc_load,    // 1 = branch/jump taken
    output reg       mem_to_reg  // reserved (no data memory yet)
);
    always @(*) begin
        // defaults
        alu_op     = opcode;
        reg_write  = 1'b0;
        alu_src    = 1'b0;
        pc_load    = 1'b0;
        mem_to_reg = 1'b0;

        case (opcode)
            3'b000: begin reg_write=1; end                     // ADD
            3'b001: begin reg_write=1; end                     // SUB
            3'b010: begin reg_write=1; end                     // AND
            3'b011: begin reg_write=1; end                     // OR
            3'b100: begin reg_write=1; end                     // XOR
            3'b101: begin reg_write=1; alu_src=1; alu_op=3'b000; end  // LDI (add 0+imm)
            3'b110: begin pc_load=1; end                       // JMP
            3'b111: begin pc_load=zero; end                    // BEQ
        endcase
    end
endmodule
