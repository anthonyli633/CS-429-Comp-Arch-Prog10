`timescale 1ns/1ps

module tb_and_only;
    reg clk;
    reg reset;
    integer cycles;

    localparam OP_AND  = 5'h00;
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

    initial begin
        reset = 1'b0;
        $dumpfile("sim/and_only.vcd");
        $dumpvars(0, tb_and_only);

        write_inst(64'h2000, enc_rrr(OP_AND, 5'd1, 5'd2, 5'd3));
        write_inst(64'h2004, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});

        do_reset();
        dut.reg_file.registers[2] = 64'hF0F0_F0F0_F0F0_F0F0;
        dut.reg_file.registers[3] = 64'h0FF0_0FF0_0FF0_0FF0;

        run_until_halt(40);

        if (!hlt) begin
            $display("FAIL: core did not halt");
        end else if (dut.reg_file.registers[1] !== 64'h00F0_00F0_00F0_00F0) begin
            $display("FAIL: AND result got=%h expected=%h",
                dut.reg_file.registers[1],
                64'h00F0_00F0_00F0_00F0
            );
        end else begin
            $display("PASS: AND smoke test in %0d cycles", cycles);
        end

        $finish;
    end
endmodule
