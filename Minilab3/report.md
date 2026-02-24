## Introduction

This lab implements a **Special Purpose Asynchronous Receiver/Transmitter (SPART)** and an accompanying hardware **driver** (mock processor) on the DE1-SoC FPGA board. The system allows a host PC running a serial terminal (PuTTY) to send characters to the FPGA over a UART serial link, which the driver then echoes back to the terminal. The design demonstrates programmable baud-rate serial communication and serves as a reusable I/O module for the final project processor.

## SPART Functional Description

The SPART is a synchronous, full-duplex UART peripheral. It interfaces with a processor (or driver) over an 8-bit parallel bus and communicates externally with a serial terminal over standard RS-232 signaling via two unidirectional pins: **TxD** (transmit) and **RxD** (receive).

## Block Descriptions

### Divisor Buffer

The **Divisor Buffer** is a 16-bit register that holds the programmable baud rate divisor. It is written by the processor in two 8-bit writes to IOADDR `10` (low byte) and `11` (high byte). On reset it initializes to **325**, corresponding to 9600 baud at a 50 MHz clock with 16× oversampling.

The divisor formula is:
divisor = round( f_clk / (16 × baud_rate) ) - 1

### Baud Rate Generator (BRG)

The **BRG** is a 16-bit down-counter. It counts from the divisor value down to zero, then reloads. When the counter reaches zero it asserts `baud_en` for exactly one clock cycle. This produces a strobe at 16× the target baud rate, used as the timing reference for both the transmitter and receiver. Using an enable signal (rather than a separate clock) avoids multiple clock domains.

### Transmitter

The **Transmitter** is a double-buffered state machine with states `TX_IDLE`, `TX_START`, `TX_DATA`, and `TX_STOP`.

- The processor writes a byte to the **Transmit Buffer** (`tx_buf`). `TBR` immediately goes low to signal the buffer is occupied.
- When `TX_IDLE`, the shift register is loaded from `tx_buf`, freeing the buffer (`TBR` → high) so the processor can queue the next byte during transmission.
- The state machine drives `TxD`: start bit (0), 8 data bits LSB-first, stop bit (1), each lasting exactly 16 `baud_en` pulses.

### Receiver

The **Receiver** is a state machine with states `RX_IDLE`, `RX_START`, `RX_DATA`, and `RX_STOP`.

- In `RX_IDLE` it detects the falling edge of `RxD` (start bit) through a two-stage synchronizer to resolve metastability.
- In `RX_START` it waits 8 `baud_en` pulses to center on the start bit, then verifies the line is still low (false-start rejection).
- In `RX_DATA` it samples each data bit at its center (every 16 `baud_en` pulses), shifting bits into `rx_shift` MSB-first so the assembled byte is in correct order after 8 shifts.
- In `RX_STOP` it waits out the stop-bit period, latches `rx_shift` into `rx_buf`, and asserts `RDA`.
- `RDA` is cleared when the processor reads IOADDR `00`.

### Bus Interface

The **Bus Interface** connects the SPART to the bidirectional `DATABUS`. It contains a 3-state driver and a multiplexer:

- When `IOCS=1` and `IOR/W=1` (read), `DATABUS` is driven by the mux output:
  - IOADDR `00` → `rx_buf` (received byte)
  - IOADDR `01` → `{6'b0, TBR, RDA}` (status register)
- When `IOCS=0` or `IOR/W=0`, `DATABUS` is released to high-impedance (`8'hzz`) so the processor can drive it for writes.

## Driver Block Description

The **driver** module acts as the mock processor. It controls the SPART's parallel bus and implements a two-phase operation:

Immediately after reset, the driver runs two write cycles to program SPART's Divisor Buffer with the value selected by `br_cfg[1:0]` (connected to slide switches SW[9:8] on the DE1-SoC):

After initialization the driver enters an infinite echo loop:

```
IDLE     → polls RDA; transitions to READ when RDA=1
READ     → reads received byte from SPART RX buffer (IOADDR=00, IOR/W=1)
WAIT_TBR → polls TBR; transitions to WRITE when TBR=1
WRITE    → writes received byte back to SPART TX buffer (IOADDR=00, IOR/W=0)
→ back to IDLE
```

Every character received from the serial terminal is echoed straight back, producing the loopback behavior visible in PuTTY.


## Simulation Testbench (`spart_tb.v`)


