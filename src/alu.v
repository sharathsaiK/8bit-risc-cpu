// ALU opcodes (4-bit)
// 0000 ADD  0001 SUB  0010 AND  0011 OR   0100 XOR  0101 NOT
// 0110 SHL  0111 SHR  1000 MUL  1001 DIV  1010 MOD
// ADD/SUB use the structural full-adder chain; div-by-zero follows RISC-V:
// DIV -> all-ones, MOD -> dividend.
module alu #(
    parameter WIDTH = 64
) (
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    input  [3:0]       op,
    output reg [WIDTH-1:0] result,
    output reg             zero,
    output reg             carry_out
);
    wire [WIDTH-1:0] b_mux;      // b or ~b depending on SUB
    wire             cin;
    wire [WIDTH-1:0] adder_sum;
    wire [WIDTH:0]   carry;      // carry[0]=cin, carry[WIDTH]=cout

    // SUB uses two's complement: result = a + (~b) + 1
    assign b_mux = (op == 4'b0001) ? ~b : b;
    assign cin   = (op == 4'b0001) ? 1'b1 : 1'b0;
    assign carry[0] = cin;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : adder_chain
            full_adder fa (
                .a(a[i]), .b(b_mux[i]), .cin(carry[i]),
                .sum(adder_sum[i]), .cout(carry[i+1])
            );
        end
    endgenerate

    always @(*) begin
        carry_out = 1'b0;
        case (op)
            4'b0000: begin result = adder_sum; carry_out = carry[WIDTH]; end  // ADD
            4'b0001: begin result = adder_sum; carry_out = carry[WIDTH]; end  // SUB
            4'b0010: result = a & b;                                          // AND
            4'b0011: result = a | b;                                          // OR
            4'b0100: result = a ^ b;                                          // XOR
            4'b0101: result = ~a;                                             // NOT
            4'b0110: result = a << 1;                                         // SHL
            4'b0111: result = a >> 1;                                         // SHR
            4'b1000: result = a * b;                                          // MUL (low WIDTH bits)
            4'b1001: result = (b != 0) ? a / b : {WIDTH{1'b1}};               // DIV
            4'b1010: result = (b != 0) ? a % b : a;                           // MOD
            default: result = {WIDTH{1'b0}};
        endcase
        zero = (result == {WIDTH{1'b0}});
    end
endmodule
