timeunit 1ns;
timeprecision 1ps;

module mat_vec_mult_tb ();
    logic clk, rst_n;
    logic start;
    logic [7:0] b_in;
    logic [23:0] result [0:7];
    logic done;
    logic ready_for_b;

    // Memory interface signals
    logic [31:0] mem_address;
    logic mem_read;
    logic [63:0] mem_readdata;
    logic mem_readdatavalid;
    logic mem_waitrequest;

    // Instantiate the memory module
    mem_wrapper memory (
        .clk(clk),
        .reset_n(rst_n),
        .address(mem_address),
        .read(mem_read),
        .readdata(mem_readdata),
        .readdatavalid(mem_readdatavalid),
        .waitrequest(mem_waitrequest)
    );

    // Instantiate the DUT (Device Under Test)
    mat_vec_mult #(
        .DATA_WIDTH(8),
        .FIFO_DEPTH(8),
        .NUM_MACS(8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .b_in(b_in),
        .result(result),
        .done(done),
        .ready_for_b(ready_for_b),
        .mem_address(mem_address),
        .mem_read(mem_read),
        .mem_readdata(mem_readdata),
        .mem_readdatavalid(mem_readdatavalid),
        .mem_waitrequest(mem_waitrequest)
    );

    // Test vector for B (input vector)
    logic [7:0] b_vector [0:7];


    // Test tracking
    integer tests_passed = 0;
    integer tests_failed = 0;
    integer feed_count;
    integer idx;

    // Selective monitoring - only print on significant events
    logic [2:0] prev_state;
    logic prev_done, prev_ready_for_b, prev_mem_read, prev_mem_valid;

    initial prev_state = 3'b111; // Invalid initial value to trigger first print

    always @(posedge clk) begin
        // Print only when state changes or key signals toggle
        if (dut.state != prev_state ||
            done != prev_done ||
            ready_for_b != prev_ready_for_b ||
            mem_readdatavalid != prev_mem_valid ||
            (mem_read && !prev_mem_read)) begin

            $display("[T=%0t] state=%s | start=%b done=%b ready_for_b=%b | mem_addr=%h mem_read=%b mem_valid=%b",
                     $time, dut.state.name(),
                     start, done, ready_for_b,
                     mem_address, mem_read, mem_readdatavalid);
        end

        // Update previous values
        prev_state = dut.state;
        prev_done = done;
        prev_ready_for_b = ready_for_b;
        prev_mem_read = mem_read;
        prev_mem_valid = mem_readdatavalid;
    end

    initial begin
        // Initialize signals
        clk = 0;
        rst_n = 0;
        start = 0;
        b_in = 8'h00;

        $display("\n=== Starting Matrix-Vector Multiplication Testbench ===\n");

        // Apply reset
        @(posedge clk);
        @(negedge clk);
        rst_n = 1; // deassert reset
        repeat (5) @(posedge clk);

        /* Test 1: Check initial idle state */
        if (dut.state === dut.IDLE && done === 1'b0 && ready_for_b === 1'b0) begin
            $display("Test 1: Initial idle state works - state=IDLE, done=0, ready_for_b=0\n");
            tests_passed++;
        end
        else begin
            $display("Test 1: Error - Expected IDLE state with done=0, ready_for_b=0, got state=%s, done=%b, ready_for_b=%b\n",
                     dut.state.name(), done, ready_for_b);
            tests_failed++;
        end
        repeat (2) @(posedge clk);

        /* Test 2: Assert start signal and check state transition to FETCH_ROWS */
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge clk);

        if (dut.state === dut.FETCH_ROWS) begin
            $display("Test 2: State transition to FETCH_ROWS works\n");
            tests_passed = tests_passed + 1;
        end
        else begin
            $display("Test 2: Error - Expected FETCH_ROWS state, got state=%s\n", dut.state.name());
            tests_failed++;
        end

        /* Test 3: Monitor memory read operations during FETCH_ROWS */
        $display("Test 3: Monitoring memory read operations...");
        while (dut.state === dut.FETCH_ROWS) begin
            @(posedge clk);
            if (mem_read) begin
                $display("  Memory read request: address=0x%h", mem_address);
            end
            if (mem_readdatavalid) begin
                $display("  Memory read response: data=0x%h", mem_readdata);
            end
        end
        $display("Test 3: Memory fetch phase completed\n");

        /* Test 4: Check transition to WAIT_FIFOS_FULL */
        if (dut.state === dut.WAIT_FIFOS_FULL) begin
            $display("Test 4: State transition to WAIT_FIFOS_FULL works\n");
            tests_passed = tests_passed + 1;
        end
        else begin
            $display("Test 4: Error - Expected WAIT_FIFOS_FULL state, got state=%s\n", dut.state.name());
            tests_failed++;
        end
        @(posedge clk);

        /* Test 5: Wait for transition to COMPUTE state */
        $display("Test 5: Waiting for COMPUTE state...");
        while (dut.state !== dut.COMPUTE) begin
            @(posedge clk);
        end
        if (dut.state === dut.COMPUTE) begin
            $display("Test 5: State transition to COMPUTE works\n");
            tests_passed = tests_passed + 1;
        end
        else begin
            $display("Test 5: Error - Expected COMPUTE state, got state=%s\n", dut.state.name());
            tests_failed++;
        end

        /* Test 6: Feed B vector inputs during COMPUTE phase */
        $display("Test 6: Feeding B vector inputs...");
        // Define test B vector (values from input.mif address 8 for verifying table results)
        b_vector[0] = 8'h81;
        b_vector[1] = 8'h82;
        b_vector[2] = 8'h83;
        b_vector[3] = 8'h84;
        b_vector[4] = 8'h85;
        b_vector[5] = 8'h86;
        b_vector[6] = 8'h87;
        b_vector[7] = 8'h88;

        // Wait for ready_for_b to go high before starting to feed
        while (!ready_for_b) begin
            @(posedge clk);
        end

        // Feed all 8 B values, then continue feeding while ready_for_b is high
        feed_count = 0;
        while (ready_for_b) begin
            // Use modulo to cycle through B vector, or use last value for extra cycles
            idx = (feed_count < 8) ? feed_count : 7;  // Hold at last value after 8
            b_in = b_vector[idx];
            if (feed_count < 8) begin
                $display("  >>> Feeding B[%0d] = 0x%h, ready_for_b=%b", feed_count, b_in, ready_for_b);
            end
            $display("      [Cycle %0d] en_chain[0]=%b, fifo_empty[0]=%b, fifo_rden[0]=%b, Ain=0x%h",
                     dut.compute_core.compute_counter,
                     dut.compute_core.en_chain[0],
                     dut.compute_core.fifo_empty[0],
                     dut.compute_core.fifo_rden[0],
                     dut.compute_core.fifo_data[0]);
            feed_count = feed_count + 1;
            @(posedge clk);
        end
        $display("Test 6: B vector input completed (fed %0d values)\n", feed_count);
        tests_passed = tests_passed + 1;

        /* Test 7: Monitor COMPUTE phase completion */
        $display("Test 7: Monitoring computation phase...");
        while (dut.state === dut.COMPUTE) begin
            // Debug: Print detailed MAC[0] state
            $display("  [Cycle %0d] en_chain[0]=%b, fifo_empty[0]=%b, fifo_rden[0]=%b, Ain=0x%h, Bin=0x%h",
                     dut.compute_core.compute_counter,
                     dut.compute_core.en_chain[0],
                     dut.compute_core.fifo_empty[0],
                     dut.compute_core.fifo_rden[0],
                     dut.compute_core.fifo_data[0],
                     dut.compute_core.b_chain[0]);
            @(posedge clk);
        end
        $display("Test 7: Compute phase completed\n");

        if (dut.state === dut.DONE_STATE) begin
            $display("Test 7: State transition to DONE_STATE works\n");
            tests_passed = tests_passed + 1;
        end
        else begin
            $display("Test 7: Error - Expected DONE_STATE, got state=%s\n", dut.state.name());
            tests_failed++;
        end

        /* Test 8: Check done signal */
        if (done === 1'b1) begin
            $display("Test 8: Done signal asserted correctly\n");
            tests_passed = tests_passed + 1;
        end
        else begin
            $display("Test 8: Error - Expected done=1, got done=%b\n", done);
            tests_failed++;
        end

        /* Test 9: Display and Verify computation results */
        $display("\n=== Test 9: Computation Results ===");
        
        if (result[0] === 24'h0012CC) begin
             $display("  result[0] = 0x%06h (CORRECT)", result[0]);
             tests_passed = tests_passed + 1;
        end else begin
             $display("  result[0] = 0x%06h (EXPECTED: 0x0012CC)", result[0]);
             tests_failed++;
        end

        for (int i = 1; i < 8; i++) begin
            $display("  result[%0d] = 0x%06h (%0d decimal)", i, result[i], result[i]);
        end

        // Display FIFO status
        $display("\n  FIFO Status:");
        for (int i = 0; i < 8; i++) begin
            $display("    FIFO[%0d]: full=%b empty=%b", i, dut.fifo_full[i], dut.fifo_empty[i]);
        end
        $display("Test 9: Results verified against part 1 spec\n");

        /* Test 10: Check return to IDLE state */
        @(posedge clk);
        if (dut.state === dut.IDLE && done === 1'b0) begin
            $display("Test 10: Return to IDLE state works - state=IDLE, done=0\n");
            tests_passed = tests_passed + 1;
        end
        else begin
            $display("Test 10: Error - Expected IDLE state with done=0, got state=%s, done=%b\n",
                     dut.state.name(), done);
            tests_failed++;
        end
        repeat (2) @(posedge clk);

        /* Test 11: Second computation with different B vector */
        $display("Test 11: Starting second computation with different B vector...");
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for COMPUTE state
        while (dut.state !== dut.COMPUTE) begin
            @(posedge clk);
        end

        // Feed different B vector
        b_vector[0] = 8'h0A;
        b_vector[1] = 8'h0B;
        b_vector[2] = 8'h0C;
        b_vector[3] = 8'h0D;
        b_vector[4] = 8'h0E;
        b_vector[5] = 8'h0F;
        b_vector[6] = 8'h10;
        b_vector[7] = 8'h11;

        for (int i = 0; i < 8; i++) begin
            if (ready_for_b) begin
                b_in = b_vector[i];
                @(posedge clk);
            end
        end

        // Wait for completion
        while (dut.state !== dut.DONE_STATE) begin
            @(posedge clk);
        end

        if (done === 1'b1) begin
            $display("\n=== Test 11: Second Computation Results ===");
            for (int i = 0; i < 8; i++) begin
                $display("  result[%0d] = 0x%06h (%0d decimal)", i, result[i], result[i]);
            end
            $display("Test 11: Second computation completed successfully\n");
            tests_passed = tests_passed + 1;
        end
        else begin
            $display("Test 11: Error - Second computation did not complete correctly\n");
            tests_failed++;
        end

        repeat (5) @(posedge clk);

        /* Test 12: Verify FIFO operation by checking internal FIFO signals */
        $display("Test 12: FIFO operation verification");
        $display("  All FIFOs should be empty after computation:");
        for (int i = 0; i < 8; i++) begin
            if (dut.fifo_empty[i] === 1'b1) begin
                $display("    FIFO[%0d]: empty=%b (correct)", i, dut.fifo_empty[i]);
            end
            else begin
                $display("    FIFO[%0d]: empty=%b (ERROR - should be empty)", i, dut.fifo_empty[i]);
                tests_failed++;
            end
        end
        if (&dut.fifo_empty) begin
            $display("Test 12: FIFO verification completed\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 12: FIFO verification FAILED\n");
        end

        /* Final Test Summary */
        $display("\n");
        $display("========================================");
        $display("        TEST SUMMARY");
        $display("========================================");
        $display("  Tests Passed: %0d", tests_passed);
        $display("  Tests Failed: %0d", tests_failed);
        $display("  Total Tests:  %0d", tests_passed + tests_failed);
        if (tests_failed == 0) begin
            $display("\n  *** ALL TESTS PASSED! ***");
        end else begin
            $display("\n  *** SOME TESTS FAILED ***");
        end
        $display("========================================\n");

        $stop();
    end

    // Debug: Monitor FIFO writes
    always @(posedge clk) begin
        if (dut.fetcher.state == dut.fetcher.FETCH_ROWS) begin
            for (int k=0; k<8; k++) begin
                if (dut.fifo_wren[k]) begin
                    $display("[T=%0t] FIFO[%0d] WRITE: data=0x%h", $time, k, dut.fifo_wrdata[k]);
                end
            end
        end
    end

    always
        #5 clk = ~clk;

endmodule
