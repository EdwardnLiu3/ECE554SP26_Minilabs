///////////////////////////////////////////////////////////////////////////////
// Module: spart
// Description: Special Purpose Asynchronous Receiver/Transmitter
//
// Subsystems:
//   - Divisor Buffer    : Programmable 16-bit baud divisor (written by processor)
//   - Baud Rate Generator: Down-counter producing baud_en at 16x baud rate
//   - Transmitter       : Start/Data/Stop FSM; double-buffered (tx_buf + shift reg)
//   - Receiver          : Start-detect, 8x oversample centering, 16x per-bit sampling
//   - Bus Interface     : 3-state DATABUS driver; mux between Rx Buffer and Status Reg
//
// Address Map (IOADDR):
//   00 : Transmit Buffer (IOR/W=0 write) / Receive Buffer (IOR/W=1 read)
//   01 : Status Register (IOR/W=1 read)  [1]=TBR  [0]=RDA
//   10 : DB(Low)  - low byte of baud divisor (write only)
//   11 : DB(High) - high byte of baud divisor (write only)
//
// Default divisor on reset: 325 (50 MHz clock, 9600 baud, 16x oversampling)
//   divisor = round(50_000_000 / (16 * 9600) - 1) = round(324.52) = 325
//   Actual baud = 50_000_000 / (16 * 326) = 9585.9 bps  (0.15% error)
///////////////////////////////////////////////////////////////////////////////
module spart(
    input        clk,
    input        rst,
    input        iocs,
    input        iorw,
    output       rda,
    output       tbr,
    input  [1:0] ioaddr,
    inout  [7:0] databus,
    output       txd,
    input        rxd
);

    // Default divisor: 50 MHz / (16 * 9600) - 1 = 324.52 -> 325
    localparam [15:0] DEFAULT_DIVISOR = 16'd325;

    ///////////////////////////////////////////////////////////////////////////
    // Divisor Buffer
    // Written by processor via IOADDR 10 (low byte) and 11 (high byte).
    // Resets to DEFAULT_DIVISOR for 9600 baud at 50 MHz.
    ///////////////////////////////////////////////////////////////////////////
    reg [15:0] divisor_buf;

    always @(posedge clk or posedge rst) begin
        if (rst)
            divisor_buf <= DEFAULT_DIVISOR;
        else if (iocs && !iorw) begin
            case (ioaddr)
                2'b10: divisor_buf[7:0]  <= databus;   // DB(Low)
                2'b11: divisor_buf[15:8] <= databus;   // DB(High)
                default: ;
            endcase
        end
    end

    ///////////////////////////////////////////////////////////////////////////
    // Baud Rate Generator
    // 16-bit down counter.  baud_en pulses once every (divisor+1) CLK cycles,
    // giving a rate of CLK/(divisor+1) = 16 * baud_rate.
    ///////////////////////////////////////////////////////////////////////////
    reg  [15:0] baud_cnt;
    wire        baud_en = (baud_cnt == 16'd0);

    always @(posedge clk or posedge rst) begin
        if (rst)
            baud_cnt <= DEFAULT_DIVISOR;
        else if (baud_en)
            baud_cnt <= divisor_buf;      // reload on zero
        else
            baud_cnt <= baud_cnt - 1'b1;
    end

    ///////////////////////////////////////////////////////////////////////////
    // Transmitter
    //
    // Double-buffered: processor writes to tx_buf; the shift register is
    // loaded from tx_buf when the transmitter becomes idle.  TBR goes high
    // as soon as tx_buf is consumed, allowing the processor to queue the
    // next byte while the current one is still being shifted out.
    //
    // Bit ordering: LSB first (standard UART).
    // Frame format: 1 start bit (0), 8 data bits, 1 stop bit (1).
    // Each bit occupies exactly 16 baud_en pulses.
    ///////////////////////////////////////////////////////////////////////////
    localparam TX_IDLE  = 2'b00;
    localparam TX_START = 2'b01;
    localparam TX_DATA  = 2'b10;
    localparam TX_STOP  = 2'b11;

    reg [1:0] tx_state;
    reg [7:0] tx_buf;        // Transmit buffer (loaded by processor)
    reg       tx_buf_valid;  // 1 = tx_buf contains unshifted data
    reg [7:0] tx_shift;      // Active transmit shift register
    reg [2:0] tx_bit_cnt;    // Current data bit index (0-7)
    reg [3:0] tx_baud_cnt;   // Counts baud_en pulses within each bit period
    reg       txd_reg;

    assign txd = txd_reg;
    assign tbr = ~tx_buf_valid;  // TBR high when buffer is free

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state     <= TX_IDLE;
            tx_buf       <= 8'h00;
            tx_buf_valid <= 1'b0;
            tx_shift     <= 8'h00;
            tx_bit_cnt   <= 3'd0;
            tx_baud_cnt  <= 4'd0;
            txd_reg      <= 1'b1;   // idle line is high
        end else begin
            // Accept new byte from processor (IOADDR=00, write)
            if (iocs && !iorw && (ioaddr == 2'b00)) begin
                tx_buf       <= databus;
                tx_buf_valid <= 1'b1;
            end

            case (tx_state)
                TX_IDLE: begin
                    txd_reg <= 1'b1;
                    if (tx_buf_valid) begin
                        tx_shift     <= tx_buf;   // load shift register
                        tx_buf_valid <= 1'b0;     // free the buffer (TBR -> 1)
                        tx_baud_cnt  <= 4'd0;
                        tx_state     <= TX_START;
                    end
                end

                TX_START: begin
                    txd_reg <= 1'b0;              // drive start bit
                    if (baud_en) begin
                        if (tx_baud_cnt == 4'd15) begin
                            tx_baud_cnt <= 4'd0;
                            tx_bit_cnt  <= 3'd0;
                            tx_state    <= TX_DATA;
                        end else
                            tx_baud_cnt <= tx_baud_cnt + 1'b1;
                    end
                end

                TX_DATA: begin
                    txd_reg <= tx_shift[0];       // LSB first
                    if (baud_en) begin
                        if (tx_baud_cnt == 4'd15) begin
                            tx_baud_cnt <= 4'd0;
                            if (tx_bit_cnt == 3'd7) begin
                                tx_state <= TX_STOP;
                            end else begin
                                tx_bit_cnt <= tx_bit_cnt + 1'b1;
                                tx_shift   <= tx_shift >> 1;  // advance to next bit
                            end
                        end else
                            tx_baud_cnt <= tx_baud_cnt + 1'b1;
                    end
                end

                TX_STOP: begin
                    txd_reg <= 1'b1;              // drive stop bit
                    if (baud_en) begin
                        if (tx_baud_cnt == 4'd15) begin
                            tx_baud_cnt <= 4'd0;
                            tx_state    <= TX_IDLE;
                        end else
                            tx_baud_cnt <= tx_baud_cnt + 1'b1;
                    end
                end
            endcase
        end
    end

    ///////////////////////////////////////////////////////////////////////////
    // RXD 2-stage synchronizer
    // Resolves metastability for the asynchronous RxD input.
    ///////////////////////////////////////////////////////////////////////////
    reg rxd_s1, rxd_s2;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rxd_s1 <= 1'b1;
            rxd_s2 <= 1'b1;
        end else begin
            rxd_s1 <= rxd;
            rxd_s2 <= rxd_s1;
        end
    end

    ///////////////////////////////////////////////////////////////////////////
    // Receiver
    //
    // Start-bit detection: waits for rxd_s2 to go low (idle line is high).
    // Centering: waits 8 baud_en pulses to land at the midpoint of the
    //   start bit, then verifies it is still low (false-start rejection).
    // Sampling: samples once every 16 baud_en pulses (center of each bit).
    // Shift: received LSB first -> shifts in from the MSB side so that after
    //   8 shifts rx_shift = {bit7, bit6, ..., bit0} = correct byte.
    // RDA is set when the stop-bit interval completes; cleared when the
    //   processor reads IOADDR=00.
    ///////////////////////////////////////////////////////////////////////////
    localparam RX_IDLE  = 2'b00;
    localparam RX_START = 2'b01;
    localparam RX_DATA  = 2'b10;
    localparam RX_STOP  = 2'b11;

    reg [1:0] rx_state;
    reg [7:0] rx_shift;      // Receive shift register
    reg [7:0] rx_buf;        // Receive buffer (read by processor)
    reg [2:0] rx_bit_cnt;    // Current data bit index (0-7)
    reg [3:0] rx_baud_cnt;   // Counts baud_en pulses within each bit period
    reg       rda_reg;       // Receive Data Available flag

    assign rda = rda_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state    <= RX_IDLE;
            rx_shift    <= 8'h00;
            rx_buf      <= 8'h00;
            rx_bit_cnt  <= 3'd0;
            rx_baud_cnt <= 4'd0;
            rda_reg     <= 1'b0;
        end else begin
            // Clear RDA when processor reads the receive buffer (IOADDR=00, read)
            if (iocs && iorw && (ioaddr == 2'b00))
                rda_reg <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    // Detect falling edge (start of start bit)
                    if (!rxd_s2) begin
                        rx_state    <= RX_START;
                        rx_baud_cnt <= 4'd0;
                    end
                end

                RX_START: begin
                    // Count 8 baud_en pulses to center within the start bit
                    if (baud_en) begin
                        if (rx_baud_cnt == 4'd7) begin
                            if (!rxd_s2) begin
                                // Start bit confirmed; move to data sampling
                                rx_state    <= RX_DATA;
                                rx_bit_cnt  <= 3'd0;
                                rx_baud_cnt <= 4'd0;
                            end else begin
                                // False start bit; return to idle
                                rx_state <= RX_IDLE;
                            end
                        end else
                            rx_baud_cnt <= rx_baud_cnt + 1'b1;
                    end
                end

                RX_DATA: begin
                    // Sample each bit at its center (16 baud_en pulses apart)
                    if (baud_en) begin
                        if (rx_baud_cnt == 4'd15) begin
                            // Shift in from MSB side: after 8 shifts,
                            // rx_shift = {bit7,...,bit0}
                            rx_shift    <= {rxd_s2, rx_shift[7:1]};
                            rx_baud_cnt <= 4'd0;
                            if (rx_bit_cnt == 3'd7)
                                rx_state <= RX_STOP;
                            else
                                rx_bit_cnt <= rx_bit_cnt + 1'b1;
                        end else
                            rx_baud_cnt <= rx_baud_cnt + 1'b1;
                    end
                end

                RX_STOP: begin
                    // Wait out the stop-bit period then latch received byte
                    if (baud_en) begin
                        if (rx_baud_cnt == 4'd15) begin
                            rx_buf      <= rx_shift;
                            rda_reg     <= 1'b1;   // signal data available
                            rx_state    <= RX_IDLE;
                            rx_baud_cnt <= 4'd0;
                        end else
                            rx_baud_cnt <= rx_baud_cnt + 1'b1;
                    end
                end
            endcase
        end
    end

    ///////////////////////////////////////////////////////////////////////////
    // Bus Interface - 3-state DATABUS driver
    //
    // Drive DATABUS only when IOCS=1 and IOR/W=1 (processor read).
    // Mux selects:
    //   IOADDR=00 -> Receive Buffer
    //   IOADDR=01 -> Status Register {6'b0, TBR, RDA}
    //   other     -> 0x00 (write-only registers; should not be read)
    ///////////////////////////////////////////////////////////////////////////
    reg [7:0] db_out;
    always @(*) begin
        case (ioaddr)
            2'b00:   db_out = rx_buf;            // Receive Buffer
            2'b01:   db_out = {6'b0, tbr, rda};  // Status: [1]=TBR, [0]=RDA
            default: db_out = 8'h00;
        endcase
    end

    assign databus = (iocs && iorw) ? db_out : 8'hzz;

endmodule
