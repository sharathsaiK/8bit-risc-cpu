`timescale 1ns/1ps

module half_adder_tb;
    reg  a, b;
    wire sum, carry;

    half_adder uut (.a(a), .b(b), .sum(sum), .carry(carry));

    integer errors = 0;

    task check;
        input exp_sum, exp_carry;
        begin
            #5;
            if (sum !== exp_sum || carry !== exp_carry) begin
                $display("FAIL a=%b b=%b | sum=%b (exp %b) carry=%b (exp %b)",
                         a, b, sum, exp_sum, carry, exp_carry);
                errors = errors + 1;
            end else begin
                $display("PASS a=%b b=%b | sum=%b carry=%b", a, b, sum, carry);
            end
        end
    endtask

    initial begin
        a=0; b=0; check(0, 0);
        a=0; b=1; check(1, 0);
        a=1; b=0; check(1, 0);
        a=1; b=1; check(0, 1);

        if (errors == 0)
            $display("All tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
