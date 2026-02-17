// --------------------------------------------------------------------
// Module:      sobel_conv_3x3
// Description: Applies Sobel X and Sobel Y 3x3 convolution kernels to
//              a grayscale image stream. Receives three row taps from
//              grayscale_row_buffer, forms a 3x3 pixel window using
//              column delay registers, and computes both horizontal and
//              vertical gradient outputs (signed).
//
//              Sobel X (vertical edges):    Sobel Y (horizontal edges):
//                -1  0  1                    -1 -2 -1
//                -2  0  2                     0  0  0
//                -1  0  1                     1  2  1
//
//
// Pipeline block: "3x3 Conv" from the lab spec diagram:
//   [Grey Scale Row Buffers] -> [3x3 Conv] -> [Absolute Value]
//
// Pipeline latency: 2 clocks from row buffer output to Sobel output
//   Stage 1: data_valid (iDVAL delayed 1 clock) — column shift + compute
//   Stage 2: Registered output
// --------------------------------------------------------------------

module sobel_conv_3x3 (
    input                    iCLK,      // Pixel clock
    input                    iRST,      // Active-low async reset
    input             [11:0] iRow0,     // Newest row  (oTap0 from grayscale_row_buffer)
    input             [11:0] iRow1,     // Middle row  (oTap1)
    input             [11:0] iRow2,     // Oldest row  (oTap2)
    input                    iDVAL,     // Data valid (from bayer_to_grayscale oDVAL)
    output reg signed [14:0] oSobelX,   // Sobel X gradient (signed, 15-bit)
    output reg signed [14:0] oSobelY,   // Sobel Y gradient (signed, 15-bit)
    output reg               oDVAL      // Output data valid
);

// ------------------------------------------------------------------
// Pipeline valid delay
// The grayscale_row_buffer adds 1 clock of registered latency.
// data_valid is aligned with the row buffer outputs (oTap0/1/2).
// ------------------------------------------------------------------
reg data_valid;

always @(posedge iCLK or negedge iRST) begin
    if (!iRST) data_valid <= 1'b0;
    else        data_valid <= iDVAL;
end

// ------------------------------------------------------------------
// Column delay shift register (3x3 window formation)
//
// Both stages shift together when data_valid is high.
// Nonblocking assignments ensure d2 captures the OLD d1 value
// before d1 is updated with the new iRow value.
//
// After shift, the pre-update values form the 3x3 window:
//
//   d2_row2   d1_row2   iRow2     (oldest row, top)
//   d2_row1   d1_row1   iRow1     (middle row)
//   d2_row0   d1_row0   iRow0     (newest row, bottom)
// ------------------------------------------------------------------
reg [11:0] d1_row0, d1_row1, d1_row2;  // 1 column back
reg [11:0] d2_row0, d2_row1, d2_row2;  // 2 columns back

always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        d1_row0 <= 12'd0; d1_row1 <= 12'd0; d1_row2 <= 12'd0;
        d2_row0 <= 12'd0; d2_row1 <= 12'd0; d2_row2 <= 12'd0;
    end else if (data_valid) begin
        // Shift: d1 -> d2, current -> d1
        d2_row0 <= d1_row0; d2_row1 <= d1_row1; d2_row2 <= d1_row2;
        d1_row0 <= iRow0;   d1_row1 <= iRow1;   d1_row2 <= iRow2;
    end
end

// ------------------------------------------------------------------
// Sobel convolution (combinational)
//
// Uses pre-update d1/d2 values and current iRow values.
// At the posedge where data_valid is high, the window is:
//
//   p00=d2_row2  p01=d1_row2  p02=iRow2   (top row)
//   p10=d2_row1  p11=d1_row1  p12=iRow1   (middle row)
//   p20=d2_row0  p21=d1_row0  p22=iRow0   (bottom row)
//
// Bit width analysis:
//   12-bit unsigned pixels -> 15-bit signed intermediates
//   Max |Gx| or |Gy| = 4*4095 = 16380, fits in signed [14:0]
// ------------------------------------------------------------------

// Sign-extend 12-bit unsigned pixels to 15-bit signed
wire signed [14:0] p00 = {3'b0, d2_row2};
wire signed [14:0] p01 = {3'b0, d1_row2};
wire signed [14:0] p02 = {3'b0, iRow2};
wire signed [14:0] p10 = {3'b0, d2_row1};
wire signed [14:0] p12 = {3'b0, iRow1};
wire signed [14:0] p20 = {3'b0, d2_row0};
wire signed [14:0] p21 = {3'b0, d1_row0};
wire signed [14:0] p22 = {3'b0, iRow0};


wire signed [14:0] sobel_x = (p02 - p00) + (p12 - p10) + (p12 - p10) + (p22 - p20);


wire signed [14:0] sobel_y = (p20 + p21 + p21 + p22) - (p00 + p01 + p01 + p02);

// ------------------------------------------------------------------
// Output register
// Sobel results are registered when data_valid is high.
// oDVAL is delayed 1 clock from data_valid to match the registered data.
// ------------------------------------------------------------------
always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        oSobelX <= 15'sd0;
        oSobelY <= 15'sd0;
        oDVAL   <= 1'b0;
    end else begin
        oDVAL <= data_valid;
        if (data_valid) begin
            oSobelX <= sobel_x;
            oSobelY <= sobel_y;
        end
    end
end

endmodule
