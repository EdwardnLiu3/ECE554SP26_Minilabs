// --------------------------------------------------------------------
// Module:      sobel_abs_value
// Description: Computes the gradient magnitude approximation from signed
//              Sobel X and Sobel Y outputs using the Manhattan distance:
//                 |Gx| + |Gy|
//              The 16-bit sum is scaled to 12-bit by dividing by 2
//              (right-shift 1) with saturation clamping to 4095.
//              This amplifies edges 4x vs /8 for better visibility.
//
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
    output reg        [11:0] oEdge,     // 12-bit unsigned edge magnitude
    output reg               oDVAL      // Output data valid
);

// ------------------------------------------------------------------
// Absolute values (combinational)
//   Input range:  [-16380, 16380] (signed 15-bit)
//   Output range: [0, 16380]      (unsigned 15-bit)
// ------------------------------------------------------------------
wire [14:0] abs_x = iSobelX[14] ? -iSobelX : iSobelX;
wire [14:0] abs_y = iSobelY[14] ? -iSobelY : iSobelY;

// ------------------------------------------------------------------
// Gradient magnitude: |Gx| + |Gy|
//   Range: [0, 32760] — fits in 16-bit unsigned
// ------------------------------------------------------------------
wire [15:0] grad_sum = {1'b0, abs_x} + {1'b0, abs_y};

// ------------------------------------------------------------------
// Scale to 12-bit: divide by 2 (right-shift 1) with saturation
//   Max: 32760 / 2 = 16380 → clamp to 4095 for 12-bit output
//   This gives 4x brighter edges than /8 for typical scenes.
// ------------------------------------------------------------------
wire [14:0] scaled = grad_sum[15:1];
wire [11:0] edge_val = (|scaled[14:12]) ? 12'd4095 : scaled[11:0];

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
