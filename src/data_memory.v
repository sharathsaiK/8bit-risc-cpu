// RAM: 65536 x WIDTH-bit words. Synchronous write, combinational read.
module data_memory #(
    parameter WIDTH = 64
) (
    input        clk,
    input        we,
    input  [15:0] addr,
    input  [WIDTH-1:0] wdata,
    output [WIDTH-1:0] rdata
);
    reg [WIDTH-1:0] mem [0:65535];
    integer j;
    initial for (j = 0; j < 65536; j = j+1) mem[j] = {WIDTH{1'b0}};

    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    assign rdata = mem[addr];
endmodule
