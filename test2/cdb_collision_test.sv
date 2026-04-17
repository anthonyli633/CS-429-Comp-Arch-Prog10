`define MEM_SIZE 524288

// Unit test for CDB collision and register file priority
module cdb_collision_test;
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
            if (timeout >= 20000)
                $display("WARNING: timed out waiting for halt");
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
            for (i = 0; i < 64; i = i + 1)
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

    // Opcodes
    localparam OP_ADDI   = 5'h19;
    localparam OP_ADD    = 5'h18;
    localparam OP_MOV_L  = 5'h12;
    localparam OP_FADD   = 5'h14;
    localparam OP_HALT   = 5'h0f;

    initial begin
        clk = 0;
        errors = 0;

        $dumpfile("cdb_test.vcd");
        $dumpvars(0, cdb_collision_test);

        // =============================================================
        // TEST 1: Basic sequential writes using MOV_L (rd = L)
        // Expected: r1 should have the value from the LAST instruction
        // =============================================================
        $display("\n=== TEST 1: Sequential writes to same register ===");
        reset_core();
        // MOV_L r1, 10  -> r1 = 10
        write_instruction('h2000, {OP_MOV_L, 5'd1, 5'd0, 5'd0, 12'd10});
        // MOV_L r1, 20  -> r1 = 20
        write_instruction('h2004, {OP_MOV_L, 5'd1, 5'd0, 5'd0, 12'd20});
        // MOV_L r1, 30  -> r1 = 30
        write_instruction('h2008, {OP_MOV_L, 5'd1, 5'd0, 5'd0, 12'd30});
        write_halt('h200c);
        run_until_halt();
        check("Sequential: r1 should be 30", core.reg_file.registers[1], 64'd30);

        // =============================================================
        // TEST 2: Two instructions with WAW using MOV_L
        // (They should NOT dual-issue, second should win)
        // =============================================================
        $display("\n=== TEST 2: WAW hazard prevents dual-issue ===");
        reset_core();
        // MOV_L r5, 1   -> r5 = 1
        // MOV_L r5, 2   -> r5 = 2 (WAW with above, should not dual-issue)
        // Expected: r5 = 2 (second instruction wins)
        write_instruction('h2000, {OP_MOV_L, 5'd5, 5'd0, 5'd0, 12'd1});
        write_instruction('h2004, {OP_MOV_L, 5'd5, 5'd0, 5'd0, 12'd2});
        write_halt('h2008);
        run_until_halt();
        check("WAW hazard: r5 should be 2 (second wins)", core.reg_file.registers[5], 64'd2);

        // =============================================================
        // TEST 3: Three independent instructions that can triple-issue
        // =============================================================
        $display("\n=== TEST 3: Triple-issue independent instructions ===");
        reset_core();
        // ADDI r1, r0, 100  -> r1 = 100
        // ADDI r2, r0, 200  -> r2 = 200
        // ADDI r3, r0, 300  -> r3 = 300
        write_instruction('h2000, {OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd100});
        write_instruction('h2004, {OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd200});
        write_instruction('h2008, {OP_ADDI, 5'd3, 5'd0, 5'd0, 12'd300});
        write_halt('h200c);
        run_until_halt();
        check("Triple-issue: r1", core.reg_file.registers[1], 64'd100);
        check("Triple-issue: r2", core.reg_file.registers[2], 64'd200);
        check("Triple-issue: r3", core.reg_file.registers[3], 64'd300);

        // =============================================================
        // TEST 4: FPU followed by ADDI to same register (scoreboard test)
        // The ADDI should wait for FPU to complete, then overwrite
        // =============================================================
        $display("\n=== TEST 4: FPU then ADDI to same register ===");
        reset_core();
        core.reg_file.registers[10] = 64'h3FF0000000000000; // 1.0
        core.reg_file.registers[11] = 64'h4000000000000000; // 2.0
        // FADD r5, r10, r11  -> r5 = 1.0 + 2.0 = 3.0 (FPU, 5 cycles)
        write_instruction('h2000, {OP_FADD, 5'd5, 5'd10, 5'd11, 12'd0});
        // ADDI r5, r0, 42    -> r5 = r0 + 42 = 42 (should wait for FADD, then overwrite)
        write_instruction('h2004, {OP_ADDI, 5'd5, 5'd0, 5'd0, 12'd42});
        write_halt('h2008);
        run_until_halt();
        // r5 should be 42 because ADDI comes after FADD in program order
        check("FPU then ADDI: r5 should be 42", core.reg_file.registers[5], 64'd42);

        // =============================================================
        // TEST 5: Two FPU ops to different registers (should both complete)
        // =============================================================
        $display("\n=== TEST 5: Two FPU ops to different registers ===");
        reset_core();
        core.reg_file.registers[10] = 64'h3FF0000000000000; // 1.0
        core.reg_file.registers[11] = 64'h4000000000000000; // 2.0
        // FADD r6, r10, r11  -> r6 = 3.0
        // FADD r7, r10, r11  -> r7 = 3.0
        write_instruction('h2000, {OP_FADD, 5'd6, 5'd10, 5'd11, 12'd0});
        write_instruction('h2004, {OP_FADD, 5'd7, 5'd10, 5'd11, 12'd0});
        write_halt('h2008);
        run_until_halt();
        check("Two FPU: r6", core.reg_file.registers[6], 64'h4008000000000000); // 3.0
        check("Two FPU: r7", core.reg_file.registers[7], 64'h4008000000000000); // 3.0

        // =============================================================
        // TEST 6: FPU op followed by overwrite with 0
        // This mimics the cdb_collision test scenario
        // =============================================================
        $display("\n=== TEST 6: FPU op then overwrite with 0 ===");
        reset_core();
        core.reg_file.registers[10] = 64'h3FF0000000000000; // 1.0
        core.reg_file.registers[11] = 64'h4000000000000000; // 2.0
        // FADD r21, r10, r11  -> r21 = 3.0 (FPU, 5 cycles)
        write_instruction('h2000, {OP_FADD, 5'd21, 5'd10, 5'd11, 12'd0});
        // MOV_L r21, 0        -> r21 = 0 (should overwrite FPU result)
        write_instruction('h2004, {OP_MOV_L, 5'd21, 5'd0, 5'd0, 12'd0});
        write_halt('h2008);
        run_until_halt();
        check("FPU then 0: r21 should be 0", core.reg_file.registers[21], 64'd0);

        // =============================================================
        // Summary
        // =============================================================
        $display("\n=============================================================");
        if (errors == 0) begin
            $display("All tests passed!");
        end else begin
            $display("FAILED: %0d errors", errors);
        end
        $display("=============================================================\n");

        $finish;
    end
endmodule