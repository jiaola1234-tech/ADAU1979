`timescale 1 ns / 1 ps

module adau1979_i2s_rx #
(
    parameter integer SLOT_BITS = 32,
    parameter integer WORD_BITS = 24,
    parameter integer LR_POLARITY = 1,
    parameter integer I2S_DELAY = 1
)
(
    input  wire        s_axis_clk,
    input  wire        s_axis_rstn,
    input  wire        clear,

    input  wire        bclk,
    input  wire        lrclk,
    input  wire [3:0]  sdata,

    output reg         frame_valid,
    output reg [255:0] frame_data,
    output reg [31:0]  frame_count,
    output reg [31:0]  sync_error_count
);

    localparam integer BIT_COUNT_WIDTH = 6;
    localparam [BIT_COUNT_WIDTH-1:0] WORD_COUNT = WORD_BITS;
    localparam [BIT_COUNT_WIDTH-1:0] WORD_LAST = WORD_BITS - 1;
    localparam [BIT_COUNT_WIDTH-1:0] I2S_DELAY_COUNT = I2S_DELAY;

    (* ASYNC_REG = "TRUE" *) reg [2:0] bclk_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] lrclk_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sdata0_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sdata1_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sdata2_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sdata3_sync;

    wire bclk_rise = (bclk_sync[2:1] == 2'b01);
    wire lr_state  = lrclk_sync[2];
    wire lr_active = LR_POLARITY ? lr_state : ~lr_state;
    wire lr_edge   = (lrclk_sync[2] != lrclk_sync[1]);

    reg [BIT_COUNT_WIDTH-1:0] bit_idx;
    reg                       slot_idx;
    reg [WORD_BITS-1:0]       sh0;
    reg [WORD_BITS-1:0]       sh1;
    reg [WORD_BITS-1:0]       sh2;
    reg [WORD_BITS-1:0]       sh3;
    reg [31:0]                ch [0:7];
    reg [BIT_COUNT_WIDTH-1:0] delay_left;
    reg                       frame_seen;

    wire [WORD_BITS-1:0] next_sh0 = (bit_idx < WORD_BITS) ?
                                    {sh0[WORD_BITS-2:0], sdata0_sync[1]} : sh0;
    wire [WORD_BITS-1:0] next_sh1 = (bit_idx < WORD_BITS) ?
                                    {sh1[WORD_BITS-2:0], sdata1_sync[1]} : sh1;
    wire [WORD_BITS-1:0] next_sh2 = (bit_idx < WORD_BITS) ?
                                    {sh2[WORD_BITS-2:0], sdata2_sync[1]} : sh2;
    wire [WORD_BITS-1:0] next_sh3 = (bit_idx < WORD_BITS) ?
                                    {sh3[WORD_BITS-2:0], sdata3_sync[1]} : sh3;

    wire [31:0] next_w0 = {{(32-WORD_BITS){next_sh0[WORD_BITS-1]}}, next_sh0};
    wire [31:0] next_w1 = {{(32-WORD_BITS){next_sh1[WORD_BITS-1]}}, next_sh1};
    wire [31:0] next_w2 = {{(32-WORD_BITS){next_sh2[WORD_BITS-1]}}, next_sh2};
    wire [31:0] next_w3 = {{(32-WORD_BITS){next_sh3[WORD_BITS-1]}}, next_sh3};

    integer i;

    always @(posedge s_axis_clk) begin
        if (!s_axis_rstn) begin
            bclk_sync <= 3'b000;
            lrclk_sync <= 3'b000;
            sdata0_sync <= 2'b00;
            sdata1_sync <= 2'b00;
            sdata2_sync <= 2'b00;
            sdata3_sync <= 2'b00;
        end else begin
            bclk_sync <= {bclk_sync[1:0], bclk};
            lrclk_sync <= {lrclk_sync[1:0], lrclk};
            sdata0_sync <= {sdata0_sync[0], sdata[0]};
            sdata1_sync <= {sdata1_sync[0], sdata[1]};
            sdata2_sync <= {sdata2_sync[0], sdata[2]};
            sdata3_sync <= {sdata3_sync[0], sdata[3]};
        end
    end

    always @(posedge s_axis_clk) begin
        if (!s_axis_rstn) begin
            bit_idx <= {BIT_COUNT_WIDTH{1'b0}};
            slot_idx <= 1'b0;
            sh0 <= {WORD_BITS{1'b0}};
            sh1 <= {WORD_BITS{1'b0}};
            sh2 <= {WORD_BITS{1'b0}};
            sh3 <= {WORD_BITS{1'b0}};
            delay_left <= I2S_DELAY_COUNT;
            frame_seen <= 1'b0;
            frame_valid <= 1'b0;
            frame_data <= 256'd0;
            frame_count <= 32'd0;
            sync_error_count <= 32'd0;
            for (i = 0; i < 8; i = i + 1)
                ch[i] <= 32'd0;
        end else if (clear) begin
            // A new DMA packet must begin on a fresh LRCLK boundary.  Do
            // not allow the odd-channel half of the previous frame to be
            // combined with the next packet's even-channel half.
            bit_idx <= {BIT_COUNT_WIDTH{1'b0}};
            slot_idx <= 1'b0;
            sh0 <= {WORD_BITS{1'b0}};
            sh1 <= {WORD_BITS{1'b0}};
            sh2 <= {WORD_BITS{1'b0}};
            sh3 <= {WORD_BITS{1'b0}};
            delay_left <= I2S_DELAY_COUNT;
            frame_seen <= 1'b0;
            frame_valid <= 1'b0;
            frame_data <= 256'd0;
            for (i = 0; i < 8; i = i + 1)
                ch[i] <= 32'd0;
        end else begin
            frame_valid <= 1'b0;

            if (lr_edge) begin
                if (frame_seen && bit_idx < WORD_COUNT)
                    sync_error_count <= sync_error_count + 1'b1;
                bit_idx <= {BIT_COUNT_WIDTH{1'b0}};
                delay_left <= I2S_DELAY_COUNT;
                frame_seen <= 1'b1;
                slot_idx <= lr_active ? 1'b0 : 1'b1;
                sh0 <= {WORD_BITS{1'b0}};
                sh1 <= {WORD_BITS{1'b0}};
                sh2 <= {WORD_BITS{1'b0}};
                sh3 <= {WORD_BITS{1'b0}};
            end else if (bclk_rise) begin
                if (delay_left != 0) begin
                    delay_left <= delay_left - 1'b1;
                end else if (bit_idx < WORD_COUNT) begin
                    sh0 <= next_sh0;
                    sh1 <= next_sh1;
                    sh2 <= next_sh2;
                    sh3 <= next_sh3;

                    if (bit_idx == WORD_LAST) begin
                        if (slot_idx == 1'b0) begin
                            ch[0] <= next_w0;
                            ch[2] <= next_w1;
                            ch[4] <= next_w2;
                            ch[6] <= next_w3;
                        end else begin
                            ch[1] <= next_w0;
                            ch[3] <= next_w1;
                            ch[5] <= next_w2;
                            ch[7] <= next_w3;
                            frame_data <= {
                                next_w3, ch[6],
                                next_w2, ch[4],
                                next_w1, ch[2],
                                next_w0, ch[0]
                            };
                            frame_valid <= 1'b1;
                            frame_count <= frame_count + 1'b1;
                        end
                    end

                    bit_idx <= bit_idx + 1'b1;
                end
            end
        end
    end

endmodule
