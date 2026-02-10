module FIFO
#(
  parameter DEPTH=8,
  parameter DATA_WIDTH=8
)
(
  input  clk,
  input  rst_n,
  input  rden,
  input  wren,
  input  [DATA_WIDTH-1:0] i_data,
  output [DATA_WIDTH-1:0] o_data,
  output full,
  output empty
);

  // Internal memory array
  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  // Read and write pointers
  logic [$clog2(DEPTH):0] wr_ptr;
  logic [$clog2(DEPTH):0] rd_ptr;

  // Full and empty logic
  assign full = (wr_ptr[$clog2(DEPTH)] != rd_ptr[$clog2(DEPTH)]) &&
                (wr_ptr[$clog2(DEPTH)-1:0] == rd_ptr[$clog2(DEPTH)-1:0]);
  assign empty = (wr_ptr == rd_ptr);

  // Output data (combinational read for zero latency to match MAC expectation)
  assign o_data = mem[rd_ptr[$clog2(DEPTH)-1:0]];

  // Removed registered output block to eliminate 1-cycle latency
  /*
  logic [DATA_WIDTH-1:0] o_data_reg;
  assign o_data = o_data_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      o_data_reg <= {DATA_WIDTH{1'b0}};
    end else begin
      o_data_reg <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
    end
  end
  */

  // Write logic
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      wr_ptr <= {($clog2(DEPTH)+1){1'b0}};
    end
    else if (wren && !full) begin
      mem[wr_ptr[$clog2(DEPTH)-1:0]] <= i_data;
      wr_ptr <= wr_ptr + 1'b1;
    end
  end

  // Read logic
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      rd_ptr <= {($clog2(DEPTH)+1){1'b0}};
    end
    else if (rden && !empty) begin
      rd_ptr <= rd_ptr + 1'b1;
    end
  end

endmodule
