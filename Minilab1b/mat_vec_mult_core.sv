// Matrix-Vector Multiplication Core Module
// Performs 8x8 matrix multiplied by 8x1 vector computation
// Uses 8 MAC units with propagating B/En signals
// Assumes FIFOs are pre-filled with matrix data

module mat_vec_mult_core #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 8,
    parameter NUM_MACS = 8
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,                    // Start computation
    input  logic [DATA_WIDTH-1:0] b_in,    // B vector input (one element at a time)
    output logic [DATA_WIDTH*3-1:0] result [0:NUM_MACS-1], // C outputs
    output logic done,                     // Computation complete
    output logic ready_for_b,              // Ready to accept next B input

    // FIFO Interface
    output logic [NUM_MACS-1:0] fifo_rden,
    input  logic [DATA_WIDTH-1:0] fifo_data [0:NUM_MACS-1],
    input  logic [NUM_MACS-1:0] fifo_empty
);

    // State machine states
    typedef enum logic [1:0] {
        IDLE,
        WAIT_CYCLE,
        COMPUTE,
        DONE_STATE
    } state_t;

    state_t state, next_state;

    // MAC signals
    logic [NUM_MACS-1:0] mac_en;
    logic mac_clr;

    // En and B propagation through MAC array
    logic en_chain [0:NUM_MACS];  // en_chain[0] is input, en_chain[1..8] propagate through MACs
    logic [DATA_WIDTH-1:0] b_chain [0:NUM_MACS];  // b_chain[0] is input, propagates through MACs

    // Compute control
    logic [4:0] compute_counter;  // Count MAC operations (needs to count up to NUM_MACS*2)

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
                    next_state = WAIT_CYCLE;
                end
            end

            WAIT_CYCLE: begin
                // One cycle to ensure FIFOs are ready
                next_state = COMPUTE;
            end

            COMPUTE: begin
                if (compute_counter >= (NUM_MACS * 3)) begin
                    // Need enough cycles for last MAC to finish pipeline
                    // MAC 7 starts at ~Cycle 9, inputs end ~Cycle 17, +3 pipeline = Cycle 20
                    next_state = DONE_STATE;
                end
            end

            DONE_STATE: begin
                next_state = IDLE;
            end
        endcase
    end

    // Compute counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            compute_counter <= 5'b0;
        end else if (state == IDLE || state == WAIT_CYCLE) begin
            compute_counter <= 5'b0;
        end else if (state == COMPUTE) begin
            compute_counter <= compute_counter + 1'b1;
        end
    end

    // MAC enable and clear control
    always_comb begin
        mac_clr = (state == IDLE);
    end

    // Ready to accept B input during compute phase (15 cycles for propagation)
    // Need to feed B for NUM_MACS + (NUM_MACS-1) cycles to ensure all MACs get all values
    assign ready_for_b = (state == COMPUTE) && (compute_counter < (NUM_MACS + NUM_MACS - 1));

    // En and B propagation registers for entire chain (including input)
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (int i = 0; i <= NUM_MACS; i++) begin
                en_chain[i] <= 1'b0;
                b_chain[i] <= 8'b0;
            end
        end else begin
            // Set the input to the chain
            // Delay en_chain[0] by one cycle to allow first B value to load properly
            // Extended ready_for_b (15 cycles) ensures B values propagate through entire chain
            en_chain[0] <= (state == COMPUTE) && (compute_counter > 0) && (compute_counter <= NUM_MACS);
            b_chain[0] <= b_in;

            // Propagate En and B through the MAC array
            for (int i = 1; i <= NUM_MACS; i++) begin
                en_chain[i] <= en_chain[i-1];
                b_chain[i] <= b_chain[i-1];
            end
        end
    end

    // FIFO read control - read when MAC is enabled
    // Note: MAC registers the En signal internally (stage 1).
    // To feed the MAC correctly, we should align FIFO read with that registered En.
    // However, since we made FIFO combinational, we need data AVAILABLE at the cycle En arrives at MAC input.
    // This logic needs to match the MAC's internal expectation.
    // If MAC is:
    //   Cycle 0: Inputs En, A, B arrive
    //   Cycle 1: Registered internally (En_reg, Ain_reg, Bin_reg)
    // Then we must provide A at Cycle 0 alongside En.
    
    // BUT, the issue might be that we were reading pop-ed data.
    // If FIFO is combinational (showing mem[ptr]), then rden advances the pointer for *next* cycle.
    // So if we assert rden[i] when En arrives, we consume the CURRENT value (good) but prepare NEXT value.
    
    // Let's stick to the simplest interpretation of the systolic array diagram:
    // Each MAC[i] receives En[i]. It needs A[i] (from FIFO) at that exact moment.
    // So fifo_rden[i] should indeed be En[i].
    
    // WAIT, if MAC registers inputs, it consumes them on the clock edge.
    // If FIFO output is combinational, data is valid immediately.
    // Asserting rden captures the current valid data into MAC logic effectively?
    // Actually, fifo_rden updates the read pointer. The data for *current* cycle is at current ptr.
    // So rden should be asserted to move to *next* data for *next* cycle.
    
    // FIFO read control
    always_comb begin
        for (int i = 0; i < NUM_MACS; i++) begin
            fifo_rden[i] = en_chain[i] && !fifo_empty[i];
        end
    end

    // Debug print
    always @(posedge clk) begin
        if (state == COMPUTE) begin
             $display("[CORE DEBUG] T=%0t cnt=%0d En0=%b A0=0x%h B0=0x%h Rden0=%b Empty0=%b", 
                      $time, compute_counter, en_chain[0], fifo_data[0], b_chain[0], fifo_rden[0], fifo_empty[0]);
        end
    end

    // Done signal
    assign done = (state == DONE_STATE);

    // Instantiate MACs
    genvar i;
    generate
        for (i = 0; i < NUM_MACS; i++) begin : mac_gen
            MAC #(
                .DATA_WIDTH(DATA_WIDTH)
            ) mac_inst (
                .clk(clk),
                .rst_n(rst_n),
                .En(en_chain[i]),
                .Clr(mac_clr),
                .Ain(fifo_data[i]),
                .Bin(b_chain[i]),  // Each MAC gets B from propagation chain
                .Cout(result[i])
            );
        end
    endgenerate

endmodule
