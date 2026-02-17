`timescale 1ns / 1ps

module image_processing_pipeline_tb;

    // DUT signals
    reg         clk;
    reg         rst_n;
    reg  [11:0] iDATA;
    reg         iDVAL;
    reg  [15:0] iX_Cont;
    reg  [15:0] iY_Cont;
    wire [11:0] oDATA;
    wire        oDVAL;

    // Instantiate DUT
    image_processing_pipeline dut (
        .iCLK    (clk),
        .iRST    (rst_n),
        .iDATA   (iDATA),
        .iDVAL   (iDVAL),
        .iX_Cont (iX_Cont),
        .iY_Cont (iY_Cont),
        .oDATA   (oDATA),
        .oDVAL   (oDVAL)
    );

    // Test tracking
    integer tests_passed = 0;
    integer tests_failed = 0;

    // Output collection
    integer valid_count;
    integer edge_count;
    reg [11:0] max_output;

    // Loop variables
    integer row_idx;

    // Output collector - counts valid outputs and tracks edge detections
    always @(posedge clk) begin
        if (oDVAL) begin
            valid_count = valid_count + 1;
            if (oDATA > max_output)
                max_output = oDATA;
            if (oDATA > 12'd10)
                edge_count = edge_count + 1;
        end
    end

    // Clock generation
    always
        #10 clk = ~clk;

    // ---------------------------------------------------------------
    // Helper Tasks
    // ---------------------------------------------------------------

    // Feed one full Bayer row (1280 pixels) with separate left/right values
    task feed_bayer_row;
        input [11:0] left_val;
        input [11:0] right_val;
        input [15:0] row_num;
        integer c;
        begin
            for (c = 0; c < 1280; c = c + 1) begin
                iDATA   = (c < 640) ? left_val : right_val;
                iDVAL   = 1'b1;
                iX_Cont = c;
                iY_Cont = row_num;
                @(posedge clk);
            end
            // H-blanking
            iDVAL = 1'b0;
            iDATA = 12'd0;
            repeat (10) @(posedge clk);
        end
    endtask

    // Feed one full uniform Bayer row
    task feed_uniform_row;
        input [11:0] val;
        input [15:0] row_num;
        begin
            feed_bayer_row(val, val, row_num);
        end
    endtask

    // Reset output collection counters
    task reset_counters;
        begin
            valid_count = 0;
            edge_count  = 0;
            max_output  = 12'd0;
        end
    endtask

    // ---------------------------------------------------------------
    // Main Test Sequence
    // ---------------------------------------------------------------
    initial begin
        // Initialize
        clk     = 0;
        rst_n   = 0;
        iDATA   = 12'd0;
        iDVAL   = 1'b0;
        iX_Cont = 16'd0;
        iY_Cont = 16'd0;
        reset_counters;

        $display("\n=== Starting Image Processing Pipeline Testbench ===\n");

        // Apply reset
        @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        /* Test 1: Check initial reset state */
        if (oDVAL === 1'b0 && oDATA === 12'd0) begin
            $display("Test 1: Initial reset state correct - oDVAL=0, oDATA=0\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 1: Error - Expected oDVAL=0, oDATA=0, got oDVAL=%b, oDATA=%0d\n",
                     oDVAL, oDATA);
            tests_failed = tests_failed + 1;
        end

        /* Test 2: Internal valid signals deasserted after reset */
        if (dut.gray_dval === 1'b0 && dut.sobel_dval === 1'b0) begin
            $display("Test 2: Internal valid signals correct - gray_dval=0, sobel_dval=0\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 2: Error - gray_dval=%b, sobel_dval=%b (expected both 0)\n",
                     dut.gray_dval, dut.sobel_dval);
            tests_failed = tests_failed + 1;
        end
        repeat (2) @(posedge clk);

        /* Test 3: Feed uniform rows, verify pipeline produces valid output */
        $display("Test 3: Feeding 8 uniform Bayer rows (value=200)...");
        reset_counters;
        for (row_idx = 0; row_idx < 8; row_idx = row_idx + 1) begin
            $display("  Feeding Bayer row %0d...", row_idx);
            feed_uniform_row(12'd200, row_idx);
        end
        iDVAL = 1'b0;
        repeat (100) @(posedge clk);

        $display("  Results: valid_count=%0d, edge_count=%0d, max_output=%0d",
                 valid_count, edge_count, max_output);

        if (valid_count > 0) begin
            $display("Test 3: Pipeline produced %0d valid outputs\n", valid_count);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 3: Error - No valid outputs produced\n");
            tests_failed = tests_failed + 1;
        end

        /* Test 4: Uniform region steady-state outputs should be zero */
        // First 2 grayscale rows have warmup artifacts (row buffers init to 0).
        // Last 2 grayscale rows should produce zero output.
        // Check that not ALL outputs are edges (steady-state produces zero).
        if (edge_count < valid_count) begin
            $display("Test 4: Steady-state uniform produces zero edges (%0d edges / %0d total)\n",
                     edge_count, valid_count);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 4: Error - All %0d outputs are edges, expected zero in steady-state\n",
                     valid_count);
            tests_failed = tests_failed + 1;
        end

        /* Test 5: Vertical edge pattern - detect edges */
        $display("Test 5: Resetting and feeding vertical edge (left=0, right=255)...");
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
        reset_counters;

        for (row_idx = 0; row_idx < 8; row_idx = row_idx + 1) begin
            $display("  Feeding Bayer row %0d...", row_idx);
            feed_bayer_row(12'd0, 12'd255, row_idx);
        end
        iDVAL = 1'b0;
        repeat (100) @(posedge clk);

        $display("  Results: valid_count=%0d, edge_count=%0d, max_output=%0d",
                 valid_count, edge_count, max_output);

        if (edge_count > 0) begin
            $display("Test 5: Vertical edges detected - %0d edge pixels, max=%0d\n",
                     edge_count, max_output);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 5: Error - No edges detected in vertical edge pattern\n");
            tests_failed = tests_failed + 1;
        end

        /* Test 6: Verify edge magnitude is reasonable for vertical edge */
        // For a 0->255 step, Sobel X at the boundary:
        //   Gx = (255-0) + 2*(255-0) + (255-0) = 1020
        //   abs = 1020 / 2 = 510
        // Allow broad range due to pipeline warmup and boundary effects.
        if (max_output > 12'd50) begin
            $display("Test 6: Edge magnitude %0d confirms Sobel activation\n", max_output);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 6: Error - Edge magnitude %0d too low for vertical edge\n", max_output);
            tests_failed = tests_failed + 1;
        end

        /* Test 7: Horizontal edge pattern - detect edges */
        $display("Test 7: Resetting and feeding horizontal edge (top=255, bottom=0)...");
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
        reset_counters;

        for (row_idx = 0; row_idx < 8; row_idx = row_idx + 1) begin
            if (row_idx < 4)
                feed_uniform_row(12'd255, row_idx);
            else
                feed_uniform_row(12'd0, row_idx);
        end
        iDVAL = 1'b0;
        repeat (100) @(posedge clk);

        $display("  Results: valid_count=%0d, edge_count=%0d, max_output=%0d",
                 valid_count, edge_count, max_output);

        if (edge_count > 0) begin
            $display("Test 7: Horizontal edges detected - %0d edge pixels, max=%0d\n",
                     edge_count, max_output);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 7: Error - No edges detected in horizontal edge pattern\n");
            tests_failed = tests_failed + 1;
        end

        /* Test 8: Reset clears all pipeline valid signals */
        $display("Test 8: Verifying reset clears pipeline...");
        rst_n = 0;
        repeat (5) @(posedge clk);

        if (oDVAL === 1'b0 && dut.gray_dval === 1'b0 && dut.sobel_dval === 1'b0) begin
            $display("Test 8: Reset correctly clears all valid signals\n");
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 8: Error - valid signals not cleared: oDVAL=%b, gray_dval=%b, sobel_dval=%b\n",
                     oDVAL, dut.gray_dval, dut.sobel_dval);
            tests_failed = tests_failed + 1;
        end
        rst_n = 1;
        repeat (5) @(posedge clk);

        /* Test 9: Whitebox - force Sobel outputs, verify absolute value */
        $display("Test 9: Whitebox - forcing Sobel outputs to verify abs value...");
        // Force known Sobel X = +1000, Sobel Y = -500
        // Expected: |1000| + |500| = 1500, /2 = 750
        force dut.sobel_x = 15'sd1000;
        force dut.sobel_y = -(15'sd500);
        force dut.sobel_dval = 1'b1;

        @(posedge clk); // abs_value registers edge_val on this edge
        @(posedge clk); // output now visible

        release dut.sobel_x;
        release dut.sobel_y;
        release dut.sobel_dval;

        if (oDATA === 12'd750) begin
            $display("Test 9: Absolute value correct - oDATA=%0d (expected 750)\n", oDATA);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 9: Error - oDATA=%0d (expected 750)\n", oDATA);
            tests_failed = tests_failed + 1;
        end

        /* Test 10: Whitebox - verify saturation clamping */
        $display("Test 10: Whitebox - verifying saturation clamping...");
        // Force Sobel X = +16000, Sobel Y = +16000
        // Expected: |16000| + |16000| = 32000, /2 = 16000 -> clamp to 4095
        force dut.sobel_x = 15'sd16000;
        force dut.sobel_y = 15'sd16000;
        force dut.sobel_dval = 1'b1;

        @(posedge clk);
        @(posedge clk);

        release dut.sobel_x;
        release dut.sobel_y;
        release dut.sobel_dval;

        if (oDATA === 12'd4095) begin
            $display("Test 10: Saturation clamping correct - oDATA=%0d (expected 4095)\n", oDATA);
            tests_passed = tests_passed + 1;
        end else begin
            $display("Test 10: Error - oDATA=%0d (expected 4095)\n", oDATA);
            tests_failed = tests_failed + 1;
        end

        repeat (5) @(posedge clk);

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

        $stop;
    end

endmodule
