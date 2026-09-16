`timescale 1 ns / 1 ps

module adau1979_capture_core #
(
    parameter integer SLOT_BITS = 32,
    parameter integer WORD_BITS = 24,
    parameter integer LR_POLARITY = 1,
    parameter integer I2S_DELAY = 1,
    parameter integer FIFO_ADDR_WIDTH = 10
)
(
    input  wire         clk,
    input  wire         rstn,

    input  wire         capture_enable,
    input  wire         init_done,
    input  wire [31:0]  sample_len,

    input  wire         bclk,
    input  wire         lrclk,
    input  wire [3:0]   sdata,

    output wire [255:0] m_axis_tdata,
    output wire [31:0]  m_axis_tkeep,
    output wire         m_axis_tlast,
    input  wire         m_axis_tready,
    output wire         m_axis_tvalid,

    output wire [31:0]  i2s_frame_count,
    output wire [31:0]  i2s_sync_error_count,
    output wire [31:0]  fifo_overflow_count,
    output wire [31:0]  fifo_level,
    output wire         fifo_full,
    output wire         packet_done,
    output wire [31:0]  packet_count
);

    wire rx_frame_valid;
    wire fifo_wr_en;
    wire [255:0] frame_data;
    reg capture_enable_d0;
    reg capture_enable_d1;
    reg init_done_d0;
    reg init_done_d1;
    reg capture_active_d;

    wire capture_active = capture_enable_d1 & init_done_d1;
    wire capture_start = capture_active & ~capture_active_d;

    always @(posedge clk) begin
        if (!rstn) begin
            capture_enable_d0 <= 1'b0;
            capture_enable_d1 <= 1'b0;
            init_done_d0 <= 1'b0;
            init_done_d1 <= 1'b0;
            capture_active_d <= 1'b0;
        end else begin
            capture_enable_d0 <= capture_enable;
            capture_enable_d1 <= capture_enable_d0;
            init_done_d0 <= init_done;
            init_done_d1 <= init_done_d0;
            capture_active_d <= capture_active;
        end
    end

    assign fifo_wr_en = rx_frame_valid & capture_active;

    adau1979_i2s_rx #(
        .SLOT_BITS(SLOT_BITS),
        .WORD_BITS(WORD_BITS),
        .LR_POLARITY(LR_POLARITY),
        .I2S_DELAY(I2S_DELAY)
    ) adau1979_i2s_rx_i (
        .s_axis_clk(clk),
        .s_axis_rstn(rstn),
        .clear(capture_start),
        .bclk(bclk),
        .lrclk(lrclk),
        .sdata(sdata),
        .frame_valid(rx_frame_valid),
        .frame_data(frame_data),
        .frame_count(i2s_frame_count),
        .sync_error_count(i2s_sync_error_count)
    );

    axis_fifo_256 #(
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) axis_fifo_256_i (
        .clk(clk),
        .rstn(rstn),
        .clear(capture_start),
        .wr_en(fifo_wr_en),
        .wr_data(frame_data),
        .full(fifo_full),
        .overflow_count(fifo_overflow_count),
        .level(fifo_level),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .packet_enable(capture_active),
        .packet_len(sample_len),
        .packet_done(packet_done),
        .packet_count(packet_count)
    );

endmodule
