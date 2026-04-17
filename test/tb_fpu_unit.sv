`timescale 1ns/1ps

module tb_fpu_unit;
    reg clk, reset, flush, start, consume;
    reg [63:0] a, b;
    reg [7:0] op;
    reg [4:0] tag_in;
    wire busy, pending, result_valid;
    wire [4:0] result_tag;
    wire [63:0] result;

    fpu uut (
        .clk(clk), .reset(reset), .flush(flush),
        .start(start), .consume(consume),
        .a(a), .b(b), .op(op), .tag_in(tag_in),
        .busy(busy), .pending(pending),
        .result_valid(result_valid), .result_tag(result_tag), .result(result)
    );

    always #5 clk = ~clk;

    integer cycle;

    initial begin
        clk = 0;
        reset = 1;
        flush = 0;
        start = 0;
        consume = 0;
        a = 0;
        b = 0;
        op = 0;
        tag_in = 0;
        cycle = 0;

        $dumpfile("sim/fpu_unit.vcd");
        $dumpvars(0, tb_fpu_unit);

        @(posedge clk);
        @(posedge clk);
        reset = 0;

        $display("Cycle | start | pending | valid | result");
        $display("------|-------|---------|-------|--------");

        a = 64'h3FF0000000000000;
        b = 64'h4000000000000000;
        op = 8'h14;
        tag_in = 5'd5;
        start = 1;
        #1;
        @(posedge clk);
        cycle = cycle + 1;
        #1;
        $display("  %0d   |   %b   |    %b    |   %b   | %h | s0v=%b s1v=%b s2v=%b s3v=%b s4v=%b",
            cycle, start, pending, result_valid, result,
            uut.s0_valid, uut.s1_valid, uut.s2_valid, uut.s3_valid, uut.s4_valid);

        start = 0;

        repeat (10) begin
            @(posedge clk);
            #1;
            cycle = cycle + 1;
            $display("  %0d   |   %b   |    %b    |   %b   | %h | s0v=%b s1v=%b s2v=%b s3v=%b s4v=%b",
                cycle, start, pending, result_valid, result,
                uut.s0_valid, uut.s1_valid, uut.s2_valid, uut.s3_valid, uut.s4_valid);
        end

        if (result == 64'h4008000000000000)
            $display("\nPASS: FADD 1.0 + 2.0 = 3.0");
        else
            $display("\nFAIL: Expected 0x4008000000000000, got 0x%h", result);

        $finish;
    end
endmodule
