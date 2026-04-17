`timescale 1ns/1ps

module tinker_alu(
    input  [63:0] a,
    input  [63:0] b,
    input  [5:0]  op,
    output reg [63:0] result,
    output wire a_is_zero,
    output wire a_gt_b_signed
);
    localparam ALU_PASS_A = 6'd0;
    localparam ALU_PASS_B = 6'd1;
    localparam ALU_AND    = 6'd2;
    localparam ALU_OR     = 6'd3;
    localparam ALU_XOR    = 6'd4;
    localparam ALU_NOT    = 6'd5;
    localparam ALU_SHR    = 6'd6;
    localparam ALU_SHL    = 6'd7;
    localparam ALU_ADD    = 6'd8;
    localparam ALU_SUB    = 6'd9;
    localparam ALU_MUL    = 6'd10;
    localparam ALU_DIV    = 6'd11;

    assign a_is_zero     = (a == 64'd0);
    assign a_gt_b_signed = ($signed(a) > $signed(b));

    always @(*) begin
        case (op)
            ALU_PASS_A: result = a;
            ALU_PASS_B: result = b;
            ALU_AND   : result = a & b;
            ALU_OR    : result = a | b;
            ALU_XOR   : result = a ^ b;
            ALU_NOT   : result = ~a;
            ALU_SHR   : result = a >> b[5:0];
            ALU_SHL   : result = a << b[5:0];
            ALU_ADD   : result = $signed(a) + $signed(b);
            ALU_SUB   : result = $signed(a) - $signed(b);
            ALU_MUL   : result = $signed(a) * $signed(b);
            ALU_DIV   : result = (b == 64'd0) ? 64'd0 : $signed(a) / $signed(b);
            default   : result = 64'd0;
        endcase
    end
endmodule

module tinker_fpu(
    input  [63:0] a,
    input  [63:0] b,
    input  [5:0]  op,
    output reg [63:0] result
);
    localparam ALU_FADD   = 6'd12;
    localparam ALU_FSUB   = 6'd13;
    localparam ALU_FMUL   = 6'd14;
    localparam ALU_FDIV   = 6'd15;

    localparam QUIET_NAN  = 64'h7ff8_0000_0000_0000;

    function is_nan64;
        input [63:0] x;
        begin
            is_nan64 = (x[62:52] == 11'h7ff) && (x[51:0] != 0);
        end
    endfunction

    function is_inf64;
        input [63:0] x;
        begin
            is_inf64 = (x[62:52] == 11'h7ff) && (x[51:0] == 0);
        end
    endfunction

    function is_zero64;
        input [63:0] x;
        begin
            is_zero64 = (x[62:52] == 0) && (x[51:0] == 0);
        end
    endfunction

    function [55:0] shr_sticky56;
        input [55:0] x;
        input integer sh;
        reg [55:0] tmp;
        reg sticky;
        integer i;
        begin
            if (sh <= 0) begin
                shr_sticky56 = x;
            end else if (sh >= 56) begin
                shr_sticky56 = (x != 0) ? 56'd1 : 56'd0;
            end else begin
                tmp = x >> sh;
                sticky = 1'b0;
                for (i = 0; i < sh; i = i + 1)
                    sticky = sticky | x[i];
                tmp[0] = tmp[0] | sticky;
                shr_sticky56 = tmp;
            end
        end
    endfunction

    function [63:0] pack;
        input sign;
        input integer exp_unbiased;
        input [55:0] ext;
        reg [55:0] ext_r;
        reg [52:0] sig_main;
        reg guard;
        reg roundb;
        reg sticky;
        reg inc;
        reg [53:0] sig_round;
        integer exp_r;
        integer sh;
        begin
            ext_r = ext;
            exp_r = exp_unbiased;

            if ((exp_r < -1022) || ((exp_r == -1022) && (ext_r[55] == 1'b0))) begin
                sh = -1022 - exp_r;
                if (sh < 0)
                    sh = 0;
                ext_r = shr_sticky56(ext_r, sh);
                exp_r = -1022;
            end

            sig_main = ext_r[55:3];
            guard    = ext_r[2];
            roundb   = ext_r[1];
            sticky   = ext_r[0];

            inc = guard && (roundb || sticky || sig_main[0]);
            sig_round = {1'b0, sig_main} + inc;

            if (sig_round == 0) begin
                pack = 64'd0;
            end else if (sig_round[53]) begin
                sig_round = sig_round >> 1;
                exp_r = exp_r + 1;
                if (exp_r + 1023 >= 2047)
                    pack = {sign, 11'h7ff, 52'd0};
                else
                    pack = {sign, exp_r[10:0] + 11'd1023, sig_round[51:0]};
            end else if ((exp_r == -1022) && (sig_round[52] == 1'b0)) begin
                pack = {sign, 11'd0, sig_round[51:0]};
            end else if (exp_r + 1023 >= 2047) begin
                pack = {sign, 11'h7ff, 52'd0};
            end else begin
                pack = {sign, exp_r[10:0] + 11'd1023, sig_round[51:0]};
            end
        end
    endfunction

    function [63:0] fp_addsub64;
        input [63:0] x;
        input [63:0] y;
        input sub;
        reg [63:0] y2;
        reg sx;
        reg sy;
        reg sr;
        reg s_big;
        reg s_small;
        reg [10:0] ex;
        reg [10:0] ey;
        reg [51:0] fx;
        reg [51:0] fy;
        reg [52:0] mx;
        reg [52:0] my;
        reg [52:0] m_big;
        reg [52:0] m_small;
        reg [55:0] ex_big;
        reg [55:0] ex_small;
        reg [55:0] ex_res;
        reg [56:0] sum57;
        integer e1;
        integer e2;
        integer er;
        integer sh;
        integer e_big;
        integer e_small;
        integer norm_i;
        begin
            y2 = sub ? {~y[63], y[62:0]} : y;

            if (is_nan64(x) || is_nan64(y2)) begin
                fp_addsub64 = QUIET_NAN;
            end else if (is_inf64(x) && is_inf64(y2) && (x[63] != y2[63])) begin
                fp_addsub64 = QUIET_NAN;
            end else if (is_inf64(x)) begin
                fp_addsub64 = x;
            end else if (is_inf64(y2)) begin
                fp_addsub64 = y2;
            end else if (is_zero64(x) && is_zero64(y2)) begin
                fp_addsub64 = 64'd0;
            end else begin
                sx = x[63];
                sy = y2[63];
                ex = x[62:52];
                ey = y2[62:52];
                fx = x[51:0];
                fy = y2[51:0];

                e1 = (ex == 0) ? -1022 : (ex - 1023);
                e2 = (ey == 0) ? -1022 : (ey - 1023);

                mx = (ex == 0) ? {1'b0, fx} : {1'b1, fx};
                my = (ey == 0) ? {1'b0, fy} : {1'b1, fy};

                if ((e1 > e2) || ((e1 == e2) && (mx >= my))) begin
                    e_big   = e1;
                    m_big   = mx;
                    s_big   = sx;
                    e_small = e2;
                    m_small = my;
                    s_small = sy;
                end else begin
                    e_big   = e2;
                    m_big   = my;
                    s_big   = sy;
                    e_small = e1;
                    m_small = mx;
                    s_small = sx;
                end

                er = e_big;
                ex_big = {m_big, 3'b000};
                sh = e_big - e_small;
                ex_small = shr_sticky56({m_small, 3'b000}, sh);

                if (s_big == s_small) begin
                    sum57 = {1'b0, ex_big} + {1'b0, ex_small};
                    sr = s_big;
                    if (sum57[56]) begin
                        ex_res = sum57[56:1];
                        ex_res[0] = ex_res[0] | sum57[0];
                        er = er + 1;
                    end else begin
                        ex_res = sum57[55:0];
                    end
                end else begin
                    ex_res = ex_big - ex_small;
                    sr = s_big;
                    if (ex_res == 0) begin
                        fp_addsub64 = 64'd0;
                    end
                    for (norm_i = 0; norm_i < 56; norm_i = norm_i + 1) begin
                        if ((ex_res[55] == 1'b0) && (er > -1022)) begin
                            ex_res = ex_res << 1;
                            er = er - 1;
                        end
                    end
                end

                fp_addsub64 = pack(sr, er, ex_res);
            end
        end
    endfunction

    function [63:0] fp_mul64;
        input [63:0] x;
        input [63:0] y;
        reg sx;
        reg sy;
        reg sr;
        reg [10:0] ex;
        reg [10:0] ey;
        reg [52:0] mx;
        reg [52:0] my;
        reg [105:0] prod;
        reg [55:0] ext;
        integer e1;
        integer e2;
        integer er;
        begin
            if (is_nan64(x) || is_nan64(y)) begin
                fp_mul64 = QUIET_NAN;
            end else if ((is_inf64(x) && is_zero64(y)) || (is_inf64(y) && is_zero64(x))) begin
                fp_mul64 = QUIET_NAN;
            end else if (is_inf64(x) || is_inf64(y)) begin
                fp_mul64 = {x[63]^y[63], 11'h7ff, 52'd0};
            end else if (is_zero64(x) || is_zero64(y)) begin
                fp_mul64 = {x[63]^y[63], 63'd0};
            end else begin
                sx = x[63];
                sy = y[63];
                sr = sx ^ sy;
                ex = x[62:52];
                ey = y[62:52];

                e1 = (ex == 0) ? -1022 : (ex - 1023);
                e2 = (ey == 0) ? -1022 : (ey - 1023);

                mx = (ex == 0) ? {1'b0, x[51:0]} : {1'b1, x[51:0]};
                my = (ey == 0) ? {1'b0, y[51:0]} : {1'b1, y[51:0]};

                prod = mx * my;
                er = e1 + e2;

                if (prod[105]) begin
                    ext = {prod[105:53], prod[52], prod[51], |prod[50:0]};
                    er = er + 1;
                end else begin
                    ext = {prod[104:52], prod[51], prod[50], |prod[49:0]};
                end

                fp_mul64 = pack(sr, er, ext);
            end
        end
    endfunction

    function [63:0] fp_div64;
        input [63:0] x;
        input [63:0] y;
        reg sx;
        reg sy;
        reg sr;
        reg [10:0] ex;
        reg [10:0] ey;
        reg [52:0] mx;
        reg [52:0] my;
        reg [107:0] num;
        reg [55:0] q;
        reg [52:0] rem;
        integer e1;
        integer e2;
        integer er;
        begin
            if (is_nan64(x) || is_nan64(y)) begin
                fp_div64 = QUIET_NAN;
            end else if ((is_inf64(x) && is_inf64(y)) || (is_zero64(x) && is_zero64(y))) begin
                fp_div64 = QUIET_NAN;
            end else if (is_inf64(x)) begin
                fp_div64 = {x[63]^y[63], 11'h7ff, 52'd0};
            end else if (is_inf64(y)) begin
                fp_div64 = {x[63]^y[63], 63'd0};
            end else if (is_zero64(y)) begin
                fp_div64 = {x[63]^y[63], 11'h7ff, 52'd0};
            end else if (is_zero64(x)) begin
                fp_div64 = {x[63]^y[63], 63'd0};
            end else begin
                sx = x[63];
                sy = y[63];
                sr = sx ^ sy;
                ex = x[62:52];
                ey = y[62:52];

                e1 = (ex == 0) ? -1022 : (ex - 1023);
                e2 = (ey == 0) ? -1022 : (ey - 1023);

                mx = (ex == 0) ? {1'b0, x[51:0]} : {1'b1, x[51:0]};
                my = (ey == 0) ? {1'b0, y[51:0]} : {1'b1, y[51:0]};

                er = e1 - e2;
                num = {mx, 55'd0};
                q = num / my;
                rem = num % my;

                if (q[55] == 1'b0) begin
                    q = q << 1;
                    er = er - 1;
                end

                q[0] = q[0] | (rem != 0);
                fp_div64 = pack(sr, er, q);
            end
        end
    endfunction

    always @(*) begin
        case (op)
            ALU_FADD: result = fp_addsub64(a, b, 1'b0);
            ALU_FSUB: result = fp_addsub64(a, b, 1'b1);
            ALU_FMUL: result = fp_mul64(a, b);
            ALU_FDIV: result = fp_div64(a, b);
            default : result = 64'd0;
        endcase
    end
endmodule

module tinker_alu_fpu(
    input  [63:0] a,
    input  [63:0] b,
    input  [5:0]  op,
    output reg [63:0] result,
    output wire a_is_zero,
    output wire a_gt_b_signed
);
    wire [63:0] alu_result;
    wire [63:0] fpu_result;

    tinker_alu alu (
        .a(a),
        .b(b),
        .op(op),
        .result(alu_result),
        .a_is_zero(a_is_zero),
        .a_gt_b_signed(a_gt_b_signed)
    );

    tinker_fpu fpu_compat (
        .a(a),
        .b(b),
        .op(op),
        .result(fpu_result)
    );

    always @(*) begin
        case (op)
            6'd12, 6'd13, 6'd14, 6'd15: result = fpu_result;
            default: result = alu_result;
        endcase
    end
endmodule

module fpu(
    input         clk,
    input         reset,
    input         flush,
    input         start,
    input         consume,
    input  [63:0] a,
    input  [63:0] b,
    input  [7:0]  op,
    input  [4:0]  tag_in,
    output wire   busy,
    output wire   pending,
    output wire   result_valid,
    output wire [4:0] result_tag,
    output wire [63:0] result
);
    localparam ALU_FADD = 6'd12;
    localparam ALU_FSUB = 6'd13;
    localparam ALU_FMUL = 6'd14;
    localparam ALU_FDIV = 6'd15;

    reg        s0_valid;
    reg        s1_valid;
    reg        s2_valid;
    reg        s3_valid;
    reg        s4_valid;
    reg [63:0] s0_a;
    reg [63:0] s0_b;
    reg [7:0]  s0_op;
    reg [4:0]  s0_tag;
    reg [63:0] s1_result;
    reg [63:0] s2_result;
    reg [63:0] s3_result;
    reg [63:0] s4_result;
    reg [4:0]  s1_tag;
    reg [4:0]  s2_tag;
    reg [4:0]  s3_tag;
    reg [4:0]  s4_tag;
    reg [5:0]  compat_op;
    wire [63:0] compat_result;

    function [5:0] compat_sel;
        input [7:0] opcode;
        begin
            case (opcode[4:0])
                5'h14: compat_sel = ALU_FADD;
                5'h15: compat_sel = ALU_FSUB;
                5'h16: compat_sel = ALU_FMUL;
                5'h17: compat_sel = ALU_FDIV;
                default: compat_sel = ALU_FADD;
            endcase
        end
    endfunction

    always @(*) begin
        compat_op = compat_sel(s0_op);
    end

    tinker_fpu compat_pipe (
        .a(s0_a),
        .b(s0_b),
        .op(compat_op),
        .result(compat_result)
    );

    assign busy = pending;
    assign pending = s0_valid || s1_valid || s2_valid || s3_valid || s4_valid;
    assign result_valid = s4_valid;
    assign result_tag = s4_tag;
    assign result = s4_result;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            s0_valid <= 1'b0;
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
            s3_valid <= 1'b0;
            s4_valid <= 1'b0;
            s0_a <= 64'd0;
            s0_b <= 64'd0;
            s0_op <= 8'd0;
            s0_tag <= 5'd0;
            s1_result <= 64'd0;
            s2_result <= 64'd0;
            s3_result <= 64'd0;
            s4_result <= 64'd0;
            s1_tag <= 5'd0;
            s2_tag <= 5'd0;
            s3_tag <= 5'd0;
            s4_tag <= 5'd0;
        end else if (flush) begin
            s0_valid <= 1'b0;
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
            s3_valid <= 1'b0;
            s4_valid <= 1'b0;
        end else begin
            s4_valid <= s3_valid;
            s4_result <= s3_result;
            s4_tag <= s3_tag;

            s3_valid <= s2_valid;
            s3_result <= s2_result;
            s3_tag <= s2_tag;

            s2_valid <= s1_valid;
            s2_result <= s1_result;
            s2_tag <= s1_tag;

            s1_valid <= s0_valid;
            s1_result <= compat_result;
            s1_tag <= s0_tag;

            s0_valid <= start;
            if (start) begin
                s0_a <= a;
                s0_b <= b;
                s0_op <= op;
                s0_tag <= tag_in;
            end

            if (consume && !s3_valid)
                s4_valid <= 1'b0;
        end
    end
endmodule
