`timescale 1ns/1ps

module instruction_memory_tb;
    reg  [7:0]  addr;
    wire [15:0] instruction;

    instruction_memory uut (.addr(addr), .instruction(instruction));

    integer errors = 0;

    task check;
        input [15:0] exp;
        input [7:0]  tag;
        begin
            #2;
            if (instruction !== exp) begin
                $display("FAIL [%0d] addr=%h instr=%h (exp %h)", tag, addr, instruction, exp);
                errors = errors + 1;
            end else
                $display("PASS [%0d] addr=%h instr=%h", tag, addr, instruction);
        end
    endtask

    initial begin
        addr=8'h00; check(16'h1234, 0);
        addr=8'h01; check(16'hABCD, 1);
        addr=8'h02; check(16'h0000, 2);
        addr=8'h03; check(16'hFFFF, 3);
        addr=8'h04; check(16'h5A5A, 4);
        // uninitialized addresses read as x — just verify no crash
        addr=8'hFF; #2;
        $display("INFO addr=FF instr=%h (uninitialized, x ok)", instruction);

        if (errors == 0)
            $display("All instruction_memory tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
