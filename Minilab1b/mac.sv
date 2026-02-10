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

  // Pipeline stage 1: register inputs and control signals
  logic [DATA_WIDTH-1:0] Ain_reg, Bin_reg;
  logic En_reg, Clr_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      Ain_reg <= {DATA_WIDTH{1'b0}};
      Bin_reg <= {DATA_WIDTH{1'b0}};
      En_reg <= 1'b0;
      Clr_reg <= 1'b0;
    end else begin
      Ain_reg <= Ain;
      Bin_reg <= Bin;
      En_reg <= En;
      Clr_reg <= Clr;
    end
  end

  // Pipeline stage 2: register multiplication result
  logic [DATA_WIDTH*2-1:0] product_reg;
  logic En_reg2, Clr_reg2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      product_reg <= {(DATA_WIDTH*2){1'b0}};
      En_reg2 <= 1'b0;
      Clr_reg2 <= 1'b0;
    end else begin
      product_reg <= Ain_reg * Bin_reg;
      En_reg2 <= En_reg;
      Clr_reg2 <= Clr_reg;
    end
  end

  // Output assignment
  assign Cout = accumulator;

  // Pipeline stage 3: MAC accumulation
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      accumulator <= {(DATA_WIDTH*3){1'b0}};
    end
    else if (Clr_reg2) begin
      accumulator <= {(DATA_WIDTH*3){1'b0}};
    end
    else if (En_reg2) begin
      accumulator <= accumulator + product_reg;
    end
  end

endmodule
