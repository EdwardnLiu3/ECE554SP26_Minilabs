## Implementation Overview

A real-time Sobel edge detection pipeline was implemented on the DE1-SoC (Cyclone V 5CSEMA5F31C6) with a D5M camera. The pipeline replaces the stock RAW2RGB module, converting 1280x960 raw Bayer pixels into 640x480 12-bit grayscale edge-detected output displayed via VGA through SDRAM frame buffering. The design uses a fully pipelined architecture clocked on D5M_PIXLCLK (25 MHz) with active-low asynchronous reset.

## Modules (written/modified by us)


| # | Module | Description |
|---|--------|-------------|
| 1 | `bayer_row_buffer.v` | RAM circular buffer (1280 deep) providing current-row and previous-row taps. |
| 2 | `bayer_to_grayscale.v` | Averages 2x2 Bayer blocks (R+G+G+B)/4, downsampling to 640x480. 4-clock pipeline. |
| 3 | `grayscale_row_buffer.v` | Two chained RAM buffers (640 deep) providing 3 simultaneous row taps for the 3x3 window. |
| 4 | `sobel_conv_3x3.v` | Applies Sobel X and Sobel Y 3x3 kernels using column delay registers. 2-clock pipeline. |
| 5 | `sobel_abs_value.v` | Mode-selectable gradient: \|Gx\|+\|Gy\|, \|Gx\| only, or \|Gy\| only. Scales by /4 with saturation and noise threshold. 1-clock pipeline. |
| 6 | `image_processing_pipeline.v` | Top-level wrapper connecting all submodules, includes horizontal [1,2,1]/4 Gaussian smoothing stage. |
| 7 | `DE1_SoC_CAMERA.v` | modified to call image_processing_pipeline module |

Other files were either generated or copied

## FPGA Resource Utilization

Row buffers infer as M10K block RAM. No DSP blocks are used. Sobel multiply-by-2 is implemented as addition (x + x).

## Filter Mode Selection (SW[2:1])

The pipeline supports three display modes controlled by board switches SW[2:1], allowing real-time switching between edge filter directions:

| SW[2:1] | Mode | Description |
|---------|------|-------------|

| 01 | Vertical edges only | Shows \|Gx\| — detects vertical edges using the Sobel X kernel |
| 10 | Horizontal edges only | Shows \|Gy\| — detects horizontal edges using the Sobel Y kernel |

SW[2:1] is wired to the `iMode` input of `sobel_abs_value`, which selects the gradient component via a combinational case statement.

## Testbench

The testbench (`image_processing_pipeline_tb.v`) contains 10 tests: reset state verification, internal signal checks, uniform input (no false edges), vertical and horizontal edge detection, edge magnitude validation, reset clearing, and whitebox tests forcing Sobel outputs to verify absolute value computation and saturation clamping. All 10 tests pass.

## Problems and Solutions

**Problem 1:** Pipeline alignment mismatch in `bayer_to_grayscale`. User-added `gray_val_d1`/`d2` registers created 2 extra clocks of data latency, but coordinate delays were only 2 stages. **Fix:** extended coordinate pipeline to 4 stages (`x_d4`, `y_d4`, `dval_d4`).

**Problem 2:** Off-by-one error in `grayscale_row_buffer`. Chaining two separate `bayer_row_buffer` instances caused the second buffer to read stale data due to cross-module nonblocking assignment ordering. **Fix:** consolidated into a single always block with two internal RAM arrays.

**Problem 3:** Faint edges on VGA display. Division by 8 was too aggressive for typical camera scenes. **Fix:** changed to division by 4 with saturation clamping.

**Problem 4:** Excessive sensor noise in edge output. The Sobel operator amplifies high-frequency noise. **Fix:** added a horizontal [1,2,1]/4 Gaussian smoothing stage before edge detection and a noise threshold of 60 in `sobel_abs_value`.
