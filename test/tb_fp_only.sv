`timescale 1ns/1ps

module tb_fp_only;
    reg clk;
    reg reset;
    integer fails;
    integer cycles;

    localparam OP_ADDF = 5'h14;
    localparam OP_SUBF = 5'h15;
    localparam OP_MULF = 5'h16;
    localparam OP_DIVF = 5'h17;
    localparam OP_PRIV = 5'h0f;

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

    task clear_program;
        integer i;
        begin
            for (i = 16'h2000; i < 16'h2040; i = i + 1)
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
        input [63:0] got;
        input [63:0] exp;
        begin
            if (got !== exp) begin
                fails = fails + 1;
                $display("FAIL %-20s got=%h expected=%h", name, got, exp);
            end else begin
                $display("PASS %-20s %h", name, got);
            end
        end
    endtask

    task expect_nan;
        input [255:0] name;
        input [63:0] got;
        begin
            if ((got[62:52] == 11'h7ff) && (got[51:0] != 0)) begin
                $display("PASS %-20s %h", name, got);
            end else begin
                fails = fails + 1;
                $display("FAIL %-20s got=%h expected=NaN", name, got);
            end
        end
    endtask

    task run_fp_case;
        input [31:0] inst;
        input [4:0] rd;
        input [4:0] rs;
        input [4:0] rt;
        input [63:0] rs_value;
        input [63:0] rt_value;
        begin
            clear_program();
            write_inst(64'h2000, inst);
            write_inst(64'h2004, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
            do_reset();
            dut.reg_file.registers[rs] = rs_value;
            dut.reg_file.registers[rt] = rt_value;
            run_until_halt(80);
            if (!hlt) begin
                fails = fails + 1;
                $display("FAIL program did not halt");
            end
        end
    endtask

    initial begin
        fails = 0;
        reset = 1'b0;
        cycles = 0;

        $dumpfile("sim/fp_only.vcd");
        $dumpvars(0, tb_fp_only);

        run_fp_case(enc_rrr(OP_ADDF, 5'd1, 5'd2, 5'd3), 5'd1, 5'd2, 5'd3,
            64'h3FF8_0000_0000_0000, 64'h3FF8_0000_0000_0000);
        expect64("ADDF basic", dut.reg_file.registers[1], 64'h4008_0000_0000_0000);

        run_fp_case(enc_rrr(OP_SUBF, 5'd4, 5'd5, 5'd6), 5'd4, 5'd5, 5'd6,
            64'h4016_0000_0000_0000, 64'h4002_0000_0000_0000);
        expect64("SUBF basic", dut.reg_file.registers[4], 64'h400A_0000_0000_0000);

        run_fp_case(enc_rrr(OP_MULF, 5'd7, 5'd8, 5'd9), 5'd7, 5'd8, 5'd9,
            64'h4004_0000_0000_0000, 64'h4010_0000_0000_0000);
        expect64("MULF basic", dut.reg_file.registers[7], 64'h4024_0000_0000_0000);

        run_fp_case(enc_rrr(OP_DIVF, 5'd10, 5'd11, 5'd12), 5'd10, 5'd11, 5'd12,
            64'h401E_0000_0000_0000, 64'h4004_0000_0000_0000);
        expect64("DIVF basic", dut.reg_file.registers[10], 64'h4008_0000_0000_0000);

        run_fp_case(enc_rrr(OP_ADDF, 5'd13, 5'd14, 5'd15), 5'd13, 5'd14, 5'd15,
            64'h7FF0_0000_0000_0000, 64'h3FF0_0000_0000_0000);
        expect64("ADDF inf", dut.reg_file.registers[13], 64'h7FF0_0000_0000_0000);

        run_fp_case(enc_rrr(OP_DIVF, 5'd16, 5'd17, 5'd18), 5'd16, 5'd17, 5'd18,
            64'h0000_0000_0000_0000, 64'h4014_0000_0000_0000);
        expect64("DIVF zero", dut.reg_file.registers[16], 64'h0000_0000_0000_0000);

        run_fp_case(enc_rrr(OP_DIVF, 5'd19, 5'd20, 5'd21), 5'd19, 5'd20, 5'd21,
            64'h3FF0_0000_0000_0000, 64'h0000_0000_0000_0000);
        expect64("DIVF by zero", dut.reg_file.registers[19], 64'h7FF0_0000_0000_0000);

        run_fp_case(enc_rrr(OP_ADDF, 5'd22, 5'd23, 5'd24), 5'd22, 5'd23, 5'd24,
            64'h7FF8_0000_0000_0001, 64'h3FF0_0000_0000_0000);
        expect_nan("ADDF NaN", dut.reg_file.registers[22]);

        if (fails == 0)
            $display("\nALL FP TESTS PASSED");
        else
            $display("\nFP TESTS FAILED: %0d", fails);

        $finish;
    end
endmodule
