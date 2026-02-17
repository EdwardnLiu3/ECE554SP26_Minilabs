    // --------------------------------------------------------------------
// Module:      bayer_row_buffer
// Description: RAM-based shift register that buffers one full row of
//              Bayer pixels from the D5M camera (1280 pixels). Provides
//              two outputs: the current pixel and the pixel from the
//              previous row at the same column position. These two rows
//              are needed by the downstream grayscale interpolation stage
//              to form 2x2 Bayer blocks.
//
//
// Pipeline block: "Bayer Pixel Row Buffers" from the lab spec diagram:
//   [Bayer Pixel Row Buffers] -> [Grey Scale] -> [Grey Scale Row Buffers]
//                             -> [3x3 Conv] -> [Absolute Value]
// --------------------------------------------------------------------

module bayer_row_buffer (
    input             iCLK,       // D5M pixel clock
    input             iRST,       // Active-low async reset
    input      [11:0] iDATA,      // 12-bit Bayer pixel from CCD_Capture
    input             iDVAL,      // Data valid (FVAL & LVAL)
    output     [11:0] oTap0,      // Current row pixel (registered)
    output     [11:0] oTap1       // Previous row pixel (ROW_WIDTH delayed)
);

parameter ROW_WIDTH = 1280;

// ------------------------------------------------------------------
// Circular buffer RAM — Quartus infers M10K block RAM for this.
// Depth = ROW_WIDTH (one full camera row).
// At each valid pixel clock, we read the oldest entry (written
// ROW_WIDTH valid-clocks ago = same column, previous row) and then
// overwrite that location with the incoming pixel.
// ------------------------------------------------------------------
reg [11:0] line_mem [0:ROW_WIDTH-1];
reg [10:0] wr_addr;

// Initialize memory to 0 (matches M10K power-up behavior on FPGA)
integer i;
initial begin
    for (i = 0; i < ROW_WIDTH; i = i + 1)
        line_mem[i] = 12'd0;
end

// Registered tap outputs
reg [11:0] tap0_reg;   // Current pixel (1-cycle registered passthrough)
reg [11:0] tap1_reg;   // Previous-row pixel (ROW_WIDTH-cycle delay)

always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        wr_addr  <= 11'd0;
        tap0_reg <= 12'd0;
        tap1_reg <= 12'd0;
    end else if (iDVAL) begin
        // Read-before-write: tap1 gets the data that was stored
        // ROW_WIDTH valid clocks ago (previous row, same column)
        tap1_reg <= line_mem[wr_addr];

        // Write current pixel into the buffer
        line_mem[wr_addr] <= iDATA;

        // Pass current pixel through (registered for alignment)
        tap0_reg <= iDATA;

        // Advance write pointer with wrap
        wr_addr <= (wr_addr == ROW_WIDTH - 1) ? 11'd0 : wr_addr + 11'd1;
    end
end

assign oTap0 = tap0_reg;
assign oTap1 = tap1_reg;

endmodule
