module mac_tb ();
    logic rst_n, clk;
    logic En, Clr;
    logic [7:0] Ain;
    logic [7:0] Bin;
    logic [23:0] Cout;

    MAC #(.DATA_WIDTH(8)) test1 (
        .clk(clk),
        .rst_n(rst_n),
        .En(En),
        .Clr(Clr),
        .Ain(Ain),
        .Bin(Bin),
        .Cout(Cout)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        En = 0;
        Clr = 0;
        Ain = 8'h00;
        Bin = 8'h00;
        @(posedge clk);
        @(negedge clk);
        rst_n = 1; // deassert reset
        repeat (5) @(posedge clk);

        /* Test 1: Basic MAC operation 3*4 = 12 */
        Ain = 8'h03;
        Bin = 8'h04;
        En = 1;
        @(posedge clk);
        En = 0;
        repeat (2) @(posedge clk);
        if(Cout === 24'h00000C) begin
            $display("Test 1: Basic MAC (3*4 = 12) works\n");
        end
        else begin
            $display("Test 1: Error - Expected 24'h00000C, got %h\n", Cout);
        end
        repeat (2) @(posedge clk);

        /* Test 2: Accumulate another value 5*6 = 30, total = 12+30 = 42 */
        Ain = 8'h05;
        Bin = 8'h06;
        En = 1;
        @(posedge clk);
        En = 0;
        repeat (2) @(posedge clk);
        if(Cout === 24'h00002A) begin
            $display("Test 2: Accumulation (12 + 30 = 42) works\n");
        end
        else begin
            $display("Test 2: Error - Expected 24'h00002A, got %h\n", Cout);
        end
        repeat (2) @(posedge clk);

        /* Test 3: Clear accumulator */
        Clr = 1;
        @(posedge clk);
        Clr = 0;
        repeat (2) @(posedge clk);
        if(Cout === 24'h000000) begin
            $display("Test 3: Clear works\n");
        end
        else begin
            $display("Test 3: Error - Expected 24'h000000 after clear, got %h\n", Cout);
        end
        repeat (2) @(posedge clk);

        /* Test 4: MAC with larger values 255*255 = 65025 */
        Ain = 8'hFF;
        Bin = 8'hFF;
        En = 1;
        @(posedge clk);
        En = 0;
        repeat (2) @(posedge clk);
        if(Cout === 24'h00FE01) begin
            $display("Test 4: Large value MAC (255*255 = 65025) works\n");
        end
        else begin
            $display("Test 4: Error - Expected 24'h00FE01, got %h\n", Cout);
        end
        repeat (2) @(posedge clk);

        /* Test 5: Multiple accumulations 10*10 = 100, four times = 400 */
        Clr = 1;
        @(posedge clk);
        Clr = 0;
        Ain = 8'h0A;
        Bin = 8'h0A;
        repeat (4) begin
            En = 1;
            @(posedge clk);
            En = 0;
            @(posedge clk);
        end
        repeat (2) @(posedge clk);
        if(Cout === 24'h000190) begin
            $display("Test 5: Multiple accumulations (4 * 100 = 400) works\n");
        end
        else begin
            $display("Test 5: Error - Expected 24'h000190, got %h\n", Cout);
        end
        repeat (2) @(posedge clk);

        /* Test 6: Enable control - MAC should not accumulate when En=0 */
        Clr = 1;
        @(posedge clk);
        Clr = 0;
        Ain = 8'h07;
        Bin = 8'h08;
        En = 0;  // Keep enable low
        repeat (3) @(posedge clk);
        if(Cout === 24'h000000) begin
            $display("Test 6: Enable control works (no accumulation when En=0)\n");
        end
        else begin
            $display("Test 6: Error - Expected 24'h000000 when En=0, got %h\n", Cout);
        end
        repeat (2) @(posedge clk);

        /* Test 7: Zero inputs */
        Clr = 1;
        @(posedge clk);
        Clr = 0;
        Ain = 8'h00;
        Bin = 8'h00;
        En = 1;
        @(posedge clk);
        En = 0;
        repeat (2) @(posedge clk);
        if(Cout === 24'h000000) begin
            $display("Test 7: Zero inputs (0*0 = 0) works\n");
        end
        else begin
            $display("Test 7: Error - Expected 24'h000000, got %h\n", Cout);
        end
        repeat (5) @(posedge clk);

        $stop();
    end

    always
        #5 clk = ~clk;

endmodule
