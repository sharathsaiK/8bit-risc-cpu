`timescale 1ns/1ps

module full_adder_tb;
    reg  a, b, cin;
    wire sum, cout;

    full_adder uut (.a(a), .b(b), .cin(cin), .sum(sum), .cout(cout));

    integer errors = 0;
    integer i;

    task check;
        input exp_sum, exp_cout;
        begin
            #5;
            if (sum !== exp_sum || cout !== exp_cout) begin
                $display("FAIL a=%b b=%b cin=%b | sum=%b (exp %b) cout=%b (exp %b)",
                         a, b, cin, sum, exp_sum, cout, exp_cout);
                errors = errors + 1;
            end else begin
                $display("PASS a=%b b=%b cin=%b | sum=%b cout=%b", a, b, cin, sum, cout);
            end
        end
    endtask

    initial begin
        // truth table: sum = a^b^cin, cout = majority
        a=0; b=0; cin=0; check(0, 0);
        a=0; b=0; cin=1; check(1, 0);
        a=0; b=1; cin=0; check(1, 0);
        a=0; b=1; cin=1; check(0, 1);
        a=1; b=0; cin=0; check(1, 0);
        a=1; b=0; cin=1; check(0, 1);
        a=1; b=1; cin=0; check(0, 1);
        a=1; b=1; cin=1; check(1, 1);

        if (errors == 0)
            $display("All tests passed.");
        else
            $display("%0d test(s) FAILED.", errors);
        $finish;
    end
endmodule
