module program_counter (
    input        clk,
    input        rst,
    input        load,        // branch: load pc_in
    input  [7:0] pc_in,
    output reg [7:0] pc_out
);
    always @(posedge clk or posedge rst) begin
        if (rst)
            pc_out <= 8'b0;
        else if (load)
            pc_out <= pc_in;
        else
            pc_out <= pc_out + 8'b1;
    end
endmodule
