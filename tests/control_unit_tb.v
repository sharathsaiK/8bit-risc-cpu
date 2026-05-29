`timescale 1ns/1ps

module control_unit_tb;
    reg  [2:0] opcode;
    reg        zero;
    wire [2:0] alu_op;
    wire       reg_write, alu_src, pc_load, mem_to_reg;

    control_unit uut (
        .opcode(opcode), .zero(zero),
        .alu_op(alu_op), .reg_write(reg_write),
        .alu_src(alu_src), .pc_load(pc_load), .mem_to_reg(mem_to_reg)
    );

    integer errors = 0;

    task check;
        input [2:0] exp_alu_op;
        input       exp_rw, exp_src, exp_pcl;
        input [7:0] tag;
        begin
            #2;
            if (alu_op!==exp_alu_op || reg_write!==exp_rw || alu_src!==exp_src || pc_load!==exp_pcl) begin
                $display("FAIL [%0d] op=%b z=%b | alu_op=%b(exp %b) rw=%b(exp %b) src=%b(exp %b) pcl=%b(exp %b)",
                    tag, opcode, zero, alu_op, exp_alu_op, reg_write, exp_rw, alu_src, exp_src, pc_load, exp_pcl);
                errors = errors + 1;
            end else
                $display("PASS [%0d] op=%b z=%b | alu_op=%b rw=%b src=%b pcl=%b",
                    tag, opcode, zero, alu_op, reg_write, alu_src, pc_load);
        end
    endtask

    initial begin
        zero=0;
        opcode=3'b000; check(3'b000, 1, 0, 0, 0); // ADD
        opcode=3'b001; check(3'b001, 1, 0, 0, 1); // SUB
        opcode=3'b010; check(3'b010, 1, 0, 0, 2); // AND
        opcode=3'b011; check(3'b011, 1, 0, 0, 3); // OR
        opcode=3'b100; check(3'b100, 1, 0, 0, 4); // XOR
        opcode=3'b101; check(3'b000, 1, 1, 0, 5); // LDI (alu_op=ADD, src=imm)
        opcode=3'b110; check(3'b110, 0, 0, 1, 6); // JMP always
        // BEQ zero=0 -> no branch
        opcode=3'b111; zero=0; check(3'b111, 0, 0, 0, 7);
        // BEQ zero=1 -> branch
        opcode=3'b111; zero=1; check(3'b111, 0, 0, 1, 8);

        if (errors == 0)
            $display("All control_unit tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
