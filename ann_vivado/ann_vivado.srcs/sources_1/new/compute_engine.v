// =============================================================================
// ann_compute_engine.v
// Streaming 2D Sobel edge-detection engine, 2 output channels (Gx, Gy),
// 3x3 convolution -> bias(=0) + ReLU -> 2x2 max pooling.
// Data format: 16-bit signed Q8.8 fixed point throughout.
// No frame buffer / external RAM: only 2 input-row line buffers and
// 2 small pooling row buffers (15 entries each) are used.
//
// Frame geometry (fixed, matches 32x32 input):
//   Input          : 32 x 32
//   Conv output    : 30 x 30  (valid convolution, no zero-padding)
//   Pooled output  : 15 x 15  (2x2 max pool, stride 2)
//
// Assumes pixel_in arrives one pixel per cycle, in raster order,
// continuously for a full 32x32 frame once frame_start is pulsed.
// =============================================================================

module compute_engine #(
    parameter integer IMG_W = 32,
    parameter integer IMG_H = 32
)(
    input  wire                    clk,
    input  wire                    rst,          // synchronous, active high
    input  wire                    frame_start,  // pulse 1 cycle before first pixel of a new frame
    input  wire signed [15:0]      pixel_in,     // Q8.8, 1 pixel/cycle

    output reg  signed [15:0]      pool_out_ch1, // Q8.8, Gx channel, valid when pool_valid=1
    output reg  signed [15:0]      pool_out_ch2, // Q8.8, Gy channel, valid when pool_valid=1
    output reg                     pool_valid
);

    // -------------------------------------------------------------------
    // Sobel weights in Q8.8 (integer magnitudes 1 and 2 -> exact, no
    // quantization error vs. floating point Sobel)
    // -------------------------------------------------------------------
    localparam signed [15:0] W1P =  16'sh0100; //  1.0
    localparam signed [15:0] W1N = -16'sh0100; // -1.0
    localparam signed [15:0] W2P =  16'sh0200; //  2.0
    localparam signed [15:0] W2N = -16'sh0200; // -2.0

    // -------------------------------------------------------------------
    // Line buffers holding the two previous input rows (shift-register
    // style, synthesizes to SRL16/FF chains, no BRAM required)
    // -------------------------------------------------------------------
    reg signed [15:0] line_buf_0 [0:IMG_W-1]; // most recently completed row
    reg signed [15:0] line_buf_1 [0:IMG_W-1]; // row before that

    // 3x3 sliding window. window[0][*] = row (r-2), window[2][*] = current row.
    // Column index 0 = oldest (left), 2 = newest (right) sample in that row.
    reg signed [15:0] window [0:2][0:2];

    integer i, j;

    // -------------------------------------------------------------------
    // Input position counters (drive window-validity and conv/pool timing)
    // -------------------------------------------------------------------
    reg [5:0] row_cnt, col_cnt; // 0..31
    wire window_valid = (row_cnt >= 2) && (col_cnt >= 2);
    wire signed [6:0] conv_row = row_cnt - 2; // 0..29 when window_valid
    wire signed [6:0] conv_col = col_cnt - 2; // 0..29 when window_valid

    // -------------------------------------------------------------------
    // Pipeline stage 2: convolution accumulators (Q8.8 x Q8.8 -> Q16.16,
    // summed in a wider accumulator to avoid intermediate overflow)
    // -------------------------------------------------------------------
    reg signed [31:0] mac_ch1, mac_ch2;
    reg                mac_valid;
    reg signed [6:0]   mac_row, mac_col;

    // -------------------------------------------------------------------
    // Pipeline stage 3: bias(=0) + ReLU, rounded and saturated back to Q8.8
    // -------------------------------------------------------------------
    reg signed [15:0] relu_ch1, relu_ch2;
    reg                relu_valid;
    reg signed [6:0]   relu_row, relu_col;

    // Overflow check: bits above the Q8.8 integer range must all match the
    // sign bit (mac_ch*[23]); if not, the value can't be represented in Q8.8.
    wire ovf1 = |(mac_ch1[31:24] ^ {8{mac_ch1[23]}});
    wire ovf2 = |(mac_ch2[31:24] ^ {8{mac_ch2[23]}});

    // Round-to-nearest using the top dropped fractional bit, then saturate.
    wire signed [15:0] rounded1 = mac_ch1[23:8] + mac_ch1[7];
    wire signed [15:0] rounded2 = mac_ch2[23:8] + mac_ch2[7];

    // -------------------------------------------------------------------
    // Pipeline stage 4: 2x2 max pooling (stride 2), one small row buffer
    // per channel holding the previous pooled row's horizontal maxima.
    // -------------------------------------------------------------------
    localparam integer POOL_W = IMG_W/2 - 1; // 15 for IMG_W=32 (30-wide conv output)
    reg signed [15:0] pool_row_buf_ch1 [0:POOL_W-1];
    reg signed [15:0] pool_row_buf_ch2 [0:POOL_W-1];

    reg signed [15:0] h_max_ch1, h_max_ch2; // holds first-of-pair value
    reg [4:0]          pool_col_idx;         // output column index within a pooled row
    reg signed [15:0] hmax1, hmax2;          // scratch: horizontal max for current pair

    // -------------------------------------------------------------------
    // Main sequential block
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            row_cnt <= 0; col_cnt <= 0;

            for (i = 0; i < IMG_W; i = i + 1) begin
                line_buf_0[i] <= 16'sd0;
                line_buf_1[i] <= 16'sd0;
            end
            for (i = 0; i < 3; i = i + 1)
                for (j = 0; j < 3; j = j + 1)
                    window[i][j] <= 16'sd0;

            mac_ch1 <= 32'sd0; mac_ch2 <= 32'sd0;
            mac_valid <= 1'b0; mac_row <= 7'sd0; mac_col <= 7'sd0;

            relu_ch1 <= 16'sd0; relu_ch2 <= 16'sd0;
            relu_valid <= 1'b0; relu_row <= 7'sd0; relu_col <= 7'sd0;

            h_max_ch1 <= 16'sd0; h_max_ch2 <= 16'sd0;
            hmax1 <= 16'sd0; hmax2 <= 16'sd0;
            pool_col_idx <= 5'd0;
            pool_out_ch1 <= 16'sd0; pool_out_ch2 <= 16'sd0;
            pool_valid <= 1'b0;

            for (i = 0; i < POOL_W; i = i + 1) begin
                pool_row_buf_ch1[i] <= 16'sd0;
                pool_row_buf_ch2[i] <= 16'sd0;
            end
        end else begin

            // ---------------- position counters ----------------
            if (frame_start) begin
                row_cnt <= 0;
                col_cnt <= 0;
            end else begin
                if (col_cnt == IMG_W-1) begin
                    col_cnt <= 0;
                    row_cnt <= row_cnt + 1;
                end else begin
                    col_cnt <= col_cnt + 1;
                end
            end

            // ---------------- line buffers (shift in new pixel) ----------------
            line_buf_0[0] <= pixel_in;
            for (i = 1; i < IMG_W; i = i + 1)
                line_buf_0[i] <= line_buf_0[i-1];

            line_buf_1[0] <= line_buf_0[IMG_W-1];
            for (i = 1; i < IMG_W; i = i + 1)
                line_buf_1[i] <= line_buf_1[i-1];

            // ---------------- 3x3 window update ----------------
            window[0][0] <= line_buf_1[IMG_W-1]; window[0][1] <= window[0][0]; window[0][2] <= window[0][1];
            window[1][0] <= line_buf_0[IMG_W-1]; window[1][1] <= window[1][0]; window[1][2] <= window[1][1];
            window[2][0] <= pixel_in;            window[2][1] <= window[2][0]; window[2][2] <= window[2][1];

            // ---------------- stage 2: convolution MAC ----------------
            // Gx: vertical-edge kernel
            //   -1  0  1
            //   -2  0  2
            //   -1  0  1
            mac_ch1 <= (window[0][0]*W1P) + (window[0][2]*W1N) +
           			   (window[1][0]*W2P) + (window[1][2]*W2N) +
           			   (window[2][0]*W1P) + (window[2][2]*W1N);

            // Gy: horizontal-edge kernel (top row negative, bottom row positive)
            //   -1 -2 -1
            //    0  0  0
            //    1  2  1
            mac_ch2 <= (window[0][0]*W1N) + (window[0][1]*W2N) + (window[0][2]*W1N) +
                       (window[2][0]*W1P) + (window[2][1]*W2P) + (window[2][2]*W1P);

            mac_valid <= window_valid;
            mac_row   <= conv_row;
            mac_col   <= conv_col;

            // ---------------- stage 3: bias(=0) + ReLU, round + saturate ----------------
            relu_ch1 <= (mac_ch1 <= 0) ? 16'sd0 :
                        ovf1            ? 16'sh7FFF :
                                          rounded1;

            relu_ch2 <= (mac_ch2 <= 0) ? 16'sd0 :
                        ovf2            ? 16'sh7FFF :
                                          rounded2;

            relu_valid <= mac_valid;
            relu_row   <= mac_row;
            relu_col   <= mac_col;

            // ---------------- stage 4: 2x2 max pooling ----------------
            pool_valid <= 1'b0; // default; overridden below on a real pooled output

            if (relu_valid) begin
                if (relu_col[0] == 1'b0) begin
                    // first sample of a horizontal pair: just latch it
                    h_max_ch1 <= relu_ch1;
                    h_max_ch2 <= relu_ch2;
                end else begin
                    // second sample: compute horizontal max, combine with
                    // buffered max from the row above (if this is an odd
                    // conv row), else just store it for next time.
                    hmax1 = (relu_ch1 > h_max_ch1) ? relu_ch1 : h_max_ch1;
                    hmax2 = (relu_ch2 > h_max_ch2) ? relu_ch2 : h_max_ch2;

                    if (relu_row[0] == 1'b0) begin
                        // first of a vertical pair: buffer it, no output yet
                        pool_row_buf_ch1[pool_col_idx] <= hmax1;
                        pool_row_buf_ch2[pool_col_idx] <= hmax2;
                    end else begin
                        // second of a vertical pair: emit the pooled pixel
                        pool_out_ch1 <= (hmax1 > pool_row_buf_ch1[pool_col_idx]) ?
                                         hmax1 : pool_row_buf_ch1[pool_col_idx];
                        pool_out_ch2 <= (hmax2 > pool_row_buf_ch2[pool_col_idx]) ?
                                         hmax2 : pool_row_buf_ch2[pool_col_idx];
                        pool_valid <= 1'b1;
                    end

                    if (pool_col_idx == POOL_W-1)
                        pool_col_idx <= 0;
                    else
                        pool_col_idx <= pool_col_idx + 1;
                end
            end

        end
    end

endmodule