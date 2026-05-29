// ALU opcodes
// 000 ADD  001 SUB  010 AND  011 OR
// 100 XOR  101 NOT  110 SHL  111 SHR
module alu (
    input  [7:0] a,
    input  [7:0] b,
    input  [2:0] op,
    output reg [7:0] result,
    output reg       zero,
    output reg       carry_out
);
    wire [7:0] b_mux;        // b or ~b depending on SUB
    wire       cin;
    wire [7:0] adder_sum;
    wire [8:0] carry;        // carry[0]=cin, carry[8]=cout

    // SUB uses two's complement: result = a + (~b) + 1
    assign b_mux = (op == 3'b001) ? ~b : b;
    assign cin   = (op == 3'b001) ? 1'b1 : 1'b0;
    assign carry[0] = cin;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : adder_chain
            full_adder fa (
                .a(a[i]), .b(b_mux[i]), .cin(carry[i]),
                .sum(adder_sum[i]), .cout(carry[i+1])
            );
        end
    endgenerate

    always @(*) begin
        carry_out = 1'b0;
        case (op)
            3'b000: begin result = adder_sum; carry_out = carry[8]; end  // ADD
            3'b001: begin result = adder_sum; carry_out = carry[8]; end  // SUB
            3'b010: result = a & b;                                       // AND
            3'b011: result = a | b;                                       // OR
            3'b100: result = a ^ b;                                       // XOR
            3'b101: result = ~a;                                          // NOT
            3'b110: result = a << 1;                                      // SHL
            3'b111: result = a >> 1;                                      // SHR
            default: result = 8'b0;
        endcase
        zero = (result == 8'b0);
    end
endmodule
