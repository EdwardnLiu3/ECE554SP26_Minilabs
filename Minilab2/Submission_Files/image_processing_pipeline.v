// --------------------------------------------------------------------
// Module:      image_processing_pipeline
// Description: Top-level wrapper that connects all five image processing
//              blocks into a single module. Replaces RAW2RGB in the
//              DE1_SoC_CAMERA top-level, converting raw Bayer pixels
//              from the D5M camera into Sobel edge-detected grayscale.
//
//              Pipeline:
//                [Bayer Row Buffer]      1280x960 → 2 row taps
//                [Bayer to Grayscale]    2x2 block avg → 640x480
//                [Grayscale Row Buffer]  640x480 → 3 row taps
//                [3x3 Sobel Conv]        Sobel X & Y gradients
//                [Absolute Value]        |Gx|+|Gy| / 8 → 12-bit edge
//
// Written by:  Student (custom module for image processing pipeline)
//
// Interface: Drop-in replacement for RAW2RGB in DE1_SoC_CAMERA.v
//   Input:  Bayer pixels + valid + coordinates from CCD_Capture
//   Output: 12-bit edge magnitude + valid for SDRAM write
// --------------------------------------------------------------------

module image_processing_pipeline (
    input             iCLK,          // D5M pixel clock
    input             iRST,          // Active-low async reset
    input      [11:0] iDATA,         // 12-bit Bayer pixel from CCD_Capture
    input             iDVAL,         // Data valid from CCD_Capture
    input      [15:0] iX_Cont,       // X coordinate from CCD_Capture
    input      [15:0] iY_Cont,       // Y coordinate from CCD_Capture
    input      [1:0]  iMode,         // Filter mode: 00=combined, 01=Gx, 10=Gy
    output     [11:0] oDATA,         // 12-bit edge magnitude
    output            oDVAL          // Output data valid
);

// ------------------------------------------------------------------
// Internal wires
// ------------------------------------------------------------------

// Bayer row buffer → bayer_to_grayscale
wire [11:0] bayer_tap0;             // Current row pixel
wire [11:0] bayer_tap1;             // Previous row pixel

// bayer_to_grayscale → horizontal smooth
wire [11:0] gray_data;              // 12-bit grayscale output
wire        gray_dval;              // Grayscale data valid (640x480 rate)

// horizontal smooth → grayscale_row_buffer
wire [11:0] smooth_data;            // Smoothed grayscale output
wire        smooth_dval;            // Smoothed data valid

// grayscale_row_buffer → sobel_conv_3x3
wire [11:0] gray_tap0;             // Current row (newest)
wire [11:0] gray_tap1;             // Previous row
wire [11:0] gray_tap2;             // Two rows back (oldest)

// sobel_conv_3x3 → sobel_abs_value
wire signed [14:0] sobel_x;        // Sobel X gradient
wire signed [14:0] sobel_y;        // Sobel Y gradient
wire               sobel_dval;     // Sobel data valid

// ------------------------------------------------------------------
// Block 1: Bayer Pixel Row Buffer
//   Buffers one full row (1280 pixels) of Bayer data.
//   Provides current-row and previous-row taps at the same column.
// ------------------------------------------------------------------
bayer_row_buffer #(
    .ROW_WIDTH(1280)
) u_bayer_row_buf (
    .iCLK  (iCLK),
    .iRST  (iRST),
    .iDATA (iDATA),
    .iDVAL (iDVAL),
    .oTap0 (bayer_tap0),
    .oTap1 (bayer_tap1)
);

// ------------------------------------------------------------------
// Block 2: Grey Scale (Bayer to Grayscale)
//   Averages each 2x2 Bayer block (R+G+G+B)/4.
//   Downsamples from 1280x960 to 640x480.
// ------------------------------------------------------------------
bayer_to_grayscale u_bayer_to_gray (
    .iCLK     (iCLK),
    .iRST     (iRST),
    .iCurrRow (bayer_tap0),
    .iPrevRow (bayer_tap1),
    .iDVAL    (iDVAL),
    .iX_Cont  (iX_Cont[10:0]),
    .iY_Cont  (iY_Cont[10:0]),
    .oGray    (gray_data),
    .oDVAL    (gray_dval)
);

// ------------------------------------------------------------------
// Block 2.5: Horizontal Gaussian smooth [1,2,1]/4
//   Reduces sensor noise before edge detection. The Sobel operator
//   is a high-pass filter that amplifies pixel-to-pixel noise.
//   This 1D low-pass smooths each row horizontally, suppressing
//   noise while preserving edge structure.
//   Adds 1 clock of pipeline latency.
// ------------------------------------------------------------------
reg [11:0] gray_d1;      // 1-pixel delay
reg [11:0] gray_d2;      // 2-pixel delay
reg        smooth_dval_r; // delayed valid

always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        gray_d1       <= 12'd0;
        gray_d2       <= 12'd0;
        smooth_dval_r <= 1'b0;
    end else begin
        smooth_dval_r <= gray_dval;
        if (gray_dval) begin
            gray_d1 <= gray_data;
            gray_d2 <= gray_d1;
        end
    end
end

// [1,2,1]/4 Gaussian: center-weighted average of 3 consecutive pixels
// At the clock where gray_dval is high for pixel N:
//   gray_d2 = pixel N-2, gray_d1 = pixel N-1, gray_data = pixel N
//   smooth = (pixel[N-2] + 2*pixel[N-1] + pixel[N]) / 4
wire [13:0] smooth_sum = {2'b0, gray_d2} + {1'b0, gray_d1, 1'b0} + {2'b0, gray_data};

assign smooth_data = smooth_sum[13:2];
assign smooth_dval = smooth_dval_r;

// ------------------------------------------------------------------
// Block 3: Grey Scale Row Buffers
//   Buffers two rows of 640-pixel grayscale data.
//   Provides 3 simultaneous row taps for 3x3 convolution.
// ------------------------------------------------------------------
grayscale_row_buffer #(
    .ROW_WIDTH(640)
) u_gray_row_buf (
    .iCLK  (iCLK),
    .iRST  (iRST),
    .iDATA (smooth_data),
    .iDVAL (smooth_dval),
    .oTap0 (gray_tap0),
    .oTap1 (gray_tap1),
    .oTap2 (gray_tap2)
);

// ------------------------------------------------------------------
// Block 4: 3x3 Convolution (Sobel Edge Detection)
//   Forms a 3x3 pixel window and applies Sobel X and Sobel Y kernels.
//   iDVAL = gray_dval (conv module delays internally for row buffer).
// ------------------------------------------------------------------
sobel_conv_3x3 u_sobel_conv (
    .iCLK    (iCLK),
    .iRST    (iRST),
    .iRow0   (gray_tap0),
    .iRow1   (gray_tap1),
    .iRow2   (gray_tap2),
    .iDVAL   (smooth_dval),
    .oSobelX (sobel_x),
    .oSobelY (sobel_y),
    .oDVAL   (sobel_dval)
);

// ------------------------------------------------------------------
// Block 5: Absolute Value
//   Mode-selectable: |Gx| only, |Gy| only, or combined |Gx|+|Gy|.
//   Scales to 12-bit (divide by 4) with noise threshold.
// ------------------------------------------------------------------
sobel_abs_value u_abs_val (
    .iCLK    (iCLK),
    .iRST    (iRST),
    .iSobelX (sobel_x),
    .iSobelY (sobel_y),
    .iDVAL   (sobel_dval),
    .iMode   (iMode),
    .oEdge   (oDATA),
    .oDVAL   (oDVAL)
);

endmodule
