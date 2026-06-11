`timescale 1ns/1ps

// ISA v3 control_unit testbench — one-hot decode, valid/reg_write/privileged.
module control_unit_tb;
    reg  [5:0] opcode;
    wire       is_alu, is_ldi, is_ld, is_st, is_jmp, is_beq, is_bne, is_out;
    wire       is_hlt, is_call, is_ret, is_push, is_pop, is_sti, is_cli, is_iret;
    wire       valid, reg_write, privileged;

    control_unit uut (
        .opcode(opcode),
        .is_alu(is_alu), .is_ldi(is_ldi), .is_ld(is_ld), .is_st(is_st),
        .is_jmp(is_jmp), .is_beq(is_beq), .is_bne(is_bne), .is_out(is_out),
        .is_hlt(is_hlt), .is_call(is_call), .is_ret(is_ret), .is_push(is_push),
        .is_pop(is_pop), .is_sti(is_sti), .is_cli(is_cli), .is_iret(is_iret),
        .valid(valid), .reg_write(reg_write), .privileged(privileged)
    );

    integer errors = 0;

    // Verify exactly one 'is_*' bit is high and all meta-signals match.
    task check_op;
        input [5:0]  op;
        input        exp_is_alu, exp_is_ldi, exp_is_ld, exp_is_st;
        input        exp_is_jmp, exp_is_beq, exp_is_bne, exp_is_out;
        input        exp_is_hlt, exp_is_call, exp_is_ret, exp_is_push;
        input        exp_is_pop, exp_is_sti, exp_is_cli, exp_is_iret;
        input        exp_valid, exp_rw, exp_priv;
        input [63:0] tag;
        begin
            opcode = op; #2;
            if (is_alu    !== exp_is_alu  || is_ldi  !== exp_is_ldi  ||
                is_ld     !== exp_is_ld   || is_st    !== exp_is_st   ||
                is_jmp    !== exp_is_jmp  || is_beq   !== exp_is_beq  ||
                is_bne    !== exp_is_bne  || is_out   !== exp_is_out  ||
                is_hlt    !== exp_is_hlt  || is_call  !== exp_is_call ||
                is_ret    !== exp_is_ret  || is_push  !== exp_is_push ||
                is_pop    !== exp_is_pop  || is_sti   !== exp_is_sti  ||
                is_cli    !== exp_is_cli  || is_iret  !== exp_is_iret ||
                valid     !== exp_valid   || reg_write !== exp_rw     ||
                privileged !== exp_priv)
            begin
                $display("FAIL op=%02h (%0s): is_alu=%b ldi=%b ld=%b st=%b jmp=%b beq=%b bne=%b out=%b hlt=%b call=%b ret=%b push=%b pop=%b sti=%b cli=%b iret=%b valid=%b rw=%b priv=%b",
                    op, tag,
                    is_alu,is_ldi,is_ld,is_st,is_jmp,is_beq,is_bne,is_out,
                    is_hlt,is_call,is_ret,is_push,is_pop,is_sti,is_cli,is_iret,
                    valid,reg_write,privileged);
                errors = errors + 1;
            end else
                $display("PASS op=%02h (%0s)", op, tag);
        end
    endtask

    initial begin
        // is_alu ldi ld  st  jmp beq bne out hlt call ret push pop sti cli iret  valid rw  priv
        check_op(6'h00, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "ADD");
        check_op(6'h01, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "SUB");
        check_op(6'h02, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "AND");
        check_op(6'h03, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "OR" );
        check_op(6'h04, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "XOR");
        check_op(6'h05, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "NOT");
        check_op(6'h06, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "SHL");
        check_op(6'h07, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "SHR");
        check_op(6'h08, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "MUL");
        check_op(6'h09, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "DIV");
        check_op(6'h0A, 1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "MOD");
        check_op(6'h0B, 0,1,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "LDI");
        check_op(6'h0C, 0,0,1,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,0, "LD" );
        check_op(6'h0D, 0,0,0,1, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0, "ST" );
        check_op(6'h0E, 0,0,0,0, 1,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0, "JMP");
        check_op(6'h0F, 0,0,0,0, 0,1,0,0, 0,0,0,0, 0,0,0,0, 1,0,0, "BEQ");
        check_op(6'h10, 0,0,0,0, 0,0,1,0, 0,0,0,0, 0,0,0,0, 1,0,0, "BNE");
        check_op(6'h11, 0,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,0, 1,0,0, "OUT");
        check_op(6'h12, 0,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,1, "HLT");
        check_op(6'h13, 0,0,0,0, 0,0,0,0, 0,1,0,0, 0,0,0,0, 1,0,0, "CALL");
        check_op(6'h14, 0,0,0,0, 0,0,0,0, 0,0,1,0, 0,0,0,0, 1,0,0, "RET");
        check_op(6'h15, 0,0,0,0, 0,0,0,0, 0,0,0,1, 0,0,0,0, 1,0,0, "PUSH");
        check_op(6'h16, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0,0, 1,1,0, "POP");
        check_op(6'h17, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,1,0,0, 1,0,1, "STI");
        check_op(6'h18, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,1,0, 1,0,1, "CLI");
        check_op(6'h19, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1, 1,0,1, "IRET");

        // invalid opcodes: valid must be 0
        opcode = 6'h1A; #2;
        if (valid !== 0) begin
            $display("FAIL opcode 0x1A should be invalid (valid=%b)", valid);
            errors = errors + 1;
        end else $display("PASS opcode 0x1A invalid");

        opcode = 6'h3F; #2;
        if (valid !== 0) begin
            $display("FAIL opcode 0x3F should be invalid (valid=%b)", valid);
            errors = errors + 1;
        end else $display("PASS opcode 0x3F invalid");

        if (errors == 0)
            $display("All control_unit tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
