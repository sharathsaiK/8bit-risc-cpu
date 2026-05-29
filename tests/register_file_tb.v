`timescale 1ns/1ps

module register_file_tb;
    reg        clk, we;
    reg  [2:0] rs1, rs2, rd;
    reg  [7:0] write_data;
    wire [7:0] read_data1, read_data2;

    register_file uut (
        .clk(clk), .we(we),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .write_data(write_data),
        .read_data1(read_data1), .read_data2(read_data2)
    );

    always #5 clk = ~clk;

    integer errors = 0;

    task check;
        input [7:0] exp1, exp2;
        input [7:0] tag;
        begin
            if (read_data1 !== exp1 || read_data2 !== exp2) begin
                $display("FAIL [%0d] rd1=%h (exp %h) rd2=%h (exp %h)", tag, read_data1, exp1, read_data2, exp2);
                errors = errors + 1;
            end else
                $display("PASS [%0d] rd1=%h rd2=%h", tag, read_data1, read_data2);
        end
    endtask

    initial begin
        clk = 0; we = 0; rs1 = 0; rs2 = 0; rd = 0; write_data = 0;

        // Write 0xAB into R1
        @(negedge clk); we=1; rd=3'd1; write_data=8'hAB;
        @(posedge clk); #1;
        we=0; rs1=3'd1; rs2=3'd0;
        #1; check(8'hAB, 8'h00, 1);

        // Write 0x55 into R2
        @(negedge clk); we=1; rd=3'd2; write_data=8'h55;
        @(posedge clk); #1;
        we=0; rs1=3'd1; rs2=3'd2;
        #1; check(8'hAB, 8'h55, 2);

        // Overwrite R1 with 0x12
        @(negedge clk); we=1; rd=3'd1; write_data=8'h12;
        @(posedge clk); #1;
        we=0; rs1=3'd1; rs2=3'd2;
        #1; check(8'h12, 8'h55, 3);

        // R0 must stay 0 even with write
        @(negedge clk); we=1; rd=3'd0; write_data=8'hFF;
        @(posedge clk); #1;
        we=0; rs1=3'd0; rs2=3'd0;
        #1; check(8'h00, 8'h00, 4);

        // Write all registers R3-R7 and read back
        begin : fill_loop
            integer k;
            for (k = 3; k <= 7; k = k+1) begin
                @(negedge clk); we=1; rd=k[2:0]; write_data=k*8'h11;
                @(posedge clk); #1;
            end
            we=0;
            rs1=3'd3; rs2=3'd7; #1;
            check(8'h33, 8'h77, 5);
        end

        if (errors == 0)
            $display("All register_file tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
