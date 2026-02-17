## Implementation Overview

A real-time Sobel edge detection pipeline was implemented on the DE1-SoC (Cyclone V 5CSEMA5F31C6) with a D5M camera. The pipeline replaces the stock RAW2RGB module, converting 1280x960 raw Bayer pixels into 640x480 12-bit grayscale edge-detected output displayed via VGA through SDRAM frame buffering. The design uses a fully pipelined architecture clocked on D5M_PIXLCLK (25 MHz) with active-low asynchronous reset.

## Modules (written/modified by us)

| # | Module | Description |
|---|--------|-------------|
| 1 | `bayer_row_buffer.v` | RAM circular buffer (1280 deep) providing current-row and previous-row taps. |
| 2 | `bayer_to_grayscale.v` | Averages 2x2 Bayer blocks (R+G+G+B)/4, downsampling to 640x480. 4-clock pipeline. |
| 3 | `grayscale_row_buffer.v` | Two chained RAM buffers (640 deep) providing 3 simultaneous row taps for the 3x3 window. |
| 4 | `sobel_conv_3x3.v` | Applies Sobel X and Sobel Y 3x3 kernels using column delay registers. 2-clock pipeline. |
| 5 | `sobel_abs_value.v` | Computes \|Gx\|+\|Gy\|/2 with saturation clamping to 12-bit. 1-clock pipeline. |
| 6 | `image_processing_pipeline.v` | The top-level wrapper connects the above five submodules in series |
| 7 | `DE1_SoC_CAMERA.v` | modified to call image_processing_pipeline module |

Other files were either generated or copied

## FPGA Resource Utilization

Row buffers infer as M10K block RAM. No DSP blocks are used. Sobel multiply-by-2 is implemented as addition (x + x).

## Testbench

The testbench (`image_processing_pipeline_tb.v`) contains 10 tests: reset state verification, internal signal checks, uniform input (no false edges), vertical and horizontal edge detection, edge magnitude validation, reset clearing, and whitebox tests forcing Sobel outputs to verify absolute value computation and saturation clamping. All 10 tests pass.

## Problems and Solutions

**Problem 1:** Pipeline alignment mismatch in `bayer_to_grayscale`. User-added `gray_val_d1`/`d2` registers created 2 extra clocks of data latency, but coordinate delays were only 2 stages. **Fix:** extended coordinate pipeline to 4 stages (`x_d4`, `y_d4`, `dval_d4`).

**Problem 2:** Off-by-one error in `grayscale_row_buffer`. Chaining two separate `bayer_row_buffer` instances caused the second buffer to read stale data due to cross-module nonblocking assignment ordering. **Fix:** consolidated into a single always block with two internal RAM arrays.

**Problem 3:** Faint edges on VGA display. Division by 8 was too aggressive for typical camera scenes. **Fix:** changed to division by 2 with saturation clamping, providing 4x brighter edges.
