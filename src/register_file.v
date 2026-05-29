// 8 x 8-bit registers (R0–R7). R0 is always 0 (hardwired).
module register_file (
    input        clk,
    input        we,          // write enable
    input  [2:0] rs1,         // source 1 address
    input  [2:0] rs2,         // source 2 address
    input  [2:0] rd,          // destination address
    input  [7:0] write_data,
    output [7:0] read_data1,
    output [7:0] read_data2
);
    reg [7:0] regs [7:0];
    integer j;
    initial for (j = 0; j < 8; j = j+1) regs[j] = 8'b0;

    always @(posedge clk) begin
        if (we && rd != 3'b000)   // R0 stays zero
            regs[rd] <= write_data;
    end

    assign read_data1 = regs[rs1];
    assign read_data2 = regs[rs2];
endmodule
