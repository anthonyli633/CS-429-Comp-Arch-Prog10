`define MEM_SIZE 524288

module tinker_core_test;
    reg clk, reset;
    integer addr;
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

    task run_until_halt_count;
        output integer cycles;
        integer timeout;
        begin
            cycles = 0;
            timeout = 0;
            while (!core.hlt && timeout < 20000) begin
                @(posedge clk);
                cycles = cycles + 1;
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
            addr = 64'h2000;
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
                $display("FAIL: %0s | got=%h expected=%h", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", name);
            end
        end
    endtask

    task check_float;
        input [255:0] name;
        input [63:0] got;
        input [63:0] expected_bits;
        input [63:0] tolerance_bits;
        begin
            if (got > expected_bits + tolerance_bits || got + tolerance_bits < expected_bits) begin
                $display("FAIL: %0s | got=%h expected=%h", name, got, expected_bits);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", name);
            end
        end
    endtask

    task check_mem_byte;
        input [255:0] name;
        input [63:0] address;
        input [7:0] expected;
        begin
            if (core.memory.bytes[address] !== expected) begin
                $display("FAIL: %0s | mem[%h]=%h expected=%h", name, address, core.memory.bytes[address], expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", name);
            end
        end
    endtask

    task check_le;
        input [255:0] name;
        input integer got;
        input integer expected_max;
        begin
            if (got > expected_max) begin
                $display("FAIL: %0s | got=%0d expected<=%0d", name, got, expected_max);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", name);
            end
        end
    endtask

    initial begin
        clk = 0;
        errors = 0;

        $dumpfile("test.vcd");
        $dumpvars(0, tinker_core_test);

        // =============================================================
        // ADD: rd = rs + rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'd10;
        core.reg_file.registers[3] = 64'd20;
        write_instruction(addr,     {5'h18, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("add 10+20", core.reg_file.registers[1], 64'd30);

        reset_core();
        core.reg_file.registers[2] = -64'd5;
        core.reg_file.registers[3] = 64'd15;
        write_instruction(addr,     {5'h18, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("add neg+pos", core.reg_file.registers[1], 64'd10);

        // =============================================================
        // ADDI: rd = rd + L
        // =============================================================
        reset_core();
        core.reg_file.registers[1] = 64'd10;
        write_instruction(addr,     {5'h19, 5'd1, 5'd0, 5'd0, 12'd5});
        write_halt(addr + 4);
        run_until_halt();
        check("addi 10+5", core.reg_file.registers[1], 64'd15);

        reset_core();
        core.reg_file.registers[1] = 64'd1;
        write_instruction(addr,     {5'h19, 5'd1, 5'd0, 5'd0, 12'hFFF});
        write_halt(addr + 4);
        run_until_halt();
        check("addi max L", core.reg_file.registers[1], 64'd4096);

        // =============================================================
        // SUB: rd = rs - rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'd30;
        core.reg_file.registers[3] = 64'd10;
        write_instruction(addr,     {5'h1a, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("sub 30-10", core.reg_file.registers[1], 64'd20);

        reset_core();
        core.reg_file.registers[2] = 64'd3;
        core.reg_file.registers[3] = 64'd10;
        write_instruction(addr,     {5'h1a, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("sub neg result", core.reg_file.registers[1], -64'd7);

        // =============================================================
        // SUBI: rd = rd - L
        // =============================================================
        reset_core();
        core.reg_file.registers[1] = 64'd10;
        write_instruction(addr,     {5'h1b, 5'd1, 5'd0, 5'd0, 12'd3});
        write_halt(addr + 4);
        run_until_halt();
        check("subi 10-3", core.reg_file.registers[1], 64'd7);

        // =============================================================
        // MUL: rd = rs * rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'd6;
        core.reg_file.registers[3] = 64'd7;
        write_instruction(addr,     {5'h1c, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("mul 6*7", core.reg_file.registers[1], 64'd42);

        reset_core();
        core.reg_file.registers[2] = -64'd3;
        core.reg_file.registers[3] = 64'd7;
        write_instruction(addr,     {5'h1c, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("mul neg*pos", core.reg_file.registers[1], -64'd21);

        // =============================================================
        // DIV: rd = rs / rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'd42;
        core.reg_file.registers[3] = 64'd6;
        write_instruction(addr,     {5'h1d, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("div 42/6", core.reg_file.registers[1], 64'd7);

        reset_core();
        core.reg_file.registers[2] = 64'd7;
        core.reg_file.registers[3] = 64'd2;
        write_instruction(addr,     {5'h1d, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("div truncate", core.reg_file.registers[1], 64'd3);

        // =============================================================
        // AND: rd = rs & rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'hFF;
        core.reg_file.registers[3] = 64'h0F;
        write_instruction(addr,     {5'h00, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("and", core.reg_file.registers[1], 64'h0F);

        // =============================================================
        // OR: rd = rs | rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'hF0;
        core.reg_file.registers[3] = 64'h0F;
        write_instruction(addr,     {5'h01, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("or", core.reg_file.registers[1], 64'hFF);

        // =============================================================
        // XOR: rd = rs ^ rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'hFF;
        core.reg_file.registers[3] = 64'h0F;
        write_instruction(addr,     {5'h02, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("xor", core.reg_file.registers[1], 64'hF0);

        // =============================================================
        // NOT: rd = ~rs
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'h0;
        write_instruction(addr,     {5'h03, 5'd1, 5'd2, 5'd0, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("not 0", core.reg_file.registers[1], 64'hFFFFFFFFFFFFFFFF);

        // =============================================================
        // SHFTR: rd = rs >> rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'hFF;
        core.reg_file.registers[3] = 64'd4;
        write_instruction(addr,     {5'h04, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("shftr", core.reg_file.registers[1], 64'hF);

        // =============================================================
        // SHFTRI: rd = rd >> L
        // =============================================================
        reset_core();
        core.reg_file.registers[1] = 64'hFF00;
        write_instruction(addr,     {5'h05, 5'd1, 5'd0, 5'd0, 12'd8});
        write_halt(addr + 4);
        run_until_halt();
        check("shftri", core.reg_file.registers[1], 64'hFF);

        // =============================================================
        // SHFTL: rd = rs << rt
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'h1;
        core.reg_file.registers[3] = 64'd4;
        write_instruction(addr,     {5'h06, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("shftl", core.reg_file.registers[1], 64'h10);

        // =============================================================
        // SHFTLI: rd = rd << L
        // =============================================================
        reset_core();
        core.reg_file.registers[1] = 64'hFF;
        write_instruction(addr,     {5'h07, 5'd1, 5'd0, 5'd0, 12'd8});
        write_halt(addr + 4);
        run_until_halt();
        check("shftli", core.reg_file.registers[1], 64'hFF00);

        // =============================================================
        // MOV rd, rs (0x11)
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = 64'd42;
        write_instruction(addr,     {5'h11, 5'd1, 5'd2, 5'd0, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("mov reg", core.reg_file.registers[1], 64'd42);

        // =============================================================
        // MOV rd, L (0x12)
        // =============================================================
        reset_core();
        write_instruction(addr,     {5'h12, 5'd1, 5'd0, 5'd0, 12'hABC});
        write_halt(addr + 4);
        run_until_halt();
        check("mov L", core.reg_file.registers[1], {52'b0, 12'hABC});

        // =============================================================
        // BR rd (0x08)
        // =============================================================
        reset_core();
        core.reg_file.registers[1] = 64'd0;
        core.reg_file.registers[3] = 64'd77;
        core.reg_file.registers[5] = addr + 8;
        write_instruction(addr,      {5'h08, 5'd5, 5'd0, 5'd0, 12'b0});
        write_instruction(addr + 4,  {5'h18, 5'd1, 5'd0, 5'd3, 12'b0});
        write_halt(addr + 8);
        run_until_halt();
        check("br rd skip", core.reg_file.registers[1], 64'd0);

        // =============================================================
        // BRR rd (0x09)
        // =============================================================
        reset_core();
        core.reg_file.registers[4] = 64'd8;
        core.reg_file.registers[1] = 64'd0;
        core.reg_file.registers[3] = 64'd99;
        write_instruction(addr,      {5'h09, 5'd4, 5'd0, 5'd0, 12'b0});
        write_instruction(addr + 4,  {5'h18, 5'd1, 5'd0, 5'd3, 12'b0});
        write_halt(addr + 8);
        run_until_halt();
        check("brr rd skip", core.reg_file.registers[1], 64'd0);

        // =============================================================
        // BRR L (0x0a)
        // =============================================================
        reset_core();
        core.reg_file.registers[1] = 64'd55;
        write_instruction(addr,      {5'h0a, 5'd0, 5'd0, 5'd0, 12'd8});
        write_instruction(addr + 4,  {5'h19, 5'd1, 5'd0, 5'd0, 12'd0});
        write_halt(addr + 8);
        run_until_halt();
        check("brr L forward", core.reg_file.registers[1], 64'd55);

        // =============================================================
        // BRNZ (0x0b)
        // =============================================================

        // taken
        reset_core();
        core.reg_file.registers[1] = 64'd0;
        core.reg_file.registers[2] = 64'd1;
        core.reg_file.registers[6] = addr + 8;
        write_instruction(addr,      {5'h0b, 5'd6, 5'd2, 5'd0, 12'b0});
        write_instruction(addr + 4,  {5'h19, 5'd1, 5'd0, 5'd0, 12'd1});
        write_halt(addr + 8);
        run_until_halt();
        check("brnz taken", core.reg_file.registers[1], 64'd0);

        // not taken
        reset_core();
        core.reg_file.registers[1] = 64'd0;
        core.reg_file.registers[2] = 64'd0;
        core.reg_file.registers[3] = 64'd5;
        write_instruction(addr,      {5'h0b, 5'd6, 5'd2, 5'd0, 12'b0});
        write_instruction(addr + 4,  {5'h18, 5'd1, 5'd0, 5'd3, 12'b0});
        write_halt(addr + 8);
        run_until_halt();
        check("brnz not taken", core.reg_file.registers[1], 64'd5);

        // negative nonzero
        reset_core();
        core.reg_file.registers[1] = 64'd0;
        core.reg_file.registers[2] = -64'd1;
        core.reg_file.registers[6] = addr + 8;
        write_instruction(addr,      {5'h0b, 5'd6, 5'd2, 5'd0, 12'b0});
        write_instruction(addr + 4,  {5'h19, 5'd1, 5'd0, 5'd0, 12'd1});
        write_halt(addr + 8);
        run_until_halt();
        check("brnz neg nonzero", core.reg_file.registers[1], 64'd0);

        // =============================================================
        // BRGT (0x0e)
        // =============================================================
        reset_core();
        core.reg_file.registers[1] = 64'd100;
        core.reg_file.registers[2] = addr + 8;
        write_instruction(addr,      {5'h0e, 5'd2, 5'd1, 5'd0, 12'b0});
        write_instruction(addr + 4,  {5'h19, 5'd1, 5'd0, 5'd0, 12'd1});
        write_halt(addr + 8);
        run_until_halt();
        check("brgt taken", core.reg_file.registers[1], 64'd100);

        reset_core();
        core.reg_file.registers[1] = -64'd5;
        core.reg_file.registers[3] = 64'd99;
        write_instruction(addr,      {5'h0e, 5'd1, 5'd0, 5'd0, 12'b0});
        write_instruction(addr + 4,  {5'h18, 5'd1, 5'd0, 5'd3, 12'b0});
        write_halt(addr + 8);
        run_until_halt();
        check("brgt not taken", core.reg_file.registers[1], 64'd99);

        // =============================================================
        // LOAD (0x10)
        // =============================================================
        reset_core();
        begin : load_blk
            integer i;
            for (i = 0; i < 8; i = i + 1)
                core.memory.bytes['h3000 + i] = 8'h00;
        end
        core.memory.bytes['h3000] = 8'hAB;
        core.reg_file.registers[2] = 64'h3000;
        write_instruction(addr,     {5'h10, 5'd1, 5'd2, 5'd0, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("load", core.reg_file.registers[1], 64'hAB);

        // load with offset
        reset_core();
        begin : load_off_blk
            integer i;
            for (i = 0; i < 8; i = i + 1)
                core.memory.bytes['h6000 + i] = 8'h00;
        end
        core.memory.bytes['h6000] = 8'hFF;
        core.reg_file.registers[2] = 64'h5FF0;
        write_instruction(addr,     {5'h10, 5'd1, 5'd2, 5'd0, 12'd16});
        write_halt(addr + 4);
        run_until_halt();
        check("load offset", core.reg_file.registers[1], 64'hFF);

        // =============================================================
        // STORE + LOAD roundtrip (0x13 + 0x10)
        // =============================================================
        reset_core();
        core.reg_file.registers[1] = 64'h5000;
        core.reg_file.registers[2] = 64'h12345678;
        write_instruction(addr,      {5'h13, 5'd1, 5'd2, 5'd0, 12'd0});
        write_instruction(addr + 4,  {5'h10, 5'd3, 5'd1, 5'd0, 12'd0});
        write_halt(addr + 8);
        run_until_halt();
        check("store+load roundtrip", core.reg_file.registers[3], 64'h12345678);

        // =============================================================
        // CALL (0x0c)
        // =============================================================
        reset_core();
        core.reg_file.registers[5] = addr + 8;
        write_instruction(addr,      {5'h0c, 5'd5, 5'd0, 5'd0, 12'b0});
        write_halt(addr + 8);
        run_until_halt();
        check("call r31", core.reg_file.registers[31], `MEM_SIZE);

        // =============================================================
        // RETURN (0x0d)
        // =============================================================
        reset_core();
        core.reg_file.registers[31] = `MEM_SIZE;
        begin : ret_setup
            integer i;
            reg [63:0] ret_addr;
            ret_addr = addr + 8;
            for (i = 0; i < 8; i = i + 1)
                core.memory.bytes[`MEM_SIZE - 8 + i] = ret_addr[8*i +: 8];
        end
        write_instruction(addr,      {5'h0d, 5'd0, 5'd0, 5'd0, 12'b0});
        write_halt(addr + 8);
        run_until_halt();
        check("return r31", core.reg_file.registers[31], `MEM_SIZE);

        // =============================================================
        // CALL + RETURN roundtrip
        // =============================================================
        reset_core();
        core.reg_file.registers[5] = addr + 8;
        write_instruction(addr,      {5'h0c, 5'd5, 5'd0, 5'd0, 12'b0});
        write_instruction(addr + 8,  {5'h0d, 5'd0, 5'd0, 5'd0, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("call+return r31", core.reg_file.registers[31], `MEM_SIZE);

        // =============================================================
        // HALT (0x0f)
        // =============================================================
        reset_core();
        write_halt(addr);
        run_until_halt();
        check("halt", core.hlt, 1);

        // =============================================================
        // FADD (0x14)
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = $realtobits(2.0);
        core.reg_file.registers[3] = $realtobits(3.0);
        write_instruction(addr,     {5'h14, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check_float("fadd 2+3", core.reg_file.registers[1], $realtobits(5.0), 64'd2);

        // =============================================================
        // FSUB (0x15)
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = $realtobits(5.5);
        core.reg_file.registers[3] = $realtobits(2.25);
        write_instruction(addr,     {5'h15, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check_float("fsub 5.5-2.25", core.reg_file.registers[1], $realtobits(3.25), 64'd2);

        // =============================================================
        // FMUL (0x16)
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = $realtobits(3.0);
        core.reg_file.registers[3] = $realtobits(4.0);
        write_instruction(addr,     {5'h16, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check_float("fmul 3*4", core.reg_file.registers[1], $realtobits(12.0), 64'd2);

        reset_core();
        core.reg_file.registers[2] = 64'h7FF0000000000000;
        core.reg_file.registers[3] = 64'h0;
        write_instruction(addr,     {5'h16, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("fmul inf*0=NaN", core.reg_file.registers[1], 64'h7FF8000000000000);

        // =============================================================
        // FDIV (0x17)
        // =============================================================
        reset_core();
        core.reg_file.registers[2] = $realtobits(6.0);
        core.reg_file.registers[3] = $realtobits(2.0);
        write_instruction(addr,     {5'h17, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check_float("fdiv 6/2", core.reg_file.registers[1], $realtobits(3.0), 64'd2);

        reset_core();
        core.reg_file.registers[2] = 64'h0;
        core.reg_file.registers[3] = 64'h0;
        write_instruction(addr,     {5'h17, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("fdiv 0/0=NaN", core.reg_file.registers[1], 64'h7FF8000000000000);

        reset_core();
        core.reg_file.registers[2] = $realtobits(5.0);
        core.reg_file.registers[3] = 64'h0;
        write_instruction(addr,     {5'h17, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("fdiv x/0=+inf", core.reg_file.registers[1], 64'h7FF0000000000000);

        reset_core();
        core.reg_file.registers[2] = $realtobits(1.0);
        core.reg_file.registers[3] = $realtobits(3.0);
        write_instruction(addr,     {5'h17, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check_float("fdiv 1/3", core.reg_file.registers[1], $realtobits(0.333333333333333), 64'd16);

        reset_core();
        core.reg_file.registers[2] = $realtobits(4.0);
        core.reg_file.registers[3] = $realtobits(3.0);
        write_instruction(addr,     {5'h17, 5'd1, 5'd2, 5'd3, 12'b0});
        write_halt(addr + 4);
        run_until_halt();
        check("fdiv 4/3 exact bits", core.reg_file.registers[1], 64'd4608683618675807573);

        // =============================================================
        // Multi-instruction sequence
        // =============================================================
        reset_core();
        write_instruction(addr,      {5'h12, 5'd1, 5'd0, 5'd0, 12'd10});
        write_instruction(addr + 4,  {5'h12, 5'd2, 5'd0, 5'd0, 12'd20});
        write_instruction(addr + 8,  {5'h18, 5'd3, 5'd1, 5'd2, 12'b0});
        write_halt(addr + 12);
        run_until_halt();
        check("multi: r1", core.reg_file.registers[1], 64'd10);
        check("multi: r2", core.reg_file.registers[2], 64'd20);
        check("multi: r3=r1+r2", core.reg_file.registers[3], 64'd30);

        // =============================================================
        // Branch prediction tests
        // These verify correctness in the presence of branch prediction;
        // they pass whether prediction is accurate or not, but exercise
        // the misprediction-recovery path.
        // =============================================================

        // ----- brnz backward loop (BHT warm-up + last-iteration mispredict) -----
        // Program: r1=5 (counter), r2=0 (sum). Loop: r2++, r1--; brnz back. Halt.
        // Expected after loop: r2=5, r1=0.
        reset_core();
        core.reg_file.registers[1] = 64'd5;     // loop counter
        core.reg_file.registers[2] = 64'd0;     // accumulator
        core.reg_file.registers[3] = addr;      // branch target = start of loop (0x2000)
        // 0x2000: addi r2, r2, 1
        write_instruction(addr,      {5'h19, 5'd2, 5'd0, 5'd0, 12'd1});
        // 0x2004: subi r1, r1, 1
        write_instruction(addr + 4,  {5'h1b, 5'd1, 5'd0, 5'd0, 12'd1});
        // 0x2008: brnz r3, r1  (jump to r3 if r1 != 0)
        write_instruction(addr + 8,  {5'h0b, 5'd3, 5'd1, 5'd0, 12'b0});
        // 0x200C: halt
        write_halt(addr + 12);
        run_until_halt();
        check("bp: brnz loop r2=5", core.reg_file.registers[2], 64'd5);
        check("bp: brnz loop r1=0", core.reg_file.registers[1], 64'd0);

        // ----- brgt backward loop -----
        // r1=4 (counter, must be > r2=0 to keep looping), r3=0 (sum), r4=loop target.
        // Loop: r3 += r1; r1--; brgt r4, r1, r0 (if r1>0 jump). Halt.
        // Expected: r3 = 4+3+2+1 = 10, r1 = 0.
        reset_core();
        core.reg_file.registers[1] = 64'd4;     // counter
        core.reg_file.registers[2] = 64'd0;     // rt for brgt (compare r1 > r2 = r1 > 0)
        core.reg_file.registers[3] = 64'd0;     // accumulator
        core.reg_file.registers[4] = addr;      // branch target
        // 0x2000: add r3, r3, r1  (r3 += r1)
        write_instruction(addr,      {5'h18, 5'd3, 5'd3, 5'd1, 12'b0});
        // 0x2004: subi r1, r1, 1
        write_instruction(addr + 4,  {5'h1b, 5'd1, 5'd0, 5'd0, 12'd1});
        // 0x2008: brgt r4, r1, r2 (jump to r4 if r1 > r2 = if r1 > 0)
        write_instruction(addr + 8,  {5'h0e, 5'd4, 5'd1, 5'd2, 12'b0});
        // 0x200C: halt
        write_halt(addr + 12);
        run_until_halt();
        check("bp: brgt loop r3=10", core.reg_file.registers[3], 64'd10);
        check("bp: brgt loop r1=0",  core.reg_file.registers[1], 64'd0);

        // ----- consecutive forward branches (both predicted not-taken first, then taken) -----
        // Two BRR_L instructions each skipping one instruction.
        // On first run: both not predicted (BTB cold) → mispredict → flush → correct result.
        // r1 and r2 must stay 0 (the skipped stores never execute).
        reset_core();
        core.reg_file.registers[1] = 64'd0;
        core.reg_file.registers[2] = 64'd0;
        // 0x2000: brr L=+8  (skip next instruction, jump to 0x200C)
        write_instruction(addr,      {5'h0a, 5'd0, 5'd0, 5'd0, 12'd8});
        // 0x2004: mov r1, ?, 99  (should be skipped)
        write_instruction(addr + 4,  {5'h12, 5'd1, 5'd0, 5'd0, 12'd99});
        // 0x2008: brr L=+8  (skip next instruction, jump to 0x2014)
        write_instruction(addr + 8,  {5'h0a, 5'd0, 5'd0, 5'd0, 12'd8});
        // 0x200C: mov r2, ?, 88  (should be skipped)
        write_instruction(addr + 12, {5'h12, 5'd2, 5'd0, 5'd0, 12'd88});
        // 0x2010: halt
        write_halt(addr + 16);
        run_until_halt();
        check("bp: fwd branch r1=0", core.reg_file.registers[1], 64'd0);
        check("bp: fwd branch r2=0", core.reg_file.registers[2], 64'd0);

        // ----- call + return with prediction -----
        // CALL at addr → jumps to r5=addr+12, saves ret_addr=addr+4 to mem[r31-8].
        // RETURN at addr+12 → reads mem[r31-8]=addr+4, jumps there.
        // HALT at addr+4 ends execution. r31 must remain MEM_SIZE throughout.
        reset_core();
        core.reg_file.registers[5] = addr + 12;
        write_instruction(addr,      {5'h0c, 5'd5, 5'd0, 5'd0, 12'b0});  // call r5
        write_halt(addr + 4);                                              // return destination
        write_halt(addr + 8);                                              // padding (unreachable)
        write_instruction(addr + 12, {5'h0d, 5'd0, 5'd0, 5'd0, 12'b0});  // return
        run_until_halt();
        check("bp: call+ret r31", core.reg_file.registers[31], `MEM_SIZE);

        // =============================================================
        // Phase 10: Triple-issue (3-wide superscalar) tests
        // =============================================================

        // ---- 3 independent ADDIs → should triple-issue in one cycle ----
        // No RAW/WAW hazards: each reads/writes a distinct register.
        reset_core();
        write_instruction(addr,      {5'h19, 5'd1, 5'd0, 5'd0, 12'd10});  // addi r1, 10
        write_instruction(addr + 4,  {5'h19, 5'd2, 5'd0, 5'd0, 12'd20});  // addi r2, 20
        write_instruction(addr + 8,  {5'h19, 5'd3, 5'd0, 5'd0, 12'd30});  // addi r3, 30
        write_halt(addr + 12);
        run_until_halt();
        check("triple: r1=10", core.reg_file.registers[1], 64'd10);
        check("triple: r2=20", core.reg_file.registers[2], 64'd20);
        check("triple: r3=30", core.reg_file.registers[3], 64'd30);

        // ---- 3 independent ALU ops, then use all results ----
        // A: add r1=5+7=12,  B: add r2=3*4=12 (mul),  C: and r3=0xFF&0x0F=0x0F
        // Then A: add r4=r1+r2=24,  halt
        reset_core();
        core.reg_file.registers[5] = 64'd5;
        core.reg_file.registers[6] = 64'd7;
        core.reg_file.registers[7] = 64'd3;
        core.reg_file.registers[8] = 64'd4;
        core.reg_file.registers[9] = 64'hFF;
        core.reg_file.registers[10] = 64'h0F;
        write_instruction(addr,      {5'h18, 5'd1, 5'd5, 5'd6, 12'b0});  // add  r1 = r5+r6 = 12
        write_instruction(addr + 4,  {5'h1c, 5'd2, 5'd7, 5'd8, 12'b0});  // mul  r2 = r7*r8 = 12
        write_instruction(addr + 8,  {5'h00, 5'd3, 5'd9, 5'd10, 12'b0}); // and  r3 = r9&r10 = 0x0F
        write_instruction(addr + 12, {5'h18, 5'd4, 5'd1, 5'd2, 12'b0});  // add  r4 = r1+r2 (RAW on r1,r2 → no triple with prev)
        write_halt(addr + 16);
        run_until_halt();
        check("triple alu: r1=12",   core.reg_file.registers[1], 64'd12);
        check("triple alu: r2=12",   core.reg_file.registers[2], 64'd12);
        check("triple alu: r3=0x0F", core.reg_file.registers[3], 64'h0F);
        check("triple alu: r4=24",   core.reg_file.registers[4], 64'd24);

        // ---- triple-issue falls back to dual when C has a RAW on B ----
        // A: addi r1, 5   B: addi r2, 10   C: add r3 = r2+r1 (RAW on r1 and r2 from B)
        // C cannot triple-issue; A+B dual-issue, then C single-issues next cycle.
        reset_core();
        write_instruction(addr,      {5'h19, 5'd1, 5'd0, 5'd0, 12'd5});   // addi r1, 5
        write_instruction(addr + 4,  {5'h19, 5'd2, 5'd0, 5'd0, 12'd10});  // addi r2, 10
        write_instruction(addr + 8,  {5'h18, 5'd3, 5'd1, 5'd2, 12'b0});   // add  r3 = r1+r2
        write_halt(addr + 12);
        run_until_halt();
        check("triple fallback: r1=5",    core.reg_file.registers[1], 64'd5);
        check("triple fallback: r2=10",   core.reg_file.registers[2], 64'd10);
        check("triple fallback: r3=15",   core.reg_file.registers[3], 64'd15);

        // =============================================================
        // Phase 9: Scoreboard / out-of-order scheduling tests
        // =============================================================

        // ---- dependent consumer of FP result must wait until the result is written ----
        reset_core();
        core.reg_file.registers[2] = $realtobits(6.0);
        core.reg_file.registers[3] = $realtobits(2.0);
        write_instruction(addr,      {5'h17, 5'd1, 5'd2, 5'd3, 12'b0});  // fdiv r1 = 3.0
        write_instruction(addr + 4,  {5'h11, 5'd4, 5'd1, 5'd0, 12'b0});  // mov  r4 = r1 (must wait)
        write_halt(addr + 8);
        run_until_halt();
        check("scoreboard dep fp bits", core.reg_file.registers[4], $realtobits(3.0));

        // ---- independent integer work behind FDIV should overlap with the divide ----
        begin : ooo_cycles
            integer cycles;
            reset_core();
            core.reg_file.registers[2] = $realtobits(6.0);
            core.reg_file.registers[3] = $realtobits(2.0);
            write_instruction(addr,      {5'h17, 5'd1, 5'd2, 5'd3, 12'b0});   // long FP op
            write_instruction(addr + 4,  {5'h19, 5'd4, 5'd0, 5'd0, 12'd5});    // independent
            write_instruction(addr + 8,  {5'h19, 5'd5, 5'd0, 5'd0, 12'd7});    // independent
            write_instruction(addr + 12, {5'h18, 5'd6, 5'd4, 5'd5, 12'b0});    // uses integer results only
            write_instruction(addr + 16, {5'h19, 5'd7, 5'd0, 5'd0, 12'd9});    // more independent work
            write_halt(addr + 20);
            run_until_halt_count(cycles);
            check("scoreboard indep r6=12", core.reg_file.registers[6], 64'd12);
            check("scoreboard indep r7=9", core.reg_file.registers[7], 64'd9);
            check_le("scoreboard cycles bounded", cycles, 65);
        end

        // ---- launching an FP op must not inject an extra front-end bubble ----
        begin : fp_launch_overlap
            integer cycles;
            reset_core();
            core.reg_file.registers[10] = $realtobits(2.0);
            core.reg_file.registers[11] = $realtobits(3.0);
            write_instruction(addr,      {5'h14, 5'd1, 5'd10, 5'd11, 12'b0});  // fadd r1 = 5.0
            write_instruction(addr + 4,  {5'h19, 5'd4, 5'd0, 5'd0, 12'd5});    // independent
            write_instruction(addr + 8,  {5'h19, 5'd5, 5'd0, 5'd0, 12'd7});    // independent
            write_instruction(addr + 12, {5'h18, 5'd6, 5'd4, 5'd5, 12'b0});    // independent consumer
            write_halt(addr + 16);
            run_until_halt_count(cycles);
            check_float("fp launch overlap r1", core.reg_file.registers[1], $realtobits(5.0), 64'd2);
            check("fp launch overlap r6", core.reg_file.registers[6], 64'd12);
            check_le("fp launch overlap cycles", cycles, 14);
        end

        // ---- independent FP ops should stream through the fixed-latency pipe ----
        begin : fp_stream_overlap
            integer cycles;
            integer i;
            reg [4:0] rd_tmp, rs_tmp, rt_tmp;
            reset_core();
            for (i = 0; i < 24; i = i + 1)
                core.reg_file.registers[2 + i] = $realtobits(i + 1.0);
            for (i = 0; i < 12; i = i + 1) begin
                rd_tmp = i[4:0];
                rs_tmp = i + 2;
                rt_tmp = i + 3;
                write_instruction(addr + i * 4, {5'h14, rd_tmp, rs_tmp, rt_tmp, 12'b0});
            end
            write_halt(addr + 48);
            run_until_halt_count(cycles);
            check_float("fp stream r0", core.reg_file.registers[0], $realtobits(3.0), 64'd2);
            check_float("fp stream r1", core.reg_file.registers[1], $realtobits(5.0), 64'd2);
            check_float("fp stream r2", core.reg_file.registers[2], $realtobits(7.0), 64'd2);
            check_le("fp stream cycles", cycles, 17);
        end

        // ---- a divide blocked behind fixed-latency FP ops must stay live until launch ----
        reset_core();
        core.reg_file.registers[1] = $realtobits(1.0);
        core.reg_file.registers[2] = $realtobits(2.0);
        core.reg_file.registers[3] = $realtobits(3.0);
        core.reg_file.registers[4] = $realtobits(4.0);
        write_instruction(addr,      {5'h14, 5'd8,  5'd1, 5'd2, 12'b0});  // fadd = 3.0
        write_instruction(addr + 4,  {5'h14, 5'd9,  5'd1, 5'd2, 12'b0});  // fadd = 3.0
        write_instruction(addr + 8,  {5'h16, 5'd10, 5'd2, 5'd3, 12'b0});  // fmul = 6.0
        write_instruction(addr + 12, {5'h17, 5'd11, 5'd4, 5'd2, 12'b0});  // delayed fdiv = 2.0
        write_halt(addr + 16);
        run_until_halt();
        check_float("delayed fdiv survives stall", core.reg_file.registers[11], $realtobits(2.0), 64'd2);

        // ---- same delayed-divide case, but writing r31 like the benchmark does ----
        reset_core();
        core.reg_file.registers[1] = $realtobits(1.0);
        core.reg_file.registers[2] = $realtobits(2.0);
        core.reg_file.registers[3] = $realtobits(3.0);
        core.reg_file.registers[4] = $realtobits(4.0);
        write_instruction(addr,      {5'h14, 5'd8,  5'd1, 5'd2, 12'b0});
        write_instruction(addr + 4,  {5'h14, 5'd9,  5'd1, 5'd2, 12'b0});
        write_instruction(addr + 8,  {5'h16, 5'd10, 5'd2, 5'd3, 12'b0});
        write_instruction(addr + 12, {5'h17, 5'd31, 5'd4, 5'd2, 12'b0});  // delayed fdiv = 2.0 into r31
        write_halt(addr + 16);
        run_until_halt();
        check_float("delayed fdiv writes r31", core.reg_file.registers[31], $realtobits(2.0), 64'd2);

        // ---- if slot C is blocked by an FP dependency, it must stay in the window ----
        reset_core();
        core.reg_file.registers[6] = $realtobits(6.0);
        core.reg_file.registers[7] = $realtobits(2.0);
        write_instruction(addr,      {5'h17, 5'd1, 5'd6, 5'd7, 12'b0});   // A: fdiv r1 = 3.0
        write_instruction(addr + 4,  {5'h19, 5'd2, 5'd0, 5'd0, 12'd5});   // B: independent addi
        write_instruction(addr + 8,  {5'h11, 5'd3, 5'd1, 5'd0, 12'b0});   // C: mov r3 = r1 (blocked)
        write_instruction(addr + 12, {5'h19, 5'd4, 5'd0, 5'd0, 12'd9});   // next instruction after blocked C
        write_halt(addr + 16);
        run_until_halt();
        check("scoreboard keep blocked C r2", core.reg_file.registers[2], 64'd5);
        check("scoreboard keep blocked C r3", core.reg_file.registers[3], $realtobits(3.0));
        check("scoreboard keep blocked C r4", core.reg_file.registers[4], 64'd9);

        // =============================================================
        // Memory port conflict tests (1 read + 1 write port constraint)
        // =============================================================

        // ---- Two consecutive LOADs cannot dual-issue (must serialize) ----
        // LOAD r1 from addr1, LOAD r2 from addr2 — both need the single read port
        // Result: correct values, but takes more cycles than if dual-issued
        begin : mem_dual_load
            integer cycles;
            reset_core();
            // Set up two memory locations with different values
            core.memory.bytes['h3000] = 8'hAA;
            core.memory.bytes['h3001] = 8'h00;
            core.memory.bytes['h3002] = 8'h00;
            core.memory.bytes['h3003] = 8'h00;
            core.memory.bytes['h3004] = 8'h00;
            core.memory.bytes['h3005] = 8'h00;
            core.memory.bytes['h3006] = 8'h00;
            core.memory.bytes['h3007] = 8'h00;
            core.memory.bytes['h4000] = 8'hBB;
            core.memory.bytes['h4001] = 8'h00;
            core.memory.bytes['h4002] = 8'h00;
            core.memory.bytes['h4003] = 8'h00;
            core.memory.bytes['h4004] = 8'h00;
            core.memory.bytes['h4005] = 8'h00;
            core.memory.bytes['h4006] = 8'h00;
            core.memory.bytes['h4007] = 8'h00;
            core.reg_file.registers[10] = 64'h3000;
            core.reg_file.registers[11] = 64'h4000;
            write_instruction(addr,      {5'h10, 5'd1, 5'd10, 5'd0, 12'b0});  // load r1 = mem[r10]
            write_instruction(addr + 4,  {5'h10, 5'd2, 5'd11, 5'd0, 12'b0});  // load r2 = mem[r11]
            write_halt(addr + 8);
            run_until_halt_count(cycles);
            check("mem: dual load r1", core.reg_file.registers[1], 64'hAA);
            check("mem: dual load r2", core.reg_file.registers[2], 64'hBB);
        end

        // ---- Two consecutive STOREs cannot dual-issue (must serialize) ----
        begin : mem_dual_store
            integer cycles;
            reset_core();
            core.reg_file.registers[1] = 64'h1234;
            core.reg_file.registers[2] = 64'h5678;
            core.reg_file.registers[10] = 64'h5000;
            core.reg_file.registers[11] = 64'h6000;
            write_instruction(addr,      {5'h13, 5'd10, 5'd1, 5'd0, 12'b0});  // store mem[r10] = r1
            write_instruction(addr + 4,  {5'h13, 5'd11, 5'd2, 5'd0, 12'b0});  // store mem[r11] = r2
            write_halt(addr + 8);
            run_until_halt_count(cycles);
            // Verify both stores happened correctly
            check_mem_byte("mem: dual store @5000", 64'h5000, 8'h34);
            check_mem_byte("mem: dual store @5001", 64'h5001, 8'h12);
            check_mem_byte("mem: dual store @6000", 64'h6000, 8'h78);
            check_mem_byte("mem: dual store @6001", 64'h6001, 8'h56);
        end

        // ---- LOAD + ALU should still dual-issue ----
        begin : mem_load_alu_dual
            integer cycles;
            reset_core();
            core.memory.bytes['h3000] = 8'h10;
            core.memory.bytes['h3001] = 8'h00;
            core.memory.bytes['h3002] = 8'h00;
            core.memory.bytes['h3003] = 8'h00;
            core.memory.bytes['h3004] = 8'h00;
            core.memory.bytes['h3005] = 8'h00;
            core.memory.bytes['h3006] = 8'h00;
            core.memory.bytes['h3007] = 8'h00;
            core.reg_file.registers[10] = 64'h3000;
            core.reg_file.registers[5] = 64'd100;
            write_instruction(addr,      {5'h10, 5'd1, 5'd10, 5'd0, 12'b0});  // load r1 = mem[r10]
            write_instruction(addr + 4,  {5'h19, 5'd2, 5'd0, 5'd0, 12'd50});  // addi r2 = 50 (can dual-issue)
            write_halt(addr + 8);
            run_until_halt_count(cycles);
            check("mem: load+alu r1", core.reg_file.registers[1], 64'h10);
            check("mem: load+alu r2", core.reg_file.registers[2], 64'd50);
            // Should complete quickly since LOAD+ALU can dual-issue
            check_le("mem: load+alu cycles", cycles, 8);
        end

        // ---- STORE + ALU should still dual-issue ----
        begin : mem_store_alu_dual
            integer cycles;
            reset_core();
            core.reg_file.registers[1] = 64'hDEAD;
            core.reg_file.registers[10] = 64'h7000;
            write_instruction(addr,      {5'h13, 5'd10, 5'd1, 5'd0, 12'b0});  // store mem[r10] = r1
            write_instruction(addr + 4,  {5'h19, 5'd2, 5'd0, 5'd0, 12'd99});  // addi r2 = 99 (can dual-issue)
            write_halt(addr + 8);
            run_until_halt_count(cycles);
            check_mem_byte("mem: store+alu @7000", 64'h7000, 8'hAD);
            check_mem_byte("mem: store+alu @7001", 64'h7001, 8'hDE);
            check("mem: store+alu r2", core.reg_file.registers[2], 64'd99);
            // Should complete quickly since STORE+ALU can dual-issue
            check_le("mem: store+alu cycles", cycles, 8);
        end

        // ---- LOAD + STORE can dual-issue (different ports) ----
        begin : mem_load_store_dual
            integer cycles;
            reset_core();
            core.memory.bytes['h3000] = 8'h42;
            core.memory.bytes['h3001] = 8'h00;
            core.memory.bytes['h3002] = 8'h00;
            core.memory.bytes['h3003] = 8'h00;
            core.memory.bytes['h3004] = 8'h00;
            core.memory.bytes['h3005] = 8'h00;
            core.memory.bytes['h3006] = 8'h00;
            core.memory.bytes['h3007] = 8'h00;
            core.reg_file.registers[1] = 64'hBEEF;
            core.reg_file.registers[10] = 64'h3000;  // load address
            core.reg_file.registers[11] = 64'h8000;  // store address
            // Note: LOAD must be in A, STORE in B (store_load_hazard prevents STORE A + LOAD B)
            write_instruction(addr,      {5'h10, 5'd2, 5'd10, 5'd0, 12'b0});  // load r2 = mem[r10]
            write_instruction(addr + 4,  {5'h13, 5'd11, 5'd1, 5'd0, 12'b0});  // store mem[r11] = r1
            write_halt(addr + 8);
            run_until_halt_count(cycles);
            check("mem: load+store r2", core.reg_file.registers[2], 64'h42);
            check_mem_byte("mem: load+store @8000", 64'h8000, 8'hEF);
            check_mem_byte("mem: load+store @8001", 64'h8001, 8'hBE);
            // Should complete quickly since LOAD+STORE can dual-issue
            check_le("mem: load+store cycles", cycles, 8);
        end

        // =============================================================
        // SUMMARY
        // =============================================================
        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\nFAILED WITH %0d ERRORS", errors);

        $finish;
    end
endmodule