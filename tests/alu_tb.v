`timescale 1ns/1ps

module alu_tb;
    reg  [7:0] a, b;
    reg  [2:0] op;
    wire [7:0] result;
    wire       zero, carry_out;

    alu uut (.a(a), .b(b), .op(op), .result(result), .zero(zero), .carry_out(carry_out));

    integer errors = 0;

    task check;
        input [7:0]  exp_result;
        input        exp_zero;
        input        exp_carry;
        input [63:0] label;  // unused but kept for readability
        begin
            #5;
            if (result !== exp_result || zero !== exp_zero || carry_out !== exp_carry) begin
                $display("FAIL op=%b a=%h b=%h | result=%h (exp %h) zero=%b (exp %b) carry=%b (exp %b)",
                         op, a, b, result, exp_result, zero, exp_zero, carry_out, exp_carry);
                errors = errors + 1;
            end else begin
                $display("PASS op=%b a=%h b=%h | result=%h zero=%b carry=%b",
                         op, a, b, result, zero, carry_out);
            end
        end
    endtask

    initial begin
        // ADD
        a=8'h05; b=8'h03; op=3'b000; check(8'h08, 0, 0, 0);
        a=8'hFF; b=8'h01; op=3'b000; check(8'h00, 1, 1, 0); // overflow -> zero, carry
        // SUB
        a=8'h09; b=8'h04; op=3'b001; check(8'h05, 0, 1, 0);
        a=8'h04; b=8'h04; op=3'b001; check(8'h00, 1, 1, 0); // a-a = 0
        // AND
        a=8'hAA; b=8'h0F; op=3'b010; check(8'h0A, 0, 0, 0);
        // OR
        a=8'hA0; b=8'h0B; op=3'b011; check(8'hAB, 0, 0, 0);
        // XOR
        a=8'hFF; b=8'hFF; op=3'b100; check(8'h00, 1, 0, 0);
        a=8'hAA; b=8'h55; op=3'b100; check(8'hFF, 0, 0, 0);
        // NOT
        a=8'h00; b=8'h00; op=3'b101; check(8'hFF, 0, 0, 0);
        a=8'hFF; b=8'h00; op=3'b101; check(8'h00, 1, 0, 0);
        // SHL
        a=8'h01; b=8'h00; op=3'b110; check(8'h02, 0, 0, 0);
        a=8'h80; b=8'h00; op=3'b110; check(8'h00, 1, 0, 0);
        // SHR
        a=8'h80; b=8'h00; op=3'b111; check(8'h40, 0, 0, 0);
        a=8'h01; b=8'h00; op=3'b111; check(8'h00, 1, 0, 0);

        if (errors == 0)
            $display("All ALU tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
