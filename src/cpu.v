// ISA v3 CPU — 64-bit data path, 16-bit addresses, stack, traps, I/O.
// Authoritative behavior spec: docs/isa_v3.md. The C++ simulator implements
// the same spec; `make cosim` diffs the two against each other.
module cpu #(
    parameter WIDTH = 64       // data path width (registers, ALU, memory words)
) (
    input        clk,
    input        rst,
    output       halted,      // HLT or unhandled trap
    output       out_valid,   // OUT (or ST to 0xFF01) this cycle
    output [WIDTH-1:0] out_data
);
    // I/O map (kernel-only region starts at 0xFF00)
    localparam [15:0] IO_BASE  = 16'hFF00;
    localparam [15:0] IO_IN    = 16'hFF00;
    localparam [15:0] IO_OUT   = 16'hFF01;
    localparam [15:0] IO_TIMER = 16'hFF02;
    localparam [15:0] IO_IVEC  = 16'hFF04;
    localparam [15:0] IO_CAUSE = 16'hFF05;

    // --- Fetch ---
    wire [15:0] pc;
    wire [31:0] instr;

    instruction_memory imem_inst (
        .addr(pc),
        .instruction(instr)
    );

    // --- Decode (ISA v3) ---
    wire [5:0]  opcode = instr[31:26];
    wire [2:0]  rd     = instr[25:23];
    wire [2:0]  rs1    = instr[22:20];
    wire [2:0]  rs2    = instr[19:17];
    wire [15:0] imm16  = instr[15:0];

    wire is_alu, is_ldi, is_ld, is_st, is_jmp, is_beq, is_bne, is_out;
    wire is_hlt, is_call, is_ret, is_push, is_pop, is_sti, is_cli, is_iret;
    wire valid_op, cu_reg_write, privileged;

    control_unit cu (
        .opcode(opcode),
        .is_alu(is_alu), .is_ldi(is_ldi), .is_ld(is_ld), .is_st(is_st),
        .is_jmp(is_jmp), .is_beq(is_beq), .is_bne(is_bne), .is_out(is_out),
        .is_hlt(is_hlt), .is_call(is_call), .is_ret(is_ret), .is_push(is_push),
        .is_pop(is_pop), .is_sti(is_sti), .is_cli(is_cli), .is_iret(is_iret),
        .valid(valid_op), .reg_write(cu_reg_write), .privileged(privileged)
    );

    // --- Machine state ---
    reg [15:0]      sp;            // stack pointer, grows down from 0xFF00
    reg             zf, cf;        // flags (registered)
    reg             kernel;        // 1 = kernel mode
    reg             ie;            // interrupt enable
    reg             irq_pending;
    reg [WIDTH-1:0] timer_period, timer_count;
    reg [15:0]      ivec;          // trap vector (0 = none installed)
    reg [WIDTH-1:0] cause;
    reg             halted_r;

    // --- Register file ---
    wire [WIDTH-1:0] rdata1, rdata2;
    wire [15:0] maddr = rdata1[15:0];
    wire io_access = (maddr >= IO_BASE);

    // --- Trap sequencing (one trap entry consumes one cycle) ---
    wire take_irq  = ~halted_r & irq_pending & ie & (ivec != 16'd0);
    wire priv_viol = ~kernel & (privileged | ((is_ld | is_st) & io_access));
    wire exc       = ~halted_r & ~take_irq & (~valid_op | priv_viol);
    wire take_exc  = exc & (ivec != 16'd0);
    wire entry     = take_irq | take_exc;
    wire exc_halt  = exc & (ivec == 16'd0);

    wire exec    = ~halted_r & ~entry & ~exc;      // normal instruction commits
    wire do_halt = (exec & is_hlt) | (~halted_r & exc_halt);

    // --- ALU (opcodes 0x00-0x0A map directly onto alu_op) ---
    wire [WIDTH-1:0] alu_result;
    wire             zero, carry_out;
    alu #(.WIDTH(WIDTH)) alu_inst (
        .a(rdata1), .b(rdata2), .op(opcode[3:0]),
        .result(alu_result), .zero(zero), .carry_out(carry_out)
    );

    // --- Input stream (simulation: +in=<file> of hex words) ---
    reg [WIDTH-1:0] in_fifo [0:1023];
    reg [1023:0]    in_file;
    reg [15:0]      in_ptr;
    integer k;
    initial begin
        for (k = 0; k < 1024; k = k + 1) in_fifo[k] = {WIDTH{1'b0}};
        if ($value$plusargs("in=%s", in_file))
            $readmemh(in_file, in_fifo);
    end
    wire [WIDTH-1:0] in_value = (in_ptr < 16'd1024) ? in_fifo[in_ptr[9:0]]
                                                    : {WIDTH{1'b0}};

    // --- I/O reads (combinational) ---
    reg [WIDTH-1:0] io_rdata;
    always @(*) begin
        case (maddr)
            IO_IN:    io_rdata = in_value;
            IO_TIMER: io_rdata = timer_period;
            IO_IVEC:  io_rdata = {{(WIDTH-16){1'b0}}, ivec};
            IO_CAUSE: io_rdata = cause;
            default:  io_rdata = {WIDTH{1'b0}};
        endcase
    end

    // --- Data memory (single port; address/data muxed per operation) ---
    // saved trap frame: pc | zf<<16 | cf<<17 | mode<<18 | ie<<19
    wire [15:0] saved_pc = take_irq ? pc : (pc + 16'd1);
    wire [WIDTH-1:0] frame = {{(WIDTH-20){1'b0}}, ie, kernel, cf, zf, saved_pc};

    wire stack_write = entry | (exec & (is_push | is_call));
    wire stack_read  = exec & (is_pop | is_ret | is_iret);

    wire [15:0] dmem_addr = stack_write ? (sp - 16'd1) :
                            stack_read  ? sp :
                                          maddr;          // LD/ST
    wire [WIDTH-1:0] dmem_wdata = entry   ? frame :
                                  is_call ? {{(WIDTH-16){1'b0}}, pc + 16'd1} :
                                  is_push ? rdata1 :
                                            rdata2;       // ST
    wire dmem_we = stack_write | (exec & is_st & ~io_access);
    wire [WIDTH-1:0] mem_rdata;

    data_memory #(.WIDTH(WIDTH)) dmem (
        .clk(clk), .we(dmem_we),
        .addr(dmem_addr), .wdata(dmem_wdata),
        .rdata(mem_rdata)
    );

    // --- Writeback ---
    wire [WIDTH-1:0] imm_ext  = {{(WIDTH-16){1'b0}}, imm16};
    wire [WIDTH-1:0] ld_data  = io_access ? io_rdata : mem_rdata;
    wire [WIDTH-1:0] write_data = is_ldi ? imm_ext :
                                  is_ld  ? ld_data :
                                  is_pop ? mem_rdata :
                                           alu_result;
    wire reg_write = exec & cu_reg_write;

    register_file #(.WIDTH(WIDTH)) rf (
        .clk(clk), .we(reg_write),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .write_data(write_data),
        .read_data1(rdata1), .read_data2(rdata2)
    );

    // --- Next PC ---
    wire branch_taken = exec & (is_jmp | is_call |
                                (is_beq & zf) | (is_bne & ~zf) |
                                is_ret | is_iret);
    wire [15:0] pc_target = (is_ret | is_iret) ? mem_rdata[15:0] : imm16;
    wire pc_load = entry | branch_taken;
    wire [15:0] pc_in = entry ? ivec : pc_target;

    program_counter #(.AWIDTH(16)) pc_inst (
        .clk(clk), .rst(rst), .halt(halted_r | do_halt),
        .load(pc_load), .pc_in(pc_in),
        .pc_out(pc)
    );

    // --- Timer: ST to 0xFF02 loads the period and resets the counter;
    //     counting starts the following cycle (spec: docs/isa_v3.md) ---
    wire timer_write = exec & is_st & io_access & (maddr == IO_TIMER);

    // --- State updates ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sp <= 16'hFF00; zf <= 0; cf <= 0;
            kernel <= 1; ie <= 0; irq_pending <= 0;
            timer_period <= 0; timer_count <= 0;
            ivec <= 0; cause <= 0; halted_r <= 0; in_ptr <= 0;
        end else if (!halted_r) begin
            if (do_halt)
                halted_r <= 1;

            if (entry) begin
                sp     <= sp - 16'd1;
                kernel <= 1;
                ie     <= 0;
                cause  <= take_irq ? 1 : (~valid_op ? 2 : 3);
                if (take_irq) irq_pending <= 0;
            end else if (exec) begin
                if (is_push | is_call)          sp <= sp - 16'd1;
                if (is_pop | is_ret | is_iret)  sp <= sp + 16'd1;
                if (is_sti) ie <= 1;
                if (is_cli) ie <= 0;
                if (is_iret) begin
                    zf     <= mem_rdata[16];
                    cf     <= mem_rdata[17];
                    kernel <= mem_rdata[18];
                    ie     <= mem_rdata[19];
                end else if (cu_reg_write) begin
                    zf <= (write_data == {WIDTH{1'b0}});
                    if (opcode == 6'h00 || opcode == 6'h01)   // ADD/SUB
                        cf <= carry_out;
                end
                if (is_st & io_access) begin
                    case (maddr)
                        IO_TIMER: begin timer_period <= rdata2; timer_count <= 0; end
                        IO_IVEC:  ivec <= rdata2[15:0];
                        default: ;   // IO_OUT handled via out_valid; others ignored
                    endcase
                end
                if (is_ld & io_access & (maddr == IO_IN))
                    in_ptr <= in_ptr + 16'd1;
            end

            // timer tick (skipped on the cycle that programs the timer)
            if (timer_period > 0 && !timer_write) begin
                if (timer_count + 1 >= timer_period) begin
                    timer_count <= 0;
                    irq_pending <= 1;
                end else
                    timer_count <= timer_count + 1;
            end
        end
    end

    assign halted    = halted_r;
    assign out_valid = exec & (is_out | (is_st & io_access & (maddr == IO_OUT)));
    assign out_data  = is_out ? rdata1 : rdata2;
endmodule
