`timescale 1ns/1ps

module fpu_unit_test;
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

        $dumpfile("fpu_unit_test.vcd");
        $dumpvars(0, fpu_unit_test);

        // Reset
        @(posedge clk);
        @(posedge clk);
        reset = 0;

        $display("Cycle | start | pending | valid | result");
        $display("------|-------|---------|-------|--------");

        // Test FADD: 1.0 + 2.0 = 3.0
        a = 64'h3FF0000000000000; // 1.0
        b = 64'h4000000000000000; // 2.0
        op = 8'h14; // FADD
        tag_in = 5'd5;
        start = 1;
        #1; // Small delay to ensure inputs are stable before clock edge
        @(posedge clk);
        cycle = cycle + 1;
        #1; // Let combinational logic settle
        $display("  %0d   |   %b   |    %b    |   %b   | %h | s0v=%b s1v=%b s2v=%b s3v=%b s4v=%b",
            cycle, start, pending, result_valid, result,
            uut.s0_valid, uut.s1_valid, uut.s2_valid, uut.s3_valid, uut.s4_valid);

        start = 0;

        // Run for 10 more cycles to see the result
        repeat (10) begin
            @(posedge clk);
            #1; // Let combinational logic settle
            cycle = cycle + 1;
            $display("  %0d   |   %b   |    %b    |   %b   | %h | s0v=%b s1v=%b s2v=%b s3v=%b s4v=%b",
                cycle, start, pending, result_valid, result,
                uut.s0_valid, uut.s1_valid, uut.s2_valid, uut.s3_valid, uut.s4_valid);
        end

        if (result == 64'h4008000000000000) begin
            $display("\nPASS: FADD 1.0 + 2.0 = 3.0");
        end else begin
            $display("\nFAIL: Expected 0x4008000000000000, got 0x%h", result);
        end

        $finish;
    end
endmodule