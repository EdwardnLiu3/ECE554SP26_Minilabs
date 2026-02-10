module fifo_tb ();
    logic rst_n, clk;
    logic rden, wren;
    logic [7:0] i_data;
    logic [7:0] o_data;
    logic full, empty;

    FIFO #(.DEPTH(8), .DATA_WIDTH(8)) test1 (
        .clk(clk),
        .rst_n(rst_n),
        .rden(rden),
        .wren(wren),
        .i_data(i_data),
        .o_data(o_data),
        .full(full),
        .empty(empty)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        rden = 0;
        wren = 0;
        i_data = 8'h00;
        @(posedge clk);
        @(negedge clk);
        rst_n = 1; // deassert reset
        repeat (5) @(posedge clk);

        /* Test 1: Check initial empty condition */
        if(empty === 1'b1 && full === 1'b0) begin
            $display("Test 1: Initial empty state works\n");
        end
        else begin
            $display("Test 1: Error - Expected empty=1, full=0, got empty=%b, full=%b\n", empty, full);
        end
        repeat (2) @(posedge clk);

        /* Test 2: Write single value (0xAA) */
        i_data = 8'hAA;
        wren = 1;
        @(posedge clk);
        wren = 0;
        repeat (2) @(posedge clk);
        if(empty === 1'b0) begin
            $display("Test 2: Write operation works (not empty after write)\n");
        end
        else begin
            $display("Test 2: Error - FIFO should not be empty after write\n");
        end
        repeat (2) @(posedge clk);

        /* Test 3: Read the value back */
        if(o_data === 8'hAA) begin
            $display("Test 3: Read operation works (got 0xAA)\n");
        end
        else begin
            $display("Test 3: Error - Expected 0xAA, got %h\n", o_data);
        end
        rden = 1;
        @(posedge clk);
        rden = 0;
        repeat (2) @(posedge clk);

        /* Test 4: FIFO should be empty after reading the only element */
        if(empty === 1'b1) begin
            $display("Test 4: Empty flag works after reading\n");
        end
        else begin
            $display("Test 4: Error - FIFO should be empty\n");
        end
        repeat (2) @(posedge clk);

        /* Test 5: Write multiple values */
        wren = 1;
        i_data = 8'h11;
        @(posedge clk);
        i_data = 8'h22;
        @(posedge clk);
        i_data = 8'h33;
        @(posedge clk);
        i_data = 8'h44;
        @(posedge clk);
        wren = 0;
        repeat (2) @(posedge clk);
        if(empty === 1'b0 && full === 1'b0) begin
            $display("Test 5: Multiple writes work (not empty, not full)\n");
        end
        else begin
            $display("Test 5: Error - After 4 writes, expected empty=0, full=0\n");
        end
        repeat (2) @(posedge clk);

        /* Test 6: Read values in FIFO order */
        if(o_data === 8'h11) begin
            $display("Test 6a: First read (0x11) correct\n");
        end
        else begin
            $display("Test 6a: Error - Expected 0x11, got %h\n", o_data);
        end
        rden = 1;
        @(posedge clk);
        #1;  // Allow NBA and combinational logic to settle
        if(o_data === 8'h22) begin
            $display("Test 6b: Second read (0x22) correct\n");
        end
        else begin
            $display("Test 6b: Error - Expected 0x22, got %h\n", o_data);
        end
        @(posedge clk);
        #1;  // Allow NBA and combinational logic to settle
        if(o_data === 8'h33) begin
            $display("Test 6c: Third read (0x33) correct\n");
        end
        else begin
            $display("Test 6c: Error - Expected 0x33, got %h\n", o_data);
        end
        @(posedge clk);
        #1;  // Allow NBA and combinational logic to settle
        if(o_data === 8'h44) begin
            $display("Test 6d: Fourth read (0x44) correct\n");
        end
        else begin
            $display("Test 6d: Error - Expected 0x44, got %h\n", o_data);
        end
        @(posedge clk);
        rden = 0;
        repeat (2) @(posedge clk);

        /* Test 7: Fill FIFO to capacity (8 elements) */
        wren = 1;
        i_data = 8'h01;
        @(posedge clk);
        i_data = 8'h02;
        @(posedge clk);
        i_data = 8'h03;
        @(posedge clk);
        i_data = 8'h04;
        @(posedge clk);
        i_data = 8'h05;
        @(posedge clk);
        i_data = 8'h06;
        @(posedge clk);
        i_data = 8'h07;
        @(posedge clk);
        i_data = 8'h08;
        @(posedge clk);
        wren = 0;
        repeat (2) @(posedge clk);
        if(full === 1'b1) begin
            $display("Test 7: Full flag works (FIFO is full)\n");
        end
        else begin
            $display("Test 7: Error - FIFO should be full after 8 writes\n");
        end
        repeat (2) @(posedge clk);

        /* Test 8: Attempt to write when full (should not write) */
        wren = 1;
        i_data = 8'hFF;
        @(posedge clk);
        wren = 0;
        repeat (2) @(posedge clk);
        if(full === 1'b1) begin
            $display("Test 8: Write blocked when full works\n");
        end
        else begin
            $display("Test 8: Error - FIFO should remain full\n");
        end
        repeat (2) @(posedge clk);

        /* Test 9: Read one element, FIFO should no longer be full */
        rden = 1;
        @(posedge clk);
        @(posedge clk);
        rden = 0;
        repeat (2) @(posedge clk);
        if(full === 1'b0 && empty === 1'b0) begin
            $display("Test 9: FIFO not full after one read\n");
        end
        else begin
            $display("Test 9: Error - After reading one element, full should be 0\n");
        end
        repeat (2) @(posedge clk);

        /* Test 10: Empty the FIFO completely */
        rden = 1;
        repeat (7) @(posedge clk);
        rden = 0;
        repeat (2) @(posedge clk);
        if(empty === 1'b1 && full === 1'b0) begin
            $display("Test 10: FIFO empty after reading all elements\n");
        end
        else begin
            $display("Test 10: Error - FIFO should be empty, got empty=%b, full=%b\n", empty, full);
        end
        repeat (5) @(posedge clk);

        $stop();
    end

    always
        #5 clk = ~clk;

endmodule
