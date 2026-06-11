// ROM: 65536 x 32-bit words, loaded with $readmemh.
// Hex file selectable at runtime with +hex=<path>.
// Works in both Icarus and Verilator; defaults to tests/program.hex.
module instruction_memory (
    input  [15:0] addr,
    output [31:0] instruction
);
    reg [31:0] mem [0:65535];
    reg [1023:0] hexfile;

    initial begin
        if ($value$plusargs("hex=%s", hexfile))
            $readmemh(hexfile, mem);
        else
            $readmemh("tests/program.hex", mem);
    end

    assign instruction = mem[addr];
endmodule
