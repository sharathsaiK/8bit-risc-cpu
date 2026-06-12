// Generic program runner: executes whatever +hex=<file> points at until HLT,
// printing OUT values and the final register state. Optional +in=<file>
// supplies the input stream. No self-checks — used by the cosim harness,
// which diffs this output against the C++ simulator.
`timescale 1ns/1ps

module run_tb;
    reg clk, rst;
    wire halted, out_valid;
    wire [63:0] out_data;

    cpu uut (
        .clk(clk), .rst(rst),
        .halted(halted), .out_valid(out_valid), .out_data(out_data)
    );

    always #5 clk = ~clk;

    always @(negedge clk)
        if (!rst && out_valid)
            $display("OUT %h", out_data);

    integer cyc;

    initial begin
        clk=0; rst=1;
        @(posedge clk); @(posedge clk); #1;
        rst=0;

        for (cyc = 0; cyc < 10000000 && !halted; cyc = cyc + 1)
            @(posedge clk);
        #1;

        if (!halted)
            $display("TIMEOUT: CPU did not halt within 10000000 cycles");

        $display("R1=%h", uut.rf.regs[1]);
        $display("R2=%h", uut.rf.regs[2]);
        $display("R3=%h", uut.rf.regs[3]);
        $display("R4=%h", uut.rf.regs[4]);
        $display("R5=%h", uut.rf.regs[5]);
        $display("R6=%h", uut.rf.regs[6]);
        $display("R7=%h", uut.rf.regs[7]);
        $display("PC=%h", uut.id_ex_pc);   // EX-stage PC = last retired instr
        $display("SP=%h", uut.sp);
        $finish;
    end
endmodule
