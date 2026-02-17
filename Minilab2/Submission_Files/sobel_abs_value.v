// --------------------------------------------------------------------
// Module:      sobel_abs_value
// Description: Computes the gradient magnitude from signed Sobel X and
//              Sobel Y outputs. Supports three display modes selected
//              by iMode:
//                00/11: Combined |Gx| + |Gy| (both edges)
//                01:    |Gx| only (vertical edges)
//                10:    |Gy| only (horizontal edges)
//
//              Includes a noise threshold — gradients below THRESHOLD
//              are suppressed to zero (black) to reduce sensor noise.
//
// Pipeline block: "Absolute Value" from the lab spec diagram:
//   [3x3 Conv] -> [Absolute Value] -> SDRAM write
//
// Pipeline latency: 1 clock (registered output)
// --------------------------------------------------------------------

module sobel_abs_value (
    input                    iCLK,      // Pixel clock
    input                    iRST,      // Active-low async reset
    input      signed [14:0] iSobelX,   // Sobel X gradient from sobel_conv_3x3
    input      signed [14:0] iSobelY,   // Sobel Y gradient from sobel_conv_3x3
    input                    iDVAL,     // Data valid from sobel_conv_3x3
    input             [1:0]  iMode,     // 00/11: combined, 01: Gx only, 10: Gy only
    output reg        [11:0] oEdge,     // 12-bit unsigned edge magnitude
    output reg               oDVAL      // Output data valid
);

// Noise threshold: gradients below this are set to 0 (black)
parameter THRESHOLD = 12'd60;

// ------------------------------------------------------------------
// Absolute values (combinational)
//   Input range:  [-16380, 16380] (signed 15-bit)
//   Output range: [0, 16380]      (unsigned 15-bit)
// ------------------------------------------------------------------
wire [14:0] abs_x = iSobelX[14] ? -iSobelX : iSobelX;
wire [14:0] abs_y = iSobelY[14] ? -iSobelY : iSobelY;

// ------------------------------------------------------------------
// Mode-dependent gradient selection
//   Combined: |Gx| + |Gy|   range [0, 32760]  -> /4 = [0, 8190]
//   Gx only:  |Gx|          range [0, 16380]  -> /4 = [0, 4095]
//   Gy only:  |Gy|          range [0, 16380]  -> /4 = [0, 4095]
// ------------------------------------------------------------------
reg [15:0] grad_mag;

always @(*) begin
    case (iMode)
        2'b01:   grad_mag = {1'b0, abs_x};           // Gx only
        2'b10:   grad_mag = {1'b0, abs_y};           // Gy only
        default: grad_mag = {1'b0, abs_x} + {1'b0, abs_y}; // combined
    endcase
end

// ------------------------------------------------------------------
// Scale to 12-bit: divide by 4 (right-shift 2) with saturation
//   Combined max: 32760 / 4 = 8190 → clamp to 4095
//   Individual max: 16380 / 4 = 4095 → fits exactly
// ------------------------------------------------------------------
wire [13:0] scaled = grad_mag[15:2];
wire [11:0] scaled_12 = (|scaled[13:12]) ? 12'd4095 : scaled[11:0];

// ------------------------------------------------------------------
// Noise suppression: zero out values below threshold
// ------------------------------------------------------------------
wire [11:0] edge_val = (scaled_12 < THRESHOLD) ? 12'd0 : scaled_12;

// ------------------------------------------------------------------
// Output register
// ------------------------------------------------------------------
always @(posedge iCLK or negedge iRST) begin
    if (!iRST) begin
        oEdge <= 12'd0;
        oDVAL <= 1'b0;
    end else begin
        oDVAL <= iDVAL;
        if (iDVAL) begin
            oEdge <= edge_val;
        end
    end
end

endmodule
