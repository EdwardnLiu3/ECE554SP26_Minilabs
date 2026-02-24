`timescale 1ns/1ps

///////////////////////////////////////////////////////////////////////////////
//
// Tests Performed:
//   Test  1: Driver starts in INIT_LOW state after reset
//   Test  2: Driver transitions INIT_LOW -> INIT_HIGH after 1 clock
//   Test  3: Driver transitions INIT_HIGH -> IDLE after 2 clocks
//   Test  4: SPART1 divisor_buf loaded correctly for 38400 baud (div=80)
//   Test  5: SPART0 divisor_buf programmed to match DUT (div=80)
//   Test  6: Single character echo - 'A' (0x41) at 38400 baud
//   Test  7: Single character echo - 'Z' (0x5A) at 38400 baud
//   Test  8: Multi-character echo  - "HELLO" (5 chars) at 38400 baud
//   Test  9: Status register read - TBR=1, RDA=0 after idle
//   Test 10: Baud rate change to 9600 baud - divisor=325 loaded correctly
//   Test 11: Echo 'S' (0x53) at 9600 baud
//   Test 12: Baud rate change to 19200 baud - divisor=162 loaded correctly
//   Test 13: Echo '!' (0x21) at 19200 baud
//   Test 14: Baud rate change to 4800 baud - divisor=650 loaded correctly
//   Test 15: Echo 'X' (0x58) at 4800 baud
//
// Clock: 50 MHz (10 ns period, matches DE1-SoC CLOCK_50)
// Default initial baud rate: 38400 (br_cfg=11, divisor=80) for simulation speed
///////////////////////////////////////////////////////////////////////////////

module spart_tb();

    ///////////////////////////////////////////////////////////////////////////
    // Clock & Reset
    ///////////////////////////////////////////////////////////////////////////
    reg clk, rst;

    ///////////////////////////////////////////////////////////////////////////
    // br_cfg: selects baud rate for the driver (and SPART1)
    //   00 -> 4800  baud, divisor = 650
    //   01 -> 9600  baud, divisor = 325
    //   10 -> 19200 baud, divisor = 162
    //   11 -> 38400 baud, divisor =  80
    ///////////////////////////////////////////////////////////////////////////
    reg [1:0] br_cfg;

    ///////////////////////////////////////////////////////////////////////////
    // DUT interface: Driver <-> SPART1 shared bus
    ///////////////////////////////////////////////////////////////////////////
    wire        iocs;          // I/O chip select (driven by driver)
    wire        iorw;          // 1=read from SPART1, 0=write to SPART1
    wire        rda1;          // Receive Data Available (from SPART1)
    wire        tbr1;          // Transmit Buffer Ready (from SPART1)
    wire [1:0]  ioaddr;        // Register select (driven by driver)
    wire [7:0]  databus;       // Bidirectional data bus (driver <-> SPART1)

    ///////////////////////////////////////////////////////////////////////////
    // Serial cross-connections:
    //   SPART0.TxD --> SPART1.RxD  (testbench transmits to DUT)
    //   SPART1.TxD --> SPART0.RxD  (DUT echoes back to testbench)
    ///////////////////////////////////////////////////////////////////////////
    wire txd0;                 // SPART0 serial transmit out
    wire txd1;                 // SPART1 serial transmit out
    wire rxd0;                 // SPART0 serial receive in  = txd1
    wire rxd1;                 // SPART1 serial receive in  = txd0

    assign rxd0 = txd1;        // DUT transmit  -> testbench receive
    assign rxd1 = txd0;        // TB  transmit  -> DUT receive

    ///////////////////////////////////////////////////////////////////////////
    // Testbench SPART0 bus interface
    // The testbench drives this bus to mimic a processor writing/reading SPART0.
    ///////////////////////////////////////////////////////////////////////////
    reg        iocs0;          // Chip select for SPART0 (driven by TB)
    reg        iorw0;          // Direction for SPART0 (driven by TB)
    reg  [1:0] ioaddr0;        // Register address for SPART0 (driven by TB)
    reg  [7:0] db_drive0;      // Data driven onto databus0 during writes
    wire [7:0] databus0;       // Bidirectional bus between TB and SPART0
    wire       rda0;           // SPART0 Receive Data Available
    wire       tbr0;           // SPART0 Transmit Buffer Ready

    // Drive databus0 during write operations; release to hi-Z during reads/idle
    assign databus0 = (iocs0 && !iorw0) ? db_drive0 : 8'hzz;

    ///////////////////////////////////////////////////////////////////////////
    // Test tracking variables
    ///////////////////////////////////////////////////////////////////////////
    integer tests_passed;
    integer tests_failed;
    integer err_count;
    integer timeout_cnt;

    // Received byte buffer used across tasks and test blocks
    reg [7:0] recv_byte;

    ///////////////////////////////////////////////////////////////////////////
    // Module Instantiations
    ///////////////////////////////////////////////////////////////////////////

    // SPART0: testbench-side SPART (emulates dumb terminal / printf source)
    spart SPART0 (
        .clk    (clk),
        .rst    (rst),
        .iocs   (iocs0),
        .iorw   (iorw0),
        .rda    (rda0),
        .tbr    (tbr0),
        .ioaddr (ioaddr0),
        .databus(databus0),
        .txd    (txd0),
        .rxd    (rxd0)
    );

    // SPART1: DUT SPART (receives from TB via rxd1, echoes back via txd1)
    spart SPART1 (
        .clk    (clk),
        .rst    (rst),
        .iocs   (iocs),
        .iorw   (iorw),
        .rda    (rda1),
        .tbr    (tbr1),
        .ioaddr (ioaddr),
        .databus(databus),
        .txd    (txd1),
        .rxd    (rxd1)
    );

    // Driver: DUT mock processor - programs baud rate then echoes received bytes
    driver DUT (
        .clk    (clk),
        .rst    (rst),
        .br_cfg (br_cfg),
        .iocs   (iocs),
        .iorw   (iorw),
        .rda    (rda1),
        .tbr    (tbr1),
        .ioaddr (ioaddr),
        .databus(databus)
    );

    ///////////////////////////////////////////////////////////////////////////
    // Tasks
    ///////////////////////////////////////////////////////////////////////////

    // --- set_spart0_divisor ----------------------------------------------- //
    // Program SPART0's 16-bit Divisor Buffer so its baud rate matches SPART1.
    // Writes DB(Low) to IOADDR=10 then DB(High) to IOADDR=11.
    task set_spart0_divisor;
        input [15:0] div;
        begin
            @(negedge clk);
            iocs0 = 1; iorw0 = 0; ioaddr0 = 2'b10; db_drive0 = div[7:0];
            @(posedge clk);                    // SPART0 latches DB(Low)
            @(negedge clk);
            iocs0 = 1; iorw0 = 0; ioaddr0 = 2'b11; db_drive0 = div[15:8];
            @(posedge clk);                    // SPART0 latches DB(High)
            @(negedge clk);
            iocs0 = 0; iorw0 = 0;
        end
    endtask

    // --- send_char -------------------------------------------------------- //
    // Send one byte via SPART0 TX (polls TBR, then writes to IOADDR=00).
    // Mimics the printf side writing a character to the terminal.
    task send_char;
        input [7:0] ch;
        begin
            // Poll TBR=1: wait for SPART0 transmit buffer to become free
            timeout_cnt = 0;
            while (!tbr0 && timeout_cnt < 300000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (timeout_cnt >= 300000)
                $display("  WARNING: TBR timeout in send_char (0x%02h) - baud mismatch?", ch);

            // Write character to SPART0 TX buffer (IOADDR=00, write)
            @(negedge clk);
            iocs0     = 1;
            iorw0     = 0;
            ioaddr0   = 2'b00;
            db_drive0 = ch;
            @(posedge clk);                    // SPART0 latches ch into tx_buf
            @(negedge clk);
            iocs0 = 0;
            iorw0 = 0;
        end
    endtask

    // --- recv_char -------------------------------------------------------- //
    // Read one byte from SPART0 RX buffer (polls RDA, then reads IOADDR=00).
    // Mimics the printf side reading an echoed character from the terminal.
    task recv_char;
        output [7:0] ch;
        begin
            // Poll RDA=1: wait for SPART0 to receive a byte from DUT
            timeout_cnt = 0;
            while (!rda0 && timeout_cnt < 700000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (timeout_cnt >= 700000)
                $display("  WARNING: RDA timeout in recv_char - no echo received");

            // Read SPART0 RX buffer (IOADDR=00, read); SPART0 clears RDA on posedge
            @(negedge clk);
            iocs0   = 1;
            iorw0   = 1;
            ioaddr0 = 2'b00;
            @(posedge clk);                    // Sample databus0; SPART0 clears rda
            ch = databus0;
            @(negedge clk);
            iocs0 = 0;
            iorw0 = 0;
        end
    endtask

    ///////////////////////////////////////////////////////////////////////////
    // Selective Monitoring: print driver state transitions on each change
    ///////////////////////////////////////////////////////////////////////////
    reg [2:0] prev_drv_state;
    initial prev_drv_state = 3'b111;  // invalid value forces first-cycle print

    always @(posedge clk) begin
        if (DUT.state !== prev_drv_state) begin
            case (DUT.state)
                3'd0: $display("[T=%0t] Driver -> INIT_LOW  : writing div[7:0]=0x%02h to SPART1",
                               $time, DUT.divisor[7:0]);
                3'd1: $display("[T=%0t] Driver -> INIT_HIGH : writing div[15:8]=0x%02h to SPART1",
                               $time, DUT.divisor[15:8]);
                3'd2: $display("[T=%0t] Driver -> IDLE      : polling RDA",
                               $time);
                3'd3: $display("[T=%0t] Driver -> READ      : reading received byte from SPART1",
                               $time);
                3'd4: $display("[T=%0t] Driver -> WAIT_TBR  : polling TBR",
                               $time);
                3'd5: $display("[T=%0t] Driver -> WRITE     : echoing 0x%02h ('%c') to SPART1",
                               $time, DUT.rx_data, DUT.rx_data);
                default: $display("[T=%0t] Driver -> UNKNOWN state=%0d",
                               $time, DUT.state);
            endcase
            prev_drv_state = DUT.state;
        end
    end

    ///////////////////////////////////////////////////////////////////////////
    // Main Test Sequence
    ///////////////////////////////////////////////////////////////////////////
    initial begin
        // ---------------------------------------------------------------
        // Initialization
        // ---------------------------------------------------------------
        clk       = 0;
        rst       = 1;
        br_cfg    = 2'b11;    // 38400 baud (divisor=80) - fastest for simulation
        iocs0     = 0;
        iorw0     = 0;
        ioaddr0   = 2'b00;
        db_drive0 = 8'h00;
        tests_passed = 0;
        tests_failed = 0;
        err_count    = 0;

        $display("\n=== Starting SPART + Driver Simulation Testbench ===");
        $display("=== Initial baud rate: 38400 baud (br_cfg=11, divisor=80) ===\n");

        // Hold reset for 4 clock cycles, then release
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;
        // At this negedge: rst just deasserted.  No posedge has occurred yet,
        // so driver.state is still INIT_LOW (the reset value).

        /* -------------------------------------------------------------------
         * Test 1: Driver starts in INIT_LOW (state=0) after reset is released.
         *         Checked before the first post-reset posedge.
         * ------------------------------------------------------------------- */
        if (DUT.state === 3'd0) begin
            $display("Test  1 PASS: Driver state = INIT_LOW (0) after reset\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  1 FAIL: Expected INIT_LOW (0), got state=%0d\n", DUT.state);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 2: After 1 clock, driver transitions to INIT_HIGH (state=1).
         *         During this cycle, driver writes divisor[7:0] to SPART1.
         *  NOTE: #1 delay lets the NBA (nonblocking assignment) for state commit
         *        before we read it; without it we see the pre-posedge value.
         * ------------------------------------------------------------------- */
        @(posedge clk); #1;
        if (DUT.state === 3'd1) begin
            $display("Test  2 PASS: Driver state = INIT_HIGH (1) - divisor low byte written\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  2 FAIL: Expected INIT_HIGH (1), got state=%0d\n", DUT.state);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 3: After 2 clocks, driver reaches IDLE (state=2).
         *         During this cycle, driver writes divisor[15:8] to SPART1.
         *  NOTE: #1 delay again; also ensures divisor_buf[15:8] NBA settles
         *        so Test 4 reads the fully-assembled divisor correctly.
         * ------------------------------------------------------------------- */
        @(posedge clk); #1;
        if (DUT.state === 3'd2) begin
            $display("Test  3 PASS: Driver state = IDLE (2) - initialization complete\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  3 FAIL: Expected IDLE (2), got state=%0d\n", DUT.state);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 4: SPART1 divisor_buf should now hold 80 (0x0050) for 38400 baud.
         *         Both low and high bytes were written by the driver above.
         * ------------------------------------------------------------------- */
        if (SPART1.divisor_buf === 16'd80) begin
            $display("Test  4 PASS: SPART1.divisor_buf = %0d (0x%04h) for 38400 baud\n",
                     SPART1.divisor_buf, SPART1.divisor_buf);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  4 FAIL: Expected SPART1.divisor_buf=80, got %0d\n",
                     SPART1.divisor_buf);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 5: Program SPART0 to 38400 baud (divisor=80) to match SPART1.
         *         Verify the divisor was stored in SPART0.divisor_buf.
         * ------------------------------------------------------------------- */
        set_spart0_divisor(16'd80);
        if (SPART0.divisor_buf === 16'd80) begin
            $display("Test  5 PASS: SPART0.divisor_buf = %0d - baud rates matched\n",
                     SPART0.divisor_buf);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  5 FAIL: SPART0.divisor_buf = %0d, expected 80\n",
                     SPART0.divisor_buf);
            tests_failed = tests_failed + 1;
        end

        // Allow baud counters to settle after divisor change
        repeat(10) @(posedge clk);

        /* -------------------------------------------------------------------
         * Test 6: Single character echo - send 'A' (0x41) at 38400 baud.
         *         TB writes 'A' to SPART0 -> SPART1 receives -> driver echoes
         *         -> SPART0 receives echo -> TB reads and checks.
         * ------------------------------------------------------------------- */
        $display("Test  6: Sending 'A' (0x41) at 38400 baud, awaiting echo...");
        send_char(8'h41);
        recv_char(recv_byte);
        if (recv_byte === 8'h41) begin
            $display("Test  6 PASS: Echo 0x%02h ('%c') matches sent 'A'\n",
                     recv_byte, recv_byte);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  6 FAIL: Expected 0x41 ('A'), received 0x%02h\n", recv_byte);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 7: Single character echo - send 'Z' (0x5A) at 38400 baud.
         * ------------------------------------------------------------------- */
        $display("Test  7: Sending 'Z' (0x5A) at 38400 baud, awaiting echo...");
        send_char(8'h5A);
        recv_char(recv_byte);
        if (recv_byte === 8'h5A) begin
            $display("Test  7 PASS: Echo 0x%02h ('%c') matches sent 'Z'\n",
                     recv_byte, recv_byte);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  7 FAIL: Expected 0x5A ('Z'), received 0x%02h\n", recv_byte);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 8: Multi-character echo - send "HELLO" (5 chars), verify each.
         *         Characters are sent and verified one at a time (per echo model).
         * ------------------------------------------------------------------- */
        $display("Test  8: Sending 'HELLO' (5 chars) at 38400 baud, checking each echo...");
        err_count = 0;

        send_char(8'h48); recv_char(recv_byte);  // 'H'
        if (recv_byte !== 8'h48) err_count = err_count + 1;
        else $display("  'H' (0x48) echoed correctly");

        send_char(8'h45); recv_char(recv_byte);  // 'E'
        if (recv_byte !== 8'h45) err_count = err_count + 1;
        else $display("  'E' (0x45) echoed correctly");

        send_char(8'h4C); recv_char(recv_byte);  // 'L'
        if (recv_byte !== 8'h4C) err_count = err_count + 1;
        else $display("  'L' (0x4C) echoed correctly");

        send_char(8'h4C); recv_char(recv_byte);  // 'L'
        if (recv_byte !== 8'h4C) err_count = err_count + 1;
        else $display("  'L' (0x4C) echoed correctly");

        send_char(8'h4F); recv_char(recv_byte);  // 'O'
        if (recv_byte !== 8'h4F) err_count = err_count + 1;
        else $display("  'O' (0x4F) echoed correctly");

        if (err_count == 0) begin
            $display("Test  8 PASS: All 5 'HELLO' characters echoed correctly\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  8 FAIL: %0d / 5 character(s) mismatched\n", err_count);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 9: Status Register check via IOADDR=01 read on SPART0.
         *         Format: {6'b0, TBR, RDA}.
         *         After an echo cycle with no pending data: TBR=1, RDA=0.
         * ------------------------------------------------------------------- */
        $display("Test  9: Reading SPART0 Status Register (IOADDR=01)...");
        repeat(50) @(posedge clk);         // ensure TX is idle
        @(negedge clk);
        iocs0 = 1; iorw0 = 1; ioaddr0 = 2'b01;
        @(posedge clk);
        recv_byte = databus0;              // status = {6'b0, TBR, RDA}
        @(negedge clk);
        iocs0 = 0; iorw0 = 0;

        $display("  Status Register = 0x%02h  |  TBR=%b  RDA=%b",
                 recv_byte, recv_byte[1], recv_byte[0]);
        if (recv_byte[1] === 1'b1 && recv_byte[0] === 1'b0) begin
            $display("Test  9 PASS: TBR=1 (buffer free), RDA=0 (no pending data)\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test  9 FAIL: Expected TBR=1, RDA=0; got TBR=%b, RDA=%b\n",
                     recv_byte[1], recv_byte[0]);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 10: Change baud rate to 9600 (br_cfg=01, divisor=325).
         *          Reset the system; driver re-initializes SPART1 with new div.
         * ------------------------------------------------------------------- */
        $display("Test 10: Switching to 9600 baud (br_cfg=01, divisor=325)...");
        br_cfg = 2'b01;
        @(negedge clk); rst = 1;
        repeat(4) @(posedge clk);
        @(negedge clk); rst = 0;
        repeat(3) @(posedge clk);          // wait through INIT_LOW + INIT_HIGH + IDLE

        if (SPART1.divisor_buf === 16'd325) begin
            $display("Test 10 PASS: SPART1.divisor_buf = %0d (0x%04h) for 9600 baud\n",
                     SPART1.divisor_buf, SPART1.divisor_buf);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 10 FAIL: Expected divisor_buf=325, got %0d\n", SPART1.divisor_buf);
            tests_failed = tests_failed + 1;
        end

        set_spart0_divisor(16'd325);
        repeat(10) @(posedge clk);

        /* -------------------------------------------------------------------
         * Test 11: Echo 'S' (0x53) at 9600 baud.
         * ------------------------------------------------------------------- */
        $display("Test 11: Sending 'S' (0x53) at 9600 baud, awaiting echo...");
        send_char(8'h53);
        recv_char(recv_byte);
        if (recv_byte === 8'h53) begin
            $display("Test 11 PASS: 9600 baud echo 0x%02h ('%c') matches 'S'\n",
                     recv_byte, recv_byte);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 11 FAIL: Expected 0x53 ('S'), received 0x%02h\n", recv_byte);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 12: Change baud rate to 19200 (br_cfg=10, divisor=162).
         * ------------------------------------------------------------------- */
        $display("Test 12: Switching to 19200 baud (br_cfg=10, divisor=162)...");
        br_cfg = 2'b10;
        @(negedge clk); rst = 1;
        repeat(4) @(posedge clk);
        @(negedge clk); rst = 0;
        repeat(3) @(posedge clk);

        if (SPART1.divisor_buf === 16'd162) begin
            $display("Test 12 PASS: SPART1.divisor_buf = %0d (0x%04h) for 19200 baud\n",
                     SPART1.divisor_buf, SPART1.divisor_buf);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 12 FAIL: Expected divisor_buf=162, got %0d\n", SPART1.divisor_buf);
            tests_failed = tests_failed + 1;
        end

        set_spart0_divisor(16'd162);
        repeat(10) @(posedge clk);

        /* -------------------------------------------------------------------
         * Test 13: Echo '!' (0x21) at 19200 baud.
         * ------------------------------------------------------------------- */
        $display("Test 13: Sending '!' (0x21) at 19200 baud, awaiting echo...");
        send_char(8'h21);
        recv_char(recv_byte);
        if (recv_byte === 8'h21) begin
            $display("Test 13 PASS: 19200 baud echo 0x%02h ('%c') matches '!'\n",
                     recv_byte, recv_byte);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 13 FAIL: Expected 0x21 ('!'), received 0x%02h\n", recv_byte);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Test 14: Change baud rate to 4800 (br_cfg=00, divisor=650).
         * ------------------------------------------------------------------- */
        $display("Test 14: Switching to 4800 baud (br_cfg=00, divisor=650)...");
        br_cfg = 2'b00;
        @(negedge clk); rst = 1;
        repeat(4) @(posedge clk);
        @(negedge clk); rst = 0;
        repeat(3) @(posedge clk);

        if (SPART1.divisor_buf === 16'd650) begin
            $display("Test 14 PASS: SPART1.divisor_buf = %0d (0x%04h) for 4800 baud\n",
                     SPART1.divisor_buf, SPART1.divisor_buf);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 14 FAIL: Expected divisor_buf=650, got %0d\n", SPART1.divisor_buf);
            tests_failed = tests_failed + 1;
        end

        set_spart0_divisor(16'd650);
        repeat(10) @(posedge clk);

        /* -------------------------------------------------------------------
         * Test 15: Echo 'X' (0x58) at 4800 baud.
         *          Slowest rate - each byte takes ~104 us in simulation.
         * ------------------------------------------------------------------- */
        $display("Test 15: Sending 'X' (0x58) at 4800 baud, awaiting echo...");
        send_char(8'h58);
        recv_char(recv_byte);
        if (recv_byte === 8'h58) begin
            $display("Test 15 PASS: 4800 baud echo 0x%02h ('%c') matches 'X'\n",
                     recv_byte, recv_byte);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 15 FAIL: Expected 0x58 ('X'), received 0x%02h\n", recv_byte);
            tests_failed = tests_failed + 1;
        end

        /* -------------------------------------------------------------------
         * Final Test Summary
         * ------------------------------------------------------------------- */
        $display("\n");
        $display("========================================");
        $display("           TEST SUMMARY");
        $display("========================================");
        $display("  Tests Passed: %0d", tests_passed);
        $display("  Tests Failed: %0d", tests_failed);
        $display("  Total Tests:  %0d", tests_passed + tests_failed);
        if (tests_failed == 0)
            $display("\n  *** ALL TESTS PASSED! ***");
        else
            $display("\n  *** SOME TESTS FAILED ***");
        $display("========================================\n");

        $stop();
    end


    always #5 clk = ~clk;

endmodule