- **SPART0** (testbench side) emulates the dumb terminal / printf. The testbench drives its parallel bus directly to send and receive characters.
- **SPART1 + Driver** (DUT side) is the exact same RTL used for hardware. SPART1 receives characters from SPART0 over the serial link; the driver echoes them back via SPART1's transmitter.
- The testbench polls `tbr0`/`rda0` (mimicking the bus protocol) with a timeout counter to prevent infinite hangs.

### Tests

| Test | Description |
|------|-------------|
| 1 | Driver resets to `INIT_LOW` |
| 2 | Driver transitions to `INIT_HIGH` after 1 clock |
| 3 | Driver transitions to `IDLE` after 2 clocks |
| 4 | `SPART1.divisor_buf` = 80 for 38400 baud |
| 5 | `SPART0.divisor_buf` programmed to 80 |
| 6 | Echo `'A'` at 38400 baud |
| 7 | Echo `'Z'` at 38400 baud |
| 8 | Echo `"HELLO"` (5 chars) at 38400 baud |
| 9 | Status register: TBR=1, RDA=0 after idle |
| 10 | Divisor = 325 after reset with `br_cfg=01` (9600 baud) |
| 11 | Echo `'S'` at 9600 baud |
| 12 | Divisor = 162 after reset with `br_cfg=10` (19200 baud) |
| 13 | Echo `'!'` at 19200 baud |
| 14 | Divisor = 650 after reset with `br_cfg=00` (4800 baud) |
| 15 | Echo `'X'` at 4800 baud |


### Hardware Test on DE1-SoC

The bitstream was programmed onto the DE1-SoC board. A USB-to-Serial adapter was wired to GPIO[3] (TxD) and GPIO[5] (RxD). PuTTY was opened on the host PC connected to the adapter's COM port.

**Basic echo test at 9600 baud (SW[9:8] = 01):**

SW[8] was set high (SW[9:8] = `01`), KEY[0] was pressed and released to reset, and PuTTY was configured to 9600 baud, 8N1. The following characters were typed and echoed correctly:

```
Hello!
```

Each keystroke appeared on screen immediately as the driver echoed it back through the SPART.

**Baud rate switching test:**

The baud rate was switched to 38400 (SW[9:8] = `11`), KEY[0] was pressed to reset, and PuTTY was reconnected at 38400 baud. The echo behavior was identical, confirming the divisor was correctly reprogrammed by the driver. The HEX display changed to show `38400` to confirm the new rate.


## Problems Encountered and Solutions

### Double-Buffered Transmitter TBR Timing

**Problem:** It was initially unclear when `TBR` (Transmit Buffer Ready) should be asserted. A naive implementation that tied `TBR` to the transmitter's idle state would force the processor to wait for the entire previous byte to finish shifting before writing the next one, halving throughput.

**Solution:** The transmitter is double-buffered: `tx_buf` is separate from the active shift register `tx_shift`. `TBR` is asserted as soon as the transmitter moves the byte from `tx_buf` into `tx_shift` (at the transition to `TX_START`), allowing the processor to immediately queue the next byte while the current one is still being transmitted. This is implemented as `assign tbr = ~tx_buf_valid`.

### Testbench NBA Race Condition (Tests 2, 3, 4)

**Problem:** Tests 2, 3, and 4 initially failed with:
```
Test  2 FAIL: Expected INIT_HIGH (1), got state=0
Test  3 FAIL: Expected IDLE (2), got state=1
Test  4 FAIL: Expected SPART1.divisor_buf=80, got 336
```

The root cause was a Verilog simulation scheduling issue. The driver uses nonblocking assignments (`state <= INIT_HIGH`). When the testbench's `initial` block wakes up at a `@(posedge clk)` event, it is in the **active region** of that posedge — the same region where nonblocking assignments are *scheduled* but not yet committed. The NBA (nonblocking assignment) update region runs after the active region. So reading `DUT.state` immediately after `@(posedge clk)` returns the **pre-posedge value**, not the newly assigned one.

For Test 4, `SPART1.divisor_buf` returned 336 (`0x0150`) instead of 80 (`0x0050`) because only the low byte (`0x50`) had settled from posedge 1's NBA; the high byte still held `0x01` from the reset value of 325 (`0x0145`), giving `0x0150 = 336`.

**Solution:** Added a `#1` delay (1 ns) after each `@(posedge clk)` where the settled state must be read. This advances simulation past the NBA region, ensuring all nonblocking assignments from that posedge have committed before sampling:

```verilog
@(posedge clk); #1;   // wait past the NBA region
if (DUT.state === 3'd1) ...
```


