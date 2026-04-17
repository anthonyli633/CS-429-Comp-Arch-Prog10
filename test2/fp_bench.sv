`define MEM_SIZE 524288

module fp_bench;
    reg clk, reset;
    integer addr;
    integer errors;

    tinker_core core(
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    task run_until_halt_count;
        output integer cycles;
        integer timeout;
        begin
            cycles = 0;
            timeout = 0;
            while (!core.hlt && timeout < 50000) begin
                @(posedge clk);
                cycles = cycles + 1;
                timeout = timeout + 1;
            end
            #1;
            if (timeout >= 50000) begin
                $display("WARNING: timed out waiting for halt");
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
            @(posedge clk);
            @(posedge clk);
            reset = 0;
            #1;
            addr = 'h2000;
            for (i = 0; i < 32; i = i + 1)
                core.reg_file.registers[i] = 64'b0;
            core.reg_file.registers[31] = `MEM_SIZE;
            for (i = 0; i < 1024; i = i + 1)
                core.memory.bytes['h2000 + i] = 8'h0;
        end
    endtask

    task print_metric;
        input [255:0] name;
        input integer cycles;
        input integer instructions;
        real cpi;
        begin
            cpi = cycles;
            cpi = cpi / instructions;
            $display("BENCH %-24s cycles=%0d instr=%0d cpi=%0f", name, cycles, instructions, cpi);
        end
    endtask

    initial begin : run_benches
        integer cycles;
        integer i;
        reg [4:0] rd_tmp, rs_tmp, rt_tmp;
        reg [4:0] base_rd;
        reg [4:0] rd0_tmp, rd1_tmp, rd2_tmp, rs0_tmp, rs1_tmp, rs2_tmp, rt0_tmp, rt1_tmp, rt2_tmp;

        clk = 0;
        reset = 0;
        errors = 0;

        $display("FP benchmark sweep starting");

        // -------------------------------------------------------------
        // Independent FADD stream: should approach 3-wide throughput.
        // -------------------------------------------------------------
        reset_core();
        for (i = 0; i < 24; i = i + 1)
            core.reg_file.registers[i + 1] = $realtobits(i + 1.0);
        for (i = 0; i < 12; i = i + 1) begin
            rd_tmp = i[4:0];
            rs_tmp = (i + 1);
            rt_tmp = (i + 2);
            write_instruction(addr + i * 4, {5'h14, rd_tmp, rs_tmp, rt_tmp, 12'b0});
        end
        write_halt(addr + 48);
        run_until_halt_count(cycles);
        print_metric("12 independent fadd", cycles, 12);

        // -------------------------------------------------------------
        // Independent FMUL stream: same issue pattern, different op.
        // -------------------------------------------------------------
        reset_core();
        for (i = 0; i < 24; i = i + 1)
            core.reg_file.registers[i + 1] = $realtobits(i + 2.0);
        for (i = 0; i < 12; i = i + 1) begin
            rd_tmp = i[4:0];
            rs_tmp = (i + 1);
            rt_tmp = (i + 2);
            write_instruction(addr + i * 4, {5'h16, rd_tmp, rs_tmp, rt_tmp, 12'b0});
        end
        write_halt(addr + 48);
        run_until_halt_count(cycles);
        print_metric("12 independent fmul", cycles, 12);

        // -------------------------------------------------------------
        // Mixed 3-wide groups: FADD/FMUL/FADD in each fetch group.
        // -------------------------------------------------------------
        reset_core();
        for (i = 0; i < 24; i = i + 1)
            core.reg_file.registers[i + 1] = $realtobits(i + 1.5);
        for (i = 0; i < 4; i = i + 1) begin
            base_rd = i * 3;
            rd0_tmp = base_rd;
            rd1_tmp = base_rd + 1;
            rd2_tmp = base_rd + 2;
            rs0_tmp = base_rd + 1;
            rt0_tmp = base_rd + 2;
            rs1_tmp = base_rd + 3;
            rt1_tmp = base_rd + 4;
            rs2_tmp = base_rd + 5;
            rt2_tmp = base_rd + 6;
            write_instruction(addr + (i * 12) + 0, {5'h14, rd0_tmp, rs0_tmp, rt0_tmp, 12'b0});
            write_instruction(addr + (i * 12) + 4, {5'h16, rd1_tmp, rs1_tmp, rt1_tmp, 12'b0});
            write_instruction(addr + (i * 12) + 8, {5'h14, rd2_tmp, rs2_tmp, rt2_tmp, 12'b0});
        end
        write_halt(addr + 48);
        run_until_halt_count(cycles);
        print_metric("4 mixed fp triplets", cycles, 12);

        // -------------------------------------------------------------
        // Dependency chain: measures true latency when throughput cannot help.
        // -------------------------------------------------------------
        reset_core();
        core.reg_file.registers[1] = $realtobits(1.0);
        core.reg_file.registers[2] = $realtobits(2.0);
        for (i = 0; i < 8; i = i + 1)
            write_instruction(addr + i * 4, {5'h14, 5'd1, 5'd1, 5'd2, 12'b0});
        write_halt(addr + 32);
        run_until_halt_count(cycles);
        print_metric("8-deep fadd chain", cycles, 8);

        // -------------------------------------------------------------
        // Divide blocks a lane much longer: useful upper bound reference.
        // -------------------------------------------------------------
        reset_core();
        for (i = 0; i < 12; i = i + 1) begin
            core.reg_file.registers[i + 8] = $realtobits((i + 8.0) * 2.0);
            core.reg_file.registers[i + 20] = $realtobits(2.0);
        end
        for (i = 0; i < 6; i = i + 1) begin
            rd_tmp = i[4:0];
            rs_tmp = i + 8;
            rt_tmp = i + 20;
            write_instruction(addr + i * 4, {5'h17, rd_tmp, rs_tmp, rt_tmp, 12'b0});
        end
        write_halt(addr + 24);
        run_until_halt_count(cycles);
        print_metric("6 independent fdiv", cycles, 6);

        if (errors == 0)
            $display("FP benchmark sweep done");
        else
            $display("FP benchmark sweep finished with %0d errors", errors);

        $finish;
    end
endmodule