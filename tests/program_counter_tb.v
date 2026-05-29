`timescale 1ns/1ps

module program_counter_tb;
    reg        clk, rst, load;
    reg  [7:0] pc_in;
    wire [7:0] pc_out;

    program_counter uut (.clk(clk), .rst(rst), .load(load), .pc_in(pc_in), .pc_out(pc_out));

    always #5 clk = ~clk;

    integer errors = 0;

    task check;
        input [7:0] exp;
        input [7:0] tag;
        begin
            if (pc_out !== exp) begin
                $display("FAIL [%0d] pc=%h (exp %h)", tag, pc_out, exp);
                errors = errors + 1;
            end else
                $display("PASS [%0d] pc=%h", tag, pc_out);
        end
    endtask

    initial begin
        clk=0; rst=1; load=0; pc_in=0;
        @(posedge clk); #1; check(8'h00, 1);  // reset holds 0

        rst=0;
        @(posedge clk); #1; check(8'h01, 2);  // increments to 1
        @(posedge clk); #1; check(8'h02, 3);  // increments to 2
        @(posedge clk); #1; check(8'h03, 4);  // increments to 3

        // branch to 0x10
        load=1; pc_in=8'h10;
        @(posedge clk); #1; check(8'h10, 5);
        load=0;
        @(posedge clk); #1; check(8'h11, 6);  // resumes incrementing

        // wrap-around at 0xFF
        load=1; pc_in=8'hFF;
        @(posedge clk); #1; check(8'hFF, 7);
        load=0;
        @(posedge clk); #1; check(8'h00, 8);  // wraps to 0

        // async reset
        rst=1;
        #3; check(8'h00, 9);   // reset fires immediately (async)
        rst=0;

        if (errors == 0)
            $display("All program_counter tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
