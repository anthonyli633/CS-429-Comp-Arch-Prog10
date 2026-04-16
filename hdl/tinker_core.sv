`timescale 1ns/1ps

module tinker_core (
    input clk,
    input reset,
    output logic hlt
);
    localparam MEM_SIZE       = 512 * 1024;
    localparam ARCH_REGS      = 32;
    localparam PHYS_REGS      = 64;
    localparam FREE_COUNT_MAX = PHYS_REGS - ARCH_REGS;
    localparam ROB_SIZE       = 16;
    localparam RS_SIZE        = 12;
    localparam LSQ_SIZE       = 8;
    localparam BHT_SIZE       = 16;

    localparam OP_AND       = 5'h00;
    localparam OP_OR        = 5'h01;
    localparam OP_XOR       = 5'h02;
    localparam OP_NOT       = 5'h03;
    localparam OP_SHFTR     = 5'h04;
    localparam OP_SHFTRI    = 5'h05;
    localparam OP_SHFTL     = 5'h06;
    localparam OP_SHFTLI    = 5'h07;
    localparam OP_BR        = 5'h08;
    localparam OP_BRR_REG   = 5'h09;
    localparam OP_BRR_LIT   = 5'h0a;
    localparam OP_BRNZ      = 5'h0b;
    localparam OP_CALL      = 5'h0c;
    localparam OP_RETURN    = 5'h0d;
    localparam OP_BRGT      = 5'h0e;
    localparam OP_PRIV      = 5'h0f;
    localparam OP_MOV_LOAD  = 5'h10;
    localparam OP_MOV_REG   = 5'h11;
    localparam OP_MOV_LIT   = 5'h12;
    localparam OP_MOV_STORE = 5'h13;
    localparam OP_ADDF      = 5'h14;
    localparam OP_SUBF      = 5'h15;
    localparam OP_MULF      = 5'h16;
    localparam OP_DIVF      = 5'h17;
    localparam OP_ADD       = 5'h18;
    localparam OP_ADDI      = 5'h19;
    localparam OP_SUB       = 5'h1a;
    localparam OP_SUBI      = 5'h1b;
    localparam OP_MUL       = 5'h1c;
    localparam OP_DIV       = 5'h1d;

    localparam ALU_PASS_A   = 6'd0;
    localparam ALU_PASS_B   = 6'd1;
    localparam ALU_AND      = 6'd2;
    localparam ALU_OR       = 6'd3;
    localparam ALU_XOR      = 6'd4;
    localparam ALU_NOT      = 6'd5;
    localparam ALU_SHR      = 6'd6;
    localparam ALU_SHL      = 6'd7;
    localparam ALU_ADD      = 6'd8;
    localparam ALU_SUB      = 6'd9;
    localparam ALU_MUL      = 6'd10;
    localparam ALU_DIV      = 6'd11;
    localparam ALU_FADD     = 6'd12;
    localparam ALU_FSUB     = 6'd13;
    localparam ALU_FMUL     = 6'd14;
    localparam ALU_FDIV     = 6'd15;

    integer i;
    integer j;
    integer k;
    integer slot;
    integer candidate;
    integer best;
    integer idx;
    integer addr_idx;
    integer head_idx;
    integer rob_idx;
    integer rs_idx;
    integer lsq_idx;
    integer old_head;
    integer old_tail;
    integer old_count;
    integer alu_pick0;
    integer alu_pick1;
    integer fpu_pick0;
    integer fpu_pick1;
    integer ls_pick0;
    integer ls_pick1;
    integer dist_a;
    integer dist_b;
    integer load_best_store;
    integer load_store_dist;
    integer slot_pc_offset;
    integer fetch_bht_idx;
    integer commit_count;
    integer free_snapshot_count;

    reg [63:0] phys_value [0:PHYS_REGS-1];
    reg        phys_ready [0:PHYS_REGS-1];
    reg [5:0]  rat [0:ARCH_REGS-1];
    reg [5:0]  checkpoint_rat [0:ARCH_REGS-1];
    reg [5:0]  free_list [0:FREE_COUNT_MAX-1];
    reg [5:0]  checkpoint_free_list [0:FREE_COUNT_MAX-1];
    integer    free_count;
    integer    checkpoint_free_count;

    reg        rob_valid [0:ROB_SIZE-1];
    reg        rob_ready [0:ROB_SIZE-1];
    reg [4:0]  rob_opcode [0:ROB_SIZE-1];
    reg [63:0] rob_pc [0:ROB_SIZE-1];
    reg        rob_has_dest [0:ROB_SIZE-1];
    reg [4:0]  rob_arch_dest [0:ROB_SIZE-1];
    reg [5:0]  rob_dest_phys [0:ROB_SIZE-1];
    reg [5:0]  rob_old_phys [0:ROB_SIZE-1];
    reg [63:0] rob_value [0:ROB_SIZE-1];
    reg        rob_is_store [0:ROB_SIZE-1];
    reg [63:0] rob_store_addr [0:ROB_SIZE-1];
    reg [63:0] rob_store_data [0:ROB_SIZE-1];
    reg        rob_store_addr_ready [0:ROB_SIZE-1];
    reg        rob_store_data_ready [0:ROB_SIZE-1];
    reg        rob_is_branch [0:ROB_SIZE-1];
    reg        rob_pred_taken [0:ROB_SIZE-1];
    reg [63:0] rob_pred_target [0:ROB_SIZE-1];
    reg        rob_is_halt [0:ROB_SIZE-1];
    integer    rob_head;
    integer    rob_tail;
    integer    rob_count;

    reg        rs_valid [0:RS_SIZE-1];
    reg [4:0]  rs_opcode [0:RS_SIZE-1];
    reg [63:0] rs_src0_val [0:RS_SIZE-1];
    reg [63:0] rs_src1_val [0:RS_SIZE-1];
    reg [63:0] rs_src2_val [0:RS_SIZE-1];
    reg        rs_src0_wait [0:RS_SIZE-1];
    reg        rs_src1_wait [0:RS_SIZE-1];
    reg        rs_src2_wait [0:RS_SIZE-1];
    reg        rs_use0 [0:RS_SIZE-1];
    reg        rs_use1 [0:RS_SIZE-1];
    reg        rs_use2 [0:RS_SIZE-1];
    reg [5:0]  rs_src0_tag [0:RS_SIZE-1];
    reg [5:0]  rs_src1_tag [0:RS_SIZE-1];
    reg [5:0]  rs_src2_tag [0:RS_SIZE-1];
    reg        rs_is_fpu [0:RS_SIZE-1];
    reg        rs_is_branch [0:RS_SIZE-1];
    reg        rs_has_dest [0:RS_SIZE-1];
    reg [5:0]  rs_dest_phys [0:RS_SIZE-1];
    reg [3:0]  rs_rob_idx [0:RS_SIZE-1];
    reg [63:0] rs_pc [0:RS_SIZE-1];
    reg        rs_pred_taken [0:RS_SIZE-1];
    reg [63:0] rs_pred_target [0:RS_SIZE-1];

    reg        lsq_valid [0:LSQ_SIZE-1];
    reg        lsq_is_load [0:LSQ_SIZE-1];
    reg [63:0] lsq_base_val [0:LSQ_SIZE-1];
    reg        lsq_base_wait [0:LSQ_SIZE-1];
    reg [5:0]  lsq_base_tag [0:LSQ_SIZE-1];
    reg [63:0] lsq_store_val [0:LSQ_SIZE-1];
    reg        lsq_store_wait [0:LSQ_SIZE-1];
    reg [5:0]  lsq_store_tag [0:LSQ_SIZE-1];
    reg [63:0] lsq_imm [0:LSQ_SIZE-1];
    reg        lsq_addr_ready [0:LSQ_SIZE-1];
    reg [63:0] lsq_addr [0:LSQ_SIZE-1];
    reg        lsq_has_dest [0:LSQ_SIZE-1];
    reg [5:0]  lsq_dest_phys [0:LSQ_SIZE-1];
    reg [3:0]  lsq_rob_idx [0:LSQ_SIZE-1];
    reg        lsq_inflight [0:LSQ_SIZE-1];

    reg [1:0]  bht [0:BHT_SIZE-1];
    reg        btb_valid [0:BHT_SIZE-1];
    reg [63:0] btb_target [0:BHT_SIZE-1];

    reg        checkpoint_valid;
    integer    checkpoint_rob_idx;

    reg        alu0_s0_valid;
    reg [4:0]  alu0_s0_opcode;
    reg [63:0] alu0_s0_a;
    reg [63:0] alu0_s0_b;
    reg [63:0] alu0_s0_c;
    reg [63:0] alu0_s0_pc;
    reg        alu0_s0_is_branch;
    reg        alu0_s0_has_dest;
    reg [5:0]  alu0_s0_dest_phys;
    reg [3:0]  alu0_s0_rob_idx;
    reg        alu0_s0_pred_taken;
    reg [63:0] alu0_s0_pred_target;

    reg        alu1_s0_valid;
    reg [4:0]  alu1_s0_opcode;
    reg [63:0] alu1_s0_a;
    reg [63:0] alu1_s0_b;
    reg [63:0] alu1_s0_c;
    reg [63:0] alu1_s0_pc;
    reg        alu1_s0_is_branch;
    reg        alu1_s0_has_dest;
    reg [5:0]  alu1_s0_dest_phys;
    reg [3:0]  alu1_s0_rob_idx;
    reg        alu1_s0_pred_taken;
    reg [63:0] alu1_s0_pred_target;

    reg        alu0_s1_valid;
    reg [4:0]  alu0_s1_opcode;
    reg [63:0] alu0_s1_result;
    reg [63:0] alu0_s1_a;
    reg [63:0] alu0_s1_b;
    reg [63:0] alu0_s1_c;
    reg [63:0] alu0_s1_pc;
    reg        alu0_s1_is_branch;
    reg        alu0_s1_has_dest;
    reg [5:0]  alu0_s1_dest_phys;
    reg [3:0]  alu0_s1_rob_idx;
    reg        alu0_s1_pred_taken;
    reg [63:0] alu0_s1_pred_target;

    reg        alu1_s1_valid;
    reg [4:0]  alu1_s1_opcode;
    reg [63:0] alu1_s1_result;
    reg [63:0] alu1_s1_a;
    reg [63:0] alu1_s1_b;
    reg [63:0] alu1_s1_c;
    reg [63:0] alu1_s1_pc;
    reg        alu1_s1_is_branch;
    reg        alu1_s1_has_dest;
    reg [5:0]  alu1_s1_dest_phys;
    reg [3:0]  alu1_s1_rob_idx;
    reg        alu1_s1_pred_taken;
    reg [63:0] alu1_s1_pred_target;

    reg        fpu0_s0_valid;
    reg [4:0]  fpu0_s0_opcode;
    reg [63:0] fpu0_s0_a;
    reg [63:0] fpu0_s0_b;
    reg        fpu0_s0_has_dest;
    reg [5:0]  fpu0_s0_dest_phys;
    reg [3:0]  fpu0_s0_rob_idx;

    reg        fpu1_s0_valid;
    reg [4:0]  fpu1_s0_opcode;
    reg [63:0] fpu1_s0_a;
    reg [63:0] fpu1_s0_b;
    reg        fpu1_s0_has_dest;
    reg [5:0]  fpu1_s0_dest_phys;
    reg [3:0]  fpu1_s0_rob_idx;

    reg        fpu0_s1_valid;
    reg [63:0] fpu0_s1_result;
    reg        fpu0_s1_has_dest;
    reg [5:0]  fpu0_s1_dest_phys;
    reg [3:0]  fpu0_s1_rob_idx;

    reg        fpu1_s1_valid;
    reg [63:0] fpu1_s1_result;
    reg        fpu1_s1_has_dest;
    reg [5:0]  fpu1_s1_dest_phys;
    reg [3:0]  fpu1_s1_rob_idx;

    reg        fpu0_s2_valid;
    reg [63:0] fpu0_s2_result;
    reg        fpu0_s2_has_dest;
    reg [5:0]  fpu0_s2_dest_phys;
    reg [3:0]  fpu0_s2_rob_idx;

    reg        fpu1_s2_valid;
    reg [63:0] fpu1_s2_result;
    reg        fpu1_s2_has_dest;
    reg [5:0]  fpu1_s2_dest_phys;
    reg [3:0]  fpu1_s2_rob_idx;

    reg        fpu0_s3_valid;
    reg [63:0] fpu0_s3_result;
    reg        fpu0_s3_has_dest;
    reg [5:0]  fpu0_s3_dest_phys;
    reg [3:0]  fpu0_s3_rob_idx;

    reg        fpu1_s3_valid;
    reg [63:0] fpu1_s3_result;
    reg        fpu1_s3_has_dest;
    reg [5:0]  fpu1_s3_dest_phys;
    reg [3:0]  fpu1_s3_rob_idx;

    reg        lsu0_s0_valid;
    reg        lsu0_s0_is_addr;
    reg [2:0]  lsu0_s0_lsq_idx;
    reg [63:0] lsu0_s0_base;
    reg [63:0] lsu0_s0_imm;
    reg [63:0] lsu0_s0_addr;
    reg [3:0]  lsu0_s0_rob_idx;

    reg        lsu1_s0_valid;
    reg        lsu1_s0_is_addr;
    reg [2:0]  lsu1_s0_lsq_idx;
    reg [63:0] lsu1_s0_base;
    reg [63:0] lsu1_s0_imm;
    reg [63:0] lsu1_s0_addr;
    reg [3:0]  lsu1_s0_rob_idx;

    reg        lsu0_s1_valid;
    reg        lsu0_s1_is_addr;
    reg [2:0]  lsu0_s1_lsq_idx;
    reg [63:0] lsu0_s1_addr;
    reg [63:0] lsu0_s1_result;
    reg [3:0]  lsu0_s1_rob_idx;

    reg        lsu1_s1_valid;
    reg        lsu1_s1_is_addr;
    reg [2:0]  lsu1_s1_lsq_idx;
    reg [63:0] lsu1_s1_addr;
    reg [63:0] lsu1_s1_result;
    reg [3:0]  lsu1_s1_rob_idx;

    reg [63:0] fetch_pc_next;
    reg        fetch_stop;
    reg        slot_issued;
    reg [31:0] slot_inst;
    reg [4:0]  slot_opcode;
    reg [4:0]  slot_rd;
    reg [4:0]  slot_rs;
    reg [4:0]  slot_rt;
    reg [11:0] slot_lit12;
    reg [63:0] slot_lit_zext;
    reg [63:0] slot_lit_sext;
    reg        slot_pred_taken;
    reg [63:0] slot_pred_target;
    reg        need_dest_phys;
    reg [5:0]  new_dest_phys;
    reg [5:0]  old_dest_phys;
    reg [63:0] src_val;
    reg [63:0] src_val1;
    reg [63:0] src_val2;
    reg        src_wait;
    reg        src_wait1;
    reg        src_wait2;
    reg [5:0]  src_tag;
    reg [5:0]  src_tag1;
    reg [5:0]  src_tag2;
    reg [63:0] branch_target;
    reg        branch_taken;
    reg        mispredict;
    reg [63:0] correct_pc;
    reg [63:0] forwarded_value;
    reg        forward_found;
    reg        forward_blocked;
    reg        halt_inflight;

    wire [31:0] unused_inst_word;
    wire [63:0] unused_data_word;
    wire [63:0] unused_read_a;
    wire [63:0] unused_read_b;
    wire [63:0] unused_read_c;
    wire [63:0] unused_sp_data;

    reg [63:0] alu0_pipe_a;
    reg [63:0] alu0_pipe_b;
    reg [5:0]  alu0_pipe_op;
    wire [63:0] alu0_pipe_result;
    wire        alu0_pipe_zero;
    wire        alu0_pipe_gt;

    reg [63:0] alu1_pipe_a;
    reg [63:0] alu1_pipe_b;
    reg [5:0]  alu1_pipe_op;
    wire [63:0] alu1_pipe_result;
    wire        alu1_pipe_zero;
    wire        alu1_pipe_gt;

    reg [63:0] fpu0_pipe_a;
    reg [63:0] fpu0_pipe_b;
    reg [5:0]  fpu0_pipe_op;
    wire [63:0] fpu0_pipe_result;

    reg [63:0] fpu1_pipe_a;
    reg [63:0] fpu1_pipe_b;
    reg [5:0]  fpu1_pipe_op;
    wire [63:0] fpu1_pipe_result;

    tinker_memory #( .MEM_SIZE(MEM_SIZE) ) memory (
        .clk(clk),
        .inst_addr(64'd0),
        .inst_word(unused_inst_word),
        .data_addr(64'd0),
        .data_write_data(64'd0),
        .data_write_en(1'b0),
        .data_read_data(unused_data_word)
    );

    tinker_fetch fetch (
        .clk(clk),
        .reset(reset),
        .pc_write(1'b0),
        .pc_next(64'd0),
        .pc()
    );

    tinker_reg_file #( .MEM_SIZE(MEM_SIZE) ) reg_file (
        .clk(clk),
        .reset(reset),
        .read_addr_a(5'd0),
        .read_addr_b(5'd0),
        .read_addr_c(5'd0),
        .read_data_a(unused_read_a),
        .read_data_b(unused_read_b),
        .read_data_c(unused_read_c),
        .sp_data(unused_sp_data),
        .write_en(1'b0),
        .write_addr(5'd0),
        .write_data(64'd0)
    );

    tinker_alu alu0 (
        .a(alu0_pipe_a),
        .b(alu0_pipe_b),
        .op(alu0_pipe_op),
        .result(alu0_pipe_result),
        .a_is_zero(alu0_pipe_zero),
        .a_gt_b_signed(alu0_pipe_gt)
    );

    tinker_alu alu1 (
        .a(alu1_pipe_a),
        .b(alu1_pipe_b),
        .op(alu1_pipe_op),
        .result(alu1_pipe_result),
        .a_is_zero(alu1_pipe_zero),
        .a_gt_b_signed(alu1_pipe_gt)
    );

    tinker_fpu fpu (
        .a(fpu0_pipe_a),
        .b(fpu0_pipe_b),
        .op(fpu0_pipe_op),
        .result(fpu0_pipe_result)
    );

    tinker_fpu fpu1 (
        .a(fpu1_pipe_a),
        .b(fpu1_pipe_b),
        .op(fpu1_pipe_op),
        .result(fpu1_pipe_result)
    );

    function automatic integer rob_inc(input integer value);
        begin
            if (value == ROB_SIZE - 1)
                rob_inc = 0;
            else
                rob_inc = value + 1;
        end
    endfunction

    function automatic integer rob_distance(input integer entry_idx);
        begin
            if (entry_idx >= rob_head)
                rob_distance = entry_idx - rob_head;
            else
                rob_distance = entry_idx + ROB_SIZE - rob_head;
        end
    endfunction

    function automatic integer rob_younger_than(input integer entry_idx, input integer branch_idx);
        begin
            rob_younger_than = rob_valid[entry_idx] && (rob_distance(entry_idx) > rob_distance(branch_idx));
        end
    endfunction

    function automatic [63:0] signext12(input [11:0] lit);
        begin
            signext12 = {{52{lit[11]}}, lit};
        end
    endfunction

    function automatic integer bht_idx(input [63:0] pc);
        begin
            bht_idx = pc[5:2];
        end
    endfunction

    function automatic integer is_fpu_opcode(input [4:0] opcode);
        begin
            is_fpu_opcode = (opcode == OP_ADDF) || (opcode == OP_SUBF) ||
                            (opcode == OP_MULF) || (opcode == OP_DIVF);
        end
    endfunction

    function automatic integer is_load_opcode(input [4:0] opcode);
        begin
            is_load_opcode = (opcode == OP_MOV_LOAD);
        end
    endfunction

    function automatic integer is_store_opcode(input [4:0] opcode);
        begin
            is_store_opcode = (opcode == OP_MOV_STORE);
        end
    endfunction

    function automatic integer is_branch_opcode(input [4:0] opcode);
        begin
            is_branch_opcode = (opcode == OP_BR) || (opcode == OP_BRR_REG) ||
                               (opcode == OP_BRR_LIT) || (opcode == OP_BRNZ) ||
                               (opcode == OP_BRGT) || (opcode == OP_CALL) ||
                               (opcode == OP_RETURN);
        end
    endfunction

    function automatic integer has_dest_opcode(input [4:0] opcode, input [11:0] lit);
        begin
            has_dest_opcode = !is_branch_opcode(opcode) &&
                              !is_load_opcode(opcode) &&
                              !is_store_opcode(opcode) &&
                              !((opcode == OP_PRIV) && (lit == 12'h000));
            if (opcode == OP_MOV_LOAD)
                has_dest_opcode = 1;
        end
    endfunction

    function automatic integer is_halt_opcode(input [4:0] opcode, input [11:0] lit);
        begin
            is_halt_opcode = (opcode == OP_PRIV) && (lit == 12'h000);
        end
    endfunction

    function automatic [5:0] alu_sel_for_opcode(input [4:0] opcode);
        begin
            case (opcode)
                OP_AND    : alu_sel_for_opcode = ALU_AND;
                OP_OR     : alu_sel_for_opcode = ALU_OR;
                OP_XOR    : alu_sel_for_opcode = ALU_XOR;
                OP_NOT    : alu_sel_for_opcode = ALU_NOT;
                OP_SHFTR  : alu_sel_for_opcode = ALU_SHR;
                OP_SHFTRI : alu_sel_for_opcode = ALU_SHR;
                OP_SHFTL  : alu_sel_for_opcode = ALU_SHL;
                OP_SHFTLI : alu_sel_for_opcode = ALU_SHL;
                OP_MOV_REG : alu_sel_for_opcode = ALU_PASS_A;
                OP_ADD    : alu_sel_for_opcode = ALU_ADD;
                OP_ADDI   : alu_sel_for_opcode = ALU_ADD;
                OP_SUB    : alu_sel_for_opcode = ALU_SUB;
                OP_SUBI   : alu_sel_for_opcode = ALU_SUB;
                OP_MUL    : alu_sel_for_opcode = ALU_MUL;
                OP_DIV    : alu_sel_for_opcode = ALU_DIV;
                default   : alu_sel_for_opcode = ALU_PASS_A;
            endcase
        end
    endfunction

    function automatic [5:0] fpu_sel_for_opcode(input [4:0] opcode);
        begin
            case (opcode)
                OP_ADDF: fpu_sel_for_opcode = ALU_FADD;
                OP_SUBF: fpu_sel_for_opcode = ALU_FSUB;
                OP_MULF: fpu_sel_for_opcode = ALU_FMUL;
                OP_DIVF: fpu_sel_for_opcode = ALU_FDIV;
                default: fpu_sel_for_opcode = ALU_FADD;
            endcase
        end
    endfunction

    function automatic [31:0] read_inst32(input [63:0] addr);
        integer local_idx;
        begin
            local_idx = addr[31:0];
            if (local_idx + 3 < MEM_SIZE)
                read_inst32 = {memory.bytes[local_idx + 3], memory.bytes[local_idx + 2],
                               memory.bytes[local_idx + 1], memory.bytes[local_idx + 0]};
            else
                read_inst32 = 32'd0;
        end
    endfunction

    function automatic [63:0] read_mem64_direct(input [63:0] addr);
        integer local_idx;
        begin
            local_idx = addr[31:0];
            if (local_idx + 7 < MEM_SIZE)
                read_mem64_direct = {
                    memory.bytes[local_idx + 7], memory.bytes[local_idx + 6],
                    memory.bytes[local_idx + 5], memory.bytes[local_idx + 4],
                    memory.bytes[local_idx + 3], memory.bytes[local_idx + 2],
                    memory.bytes[local_idx + 1], memory.bytes[local_idx + 0]
                };
            else
                read_mem64_direct = 64'd0;
        end
    endfunction

    task automatic capture_operand;
        input [4:0] arch_reg;
        output reg wait_out;
        output reg [5:0] tag_out;
        output reg [63:0] value_out;
        reg [5:0] phys_reg;
        begin
            phys_reg = rat[arch_reg];
            if (phys_reg < ARCH_REGS) begin
                wait_out = 1'b0;
                tag_out = phys_reg;
                value_out = reg_file.registers[phys_reg];
            end else if (phys_ready[phys_reg]) begin
                wait_out = 1'b0;
                tag_out = phys_reg;
                value_out = phys_value[phys_reg];
            end else begin
                wait_out = 1'b1;
                tag_out = phys_reg;
                value_out = 64'd0;
            end
        end
    endtask

    task automatic capture_operand_from_phys;
        input [5:0] phys_reg;
        output reg wait_out;
        output reg [5:0] tag_out;
        output reg [63:0] value_out;
        begin
            if (phys_reg < ARCH_REGS) begin
                wait_out = 1'b0;
                tag_out = phys_reg;
                value_out = reg_file.registers[phys_reg];
            end else if (phys_ready[phys_reg]) begin
                wait_out = 1'b0;
                tag_out = phys_reg;
                value_out = phys_value[phys_reg];
            end else begin
                wait_out = 1'b1;
                tag_out = phys_reg;
                value_out = 64'd0;
            end
        end
    endtask

    task automatic wakeup_tag;
        input [5:0] tag;
        input [63:0] value;
        begin
            if (tag < PHYS_REGS) begin
                for (k = 0; k < RS_SIZE; k = k + 1) begin
                    if (rs_valid[k]) begin
                        if (rs_use0[k] && rs_src0_wait[k] && (rs_src0_tag[k] == tag)) begin
                            rs_src0_wait[k] = 1'b0;
                            rs_src0_val[k] = value;
                        end
                        if (rs_use1[k] && rs_src1_wait[k] && (rs_src1_tag[k] == tag)) begin
                            rs_src1_wait[k] = 1'b0;
                            rs_src1_val[k] = value;
                        end
                        if (rs_use2[k] && rs_src2_wait[k] && (rs_src2_tag[k] == tag)) begin
                            rs_src2_wait[k] = 1'b0;
                            rs_src2_val[k] = value;
                        end
                    end
                end

                for (k = 0; k < LSQ_SIZE; k = k + 1) begin
                    if (lsq_valid[k]) begin
                        if (lsq_base_wait[k] && (lsq_base_tag[k] == tag)) begin
                            lsq_base_wait[k] = 1'b0;
                            lsq_base_val[k] = value;
                        end
                        if (!lsq_is_load[k] && lsq_store_wait[k] && (lsq_store_tag[k] == tag)) begin
                            lsq_store_wait[k] = 1'b0;
                            lsq_store_val[k] = value;
                            rob_store_data[lsq_rob_idx[k]] = value;
                            rob_store_data_ready[lsq_rob_idx[k]] = 1'b1;
                            if (rob_store_addr_ready[lsq_rob_idx[k]])
                                rob_ready[lsq_rob_idx[k]] = 1'b1;
                        end
                    end
                end
            end
        end
    endtask

    task automatic finish_result;
        input [5:0] dest_phys;
        input [3:0] finish_rob_idx;
        input [63:0] value;
        begin
            if (dest_phys < PHYS_REGS) begin
                phys_value[dest_phys] = value;
                phys_ready[dest_phys] = 1'b1;
                wakeup_tag(dest_phys, value);
            end
            rob_ready[finish_rob_idx] = 1'b1;
            rob_value[finish_rob_idx] = value;
        end
    endtask

    task automatic predict_instruction;
        input [63:0] pc;
        input [4:0] opcode;
        input [11:0] lit;
        output reg pred_taken;
        output reg [63:0] pred_target;
        integer pred_idx;
        begin
            pred_idx = bht_idx(pc);
            pred_taken = 1'b0;
            pred_target = pc + 64'd4;

            case (opcode)
                OP_BRR_LIT: begin
                    pred_taken = 1'b1;
                    pred_target = pc + signext12(lit);
                end
                OP_BR, OP_BRR_REG, OP_CALL, OP_RETURN: begin
                    if (btb_valid[pred_idx]) begin
                        pred_taken = 1'b1;
                        pred_target = btb_target[pred_idx];
                    end
                end
                OP_BRNZ, OP_BRGT: begin
                    if (bht[pred_idx][1] && btb_valid[pred_idx]) begin
                        pred_taken = 1'b1;
                        pred_target = btb_target[pred_idx];
                    end
                end
                default: begin
                    pred_taken = 1'b0;
                    pred_target = pc + 64'd4;
                end
            endcase
        end
    endtask

    task automatic scan_store_forward;
        input [63:0] addr;
        input integer cur_rob_idx;
        output reg found_out;
        output reg blocked_out;
        output reg [63:0] value_out;
        integer s;
        integer best_dist;
        integer dist_cur;
        begin
            found_out = 1'b0;
            blocked_out = 1'b0;
            value_out = 64'd0;
            load_best_store = -1;
            best_dist = -1;
            dist_cur = rob_distance(cur_rob_idx);

            for (s = 0; s < ROB_SIZE; s = s + 1) begin
                if (rob_valid[s] && rob_is_store[s] && (rob_distance(s) < dist_cur)) begin
                    if (!rob_store_addr_ready[s]) begin
                        blocked_out = 1'b1;
                    end else if (rob_store_addr[s] == addr) begin
                        if (!rob_store_data_ready[s]) begin
                            blocked_out = 1'b1;
                        end else if (rob_distance(s) > best_dist) begin
                            best_dist = rob_distance(s);
                            load_best_store = s;
                        end
                    end
                end
            end

            if (load_best_store != -1) begin
                found_out = 1'b1;
                value_out = rob_store_data[load_best_store];
            end
        end
    endtask

    always @(*) begin
        alu0_pipe_a = alu0_s0_a;
        alu0_pipe_b = alu0_s0_b;
        alu0_pipe_op = alu_sel_for_opcode(alu0_s0_opcode);

        alu1_pipe_a = alu1_s0_a;
        alu1_pipe_b = alu1_s0_b;
        alu1_pipe_op = alu_sel_for_opcode(alu1_s0_opcode);

        fpu0_pipe_a = fpu0_s0_a;
        fpu0_pipe_b = fpu0_s0_b;
        fpu0_pipe_op = fpu_sel_for_opcode(fpu0_s0_opcode);

        fpu1_pipe_a = fpu1_s0_a;
        fpu1_pipe_b = fpu1_s0_b;
        fpu1_pipe_op = fpu_sel_for_opcode(fpu1_s0_opcode);
    end

    always @(posedge clk) begin
        if (reset) begin
            hlt <= 1'b0;
            fetch.pc = 64'h0000_0000_0000_2000;

            rob_head = 0;
            rob_tail = 0;
            rob_count = 0;
            checkpoint_valid = 1'b0;
            checkpoint_rob_idx = 0;
            free_count = FREE_COUNT_MAX;
            checkpoint_free_count = FREE_COUNT_MAX;

            alu0_s0_valid = 1'b0;
            alu1_s0_valid = 1'b0;
            alu0_s1_valid = 1'b0;
            alu1_s1_valid = 1'b0;
            fpu0_s0_valid = 1'b0;
            fpu1_s0_valid = 1'b0;
            fpu0_s1_valid = 1'b0;
            fpu1_s1_valid = 1'b0;
            fpu0_s2_valid = 1'b0;
            fpu1_s2_valid = 1'b0;
            fpu0_s3_valid = 1'b0;
            fpu1_s3_valid = 1'b0;
            lsu0_s0_valid = 1'b0;
            lsu1_s0_valid = 1'b0;
            lsu0_s1_valid = 1'b0;
            lsu1_s1_valid = 1'b0;

            for (i = 0; i < ARCH_REGS; i = i + 1) begin
                rat[i] = i[5:0];
                checkpoint_rat[i] = i[5:0];
            end

            for (i = 0; i < PHYS_REGS; i = i + 1) begin
                phys_value[i] = 64'd0;
                phys_ready[i] = 1'b1;
            end
            phys_value[31] = MEM_SIZE;

            for (i = 0; i < FREE_COUNT_MAX; i = i + 1) begin
                free_list[i] = ARCH_REGS + i;
                checkpoint_free_list[i] = ARCH_REGS + i;
            end

            for (i = 0; i < ROB_SIZE; i = i + 1) begin
                rob_valid[i] = 1'b0;
                rob_ready[i] = 1'b0;
                rob_opcode[i] = 5'd0;
                rob_pc[i] = 64'd0;
                rob_has_dest[i] = 1'b0;
                rob_arch_dest[i] = 5'd0;
                rob_dest_phys[i] = 6'd0;
                rob_old_phys[i] = 6'd0;
                rob_value[i] = 64'd0;
                rob_is_store[i] = 1'b0;
                rob_store_addr[i] = 64'd0;
                rob_store_data[i] = 64'd0;
                rob_store_addr_ready[i] = 1'b0;
                rob_store_data_ready[i] = 1'b0;
                rob_is_branch[i] = 1'b0;
                rob_pred_taken[i] = 1'b0;
                rob_pred_target[i] = 64'd0;
                rob_is_halt[i] = 1'b0;
            end

            for (i = 0; i < RS_SIZE; i = i + 1) begin
                rs_valid[i] = 1'b0;
                rs_opcode[i] = 5'd0;
                rs_src0_val[i] = 64'd0;
                rs_src1_val[i] = 64'd0;
                rs_src2_val[i] = 64'd0;
                rs_src0_wait[i] = 1'b0;
                rs_src1_wait[i] = 1'b0;
                rs_src2_wait[i] = 1'b0;
                rs_use0[i] = 1'b0;
                rs_use1[i] = 1'b0;
                rs_use2[i] = 1'b0;
                rs_src0_tag[i] = 6'd0;
                rs_src1_tag[i] = 6'd0;
                rs_src2_tag[i] = 6'd0;
                rs_is_fpu[i] = 1'b0;
                rs_is_branch[i] = 1'b0;
                rs_has_dest[i] = 1'b0;
                rs_dest_phys[i] = 6'd0;
                rs_rob_idx[i] = 4'd0;
                rs_pc[i] = 64'd0;
                rs_pred_taken[i] = 1'b0;
                rs_pred_target[i] = 64'd0;
            end

            for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                lsq_valid[i] = 1'b0;
                lsq_is_load[i] = 1'b0;
                lsq_base_val[i] = 64'd0;
                lsq_base_wait[i] = 1'b0;
                lsq_base_tag[i] = 6'd0;
                lsq_store_val[i] = 64'd0;
                lsq_store_wait[i] = 1'b0;
                lsq_store_tag[i] = 6'd0;
                lsq_imm[i] = 64'd0;
                lsq_addr_ready[i] = 1'b0;
                lsq_addr[i] = 64'd0;
                lsq_has_dest[i] = 1'b0;
                lsq_dest_phys[i] = 6'd0;
                lsq_rob_idx[i] = 4'd0;
                lsq_inflight[i] = 1'b0;
            end

            for (i = 0; i < BHT_SIZE; i = i + 1) begin
                bht[i] = 2'b01;
                btb_valid[i] = 1'b0;
                btb_target[i] = 64'd0;
            end
        end else begin
            if (hlt) begin
                fetch.pc = fetch.pc;
            end else begin
                mispredict = 1'b0;
                correct_pc = fetch.pc;

                if (alu0_s1_valid) begin
                    if (alu0_s1_is_branch) begin
                        branch_taken = 1'b0;
                        branch_target = alu0_s1_pc + 64'd4;

                        case (alu0_s1_opcode)
                            OP_BR: begin
                                branch_taken = 1'b1;
                                branch_target = alu0_s1_a;
                            end
                            OP_BRR_REG: begin
                                branch_taken = 1'b1;
                                branch_target = alu0_s1_pc + alu0_s1_a;
                            end
                            OP_BRR_LIT: begin
                                branch_taken = 1'b1;
                                branch_target = alu0_s1_pc + alu0_s1_a;
                            end
                            OP_BRNZ: begin
                                branch_taken = (alu0_s1_b != 64'd0);
                                branch_target = alu0_s1_a;
                            end
                            OP_BRGT: begin
                                branch_taken = ($signed(alu0_s1_b) > $signed(alu0_s1_c));
                                branch_target = alu0_s1_a;
                            end
                            OP_CALL: begin
                                branch_taken = 1'b1;
                                branch_target = alu0_s1_a;
                                rob_store_addr[alu0_s1_rob_idx] = alu0_s1_b - 64'd8;
                                rob_store_data[alu0_s1_rob_idx] = alu0_s1_pc + 64'd4;
                                rob_store_addr_ready[alu0_s1_rob_idx] = 1'b1;
                                rob_store_data_ready[alu0_s1_rob_idx] = 1'b1;
                            end
                            OP_RETURN: begin
                                scan_store_forward(alu0_s1_a - 64'd8, alu0_s1_rob_idx, forward_found, forward_blocked, forwarded_value);
                                if (forward_found)
                                    branch_target = forwarded_value;
                                else
                                    branch_target = read_mem64_direct(alu0_s1_a - 64'd8);
                                branch_taken = 1'b1;
                            end
                            default: begin
                                branch_taken = 1'b0;
                                branch_target = alu0_s1_pc + 64'd4;
                            end
                        endcase

                        fetch_bht_idx = bht_idx(alu0_s1_pc);
                        if (branch_taken) begin
                            btb_valid[fetch_bht_idx] = 1'b1;
                            btb_target[fetch_bht_idx] = branch_target;
                            if (bht[fetch_bht_idx] != 2'b11)
                                bht[fetch_bht_idx] = bht[fetch_bht_idx] + 2'b01;
                        end else if ((alu0_s1_opcode == OP_BRNZ) || (alu0_s1_opcode == OP_BRGT)) begin
                            if (bht[fetch_bht_idx] != 2'b00)
                                bht[fetch_bht_idx] = bht[fetch_bht_idx] - 2'b01;
                        end

                        rob_ready[alu0_s1_rob_idx] = 1'b1;

                        if (rob_is_store[alu0_s1_rob_idx] && rob_store_addr_ready[alu0_s1_rob_idx] && rob_store_data_ready[alu0_s1_rob_idx])
                            rob_ready[alu0_s1_rob_idx] = 1'b1;

                        if ((branch_taken != alu0_s1_pred_taken) ||
                            (branch_taken && (branch_target != alu0_s1_pred_target))) begin
                            mispredict = 1'b1;
                            correct_pc = branch_taken ? branch_target : (alu0_s1_pc + 64'd4);
                        end
                    end else if (alu0_s1_has_dest) begin
                        finish_result(alu0_s1_dest_phys, alu0_s1_rob_idx, alu0_s1_result);
                    end
                end

                if (alu1_s1_valid && !mispredict) begin
                    if (alu1_s1_is_branch) begin
                        branch_taken = 1'b0;
                        branch_target = alu1_s1_pc + 64'd4;

                        case (alu1_s1_opcode)
                            OP_BR: begin
                                branch_taken = 1'b1;
                                branch_target = alu1_s1_a;
                            end
                            OP_BRR_REG: begin
                                branch_taken = 1'b1;
                                branch_target = alu1_s1_pc + alu1_s1_a;
                            end
                            OP_BRR_LIT: begin
                                branch_taken = 1'b1;
                                branch_target = alu1_s1_pc + alu1_s1_a;
                            end
                            OP_BRNZ: begin
                                branch_taken = (alu1_s1_b != 64'd0);
                                branch_target = alu1_s1_a;
                            end
                            OP_BRGT: begin
                                branch_taken = ($signed(alu1_s1_b) > $signed(alu1_s1_c));
                                branch_target = alu1_s1_a;
                            end
                            OP_CALL: begin
                                branch_taken = 1'b1;
                                branch_target = alu1_s1_a;
                                rob_store_addr[alu1_s1_rob_idx] = alu1_s1_b - 64'd8;
                                rob_store_data[alu1_s1_rob_idx] = alu1_s1_pc + 64'd4;
                                rob_store_addr_ready[alu1_s1_rob_idx] = 1'b1;
                                rob_store_data_ready[alu1_s1_rob_idx] = 1'b1;
                            end
                            OP_RETURN: begin
                                scan_store_forward(alu1_s1_a - 64'd8, alu1_s1_rob_idx, forward_found, forward_blocked, forwarded_value);
                                if (forward_found)
                                    branch_target = forwarded_value;
                                else
                                    branch_target = read_mem64_direct(alu1_s1_a - 64'd8);
                                branch_taken = 1'b1;
                            end
                            default: begin
                                branch_taken = 1'b0;
                                branch_target = alu1_s1_pc + 64'd4;
                            end
                        endcase

                        fetch_bht_idx = bht_idx(alu1_s1_pc);
                        if (branch_taken) begin
                            btb_valid[fetch_bht_idx] = 1'b1;
                            btb_target[fetch_bht_idx] = branch_target;
                            if (bht[fetch_bht_idx] != 2'b11)
                                bht[fetch_bht_idx] = bht[fetch_bht_idx] + 2'b01;
                        end else if ((alu1_s1_opcode == OP_BRNZ) || (alu1_s1_opcode == OP_BRGT)) begin
                            if (bht[fetch_bht_idx] != 2'b00)
                                bht[fetch_bht_idx] = bht[fetch_bht_idx] - 2'b01;
                        end

                        rob_ready[alu1_s1_rob_idx] = 1'b1;

                        if (rob_is_store[alu1_s1_rob_idx] && rob_store_addr_ready[alu1_s1_rob_idx] && rob_store_data_ready[alu1_s1_rob_idx])
                            rob_ready[alu1_s1_rob_idx] = 1'b1;

                        if ((branch_taken != alu1_s1_pred_taken) ||
                            (branch_taken && (branch_target != alu1_s1_pred_target))) begin
                            mispredict = 1'b1;
                            correct_pc = branch_taken ? branch_target : (alu1_s1_pc + 64'd4);
                        end
                    end else if (alu1_s1_has_dest) begin
                        finish_result(alu1_s1_dest_phys, alu1_s1_rob_idx, alu1_s1_result);
                    end
                end

                if (fpu0_s3_valid && !mispredict && fpu0_s3_has_dest)
                    finish_result(fpu0_s3_dest_phys, fpu0_s3_rob_idx, fpu0_s3_result);

                if (fpu1_s3_valid && !mispredict && fpu1_s3_has_dest)
                    finish_result(fpu1_s3_dest_phys, fpu1_s3_rob_idx, fpu1_s3_result);

                if (lsu0_s1_valid && !mispredict) begin
                    lsq_inflight[lsu0_s1_lsq_idx] = 1'b0;
                    if (lsu0_s1_is_addr) begin
                        lsq_addr_ready[lsu0_s1_lsq_idx] = 1'b1;
                        lsq_addr[lsu0_s1_lsq_idx] = lsu0_s1_addr;
                        rob_store_addr[lsq_rob_idx[lsu0_s1_lsq_idx]] = lsu0_s1_addr;
                        rob_store_addr_ready[lsq_rob_idx[lsu0_s1_lsq_idx]] = 1'b1;
                        if (!lsq_is_load[lsu0_s1_lsq_idx] && rob_store_data_ready[lsq_rob_idx[lsu0_s1_lsq_idx]])
                            rob_ready[lsq_rob_idx[lsu0_s1_lsq_idx]] = 1'b1;
                    end else begin
                        finish_result(lsq_dest_phys[lsu0_s1_lsq_idx], lsq_rob_idx[lsu0_s1_lsq_idx], lsu0_s1_result);
                        lsq_valid[lsu0_s1_lsq_idx] = 1'b0;
                    end
                end

                if (lsu1_s1_valid && !mispredict) begin
                    lsq_inflight[lsu1_s1_lsq_idx] = 1'b0;
                    if (lsu1_s1_is_addr) begin
                        lsq_addr_ready[lsu1_s1_lsq_idx] = 1'b1;
                        lsq_addr[lsu1_s1_lsq_idx] = lsu1_s1_addr;
                        rob_store_addr[lsq_rob_idx[lsu1_s1_lsq_idx]] = lsu1_s1_addr;
                        rob_store_addr_ready[lsq_rob_idx[lsu1_s1_lsq_idx]] = 1'b1;
                        if (!lsq_is_load[lsu1_s1_lsq_idx] && rob_store_data_ready[lsq_rob_idx[lsu1_s1_lsq_idx]])
                            rob_ready[lsq_rob_idx[lsu1_s1_lsq_idx]] = 1'b1;
                    end else begin
                        finish_result(lsq_dest_phys[lsu1_s1_lsq_idx], lsq_rob_idx[lsu1_s1_lsq_idx], lsu1_s1_result);
                        lsq_valid[lsu1_s1_lsq_idx] = 1'b0;
                    end
                end

                if (mispredict && checkpoint_valid) begin
                    for (i = 0; i < ARCH_REGS; i = i + 1)
                        rat[i] = checkpoint_rat[i];

                    free_count = checkpoint_free_count;
                    for (i = 0; i < FREE_COUNT_MAX; i = i + 1)
                        free_list[i] = checkpoint_free_list[i];

                    for (i = 0; i < ROB_SIZE; i = i + 1) begin
                        if (rob_younger_than(i, checkpoint_rob_idx))
                            rob_valid[i] = 1'b0;
                    end
                    rob_tail = rob_inc(checkpoint_rob_idx);
                    rob_count = rob_distance(checkpoint_rob_idx) + 1;

                    for (i = 0; i < RS_SIZE; i = i + 1) begin
                        if (rs_valid[i] && rob_younger_than(rs_rob_idx[i], checkpoint_rob_idx))
                            rs_valid[i] = 1'b0;
                    end

                    for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                        if (lsq_valid[i] && rob_younger_than(lsq_rob_idx[i], checkpoint_rob_idx)) begin
                            lsq_valid[i] = 1'b0;
                            lsq_inflight[i] = 1'b0;
                        end
                    end

                    if (alu0_s0_valid && rob_younger_than(alu0_s0_rob_idx, checkpoint_rob_idx)) alu0_s0_valid = 1'b0;
                    if (alu1_s0_valid && rob_younger_than(alu1_s0_rob_idx, checkpoint_rob_idx)) alu1_s0_valid = 1'b0;
                    if (alu0_s1_valid && rob_younger_than(alu0_s1_rob_idx, checkpoint_rob_idx)) alu0_s1_valid = 1'b0;
                    if (alu1_s1_valid && rob_younger_than(alu1_s1_rob_idx, checkpoint_rob_idx)) alu1_s1_valid = 1'b0;
                    if (fpu0_s0_valid && rob_younger_than(fpu0_s0_rob_idx, checkpoint_rob_idx)) fpu0_s0_valid = 1'b0;
                    if (fpu1_s0_valid && rob_younger_than(fpu1_s0_rob_idx, checkpoint_rob_idx)) fpu1_s0_valid = 1'b0;
                    if (fpu0_s1_valid && rob_younger_than(fpu0_s1_rob_idx, checkpoint_rob_idx)) fpu0_s1_valid = 1'b0;
                    if (fpu1_s1_valid && rob_younger_than(fpu1_s1_rob_idx, checkpoint_rob_idx)) fpu1_s1_valid = 1'b0;
                    if (fpu0_s2_valid && rob_younger_than(fpu0_s2_rob_idx, checkpoint_rob_idx)) fpu0_s2_valid = 1'b0;
                    if (fpu1_s2_valid && rob_younger_than(fpu1_s2_rob_idx, checkpoint_rob_idx)) fpu1_s2_valid = 1'b0;
                    if (fpu0_s3_valid && rob_younger_than(fpu0_s3_rob_idx, checkpoint_rob_idx)) fpu0_s3_valid = 1'b0;
                    if (fpu1_s3_valid && rob_younger_than(fpu1_s3_rob_idx, checkpoint_rob_idx)) fpu1_s3_valid = 1'b0;
                    if (lsu0_s0_valid && rob_younger_than(lsu0_s0_rob_idx, checkpoint_rob_idx)) begin
                        lsq_inflight[lsu0_s0_lsq_idx] = 1'b0;
                        lsu0_s0_valid = 1'b0;
                    end
                    if (lsu1_s0_valid && rob_younger_than(lsu1_s0_rob_idx, checkpoint_rob_idx)) begin
                        lsq_inflight[lsu1_s0_lsq_idx] = 1'b0;
                        lsu1_s0_valid = 1'b0;
                    end
                    if (lsu0_s1_valid && rob_younger_than(lsu0_s1_rob_idx, checkpoint_rob_idx)) begin
                        lsq_inflight[lsu0_s1_lsq_idx] = 1'b0;
                        lsu0_s1_valid = 1'b0;
                    end
                    if (lsu1_s1_valid && rob_younger_than(lsu1_s1_rob_idx, checkpoint_rob_idx)) begin
                        lsq_inflight[lsu1_s1_lsq_idx] = 1'b0;
                        lsu1_s1_valid = 1'b0;
                    end

                    checkpoint_valid = 1'b0;
                    fetch.pc = correct_pc;
                end else if (!mispredict && checkpoint_valid &&
                             rob_valid[checkpoint_rob_idx] &&
                             rob_ready[checkpoint_rob_idx]) begin
                    checkpoint_valid = 1'b0;
                end

                if (rob_count != 0 && rob_valid[rob_head] && rob_ready[rob_head]) begin
                    if (rob_is_store[rob_head]) begin
                        addr_idx = rob_store_addr[rob_head][31:0];
                        if (addr_idx + 7 < MEM_SIZE) begin
                            memory.bytes[addr_idx + 0] = rob_store_data[rob_head][7:0];
                            memory.bytes[addr_idx + 1] = rob_store_data[rob_head][15:8];
                            memory.bytes[addr_idx + 2] = rob_store_data[rob_head][23:16];
                            memory.bytes[addr_idx + 3] = rob_store_data[rob_head][31:24];
                            memory.bytes[addr_idx + 4] = rob_store_data[rob_head][39:32];
                            memory.bytes[addr_idx + 5] = rob_store_data[rob_head][47:40];
                            memory.bytes[addr_idx + 6] = rob_store_data[rob_head][55:48];
                            memory.bytes[addr_idx + 7] = rob_store_data[rob_head][63:56];
                        end
                    end

                    if (rob_has_dest[rob_head]) begin
                        reg_file.registers[rob_arch_dest[rob_head]] = rob_value[rob_head];
                        if (rob_old_phys[rob_head] >= ARCH_REGS) begin
                            free_list[free_count] = rob_old_phys[rob_head];
                            free_count = free_count + 1;
                            if (checkpoint_valid) begin
                                checkpoint_free_list[checkpoint_free_count] = rob_old_phys[rob_head];
                                checkpoint_free_count = checkpoint_free_count + 1;
                            end
                        end
                    end

                    if (rob_is_halt[rob_head])
                        hlt <= 1'b1;

                    rob_valid[rob_head] = 1'b0;
                    rob_head = rob_inc(rob_head);
                    rob_count = rob_count - 1;
                end

                alu0_s1_valid = alu0_s0_valid;
                alu0_s1_opcode = alu0_s0_opcode;
                alu0_s1_a = alu0_s0_a;
                alu0_s1_b = alu0_s0_b;
                alu0_s1_c = alu0_s0_c;
                alu0_s1_pc = alu0_s0_pc;
                alu0_s1_is_branch = alu0_s0_is_branch;
                alu0_s1_has_dest = alu0_s0_has_dest;
                alu0_s1_dest_phys = alu0_s0_dest_phys;
                alu0_s1_rob_idx = alu0_s0_rob_idx;
                alu0_s1_pred_taken = alu0_s0_pred_taken;
                alu0_s1_pred_target = alu0_s0_pred_target;
                if (alu0_s0_opcode == OP_MOV_LIT)
                    alu0_s1_result = {alu0_s0_a[63:12], alu0_s0_b[11:0]};
                else
                    alu0_s1_result = alu0_pipe_result;

                alu1_s1_valid = alu1_s0_valid;
                alu1_s1_opcode = alu1_s0_opcode;
                alu1_s1_a = alu1_s0_a;
                alu1_s1_b = alu1_s0_b;
                alu1_s1_c = alu1_s0_c;
                alu1_s1_pc = alu1_s0_pc;
                alu1_s1_is_branch = alu1_s0_is_branch;
                alu1_s1_has_dest = alu1_s0_has_dest;
                alu1_s1_dest_phys = alu1_s0_dest_phys;
                alu1_s1_rob_idx = alu1_s0_rob_idx;
                alu1_s1_pred_taken = alu1_s0_pred_taken;
                alu1_s1_pred_target = alu1_s0_pred_target;
                if (alu1_s0_opcode == OP_MOV_LIT)
                    alu1_s1_result = {alu1_s0_a[63:12], alu1_s0_b[11:0]};
                else
                    alu1_s1_result = alu1_pipe_result;

                fpu0_s3_valid = fpu0_s2_valid;
                fpu0_s3_result = fpu0_s2_result;
                fpu0_s3_has_dest = fpu0_s2_has_dest;
                fpu0_s3_dest_phys = fpu0_s2_dest_phys;
                fpu0_s3_rob_idx = fpu0_s2_rob_idx;

                fpu1_s3_valid = fpu1_s2_valid;
                fpu1_s3_result = fpu1_s2_result;
                fpu1_s3_has_dest = fpu1_s2_has_dest;
                fpu1_s3_dest_phys = fpu1_s2_dest_phys;
                fpu1_s3_rob_idx = fpu1_s2_rob_idx;

                fpu0_s2_valid = fpu0_s1_valid;
                fpu0_s2_result = fpu0_s1_result;
                fpu0_s2_has_dest = fpu0_s1_has_dest;
                fpu0_s2_dest_phys = fpu0_s1_dest_phys;
                fpu0_s2_rob_idx = fpu0_s1_rob_idx;

                fpu1_s2_valid = fpu1_s1_valid;
                fpu1_s2_result = fpu1_s1_result;
                fpu1_s2_has_dest = fpu1_s1_has_dest;
                fpu1_s2_dest_phys = fpu1_s1_dest_phys;
                fpu1_s2_rob_idx = fpu1_s1_rob_idx;

                fpu0_s1_valid = fpu0_s0_valid;
                fpu0_s1_result = fpu0_pipe_result;
                fpu0_s1_has_dest = fpu0_s0_has_dest;
                fpu0_s1_dest_phys = fpu0_s0_dest_phys;
                fpu0_s1_rob_idx = fpu0_s0_rob_idx;

                fpu1_s1_valid = fpu1_s0_valid;
                fpu1_s1_result = fpu1_pipe_result;
                fpu1_s1_has_dest = fpu1_s0_has_dest;
                fpu1_s1_dest_phys = fpu1_s0_dest_phys;
                fpu1_s1_rob_idx = fpu1_s0_rob_idx;

                lsu0_s1_valid = lsu0_s0_valid;
                lsu0_s1_is_addr = lsu0_s0_is_addr;
                lsu0_s1_lsq_idx = lsu0_s0_lsq_idx;
                lsu0_s1_rob_idx = lsu0_s0_rob_idx;
                if (lsu0_s0_is_addr) begin
                    lsu0_s1_addr = lsu0_s0_base + lsu0_s0_imm;
                    lsu0_s1_result = 64'd0;
                end else begin
                    lsu0_s1_addr = lsu0_s0_addr;
                    scan_store_forward(lsu0_s0_addr, lsu0_s0_rob_idx, forward_found, forward_blocked, forwarded_value);
                    if (forward_found)
                        lsu0_s1_result = forwarded_value;
                    else
                        lsu0_s1_result = read_mem64_direct(lsu0_s0_addr);
                end

                lsu1_s1_valid = lsu1_s0_valid;
                lsu1_s1_is_addr = lsu1_s0_is_addr;
                lsu1_s1_lsq_idx = lsu1_s0_lsq_idx;
                lsu1_s1_rob_idx = lsu1_s0_rob_idx;
                if (lsu1_s0_is_addr) begin
                    lsu1_s1_addr = lsu1_s0_base + lsu1_s0_imm;
                    lsu1_s1_result = 64'd0;
                end else begin
                    lsu1_s1_addr = lsu1_s0_addr;
                    scan_store_forward(lsu1_s0_addr, lsu1_s0_rob_idx, forward_found, forward_blocked, forwarded_value);
                    if (forward_found)
                        lsu1_s1_result = forwarded_value;
                    else
                        lsu1_s1_result = read_mem64_direct(lsu1_s0_addr);
                end

                alu0_s0_valid = 1'b0;
                alu1_s0_valid = 1'b0;
                fpu0_s0_valid = 1'b0;
                fpu1_s0_valid = 1'b0;
                lsu0_s0_valid = 1'b0;
                lsu1_s0_valid = 1'b0;

                alu_pick0 = -1;
                alu_pick1 = -1;
                fpu_pick0 = -1;
                fpu_pick1 = -1;
                ls_pick0 = -1;
                ls_pick1 = -1;

                if (!mispredict) begin
                    for (i = 0; i < RS_SIZE; i = i + 1) begin
                        if (rs_valid[i] &&
                            (!rs_use0[i] || !rs_src0_wait[i]) &&
                            (!rs_use1[i] || !rs_src1_wait[i]) &&
                            (!rs_use2[i] || !rs_src2_wait[i])) begin
                            if (rs_is_fpu[i]) begin
                                if ((fpu_pick0 == -1) || (rob_distance(rs_rob_idx[i]) < rob_distance(rs_rob_idx[fpu_pick0])))
                                    fpu_pick0 = i;
                            end else begin
                                if ((alu_pick0 == -1) || (rob_distance(rs_rob_idx[i]) < rob_distance(rs_rob_idx[alu_pick0])))
                                    alu_pick0 = i;
                            end
                        end
                    end

                    if (alu_pick0 != -1) begin
                        for (i = 0; i < RS_SIZE; i = i + 1) begin
                            if ((i != alu_pick0) && rs_valid[i] && !rs_is_fpu[i] &&
                                (!rs_use0[i] || !rs_src0_wait[i]) &&
                                (!rs_use1[i] || !rs_src1_wait[i]) &&
                                (!rs_use2[i] || !rs_src2_wait[i])) begin
                                if ((alu_pick1 == -1) || (rob_distance(rs_rob_idx[i]) < rob_distance(rs_rob_idx[alu_pick1])))
                                    alu_pick1 = i;
                            end
                        end
                    end

                    if (fpu_pick0 != -1) begin
                        for (i = 0; i < RS_SIZE; i = i + 1) begin
                            if ((i != fpu_pick0) && rs_valid[i] && rs_is_fpu[i] &&
                                (!rs_use0[i] || !rs_src0_wait[i]) &&
                                (!rs_use1[i] || !rs_src1_wait[i]) &&
                                (!rs_use2[i] || !rs_src2_wait[i])) begin
                                if ((fpu_pick1 == -1) || (rob_distance(rs_rob_idx[i]) < rob_distance(rs_rob_idx[fpu_pick1])))
                                    fpu_pick1 = i;
                            end
                        end
                    end

                    for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                        if (lsq_valid[i] && !lsq_inflight[i] &&
                            !(lsu0_s1_valid && (lsu0_s1_lsq_idx == i[2:0])) &&
                            !(lsu1_s1_valid && (lsu1_s1_lsq_idx == i[2:0])) &&
                            lsq_is_load[i] && lsq_addr_ready[i]) begin
                            scan_store_forward(lsq_addr[i], lsq_rob_idx[i], forward_found, forward_blocked, forwarded_value);
                            if (!forward_blocked) begin
                                if ((ls_pick0 == -1) || (rob_distance(lsq_rob_idx[i]) < rob_distance(lsq_rob_idx[ls_pick0])))
                                    ls_pick0 = i;
                            end
                        end else if (lsq_valid[i] && !lsq_inflight[i] &&
                                     !(lsu0_s1_valid && (lsu0_s1_lsq_idx == i[2:0])) &&
                                     !(lsu1_s1_valid && (lsu1_s1_lsq_idx == i[2:0])) &&
                                     !lsq_addr_ready[i] && !lsq_base_wait[i]) begin
                            if ((ls_pick0 == -1) || (rob_distance(lsq_rob_idx[i]) < rob_distance(lsq_rob_idx[ls_pick0])))
                                ls_pick0 = i;
                        end
                    end

                    if (ls_pick0 != -1) begin
                        for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                            if (i != ls_pick0) begin
                                if (lsq_valid[i] && !lsq_inflight[i] &&
                                    !(lsu0_s1_valid && (lsu0_s1_lsq_idx == i[2:0])) &&
                                    !(lsu1_s1_valid && (lsu1_s1_lsq_idx == i[2:0])) &&
                                    lsq_is_load[i] && lsq_addr_ready[i]) begin
                                    scan_store_forward(lsq_addr[i], lsq_rob_idx[i], forward_found, forward_blocked, forwarded_value);
                                    if (!forward_blocked) begin
                                        if ((ls_pick1 == -1) || (rob_distance(lsq_rob_idx[i]) < rob_distance(lsq_rob_idx[ls_pick1])))
                                            ls_pick1 = i;
                                    end
                                end else if (lsq_valid[i] && !lsq_inflight[i] &&
                                             !(lsu0_s1_valid && (lsu0_s1_lsq_idx == i[2:0])) &&
                                             !(lsu1_s1_valid && (lsu1_s1_lsq_idx == i[2:0])) &&
                                             !lsq_addr_ready[i] && !lsq_base_wait[i]) begin
                                    if ((ls_pick1 == -1) || (rob_distance(lsq_rob_idx[i]) < rob_distance(lsq_rob_idx[ls_pick1])))
                                        ls_pick1 = i;
                                end
                            end
                        end
                    end

                    if (alu_pick0 != -1) begin
                        alu0_s0_valid = 1'b1;
                        alu0_s0_opcode = rs_opcode[alu_pick0];
                        alu0_s0_a = rs_src0_val[alu_pick0];
                        alu0_s0_b = rs_src1_val[alu_pick0];
                        alu0_s0_c = rs_src2_val[alu_pick0];
                        alu0_s0_pc = rs_pc[alu_pick0];
                        alu0_s0_is_branch = rs_is_branch[alu_pick0];
                        alu0_s0_has_dest = rs_has_dest[alu_pick0];
                        alu0_s0_dest_phys = rs_dest_phys[alu_pick0];
                        alu0_s0_rob_idx = rs_rob_idx[alu_pick0];
                        alu0_s0_pred_taken = rs_pred_taken[alu_pick0];
                        alu0_s0_pred_target = rs_pred_target[alu_pick0];
                        rs_valid[alu_pick0] = 1'b0;
                    end

                    if (alu_pick1 != -1) begin
                        alu1_s0_valid = 1'b1;
                        alu1_s0_opcode = rs_opcode[alu_pick1];
                        alu1_s0_a = rs_src0_val[alu_pick1];
                        alu1_s0_b = rs_src1_val[alu_pick1];
                        alu1_s0_c = rs_src2_val[alu_pick1];
                        alu1_s0_pc = rs_pc[alu_pick1];
                        alu1_s0_is_branch = rs_is_branch[alu_pick1];
                        alu1_s0_has_dest = rs_has_dest[alu_pick1];
                        alu1_s0_dest_phys = rs_dest_phys[alu_pick1];
                        alu1_s0_rob_idx = rs_rob_idx[alu_pick1];
                        alu1_s0_pred_taken = rs_pred_taken[alu_pick1];
                        alu1_s0_pred_target = rs_pred_target[alu_pick1];
                        rs_valid[alu_pick1] = 1'b0;
                    end

                    if (fpu_pick0 != -1) begin
                        fpu0_s0_valid = 1'b1;
                        fpu0_s0_opcode = rs_opcode[fpu_pick0];
                        fpu0_s0_a = rs_src0_val[fpu_pick0];
                        fpu0_s0_b = rs_src1_val[fpu_pick0];
                        fpu0_s0_has_dest = rs_has_dest[fpu_pick0];
                        fpu0_s0_dest_phys = rs_dest_phys[fpu_pick0];
                        fpu0_s0_rob_idx = rs_rob_idx[fpu_pick0];
                        rs_valid[fpu_pick0] = 1'b0;
                    end

                    if (fpu_pick1 != -1) begin
                        fpu1_s0_valid = 1'b1;
                        fpu1_s0_opcode = rs_opcode[fpu_pick1];
                        fpu1_s0_a = rs_src0_val[fpu_pick1];
                        fpu1_s0_b = rs_src1_val[fpu_pick1];
                        fpu1_s0_has_dest = rs_has_dest[fpu_pick1];
                        fpu1_s0_dest_phys = rs_dest_phys[fpu_pick1];
                        fpu1_s0_rob_idx = rs_rob_idx[fpu_pick1];
                        rs_valid[fpu_pick1] = 1'b0;
                    end

                    if (ls_pick0 != -1) begin
                        lsu0_s0_valid = 1'b1;
                        lsq_inflight[ls_pick0] = 1'b1;
                        lsu0_s0_lsq_idx = ls_pick0[2:0];
                        lsu0_s0_rob_idx = lsq_rob_idx[ls_pick0];
                        if (!lsq_addr_ready[ls_pick0]) begin
                            lsu0_s0_is_addr = 1'b1;
                            lsu0_s0_base = lsq_base_val[ls_pick0];
                            lsu0_s0_imm = lsq_imm[ls_pick0];
                            lsu0_s0_addr = 64'd0;
                        end else begin
                            lsu0_s0_is_addr = 1'b0;
                            lsu0_s0_base = 64'd0;
                            lsu0_s0_imm = 64'd0;
                            lsu0_s0_addr = lsq_addr[ls_pick0];
                        end
                    end

                    if (ls_pick1 != -1) begin
                        lsu1_s0_valid = 1'b1;
                        lsq_inflight[ls_pick1] = 1'b1;
                        lsu1_s0_lsq_idx = ls_pick1[2:0];
                        lsu1_s0_rob_idx = lsq_rob_idx[ls_pick1];
                        if (!lsq_addr_ready[ls_pick1]) begin
                            lsu1_s0_is_addr = 1'b1;
                            lsu1_s0_base = lsq_base_val[ls_pick1];
                            lsu1_s0_imm = lsq_imm[ls_pick1];
                            lsu1_s0_addr = 64'd0;
                        end else begin
                            lsu1_s0_is_addr = 1'b0;
                            lsu1_s0_base = 64'd0;
                            lsu1_s0_imm = 64'd0;
                            lsu1_s0_addr = lsq_addr[ls_pick1];
                        end
                    end

                    fetch_pc_next = fetch.pc;
                    fetch_stop = 1'b0;
                    halt_inflight = 1'b0;
                    for (i = 0; i < ROB_SIZE; i = i + 1) begin
                        if (rob_valid[i] && rob_is_halt[i])
                            halt_inflight = 1'b1;
                    end
                    if (halt_inflight)
                        fetch_stop = 1'b1;

                    for (slot = 0; slot < 2; slot = slot + 1) begin
                        if (!fetch_stop) begin
                            slot_inst = read_inst32(fetch.pc + (slot * 64'd4));
                            slot_opcode = slot_inst[31:27];
                            slot_rd = slot_inst[26:22];
                            slot_rs = slot_inst[21:17];
                            slot_rt = slot_inst[16:12];
                            slot_lit12 = slot_inst[11:0];
                            slot_lit_zext = {52'd0, slot_lit12};
                            slot_lit_sext = signext12(slot_lit12);
                            slot_pred_taken = 1'b0;
                            slot_pred_target = fetch.pc + ((slot + 1) * 64'd4);

                            if (rob_count == ROB_SIZE) begin
                                fetch_stop = 1'b1;
                            end else begin
                                need_dest_phys = has_dest_opcode(slot_opcode, slot_lit12);
                                if (need_dest_phys && (free_count == 0)) begin
                                    fetch_stop = 1'b1;
                                end else begin
                                    if (is_load_opcode(slot_opcode) || is_store_opcode(slot_opcode)) begin
                                        lsq_idx = -1;
                                        for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                                            if (!lsq_valid[i] && (lsq_idx == -1))
                                                lsq_idx = i;
                                        end
                                        if (lsq_idx == -1)
                                            fetch_stop = 1'b1;
                                    end else begin
                                        rs_idx = -1;
                                        for (i = 0; i < RS_SIZE; i = i + 1) begin
                                            if (!rs_valid[i] && (rs_idx == -1))
                                                rs_idx = i;
                                        end
                                        if (rs_idx == -1)
                                            fetch_stop = 1'b1;
                                    end

                                    if (is_branch_opcode(slot_opcode) && checkpoint_valid)
                                        fetch_stop = 1'b1;
                                end
                            end

                            if (!fetch_stop) begin
                                rob_idx = rob_tail;
                                rob_tail = rob_inc(rob_tail);
                                rob_count = rob_count + 1;

                                rob_valid[rob_idx] = 1'b1;
                                rob_ready[rob_idx] = is_halt_opcode(slot_opcode, slot_lit12) ? 1'b1 : 1'b0;
                                rob_opcode[rob_idx] = slot_opcode;
                                rob_pc[rob_idx] = fetch.pc + (slot * 64'd4);
                                rob_has_dest[rob_idx] = need_dest_phys;
                                rob_arch_dest[rob_idx] = slot_rd;
                                rob_value[rob_idx] = 64'd0;
                                rob_is_store[rob_idx] = is_store_opcode(slot_opcode) || (slot_opcode == OP_CALL);
                                rob_store_addr[rob_idx] = 64'd0;
                                rob_store_data[rob_idx] = 64'd0;
                                rob_store_addr_ready[rob_idx] = 1'b0;
                                rob_store_data_ready[rob_idx] = 1'b0;
                                rob_is_branch[rob_idx] = is_branch_opcode(slot_opcode);
                                rob_is_halt[rob_idx] = is_halt_opcode(slot_opcode, slot_lit12);

                                if (need_dest_phys) begin
                                    new_dest_phys = free_list[free_count - 1];
                                    free_count = free_count - 1;
                                    old_dest_phys = rat[slot_rd];
                                    rat[slot_rd] = new_dest_phys;
                                    phys_ready[new_dest_phys] = 1'b0;
                                    phys_value[new_dest_phys] = 64'd0;
                                    rob_dest_phys[rob_idx] = new_dest_phys;
                                    rob_old_phys[rob_idx] = old_dest_phys;
                                end else begin
                                    rob_dest_phys[rob_idx] = 6'd0;
                                    rob_old_phys[rob_idx] = 6'd0;
                                end

                                if (slot_opcode == OP_CALL)
                                    capture_operand(5'd31, src_wait1, src_tag1, src_val1);

                                if (is_branch_opcode(slot_opcode)) begin
                                    predict_instruction(fetch.pc + (slot * 64'd4), slot_opcode, slot_lit12, slot_pred_taken, slot_pred_target);
                                    rob_pred_taken[rob_idx] = slot_pred_taken;
                                    rob_pred_target[rob_idx] = slot_pred_target;
                                    checkpoint_valid = 1'b1;
                                    checkpoint_rob_idx = rob_idx;
                                    checkpoint_free_count = free_count;
                                    for (i = 0; i < ARCH_REGS; i = i + 1)
                                        checkpoint_rat[i] = rat[i];
                                    for (i = 0; i < FREE_COUNT_MAX; i = i + 1)
                                        checkpoint_free_list[i] = free_list[i];
                                end else begin
                                    rob_pred_taken[rob_idx] = 1'b0;
                                    rob_pred_target[rob_idx] = 64'd0;
                                end

                                if (is_load_opcode(slot_opcode) || is_store_opcode(slot_opcode)) begin
                                    lsq_valid[lsq_idx] = 1'b1;
                                    lsq_is_load[lsq_idx] = is_load_opcode(slot_opcode);
                                    lsq_imm[lsq_idx] = slot_lit_sext;
                                    lsq_addr_ready[lsq_idx] = 1'b0;
                                    lsq_addr[lsq_idx] = 64'd0;
                                    lsq_has_dest[lsq_idx] = is_load_opcode(slot_opcode);
                                    lsq_dest_phys[lsq_idx] = need_dest_phys ? new_dest_phys : 6'd0;
                                    lsq_rob_idx[lsq_idx] = rob_idx[3:0];

                                    if (is_load_opcode(slot_opcode)) begin
                                        capture_operand(slot_rs, src_wait, src_tag, src_val);
                                        lsq_base_wait[lsq_idx] = src_wait;
                                        lsq_base_tag[lsq_idx] = src_tag;
                                        lsq_base_val[lsq_idx] = src_val;
                                        lsq_store_wait[lsq_idx] = 1'b0;
                                        lsq_store_tag[lsq_idx] = 6'd0;
                                        lsq_store_val[lsq_idx] = 64'd0;
                                    end else begin
                                        capture_operand(slot_rd, src_wait, src_tag, src_val);
                                        capture_operand(slot_rs, src_wait1, src_tag1, src_val1);
                                        lsq_base_wait[lsq_idx] = src_wait;
                                        lsq_base_tag[lsq_idx] = src_tag;
                                        lsq_base_val[lsq_idx] = src_val;
                                        lsq_store_wait[lsq_idx] = src_wait1;
                                        lsq_store_tag[lsq_idx] = src_tag1;
                                        lsq_store_val[lsq_idx] = src_val1;
                                        if (!src_wait1) begin
                                            rob_store_data[rob_idx] = src_val1;
                                            rob_store_data_ready[rob_idx] = 1'b1;
                                        end
                                    end
                                end else if (!is_halt_opcode(slot_opcode, slot_lit12)) begin
                                    rs_valid[rs_idx] = 1'b1;
                                    rs_opcode[rs_idx] = slot_opcode;
                                    rs_is_fpu[rs_idx] = is_fpu_opcode(slot_opcode);
                                    rs_is_branch[rs_idx] = is_branch_opcode(slot_opcode);
                                    rs_has_dest[rs_idx] = need_dest_phys;
                                    rs_dest_phys[rs_idx] = need_dest_phys ? new_dest_phys : 6'd0;
                                    rs_rob_idx[rs_idx] = rob_idx[3:0];
                                    rs_pc[rs_idx] = fetch.pc + (slot * 64'd4);
                                    rs_pred_taken[rs_idx] = slot_pred_taken;
                                    rs_pred_target[rs_idx] = slot_pred_target;
                                    rs_use0[rs_idx] = 1'b0;
                                    rs_use1[rs_idx] = 1'b0;
                                    rs_use2[rs_idx] = 1'b0;
                                    rs_src0_wait[rs_idx] = 1'b0;
                                    rs_src1_wait[rs_idx] = 1'b0;
                                    rs_src2_wait[rs_idx] = 1'b0;
                                    rs_src0_tag[rs_idx] = 6'd0;
                                    rs_src1_tag[rs_idx] = 6'd0;
                                    rs_src2_tag[rs_idx] = 6'd0;
                                    rs_src0_val[rs_idx] = 64'd0;
                                    rs_src1_val[rs_idx] = 64'd0;
                                    rs_src2_val[rs_idx] = 64'd0;

                                    case (slot_opcode)
                                        OP_AND, OP_OR, OP_XOR, OP_SHFTR, OP_SHFTL,
                                        OP_ADD, OP_SUB, OP_MUL, OP_DIV,
                                        OP_ADDF, OP_SUBF, OP_MULF, OP_DIVF: begin
                                            capture_operand(slot_rs, src_wait, src_tag, src_val);
                                            capture_operand(slot_rt, src_wait1, src_tag1, src_val1);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_use1[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                            rs_src1_wait[rs_idx] = src_wait1;
                                            rs_src1_tag[rs_idx] = src_tag1;
                                            rs_src1_val[rs_idx] = src_val1;
                                        end
                                        OP_NOT, OP_MOV_REG: begin
                                            capture_operand(slot_rs, src_wait, src_tag, src_val);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                        end
                                        OP_MOV_LIT, OP_ADDI, OP_SUBI, OP_SHFTRI, OP_SHFTLI: begin
                                            capture_operand_from_phys(old_dest_phys, src_wait, src_tag, src_val);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_use1[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                            rs_src1_wait[rs_idx] = 1'b0;
                                            rs_src1_tag[rs_idx] = 6'd0;
                                            rs_src1_val[rs_idx] = slot_lit_zext;
                                        end
                                        OP_BR: begin
                                            capture_operand(slot_rd, src_wait, src_tag, src_val);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                        end
                                        OP_BRR_REG: begin
                                            capture_operand(slot_rd, src_wait, src_tag, src_val);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                        end
                                        OP_BRR_LIT: begin
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = 1'b0;
                                            rs_src0_val[rs_idx] = slot_lit_sext;
                                        end
                                        OP_BRNZ: begin
                                            capture_operand(slot_rd, src_wait, src_tag, src_val);
                                            capture_operand(slot_rs, src_wait1, src_tag1, src_val1);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_use1[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                            rs_src1_wait[rs_idx] = src_wait1;
                                            rs_src1_tag[rs_idx] = src_tag1;
                                            rs_src1_val[rs_idx] = src_val1;
                                        end
                                        OP_BRGT: begin
                                            capture_operand(slot_rd, src_wait, src_tag, src_val);
                                            capture_operand(slot_rs, src_wait1, src_tag1, src_val1);
                                            capture_operand(slot_rt, src_wait2, src_tag2, src_val2);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_use1[rs_idx] = 1'b1;
                                            rs_use2[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                            rs_src1_wait[rs_idx] = src_wait1;
                                            rs_src1_tag[rs_idx] = src_tag1;
                                            rs_src1_val[rs_idx] = src_val1;
                                            rs_src2_wait[rs_idx] = src_wait2;
                                            rs_src2_tag[rs_idx] = src_tag2;
                                            rs_src2_val[rs_idx] = src_val2;
                                        end
                                        OP_CALL: begin
                                            capture_operand(slot_rd, src_wait, src_tag, src_val);
                                            capture_operand(5'd31, src_wait1, src_tag1, src_val1);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_use1[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                            rs_src1_wait[rs_idx] = src_wait1;
                                            rs_src1_tag[rs_idx] = src_tag1;
                                            rs_src1_val[rs_idx] = src_val1;
                                        end
                                        OP_RETURN: begin
                                            capture_operand(5'd31, src_wait, src_tag, src_val);
                                            rs_use0[rs_idx] = 1'b1;
                                            rs_src0_wait[rs_idx] = src_wait;
                                            rs_src0_tag[rs_idx] = src_tag;
                                            rs_src0_val[rs_idx] = src_val;
                                        end
                                        default: begin
                                        end
                                    endcase
                                end

                                if (slot_opcode == OP_MOV_STORE)
                                    fetch_pc_next = fetch.pc + ((slot + 1) * 64'd4);
                                else if (is_branch_opcode(slot_opcode)) begin
                                    if (slot_pred_taken)
                                        fetch_pc_next = slot_pred_target;
                                    else
                                        fetch_pc_next = fetch.pc + ((slot + 1) * 64'd4);
                                    if (slot_pred_taken)
                                        fetch_stop = 1'b1;
                                end else if (is_halt_opcode(slot_opcode, slot_lit12)) begin
                                    fetch_pc_next = fetch.pc + ((slot + 1) * 64'd4);
                                    fetch_stop = 1'b1;
                                end else begin
                                    fetch_pc_next = fetch.pc + ((slot + 1) * 64'd4);
                                end
                            end
                        end
                    end

                    fetch.pc = fetch_pc_next;
                end
            end
        end
    end
endmodule
