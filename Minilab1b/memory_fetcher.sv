// Memory Fetcher Module
// Implements Avalon MM Master interface to fetch matrix rows from memory
// and write them to FIFOs for the matrix-vector multiplier

module memory_fetcher #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 8,
    parameter NUM_ROWS = 8
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,                    // Start fetching data
    output logic fetch_done,               // All FIFOs filled

    // Avalon MM Master Interface
    output logic [31:0] mem_address,
    output logic mem_read,
    input  logic [63:0] mem_readdata,
    input  logic mem_readdatavalid,
    input  logic mem_waitrequest,

    // FIFO Interface
    output logic [NUM_ROWS-1:0] fifo_wren,
    output logic [DATA_WIDTH-1:0] fifo_data [0:NUM_ROWS-1],
    input  logic [NUM_ROWS-1:0] fifo_full
);

    // State machine states
    typedef enum logic [1:0] {
        IDLE,
        FETCH_ROWS,
        DONE_STATE
    } state_t;

    state_t state, next_state;

    // Control signals
    logic [2:0] current_fifo;     // Which FIFO we're currently filling (0-7)
    logic [2:0] byte_counter;     // Which byte within the row (0-7)
    logic writing_to_fifo;        // Flag indicating we're writing data to FIFO
    logic all_fifos_full;
    logic [63:0] row_data;        // Stored row data from memory

    // Check if all FIFOs are full
    assign all_fifos_full = &fifo_full;

    // State machine - sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // State machine - combinational logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    next_state = FETCH_ROWS;
                end
            end

            FETCH_ROWS: begin
                if (all_fifos_full) begin
                    next_state = DONE_STATE;
                end
            end

            DONE_STATE: begin
                next_state = IDLE;
            end
        endcase
    end

    // Row/byte counter control
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            current_fifo <= 3'b0;
            byte_counter <= 3'b0;
            writing_to_fifo <= 1'b0;
        end
        else if (state == IDLE) begin
            current_fifo <= 3'b0;
            byte_counter <= 3'b0;
            writing_to_fifo <= 1'b0;
        end
        else if (state == FETCH_ROWS) begin
            if (mem_readdatavalid) begin
                writing_to_fifo <= 1'b1;
                byte_counter <= 3'b0;
            end
            else if (writing_to_fifo) begin
                if (byte_counter < NUM_ROWS - 1) begin
                    byte_counter <= byte_counter + 1'b1;
                end
                else begin
                    byte_counter <= 3'b0;
                    writing_to_fifo <= 1'b0;
                    if (current_fifo < NUM_ROWS - 1) begin
                        current_fifo <= current_fifo + 1'b1;
                    end
                end
            end
        end
    end

    // Memory read control (Avalon MM Master)
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            mem_read <= 1'b0;
            mem_address <= 32'b0;
        end else begin
            case (state)
                IDLE: begin
                    mem_read <= 1'b0;
                    mem_address <= 32'b0;
                end

                FETCH_ROWS: begin
                    // Issue read when: not all FIFOs full, not currently writing,
                    // memory not waiting, haven't fetched all rows yet, and not receiving data
                    if (!all_fifos_full && !writing_to_fifo && !mem_waitrequest && (current_fifo < NUM_ROWS) && !mem_readdatavalid) begin
                        mem_read <= 1'b1;
                        mem_address <= {29'b0, current_fifo};  // Address is row index
                    end else begin
                        mem_read <= 1'b0;
                    end
                end

                default: begin
                    mem_read <= 1'b0;
                end
            endcase
        end
    end

    // Store the read data
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            row_data <= 64'b0;
        end else if (mem_readdatavalid) begin
            row_data <= mem_readdata;
        end
    end

    // FIFO write control - write one byte at a time to current FIFO
    always_comb begin
        for (int i = 0; i < NUM_ROWS; i++) begin
            fifo_wren[i] = (i == current_fifo) && writing_to_fifo && !fifo_full[i];
            // Extract appropriate byte from the stored row data
            // Fix: MIF data 0102...08 typically loads such that 01 is MSB (bits 63:56)
            // Previous code read bits [7:0] first, which was 08.
            // We need to read top byte first if byte_counter=0 is semantically the "first" element.
            fifo_data[i] = row_data[(7 - byte_counter)*8 +: 8];
        end
    end

    // Fetch done signal
    assign fetch_done = (state == DONE_STATE);

endmodule
