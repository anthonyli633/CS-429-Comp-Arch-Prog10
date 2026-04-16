`timescale 1ns/1ps

module tb_hidden_style;
    reg clk;
    reg reset;
    integer fails;
    integer cycles;
    integer i;

    localparam MEM_SIZE = 512 * 1024;
    localparam RET_SLOT = MEM_SIZE - 8;

    localparam OP_AND       = 5'h00;
    localparam OP_OR        = 5'h01;
    localparam OP_XOR       = 5'h02;
    localparam OP_BR        = 5'h08;
    localparam OP_BRR_LIT   = 5'h0a;
    localparam OP_BRNZ      = 5'h0b;
    localparam OP_PRIV      = 5'h0f;
    localparam OP_MOV_LOAD  = 5'h10;
    localparam OP_MOV_STORE = 5'h13;
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
        integer j;
        begin
            for (j = 16'h2000; j < 16'h2140; j = j + 1)
                dut.memory.bytes[j] = 8'h00;
        end
    endtask

    task clear_data_window;
        integer j;
        begin
            for (j = 16'h0100; j < 16'h0180; j = j + 1)
                dut.memory.bytes[j] = 8'h00;
        end
    endtask

    task clear_ret_slot;
        begin
            write_mem64(RET_SLOT, 64'd0);
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
                $display("FAIL %-28s got=%h expected=%h", name, got, exp);
            end else begin
                $display("PASS %-28s %h", name, got);
            end
        end
    endtask

    task expect_true;
        input [255:0] name;
        input cond;
        begin
            if (!cond) begin
                fails = fails + 1;
                $display("FAIL %-28s", name);
            end else begin
                $display("PASS %-28s", name);
            end
        end
    endtask

    initial begin
        fails = 0;
        reset = 1'b0;
        cycles = 0;

        $dumpfile("sim/hidden_style.vcd");
        $dumpvars(0, tb_hidden_style);

        // Long branch loop: if this stalls, it matches the autograder symptom closely.
        clear_program();
        clear_data_window();
        clear_ret_slot();
        write_inst(64'h2000, enc_rr(OP_BRNZ, 5'd2, 5'd1));
        write_inst(64'h2004, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        write_inst(64'h2038, enc_rd_lit(OP_ADDI, 5'd4, 12'd1));
        write_inst(64'h203C, enc_rd_lit(OP_SUBI, 5'd1, 12'd1));
        write_inst(64'h2040, enc_rr(OP_BRNZ, 5'd6, 5'd0));
        write_inst(64'h2044, enc_rr(OP_BRNZ, 5'd3, 5'd4));
        do_reset();
        dut.reg_file.registers[1] = 64'd5000;
        dut.reg_file.registers[2] = 64'h2038;
        dut.reg_file.registers[3] = 64'h2000;
        dut.reg_file.registers[6] = 64'd0;
        run_until_halt(120000);
        expect_true("branch loop halts", hlt == 1'b1);
        expect64("branch loop count", dut.reg_file.registers[4], 64'd5000);
        expect64("branch loop tail", dut.reg_file.registers[1], 64'd0);

        // Wrong-path side effects must not commit.
        clear_program();
        clear_data_window();
        clear_ret_slot();
        write_inst(64'h2000, enc_rr(OP_BRNZ, 5'd2, 5'd1));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd7, 12'd99));
        write_inst(64'h2008, enc_mov_store(5'd3, 5'd7, 12'd0));
        write_inst(64'h200C, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        write_inst(64'h2010, enc_rd_lit(OP_ADDI, 5'd7, 12'd5));
        write_inst(64'h2014, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[1] = 64'd1;
        dut.reg_file.registers[2] = 64'h2010;
        dut.reg_file.registers[3] = 64'h0100;
        run_until_halt(300);
        expect_true("recovery halts", hlt == 1'b1);
        expect64("recovery reg sidefx", dut.reg_file.registers[7], 64'd5);
        expect64("recovery store sidefx", read_mem64(64'h0100), 64'd0);

        // CDB-style collision: two producers complete together and feed later consumers.
        clear_program();
        clear_data_window();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'd5));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd2, 12'd7));
        write_inst(64'h2008, enc_rrr(OP_ADD, 5'd3, 5'd1, 5'd2));
        write_inst(64'h200C, enc_rrr(OP_SUB, 5'd4, 5'd2, 5'd1));
        write_inst(64'h2010, enc_rrr(OP_XOR, 5'd5, 5'd3, 5'd4));
        write_inst(64'h2014, enc_rrr(OP_OR,  5'd6, 5'd3, 5'd4));
        write_inst(64'h2018, enc_rrr(OP_AND, 5'd8, 5'd5, 5'd6));
        write_inst(64'h201C, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(300);
        expect_true("cdb halts", hlt == 1'b1);
        expect64("cdb xor", dut.reg_file.registers[5], 64'd14);
        expect64("cdb or", dut.reg_file.registers[6], 64'd14);
        expect64("cdb and", dut.reg_file.registers[8], 64'd14);

        // Forward newest older store to a load.
        clear_program();
        clear_data_window();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'h100));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd2, 12'd11));
        write_inst(64'h2008, enc_mov_store(5'd1, 5'd2, 12'd0));
        write_inst(64'h200C, enc_rd_lit(OP_ADDI, 5'd2, 12'd22));
        write_inst(64'h2010, enc_mov_store(5'd1, 5'd2, 12'd0));
        write_inst(64'h2014, enc_mov_load(5'd4, 5'd1, 12'd0));
        write_inst(64'h2018, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(400);
        expect_true("lsq order halts", hlt == 1'b1);
        expect64("lsq newest store", dut.reg_file.registers[4], 64'd33);
        expect64("lsq committed store", read_mem64(64'h0100), 64'd33);

        // Older unknown store must not deadlock younger work forever.
        clear_program();
        clear_data_window();
        write_inst(64'h2000, enc_mov_store(5'd9, 5'd2, 12'd0));
        write_inst(64'h2004, enc_mov_load(5'd4, 5'd1, 12'd0));
        write_inst(64'h2008, enc_rrr(OP_ADD, 5'd5, 5'd4, 5'd2));
        write_inst(64'h200C, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[1] = 64'h0100;
        dut.reg_file.registers[2] = 64'd3;
        dut.reg_file.registers[9] = 64'h0100;
        write_mem64(64'h0100, 64'd9);
        run_until_halt(500);
        expect_true("unknown store halts", hlt == 1'b1);
        expect64("unknown store load", dut.reg_file.registers[4], 64'd3);
        expect64("unknown store add", dut.reg_file.registers[5], 64'd6);

        // Longer memory stream loop to stress LSQ/ROB wraparound and branch recovery.
        clear_program();
        clear_data_window();
        write_inst(64'h2000, enc_mov_store(5'd1, 5'd2, 12'd0));
        write_inst(64'h2004, enc_mov_load(5'd4, 5'd1, 12'd0));
        write_inst(64'h2008, enc_rd_lit(OP_ADDI, 5'd1, 12'd8));
        write_inst(64'h200C, enc_rd_lit(OP_ADDI, 5'd2, 12'd1));
        write_inst(64'h2010, enc_rd_lit(OP_SUBI, 5'd3, 12'd1));
        write_inst(64'h2014, enc_rr(OP_BRNZ, 5'd5, 5'd3));
        write_inst(64'h2018, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[1] = 64'h0100;
        dut.reg_file.registers[2] = 64'd1;
        dut.reg_file.registers[3] = 64'd256;
        dut.reg_file.registers[5] = 64'h2000;
        run_until_halt(150000);
        expect_true("memory stream halts", hlt == 1'b1);
        expect64("memory stream last load", dut.reg_file.registers[4], 64'd256);
        expect64("memory stream tail count", dut.reg_file.registers[3], 64'd0);
        expect64("memory stream first", read_mem64(64'h0100), 64'd1);
        expect64("memory stream last", read_mem64(64'h08f8), 64'd256);

        if (fails == 0)
            $display("\nALL HIDDEN-STYLE TESTS PASSED");
        else
            $display("\nHIDDEN-STYLE FAILS = %0d", fails);

        $finish;
    end
endmodule
