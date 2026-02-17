// --------------------------------------------------------------------
// Module:      grayscale_row_buffer
// Description: Two chained RAM-based circular buffers that store two
//              full rows of 640-pixel grayscale data. Provides three
//              simultaneous taps at the same column position:
//                oTap0 = current row   (row N)
//                oTap1 = previous row  (row N-1)
//                oTap2 = two rows back (row N-2)
//
//              These three rows are required by the downstream 3x3
//              convolution stage to form the Sobel kernel window.
//

//
// Pipeline block: "Grey Scale Row Buffers" from the lab spec diagram:
//   [Grey Scale] -> [Grey Scale Row Buffers] -> [3x3 Conv]
//
// Pipeline latency: 1 clock (registered outputs)
//
// Architecture:
//   line_mem_a holds the most recent complete row (1-row delay).
//   line_mem_b holds the row before that (2-row delay).
//   On each valid clock, the cascade shifts data through:
//     line_mem_b[addr] <- line_mem_a[addr]  (promote to oldest)
//     line_mem_a[addr] <- iDATA             (store new pixel)
//   All reads occur before writes (nonblocking assignment semantics).
//
// IMPORTANT: This must use a SINGLE always block so that both buffers
//   update atomically. Chaining two separate bayer_row_buffer instances
//   with the same iDVAL causes an off-by-one error because the second
//   buffer reads the first buffer's oTap1 BEFORE its NB update.
// --------------------------------------------------------------------

module grayscale_row_buffer (
    input             iCLK,       // Pixel clock
    input             iRST,       // Active-low async reset
    input      [11:0] iDATA,      // 12-bit grayscale pixel from bayer_to_grayscale
    input             iDVAL,      // Data valid (640x480 rate)
    output     [11:0] oTap0,      // Current row pixel (registered)
    output     [11:0] oTap1,      // Previous row pixel (1 row back)
    output     [11:0] oTap2       // Two rows back pixel
);

parameter ROW_WIDTH = 640;

// ------------------------------------------------------------------
// Two circular buffer RAMs — Quartus infers M10K block RAM.
// line_mem_a: stores data written ROW_WIDTH valid-clocks ago (1 row)
// line_mem_b: stores data written 2*ROW_WIDTH valid-clocks ago (2 rows)
// ------------------------------------------------------------------
reg [11:0] line_mem_a [0:ROW_WIDTH-1];
reg [11:0] line_mem_b [0:ROW_WIDTH-1];
reg  [9:0] wr_addr;

// Initialize memory to 0 (matches M10K power-up behavior on FPGA)
integer i;
initial begin
    for (i = 0; i < ROW_WIDTH; i = i + 1) begin
        line_mem_a[i] = 12'd0;
        line_mem_b[i] = 12'd0;
    end
end

// Registered tap outputs
reg [11:0] tap0_reg;   // Current pixel (1-cycle registered passthrough)
reg [11:0] tap1_reg;   // Previous-row pixel (ROW_WIDTH-cycle delay)
reg [11:0] tap2_reg;   // Two-rows-back pixel (2*ROW_WIDTH-cycle delay)

always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        wr_addr  <= 10'd0;
        tap0_reg <= 12'd0;
        tap1_reg <= 12'd0;
        tap2_reg <= 12'd0;
    end else if (iDVAL) begin
        // Read-before-write cascade (all RHS sampled before any LHS update):

        // tap2 gets the oldest data (2 rows back)
        tap2_reg <= line_mem_b[wr_addr];

        // Promote line_mem_a entry to line_mem_b (shift the delay chain)
        line_mem_b[wr_addr] <= line_mem_a[wr_addr];

        // tap1 gets the previous-row data (1 row back)
        tap1_reg <= line_mem_a[wr_addr];

        // Write current pixel into line_mem_a
        line_mem_a[wr_addr] <= iDATA;

        // Pass current pixel through (registered for alignment)
        tap0_reg <= iDATA;

        // Advance write pointer with wrap
        wr_addr <= (wr_addr == ROW_WIDTH - 1) ? 10'd0 : wr_addr + 10'd1;
    end
end

assign oTap0 = tap0_reg;
assign oTap1 = tap1_reg;
assign oTap2 = tap2_reg;

endmodule
