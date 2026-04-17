`timescale 1ns/1ps

module tb_regressions;
    reg clk;
    reg reset;
    integer fails;
    integer cycles;
    integer i;

    localparam MEM_SIZE = 512 * 1024;

    localparam OP_AND       = 5'h00;
    localparam OP_OR        = 5'h01;
    localparam OP_XOR       = 5'h02;
    localparam OP_BRGT      = 5'h0e;
    localparam OP_BRNZ      = 5'h0b;
    localparam OP_PRIV      = 5'h0f;
    localparam OP_MOV_LOAD  = 5'h10;
    localparam OP_MOV_LIT   = 5'h12;
    localparam OP_ADD       = 5'h18;
    localparam OP_ADDI      = 5'h19;
    localparam OP_SUB       = 5'h1a;
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

    function [31:0] enc_rd_lit;
        input [4:0] opcode, rd;
        input [11:0] lit;
        begin
            enc_rd_lit = {opcode, rd, 5'd0, 5'd0, lit};
        end
    endfunction

    function [31:0] enc_mov_load;
        input [4:0] rd, rs;
        input [11:0] lit;
        begin
            enc_mov_load = {OP_MOV_LOAD, rd, rs, 5'd0, lit};
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

    task clear_program;
        integer j;
        begin
            for (j = 16'h2000; j < 16'h2100; j = j + 1)
                dut.memory.bytes[j] = 8'h00;
        end
    endtask

    task do_reset;
        begin
            reset = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            reset = 1'b0;
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
        input [63:0] got;
        input [63:0] exp;
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

        $dumpfile("sim/regressions.vcd");
        $dumpvars(0, tb_regressions);

        // Straight-line reproduction of the autograder ooo_window benchmark.
        clear_program();
        for (i = 0; i < 12; i = i + 1)
            write_mem64(64'd256 + (i * 64'd8), i + 64'd1);
        write_inst(64'h2000, enc_mov_load(5'd4,  5'd0, 12'd0));
        write_inst(64'h2004, enc_rrr(OP_ADD, 5'd5,  5'd28, 5'd29));
        write_inst(64'h2008, enc_mov_load(5'd6,  5'd0, 12'd8));
        write_inst(64'h200C, enc_rrr(OP_SUB, 5'd7,  5'd28, 5'd29));
        write_inst(64'h2010, enc_mov_load(5'd8,  5'd0, 12'd16));
        write_inst(64'h2014, enc_rrr(OP_XOR, 5'd9,  5'd28, 5'd29));
        write_inst(64'h2018, enc_mov_load(5'd10, 5'd0, 12'd24));
        write_inst(64'h201C, enc_rrr(OP_OR,  5'd11, 5'd28, 5'd29));
        write_inst(64'h2020, enc_mov_load(5'd12, 5'd0, 12'd32));
        write_inst(64'h2024, enc_rrr(OP_AND, 5'd13, 5'd28, 5'd29));
        write_inst(64'h2028, enc_mov_load(5'd14, 5'd0, 12'd40));
        write_inst(64'h202C, enc_rrr(OP_ADD, 5'd15, 5'd28, 5'd29));
        write_inst(64'h2030, enc_mov_load(5'd16, 5'd0, 12'd48));
        write_inst(64'h2034, enc_rrr(OP_SUB, 5'd17, 5'd28, 5'd29));
        write_inst(64'h2038, enc_mov_load(5'd18, 5'd0, 12'd56));
        write_inst(64'h203C, enc_rrr(OP_XOR, 5'd19, 5'd28, 5'd29));
        write_inst(64'h2040, enc_mov_load(5'd20, 5'd0, 12'd64));
        write_inst(64'h2044, enc_rrr(OP_OR,  5'd21, 5'd28, 5'd29));
        write_inst(64'h2048, enc_mov_load(5'd22, 5'd0, 12'd72));
        write_inst(64'h204C, enc_rrr(OP_AND, 5'd23, 5'd28, 5'd29));
        write_inst(64'h2050, enc_mov_load(5'd24, 5'd0, 12'd80));
        write_inst(64'h2054, enc_rrr(OP_ADD, 5'd25, 5'd28, 5'd29));
        write_inst(64'h2058, enc_mov_load(5'd26, 5'd0, 12'd88));
        write_inst(64'h205C, enc_rrr(OP_SUB, 5'd27, 5'd28, 5'd29));
        write_inst(64'h2060, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[0]  = 64'd256;
        dut.reg_file.registers[28] = 64'd11;
        dut.reg_file.registers[29] = 64'd17;
        run_until_halt(200);
        expect_true("window halts", hlt == 1'b1);
        expect64("load r14", dut.reg_file.registers[14], 64'd6);
        expect64("load r22", dut.reg_file.registers[22], 64'd10);
        expect64("xor r19",  dut.reg_file.registers[19], 64'd26);
        expect64("sub r27",  dut.reg_file.registers[27], -64'sd6);

        // Repeated aliasing mispredicts with a wrong-path halt fetched each trip.
        clear_program();
        write_inst(64'h2000, enc_rr(OP_BRNZ, 5'd2, 5'd5));
        write_inst(64'h2004, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        write_inst(64'h2038, enc_rd_lit(OP_ADDI, 5'd4, 12'd1));
        write_inst(64'h203C, enc_rd_lit(OP_SUBI, 5'd5, 12'd1));
        write_inst(64'h2040, enc_rr(OP_BRNZ, 5'd6, 5'd0));
        write_inst(64'h2044, enc_rr(OP_BRNZ, 5'd3, 5'd4));
        do_reset();
        dut.reg_file.registers[2] = 64'h2038;
        dut.reg_file.registers[3] = 64'h2000;
        dut.reg_file.registers[5] = 64'd20;
        dut.reg_file.registers[6] = 64'h0000_0000_0000_0000;
        run_until_halt(800);
        expect_true("branch stress halts", hlt == 1'b1);
        expect64("branch stress count", dut.reg_file.registers[4], 64'd20);
        expect64("branch stress tail", dut.reg_file.registers[5], 64'd0);
        expect_true("free list not drained", dut.free_count > 8);

        // Backward BRGT loop regression for self-dependence and branch recovery.
        clear_program();
        write_inst(64'h2000, enc_rrr(OP_ADD, 5'd3, 5'd3, 5'd1));
        write_inst(64'h2004, enc_rd_lit(OP_SUBI, 5'd1, 12'd1));
        write_inst(64'h2008, enc_rrr(OP_BRGT, 5'd4, 5'd1, 5'd2));
        write_inst(64'h200C, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[1] = 64'd4;
        dut.reg_file.registers[2] = 64'd0;
        dut.reg_file.registers[3] = 64'd0;
        dut.reg_file.registers[4] = 64'h2000;
        run_until_halt(160);
        expect_true("brgt loop halts", hlt == 1'b1);
        expect64("brgt loop sum", dut.reg_file.registers[3], 64'd10);
        expect64("brgt loop count", dut.reg_file.registers[1], 64'd0);

        // Preserve the 3-wide issue smoke tests after removing /test2.
        clear_program();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'd10));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd2, 12'd20));
        write_inst(64'h2008, enc_rd_lit(OP_ADDI, 5'd3, 12'd30));
        write_inst(64'h200C, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(80);
        expect64("triple issue r1", dut.reg_file.registers[1], 64'd10);
        expect64("triple issue r2", dut.reg_file.registers[2], 64'd20);
        expect64("triple issue r3", dut.reg_file.registers[3], 64'd30);
        expect_true("triple issue cadence", cycles <= 8);

        clear_program();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'd5));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd2, 12'd10));
        write_inst(64'h2008, enc_rrr(OP_ADD, 5'd3, 5'd1, 5'd2));
        write_inst(64'h200C, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(80);
        expect64("issue fallback r1", dut.reg_file.registers[1], 64'd5);
        expect64("issue fallback r2", dut.reg_file.registers[2], 64'd10);
        expect64("issue fallback r3", dut.reg_file.registers[3], 64'd15);

        // Keep a MOV_LIT/WAW regression in /test with the official semantics.
        clear_program();
        write_inst(64'h2000, enc_rd_lit(OP_MOV_LIT, 5'd5, 12'h123));
        write_inst(64'h2004, enc_rd_lit(OP_MOV_LIT, 5'd5, 12'h456));
        write_inst(64'h2008, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[5] = 64'h1234_5678_9ABC_DEF0;
        run_until_halt(80);
        expect64("mov_lit waw result", dut.reg_file.registers[5], 64'h1234_5678_9ABC_D456);

        if (fails == 0)
            $display("\nALL REGRESSION TESTS PASSED");
        else
            $display("\nREGRESSION FAILS = %0d", fails);

        $finish;
    end
endmodule
