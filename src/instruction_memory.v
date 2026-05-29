// ROM: 256 x 16-bit words, initialized from parameter or $readmemh file.
// Read-only, combinational output.
module instruction_memory (
    input  [7:0]  addr,
    output [15:0] instruction
);
    reg [15:0] mem [0:255];

    initial $readmemh("tests/program.hex", mem);

    assign instruction = mem[addr];
endmodule
