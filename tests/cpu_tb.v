`timescale 1ns/1ps

module cpu_tb;
    reg clk, rst;

    cpu uut (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    // expose internals for checking
    wire [7:0] pc       = uut.pc;
    wire [7:0] r1       = uut.rf.regs[1];
    wire [7:0] r2       = uut.rf.regs[2];
    wire [7:0] r3       = uut.rf.regs[3];
    wire [7:0] r4       = uut.rf.regs[4];
    wire [7:0] r5       = uut.rf.regs[5];
    wire [7:0] r6       = uut.rf.regs[6];
    wire [7:0] r7       = uut.rf.regs[7];
    wire [7:0] alu_res  = uut.alu_result;
    wire [2:0] opcode   = uut.opcode;

    integer errors = 0;

    task check_reg;
        input [7:0] actual, expected;
        input [63:0] name;
        begin
            if (actual !== expected) begin
                $display("FAIL %s = %h (expected %h)", name, actual, expected);
                errors = errors + 1;
            end else
                $display("PASS %s = %h", name, actual);
        end
    endtask

    initial begin
        $dumpfile("sim/cpu_tb.vcd");
        $dumpvars(0, cpu_tb);

        clk=0; rst=1;
        @(posedge clk); @(posedge clk); #1;
        rst=0;

        // cycle 1: LDI R1, 0x0A
        @(posedge clk); #1;
        // cycle 2: LDI R2, 0x05
        @(posedge clk); #1;
        // cycle 3: ADD R3, R1, R2
        @(posedge clk); #1;
        // cycle 4: SUB R4, R1, R2
        @(posedge clk); #1;
        // cycle 5: AND R5, R1, R2
        @(posedge clk); #1;
        // cycle 6: OR  R6, R1, R2
        @(posedge clk); #1;
        // cycle 7: XOR R7, R1, R2
        @(posedge clk); #1;
        // cycle 8+: JMP 0x07 (halt loop)
        @(posedge clk); #1;
        @(posedge clk); #1;

        $display("--- Register file after program ---");
        check_reg(r1, 8'h0A, "R1"); // LDI 0x0A
        check_reg(r2, 8'h05, "R2"); // LDI 0x05
        check_reg(r3, 8'h0F, "R3"); // 0x0A + 0x05
        check_reg(r4, 8'h05, "R4"); // 0x0A - 0x05
        check_reg(r5, 8'h00, "R5"); // 0x0A & 0x05 = 0b00001010 & 0b00000101 = 0x00
        check_reg(r6, 8'h0F, "R6"); // 0x0A | 0x05 = 0x0F
        check_reg(r7, 8'h0F, "R7"); // 0x0A ^ 0x05 = 0x0F

        $display("--- PC halted at 0x07 ---");
        if (pc !== 8'h07)
            $display("FAIL PC = %h (expected 07)", pc);
        else
            $display("PASS PC = %h", pc);

        if (errors == 0)
            $display("All CPU tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
