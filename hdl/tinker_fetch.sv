`timescale 1ns/1ps

module tinker_fetch(
    input         clk,
    input         reset,
    input         pc_write,
    input  [63:0] pc_next,
    output reg [63:0] pc
);
    initial begin
        pc = 64'h0000_0000_0000_2000;
    end
endmodule
