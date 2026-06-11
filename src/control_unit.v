// ISA v3 decoder — one-hot instruction class signals (see docs/isa_v3.md).
// Trap/privilege sequencing lives in cpu.v; this module only classifies.
module control_unit (
    input  [5:0] opcode,
    output       is_alu,    // ADD..MOD (0x00-0x0A)
    output       is_ldi,
    output       is_ld,
    output       is_st,
    output       is_jmp,
    output       is_beq,
    output       is_bne,
    output       is_out,
    output       is_hlt,
    output       is_call,
    output       is_ret,
    output       is_push,
    output       is_pop,
    output       is_sti,
    output       is_cli,
    output       is_iret,
    output       valid,     // recognized opcode
    output       reg_write, // writes a register (ALU ops, LDI, LD, POP)
    output       privileged // kernel-only instruction (HLT/STI/CLI/IRET)
);
    assign is_alu  = (opcode <= 6'h0A);
    assign is_ldi  = (opcode == 6'h0B);
    assign is_ld   = (opcode == 6'h0C);
    assign is_st   = (opcode == 6'h0D);
    assign is_jmp  = (opcode == 6'h0E);
    assign is_beq  = (opcode == 6'h0F);
    assign is_bne  = (opcode == 6'h10);
    assign is_out  = (opcode == 6'h11);
    assign is_hlt  = (opcode == 6'h12);
    assign is_call = (opcode == 6'h13);
    assign is_ret  = (opcode == 6'h14);
    assign is_push = (opcode == 6'h15);
    assign is_pop  = (opcode == 6'h16);
    assign is_sti  = (opcode == 6'h17);
    assign is_cli  = (opcode == 6'h18);
    assign is_iret = (opcode == 6'h19);
    assign valid   = (opcode <= 6'h19);

    assign reg_write  = is_alu | is_ldi | is_ld | is_pop;
    assign privileged = is_hlt | is_sti | is_cli | is_iret;
endmodule
