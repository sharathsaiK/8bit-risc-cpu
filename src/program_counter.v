module program_counter #(
    parameter AWIDTH = 16
) (
    input        clk,
    input        rst,
    input        halt,        // HLT: freeze
    input        load,        // branch/trap: load pc_in
    input  [AWIDTH-1:0] pc_in,
    output reg [AWIDTH-1:0] pc_out
);
    always @(posedge clk or posedge rst) begin
        if (rst)
            pc_out <= {AWIDTH{1'b0}};
        else if (halt)
            pc_out <= pc_out;
        else if (load)
            pc_out <= pc_in;
        else
            pc_out <= pc_out + {{(AWIDTH-1){1'b0}}, 1'b1};
    end
endmodule
