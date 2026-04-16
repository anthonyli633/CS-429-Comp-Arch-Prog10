`timescale 1ns/1ps

module tb_comprehensive;
    reg clk;
    reg reset;
    integer fails;
    integer cycles;

    localparam MEM_SIZE     = 512 * 1024;
    localparam RET_SLOT     = MEM_SIZE - 8;

    localparam OP_AND       = 5'h00;
    localparam OP_BRR_LIT   = 5'h0a;
    localparam OP_BRNZ      = 5'h0b;
    localparam OP_CALL      = 5'h0c;
    localparam OP_RETURN    = 5'h0d;
    localparam OP_PRIV      = 5'h0f;
    localparam OP_MOV_LOAD  = 5'h10;
    localparam OP_MOV_LIT   = 5'h12;
    localparam OP_MOV_STORE = 5'h13;
    localparam OP_ADDI      = 5'h19;
    localparam OP_SUBI      = 5'h1b;

    wire hlt;

    tinker_core dut (
        .clk(clk),
        .reset(reset),
        .hlt(hlt)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function [31:0] enc_rrr;
        input [4:0] opcode, rd, rs, rt;
        begin
            enc_rrr = {opcode, rd, rs, rt, 12'd0};
        end
    endfunction

    function [31:0] enc_rr;
        input [4:0] opcode, rd, rs;
        begin
            enc_rr = {opcode, rd, rs, 5'd0, 12'd0};
        end
    endfunction

    function [31:0] enc_r;
        input [4:0] opcode, rd;
        begin
            enc_r = {opcode, rd, 5'd0, 5'd0, 12'd0};
        end
    endfunction

    function [31:0] enc_rd_lit;
        input [4:0] opcode, rd;
        input [11:0] lit;
        begin
            enc_rd_lit = {opcode, rd, 5'd0, 5'd0, lit};
        end
    endfunction

    function [31:0] enc_lit;
        input [4:0] opcode;
        input [11:0] lit;
        begin
            enc_lit = {opcode, 5'd0, 5'd0, 5'd0, lit};
        end
    endfunction

    function [31:0] enc_mov_load;
        input [4:0] rd, rs;
        input [11:0] lit;
        begin
            enc_mov_load = {OP_MOV_LOAD, rd, rs, 5'd0, lit};
        end
    endfunction

    function [31:0] enc_mov_store;
        input [4:0] rd, rs;
        input [11:0] lit;
        begin
            enc_mov_store = {OP_MOV_STORE, rd, rs, 5'd0, lit};
        end
    endfunction

    task write_inst;
        input [63:0] addr;
        input [31:0] inst;
        begin
            dut.memory.bytes[addr+0] = inst[7:0];
            dut.memory.bytes[addr+1] = inst[15:8];
            dut.memory.bytes[addr+2] = inst[23:16];
            dut.memory.bytes[addr+3] = inst[31:24];
        end
    endtask

    task write_mem64;
        input [63:0] addr;
        input [63:0] data;
        begin
            dut.memory.bytes[addr+0] = data[7:0];
            dut.memory.bytes[addr+1] = data[15:8];
            dut.memory.bytes[addr+2] = data[23:16];
            dut.memory.bytes[addr+3] = data[31:24];
            dut.memory.bytes[addr+4] = data[39:32];
            dut.memory.bytes[addr+5] = data[47:40];
            dut.memory.bytes[addr+6] = data[55:48];
            dut.memory.bytes[addr+7] = data[63:56];
        end
    endtask

    function [63:0] read_mem64;
        input [63:0] addr;
        begin
            read_mem64 = {
                dut.memory.bytes[addr+7],
                dut.memory.bytes[addr+6],
                dut.memory.bytes[addr+5],
                dut.memory.bytes[addr+4],
                dut.memory.bytes[addr+3],
                dut.memory.bytes[addr+2],
                dut.memory.bytes[addr+1],
                dut.memory.bytes[addr+0]
            };
        end
    endfunction

    task clear_program;
        integer i;
        begin
            for (i = 16'h2000; i < 16'h2080; i = i + 1)
                dut.memory.bytes[i] = 8'h00;
        end
    endtask

    task do_reset;
        begin
            reset = 1'b1;
            repeat (2) @(posedge clk);
            #1 reset = 1'b0;
            #1;
        end
    endtask

    task run_until_halt;
        input integer max_cycles;
        begin
            cycles = 0;
            while (!hlt && cycles < max_cycles) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            #1;
        end
    endtask

    task expect64;
        input [255:0] name;
        input [63:0] got, exp;
        begin
            if (got !== exp) begin
                fails = fails + 1;
                $display("FAIL %-24s got=%h expected=%h", name, got, exp);
            end else begin
                $display("PASS %-24s %h", name, got);
            end
        end
    endtask

    task expect_true;
        input [255:0] name;
        input cond;
        begin
            if (!cond) begin
                fails = fails + 1;
                $display("FAIL %-24s", name);
            end else begin
                $display("PASS %-24s", name);
            end
        end
    endtask

    initial begin
        fails = 0;
        reset = 1'b0;
        cycles = 0;

        $dumpfile("sim/comprehensive.vcd");
        $dumpvars(0, tb_comprehensive);

        // Smoke test for integer datapath and dual-issue-ish progress.
        clear_program();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'd5));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd2, 12'd7));
        write_inst(64'h2008, enc_rrr(OP_AND, 5'd4, 5'd1, 5'd2));
        write_inst(64'h200C, enc_rd_lit(OP_SUBI, 5'd2, 12'd2));
        write_inst(64'h2010, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(80);
        expect_true("smoke halt", hlt == 1'b1);
        expect64("addi r1", dut.reg_file.registers[1], 64'd5);
        expect64("subi r2", dut.reg_file.registers[2], 64'd5);
        expect64("and r4", dut.reg_file.registers[4], 64'd5);
        expect_true("pipeline cadence", cycles <= 12);

        // MOV_LIT keeps the upper bits from rd.
        clear_program();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd5, 12'hABC));
        write_inst(64'h2004, enc_rd_lit(OP_MOV_LIT, 5'd5, 12'h123));
        write_inst(64'h2008, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(60);
        expect64("mov_lit low bits", dut.reg_file.registers[5], 64'h0000_0000_0000_0123);

        // Store/load path and store-to-load visibility.
        clear_program();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'h100));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd2, 12'd42));
        write_inst(64'h2008, enc_mov_store(5'd1, 5'd2, 12'd0));
        write_inst(64'h200C, enc_mov_load(5'd3, 5'd1, 12'd0));
        write_inst(64'h2010, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(100);
        expect64("store commit", read_mem64(64'h100), 64'd42);
        expect64("load after store", dut.reg_file.registers[3], 64'd42);

        // Branch recovery should discard the wrong-path ADDI.
        clear_program();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'd1));
        write_inst(64'h2004, enc_rr(OP_BRNZ, 5'd6, 5'd1));
        write_inst(64'h2008, enc_rd_lit(OP_ADDI, 5'd2, 12'd99));
        write_inst(64'h200C, enc_rd_lit(OP_ADDI, 5'd2, 12'd7));
        write_inst(64'h2010, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[6] = 64'h200C;
        run_until_halt(100);
        expect64("branch flush", dut.reg_file.registers[2], 64'd7);

        // Relative branch and call/return.
        clear_program();
        write_inst(64'h2000, enc_lit(OP_BRR_LIT, 12'd8));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd7, 12'd99));
        write_inst(64'h2008, enc_rd_lit(OP_ADDI, 5'd7, 12'd9));
        write_inst(64'h200C, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(80);
        expect64("brr_lit target", dut.reg_file.registers[7], 64'd9);

        clear_program();
        write_inst(64'h2000, enc_r(OP_CALL, 5'd10));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd8, 12'd1));
        write_inst(64'h2008, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        write_inst(64'h2010, enc_r(OP_RETURN, 5'd0));
        do_reset();
        dut.reg_file.registers[10] = 64'h2010;
        run_until_halt(120);
        expect64("call/return", dut.reg_file.registers[8], 64'd1);
        expect64("saved return", read_mem64(RET_SLOT), 64'h2004);

        if (fails == 0)
            $display("\nALL COMPREHENSIVE TESTS PASSED");
        else
            $display("\nTOTAL FAILS = %0d", fails);

        $finish;
    end
endmodule
