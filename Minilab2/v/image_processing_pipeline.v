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
    output     [11:0] oDATA,         // 12-bit edge magnitude
    output            oDVAL          // Output data valid
);

// ------------------------------------------------------------------
// Internal wires
// ------------------------------------------------------------------

// Bayer row buffer → bayer_to_grayscale
wire [11:0] bayer_tap0;             // Current row pixel
wire [11:0] bayer_tap1;             // Previous row pixel

// bayer_to_grayscale → grayscale_row_buffer
wire [11:0] gray_data;              // 12-bit grayscale output
wire        gray_dval;              // Grayscale data valid (640x480 rate)

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
// Block 3: Grey Scale Row Buffers
//   Buffers two rows of 640-pixel grayscale data.
//   Provides 3 simultaneous row taps for 3x3 convolution.
// ------------------------------------------------------------------
grayscale_row_buffer #(
    .ROW_WIDTH(640)
) u_gray_row_buf (
    .iCLK  (iCLK),
    .iRST  (iRST),
    .iDATA (gray_data),
    .iDVAL (gray_dval),
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
    .iDVAL   (gray_dval),
    .oSobelX (sobel_x),
    .oSobelY (sobel_y),
    .oDVAL   (sobel_dval)
);

// ------------------------------------------------------------------
// Block 5: Absolute Value
//   Computes |Gx| + |Gy| and scales to 12-bit (divide by 8).
// ------------------------------------------------------------------
sobel_abs_value u_abs_val (
    .iCLK    (iCLK),
    .iRST    (iRST),
    .iSobelX (sobel_x),
    .iSobelY (sobel_y),
    .iDVAL   (sobel_dval),
    .oEdge   (oDATA),
    .oDVAL   (oDVAL)
);

endmodule
