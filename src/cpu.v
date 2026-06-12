// 5-stage pipelined CPU (IF/ID/EX/MEM/WB) — ISA v3, 64-bit data path.
// Authoritative behaviour spec: docs/isa_v3.md.
//
// Pipeline structure
// ------------------
//   IF  : instruction_memory[pc] → IF/ID register
//   ID  : decode + register-file read → ID/EX register
//   EX  : forwarding + ALU + data-memory (combinational read) + state updates
//   MEM : carries EX result through EX/MEM register (no separate memory port)
//   WB  : register-file write from MEM/WB register
//
// Hazard policy
//   Data    : none — all memory reads are combinational in EX, so results are
//             available in EX/MEM by the next cycle; EX/MEM→EX and MEM/WB→EX
//             forwarding eliminates all RAW stalls.
//   Control : 2-cycle bubble inserted after every taken branch / call / ret /
//             iret and after every trap entry (both IF/ID and ID/EX flushed).
//
// Cosim note
//   The C++ reference simulator adds two extra tick_timer() calls after each
//   taken branch and after each trap entry to mirror the 2 bubble cycles.

module cpu #(
    parameter WIDTH = 64
) (
    input        clk,
    input        rst,
    output       halted,
    output       out_valid,
    output [WIDTH-1:0] out_data
);
    localparam [15:0] IO_BASE  = 16'hFF00;
    localparam [15:0] IO_IN    = 16'hFF00;
    localparam [15:0] IO_OUT   = 16'hFF01;
    localparam [15:0] IO_TIMER = 16'hFF02;
    localparam [15:0] IO_IVEC  = 16'hFF04;
    localparam [15:0] IO_CAUSE = 16'hFF05;

    // =========================================================
    // IF STAGE — program counter drives instruction ROM
    // =========================================================
    wire [15:0] pc;
    wire [31:0] instr_if;

    instruction_memory imem_inst (
        .addr(pc),
        .instruction(instr_if)
    );

    // =========================================================
    // IF/ID PIPELINE REGISTER
    // =========================================================
    reg [31:0] if_id_instr;
    reg [15:0] if_id_pc;
    reg        if_id_valid;

    // =========================================================
    // ID STAGE — decode + register-file read
    // =========================================================
    wire [5:0]  id_opcode = if_id_instr[31:26];
    wire [2:0]  id_rd     = if_id_instr[25:23];
    wire [2:0]  id_rs1    = if_id_instr[22:20];
    wire [2:0]  id_rs2    = if_id_instr[19:17];
    wire [15:0] id_imm16  = if_id_instr[15:0];

    wire id_is_alu, id_is_ldi, id_is_ld, id_is_st, id_is_jmp;
    wire id_is_beq, id_is_bne, id_is_out, id_is_hlt, id_is_call;
    wire id_is_ret, id_is_push, id_is_pop, id_is_sti, id_is_cli, id_is_iret;
    wire id_valid_op, id_reg_write, id_privileged;

    control_unit cu (
        .opcode(id_opcode),
        .is_alu(id_is_alu), .is_ldi(id_is_ldi), .is_ld(id_is_ld), .is_st(id_is_st),
        .is_jmp(id_is_jmp), .is_beq(id_is_beq), .is_bne(id_is_bne), .is_out(id_is_out),
        .is_hlt(id_is_hlt), .is_call(id_is_call), .is_ret(id_is_ret), .is_push(id_is_push),
        .is_pop(id_is_pop), .is_sti(id_is_sti), .is_cli(id_is_cli), .is_iret(id_is_iret),
        .valid(id_valid_op), .reg_write(id_reg_write), .privileged(id_privileged)
    );

    // =========================================================
    // Machine state (updated in EX)
    // =========================================================
    reg [15:0]      sp;
    reg             zf, cf;
    reg             kernel;
    reg             ie;
    reg             irq_pending;
    reg [WIDTH-1:0] timer_period, timer_count;
    reg [15:0]      ivec;
    reg [WIDTH-1:0] cause;
    reg             halted_r;

    // =========================================================
    // EX/MEM PIPELINE REGISTER
    // =========================================================
    reg [WIDTH-1:0] ex_mem_result;
    reg [2:0]       ex_mem_rd;
    reg             ex_mem_reg_write;

    // =========================================================
    // MEM/WB PIPELINE REGISTER
    // =========================================================
    reg [WIDTH-1:0] mem_wb_result;
    reg [2:0]       mem_wb_rd;
    reg             mem_wb_reg_write;

    // =========================================================
    // REGISTER FILE — reads in ID, write in WB
    // =========================================================
    wire [WIDTH-1:0] id_rdata1, id_rdata2;

    register_file #(.WIDTH(WIDTH)) rf (
        .clk(clk),
        .we(mem_wb_reg_write),
        .rs1(id_rs1), .rs2(id_rs2), .rd(mem_wb_rd),
        .write_data(mem_wb_result),
        .read_data1(id_rdata1), .read_data2(id_rdata2)
    );

    // =========================================================
    // ID/EX PIPELINE REGISTER
    // =========================================================

    // WB→ID forwarding: covers the 3-instruction-apart case where WB is writing
    // the same register that ID is reading in the same clock cycle.  Without this,
    // the register file would return the stale pre-write value.
    wire [WIDTH-1:0] id_rdata1_fwd =
        (mem_wb_reg_write & (mem_wb_rd != 0) & (mem_wb_rd == id_rs1)) ? mem_wb_result : id_rdata1;
    wire [WIDTH-1:0] id_rdata2_fwd =
        (mem_wb_reg_write & (mem_wb_rd != 0) & (mem_wb_rd == id_rs2)) ? mem_wb_result : id_rdata2;

    reg [5:0]       id_ex_opcode;
    reg [2:0]       id_ex_rd, id_ex_rs1, id_ex_rs2;
    reg [15:0]      id_ex_imm16, id_ex_pc;
    reg [WIDTH-1:0] id_ex_rdata1, id_ex_rdata2;
    reg             id_ex_valid;
    reg             id_ex_is_alu, id_ex_is_ldi, id_ex_is_ld, id_ex_is_st;
    reg             id_ex_is_jmp, id_ex_is_beq, id_ex_is_bne, id_ex_is_out;
    reg             id_ex_is_hlt, id_ex_is_call, id_ex_is_ret, id_ex_is_push;
    reg             id_ex_is_pop, id_ex_is_sti, id_ex_is_cli, id_ex_is_iret;
    reg             id_ex_reg_write, id_ex_valid_op, id_ex_privileged;

    // =========================================================
    // EX STAGE — forwarding + ALU + memory + state
    // =========================================================

    // EX/MEM → EX forwarding takes priority over MEM/WB → EX.
    wire [WIDTH-1:0] fwd_rs1 =
        (ex_mem_reg_write & (ex_mem_rd != 0) & (ex_mem_rd == id_ex_rs1)) ? ex_mem_result :
        (mem_wb_reg_write & (mem_wb_rd != 0) & (mem_wb_rd == id_ex_rs1)) ? mem_wb_result :
        id_ex_rdata1;

    wire [WIDTH-1:0] fwd_rs2 =
        (ex_mem_reg_write & (ex_mem_rd != 0) & (ex_mem_rd == id_ex_rs2)) ? ex_mem_result :
        (mem_wb_reg_write & (mem_wb_rd != 0) & (mem_wb_rd == id_ex_rs2)) ? mem_wb_result :
        id_ex_rdata2;

    wire [15:0] maddr     = fwd_rs1[15:0];
    wire        io_access = (maddr >= IO_BASE);

    // Trap sequencing — only fire when a valid instruction is in EX.
    wire take_irq  = id_ex_valid & ~halted_r & irq_pending & ie & (ivec != 16'd0);
    wire priv_viol = ~kernel & id_ex_valid &
                     (id_ex_privileged | ((id_ex_is_ld | id_ex_is_st) & io_access));
    wire exc       = id_ex_valid & ~halted_r & ~take_irq & (~id_ex_valid_op | priv_viol);
    wire take_exc  = exc & (ivec != 16'd0);
    wire entry     = take_irq | take_exc;
    wire exc_halt  = exc & (ivec == 16'd0);

    wire exec    = id_ex_valid & ~halted_r & ~entry & ~exc;
    wire do_halt = (exec & id_ex_is_hlt) | (~halted_r & exc_halt);

    // ALU (exposed as `alu_result` for testbench compatibility)
    wire [WIDTH-1:0] alu_result;
    wire             zero, carry_out;
    alu #(.WIDTH(WIDTH)) alu_inst (
        .a(fwd_rs1), .b(fwd_rs2), .op(id_ex_opcode[3:0]),
        .result(alu_result), .zero(zero), .carry_out(carry_out)
    );

    // Input stream (+in=<file>)
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

    // I/O reads (combinational)
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

    // Data memory — combinational read in EX, synchronous write at posedge.
    wire [15:0] saved_pc = take_irq ? id_ex_pc : (id_ex_pc + 16'd1);
    wire [WIDTH-1:0] frame = {{(WIDTH-20){1'b0}}, ie, kernel, cf, zf, saved_pc};

    wire stack_write = entry | (exec & (id_ex_is_push | id_ex_is_call));
    wire stack_read  = exec & (id_ex_is_pop | id_ex_is_ret | id_ex_is_iret);

    wire [15:0] dmem_addr  = stack_write ? (sp - 16'd1) :
                             stack_read  ? sp :
                                           maddr;
    wire [WIDTH-1:0] dmem_wdata =
        entry         ? frame :
        id_ex_is_call ? {{(WIDTH-16){1'b0}}, id_ex_pc + 16'd1} :
        id_ex_is_push ? fwd_rs1 :
                        fwd_rs2;
    wire dmem_we = stack_write | (exec & id_ex_is_st & ~io_access);
    wire [WIDTH-1:0] mem_rdata;

    data_memory #(.WIDTH(WIDTH)) dmem (
        .clk(clk), .we(dmem_we),
        .addr(dmem_addr), .wdata(dmem_wdata),
        .rdata(mem_rdata)
    );

    // Write-data selection (all computed in EX, result forwarded via EX/MEM)
    wire [WIDTH-1:0] imm_ext    = {{(WIDTH-16){1'b0}}, id_ex_imm16};
    wire [WIDTH-1:0] ld_data    = io_access ? io_rdata : mem_rdata;
    wire [WIDTH-1:0] write_data = id_ex_is_ldi ? imm_ext :
                                  id_ex_is_ld  ? ld_data :
                                  id_ex_is_pop ? mem_rdata :
                                                 alu_result;

    // Control hazard — taken branch or trap flushes both IF/ID and ID/EX (2 bubbles).
    wire branch_taken = exec & (id_ex_is_jmp | id_ex_is_call |
                                (id_ex_is_beq & zf) | (id_ex_is_bne & ~zf) |
                                id_ex_is_ret | id_ex_is_iret);
    wire [15:0] pc_target = (id_ex_is_ret | id_ex_is_iret) ? mem_rdata[15:0] : id_ex_imm16;
    wire        pc_load   = entry | branch_taken;
    wire [15:0] pc_in     = entry ? ivec : pc_target;
    wire        squash    = entry | branch_taken | do_halt;

    wire timer_write = exec & id_ex_is_st & io_access & (maddr == IO_TIMER);

    program_counter #(.AWIDTH(16)) pc_inst (
        .clk(clk), .rst(rst), .halt(halted_r | do_halt),
        .load(pc_load), .pc_in(pc_in),
        .pc_out(pc)
    );

    // =========================================================
    // IF/ID register update — flush on squash, advance otherwise
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst || squash) begin
            if_id_valid <= 0;
            if_id_instr <= 0;
            if_id_pc    <= 0;
        end else if (!halted_r) begin
            if_id_valid <= 1;
            if_id_instr <= instr_if;
            if_id_pc    <= pc;
        end
    end

    // =========================================================
    // ID/EX register update — flush on squash; preserve pc on halt
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            id_ex_valid <= 0;
            id_ex_opcode <= 0; id_ex_rd <= 0; id_ex_rs1 <= 0; id_ex_rs2 <= 0;
            id_ex_imm16 <= 0; id_ex_rdata1 <= 0; id_ex_rdata2 <= 0; id_ex_pc <= 0;
            id_ex_is_alu <= 0; id_ex_is_ldi <= 0; id_ex_is_ld <= 0; id_ex_is_st <= 0;
            id_ex_is_jmp <= 0; id_ex_is_beq <= 0; id_ex_is_bne <= 0; id_ex_is_out <= 0;
            id_ex_is_hlt <= 0; id_ex_is_call <= 0; id_ex_is_ret <= 0; id_ex_is_push <= 0;
            id_ex_is_pop <= 0; id_ex_is_sti <= 0; id_ex_is_cli <= 0; id_ex_is_iret <= 0;
            id_ex_reg_write <= 0; id_ex_valid_op <= 0; id_ex_privileged <= 0;
        end else if (do_halt) begin
            // Preserve id_ex_pc so testbenches can read the HLT address.
            id_ex_valid <= 0;
        end else if (squash) begin
            id_ex_valid <= 0;
            id_ex_opcode <= 0; id_ex_rd <= 0; id_ex_rs1 <= 0; id_ex_rs2 <= 0;
            id_ex_imm16 <= 0; id_ex_rdata1 <= 0; id_ex_rdata2 <= 0; id_ex_pc <= 0;
            id_ex_is_alu <= 0; id_ex_is_ldi <= 0; id_ex_is_ld <= 0; id_ex_is_st <= 0;
            id_ex_is_jmp <= 0; id_ex_is_beq <= 0; id_ex_is_bne <= 0; id_ex_is_out <= 0;
            id_ex_is_hlt <= 0; id_ex_is_call <= 0; id_ex_is_ret <= 0; id_ex_is_push <= 0;
            id_ex_is_pop <= 0; id_ex_is_sti <= 0; id_ex_is_cli <= 0; id_ex_is_iret <= 0;
            id_ex_reg_write <= 0; id_ex_valid_op <= 0; id_ex_privileged <= 0;
        end else if (!halted_r) begin
            id_ex_valid      <= if_id_valid;
            id_ex_opcode     <= id_opcode;
            id_ex_rd         <= id_rd;
            id_ex_rs1        <= id_rs1;
            id_ex_rs2        <= id_rs2;
            id_ex_imm16      <= id_imm16;
            id_ex_pc         <= if_id_pc;
            id_ex_rdata1     <= id_rdata1_fwd;
            id_ex_rdata2     <= id_rdata2_fwd;
            id_ex_is_alu     <= id_is_alu;
            id_ex_is_ldi     <= id_is_ldi;
            id_ex_is_ld      <= id_is_ld;
            id_ex_is_st      <= id_is_st;
            id_ex_is_jmp     <= id_is_jmp;
            id_ex_is_beq     <= id_is_beq;
            id_ex_is_bne     <= id_is_bne;
            id_ex_is_out     <= id_is_out;
            id_ex_is_hlt     <= id_is_hlt;
            id_ex_is_call    <= id_is_call;
            id_ex_is_ret     <= id_is_ret;
            id_ex_is_push    <= id_is_push;
            id_ex_is_pop     <= id_is_pop;
            id_ex_is_sti     <= id_is_sti;
            id_ex_is_cli     <= id_is_cli;
            id_ex_is_iret    <= id_is_iret;
            id_ex_reg_write  <= id_reg_write;
            id_ex_valid_op   <= id_valid_op;
            id_ex_privileged <= id_privileged;
        end
    end

    // =========================================================
    // EX/MEM register update
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_result <= 0; ex_mem_rd <= 0; ex_mem_reg_write <= 0;
        end else begin
            ex_mem_reg_write <= exec & id_ex_reg_write;
            ex_mem_result    <= write_data;
            ex_mem_rd        <= id_ex_rd;
        end
    end

    // =========================================================
    // MEM/WB register update
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_result <= 0; mem_wb_rd <= 0; mem_wb_reg_write <= 0;
        end else begin
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_result    <= ex_mem_result;
            mem_wb_rd        <= ex_mem_rd;
        end
    end

    // =========================================================
    // Machine state updates (EX stage, posedge clk)
    // =========================================================
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
                cause  <= take_irq ? 1 : (~id_ex_valid_op ? 2 : 3);
                if (take_irq) irq_pending <= 0;
            end else if (exec) begin
                if (id_ex_is_push | id_ex_is_call)              sp <= sp - 16'd1;
                if (id_ex_is_pop | id_ex_is_ret | id_ex_is_iret) sp <= sp + 16'd1;
                if (id_ex_is_sti) ie <= 1;
                if (id_ex_is_cli) ie <= 0;
                if (id_ex_is_iret) begin
                    zf     <= mem_rdata[16];
                    cf     <= mem_rdata[17];
                    kernel <= mem_rdata[18];
                    ie     <= mem_rdata[19];
                end else if (id_ex_reg_write) begin
                    zf <= (write_data == {WIDTH{1'b0}});
                    if (id_ex_opcode == 6'h00 || id_ex_opcode == 6'h01)
                        cf <= carry_out;
                end
                if (id_ex_is_st & io_access) begin
                    case (maddr)
                        IO_TIMER: begin timer_period <= fwd_rs2; timer_count <= 0; end
                        IO_IVEC:  ivec <= fwd_rs2[15:0];
                        default: ;
                    endcase
                end
                if (id_ex_is_ld & io_access & (maddr == IO_IN))
                    in_ptr <= in_ptr + 16'd1;
            end

            // timer ticks every cycle; skip the cycle when timer is programmed
            if (timer_period > 0 && !timer_write) begin
                if (timer_count + 1 >= timer_period) begin
                    timer_count <= 0;
                    irq_pending <= 1;
                end else
                    timer_count <= timer_count + 1;
            end
        end
    end

    // Aliases kept for testbench compatibility (cpu_tb.v reads these by name)
    wire [5:0] opcode = id_ex_opcode;

    assign halted    = halted_r;
    assign out_valid = exec & (id_ex_is_out | (id_ex_is_st & io_access & (maddr == IO_OUT)));
    assign out_data  = id_ex_is_out ? fwd_rs1 : fwd_rs2;
endmodule
