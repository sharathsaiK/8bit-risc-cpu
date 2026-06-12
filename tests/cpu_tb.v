`timescale 1ns/1ps

module cpu_tb;
    reg clk, rst;
    wire halted, out_valid;
    wire [63:0] out_data;

    cpu uut (
        .clk(clk), .rst(rst),
        .halted(halted), .out_valid(out_valid), .out_data(out_data)
    );

    always #5 clk = ~clk;

    // expose internals for checking
    wire [15:0] pc      = uut.if_ex_pc;   // EX-stage PC (last committed instruction)
    wire [15:0] sp      = uut.sp;
    wire [63:0] r1      = uut.rf.regs[1];
    wire [63:0] r2      = uut.rf.regs[2];
    wire [63:0] r3      = uut.rf.regs[3];
    wire [63:0] r4      = uut.rf.regs[4];
    wire [63:0] r5      = uut.rf.regs[5];
    wire [63:0] r6      = uut.rf.regs[6];
    wire [63:0] r7      = uut.rf.regs[7];
    wire [63:0] mem256  = uut.dmem.mem[16'h0100];
    wire [5:0]  opcode  = uut.opcode;
    wire [63:0] alu_res = uut.alu_result;

    integer errors = 0;
    integer cyc;

    // print OUT values mid-cycle, when signals are stable
    always @(negedge clk)
        if (!rst && out_valid)
            $display("OUT %h", out_data);

    task check_reg;
        input [63:0] actual, expected;
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

        // run until the CPU executes HLT (or give up after 10000 cycles)
        for (cyc = 0; cyc < 10000 && !halted; cyc = cyc + 1)
            @(posedge clk);
        #1;

        if (!halted) begin
            $display("FAIL CPU did not halt within 10000 cycles");
            errors = errors + 1;
        end else
            $display("CPU halted after %0d cycles", cyc);

        // machine-readable final state (used by cosim diff)
        $display("R1=%h", r1);
        $display("R2=%h", r2);
        $display("R3=%h", r3);
        $display("R4=%h", r4);
        $display("R5=%h", r5);
        $display("R6=%h", r6);
        $display("R7=%h", r7);
        $display("PC=%h", pc);
        $display("SP=%h", sp);

        // self-check against cpp/test_program.asm expected results
        $display("--- Register file after program ---");
        check_reg(r1, 64'h2A,   "R1"); // 21 doubled by CALL DOUBLE
        check_reg(r2, 64'hABCD, "R2"); // LDI 0xABCD
        check_reg(r3, 64'hABCD, "R3"); // POP round-trip
        check_reg(r4, 64'h00,   "R4"); // SUB R1-R1
        check_reg(r5, 64'h00,   "R5"); // MOD 10 % 5
        check_reg(r6, 64'h02,   "R6"); // MOD 7 % 5
        check_reg(r7, 64'h42,   "R7"); // LDI after branch tests
        check_reg(mem256, 64'hABCD, "M256"); // ST [0x100]
        check_reg({48'd0, sp}, 64'hFF00, "SP"); // stack balanced

        $display("--- PC parked at HLT (0x0022) ---");
        if (pc !== 16'h0022) begin
            $display("FAIL PC = %h (expected 0022)", pc);
            errors = errors + 1;
        end else
            $display("PASS PC = %h", pc);

        if (errors == 0)
            $display("All CPU tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
