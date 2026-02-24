///////////////////////////////////////////////////////////////////////////////
// Module: driver
// Description: Hardware testbench / mock processor for the SPART.
//
// Operation:
//   1. After reset is released, writes a baud-rate divisor selected by
//      br_cfg into the SPART's 16-bit Divisor Buffer (two 8-bit writes).
//   2. Runs an infinite echo loop:
//        - Polls RDA; when high, reads the received character from the SPART.
//        - Polls TBR; when high, writes the character back to the SPART
//          transmit buffer (echoes it to the terminal).
//
// Baud rates and divisors (50 MHz clock, 16x oversampling):
//   divisor = round(50_000_000 / (16 * baud_rate) - 1)
//   br_cfg=00 -> 4800  baud, divisor = 650  (0x028A)
//   br_cfg=01 -> 9600  baud, divisor = 325  (0x0145)
//   br_cfg=10 -> 19200 baud, divisor = 162  (0x00A2)
//   br_cfg=11 -> 38400 baud, divisor =  80  (0x0050)
//
// Bus protocol (synchronous, single-cycle):
//   Write: assert iocs=1, iorw=0, ioaddr, databus for one CLK period;
//          SPART captures on the following posedge.
//   Read:  assert iocs=1, iorw=1, ioaddr for one CLK period;
//          SPART drives databus combinationally; driver samples on posedge.
///////////////////////////////////////////////////////////////////////////////
module driver(
    input        clk,
    input        rst,
    input  [1:0] br_cfg,
    output       iocs,
    output       iorw,
    input        rda,
    input        tbr,
    output [1:0] ioaddr,
    inout  [7:0] databus
);

    // -------------------------------------------------------------------------
    // Baud-rate divisor lookup (50 MHz clock, 16x oversampling)
    // -------------------------------------------------------------------------
    localparam [15:0] DIV_4800  = 16'd650;
    localparam [15:0] DIV_9600  = 16'd325;
    localparam [15:0] DIV_19200 = 16'd162;
    localparam [15:0] DIV_38400 = 16'd80;

    // -------------------------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------------------------
    localparam [2:0] INIT_LOW  = 3'd0;  // Write divisor[7:0]  to IOADDR=10
    localparam [2:0] INIT_HIGH = 3'd1;  // Write divisor[15:8] to IOADDR=11
    localparam [2:0] IDLE      = 3'd2;  // Poll RDA
    localparam [2:0] READ      = 3'd3;  // Read receive buffer (IOADDR=00, iorw=1)
    localparam [2:0] WAIT_TBR  = 3'd4;  // Poll TBR
    localparam [2:0] WRITE     = 3'd5;  // Write tx buffer    (IOADDR=00, iorw=0)

    reg [2:0] state;
    reg [7:0] rx_data;  // Holds the received byte between READ and WRITE states

    // -------------------------------------------------------------------------
    // Divisor selection (combinational; br_cfg is stable before reset release)
    // -------------------------------------------------------------------------
    reg [15:0] divisor;
    always @(*) begin
        case (br_cfg)
            2'b00: divisor = DIV_4800;
            2'b01: divisor = DIV_9600;
            2'b10: divisor = DIV_19200;
            2'b11: divisor = DIV_38400;
        endcase
    end

    // -------------------------------------------------------------------------
    // FSM state register
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= INIT_LOW;
            rx_data <= 8'h00;
        end else begin
            case (state)
                // Write low byte of divisor; advance immediately (1-cycle write)
                INIT_LOW:  state <= INIT_HIGH;

                // Write high byte of divisor; then begin echo loop
                INIT_HIGH: state <= IDLE;

                // Wait until SPART signals a received character
                IDLE:      if (rda) state <= READ;

                // Assert read for one cycle; capture databus on this posedge
                READ: begin
                    rx_data <= databus;   // latch character from SPART's rx_buf
                    state   <= WAIT_TBR;
                end

                // Wait until SPART transmit buffer is free
                WAIT_TBR:  if (tbr) state <= WRITE;

                // Assert write for one cycle; SPART latches tx_buf on next posedge
                WRITE:     state <= IDLE;

                default:   state <= INIT_LOW;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Output logic (fully combinational)
    //
    // IOCS is asserted during all four bus-active states.
    // IORW is 1 (read) only during READ; 0 (write) everywhere else.
    // IOADDR selects the Divisor Buffer bytes during INIT, Rx/Tx buffer otherwise.
    // DATABUS is driven only during write states; tri-stated otherwise so the
    // SPART can drive it during READ.
    // -------------------------------------------------------------------------
    assign iocs = (state == INIT_LOW)  || (state == INIT_HIGH) ||
                  (state == READ)      || (state == WRITE);

    assign iorw = (state == READ);  // 1 = read from SPART; 0 = write to SPART

    assign ioaddr = (state == INIT_LOW)  ? 2'b10 :   // DB(Low)
                    (state == INIT_HIGH) ? 2'b11 :   // DB(High)
                    2'b00;                            // Rx / Tx buffer

    // Data to place on DATABUS during write operations
    reg [7:0] db_drive;
    always @(*) begin
        case (state)
            INIT_LOW:  db_drive = divisor[7:0];   // low byte of divisor
            INIT_HIGH: db_drive = divisor[15:8];  // high byte of divisor
            WRITE:     db_drive = rx_data;         // echo received character
            default:   db_drive = 8'h00;
        endcase
    end

    // Drive DATABUS only during write operations; release (hi-Z) during reads
    assign databus = (iocs && !iorw) ? db_drive : 8'hzz;

endmodule
