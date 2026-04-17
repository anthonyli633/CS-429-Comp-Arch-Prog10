`define MEM_SIZE 524288

module loop_forwarding_test;
    reg clk, reset;
    integer errors;

    tinker_core core(
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    task run_until_halt;
        integer timeout;
        begin
            timeout = 0;
            while (!core.hlt && timeout < 20000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            #1;
            if (timeout >= 20000) begin
                $display("FAIL: timed out waiting for halt");
                errors = errors + 1;
            end
        end
    endtask

    task write_instruction;
        input integer a;
        input [31:0] instr;
        begin
            core.memory.bytes[a]   = instr[7:0];
            core.memory.bytes[a+1] = instr[15:8];
            core.memory.bytes[a+2] = instr[23:16];
            core.memory.bytes[a+3] = instr[31:24];
        end
    endtask

    task write_halt;
        input integer a;
        begin
            write_instruction(a, {5'h0f, 5'd0, 5'd0, 5'd0, 12'b0});
        end
    endtask

    task reset_core;
        integer i;
        begin
            reset = 1;
            @(posedge clk); @(posedge clk);
            reset = 0;
            #1;
            for (i = 0; i < 31; i = i + 1)
                core.reg_file.registers[i] = 0;
            core.reg_file.registers[31] = `MEM_SIZE;
            for (i = 0; i < 128; i = i + 1)
                core.memory.bytes['h2000 + i] = 8'h0;
        end
    endtask

    task check;
        input [255:0] name;
        input [63:0] got;
        input [63:0] expected;
        begin
            if (got !== expected) begin
                $display("FAIL: %0s | got=%0d expected=%0d", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", name);
            end
        end
    endtask

    localparam OP_ADDI = 5'h19;
    localparam OP_SUBI = 5'h1b;
    localparam OP_BRNZ = 5'h0b;

    initial begin
        clk = 0;
        errors = 0;

        reset_core();

        core.reg_file.registers[20] = 64'h2000;
        core.reg_file.registers[21] = 64'd3;

        // Two independent instructions, then a self-decrement in slot C.
        // The next-cycle branch must observe the decremented r21 and loop
        // until the counter reaches zero.
        write_instruction('h2000, {OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd1});
        write_instruction('h2004, {OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd1});
        write_instruction('h2008, {OP_SUBI, 5'd21, 5'd0, 5'd0, 12'd1});
        write_instruction('h200c, {OP_BRNZ, 5'd20, 5'd21, 5'd0, 12'd0});
        write_halt('h2010);

        run_until_halt();

        check("loop counter reaches zero", core.reg_file.registers[21], 64'd0);
        check("slot A body runs three times", core.reg_file.registers[1], 64'd3);
        check("slot B body runs three times", core.reg_file.registers[2], 64'd3);

        reset_core();

        core.reg_file.registers[20] = 64'h2000;
        core.reg_file.registers[21] = 64'd3;
        core.memory.bytes[0] = 8'd9;
        core.memory.bytes[1] = 8'd0;
        core.memory.bytes[2] = 8'd0;
        core.memory.bytes[3] = 8'd0;
        core.memory.bytes[4] = 8'd0;
        core.memory.bytes[5] = 8'd0;
        core.memory.bytes[6] = 8'd0;
        core.memory.bytes[7] = 8'd0;

        // Match the hidden-loop tail shape more closely:
        // slot A is a load, slot B is the self-decrement, then BRNZ follows.
        write_instruction('h2000, {5'h10, 5'd9, 5'd0, 5'd0, 12'd0});
        write_instruction('h2004, {OP_SUBI, 5'd21, 5'd0, 5'd0, 12'd1});
        write_instruction('h2008, {OP_BRNZ, 5'd20, 5'd21, 5'd0, 12'd0});
        write_halt('h200c);

        run_until_halt();

        check("load+slot B decrement counter reaches zero", core.reg_file.registers[21], 64'd0);
        check("load in slot A executes three times", core.reg_file.registers[9], 64'd9);

        reset_core();

        core.reg_file.registers[20] = 64'h2000;
        core.reg_file.registers[21] = 64'd3;

        // Triple-issue group followed by dual-issue group, then branch.
        // This exercises the FD shift logic across mixed issue widths.
        write_instruction('h2000, {OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd1});
        write_instruction('h2004, {OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd1});
        write_instruction('h2008, {OP_ADDI, 5'd3, 5'd0, 5'd0, 12'd1});
        write_instruction('h200c, {OP_ADDI, 5'd4, 5'd0, 5'd0, 12'd1});
        write_instruction('h2010, {OP_SUBI, 5'd21, 5'd0, 5'd0, 12'd1});
        write_instruction('h2014, {OP_BRNZ, 5'd20, 5'd21, 5'd0, 12'd0});
        write_halt('h2018);

        run_until_halt();

        check("mixed issue counter reaches zero", core.reg_file.registers[21], 64'd0);
        check("mixed issue slot A triple body runs three times", core.reg_file.registers[1], 64'd3);
        check("mixed issue slot B triple body runs three times", core.reg_file.registers[2], 64'd3);
        check("mixed issue slot C triple body runs three times", core.reg_file.registers[3], 64'd3);
        check("mixed issue dual body runs three times", core.reg_file.registers[4], 64'd3);

        reset_core();

        core.reg_file.registers[1] = 64'h3FF0000000000000; // 1.0
        core.reg_file.registers[2] = 64'h4000000000000000; // 2.0
        core.reg_file.registers[3] = 64'h3FE0000000000000; // 0.5
        core.reg_file.registers[20] = 64'h2000;
        core.reg_file.registers[21] = 64'd3;
        core.reg_file.registers[28] = 64'd11;
        core.reg_file.registers[29] = 64'd17;
        core.memory.bytes[0] = 8'd5;
        core.memory.bytes[8] = 8'd7;

        // Reduced form of the hidden cdb-collision loop:
        // independent ALU/load work, then an FP dependency, then store/load,
        // then the loop-closing SUBI/BRNZ pair.
        write_instruction('h2000, {5'h18, 5'd4, 5'd28, 5'd29, 12'd0}); // add  r4, r28, r29
        write_instruction('h2004, {5'h1a, 5'd5, 5'd29, 5'd28, 12'd0}); // sub  r5, r29, r28
        write_instruction('h2008, {5'h10, 5'd6, 5'd0,  5'd0,  12'd0}); // load r6, [0]
        write_instruction('h200c, {5'h14, 5'd7, 5'd1,  5'd2,  12'd0}); // fadd r7, r1, r2
        write_instruction('h2010, {5'h18, 5'd8, 5'd4,  5'd6,  12'd0}); // add  r8, r4, r6
        write_instruction('h2014, {5'h10, 5'd9, 5'd0,  5'd0,  12'd8}); // load r9, [8]
        write_instruction('h2018, {5'h15, 5'd10,5'd7,  5'd3,  12'd0}); // fsub r10, r7, r3
        write_instruction('h201c, {5'h18, 5'd11,5'd5,  5'd9,  12'd0}); // add  r11, r5, r9
        write_instruction('h2020, {5'h18, 5'd12,5'd8,  5'd11, 12'd0}); // add  r12, r8, r11
        write_instruction('h2024, {5'h13, 5'd0, 5'd12, 5'd0,  12'd16}); // store [16], r12
        write_instruction('h2028, {5'h10, 5'd13,5'd0,  5'd0,  12'd16}); // load r13, [16]
        write_instruction('h202c, {OP_SUBI, 5'd21,5'd0, 5'd0,  12'd1}); // subi r21, 1
        write_instruction('h2030, {OP_BRNZ, 5'd20,5'd21,5'd0,  12'd0}); // brnz r21, r20
        write_halt('h2034);

        run_until_halt();

        check("fp loop counter reaches zero", core.reg_file.registers[21], 64'd0);

        if (errors == 0)
            $display("All loop forwarding tests passed.");
        else
            $display("Loop forwarding tests failed with %0d errors.", errors);

        $finish;
    end
endmodule