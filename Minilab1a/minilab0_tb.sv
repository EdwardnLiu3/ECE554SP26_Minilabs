module minilab0_tb ();
    logic CLOCK_50;
    logic [3:0] KEY;
    logic [9:0] SW;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    logic [9:0] LEDR;

    localparam FILL = 2'd0;
    localparam EXEC = 2'd1;
    localparam DONE = 2'd2;

    parameter HEX_0 = 7'b1000000;
    parameter HEX_1 = 7'b1111001;
    parameter HEX_2 = 7'b0100100;
    parameter HEX_3 = 7'b0110000;
    parameter HEX_4 = 7'b0011001;
    parameter HEX_5 = 7'b0010010;
    parameter HEX_6 = 7'b0000010;
    parameter HEX_7 = 7'b1111000;
    parameter HEX_8 = 7'b0000000;
    parameter HEX_9 = 7'b0011000;
    parameter HEX_10 = 7'b0001000;
    parameter HEX_11 = 7'b0000011;
    parameter HEX_12 = 7'b1000110;
    parameter HEX_13 = 7'b0100001;
    parameter HEX_14 = 7'b0000110;
    parameter HEX_15 = 7'b0001110;
    parameter OFF   = 7'b1111111;

    Minilab0 dut (
        .CLOCK_50(CLOCK_50),
        .CLOCK2_50(1'b0),
        .CLOCK3_50(1'b0),
        .CLOCK4_50(1'b0),
        .HEX0(HEX0),
        .HEX1(HEX1),
        .HEX2(HEX2),
        .HEX3(HEX3),
        .HEX4(HEX4),
        .HEX5(HEX5),
        .LEDR(LEDR),
        .KEY(KEY),
        .SW(SW)
    );

    initial begin
        int timeout_counter;  // Declare at beginning of block

        CLOCK_50 = 0;
        KEY = 4'b1111;
        KEY[0] = 0;  // Assert reset
        SW = 10'h000;
        @(posedge CLOCK_50);
        @(negedge CLOCK_50);
        KEY[0] = 1;  // Deassert reset
        repeat (5) @(posedge CLOCK_50);

        if(LEDR[1:0] === FILL) begin
            $display("Test 1: Initial state is FILL\n");
        end
        else begin
            $display("Test 1: Error - Expected FILL state (2'b00), got %b\n", LEDR[1:0]);
        end
        repeat (2) @(posedge CLOCK_50);

        if(HEX0 === OFF && HEX1 === OFF && HEX2 === OFF &&
           HEX3 === OFF && HEX4 === OFF && HEX5 === OFF) begin
            $display("Test 2: HEX displays OFF when SW[0] is low\n");
        end
        else begin
            $display("Test 2: Error - HEX displays should be OFF\n");
        end
        repeat (2) @(posedge CLOCK_50);

        /* Test 3: Wait for FILL state to complete (FIFOs to fill) */
        $display("Waiting for FILL state to complete...");
        $display("Monitoring FIFO fill progress (will timeout after 1000 cycles if stuck)");

        // Add timeout counter to prevent infinite wait
        timeout_counter = 0;
        while(LEDR[1:0] !== EXEC && timeout_counter < 1000) begin
            @(posedge CLOCK_50);
            timeout_counter++;
            // Print status every 10 cycles
            if(timeout_counter % 10 == 0) begin
                $display("  Cycle %0d: State=%b", timeout_counter, LEDR[1:0]);
            end
        end

        if(timeout_counter >= 1000) begin
            $display("ERROR: Timeout waiting for EXEC state!");
            $display("  Final state: %b", LEDR[1:0]);
            $display("  This may indicate:");
            $display("    1. FIFO IP cores are not included in simulation");
            $display("    2. FIFO IP cores are not properly initialized");
            $display("    3. FIFO full signals are not working correctly");
            $stop();
        end

        @(posedge CLOCK_50);
        if(LEDR[1:0] === EXEC) begin
            $display("Test 3: Transitioned to EXEC state\n");
        end
        else begin
            $display("Test 3: Error - Expected EXEC state (2'b01), got %b\n", LEDR[1:0]);
        end
        repeat (2) @(posedge CLOCK_50);

        /* Test 4: Wait for EXEC state to complete (dot product calculation) */
        $display("Waiting for EXEC state to complete...");
        timeout_counter = 0;
        while(LEDR[1:0] !== DONE && timeout_counter < 1000) begin
            @(posedge CLOCK_50);
            timeout_counter++;
            if(timeout_counter % 10 == 0) begin
                $display("  Cycle %0d: State=%b", timeout_counter, LEDR[1:0]);
            end
        end

        if(timeout_counter >= 1000) begin
            $display("ERROR: Timeout waiting for DONE state!");
            $stop();
        end

        @(posedge CLOCK_50);
        if(LEDR[1:0] === DONE) begin
            $display("Test 4: Transitioned to DONE state\n");
        end
        else begin
            $display("Test 4: Error - Expected DONE state (2'b10), got %b\n", LEDR[1:0]);
        end
        repeat (2) @(posedge CLOCK_50);

        if(LEDR[1] === 1'b1) begin
            $display("Test 5: LED1 (LEDR[1]) is ON in DONE state\n");
        end
        else begin
            $display("Test 5: Error - LED1 (LEDR[1]) should be ON in DONE state, got %b\n", LEDR[1]);
        end
        repeat (2) @(posedge CLOCK_50);

        SW[0] = 1;
        repeat (2) @(posedge CLOCK_50);

        /*
         * Expected dot product: 0*0 + 5*10 + 10*20 + 15*30 + 20*40 + 25*50 + 30*60 + 35*70
         * = 0 + 50 + 200 + 450 + 800 + 1250 + 1800 + 2450 = 7000 (decimal) = 0x1B58 (hex)
         * HEX5=0, HEX4=0, HEX3=1, HEX2=B, HEX1=5, HEX0=8
         */
        if(HEX0 === HEX_8) begin
            $display("Test 7a: HEX0 displays 8 (LSB nibble)\n");
        end
        else begin
            $display("Test 7a: Error - HEX0 expected 8, got %b\n", HEX0);
        end

        if(HEX1 === HEX_5) begin
            $display("Test 7b: HEX1 displays 5\n");
        end
        else begin
            $display("Test 7b: Error - HEX1 expected 5, got %b\n", HEX1);
        end

        if(HEX2 === HEX_11) begin
            $display("Test 7c: HEX2 displays B (11)\n");
        end
        else begin
            $display("Test 7c: Error - HEX2 expected B, got %b\n", HEX2);
        end

        if(HEX3 === HEX_1) begin
            $display("Test 7d: HEX3 displays 1\n");
        end
        else begin
            $display("Test 7d: Error - HEX3 expected 1, got %b\n", HEX3);
        end

        if(HEX4 === HEX_0) begin
            $display("Test 7e: HEX4 displays 0\n");
        end
        else begin
            $display("Test 7e: Error - HEX4 expected 0, got %b\n", HEX4);
        end

        if(HEX5 === HEX_0) begin
            $display("Test 7f: HEX5 displays 0 (MSB nibble)\n");
        end
        else begin
            $display("Test 7f: Error - HEX5 expected 0, got %b\n", HEX5);
        end
        repeat (2) @(posedge CLOCK_50);

        SW[0] = 0;
        repeat (2) @(posedge CLOCK_50);
        if(HEX0 === OFF && HEX1 === OFF && HEX2 === OFF &&
           HEX3 === OFF && HEX4 === OFF && HEX5 === OFF) begin
            $display("Test 8: HEX displays turn OFF when SW[0] is turned OFF\n");
        end
        else begin
            $display("Test 8: Error - HEX displays should be OFF when SW[0]=0\n");
        end
        repeat (2) @(posedge CLOCK_50);

        SW[0] = 1;
        repeat (2) @(posedge CLOCK_50);
        if(HEX0 === HEX_8 && HEX1 === HEX_5 && HEX2 === HEX_11 &&
           HEX3 === HEX_1 && HEX4 === HEX_0 && HEX5 === HEX_0) begin
            $display("Test 9: HEX displays show result again when SW[0] is turned back ON\n");
        end
        else begin
            $display("Test 9: Error - HEX displays should show 0x001B58\n");
        end
        repeat (2) @(posedge CLOCK_50);

        if(LEDR[1:0] === DONE) begin
            $display("Test 10: State remains in DONE\n");
        end
        else begin
            $display("Test 10: Error - State should remain in DONE, got %b\n", LEDR[1:0]);
        end
        repeat (5) @(posedge CLOCK_50);

        $stop();
    end

    always
        #5 CLOCK_50 = ~CLOCK_50;

endmodule
