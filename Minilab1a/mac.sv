module MAC #
(
parameter DATA_WIDTH = 8
)
(
input clk,
input rst_n,
input En,
input Clr,
input [DATA_WIDTH-1:0] Ain,
input [DATA_WIDTH-1:0] Bin,
output [DATA_WIDTH*3-1:0] Cout
);

  // Internal accumulator register
  logic [DATA_WIDTH*3-1:0] accumulator;

  // Product calculation (2*DATA_WIDTH bits needed for multiplication)
  logic [DATA_WIDTH*2-1:0] product;
  assign product = Ain * Bin;

  // Output assignment
  assign Cout = accumulator;

  // MAC logic
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      accumulator <= {(DATA_WIDTH*3){1'b0}};
    end
    else if (Clr) begin
      accumulator <= {(DATA_WIDTH*3){1'b0}};
    end
    else if (En) begin
      accumulator <= accumulator + product;
    end
  end

endmodule
