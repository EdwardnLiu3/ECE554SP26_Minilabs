// --------------------------------------------------------------------
// Module:      bayer_to_grayscale
// Description: Converts Bayer pattern pixels to grayscale by averaging
//              each 2x2 Bayer block (R + G + G + B) / 4. Takes the
//              current-row and previous-row taps from bayer_row_buffer,
//              registers them for previous-column access, and outputs
//              one grayscale pixel per 2x2 block. Downsamples from
//              1280x960 Bayer to 640x480 grayscale.
//
//
// Pipeline block: "Grey Scale" from the lab spec diagram:
//   [Bayer Pixel Row Buffers] -> [Grey Scale] -> [Grey Scale Row Buffers]
//                             -> [3x3 Conv] -> [Absolute Value]
//
// Pipeline latency: 4 clocks from row buffer output to grayscale output
//   Stage 1: Register previous-column values (dval_d1)
//   Stage 2: Compute gray average (combinational gray_val)
//   Stage 3-4: gray_val_d1, gray_val_d2 pipeline registers
//   Output: Register with valid gating (dval_d4, x_d4, y_d4)
// --------------------------------------------------------------------

module bayer_to_grayscale (
    input             iCLK,       // D5M pixel clock
    input             iRST,       // Active-low async reset
    input      [11:0] iCurrRow,   // Current row pixel (oTap0 from row buffer)
    input      [11:0] iPrevRow,   // Previous row pixel (oTap1 from row buffer)
    input             iDVAL,      // Data valid from CCD_Capture
    input      [10:0] iX_Cont,    // Bayer X coordinate from CCD_Capture
    input      [10:0] iY_Cont,    // Bayer Y coordinate from CCD_Capture
    output reg [11:0] oGray,      // 12-bit grayscale output
    output reg        oDVAL       // Grayscale data valid (640x480 rate)
);

// ------------------------------------------------------------------
// Pipeline coordinate delay (4 stages)
// The row buffer adds 1 clock of latency (registered output).
// The previous-column register adds 1 more clock.
// The gray_val_d1 and gray_val_d2 registers add 2 more clocks.
// Delay X/Y coordinates by 4 clocks to stay aligned with the data.
// ------------------------------------------------------------------
reg [10:0] x_d1, y_d1;
reg        dval_d1;
reg [10:0] x_d2, y_d2;
reg        dval_d2;
reg [10:0] x_d3, y_d3;
reg        dval_d3;
reg [10:0] x_d4, y_d4;
reg        dval_d4;

always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        x_d1 <= 11'd0;  y_d1 <= 11'd0;  dval_d1 <= 1'b0;
        x_d2 <= 11'd0;  y_d2 <= 11'd0;  dval_d2 <= 1'b0;
        x_d3 <= 11'd0;  y_d3 <= 11'd0;  dval_d3 <= 1'b0;
        x_d4 <= 11'd0;  y_d4 <= 11'd0;  dval_d4 <= 1'b0;
    end else begin
        x_d1 <= iX_Cont;  y_d1 <= iY_Cont;  dval_d1 <= iDVAL;
        x_d2 <= x_d1;     y_d2 <= y_d1;     dval_d2 <= dval_d1;
        x_d3 <= x_d2;     y_d3 <= y_d2;     dval_d3 <= dval_d2;
        x_d4 <= x_d3;     y_d4 <= y_d3;     dval_d4 <= dval_d3;
    end
end

// ------------------------------------------------------------------
// Previous-column registers
// Register the row buffer outputs by 1 DVAL-clock to capture the
// pixel from the previous column in both current and previous rows.
// Update only when dval_d1 is high (aligned with row buffer output).
// ------------------------------------------------------------------
reg [11:0] prev_curr_row;    // Current row, previous column
reg [11:0] prev_prev_row;    // Previous row, previous column

always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        prev_curr_row <= 12'd0;
        prev_prev_row <= 12'd0;
    end else if (dval_d1) begin
        prev_curr_row <= iCurrRow;
        prev_prev_row <= iPrevRow;
    end
end

// ------------------------------------------------------------------
// 2x2 Bayer block average (combinational)
//
// When the pipeline is aligned, the four values form a 2x2 block:
//
//   prev_prev_row   iPrevRow       (previous row: col X, col X+1)
//   prev_curr_row   iCurrRow       (current  row: col X, col X+1)
//
// Bayer pattern (even row starts with R):
//   R  G      Gray = (R + G_r + G_b + B) / 4
//   G  B
//
// The /4 is implemented by taking bits [13:2] of the 14-bit sum.
// ------------------------------------------------------------------
wire [13:0] gray_sum = {2'b0, prev_prev_row} + {2'b0, iPrevRow}
                     + {2'b0, prev_curr_row} + {2'b0, iCurrRow};
wire [11:0] gray_val = gray_sum[13:2];

// ------------------------------------------------------------------
// Extra pipeline delay for gray_val (2 stages)
// These free-running registers add 2 clocks of latency to the gray
// data, improving timing closure. The coordinate delays above are
// extended to 4 stages (d1-d4) to stay aligned with this data.
// ------------------------------------------------------------------
reg [11:0] gray_val_d1;
reg [11:0] gray_val_d2;

always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        gray_val_d1 <= 12'd0;
        gray_val_d2 <= 12'd0;
    end else begin
        gray_val_d1 <= gray_val;
        gray_val_d2 <= gray_val_d1;
    end
end

// ------------------------------------------------------------------
// Output register with valid gating
//
// Uses d4-stage coordinates (aligned with gray_val_d2 data):
//   - x_d4 is odd   (RIGHT column of the 2x2 block, so the block
//                     starts at column x_d4-1 which is even)
//   - y_d4 is odd   (block spans even row y_d4-1 and odd row y_d4)
//   - dval_d4 is high
//
// This produces 640 pixels per row x 480 rows = 307,200 per frame.
// ------------------------------------------------------------------
always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        oGray <= 12'd0;
        oDVAL <= 1'b0;
    end else if (dval_d4) begin
        oGray <= gray_val_d2;
        oDVAL <= (x_d4[0] == 1'b1) && (y_d4[0] == 1'b1);
    end else begin
        oDVAL <= 1'b0;
    end
end

endmodule
